// Lokalni server Evil Boće (plan §11): web app, cards.json i slike iz Drive foldera, deckovi.
// Sluša na localhostu i na Tailscale adresi, pa mobitel može slagati deckove (sve na tailnetu je moje).
// Postavke: server/config.local.json (nije u gitu) ili env EB_DRIVE, PORT, HOST.
import http from 'node:http';
import fs from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ttsPayload, mergeSteamUrls } from '../js/tts.js';
import { normalizeDb } from '../js/importer.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CONFIG_PATH = path.join(ROOT, 'server', 'config.local.json');

async function loadConfig() {
  let cfg = {};
  try {
    cfg = JSON.parse(await fs.readFile(CONFIG_PATH, 'utf8'));
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }
  const drive = process.env.EB_DRIVE || cfg.driveFolder;
  if (!drive) throw new Error(`Nema Drive foldera: upiši "driveFolder" u ${CONFIG_PATH} ili postavi EB_DRIVE`);
  return {
    drive: path.resolve(drive),
    port: Number(process.env.PORT || cfg.port || 5100),
    hosts: (process.env.HOST ? process.env.HOST.split(',') : cfg.hosts || ['127.0.0.1']).map(s => s.trim()).filter(Boolean),
  };
}

const cfg = await loadConfig();
const DECKS = path.join(cfg.drive, 'decks');
const STEAM_PATH = path.join(cfg.drive, 'data', 'steam-urls.json');
const SLUG_RE = /^[a-z0-9][a-z0-9-]{0,59}$/;
const LOGO_FILES = ['logo.png', 'logo.jpg', 'logo.jpeg', 'logo.webp'];
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
};

function send(res, status, body, type = 'application/json; charset=utf-8', cache = 'no-store') {
  const data = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': cache });
  res.end(data);
}

// Slike i sličice nose hash u imenu (ID.hash.png/jpg), pa nova verzija ima novo ime i smije se pamtiti zauvijek.
const IMMUTABLE = 'public, max-age=31536000, immutable';

const fail = (res, status, msg) => send(res, status, { error: msg });

// Datoteka unutar baze, ili null ako putanja izlazi iz nje.
function inside(base, rel) {
  const file = path.resolve(base, '.' + path.sep + rel);
  return file === base || file.startsWith(base + path.sep) ? file : null;
}

async function sendFile(res, file, cache) {
  try {
    const data = await fs.readFile(file);
    send(res, 200, data, TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream', cache);
  } catch (e) {
    if (e.code === 'ENOENT' || e.code === 'EISDIR') fail(res, 404, 'not found');
    else throw e;
  }
}

async function readJson(file) {
  try {
    return JSON.parse(await fs.readFile(file, 'utf8'));
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw e;
  }
}

// Zapis preko privremenog filea, da Drive ili čitač nikad ne vide pola filea.
async function writeJson(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  await fs.writeFile(tmp, JSON.stringify(value, null, 2) + '\n');
  await fs.rename(tmp, file);
}

async function findLogo() {
  for (const name of LOGO_FILES) {
    try {
      await fs.access(path.join(cfg.drive, name));
      return name;
    } catch {}
  }
  return null;
}

function readBody(req, limit = 256 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', c => {
      size += c.length;
      if (size > limit) {
        reject(Object.assign(new Error('request too large'), { status: 413 }));
        req.destroy();
      } else chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function deckSummary(slug, d) {
  return {
    slug,
    name: d.name,
    heroes: d.heroes ?? [],
    cards: d.cards ?? {},
    count: Object.values(d.cards ?? {}).reduce((s, n) => s + n, 0),
    catalogVersion: d.catalogVersion ?? 0,
    rev: d.rev ?? 0,
    updated: d.updated ?? null,
  };
}

async function api(req, res, parts) {
  const [, what, slug] = parts;
  if (what === 'info' && req.method === 'GET') {
    const db = await readJson(path.join(cfg.drive, 'data', 'cards.json'));
    return send(res, 200, { folder: path.basename(cfg.drive), version: db?.version ?? 0, cards: db?.cards.length ?? 0, logo: (await findLogo()) ? 'logo' : null });
  }
  // TTS (Sync karata): karte, heroji i bakugani u obliku koji global.lua samo primijeni.
  if (what === 'tts' && req.method === 'GET') {
    const db = normalizeDb(await readJson(path.join(cfg.drive, 'data', 'cards.json')));
    if (!db) return fail(res, 404, 'no data/cards.json');
    const steam = (await readJson(STEAM_PATH)) ?? {};
    const bakugani = (await readJson(path.join(cfg.drive, 'data', 'bakugani', 'catalog.json')))?.bakugani ?? [];
    return send(res, 200, ttsPayload(db, { steam, drivePath: cfg.drive, bakugani }));
  }
  // Nakon Cloud Manager "Upload All Loaded Files" TTS pošalje Steam URL-ove slika: { urls: { "OP1-008.a1b2c3d4": "https://…" } }.
  if (what === 'steam-urls' && req.method === 'POST') {
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      return fail(res, 400, 'invalid JSON');
    }
    const { steam, added } = mergeSteamUrls((await readJson(STEAM_PATH)) ?? {}, body?.urls);
    if (added) await writeJson(STEAM_PATH, steam);
    return send(res, 200, { added, total: Object.keys(steam).length });
  }
  if (what !== 'decks') return fail(res, 404, 'unknown API');

  if (!slug) {
    if (req.method !== 'GET') return fail(res, 405, 'GET only');
    let names = [];
    try {
      names = (await fs.readdir(DECKS)).filter(n => n.endsWith('.json'));
    } catch (e) {
      if (e.code !== 'ENOENT') throw e;
    }
    const list = [];
    for (const n of names) {
      const s = n.slice(0, -5);
      if (!SLUG_RE.test(s)) continue;
      try {
        const d = await readJson(path.join(DECKS, n));
        if (d) list.push(deckSummary(s, d));
      } catch {
        list.push({ slug: s, name: s, broken: true });
      }
    }
    list.sort((a, b) => String(b.updated).localeCompare(String(a.updated)));
    return send(res, 200, list);
  }

  if (!SLUG_RE.test(slug)) return fail(res, 400, 'invalid deck name');
  const file = path.join(DECKS, `${slug}.json`);
  const current = await readJson(file);

  if (req.method === 'GET') return current ? send(res, 200, { slug, ...current }) : fail(res, 404, 'no such deck');

  if (req.method === 'DELETE') {
    const base = Number(req.headers['if-match']);
    if (!current) return fail(res, 404, 'no such deck');
    if (Number.isFinite(base) && base !== (current.rev ?? 0)) return send(res, 409, { error: 'the deck was changed in the meantime', current: { slug, ...current } });
    await fs.rm(file);
    return send(res, 200, { ok: true });
  }

  if (req.method === 'PUT') {
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch (e) {
      return fail(res, e.status ?? 400, e.status ? e.message : 'body is not JSON');
    }
    if (typeof body.name !== 'string' || !body.name.trim() || !Array.isArray(body.heroes) || typeof body.cards !== 'object' || body.cards === null) {
      return fail(res, 400, 'deck must have name, heroes and cards');
    }
    // If-Match: rev koji je klijent zadnji vidio; 0 = novi deck. Bez zaglavlja se presnimava.
    const header = req.headers['if-match'];
    if (header !== undefined && Number(header) !== (current?.rev ?? 0)) {
      return send(res, 409, { error: 'the deck was changed in the meantime', current: current && { slug, ...current } });
    }
    const deck = {
      name: body.name.trim(),
      heroes: body.heroes.map(String),
      cards: Object.fromEntries(Object.entries(body.cards).filter(([, n]) => Number.isInteger(n) && n > 0)),
      catalogVersion: Number(body.catalogVersion) || 0,
      rev: (current?.rev ?? 0) + 1,
      updated: new Date().toISOString(),
    };
    await writeJson(file, deck);
    return send(res, 200, { slug, ...deck });
  }
  return fail(res, 405, 'unsupported method');
}

async function handle(req, res) {
  let rel;
  try {
    rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  } catch {
    return fail(res, 400, 'invalid URL');
  }
  const parts = rel.split('/').filter(Boolean);
  if (parts[0] === 'api') return api(req, res, parts);
  if (req.method !== 'GET' && req.method !== 'HEAD') return fail(res, 405, 'GET only');

  // Podaci iz Drive foldera: samo data/ (cards.json, slike) i logo.
  if (parts[0] === 'data') {
    const file = inside(path.join(cfg.drive, 'data'), parts.slice(1).join('/'));
    const hashed = ['images', 'thumbs', 'large'].includes(parts[1]) && /\.[0-9a-f]{8}\.(png|jpg)$/i.test(rel);
    return file ? sendFile(res, file, hashed ? IMMUTABLE : 'no-store') : fail(res, 403, 'forbidden');
  }
  // Modeli za alate (tools/lama.onnx, 208 MB): šalju se u komadima, preglednik ih smije pamtiti dan.
  if (parts[0] === 'tools') {
    const file = inside(path.join(cfg.drive, 'tools'), parts.slice(1).join('/'));
    if (!file) return fail(res, 403, 'forbidden');
    try {
      const st = await fs.stat(file);
      if (!st.isFile()) return fail(res, 404, 'not found');
      res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Length': st.size, 'Cache-Control': 'max-age=86400' });
      if (req.method === 'HEAD') return res.end();
      return createReadStream(file).pipe(res);
    } catch (e) {
      if (e.code === 'ENOENT') return fail(res, 404, 'not found');
      throw e;
    }
  }
  if (rel === '/logo') {
    const name = await findLogo();
    return name ? sendFile(res, path.join(cfg.drive, name)) : fail(res, 404, 'no logo');
  }

  // Web app iz repoa. server/ i .git/ se ne poslužuju; docs/ (privatno, testna stranica) samo ovom računalu.
  const top = (parts[0] ?? '').toLowerCase();
  const local = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
  if (['server', '.git', 'node_modules'].includes(top) || (top === 'docs' && !local)) return fail(res, 404, 'not found');
  const file = inside(ROOT, rel.endsWith('/') ? rel + 'index.html' : rel);
  return file ? sendFile(res, file) : fail(res, 403, 'forbidden');
}

// Tailscale adresa pri prijavi u Windows zna kasniti: adresa koje još nema pokušava se ponovo svakih 30 s.
function listen(host, retry = false) {
  http
    .createServer((req, res) => handle(req, res).catch(e => {
      console.error(e);
      if (!res.headersSent) fail(res, 500, 'server error');
    }))
    .on('error', e => {
      if (!retry) console.error(`${host}:${cfg.port}: ${e.message}`);
      if (e.code === 'EADDRNOTAVAIL') setTimeout(() => listen(host, true), 30_000);
    })
    .listen(cfg.port, host, () => console.log(`Evil Boće server: http://${host === '127.0.0.1' ? 'localhost' : host}:${cfg.port}/  (folder ${cfg.drive})`));
}

for (const host of cfg.hosts) listen(host);

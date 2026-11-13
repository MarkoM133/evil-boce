// Pisanje u zajednički folder preko servera (Marko 2026-11-05): mobitel nema pristup folderu iz preglednika,
// pa Card Studio na mobitelu sprema nacrte, fx, wishlist i art preko ovog servera na Markovom računalu.
// Samo popis putanja ispod: nikad cards.json, slike karata ni ništa što radi Publish (to ostaje na računalu).
import fs from 'node:fs/promises';
import path from 'node:path';

const NAME = '[A-Za-z0-9][A-Za-z0-9._-]{0,120}';
const IMG = '\\.(?:png|jpe?g|webp)';

// Što smije pisati (PUT): nacrti i bilješke editora, lockovi, Claude zahtjevi (fx i Check text), wishlist, art i amblemi,
// setovi (sets.json i slike setova), vodič za tekst.
const WRITE = [
  /^data\/editor\/(?:drafts|notes|history|text-guide)\.json$/,
  new RegExp(`^data/locks/${NAME}\\.json$`),
  new RegExp(`^data/fx-requests/${NAME}\\.json$`),
  new RegExp(`^data/text-requests/${NAME}\\.json$`),
  /^data\/fx-wishlist\.json$/,
  new RegExp(`^data/art/(?:emblems/)?${NAME}${IMG}$`),
  /^data\/sets\/sets\.json$/,
  /^data\/card-frames\/[a-z0-9-]{1,30}\/layout\.json$/,
  new RegExp(`^data/sets/[A-Za-z0-9-]{1,20}/${NAME}${IMG}$`),
];
// Što smije brisati: samo lockove (editor ih pušta kad zatvoriš kartu).
const REMOVE = [new RegExp(`^data/locks/${NAME}\\.json$`)];
// Koje foldere smije izlistati.
const LIST = ['data/locks'];

// Putanja iz zahtjeva: relativna, s /, bez .. i bez praznih dijelova; inače null.
export function cleanPath(p) {
  if (typeof p !== 'string' || !p || p.length > 300) return null;
  if (p.includes('\\') || p.startsWith('/') || p.includes('\0')) return null;
  const parts = p.split('/');
  if (parts.some(x => !x || x === '.' || x === '..')) return null;
  return parts.join('/');
}

export const canWrite = p => !!p && WRITE.some(r => r.test(p));
export const canRemove = p => !!p && REMOVE.some(r => r.test(p));
export const canList = p => !!p && LIST.includes(p);

const LIMIT = { json: 8 * 1024 * 1024, image: 40 * 1024 * 1024 };

function readBytes(req, limit) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', c => {
      size += c.length;
      if (size > limit) {
        reject(Object.assign(new Error('file too large'), { status: 413 }));
        req.destroy();
      } else chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

// Zapis preko privremenog filea i preimenovanja: Syncthing i drugi čitač nikad ne vide pola filea, a pukla
// veza s mobitela ostavi stari file netaknut. Syncthing zna file na tren zaključati, pa se preimenovanje ponovi.
export async function atomicWrite(file, data) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tmp, data);
  for (let i = 0; ; i++) {
    try {
      await fs.rename(tmp, file);
      return;
    } catch (e) {
      if (i >= 8 || !['EPERM', 'EBUSY', 'EACCES'].includes(e.code)) {
        await fs.rm(tmp, { force: true });
        throw e;
      }
      await new Promise(r => setTimeout(r, 60 * (i + 1)));
    }
  }
}

// api/fs?path=…  PUT (tijelo = sadržaj), DELETE; api/fs?list=…  GET imena fileova.
export async function handleFs(req, res, { drive, enabled, send, fail }) {
  if (!enabled) return fail(res, 403, 'saving through the server is off on this computer');
  const url = new URL(req.url, 'http://x');
  if (req.method === 'GET' && url.searchParams.has('list')) {
    const dir = cleanPath(url.searchParams.get('list'));
    if (!canList(dir)) return fail(res, 403, 'not allowed');
    try {
      const names = [];
      for (const d of await fs.readdir(path.join(drive, dir), { withFileTypes: true })) if (d.isFile() && !d.name.endsWith('.tmp')) names.push(d.name);
      return send(res, 200, names);
    } catch (e) {
      if (e.code === 'ENOENT') return send(res, 200, []);
      throw e;
    }
  }
  const p = cleanPath(url.searchParams.get('path'));
  if (!p) return fail(res, 400, 'bad path');
  const file = path.join(drive, ...p.split('/'));
  if (req.method === 'PUT') {
    if (!canWrite(p)) return fail(res, 403, `${p} can't be saved from here (Publish and card images stay on the computer)`);
    let data;
    try {
      data = await readBytes(req, p.endsWith('.json') ? LIMIT.json : LIMIT.image);
    } catch (e) {
      return fail(res, e.status ?? 400, e.message);
    }
    // An empty body is not JSON either (an empty request file had the fx worker fail on it every few seconds).
    if (p.endsWith('.json')) {
      try {
        JSON.parse(data.toString('utf8'));
      } catch {
        return fail(res, 400, 'not JSON');
      }
    }
    await atomicWrite(file, data);
    return send(res, 200, { ok: true });
  }
  if (req.method === 'DELETE') {
    if (!canRemove(p)) return fail(res, 403, 'not allowed');
    await fs.rm(file, { force: true });
    return send(res, 200, { ok: true });
  }
  return fail(res, 405, 'unsupported method');
}

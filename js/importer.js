// Uvoz exporta u cards.json: spajanje XML-ova i PNG-ova, usporedba s bazom, provjere i Objavi.
// Bez I/O: pozivatelj (app ili test) skupi fileove i zapiše rezultat.
import { parseCardEngineXml, CODE_RE } from './parse.js';

// Polja koja dolaze iz Card Enginea (§5). App ih ne mijenja.
export const CE_FIELDS = ['name', 'type', 'color', 'cost', 'evo', 'hero', 'stats', 'bonus', 'values', 'traits', 'text'];
// Polja koja se uređuju samo u appu. Ponovni uvoz ih ne dira.
export const APP_FIELDS = ['wt', 'bakugan', 'bakuganShape', 'bakuganColor', 'deleted'];
const FIELD_ORDER = ['id', 'name', 'type', 'color', 'cost', 'evo', 'hero', 'stats', 'wt', 'bonus', 'values', 'traits', 'text', 'bakugan', 'bakuganShape', 'bakuganColor', 'image', 'imageHash', 'sprite', 'spriteHash', 'rev', 'deleted'];

export const DEFAULT_WT = 2;

// Sprite = slika figurine (otvoreni bakugan u TTS-u): "OP1-001 Luffy Sprite.png" ili "Luffy Sprite.png".
const SPRITE_RE = /\s+sprite$/i;
const SPRITE_TYPES = ['Character', 'Evolution'];
const normName = s => s.replace(/\s*,\s*/g, ', ').trim();

export function emptyDb() {
  return { version: 0, updated: null, cards: [] };
}

export function ordered(card) {
  const out = {};
  for (const k of FIELD_ORDER) if (card[k] !== undefined) out[k] = card[k];
  for (const k of Object.keys(card)) if (!(k in out) && card[k] !== undefined) out[k] = card[k];
  return out;
}

export async function sha256Hex(bytes) {
  const buf = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
}

export async function imageHashOf(bytes) {
  return (await sha256Hex(bytes)).slice(0, 8);
}

function same(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function baseName(path) {
  return path.split('/').pop();
}

// xmlFiles: [{ path, text, lastModified }]
// pngFiles: [{ path, lastModified, getBytes: () => Promise<Uint8Array> }]
// db: sadržaj cards.json
export async function analyzeExport({ xmlFiles, pngFiles, db }) {
  const errors = [];
  const warnings = [];
  const infos = [];
  const add = (list, id, msg) => list.push({ id, msg });

  // 1. Karte iz svih XML-ova; ista karta u više fileova -> vrijedi noviji file.
  const picked = new Map();
  const byAge = [...xmlFiles].sort((a, b) => a.lastModified - b.lastModified || a.path.localeCompare(b.path));
  let tokenCount = 0;
  for (const f of byAge) {
    let parsed;
    try {
      parsed = parseCardEngineXml(f.text);
    } catch (e) {
      add(errors, null, `${f.path}: ${e.message}`);
      continue;
    }
    const seenHere = new Set();
    for (const p of parsed) {
      if (p.skip) { tokenCount++; continue; }
      if (seenHere.has(p.code)) add(errors, p.code, `${f.path}: kod je dvaput u istom XML-u`);
      seenHere.add(p.code);
      const prev = picked.get(p.code);
      if (prev && !same(prev.card, p.card)) {
        add(warnings, p.code, `karta je u više XML-ova s različitim podacima; vrijedi noviji ${f.path} (ne ${prev.file})`);
      } else if (prev) {
        add(infos, p.code, `karta je i u ${prev.file} i u ${f.path} (isti podaci)`);
      }
      picked.set(p.code, { ...p, file: f.path });
    }
  }
  if (tokenCount) add(infos, null, `preskočeno ${tokenCount} karata bez koda (tokeni)`);

  // 2. PNG: "OP1-012 Sword Slash.png" (ili "OP1-012.png") ide karti po kodu, "Sword Slash.png" po imenu.
  // Isti PNG u više podfoldera -> noviji.
  // "... Sprite.png" je sprite (figurina u TTS-u), ne slika karte; po imenu se zarez s razmakom ili bez ne razlikuje.
  const pngByCode = new Map();
  const pngByName = new Map();
  const spriteByCode = new Map();
  const spriteByName = new Map();
  for (const p of [...pngFiles].sort((a, b) => a.lastModified - b.lastModified || a.path.localeCompare(b.path))) {
    const name = baseName(p.path).replace(/\.png$/i, '');
    const sprite = SPRITE_RE.test(name);
    const rest = sprite ? name.replace(SPRITE_RE, '') : name;
    const code = rest.split(/\s+/)[0];
    const [map, key] = CODE_RE.test(code)
      ? [sprite ? spriteByCode : pngByCode, code]
      : sprite ? [spriteByName, normName(rest)] : [pngByName, rest];
    if (map.has(key)) add(infos, null, `PNG "${name}" postoji više puta; vrijedi noviji ${p.path}`);
    map.set(key, p);
  }
  const pngName = card => `"${card.id} ${card.name}.png"`;

  // 3. Usporedba s bazom.
  const oldById = new Map(db.cards.map(c => [c.id, c]));
  const entries = [];
  const usedPngs = new Set();
  for (const p of picked.values()) {
    for (const pr of p.problems) add(pr.level === 'error' ? errors : warnings, p.code, pr.msg);
    const old = oldById.get(p.code);
    const byCode = pngByCode.get(p.code);
    const png = byCode ?? pngByName.get(p.card.name);
    let imageHash = null;
    if (png) {
      usedPngs.add(png);
      imageHash = await imageHashOf(await png.getBytes());
    } else if (!old?.imageHash) {
      add(errors, p.code, `nova karta bez PNG-a ${pngName(p.card)} (ili "${p.card.name}.png")`);
    }
    const diffs = old ? CE_FIELDS.filter(k => !same(old[k], p.card[k])) : [];
    const imageChanged = !!old && !!imageHash && imageHash !== old.imageHash;
    const status = !old ? 'new' : diffs.length || imageChanged ? 'changed' : 'same';
    // PNG je nacrtana karta: promijenjeni podaci, a ista slika znači da je slika vjerojatno stara.
    const staleImage = diffs.length > 0 && !imageChanged;
    if (staleImage) add(warnings, p.code, `promijenjeno (${diffs.join(', ')}), a ${png ? 'PNG je isti kao prije' : 'nema PNG-a, pa ostaje stara slika'}; slika je možda stara, treba li novi ${pngName(p.card)}?`);
    entries.push({ id: p.code, status, card: p.card, old, diffs, imageChanged, staleImage, imageHash, png, pngByName: !!png && !byCode, file: p.file });
  }

  // PNG bez XML-a: nova slika postojeće karte iz baze, po kodu ili po imenu.
  const pickedIds = new Set(picked.keys());
  const dbByName = new Map();
  for (const c of db.cards) dbByName.set(c.name, [...(dbByName.get(c.name) ?? []), c]);
  const pngOnly = [
    ...[...pngByCode].map(([code, png]) => [png, oldById.get(code) ? [oldById.get(code)] : []]),
    ...[...pngByName].map(([name, png]) => [png, dbByName.get(name) ?? []]),
  ];
  for (const [png, found] of pngOnly) {
    if (usedPngs.has(png) || !found.length) continue;
    const live = found.filter(c => !c.deleted);
    const candidates = live.length ? live : found;
    if (candidates.length > 1) {
      usedPngs.add(png);
      add(errors, null, `${png.path}: isto ime imaju ${candidates.map(c => c.id).join(' i ')}; PNG mora počinjati kodom, npr. ${pngName(candidates[0])}`);
      continue;
    }
    const old = candidates[0];
    if (pickedIds.has(old.id)) continue;
    usedPngs.add(png);
    const imageHash = await imageHashOf(await png.getBytes());
    const imageChanged = imageHash !== old.imageHash;
    const card = { id: old.id };
    for (const k of CE_FIELDS) if (old[k] !== undefined) card[k] = old[k];
    entries.push({ id: old.id, status: imageChanged ? 'changed' : 'same', card, old, diffs: [], imageChanged, staleImage: false, imageHash, png, file: png.path });
  }

  // Sprite: samo heroji i Evolution karte. Ide uz kartu iz XML-a ili uz postojeću kartu iz baze.
  const pool = new Map(db.cards.map(c => [c.id, c]));
  for (const p of picked.values()) pool.set(p.code, { ...pool.get(p.code), ...p.card });
  const poolByName = new Map();
  for (const c of pool.values()) poolByName.set(normName(c.name), [...(poolByName.get(normName(c.name)) ?? []), c]);
  const entryById = new Map(entries.map(e => [e.id, e]));
  for (const [sprite, found] of [
    ...[...spriteByCode].map(([code, s]) => [s, pool.has(code) ? [pool.get(code)] : []]),
    ...[...spriteByName].map(([name, s]) => [s, poolByName.get(name) ?? []]),
  ]) {
    if (!found.length) continue;
    usedPngs.add(sprite);
    const live = found.filter(c => !c.deleted);
    const candidates = live.length ? live : found;
    if (candidates.length > 1) {
      add(errors, null, `${sprite.path}: isto ime imaju ${candidates.map(c => c.id).join(' i ')}; sprite mora počinjati kodom, npr. "${candidates[0].id} ${candidates[0].name} Sprite.png"`);
      continue;
    }
    const target = candidates[0];
    if (!SPRITE_TYPES.includes(target.type)) {
      add(warnings, target.id, `${sprite.path}: sprite je samo za heroje i Evolution karte (${target.name} je ${target.type}); preskočen`);
      continue;
    }
    const old = oldById.get(target.id);
    let e = entryById.get(target.id);
    if (!e) {
      const card = { id: old.id };
      for (const k of CE_FIELDS) if (old[k] !== undefined) card[k] = old[k];
      e = { id: old.id, status: 'same', card, old, diffs: [], imageChanged: false, staleImage: false, imageHash: null, png: null, file: sprite.path };
      entries.push(e);
      entryById.set(e.id, e);
    }
    e.spritePng = sprite;
    e.spriteHash = await imageHashOf(await sprite.getBytes());
    e.spriteChanged = !!old && e.spriteHash !== old.spriteHash;
    if (e.status === 'same' && e.spriteChanged) e.status = 'changed';
  }
  entries.sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));

  const skipped = [...pngByCode.values(), ...pngByName.values(), ...spriteByCode.values(), ...spriteByName.values()]
    .filter(png => !usedPngs.has(png)).map(png => baseName(png.path));
  if (skipped.length) add(infos, null, `preskočeno ${skipped.length} PNG-ova koji nisu karte s kodom: ${skipped.join(', ')}`);

  // 4. Provjere na bazi kakva će biti nakon Objave.
  // Heroj mora imati jedinstveno ime (TTS ga veže uz bakugana po imenu, Evolution ga nalazi po imenu).
  // Ostale karte smiju dijeliti ime, ali tada PNG mora počinjati kodom.
  const final = mergedCards(db, entries);
  const live = final.filter(c => !c.deleted);
  const byName = new Map();
  for (const c of live) byName.set(c.name, [...(byName.get(c.name) ?? []), c]);
  for (const [name, list] of byName) {
    if (list.length < 2) continue;
    const ids = list.map(c => c.id).join(', ');
    if (list.some(c => c.type === 'Character')) add(errors, list[0].id, `ime "${name}" imaju ${ids}; heroj mora imati jedinstveno ime`);
    else add(warnings, list[0].id, `isto ime "${name}" imaju ${ids}; to je dopušteno, ali PNG-ovi moraju počinjati kodom`);
  }
  for (const e of entries) {
    if (e.pngByName && byName.get(e.card.name)?.length > 1) add(errors, e.id, `PNG "${e.card.name}.png" ne zna se kojoj karti pripada (isto ime ima više karata); preimenuj ga u ${pngName(e.card)}`);
  }
  const heroes = new Set(live.filter(c => c.type === 'Character').map(c => c.name));
  for (const c of live) {
    if (c.type === 'Evolution' && !heroes.has(c.hero)) add(errors, c.id, `Evolution: heroj "${c.hero}" ne postoji`);
    if (c.type === 'Character' && !c.bakugan) add(warnings, c.id, 'heroj bez bakugana');
  }

  return { entries, errors, warnings, infos };
}

// Kako će izgledati karte nakon Objave (bez slika i reva, samo za provjere).
function mergedCards(db, entries) {
  const byId = new Map(db.cards.map(c => [c.id, c]));
  for (const e of entries) byId.set(e.id, withAppFields(e.card, e.old));
  return [...byId.values()];
}

function withAppFields(ce, old) {
  const card = { id: ce.id, ...ce };
  if (ce.type === 'Character') {
    card.wt = old?.wt ?? DEFAULT_WT;
    card.bakugan = old?.bakugan ?? ce.name;
  }
  // Ostala app polja (npr. oblik i boja bakugana) ostaju kakva su bila.
  for (const k of APP_FIELDS) if (card[k] === undefined && old?.[k] !== undefined) card[k] = old[k];
  card.deleted = old?.deleted ?? false;
  return card;
}

// Rezultat: novi cards.json + slike koje treba zapisati.
// Karte koje nisu u exportu ostaju kakve jesu.
export function buildPublish(db, analysis, now = new Date()) {
  const writes = [];
  const touched = new Map();
  for (const e of analysis.entries) {
    if (e.status === 'same') continue;
    const card = withAppFields(e.card, e.old);
    if (e.imageHash && (!e.old || e.imageChanged)) {
      card.image = `images/${e.id}.${e.imageHash}.png`;
      card.imageHash = e.imageHash;
      writes.push({ path: `data/${card.image}`, png: e.png });
    } else {
      card.image = e.old?.image ?? null;
      card.imageHash = e.old?.imageHash ?? null;
    }
    if (e.spriteHash && (!e.old || e.spriteChanged)) {
      card.sprite = `sprites/${e.id}.${e.spriteHash}.png`;
      card.spriteHash = e.spriteHash;
      writes.push({ path: `data/${card.sprite}`, png: e.spritePng });
    } else if (e.old?.sprite) {
      card.sprite = e.old.sprite;
      card.spriteHash = e.old.spriteHash;
    }
    card.rev = (e.old?.rev ?? 0) + 1;
    touched.set(e.id, ordered(card));
  }
  if (!touched.size) return { db, writes, changed: 0 };
  const cards = db.cards.map(c => touched.get(c.id) ?? c);
  for (const [id, c] of touched) if (!db.cards.some(o => o.id === id)) cards.push(c);
  cards.sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  return {
    db: { version: db.version + 1, updated: now.toISOString(), cards },
    writes,
    changed: touched.size,
  };
}

// Izmjena app polja (wt, bakugan, deleted). edits: { [id]: { wt?, bakugan?, deleted? } }
export function applyAppEdits(db, edits, now = new Date()) {
  let changed = 0;
  const cards = db.cards.map(c => {
    const e = edits[c.id];
    if (!e) return c;
    const next = { ...c };
    for (const k of APP_FIELDS) if (k in e) next[k] = e[k];
    if (same(next, c)) return c;
    changed++;
    next.rev = (c.rev ?? 0) + 1;
    return ordered(next);
  });
  if (!changed) return { db, changed };
  return { db: { version: db.version + 1, updated: now.toISOString(), cards }, changed };
}

// Stare verzije slika (data/images/ID.hash.png) koje se smiju obrisati: samo kad za trenutnu
// verziju te karte već postoji Steam URL (§3), da master u TTS-u ne ostane bez filea.
export function obsoleteImages(db, imageFiles, steamUrls) {
  const current = new Map(db.cards.map(c => [c.id, c.imageHash]));
  return imageFiles.filter(f => {
    const m = /^(.+)\.([0-9a-f]+)\.png$/i.exec(f);
    if (!m) return false;
    const [, id, hash] = m;
    const cur = current.get(id);
    return cur && hash !== cur && !!steamUrls[`${id}.${cur}`];
  });
}

// Povijest promjena (data/changelog.json): jedan zapis po verziji baze, piše ga app pri Objavi i spremanju app polja.
// { entries: [{ version, date, cards: [{ id, name, kind: new|changed|deleted|restored, fields: [...], image }] }] }
export const CHANGELOG_PATH = 'data/changelog.json';

export function emptyChangelog() {
  return { entries: [] };
}

// Razlika dvije verzije baze, za zapis u povijest.
export function changelogEntry(oldDb, newDb) {
  const oldById = new Map(oldDb.cards.map(c => [c.id, c]));
  const cards = [];
  for (const c of newDb.cards) {
    const o = oldById.get(c.id);
    if (!o) {
      cards.push({ id: c.id, name: c.name, kind: 'new', fields: [], image: false });
      continue;
    }
    const fields = [...CE_FIELDS, 'wt', 'bakugan', 'bakuganShape', 'bakuganColor'].filter(k => !same(o[k], c[k]));
    const image = o.imageHash !== c.imageHash;
    const sprite = o.spriteHash !== c.spriteHash;
    const kind = !o.deleted && c.deleted ? 'deleted' : o.deleted && !c.deleted ? 'restored' : 'changed';
    if (fields.length || image || sprite || kind !== 'changed') cards.push({ id: c.id, name: c.name, kind, fields, image, ...(sprite ? { sprite } : {}) });
  }
  return { version: newDb.version, date: newDb.updated, cards };
}

export function appendChangelog(log, entry) {
  if (!entry.cards.length) return log;
  return { entries: [...log.entries.filter(e => e.version !== entry.version), entry].sort((a, b) => a.version - b.version) };
}

// Što se promijenilo nakon verzije `since`: id -> [{ version, kind, fields, image }], od starijih prema novijima.
export function changesSince(log, since) {
  const out = new Map();
  for (const e of log.entries) {
    if (e.version <= since) continue;
    for (const c of e.cards) {
      if (!out.has(c.id)) out.set(c.id, []);
      out.get(c.id).push({ version: e.version, kind: c.kind, fields: c.fields, image: c.image });
    }
  }
  return out;
}

// Kratak opis promjene karte: "values, slika", "nova", "maknuta".
const FIELD_LABELS = { bakuganShape: 'oblik bakugana', bakuganColor: 'boja bakugana' };

export function describeChange(c) {
  if (c.kind === 'new') return 'nova';
  if (c.kind === 'deleted') return 'maknuta';
  if (c.kind === 'restored') return 'vraćena';
  return [...c.fields.map(f => FIELD_LABELS[f] ?? f), ...(c.image ? ['slika'] : []), ...(c.sprite ? ['sprite'] : [])].join(', ');
}

// export/ je sanduče: nakon Objave pročitani fileovi idu u export/objavljeno/<datum vrijeme>/, a Uvoz arhivu preskače.
export const ARCHIVE_DIR = 'export/objavljeno';

export function archiveFolder(now = new Date()) {
  const p = n => String(n).padStart(2, '0');
  return `${ARCHIVE_DIR}/${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())} ${p(now.getHours())}.${p(now.getMinutes())}`;
}

// export/Nove/Luffy.png -> export/objavljeno/2026-10-23 21.10/Nove/Luffy.png
export function archivePath(path, folder) {
  return `${folder}/${path.replace(/^export\//, '')}`;
}

// PNG-ovi iz exporta čiji je sadržaj nakon Objave u data/ (slika karte ili sprite, isti hash): u arhivi bi bili
// duplikat, pa se brišu. PNG koji nije uz kartu (npr. token) ostaje u arhivi.
export function publishedPngPaths(analysis) {
  const out = new Set();
  for (const e of analysis.entries) {
    if (e.png) out.add(e.png.path);
    if (e.spritePng) out.add(e.spritePng.path);
  }
  return out;
}

// Umanjene slike, ime ide uz verziju slike (ID.hash.jpg): male sličice za trake, bazen i galeriju,
// velike za prikaz preko cijelog ekrana i detalj (originalni PNG ima ~2,6 MB, ovaj ~250 KB).
export const THUMB_WIDTH = 300;
export const SIZES = [{ dir: 'thumbs', width: THUMB_WIDTH }, { dir: 'large', width: 1000 }];

export function thumbName(card) {
  return card.imageHash ? `${card.id}.${card.imageHash}.jpg` : null;
}

// Koje sličice treba napraviti i koje su višak (TTS ih ne koristi, pa se stare brišu odmah).
export function thumbPlan(db, thumbFiles) {
  const have = new Set(thumbFiles);
  const wanted = new Set(db.cards.map(thumbName).filter(Boolean));
  return {
    missing: db.cards.filter(c => c.image && !have.has(thumbName(c))),
    extra: thumbFiles.filter(f => /\.jpg$/i.test(f) && !wanted.has(f)),
  };
}

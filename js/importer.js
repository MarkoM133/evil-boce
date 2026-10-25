// Uvoz exporta u cards.json: spajanje XML-ova i PNG-ova, usporedba s bazom, provjere i Objavi.
// Bez I/O: pozivatelj (app ili test) skupi fileove i zapiše rezultat.
import { parseCardEngineXml, CODE_RE, ROT_RE, terrainFromText } from './parse.js';

// Polja koja dolaze iz Card Enginea (§5). App ih ne mijenja.
export const CE_FIELDS = ['name', 'type', 'color', 'cost', 'evo', 'hero', 'stats', 'bonus', 'values', 'traits', 'text', 'abilityNames', 'landscape'];
// Polja koja se uređuju samo u appu. Ponovni uvoz ih ne dira.
// Za igru: fx (efekt karte za igru), fxStatus ('ok' | 'check' | ''), terrain (Stage; iz retka "Terrain:" ili ručno),
// figure (put do .glb, npr. figures/OP1-001.glb), ballColor i ballColor2 (kuglica: tijelo i akcent), heroSfx.
// bakugan* su stara TTS polja: ostaju u starim zapisima (igra ih čita kao zadanu boju kuglice), app ih više ne nudi.
export const APP_FIELDS = ['wt', 'bakugan', 'bakuganShape', 'bakuganColor', 'bakuganColor2', 'fx', 'fxStatus', 'terrain', 'figure', 'ballColor', 'ballColor2', 'heroSfx', 'deleted'];
// Izgled: ne mijenja igru, pa ne diže verziju baze (sprite je isto izgled, ali dolazi iz exporta).
// fxStatus je samo oznaka za pregled, pa ni on ne diže verziju.
export const LOOK_FIELDS = ['bakugan', 'bakuganShape', 'bakuganColor', 'bakuganColor2', 'fxStatus', 'figure', 'ballColor', 'ballColor2', 'heroSfx'];
const FIELD_ORDER = ['id', 'name', 'type', 'color', 'cost', 'evo', 'hero', 'stats', 'wt', 'bonus', 'values', 'traits', 'text', 'abilityNames', 'terrain', 'fx', 'fxStatus', 'landscape', 'bakugan', 'bakuganShape', 'bakuganColor', 'bakuganColor2', 'ballColor', 'ballColor2', 'figure', 'heroSfx', 'image', 'imageHash', 'imageRot', 'imageRotHash', 'sprite', 'spriteHash', 'rev', 'deleted'];

export const DEFAULT_WT = 2;

// Sprite = slika figurine (heroj iz otvorene kuglice u igri): "OP1-001 Luffy Sprite.png" ili "Luffy Sprite.png".
const SPRITE_RE = /\s+sprite$/i;
const SPRITE_TYPES = ['Hero', 'Evolution'];
const normName = s => s.replace(/\s*,\s*/g, ', ').trim();

export function emptyDb() {
  return { version: 0, updated: null, cards: [] };
}

// Baza kako je app i igra čitaju: tip Character (do 2026-10-24) je Hero. Datoteka se ne mijenja dok se ne objavi.
export function normalizeDb(db) {
  if (!db?.cards?.some(c => c.type === 'Character')) return db;
  return { ...db, cards: db.cards.map(c => (c.type === 'Character' ? { ...c, type: 'Hero' } : c)) };
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
  // Rotirana verzija ("… (rot)") je ista karta: podaci se uzmu iz nje samo ako landscape verzije nema.
  const picked = new Map();
  const rotOnly = new Map();
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
      if (p.skip && p.coreWithoutCode) { add(errors, null, `${f.path}: Core card "${p.name}" has no code; Core cards need one (CR1-001)`); continue; }
      if (p.skip) { tokenCount++; continue; }
      if (p.variant === 'rot') { rotOnly.set(p.code, { ...p, file: f.path }); continue; }
      if (seenHere.has(p.code)) add(errors, p.code, `${f.path}: code appears twice in the same XML`);
      seenHere.add(p.code);
      const prev = picked.get(p.code);
      if (prev && !same(prev.card, p.card)) {
        add(warnings, p.code, `card is in several XMLs with different data; using the newer ${f.path} (not ${prev.file})`);
      } else if (prev) {
        add(infos, p.code, `card is in both ${prev.file} and ${f.path} (same data)`);
      }
      picked.set(p.code, { ...p, file: f.path });
    }
  }
  for (const [code, p] of rotOnly) {
    const main = picked.get(code);
    if (!main) picked.set(code, p);
    else if (!same(main.card, p.card)) add(warnings, code, `the rotated version (${p.file}) has different data than ${main.file}; using ${main.file}`);
  }
  if (tokenCount) add(infos, null, `skipped ${tokenCount} ${tokenCount === 1 ? 'card' : 'cards'} without a code (tokens)`);

  // 2. PNG: "OP1-012 Sword Slash.png" (ili "OP1-012.png") ide karti po kodu, "Sword Slash.png" po imenu.
  // Isti PNG u više podfoldera -> noviji.
  // "... Sprite.png" je sprite (figurina u igri), ne slika karte; po imenu se zarez s razmakom ili bez ne razlikuje.
  // "... (rot).png" je rotirana slika Hero / Evolution karte (portrait).
  const pngByCode = new Map();
  const pngByName = new Map();
  const rotByCode = new Map();
  const rotByName = new Map();
  const spriteByCode = new Map();
  const spriteByName = new Map();
  for (const p of [...pngFiles].sort((a, b) => a.lastModified - b.lastModified || a.path.localeCompare(b.path))) {
    const name = baseName(p.path).replace(/\.png$/i, '');
    const sprite = SPRITE_RE.test(name);
    const rot = !sprite && ROT_RE.test(name);
    const rest = sprite ? name.replace(SPRITE_RE, '') : rot ? name.replace(ROT_RE, '') : name;
    const code = rest.split(/\s+/)[0];
    const [map, key] = CODE_RE.test(code)
      ? [sprite ? spriteByCode : rot ? rotByCode : pngByCode, code]
      : sprite ? [spriteByName, normName(rest)] : rot ? [rotByName, normName(rest)] : [pngByName, rest];
    if (map.has(key)) add(infos, null, `PNG "${name}" exists more than once; using the newer ${p.path}`);
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
      add(errors, p.code, `new card without a PNG ${pngName(p.card)} (or "${p.card.name}.png")`);
    }
    const diffs = old ? CE_FIELDS.filter(k => !same(old[k], p.card[k])) : [];
    const imageChanged = !!old && !!imageHash && imageHash !== old.imageHash;
    const status = !old ? 'new' : diffs.length || imageChanged ? 'changed' : 'same';
    // PNG je nacrtana karta: promijenjeni podaci, a ista slika znači da je slika vjerojatno stara.
    const staleImage = diffs.length > 0 && !imageChanged;
    if (staleImage) add(warnings, p.code, `changed (${diffs.join(', ')}), but ${png ? 'the PNG is the same as before' : 'there is no PNG, so the old image stays'}; the image may be outdated, is a new ${pngName(p.card)} needed?`);
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
      add(errors, null, `${png.path}: ${candidates.map(c => c.id).join(' and ')} share the same name; the PNG must start with the code, e.g. ${pngName(candidates[0])}`);
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
      add(errors, null, `${sprite.path}: ${candidates.map(c => c.id).join(' and ')} share the same name; the sprite must start with the code, e.g. "${candidates[0].id} ${candidates[0].name} Sprite.png"`);
      continue;
    }
    const target = candidates[0];
    if (!SPRITE_TYPES.includes(target.type)) {
      add(warnings, target.id, `${sprite.path}: sprites are only for heroes and Evolution cards (${target.name} is ${target.type}); skipped`);
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

  // Rotirana slika (portrait): samo Hero i Evolution, isto kao sprite.
  for (const [rot, found] of [
    ...[...rotByCode].map(([code, r]) => [r, pool.has(code) ? [pool.get(code)] : []]),
    ...[...rotByName].map(([name, r]) => [r, poolByName.get(name) ?? []]),
  ]) {
    if (!found.length) continue;
    usedPngs.add(rot);
    const live = found.filter(c => !c.deleted);
    const candidates = live.length ? live : found;
    if (candidates.length > 1) {
      add(errors, null, `${rot.path}: ${candidates.map(c => c.id).join(' and ')} share the same name; the rotated PNG must start with the code, e.g. "${candidates[0].id} ${candidates[0].name} (rot).png"`);
      continue;
    }
    const target = candidates[0];
    if (!SPRITE_TYPES.includes(target.type)) {
      add(warnings, target.id, `${rot.path}: rotated images are only for Hero and Evolution cards (${target.name} is ${target.type}); skipped`);
      continue;
    }
    const old = oldById.get(target.id);
    let e = entryById.get(target.id);
    if (!e) {
      const card = { id: old.id };
      for (const k of CE_FIELDS) if (old[k] !== undefined) card[k] = old[k];
      e = { id: old.id, status: 'same', card, old, diffs: [], imageChanged: false, staleImage: false, imageHash: null, png: null, file: rot.path };
      entries.push(e);
      entryById.set(e.id, e);
    }
    e.rotPng = rot;
    e.rotHash = await imageHashOf(await rot.getBytes());
    e.rotChanged = !!old && e.rotHash !== old.imageRotHash;
    if (e.status === 'same' && e.rotChanged) e.status = 'changed';
  }
  entries.sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));

  const skipped = [...pngByCode.values(), ...pngByName.values(), ...spriteByCode.values(), ...spriteByName.values(), ...rotByCode.values(), ...rotByName.values()]
    .filter(png => !usedPngs.has(png)).map(png => baseName(png.path));
  if (skipped.length) add(infos, null, `skipped ${skipped.length} ${skipped.length === 1 ? 'PNG that is not a card' : 'PNGs that are not cards'} with a code: ${skipped.join(', ')}`);

  // 4. Provjere na bazi kakva će biti nakon Objave.
  // Heroj mora imati jedinstveno ime (Evolution ga nalazi po imenu).
  // Ostale karte smiju dijeliti ime, ali tada PNG mora počinjati kodom.
  const final = mergedCards(db, entries);
  const live = final.filter(c => !c.deleted);
  const byName = new Map();
  for (const c of live) byName.set(c.name, [...(byName.get(c.name) ?? []), c]);
  for (const [name, list] of byName) {
    if (list.length < 2) continue;
    const ids = list.map(c => c.id).join(', ');
    if (list.some(c => c.type === 'Hero')) add(errors, list[0].id, `the name "${name}" is used by ${ids}; a hero must have a unique name`);
    else add(warnings, list[0].id, `the same name "${name}" is used by ${ids}; that's allowed, but the PNGs must start with the code`);
  }
  for (const e of entries) {
    if (e.pngByName && byName.get(e.card.name)?.length > 1) add(errors, e.id, `PNG "${e.card.name}.png": unclear which card it belongs to (several cards share that name); rename it to ${pngName(e.card)}`);
  }
  const heroes = new Set(live.filter(c => c.type === 'Hero').map(c => c.name));
  for (const c of live) {
    if (c.type === 'Evolution' && !heroes.has(c.hero)) add(errors, c.id, `Evolution: hero "${c.hero}" doesn't exist`);
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
  if (ce.type === 'Hero') card.wt = old?.wt ?? DEFAULT_WT;
  // Ostala app polja (npr. boja kuglice, fx) ostaju kakva su bila.
  for (const k of APP_FIELDS) if (card[k] === undefined && old?.[k] !== undefined) card[k] = old[k];
  // Redak "Terrain:" u tekstu stagea ima prednost pred ručno odabranim terenom.
  if (ce.type === 'Stage') {
    const terrain = terrainFromText(ce.text);
    if (terrain) card.terrain = terrain;
  }
  // Promijenjen tekst karte s fx-om: stari fx i dalje vrijedi, ali ga treba provjeriti.
  if (card.fx && old && old.text !== ce.text) card.fxStatus = 'check';
  card.deleted = old?.deleted ?? false;
  return card;
}

// Rezultat: novi cards.json + slike koje treba zapisati.
// Karte koje nisu u exportu ostaju kakve jesu.
export function buildPublish(db, analysis, now = new Date()) {
  const writes = [];
  const touched = new Map();
  let gameChanges = 0;
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
    if (e.rotHash && (!e.old || e.rotChanged)) {
      card.imageRot = `images/${e.id}.rot.${e.rotHash}.png`;
      card.imageRotHash = e.rotHash;
      writes.push({ path: `data/${card.imageRot}`, png: e.rotPng });
    } else if (e.old?.imageRot) {
      card.imageRot = e.old.imageRot;
      card.imageRotHash = e.old.imageRotHash;
    }
    if (e.spriteHash && (!e.old || e.spriteChanged)) {
      card.sprite = `sprites/${e.id}.${e.spriteHash}.png`;
      card.spriteHash = e.spriteHash;
      writes.push({ path: `data/${card.sprite}`, png: e.spritePng });
    } else if (e.old?.sprite) {
      card.sprite = e.old.sprite;
      card.spriteHash = e.old.spriteHash;
    }
    // rotirana slika je karta u decku, pa je i ona promjena igre (kao slika karte)
    const game = !e.old || e.diffs.length > 0 || e.imageChanged || !!e.rotChanged;
    if (game) gameChanges++;
    card.rev = (e.old?.rev ?? 0) + (game ? 1 : 0);
    touched.set(e.id, ordered(card));
  }
  if (!touched.size) return { db, writes, changed: 0, bumped: false };
  const cards = db.cards.map(c => touched.get(c.id) ?? c);
  for (const [id, c] of touched) if (!db.cards.some(o => o.id === id)) cards.push(c);
  cards.sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  // Samo izgled (npr. novi sprite): verzija ostaje, promjena se skuplja pod nju (vidi LOOK_FIELDS).
  return {
    db: { version: db.version + (gameChanges ? 1 : 0), updated: now.toISOString(), cards },
    writes,
    changed: touched.size,
    bumped: gameChanges > 0,
  };
}

// Izmjena app polja (wt, fx, boja kuglice, deleted). edits: { [id]: { polje: vrijednost } }
// Igra (wt, fx, terrain, deleted) diže verziju; samo izgled (boja kuglice, sprite) ne, nego se skuplja pod trenutnu verziju.
export function applyAppEdits(db, edits, now = new Date()) {
  let changed = 0;
  let game = 0;
  const cards = db.cards.map(c => {
    const e = edits[c.id];
    if (!e) return c;
    const next = { ...c };
    // undefined makne polje (npr. druga boja kuglice opet zadana)
    for (const k of APP_FIELDS) if (k in e) { if (e[k] === undefined) delete next[k]; else next[k] = e[k]; }
    if (same(next, c)) return c;
    changed++;
    const isGame = APP_FIELDS.some(k => !LOOK_FIELDS.includes(k) && !same(next[k], c[k]));
    if (isGame) {
      game++;
      next.rev = (c.rev ?? 0) + 1;
    }
    return ordered(next);
  });
  if (!changed) return { db, changed, bumped: false };
  return { db: { version: db.version + (game ? 1 : 0), updated: now.toISOString(), cards }, changed, bumped: game > 0 };
}

// Stare verzije slika (data/images/ID.hash.png) koje se smiju obrisati: karta ima noviju sliku.
export function obsoleteImages(db, imageFiles) {
  const current = new Map(db.cards.flatMap(c => [[c.id, c.imageHash], [`${c.id}.rot`, c.imageRotHash]]));
  return imageFiles.filter(f => {
    const m = /^(.+)\.([0-9a-f]+)\.png$/i.exec(f);
    if (!m) return false;
    const [, id, hash] = m;
    const cur = current.get(id);
    return !!cur && hash !== cur;
  });
}

// Povijest promjena (data/changelog.json): jedan zapis po verziji baze, piše ga app pri Objavi i spremanju app polja.
// { entries: [{ version, date, cards: [{ id, name, kind: new|changed|deleted|restored, fields: [...], image }] }] }
export const CHANGELOG_PATH = 'data/changelog.json';

export function emptyChangelog() {
  return { entries: [] };
}

// Razlika dvije verzije baze, za zapis u povijest. fields = igra (polja karte, wt), image = slika karte,
// look = izgled (boja kuglice, sprite): izgled ne diže verziju i ne broji se kao promjena karte.
export function changelogEntry(oldDb, newDb) {
  const oldById = new Map(oldDb.cards.map(c => [c.id, c]));
  const cards = [];
  for (const c of newDb.cards) {
    const o = oldById.get(c.id);
    if (!o) {
      cards.push({ id: c.id, name: c.name, kind: 'new', fields: [], image: false });
      continue;
    }
    const fields = [...CE_FIELDS, ...APP_FIELDS.filter(k => !LOOK_FIELDS.includes(k) && k !== 'deleted')].filter(k => !same(o[k], c[k]));
    const image = o.imageHash !== c.imageHash || (o.imageRotHash ?? null) !== (c.imageRotHash ?? null);
    const look = [...LOOK_FIELDS.filter(k => !same(o[k], c[k])), ...(o.spriteHash !== c.spriteHash ? ['sprite'] : [])];
    const kind = !o.deleted && c.deleted ? 'deleted' : o.deleted && !c.deleted ? 'restored' : 'changed';
    if (fields.length || image || look.length || kind !== 'changed') cards.push({ id: c.id, name: c.name, kind, fields, image, ...(look.length ? { look } : {}) });
  }
  return { version: newDb.version, date: newDb.updated, cards };
}

const union = (a = [], b = []) => [...new Set([...a, ...b])];

// Zapis iste verzije (izgled skupljen pod trenutnu verziju) spaja se s postojećim, karta po karta.
export function appendChangelog(log, entry) {
  if (!entry.cards.length) return log;
  const prev = log.entries.find(e => e.version === entry.version);
  let merged = entry;
  if (prev) {
    const byId = new Map(prev.cards.map(c => [c.id, { ...c }]));
    for (const c of entry.cards) {
      const p = byId.get(c.id);
      if (!p) { byId.set(c.id, c); continue; }
      const look = union(p.look, c.look);
      byId.set(c.id, {
        ...p,
        kind: c.kind !== 'changed' ? c.kind : p.kind,
        fields: union(p.fields, c.fields),
        image: !!(p.image || c.image),
        ...(look.length ? { look } : {}),
      });
    }
    merged = { ...prev, cards: [...byId.values()] };
  }
  return { entries: [...log.entries.filter(e => e.version !== entry.version), merged].sort((a, b) => a.version - b.version) };
}

// Stari zapisi (do v4) imaju izgled u fields ('bakuganShape') ili kao sprite: true.
const lookOf = c => union(union(c.look, (c.fields ?? []).filter(f => LOOK_FIELDS.includes(f))), c.sprite ? ['sprite'] : []);
const gameFieldsOf = c => (c.fields ?? []).filter(f => !LOOK_FIELDS.includes(f));
const isGameChange = c => c.kind !== 'changed' || c.image || gameFieldsOf(c).length > 0;

// Promjene igre nakon verzije `since` (izgled se ne broji): id -> [{ version, kind, fields, image }].
// Za deckove ("karta promijenjena od spremanja") i poruku "nova verzija".
export function changesSince(log, since) {
  const out = new Map();
  for (const e of log.entries) {
    if (e.version <= since) continue;
    for (const c of e.cards) {
      if (!isGameChange(c)) continue;
      if (!out.has(c.id)) out.set(c.id, []);
      out.get(c.id).push({ version: e.version, kind: c.kind, fields: gameFieldsOf(c), image: c.image });
    }
  }
  return out;
}

// Kratak opis promjene karte: "values, slika", "nova", "maknuta", "izgled: boja kuglice, sprite".
const FIELD_LABELS = { ballColor: 'ball color', ballColor2: 'ball accent color', bakuganShape: 'bakugan shape', bakuganColor: 'bakugan color', bakuganColor2: 'bakugan accent color', bakugan: 'bakugan', sprite: 'sprite' };

export function describeChange(c) {
  const kind = { new: 'new', deleted: 'deleted', restored: 'restored' }[c.kind];
  const game = kind ? [kind] : [...gameFieldsOf(c), ...(c.image ? ['image'] : [])];
  const look = lookOf(c).map(f => FIELD_LABELS[f] ?? f);
  return [game.join(', '), look.length ? `look: ${look.join(', ')}` : ''].filter(Boolean).join(' · ');
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
    if (e.rotPng) out.add(e.rotPng.path);
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

// Koje sličice treba napraviti i koje su višak (stare se brišu odmah).
export function thumbPlan(db, thumbFiles) {
  const have = new Set(thumbFiles);
  const wanted = new Set(db.cards.map(thumbName).filter(Boolean));
  return {
    missing: db.cards.filter(c => c.image && !have.has(thumbName(c))),
    extra: thumbFiles.filter(f => /\.jpg$/i.test(f) && !wanted.has(f)),
  };
}

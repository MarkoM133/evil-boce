// Uvoz exporta u cards.json: spajanje XML-ova i PNG-ova, usporedba s bazom, provjere i Objavi.
// Bez I/O: pozivatelj (app ili test) skupi fileove i zapiše rezultat.
import { parseCardEngineXml, CODE_RE, ROT_RE, terrainFromText } from './parse.js';

// Polja koja dolaze iz Card Enginea (§5). App ih ne mijenja.
export const CE_FIELDS = ['name', 'type', 'color', 'cost', 'evo', 'hero', 'stats', 'bonus', 'values', 'traits', 'text', 'abilityNames', 'landscape'];
// Polja koja se uređuju samo u appu. Ponovni uvoz ih ne dira.
// Za igru: fx (efekt karte za igru), fxStatus ('ok' | 'check' | ''), terrain (Stage; iz retka "Terrain:" ili ručno),
// aliases (Hero): druga imena po kojima ga prvi tag karte prepoznaje (pravilo prvog taga, js/tags.js),
// , npr. figures/OP1-001.glb), ballColor i ballColor2 (kuglica: tijelo i akcent), heroSfx.
// bakugan* su stara TTS polja: ostaju u starim zapisima (igra ih čita kao zadanu boju kuglice), app ih više ne nudi.
export const APP_FIELDS = ['wt', 'aliases', 'bakugan', 'bakuganShape', 'bakuganColor', 'bakuganColor2', 'fx', 'fxStatus', 'fxRead', 'terrain', 'figure', 'ballColor', 'ballColor2', 'heroSfx', 'deleted'];
// Izgled: ne mijenja igru, pa ne diže verziju baze (sprite je isto izgled, ali dolazi iz exporta).
// fxStatus je samo oznaka za pregled, pa ni on ne diže verziju.
// fxRead: čitanje parsera igre koje je čovjek potvrdio (karta bez ručnog fx-a); samo oznaka, kao fxStatus.
export const LOOK_FIELDS = ['bakugan', 'bakuganShape', 'bakuganColor', 'bakuganColor2', 'fxStatus', 'fxRead', 'figure', 'ballColor', 'ballColor2', 'heroSfx'];
const FIELD_ORDER = ['id', 'name', 'type', 'color', 'bonusColors', 'cost', 'extraCost', 'ingredients', 'introducedIn', 'evo', 'hero', 'stats', 'wt', 'bonus', 'values', 'traits', 'aliases', 'text', 'abilityNames', 'terrain', 'fx', 'fxStatus', 'fxRead', 'landscape', 'bakugan', 'bakuganShape', 'bakuganColor', 'bakuganColor2', 'ballColor', 'ballColor2', 'figure', 'heroSfx', 'art', 'artCrop', 'emblem', 'bg', 'template', 'coreImage', 'status', 'notes', 'image', 'imageHash', 'imageRot', 'imageRotHash', 'sprite', 'spriteHash', 'rev', 'deleted'];

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
  // crypto.subtle exists only on a secure page (https, localhost); over http on the Tailscale address (phone)
  // the same hash comes from the JS version below, so file names match wherever the art was uploaded.
  if (globalThis.crypto?.subtle) {
    const buf = await crypto.subtle.digest('SHA-256', bytes);
    return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
  }
  return sha256Js(bytes);
}

// SHA-256 in plain JS (FIPS 180-4), for pages without crypto.subtle. Same output as the browser's.
export function sha256Js(input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  const K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ]);
  const H = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
  const len = bytes.length;
  const padded = new Uint8Array(Math.ceil((len + 9) / 64) * 64);
  padded.set(bytes);
  padded[len] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(padded.length - 8, Math.floor((len * 8) / 0x100000000));
  view.setUint32(padded.length - 4, (len * 8) >>> 0);
  const W = new Uint32Array(64);
  const rotr = (x, n) => (x >>> n) | (x << (32 - n));
  for (let off = 0; off < padded.length; off += 64) {
    for (let i = 0; i < 16; i++) W[i] = view.getUint32(off + i * 4);
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(W[i - 15], 7) ^ rotr(W[i - 15], 18) ^ (W[i - 15] >>> 3);
      const s1 = rotr(W[i - 2], 17) ^ rotr(W[i - 2], 19) ^ (W[i - 2] >>> 10);
      W[i] = (W[i - 16] + s0 + W[i - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, h] = H;
    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (h + S1 + ch + K[i] + W[i]) >>> 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) >>> 0;
      h = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0; H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0; H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
  }
  return [...H].map(x => x.toString(16).padStart(8, '0')).join('');
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
      if (p.skip && p.coreWithoutCode) { add(errors, null, `${f.path}: Core card "${p.name}" has no code; Core cards need one (Core-001)`); continue; }
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
    // Colorless karta (2026-11-01) ostaje colorless: Card Engine zna samo boju okvira.
    if (old?.color === 'None') { p.card.color = 'None'; if (old.bonusColors) p.card.bonusColors = old.bonusColors; }
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

// Nacrti iz Card editora (data/editor/drafts.json) u bazu. Polja igre dižu rev karte i verziju baze;
// polja izgleda (art, izrez, amblem, pozadina, predložak, status, bilješke) i nova slika ne dižu.
// images: { id: imageHash } za karte kojima je Objava nacrtala novi PNG (data/images/ID.hash.png).
// Nacrt s new: true i kodom kojeg nema u bazi je nova karta (dodaje se na kraj, rev 1).
export const DRAFT_GAME_FIELDS = ['name', 'type', 'color', 'bonusColors', 'cost', 'evo', 'hero', 'stats', 'bonus', 'traits', 'aliases', 'text', 'abilityNames', 'terrain', 'fx', 'ingredients', 'extraCost', 'introducedIn'];
export const DRAFT_LOOK_FIELDS = ['fxStatus', 'fxRead', 'art', 'artCrop', 'emblem', 'bg', 'template', 'coreImage', 'status', 'notes'];

export function applyDrafts(db, drafts, images = {}, now = new Date()) {
  let changed = 0;
  let game = 0;
  const ids = [];
  const cards = db.cards.map(c => {
    const d = drafts[c.id];
    if (!d && !images[c.id]) return c;
    const next = { ...c };
    for (const k of [...DRAFT_GAME_FIELDS, ...DRAFT_LOOK_FIELDS]) if (d && k in d) { if (d[k] == null) delete next[k]; else next[k] = d[k]; }
    if (images[c.id]) {
      next.image = `images/${c.id}.${images[c.id]}.png`;
      next.imageHash = images[c.id];
    }
    if (same(next, c)) return c;
    changed++;
    ids.push(c.id);
    if (DRAFT_GAME_FIELDS.some(k => !same(next[k], c[k]))) {
      game++;
      next.rev = (c.rev ?? 0) + 1;
    }
    return ordered(next);
  });
  for (const [id, d] of Object.entries(drafts)) {
    if (!d.new || db.cards.some(c => c.id === id)) continue;
    const card = { id };
    for (const k of [...DRAFT_GAME_FIELDS, ...DRAFT_LOOK_FIELDS]) if (d[k] != null) card[k] = d[k];
    if (['Hero', 'Evolution', 'Combo'].includes(card.type)) card.landscape = true;
    if (images[id]) {
      card.image = `images/${id}.${images[id]}.png`;
      card.imageHash = images[id];
    }
    card.rev = 1;
    card.deleted = false;
    cards.push(ordered(card));
    changed++;
    game++;
    ids.push(id);
  }
  if (!changed) return { db, changed, bumped: false, ids };
  return { db: { version: db.version + (game ? 1 : 0), updated: now.toISOString(), cards }, changed, bumped: game > 0, ids };
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

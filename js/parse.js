// Card Engine XML -> zapisi karata. Pravila su opisana u privatnom planu (§6).
// Dva layouta: stari portrait template (Action, Equipment, Assist, Stage i stari heroji) čita se po pozicijama (x, y);
// novi landscape Hero i Evolution (okvir *_hero_frame_X / *_evo_frame_X, 1050×750) po SiblingIndexu elemenata.
import { parseXml, child, children, text } from './xml.js';

export const COLORS = {
  '0,255,255': 'Cyan',
  '255,255,0': 'Yellow',
  '255,0,255': 'Purple',
  '255,0,0': 'Red',
  '0,0,255': 'Blue',
  '0,255,0': 'Green',
};
export const COLOR_NAMES = Object.values(COLORS);

// Character je preimenovan u Hero (2026-10-24); stari zapisi s 'Character' čitaju se kao Hero (normalizeDb).
// Core (kodovi CR1-001…) je za igru: kuglice na mapi, ne idu u deck.
export const TYPES = ['Hero', 'Evolution', 'Action', 'Equipment', 'Assist', 'Stage', 'Core'];
export const DECK_TYPES = ['Evolution', 'Action', 'Equipment', 'Assist'];
export const HERO_TYPES = ['Hero', 'Evolution'];
// Tipovi bez boje frakcije.
const COLORLESS_TYPES = ['Stage', 'Core'];
const TYPE_TEXTS = { Character: 'Hero', Hero: 'Hero', Action: 'Action', Assist: 'Assist', Equipment: 'Equipment', Evolution: 'Evolution', Core: 'Core' };

// Teren stagea: zaseban redak "Terrain: Ice" u tekstu stage karte (vodič za tekst karata).
export const TERRAINS = ['Ice', 'Mud', 'Ramp', 'Wind', 'None'];
const TERRAIN_RE = /\bTerrain:\s*([A-Za-z]+)/;

// Novi layout: okvir nosi slovo boje frakcije (ista boja kao stara tinta p_frame_11).
const FRAME_RE = /_(hero|evo)_frame_([RGBCMY])$/i;
const FRAME_COLORS = { R: 'Red', G: 'Green', B: 'Blue', C: 'Cyan', M: 'Purple', Y: 'Yellow' };
const ROMAN = { I: 1, II: 2, III: 3, IV: 4, V: 5 };
// SiblingIndex elemenata na Hero i Evolution kartama (handoff 2026-10-24).
const IDX = { type: 3, name: 4, text: 11, traits: 16, code: 17, cost: 18 };
// Rotirana verzija iste karte (za deck): ime završava s " (rot)", elementi imaju rotation 90.
export const ROT_RE = /\s*\(rot\)$/i;

const ICONS = {
  tabletop_icons_24: 'kb',
  tabletop_icons_25: 'pwr',
  tabletop_icons_26: 'rng',
  tabletop_icons_27: 'dmg',
  tabletop_icons_28: 'hp',
};
export const STAT_KEYS = ['hp', 'dmg', 'pwr', 'rng', 'kb'];

const SPRITES = { 0: 'HP', 1: 'DMG', 2: 'Power', 3: 'Range', 4: 'Knockback' };

// Kod karte: SET-001, SET je veliko slovo pa do 5 slova ili brojki (OP1, JO1, CR1, DBZ, JJ5, OPM, Stage).
// Samo "OP" bez broja nije set: One Piece uvijek ima broj seta.
export const CODE_RE = /^(?:Stage|(?!OP-)[A-Z][A-Z0-9]{1,5})-\d{3}$/;
const LOOSE_CODE_RE = /^[A-Za-z][A-Za-z0-9]{0,5}-\d+$/;
const NUM_RE = /^[+-]?\d+$/;

const COST_Y = 461;
const TRAITS_X = 158;
const TRAITS_Y = -456;

// TMP tagovi (<b>, <cspace=6>, <sprite=…>) van; za ime, kod, tip i traitove.
export const stripTags = t => (t ?? '').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();

// "Terrain: ice" -> 'Ice'; nepoznat teren ili bez retka -> null.
export function terrainFromText(t) {
  const m = TERRAIN_RE.exec(t ?? '');
  if (!m) return null;
  return TERRAINS.find(x => x.toLowerCase() === m[1].toLowerCase()) ?? null;
}

// Imena abilityja: na kartama su podcrtana (<u>Gomu Gomu no Grab</u>) u retku iznad efekta.
// Imena idu u abilityNames (redom kojim su na karti), a iz teksta van, da tekst efekta ostane kakav je bio.
export function abilityNames(t) {
  return [...(t ?? '').matchAll(/<u>([\s\S]*?)<\/u>/g)].map(m => stripTags(m[1])).filter(Boolean);
}

export function withoutAbilityNames(t) {
  return (t ?? '').replace(/<u>[\s\S]*?<\/u>[ \t]*\r?\n?/g, '').replace(/<b>\s*<\/b>/g, '');
}

function setText(card, raw) {
  const names = abilityNames(raw);
  card.text = raw ? cleanText(withoutAbilityNames(raw)) : '';
  if (names.length) card.abilityNames = names;
}

export function cleanText(t) {
  return t
    .replace(/^\s*<sprite=3[^>]*>/, '[Range] ')
    .replace(/<sprite=(\d+)[^>]*>/g, (_, n) => ' ' + (SPRITES[n] ?? ''))
    .replace(/<\/?b>/g, '')
    .replace(/<[^>]+>/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/ \./g, '.')
    .trim();
}

function readElements(cardNode) {
  return children(child(cardNode, 'Front/Elements'), 'Element')
    .filter(e => text(e, 'Active') === 'true')
    .map(e => ({
      t: (text(e, 'Text') ?? '').trim(),
      x: parseFloat(text(e, 'Position/x')),
      y: parseFloat(text(e, 'Position/y')),
      kind: text(e, 'Type') === '0' ? 'text' : 'image',
      rgb: ['r', 'g', 'b'].map(k => parseInt(text(e, 'color/' + k), 10)).join(','),
      idx: parseInt(text(e, 'SiblingIndex') ?? '', 10),
      rotation: parseFloat(text(e, 'rotation') ?? '0') || 0,
    }));
}

// Statsi: broj desno od ikone u istom redu (najbliži); ICONS daje stat po imenu ikone.
function readIcons(els, texts) {
  const icons = {};
  for (const ic of els) {
    const key = ICONS[ic.t];
    if (!key) continue;
    const cand = texts.filter(t => NUM_RE.test(t.t) && Math.abs(t.y - ic.y) < 10 && t.x > ic.x);
    if (!cand.length) continue;
    icons[key] = cand.reduce((a, b) => (b.x - ic.x < a.x - ic.x ? b : a)).t;
  }
  return Object.fromEntries(STAT_KEYS.filter(k => k in icons).map(k => [k, icons[k]]));
}

function heroStats(card, ordered, problems) {
  card.stats = Object.fromEntries(Object.entries(ordered).map(([k, v]) => [k, parseInt(v, 10)]));
  const missing = STAT_KEYS.filter(k => !(k in card.stats));
  if (missing.length) problems.push({ level: 'error', msg: `missing stats: ${missing.join(', ')}` });
}

function readCode(raw, problems) {
  if (CODE_RE.test(raw)) return raw;
  if (!LOOSE_CODE_RE.test(raw)) return null;
  problems.push({ level: 'error', msg: `code "${raw}" doesn't match the pattern SET-001 (OP1-001, DBZ-001, Stage-001)` });
  return raw;
}

// Vraća jedan zapis po <Card>: { skip, code, card, problems }.
// skip = true za karte bez koda (tokeni); Core bez koda nije token, nego greška (skip + coreWithoutCode).
// problems = [{ level: 'error'|'warn', msg }].
export function parseCardEngineXml(xmlText) {
  const root = parseXml(xmlText);
  const list = child(root, 'ArrayOfCard');
  if (!list) throw new Error('Not a Card Engine export (no <ArrayOfCard>)');
  return children(list, 'Card').map(parseCard);
}

function parseCard(node) {
  const rawName = (text(node, 'Name') ?? '').trim();
  const els = readElements(node);
  const frame = els.find(e => e.kind === 'image' && FRAME_RE.test(e.t));
  if (frame) return parseLandscape(rawName, els, frame);
  const texts = els.filter(e => e.kind === 'text');
  const problems = [];

  let code = texts.find(e => CODE_RE.test(e.t))?.t;
  if (!code) {
    const loose = texts.find(e => LOOSE_CODE_RE.test(e.t))?.t;
    if (!loose) return { skip: true, name: rawName, coreWithoutCode: texts.some(e => e.t === 'Core') };
    code = readCode(loose, problems);
  }
  // Card Engine PNG nazove po imenu karte, pa frend u ime stavi i kod ("JO1-001 Giorno Giovanna").
  // Kod je već id karte, pa se iz imena makne.
  const name = rawName.startsWith(`${code} `) ? rawName.slice(code.length).trim() : rawName;

  let type = TYPE_TEXTS[texts.find(e => Object.hasOwn(TYPE_TEXTS, e.t))?.t];
  if (!type && code.startsWith('Stage-')) type = 'Stage';
  if (!type) problems.push({ level: 'error', msg: 'no card type' });

  const card = { id: code, name, type: type ?? null };

  if (COLORLESS_TYPES.includes(type)) {
    card.color = null;
  } else {
    const frame = els.find(e => e.kind === 'image' && e.t === 'p_frame_11');
    card.color = frame ? COLORS[frame.rgb] ?? null : null;
    if (!frame) problems.push({ level: 'error', msg: 'no p_frame_11 frame (color)' });
    else if (!card.color) problems.push({ level: 'error', msg: `unknown frame tint (${frame.rgb})` });
  }

  const row = texts.filter(e => NUM_RE.test(e.t) && Math.abs(e.y - COST_Y) < 5);
  const cost = row.find(e => e.x > 200);
  const evo = row.find(e => e.x < -200);
  if (DECK_TYPES.includes(type)) {
    if (cost) card.cost = parseInt(cost.t, 10);
    else problems.push({ level: 'error', msg: 'no cost' });
  }
  if (type === 'Evolution') {
    if (evo) card.evo = parseInt(evo.t, 10);
    card.hero = name.split(',')[0].trim();
  }

  const ordered = readIcons(els, texts);
  if (HERO_TYPES.includes(type)) {
    heroStats(card, ordered, problems);
  } else if (type && type !== 'Stage') { // i Core: +2000 Power i sl. su bonus
    const signed = Object.entries(ordered).filter(([, v]) => /^[+-]/.test(v));
    const plain = Object.entries(ordered).filter(([, v]) => !/^[+-]/.test(v));
    card.bonus = Object.fromEntries(signed.map(([k, v]) => [k, parseInt(v, 10)]));
    if (plain.length) {
      card.values = Object.fromEntries(plain.map(([k, v]) => [k, parseInt(v, 10)]));
      problems.push({ level: 'warn', msg: `unsigned values (${plain.map(([k, v]) => `${k} ${v}`).join(', ')}) go into "values", not bonus` });
    }
  }

  const traits = texts.find(e => Math.abs(e.x - TRAITS_X) < 5 && Math.abs(e.y - TRAITS_Y) < 5)?.t ?? '';
  card.traits = traits ? traits.split('/').map(s => s.trim()).filter(Boolean) : [];

  const effect = texts.find(e => Math.abs(e.x) < 10 && e.y < -250 && e.y > -400);
  setText(card, effect?.t ?? '');

  if (type === 'Stage') {
    const m = TERRAIN_RE.exec(card.text);
    if (m && !terrainFromText(card.text)) problems.push({ level: 'warn', msg: `unknown terrain "${m[1]}" (expected ${TERRAINS.join(', ')})` });
  }

  return { skip: false, code, card, problems };
}

// Novi landscape Hero / Evolution: dijelovi po SiblingIndexu, statsi po ikonama (kao stari layout).
// Rotirana verzija ("… (rot)", za deck) ima zarotirane pozicije (x, y) -> (−y, x); ovdje se vrate, pa je karta ista.
// variant: 'rot' za rotiranu verziju; app uz kartu sprema obje slike (landscape i rotiranu).
function parseLandscape(rawName, els, frame) {
  const problems = [];
  const rot = ROT_RE.test(rawName) || els.some(e => Math.abs(e.rotation) === 90);
  if (rot) for (const e of els) [e.x, e.y] = [e.y, -e.x];
  const byIdx = new Map(els.filter(e => Number.isInteger(e.idx)).map(e => [e.idx, e]));
  const at = k => stripTags(byIdx.get(IDX[k])?.t);

  const code = readCode(at('code'), problems);
  if (!code) return { skip: true, name: rawName };

  const [, frameKind, frameColor] = frame.t.match(FRAME_RE);
  const label = at('type').toUpperCase();
  const evo = /^EVOLUTION\s+([IVX]+)$/.exec(label);
  const type = label === 'HERO' ? 'Hero' : evo ? 'Evolution' : null;
  if (!type) problems.push({ level: 'error', msg: `unknown card type "${at('type')}" (expected HERO or EVOLUTION I–V)` });
  else if ((frameKind.toLowerCase() === 'hero') !== (type === 'Hero')) {
    problems.push({ level: 'warn', msg: `${type} on a ${frameKind.toLowerCase()} frame (${frame.t})` });
  }
  // Ime iz elementa; <Name> karte ima kod sprijeda i dodatak " Hero" ili " (rot)".
  const name = at('name') || rawName.replace(ROT_RE, '').replace(code, '').replace(/\s+Hero$/, '').trim();
  const card = { id: code, name, type: type ?? 'Hero', color: FRAME_COLORS[frameColor.toUpperCase()] };

  if (type === 'Evolution') {
    const cost = at('cost');
    if (NUM_RE.test(cost)) card.cost = parseInt(cost, 10);
    else problems.push({ level: 'error', msg: 'no cost' });
    card.evo = ROMAN[evo[1]];
    if (!card.evo) problems.push({ level: 'error', msg: `unknown evolution stage "${evo[1]}"` });
    card.hero = name.split(',')[0].trim();
  }
  heroStats(card, readIcons(els, els.filter(e => e.kind === 'text')), problems);
  const traits = at('traits');
  card.traits = traits ? traits.split('/').map(t => t.trim()).filter(Boolean) : [];
  setText(card, byIdx.get(IDX.text)?.t ?? '');
  card.landscape = true;
  return { skip: false, code, card, problems, variant: rot ? 'rot' : null };
}

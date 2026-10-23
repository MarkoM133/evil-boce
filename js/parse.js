// Card Engine XML -> zapisi karata. Pravila su opisana u privatnom planu (§6);
// pozicije (x, y) odgovaraju trenutnom templateu karata.
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

export const TYPES = ['Character', 'Evolution', 'Action', 'Equipment', 'Assist', 'Stage'];
export const DECK_TYPES = ['Evolution', 'Action', 'Equipment', 'Assist'];
export const HERO_TYPES = ['Character', 'Evolution'];
const TYPE_TEXTS = ['Character', 'Action', 'Assist', 'Equipment', 'Evolution'];

const ICONS = {
  tabletop_icons_24: 'kb',
  tabletop_icons_25: 'pwr',
  tabletop_icons_26: 'rng',
  tabletop_icons_27: 'dmg',
  tabletop_icons_28: 'hp',
};
export const STAT_KEYS = ['hp', 'dmg', 'pwr', 'rng', 'kb'];

const SPRITES = { 0: 'HP', 1: 'DMG', 2: 'Power', 3: 'Range', 4: 'Knockback' };

// Kod karte: SET-001, SET je veliko slovo pa do 5 slova ili brojki (OP1, DBZ, JJ5, OPM, Stage).
// Samo "OP" bez broja nije set: One Piece uvijek ima broj seta.
export const CODE_RE = /^(?:Stage|(?!OP-)[A-Z][A-Z0-9]{1,5})-\d{3}$/;
const LOOSE_CODE_RE = /^[A-Za-z][A-Za-z0-9]{0,5}-\d+$/;
const NUM_RE = /^[+-]?\d+$/;

const COST_Y = 461;
const TRAITS_X = 158;
const TRAITS_Y = -456;

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
    }));
}

// Vraća jedan zapis po <Card>: { skip, code, card, problems }.
// skip = true za karte bez koda (tokeni). problems = [{ level: 'error'|'warn', msg }].
export function parseCardEngineXml(xmlText) {
  const root = parseXml(xmlText);
  const list = child(root, 'ArrayOfCard');
  if (!list) throw new Error('Nije Card Engine export (nema <ArrayOfCard>)');
  return children(list, 'Card').map(parseCard);
}

function parseCard(node) {
  const rawName = (text(node, 'Name') ?? '').trim();
  const els = readElements(node);
  const texts = els.filter(e => e.kind === 'text');
  const problems = [];

  let code = texts.find(e => CODE_RE.test(e.t))?.t;
  if (!code) {
    const loose = texts.find(e => LOOSE_CODE_RE.test(e.t))?.t;
    if (!loose) return { skip: true, name: rawName };
    problems.push({ level: 'error', msg: `kod "${loose}" ne odgovara uzorku SET-001 (OP1-001, DBZ-001, Stage-001)` });
    code = loose;
  }
  // Card Engine PNG nazove po imenu karte, pa frend u ime stavi i kod ("JO1-001 Giorno Giovanna").
  // Kod je već id karte, pa se iz imena makne.
  const name = rawName.startsWith(`${code} `) ? rawName.slice(code.length).trim() : rawName;

  let type = texts.find(e => TYPE_TEXTS.includes(e.t))?.t;
  if (!type && code.startsWith('Stage-')) type = 'Stage';
  if (!type) problems.push({ level: 'error', msg: 'nema tipa karte' });

  const card = { id: code, name, type: type ?? null };

  if (type === 'Stage') {
    card.color = null;
  } else {
    const frame = els.find(e => e.kind === 'image' && e.t === 'p_frame_11');
    card.color = frame ? COLORS[frame.rgb] ?? null : null;
    if (!frame) problems.push({ level: 'error', msg: 'nema okvira p_frame_11 (boja)' });
    else if (!card.color) problems.push({ level: 'error', msg: `nepoznat ton okvira (${frame.rgb})` });
  }

  const row = texts.filter(e => NUM_RE.test(e.t) && Math.abs(e.y - COST_Y) < 5);
  const cost = row.find(e => e.x > 200);
  const evo = row.find(e => e.x < -200);
  if (DECK_TYPES.includes(type)) {
    if (cost) card.cost = parseInt(cost.t, 10);
    else problems.push({ level: 'error', msg: 'nema costa' });
  }
  if (type === 'Evolution') {
    if (evo) card.evo = parseInt(evo.t, 10);
    card.hero = name.split(',')[0].trim();
  }

  const icons = {};
  for (const ic of els) {
    const key = ICONS[ic.t];
    if (!key) continue;
    const cand = texts.filter(t => NUM_RE.test(t.t) && Math.abs(t.y - ic.y) < 10 && t.x > ic.x);
    if (!cand.length) continue;
    icons[key] = cand.reduce((a, b) => (b.x - ic.x < a.x - ic.x ? b : a)).t;
  }
  const ordered = Object.fromEntries(STAT_KEYS.filter(k => k in icons).map(k => [k, icons[k]]));
  if (HERO_TYPES.includes(type)) {
    card.stats = Object.fromEntries(Object.entries(ordered).map(([k, v]) => [k, parseInt(v, 10)]));
    const missing = STAT_KEYS.filter(k => !(k in card.stats));
    if (missing.length) problems.push({ level: 'error', msg: `nedostaju statsi: ${missing.join(', ')}` });
  } else if (type && type !== 'Stage') {
    const signed = Object.entries(ordered).filter(([, v]) => /^[+-]/.test(v));
    const plain = Object.entries(ordered).filter(([, v]) => !/^[+-]/.test(v));
    card.bonus = Object.fromEntries(signed.map(([k, v]) => [k, parseInt(v, 10)]));
    if (plain.length) {
      card.values = Object.fromEntries(plain.map(([k, v]) => [k, parseInt(v, 10)]));
      problems.push({ level: 'warn', msg: `vrijednosti bez predznaka (${plain.map(([k, v]) => `${k} ${v}`).join(', ')}) idu u "values", nisu bonus` });
    }
  }

  const traits = texts.find(e => Math.abs(e.x - TRAITS_X) < 5 && Math.abs(e.y - TRAITS_Y) < 5)?.t ?? '';
  card.traits = traits ? traits.split('/').map(s => s.trim()).filter(Boolean) : [];

  const effect = texts.find(e => Math.abs(e.x) < 10 && e.y < -250 && e.y > -400);
  card.text = effect ? cleanText(effect.t) : '';

  return { skip: false, code, card, problems };
}

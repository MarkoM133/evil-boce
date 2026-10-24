// Deck: pravila (§8 plana), random deck (§10) i deck kod. Bez I/O, isto za app i testove.
import { DECK_TYPES } from './parse.js';

export const DECK_SIZE = 40;
export const LIMITS = { Action: 4, Equipment: 4, Assist: 2, Evolution: 2 };
export const CODE_PREFIX = 'EB1';

const nCards = n => `${n} ${n === 1 ? 'card' : 'cards'}`;

export function emptyDeck(name = '') {
  return { name, heroes: [], cards: {} };
}

export function cardCount(deck) {
  return Object.values(deck.cards).reduce((s, n) => s + n, 0);
}

function byId(db) {
  return new Map(db.cards.map(c => [c.id, c]));
}

export function heroCards(db) {
  return db.cards.filter(c => c.type === 'Hero' && !c.deleted);
}

// Karte koje smiju u deck uz ove heroje (bez maknutih).
export function deckPool(db, heroIds) {
  const ids = byId(db);
  const heroes = heroIds.map(id => ids.get(id)).filter(Boolean);
  const colors = new Set(heroes.map(h => h.color));
  const names = new Set(heroes.map(h => h.name));
  return db.cards.filter(c =>
    !c.deleted &&
    DECK_TYPES.includes(c.type) &&
    colors.has(c.color) &&
    (c.type !== 'Evolution' || names.has(c.hero)));
}

export function poolCapacity(pool) {
  return pool.reduce((s, c) => s + (LIMITS[c.type] ?? 0), 0);
}

export function slugify(name) {
  return name
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd').replace(/Đ/g, 'D')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
}

// problems: [{ level: 'error'|'warn', msg }]. ready = deck se može igrati (nema grešaka).
export function checkDeck(db, deck) {
  const ids = byId(db);
  const problems = [];
  const err = msg => problems.push({ level: 'error', msg });
  const warn = msg => problems.push({ level: 'warn', msg });

  const heroes = deck.heroes.map(id => ids.get(id));
  if (deck.heroes.length !== 3) err(`pick 3 heroes (now ${deck.heroes.length})`);
  if (new Set(deck.heroes).size !== deck.heroes.length) err('the same hero is picked twice');
  deck.heroes.forEach((id, i) => {
    if (!heroes[i]) err(`hero ${id} is not in the database`);
    else if (heroes[i].type !== 'Hero') err(`${id} is not a hero`);
    else if (heroes[i].deleted) warn(`hero ${heroes[i].name} was deleted from the database`);
  });

  const colors = new Set(heroes.filter(Boolean).map(h => h.color));
  const names = new Set(heroes.filter(Boolean).map(h => h.name));
  const byType = {};
  const byColor = {};
  const curve = {};
  for (const [id, n] of Object.entries(deck.cards)) {
    if (!n) continue;
    const c = ids.get(id);
    if (!c) { err(`card ${id} is not in the database`); continue; }
    if (!DECK_TYPES.includes(c.type)) { err(`${c.name}: ${c.type} can't go in a deck`); continue; }
    if (c.deleted) warn(`${c.name} was deleted from the database`);
    if (!colors.has(c.color)) err(`${c.name}: color ${c.color} is not a color of the chosen heroes`);
    if (c.type === 'Evolution' && !names.has(c.hero)) err(`${c.name}: Evolution for a hero who isn't in the deck`);
    if (n > LIMITS[c.type]) err(`${c.name}: ${n} copies, but ${c.type} allows at most ${LIMITS[c.type]}`);
    byType[c.type] = (byType[c.type] ?? 0) + n;
    byColor[c.color] = (byColor[c.color] ?? 0) + n;
    curve[c.cost] = (curve[c.cost] ?? 0) + n;
  }

  const count = cardCount(deck);
  const capacity = poolCapacity(deckPool(db, deck.heroes));
  if (count > DECK_SIZE) err(`${nCards(count)}, the maximum is ${DECK_SIZE}`);
  else if (count < DECK_SIZE) {
    if (deck.heroes.length === 3 && capacity < DECK_SIZE) {
      if (count < capacity) err(`${nCards(capacity - count)} missing (the pool of these heroes has only ${capacity})`);
      else warn(`the deck has ${nCards(count)} because the pool of these heroes has only ${capacity}`);
    } else {
      err(`${nCards(DECK_SIZE - count)} short of ${DECK_SIZE}`);
    }
  }

  return { ready: !problems.some(p => p.level === 'error'), problems, count, capacity, byType, byColor, curve };
}

// §10: popuni deck do 40. focusColor/focus (0..1) pomiče težinu prema jednoj boji (klizač u builderu).
export function randomFill(db, deck, { focusColor = null, focus = 0, rng = Math.random } = {}) {
  const pool = deckPool(db, deck.heroes);
  const cards = { ...deck.cards };
  let total = cardCount({ cards });
  const under = c => (cards[c.id] ?? 0) < LIMITS[c.type];
  const colors = [...new Set(pool.map(c => c.color))];
  const weight = color => (color === focusColor ? 1 + 4 * focus : 1);
  while (total < DECK_SIZE) {
    const open = colors.filter(color => pool.some(c => c.color === color && under(c)));
    if (!open.length) break;
    let r = rng() * open.reduce((s, color) => s + weight(color), 0);
    const color = open.find(col => (r -= weight(col)) < 0) ?? open[open.length - 1];
    const candidates = pool.filter(c => c.color === color && under(c));
    const card = candidates[Math.floor(rng() * candidates.length)];
    const add = Math.min(rng() < 0.5 ? 1 : 2, LIMITS[card.type] - (cards[card.id] ?? 0), DECK_SIZE - total);
    cards[card.id] = (cards[card.id] ?? 0) + add;
    total += add;
  }
  return { ...deck, cards, missing: DECK_SIZE - total };
}

// EB1|v12|OP1-001,OP1-002,OP1-005|OP1-008*4,OP1-012*2
export function encodeDeck(deck, catalogVersion) {
  const cards = Object.entries(deck.cards)
    .filter(([, n]) => n > 0)
    .sort(([a], [b]) => a.localeCompare(b, undefined, { numeric: true }))
    .map(([id, n]) => `${id}*${n}`);
  return [CODE_PREFIX, `v${catalogVersion}`, deck.heroes.join(','), cards.join(',')].join('|');
}

export function decodeDeck(code) {
  const parts = code.trim().split('|');
  if (parts.length !== 4 || parts[0] !== CODE_PREFIX) throw new Error(`Deck code must start with ${CODE_PREFIX}| and have 4 parts`);
  const version = /^v(\d+)$/.exec(parts[1]);
  if (!version) throw new Error('Deck code: invalid catalog version');
  const heroes = parts[2] ? parts[2].split(',') : [];
  const cards = {};
  for (const item of parts[3] ? parts[3].split(',') : []) {
    const m = /^(.+)\*(\d+)$/.exec(item);
    if (!m) throw new Error(`Deck code: invalid part "${item}"`);
    cards[m[1]] = (cards[m[1]] ?? 0) + parseInt(m[2], 10);
  }
  return { catalogVersion: parseInt(version[1], 10), heroes, cards };
}

// Karte iz decka (heroji i karte) promijenjene nakon verzije baze s kojom je deck spremljen.
// changes: rezultat changesSince(changelog, deck.catalogVersion). Vraća [{ id, changes }] redom kao u decku.
export function deckChanges(deck, changes) {
  const ids = [...deck.heroes, ...Object.keys(deck.cards).filter(id => deck.cards[id] > 0)];
  return [...new Set(ids)]
    .map(id => ({ id, changes: (changes.get(id) ?? []).filter(c => c.kind !== 'new') }))
    .filter(x => x.changes.length);
}

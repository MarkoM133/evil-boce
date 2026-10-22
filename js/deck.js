// Deck: pravila (§8 plana), random deck (§10) i deck kod. Bez I/O, isto za app i testove.
import { DECK_TYPES } from './parse.js';

export const DECK_SIZE = 40;
export const LIMITS = { Action: 4, Equipment: 4, Assist: 2, Evolution: 2 };
export const CODE_PREFIX = 'EB1';

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
  return db.cards.filter(c => c.type === 'Character' && !c.deleted);
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
  if (deck.heroes.length !== 3) err(`odaberi 3 heroja (sad ${deck.heroes.length})`);
  if (new Set(deck.heroes).size !== deck.heroes.length) err('isti heroj je odabran dvaput');
  deck.heroes.forEach((id, i) => {
    if (!heroes[i]) err(`heroj ${id} ne postoji u bazi`);
    else if (heroes[i].type !== 'Character') err(`${id} nije heroj (Character)`);
    else if (heroes[i].deleted) warn(`heroj ${heroes[i].name} je maknut iz baze`);
  });

  const colors = new Set(heroes.filter(Boolean).map(h => h.color));
  const names = new Set(heroes.filter(Boolean).map(h => h.name));
  const byType = {};
  const byColor = {};
  const curve = {};
  for (const [id, n] of Object.entries(deck.cards)) {
    if (!n) continue;
    const c = ids.get(id);
    if (!c) { err(`karta ${id} ne postoji u bazi`); continue; }
    if (!DECK_TYPES.includes(c.type)) { err(`${c.name}: ${c.type} ne ide u deck`); continue; }
    if (c.deleted) warn(`${c.name} je maknuta iz baze`);
    if (!colors.has(c.color)) err(`${c.name}: boja ${c.color} nije boja odabranih heroja`);
    if (c.type === 'Evolution' && !names.has(c.hero)) err(`${c.name}: Evolution za heroja kojeg nema u decku`);
    if (n > LIMITS[c.type]) err(`${c.name}: ${n} kopija, a ${c.type} smije najviše ${LIMITS[c.type]}`);
    byType[c.type] = (byType[c.type] ?? 0) + n;
    byColor[c.color] = (byColor[c.color] ?? 0) + n;
    curve[c.cost] = (curve[c.cost] ?? 0) + n;
  }

  const count = cardCount(deck);
  const capacity = poolCapacity(deckPool(db, deck.heroes));
  if (count > DECK_SIZE) err(`${count} karata, najviše je ${DECK_SIZE}`);
  else if (count < DECK_SIZE) {
    if (deck.heroes.length === 3 && capacity < DECK_SIZE) {
      if (count < capacity) err(`nedostaje ${capacity - count} karata (bazen ovih heroja ima samo ${capacity})`);
      else warn(`deck ima ${count} karata jer bazen ovih heroja ima samo ${capacity}`);
    } else {
      err(`nedostaje ${DECK_SIZE - count} karata do ${DECK_SIZE}`);
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
  if (parts.length !== 4 || parts[0] !== CODE_PREFIX) throw new Error(`Deck kod mora počinjati s ${CODE_PREFIX}| i imati 4 dijela`);
  const version = /^v(\d+)$/.exec(parts[1]);
  if (!version) throw new Error('Deck kod: neispravna verzija kataloga');
  const heroes = parts[2] ? parts[2].split(',') : [];
  const cards = {};
  for (const item of parts[3] ? parts[3].split(',') : []) {
    const m = /^(.+)\*(\d+)$/.exec(item);
    if (!m) throw new Error(`Deck kod: neispravan dio "${item}"`);
    cards[m[1]] = (cards[m[1]] ?? 0) + parseInt(m[2], 10);
  }
  return { catalogVersion: parseInt(version[1], 10), heroes, cards };
}

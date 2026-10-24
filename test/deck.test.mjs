// Testovi pravila decka, random decka i deck koda na izmišljenoj bazi.
import test from 'node:test';
import assert from 'node:assert/strict';
import { checkDeck, randomFill, deckPool, poolCapacity, encodeDeck, decodeDeck, slugify, LIMITS } from '../js/deck.js';

const hero = (id, name, color) => ({ id, name, type: 'Hero', color, stats: {} });
const card = (id, type, color, cost = 1, extra = {}) => ({ id, name: `Card ${id}`, type, color, cost, ...extra });

function db() {
  const cards = [
    hero('H-1', 'Alpha', 'Red'), hero('H-2', 'Beta', 'Blue'), hero('H-3', 'Gamma', 'Green'), hero('H-4', 'Delta', 'Cyan'),
    card('E-1', 'Evolution', 'Red', 2, { hero: 'Alpha' }),
    card('E-2', 'Evolution', 'Cyan', 2, { hero: 'Delta' }),
    card('S-1', 'Stage', null),
  ];
  for (const [color, n] of [['Red', 4], ['Blue', 4], ['Green', 4], ['Cyan', 4]]) {
    for (let i = 1; i <= n; i++) cards.push(card(`${color}-A${i}`, 'Action', color, i % 4));
    cards.push(card(`${color}-Q`, 'Equipment', color, 2));
    cards.push(card(`${color}-S`, 'Assist', color, 3));
  }
  cards.push(card('Red-X', 'Action', 'Red', 1, { deleted: true }));
  return { version: 7, cards };
}

// Deterministički "random" za testove.
function seeded(seed) {
  let s = seed;
  return () => ((s = (s * 1103515245 + 12345) % 2147483648) / 2147483648);
}

test('bazen: boje heroja, Evolution samo svog heroja, bez maknutih i Stagea', () => {
  const pool = deckPool(db(), ['H-1', 'H-2', 'H-3']);
  const ids = pool.map(c => c.id);
  assert.ok(ids.includes('E-1'));
  assert.ok(!ids.includes('E-2'));
  assert.ok(!ids.includes('Red-X'));
  assert.ok(!ids.includes('S-1'));
  assert.ok(!ids.some(id => id.startsWith('Cyan')));
  // po boji: 4 Action*4 + Equipment 4 + Assist 2 = 22; Red još Evolution 2
  assert.equal(poolCapacity(pool), 22 * 3 + 2);
});

test('provjera: heroji, limiti, boje, veličina', () => {
  const d = db();
  const r = checkDeck(d, { heroes: ['H-1', 'H-1'], cards: { 'Red-S': 3, 'Cyan-A1': 1, 'E-2': 1, 'S-1': 1 } });
  const msgs = r.problems.map(p => p.msg).join('\n');
  assert.equal(r.ready, false);
  assert.match(msgs, /pick 3 heroes/);
  assert.match(msgs, /same hero/);
  assert.match(msgs, /Assist allows at most 2/);
  assert.match(msgs, /color Cyan is not a color/);
  assert.match(msgs, /Evolution for a hero who isn't/);
  assert.match(msgs, /Stage can't go in a deck/);
});

test('random popuni do 40, poštuje limite po tipu, ostaje ispravan', () => {
  const d = db();
  for (let seed = 1; seed <= 30; seed++) {
    const deck = randomFill(d, { heroes: ['H-1', 'H-2', 'H-3'], cards: {} }, { rng: seeded(seed) });
    const r = checkDeck(d, deck);
    assert.equal(r.count, 40, `seed ${seed}`);
    assert.equal(deck.missing, 0);
    assert.ok(r.ready, `seed ${seed}: ${r.problems.map(p => p.msg).join('; ')}`);
    for (const [id, n] of Object.entries(deck.cards)) {
      const c = d.cards.find(x => x.id === id);
      assert.ok(n <= LIMITS[c.type]);
    }
  }
});

test('random dopuni postojeći deck i ne dira ručno dodane karte', () => {
  const d = db();
  const deck = randomFill(d, { heroes: ['H-1', 'H-2', 'H-3'], cards: { 'Red-A1': 4, 'E-1': 2 } }, { rng: seeded(3) });
  assert.equal(deck.cards['Red-A1'], 4);
  assert.equal(deck.cards['E-1'], 2);
  assert.equal(checkDeck(d, deck).count, 40);
});

test('random s naglaskom na boju daje više te boje', () => {
  const d = db();
  let focused = 0;
  let plain = 0;
  for (let seed = 1; seed <= 20; seed++) {
    focused += checkDeck(d, randomFill(d, { heroes: ['H-1', 'H-2', 'H-3'], cards: {} }, { focusColor: 'Blue', focus: 1, rng: seeded(seed) })).byColor.Blue ?? 0;
    plain += checkDeck(d, randomFill(d, { heroes: ['H-1', 'H-2', 'H-3'], cards: {} }, { rng: seeded(seed) })).byColor.Blue ?? 0;
  }
  assert.ok(focused > plain, `${focused} > ${plain}`);
});

test('premali bazen: random staje i javi koliko fali, provjera daje upozorenje', () => {
  const d = { version: 1, cards: [hero('H-1', 'A', 'Red'), hero('H-2', 'B', 'Blue'), hero('H-3', 'C', 'Green'), card('R-1', 'Action', 'Red'), card('B-1', 'Assist', 'Blue')] };
  const deck = randomFill(d, { heroes: ['H-1', 'H-2', 'H-3'], cards: {} }, { rng: seeded(1) });
  assert.deepEqual(deck.cards, { 'R-1': 4, 'B-1': 2 });
  assert.equal(deck.missing, 34);
  const r = checkDeck(d, deck);
  assert.ok(r.ready);
  assert.match(r.problems[0].msg, /pool of these heroes has only 6/);
});

test('deck kod: tamo i natrag', () => {
  const deck = { heroes: ['H-1', 'H-2', 'H-3'], cards: { 'Red-A10': 1, 'Red-A2': 4, 'E-1': 2, 'Blue-Q': 0 } };
  const code = encodeDeck(deck, 12);
  assert.equal(code, 'EB1|v12|H-1,H-2,H-3|E-1*2,Red-A2*4,Red-A10*1');
  assert.deepEqual(decodeDeck(code), { catalogVersion: 12, heroes: ['H-1', 'H-2', 'H-3'], cards: { 'E-1': 2, 'Red-A2': 4, 'Red-A10': 1 } });
  assert.throws(() => decodeDeck('XX|v1||'), /EB1/);
  assert.throws(() => decodeDeck('EB1|v1|H-1|bad'), /invalid part/);
});

test('slugify za ime filea', () => {
  assert.equal(slugify('Luffy aggro'), 'luffy-aggro');
  assert.equal(slugify('  Čćžšđ Deck #2!! '), 'cczsd-deck-2');
});

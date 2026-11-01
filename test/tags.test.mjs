// Pravilo prvog taga na zajedničkim slučajevima s igrom (game/tests/fixtures/first_tag_cases.json).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { firstTag, deckVerdict } from '../js/tags.js';

const fx = JSON.parse(readFileSync(new URL('../game/tests/fixtures/first_tag_cases.json', import.meta.url), 'utf8'));
const db = { cards: fx.cards };
const byId = new Map(fx.cards.map(c => [c.id, c]));

test('prvi tag: vrsta (General, heroj, trait, nevažeći)', () => {
  for (const k of fx.kinds) {
    const got = firstTag(db, byId.get(k.card), fx.traits);
    assert.equal(got.kind, k.kind, k.card);
    if (k.heroes) assert.deepEqual(got.heroes, k.heroes, k.card);
    if (k.trait) assert.equal(got.trait, k.trait, k.card);
  }
});

test('prvi tag: smije li karta u deck (isti slučajevi kao u igri)', () => {
  for (const c of fx.cases) {
    const v = deckVerdict(db, fx.traits, byId.get(c.card), c.heroes, c.evolutions ?? []);
    assert.equal(v.ok, c.ok, `${c.card}: ${c.why} (${v.why})`);
    if (c.needs) assert.deepEqual(v.needs, [c.needs], c.card);
  }
});

test('upozorenja pri uvozu i pokrivenost', async () => {
  const { setTraits, tagWarnings, coverage } = await import('../js/deck.js');
  const d = setTraits({ cards: fx.cards }, fx.traits);
  const w = tagWarnings(d);
  const has = (id, part) => w.some(x => x.id === id && x.msg.includes(part));
  assert.ok(has('C-TYPO', 'first tag "Hakki"'), 'unknown first tag');
  assert.ok(has('C-NONE', 'no tags'), 'no tags');
  assert.ok(has('C-LATE', '"Alfa" is a hero'), 'alias in second place');
  assert.ok(has('H-DEL', 'no trait from the trait list'), 'hero without a list trait');
  assert.ok(has('H-ALF', 'only'), 'few own cards');
  assert.ok(!has('C-HAKI', 'nobody can take'), 'Alfa (Red) has Haki');
  assert.ok(has('C-SWORD-B', 'nobody can take'), 'no Blue hero with Sword');
  const cov = coverage(d);
  const alfa = cov.find(r => r.id === 'H-ALF');
  assert.ok(alfa.signature >= 2 && alfa.general >= 1 && alfa.trait >= 1, JSON.stringify(alfa));
  assert.equal(alfa.pairs, 6, 'four other heroes make six pairs');
});

// Colorless (2026-11-01): samo u web appu dok igra to ne zna; zajednički slučajevi s igrom dolaze s njezinom izvedbom.
test('colorless: any colour may take it, the first tag still counts', () => {
  const cards = [
    { id: 'H1', type: 'Hero', name: 'Luffy', color: 'Cyan', traits: ['Haki'] },
    { id: 'H2', type: 'Hero', name: 'Sanji', color: 'Purple', traits: ['Cook'] },
    { id: 'C1', type: 'Action', name: 'Taunt', color: 'None', bonusColors: ['Red'], traits: ['General'] },
    { id: 'C2', type: 'Action', name: 'Observation Haki', color: 'None', bonusColors: ['Cyan'], traits: ['Haki'] },
  ];
  const d = { cards };
  const traits = [{ name: 'Haki' }, { name: 'Cook' }];
  const by = id => cards.find(c => c.id === id);
  assert.equal(deckVerdict(d, traits, by('C1'), ['H2']).ok, true, 'General colorless: any hero');
  assert.equal(deckVerdict(d, traits, by('C2'), ['H1']).ok, true, 'Haki colorless: a Haki hero of another colour');
  const no = deckVerdict(d, traits, by('C2'), ['H2']);
  assert.equal(no.ok, false, 'Haki colorless: still needs a Haki hero');
  assert.match(no.why, /needs a hero with Haki/);
});

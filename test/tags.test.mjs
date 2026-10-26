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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildPack, manualPart, cardText, MANUAL_START, MANUAL_END } from '../tools/design-pack.mjs';

const db = {
  version: 3,
  cards: [
    { id: 'XX1-001', name: 'Hero A', type: 'Hero', color: 'Red', stats: { hp: 8, dmg: 3, pwr: 2000, rng: 2, kb: 1 }, wt: 2, traits: ['Crew', 'Sword'], aliases: ['A'], abilityNames: ['Slash'], text: 'Battle Phase: Hero A gets\n+1000 Power.' },
    { id: 'XX1-002', name: 'Evo A', type: 'Evolution', color: 'Red', hero: 'Hero A', evo: 1, cost: 2, stats: { hp: 10, dmg: 4, pwr: 3000, rng: 2, kb: 1 }, traits: ['Crew'], text: '' },
    { id: 'XX1-003', name: 'Cut', type: 'Action', color: 'Red', cost: 1, bonus: { pwr: 2000 }, traits: ['A'], text: 'Battle Phase:' },
    { id: 'XX1-004', name: 'Blade', type: 'Equipment', color: 'None', bonusColors: ['Red'], cost: 2, traits: ['Sword'], text: 'The equipped Hero gets +1 DMG.\nRed Bonus: They get an additional +1 DMG.' },
    { id: 'XX1-005', name: 'Shout', type: 'Action', color: 'Red', cost: 2, traits: ['General'], text: 'Preroll Phase: Gain 1 Energy.' },
    { id: 'Stage-001', name: 'Field', type: 'Stage', text: 'Each Hero on this Stage gets +1000 Power.\nTerrain: Ice', terrain: 'Ice' },
    { id: 'Core-001', name: '+2000 Power', type: 'Core', traits: ['Buff'], bonus: { pwr: 2000 } },
    { id: 'XX1-099', name: 'Gone', type: 'Action', color: 'Red', cost: 1, traits: ['A'], text: 'x', deleted: true },
  ],
};
const traits = [{ name: 'Sword' }];
const sets = [{ code: 'XX1', name: 'Test Set' }];

test('a hand line break inside a sentence becomes a space, a new effect a new line', () => {
  assert.equal(cardText('Battle Phase: Hero A gets\n+1000 Power.\nRed Bonus: more.'), 'Battle Phase: Hero A gets +1000 Power.\nRed Bonus: more.');
});

test('cards come grouped by set and hero, with the first tag marked and deleted cards left out', () => {
  const md = buildPack({ db, traits, sets, gameVersion: '9.9.9', manual: 'Pravila ovdje.', now: new Date('2026-11-07T10:00:00Z') });
  assert.match(md, /karte verzija 3, 7 karata, igra 9\.9\.9/);
  assert.match(md, /### Set XX1: Test Set/);
  const hero = md.indexOf('#### Hero A (Red)');
  const trait = md.indexOf('#### Trait Sword');
  const general = md.indexOf('#### General');
  assert.ok(hero > 0 && general > hero && trait > general, 'hero first, then General and trait groups');
  // The hero's evolution and its signature card sit in its group.
  assert.ok(md.indexOf('XX1-002 Evo A') > hero && md.indexOf('XX1-003 Cut') > hero && md.indexOf('XX1-003 Cut') < general);
  assert.match(md, /Tagovi: \*\*A\*\* \(prvi\)/);
  assert.match(md, /Colorless \(bonus: Red\)/);
  assert.match(md, /Bonus kvadratići: \+2000 Power/);
  assert.doesNotMatch(md, /XX1-099/);
  // A stage's terrain is a field, not repeated in its text.
  assert.match(md, /Teren: Ice/);
  assert.doesNotMatch(md, /Terrain: Ice/);
  assert.match(md, /\| Hero A \| Red \| 1 \| 1 \|/, 'one own card and one evolution');
});

test('the hand-written rules survive a rebuild', () => {
  const first = buildPack({ db, traits, sets, gameVersion: '1', manual: '\nRučni sažetak pravila.\n' });
  assert.ok(first.includes(`${MANUAL_START}\nRučni sažetak pravila.\n${MANUAL_END}`));
  const again = buildPack({ db, traits, sets, gameVersion: '2', manual: manualPart(first) });
  assert.ok(again.includes('Ručni sažetak pravila.'));
  assert.equal(manualPart('no markers here'), '');
});

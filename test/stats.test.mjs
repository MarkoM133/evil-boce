// Testovi zbrajanja statistike partija (kartica Balance) na izmišljenim sažecima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { aggregate, filterMatches, ranked, cardsVersions } from '../js/stats.js';

const player = (slot, heroes, extra = {}) => ({ slot, name: `P${slot}`, bot: false, deck_name: '', heroes, stages: ['S-1', 'S-2', 'S-3'], ...extra });

function matches() {
  return [
    { cards_version: 7, turns: 10, battles: 4, winner: 0, result: 'stages',
      players: [player(0, ['H-1', 'H-2', 'H-3'], { deck_name: 'Red rush' }), player(1, ['H-4', 'H-5', 'H-6'], { bot: true })],
      cards_played: { 'A-1': 3, 'A-2': 1 } },
    { cards_version: 7, turns: 6, battles: 2, winner: 1, result: 'ko',
      players: [player(0, ['H-1', 'H-4', 'H-5'], { deck_name: 'Random (x)' }), player(1, ['H-2', 'H-3', 'H-6'])],
      cards_played: { 'A-1': 1 } },
    { cards_version: 6, turns: 8, battles: 0, winner: -1, result: 'draw',
      players: [player(0, ['H-1', 'H-2', 'H-3']), player(1, ['H-1', 'H-2', 'H-3'])],
      cards_played: {} },
  ];
}

test('heroji: odabiri, pobjede i postotak; isti heroj kod oba igrača broji se dvaput', () => {
  const a = aggregate(matches());
  assert.equal(a.matches, 3);
  assert.deepEqual(a.heroes['H-1'], { picks: 4, wins: 1, rate: 25 });
  assert.deepEqual(a.heroes['H-6'], { picks: 2, wins: 1, rate: 50 });
  assert.equal(a.results.draw, 1);
  assert.equal(a.avgTurns, 8);
  assert.equal(a.avgBattles, 2);
});

test('karte: zbroj igranja i u koliko partija', () => {
  const a = aggregate(matches());
  assert.deepEqual(a.cards['A-1'], { plays: 4, matches: 2, perMatch: 4 / 3 });
});

test('deckovi bez Random, botovi zasebno', () => {
  const a = aggregate(matches());
  assert.deepEqual(Object.keys(a.decks), ['Red rush']);
  assert.deepEqual(a.decks['Red rush'], { picks: 1, wins: 1, rate: 100 });
  assert.deepEqual(a.bots, { picks: 1, wins: 0, rate: 0 });
});

test('filter: bez botova i po verziji baze', () => {
  assert.equal(filterMatches(matches(), { withBots: false }).length, 2);
  assert.equal(filterMatches(matches(), { cardsVersion: 7 }).length, 2);
  assert.equal(filterMatches(matches(), { withBots: false, cardsVersion: 6 }).length, 1);
  assert.equal(filterMatches([null, { players: 'x' }]).length, 0);
  assert.deepEqual(cardsVersions(matches()), [7, 6]);
});

test('poredak: najviše odabira, pa postotak pobjeda', () => {
  const rows = ranked(aggregate(matches()).heroes);
  // H-1, H-2 i H-3 imaju po 4 odabira; H-2 i H-3 po 2 pobjede (pa id), H-1 jednu.
  assert.deepEqual(rows.slice(0, 3).map(r => r.id), ['H-2', 'H-3', 'H-1']);
  assert.equal(rows.at(-1).picks, 2);
  const empty = aggregate([]);
  assert.equal(empty.avgTurns, 0);
  assert.equal(empty.bots.rate, null);
});

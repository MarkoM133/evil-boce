import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fxProblems, lineProblem, tokenIds } from '../js/fx-grammar.js';

test('lines from fx-keywords.md read as the game reads them', () => {
  for (const line of [
    'POSTROLL ONCE OPTIONAL: MOVE SELF 2',
    'POSTROLL IF ACTIVATED: DAMAGE ALL_OTHER_IN_RANGE 2',
    'PASSIVE: BUFF EQUIPPED PWR 1000 PER TRAIT_EQUIPPED {Sword}',
    'BATTLE IF WIN: DISCARD OPP 1',
    'POSTROLL RANGE: CHOOSE OPP [CHARGE ME 2; DISCHARGE OPP 2] [HEAL SELF 3; DAMAGE ENEMY 3]',
    'BATTLE IF OPP_EQUIPPED {Sword}: BUFF SELF PWR 1000',
    'BATTLE INSTEAD BONUS IF OPP_EQUIPPED {Sword}: BUFF SELF PWR 2000',
    'PLAY BONUS CYAN: OWN_COST -1',
    'PREROLL RANGE INSTEAD BONUS: HEAL FRIENDLY 4',
    'BATTLE IF WIN: FULL_HIT OPP',
    'POSTROLL: NO_CLAIM ALL_ENEMY_IN_RANGE',
    'POSTROLL RANGE: SWAP FRIENDLY ENGAGED',
    'BATTLE: BUFF MOST_ENERGY PWR 3000',
    'BATTLE: BUFF MOST_ENERGY PWR 3000 PICK',
    'BATTLE: BUFF ALL_FRIENDLY_IN_BATTLE PWR 3000; BUFF ALL_FRIENDLY_IN_BATTLE DMG 2',
    'PREROLL: TOKEN ME DQ1-010-1',
    'POSTROLL ONCE OPTIONAL: TOKEN ME DQ1-001-1 2',
    'PLAY: CHOOSE ME [TOKEN ME DQ1-010-1] [TOKEN OPP DQ1-010-2]',
    // A tag bonus (2026-11-21): the hero is called that or carries the tag.
    'BATTLE INSTEAD BONUS {Flazzard}: COST_DAMAGE 0',
    'BATTLE BONUS {Mage & Brave Hero}: BUFF SELF DMG 2',
    // A companion (GDD 10, 2026-11-21): Coco Jumbo's three lines.
    'PLAY: COMPANION',
    'POSTROLL OPTIONAL: HIDE 1 1',
    'POSTROLL OPTIONAL: HIDE 2',
    'END: WANDER 2',
    'POSTROLL: TERRAIN FIRE',
    'PASSIVE: STATUS SELF IGNORE_TERRAIN',
  ]) assert.equal(lineProblem(line), '', line);
});

test('lines the game would refuse are named', () => {
  assert.match(lineProblem('SOMETIMES: HEAL SELF 2'), /not a WHEN/);
  assert.match(lineProblem('PLAY HEAL SELF 2'), /no ":"/);
  assert.match(lineProblem('PLAY: ZAP ENEMY 2'), /not a verb/);
  assert.match(lineProblem('PLAY: HEAL BOB 2'), /needs a target/);
  assert.match(lineProblem('PLAY: BUFF SELF POWER 1000'), /BUFF needs a stat/);
  assert.match(lineProblem('PLAY: CHOOSE OPP [HEAL SELF 1]'), /two \[/);
  assert.match(lineProblem('PLAY QUICKLY: HEAL SELF 1'), /not a flag/);
  assert.deepEqual(fxProblems('PLAY: HEAL SELF 2\n\nPLAY: ZAP ENEMY 1').map(p => p.line), ['PLAY: ZAP ENEMY 1']);
});

test('TOKEN: a player and a token card id, never in the End phase or a passive (GDD 10, 2026-11-14)', () => {
  assert.match(lineProblem('PREROLL: TOKEN SELF DQ1-010-1'), /ME or OPP/);
  assert.match(lineProblem('PREROLL: TOKEN ME'), /needs 1 more argument/);
  assert.match(lineProblem('PREROLL: TOKEN ME DQ1-010-1 0'), /how many/);
  assert.match(lineProblem('END: TOKEN ME DQ1-010-1'), /End phase/);
  assert.match(lineProblem('END: CHOOSE ME [TOKEN ME DQ1-010-1] [NOOP]'), /End phase/);
  assert.match(lineProblem('PASSIVE: TOKEN ME DQ1-010-1'), /PASSIVE/);
  assert.deepEqual(tokenIds('PREROLL: TOKEN ME dq1-010-1\nPLAY: CHOOSE ME [TOKEN ME DQ1-010-1] [TOKEN OPP DQ1-010-2 2]\nBATTLE: HEAL SELF 2'), ['DQ1-010-1', 'DQ1-010-2']);
  assert.deepEqual(tokenIds('BATTLE: HEAL SELF 2'), []);
});

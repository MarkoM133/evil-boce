import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fxProblems, lineProblem } from '../js/fx-grammar.js';

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

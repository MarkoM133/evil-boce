import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planMove, targetCode, renameKeys, moveDrafts } from '../js/card-move.js';

const ids = (set, ...nums) => new Set(nums.map(n => `${set}-${String(n).padStart(3, '0')}`));
const plan = (from, to, published, unpublished) => Object.fromEntries(planMove({ from, to, published, unpublished }));

test('a new hero moves before the actions and they shift one place', () => {
  const got = plan('DQ1-006', 'DQ1-003', new Set(), ids('DQ1', 1, 2, 3, 4, 5, 6));
  assert.deepEqual(got, { 'DQ1-006': 'DQ1-003', 'DQ1-003': 'DQ1-004', 'DQ1-004': 'DQ1-005', 'DQ1-005': 'DQ1-006' });
});

test('moving later shifts the cards in between back', () => {
  const got = plan('DQ1-002', 'DQ1-004', new Set(), ids('DQ1', 1, 2, 3, 4, 5));
  assert.deepEqual(got, { 'DQ1-002': 'DQ1-004', 'DQ1-003': 'DQ1-002', 'DQ1-004': 'DQ1-003' });
});

test('next to each other it is a swap', () => {
  assert.deepEqual(plan('DQ1-003', 'DQ1-002', new Set(), ids('DQ1', 1, 2, 3)), { 'DQ1-003': 'DQ1-002', 'DQ1-002': 'DQ1-003' });
});

test('published cards keep their codes and the others step over them', () => {
  // OP1-001..003 published; 004 and 006 new, 005 published.
  const got = plan('OP1-006', 'OP1-004', ids('OP1', 1, 2, 3, 5), ids('OP1', 4, 6));
  assert.deepEqual(got, { 'OP1-006': 'OP1-004', 'OP1-004': 'OP1-006' });
});

test('an empty code stops the shift', () => {
  // 003 is free: moving 005 to 002 moves only 002 into the gap.
  assert.deepEqual(plan('DQ1-005', 'DQ1-002', new Set(), ids('DQ1', 1, 2, 4, 5)), { 'DQ1-005': 'DQ1-002', 'DQ1-002': 'DQ1-003' });
  // A free code as the target just renames.
  assert.deepEqual(plan('DQ1-004', 'DQ1-009', new Set(), ids('DQ1', 1, 4)), { 'DQ1-004': 'DQ1-009' });
});

test('published cards and published targets are refused', () => {
  assert.throws(() => planMove({ from: 'OP1-002', to: 'OP1-001', published: ids('OP1', 1, 2), unpublished: new Set() }), /published/);
  assert.throws(() => planMove({ from: 'OP1-004', to: 'OP1-002', published: ids('OP1', 1, 2), unpublished: ids('OP1', 4) }), /OP1-002 is published/);
  assert.throws(() => planMove({ from: 'OP1-004', to: 'OP2-001', published: new Set(), unpublished: ids('OP1', 4) }), /set OP1/);
  assert.throws(() => planMove({ from: 'OP1-004', to: 'OP1-001', published: new Set(), unpublished: new Set() }), /save it first/);
  assert.equal(planMove({ from: 'OP1-004', to: 'OP1-004', published: new Set(), unpublished: ids('OP1', 4) }).size, 0);
});

test('the code typed in the prompt', () => {
  assert.equal(targetCode('DQ1', '5'), 'DQ1-005');
  assert.equal(targetCode('DQ1', ' 005 '), 'DQ1-005');
  assert.equal(targetCode('DQ1', 'dq1-012'), 'DQ1-012');
  assert.equal(targetCode('DQ1', 'OP1-012'), null);
  assert.equal(targetCode('DQ1', '0'), null);
  assert.equal(targetCode('DQ1', 'five'), null);
});

test('drafts, notes and combo ingredients follow the move', () => {
  const p = new Map([['DQ1-003', 'DQ1-002'], ['DQ1-002', 'DQ1-003']]);
  assert.deepEqual(renameKeys({ 'DQ1-002': 'b', 'DQ1-003': 'c', 'DQ1-001': 'a' }, p), { 'DQ1-001': 'a', 'DQ1-002': 'c', 'DQ1-003': 'b' });
  const d = moveDrafts({ 'DQ1-002': { name: 'B' }, 'DQ1-003': { name: 'C' }, 'CB-004': { ingredients: ['DQ1-003', 'OP1-001'] } }, p);
  assert.deepEqual(d['DQ1-002'], { name: 'C' });
  assert.deepEqual(d['CB-004'].ingredients, ['DQ1-002', 'OP1-001']);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setList, setRow, seriesNames, seriesOf, bySeries, pinnedCodes } from '../js/editor-sets.js';

test('sets: saved ones first by number, codes from cards fill in, Stage and Core are not sets', () => {
  const cards = [{ id: 'JO1-001' }, { id: 'OP1-001' }, { id: 'NR1-004' }, { id: 'Stage-001' }, { id: 'Core-001' }];
  const list = setList({ sets: [{ code: 'OP1', name: 'One Piece', number: 1, packSize: 10 }, { code: 'JO1', name: 'JoJo', number: 2, packSize: 12 }] }, cards);
  assert.deepEqual(list.map(s => [s.code, s.number, s.packSize]), [['OP1', 1, 10], ['JO1', 2, 12], ['NR1', 3, 10]]);
  assert.deepEqual(setList(null, []), []);
});

test('sets: a set keeps its series when it has one, and the series are offered once each', () => {
  assert.deepEqual(setRow({ code: 'DQ1', name: 'Disciples of Avan', number: 3, packSize: 10, series: ' Dragon Quest ' }),
    { code: 'DQ1', name: 'Disciples of Avan', number: 3, packSize: 10, series: 'Dragon Quest' });
  // No series, or only spaces: the field is left out. Work in progress stays last.
  assert.deepEqual(setRow({ code: 'OP1', name: 'One Piece', number: 1, packSize: 10, series: '  ' }), { code: 'OP1', name: 'One Piece', number: 1, packSize: 10 });
  assert.deepEqual(setRow({ code: 'DQ2', name: 'Dragon Knights', number: 4, packSize: 10, series: 'Dragon Quest', wip: true }),
    { code: 'DQ2', name: 'Dragon Knights', number: 4, packSize: 10, series: 'Dragon Quest', wip: true });
  assert.deepEqual(seriesNames([{ code: 'OP1' }, { code: 'DQ1', series: 'Dragon Quest' }, { code: 'JO1', series: 'JoJo' }, { code: 'DQ2', series: 'Dragon Quest ' }]), ['Dragon Quest', 'JoJo']);
});

test('sets: the set row groups sets by series, and pins are what the browser remembers of the sets that exist', () => {
  const list = [{ code: 'OP1', name: 'One Piece' }, { code: 'DQ1', name: 'Disciples of Avan', series: 'Dragon Quest' }, { code: 'JO1', name: 'JoJo', series: '  ' }, { code: 'DQ2', name: 'Dragon Knights', series: 'Dragon Quest' }];
  // A set that names no series stands under its own name.
  assert.equal(seriesOf(list[0]), 'One Piece');
  assert.equal(seriesOf(list[1]), 'Dragon Quest');
  assert.equal(seriesOf(list[2]), 'JoJo');
  assert.deepEqual(bySeries(list).map(([name, sets]) => [name, sets.map(s => s.code)]), [['One Piece', ['OP1']], ['Dragon Quest', ['DQ1', 'DQ2']], ['JoJo', ['JO1']]]);
  // Nothing remembered: every set is in the row. Remembered: those, less sets that are gone; none is none.
  assert.deepEqual(pinnedCodes(null, list), ['OP1', 'DQ1', 'JO1', 'DQ2']);
  assert.deepEqual(pinnedCodes(['DQ1', 'XX9', 'OP1'], list), ['DQ1', 'OP1']);
  assert.deepEqual(pinnedCodes([], list), []);
});

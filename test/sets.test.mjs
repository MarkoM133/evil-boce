import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setList, setRow, seriesNames } from '../js/editor-sets.js';

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

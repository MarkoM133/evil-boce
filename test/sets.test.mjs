import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setList } from '../js/editor-sets.js';

test('sets: saved ones first by number, codes from cards fill in, Stage and Core are not sets', () => {
  const cards = [{ id: 'JO1-001' }, { id: 'OP1-001' }, { id: 'NR1-004' }, { id: 'Stage-001' }, { id: 'Core-001' }];
  const list = setList({ sets: [{ code: 'OP1', name: 'One Piece', number: 1, packSize: 10 }, { code: 'JO1', name: 'JoJo', number: 2, packSize: 12 }] }, cards);
  assert.deepEqual(list.map(s => [s.code, s.number, s.packSize]), [['OP1', 1, 10], ['JO1', 2, 12], ['NR1', 3, 10]]);
  assert.deepEqual(setList(null, []), []);
});

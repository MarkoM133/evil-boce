import { test } from 'node:test';
import assert from 'node:assert/strict';
import { layoutBoxes } from '../js/editor-frames.js';

test('frames: boxes of a layout for the outline', () => {
  const boxes = layoutBoxes({
    size: [1500, 2100], artBox: [0, 64, 1500, 1170], title: { box: [250, 64, 1000, 128], size: 106 },
    bonus: { pwr: { icon: [966, 1170, 128, 128], value: [1094, 1170, 320, 128] } }, icons: { a: 'x.png' },
  });
  assert.deepEqual(boxes.map(b => b.name), ['artBox', 'title', 'bonus.pwr.icon', 'bonus.pwr.value']);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createFxWorker, sameFx } from '../server/fx-claude.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// A fake client: answers every request with the given JSON and keeps what it was asked.
function fakeClient(answer, extra = {}) {
  const calls = [];
  return {
    calls,
    beta: { messages: { create: async params => { calls.push(params); return { model: 'claude-opus-5-5', stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify(answer) }], ...extra }; } } },
  };
}

async function drive() {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'eb-fx-'));
  await fs.mkdir(path.join(dir, 'data', 'fx-requests'), { recursive: true });
  await fs.writeFile(path.join(dir, 'data', 'cards.json'), JSON.stringify({ version: 1, cards: [{ id: 'OP1-016', name: 'Mihawk', type: 'Assist', color: 'None', text: 'Battle Phase: x' }] }));
  return dir;
}

const request = (id, text, at = '2026-11-03T10:00:00.000Z') => ({ id, name: 'Test', type: 'Action', color: 'Red', text, who: 'Marko', at });

test('a request in the folder gets an answer next to it, checked by the game grammar', async () => {
  const dir = await drive();
  await fs.writeFile(path.join(dir, 'data', 'fx-requests', 'OP1-099.json'), JSON.stringify(request('OP1-099', 'Preroll Phase: A friendly Hero heals 3 HP.')));
  const client = fakeClient({ fx: 'PREROLL: HEAL FRIENDLY 3\nPREROLL: ZAP ENEMY 1', unsure: [], notes: 'Check the target.' });
  const w = createFxWorker({ root: ROOT, drive: dir, client, log: () => {} });
  await w.tick();
  const res = JSON.parse(await fs.readFile(path.join(dir, 'data', 'fx-claude', 'OP1-099.json'), 'utf8'));
  assert.equal(res.askedAt, '2026-11-03T10:00:00.000Z');
  assert.equal(res.askedText, 'Preroll Phase: A friendly Hero heals 3 HP.');
  assert.deepEqual(res.problems.map(p => p.line), ['PREROLL: ZAP ENEMY 1']);
  // The request is gone; the fx rules and the examples went into a cached system prompt.
  await assert.rejects(fs.access(path.join(dir, 'data', 'fx-requests', 'OP1-099.json')));
  const params = client.calls[0];
  assert.equal(params.model, 'claude-opus-5-5');
  assert.equal(params.system[0].cache_control.type, 'ephemeral');
  assert.match(params.system[0].text, /fx-keywords\.md/);
  assert.equal(params.output_config.format.type, 'json_schema');
});

test('a refusal or a bad code is answered with an error, not a crash', async () => {
  const dir = await drive();
  await fs.writeFile(path.join(dir, 'data', 'fx-requests', 'OP1-100.json'), JSON.stringify(request('OP1-100', 'Some text.')));
  await fs.writeFile(path.join(dir, 'data', 'fx-requests', 'bad.json'), JSON.stringify(request('../../evil', 'x')));
  const w = createFxWorker({ root: ROOT, drive: dir, client: fakeClient({}, { stop_reason: 'refusal', content: [] }), log: () => {} });
  await w.tick();
  const res = JSON.parse(await fs.readFile(path.join(dir, 'data', 'fx-claude', 'OP1-100.json'), 'utf8'));
  assert.match(res.error, /declined/);
  assert.deepEqual(await fs.readdir(path.join(dir, 'data', 'fx-requests')), []);
  assert.deepEqual((await fs.readdir(path.join(dir, 'data', 'fx-claude'))).sort(), ['OP1-100.json']);
});

test('missing words go on the fx wishlist, one item per word with every card that needs it', async () => {
  const dir = await drive();
  const ext = { kind: 'verb', word: 'STEAL_ENERGY <ME|OPP> <n>', meaning: 'Moves n energy from that player to you.', why: 'DISCHARGE only removes it.', fx: 'PLAY: STEAL_ENERGY OPP 2' };
  for (const id of ['OP1-101', 'OP1-102']) {
    await fs.writeFile(path.join(dir, 'data', 'fx-requests', `${id}.json`), JSON.stringify(request(id, 'Steal 2 Energy.')));
  }
  const answer = { fx: '', unsure: ['Steal 2 Energy: no verb moves energy between players.'], notes: '', extensions: [ext, { ...ext, kind: 'rule', word: 'Energy theft', meaning: 'x', why: 'y', fx: '' }] };
  const w = createFxWorker({ root: ROOT, drive: dir, client: fakeClient(answer), log: () => {} });
  await w.tick();
  const list = JSON.parse(await fs.readFile(path.join(dir, 'data', 'fx-wishlist.json'), 'utf8'));
  const verb = list.items.find(i => i.key === 'verb:STEAL_ENERGY');
  assert.deepEqual(verb.cards.map(c => c.id).sort(), ['OP1-101', 'OP1-102']);
  assert.equal(verb.status, 'open');
  assert.ok(list.items.find(i => i.kind === 'rule'));
  // Asked again for the same card: still one entry for it.
  await fs.writeFile(path.join(dir, 'data', 'fx-requests', 'OP1-101.json'), JSON.stringify(request('OP1-101', 'Steal 2 Energy.', '2026-11-03T11:00:00.000Z')));
  await w.tick();
  const again = JSON.parse(await fs.readFile(path.join(dir, 'data', 'fx-wishlist.json'), 'utf8'));
  assert.equal(again.items.find(i => i.key === 'verb:STEAL_ENERGY').cards.length, 2);
});

test("Claude's own reading is compared with the game's, and Claude never sees the game's", async () => {
  assert.ok(sameFx('PLAY: HEAL SELF 2\nEND: DRAW ME 1', ' end:  draw me 1 \nplay: heal self 2'));
  assert.ok(!sameFx('PLAY: HEAL SELF 2', 'PLAY: HEAL SELF 3'));
  const dir = await drive();
  await fs.writeFile(path.join(dir, 'data', 'fx-requests', 'OP1-001.json'), JSON.stringify({ ...request('OP1-001', 'Luffy may activate a Core.'), read: 'POSTROLL ONCE OPTIONAL RANGE: ACTIVATE_CORE' }));
  const client = fakeClient({ fx: 'POSTROLL ONCE OPTIONAL RANGE: ACTIVATE_CORE', unsure: [], notes: '', extensions: [] });
  const w = createFxWorker({ root: ROOT, drive: dir, client, log: () => {} });
  await w.tick();
  const res = JSON.parse(await fs.readFile(path.join(dir, 'data', 'fx-claude', 'OP1-001.json'), 'utf8'));
  assert.equal(res.agree, true);
  assert.doesNotMatch(client.calls[0].messages[0].content, /ACTIVATE_CORE/);
});

test('Check text: a request in text-requests gets the rewrite next to it, with the text guide in the prompt', async () => {
  const dir = await drive();
  await fs.mkdir(path.join(dir, 'data', 'text-requests'), { recursive: true });
  await fs.mkdir(path.join(dir, 'data', 'editor'), { recursive: true });
  await fs.writeFile(path.join(dir, 'data', 'editor', 'text-guide.json'), JSON.stringify({ phrases: [], avoid: [{ find: '\\bfor every\\b', say: 'Count with "for each".' }] }));
  const asked = 'Battle Phase: Your Hero gains +1000 Power for every {Sword}.';
  await fs.writeFile(path.join(dir, 'data', 'text-requests', 'OP1-120.json'), JSON.stringify(request('OP1-120', asked)));
  const client = fakeClient({ verdict: 'changes', text: 'Battle Phase: Your Hero gets +1000 Power for each {Sword}.\n',
    issues: [{ quote: 'gains', problem: 'A stat bonus is "gets".', rule: 'gets for stats' }, { quote: 'for every', problem: 'Count with "for each".', rule: 'for each' }],
    questions: ['Until the end of the turn?'], notes: '' });
  const w = createFxWorker({ root: ROOT, drive: dir, client, log: () => {} });
  await w.tick();
  const res = JSON.parse(await fs.readFile(path.join(dir, 'data', 'text-claude', 'OP1-120.json'), 'utf8'));
  assert.equal(res.verdict, 'changes');
  assert.equal(res.text, 'Battle Phase: Your Hero gets +1000 Power for each {Sword}.');
  assert.equal(res.askedText, asked);
  assert.equal(res.issues.length, 2);
  assert.deepEqual(res.questions, ['Until the end of the turn?']);
  await assert.rejects(fs.access(path.join(dir, 'data', 'text-requests', 'OP1-120.json')));
  // Nothing went to the fx side.
  await assert.rejects(fs.access(path.join(dir, 'data', 'fx-claude', 'OP1-120.json')));
  const params = client.calls[0];
  assert.match(params.system[0].text, /house text guide/);
  assert.match(params.system[0].text, /Count with "for each"/);
  assert.match(params.messages[0].content, /Check the text of this card/);
});

test('Check text: "changes" with the same text is an ok, and its issues go', async () => {
  const dir = await drive();
  await fs.mkdir(path.join(dir, 'data', 'text-requests'), { recursive: true });
  const asked = 'Battle Phase: Your Hero gets +1000 Power.';
  await fs.writeFile(path.join(dir, 'data', 'text-requests', 'OP1-121.json'), JSON.stringify(request('OP1-121', asked)));
  const client = fakeClient({ verdict: 'changes', text: asked, issues: [{ quote: 'x', problem: 'y', rule: 'z' }], questions: [], notes: '' });
  const w = createFxWorker({ root: ROOT, drive: dir, client, log: () => {} });
  await w.tick();
  const res = JSON.parse(await fs.readFile(path.join(dir, 'data', 'text-claude', 'OP1-121.json'), 'utf8'));
  assert.equal(res.verdict, 'ok');
  assert.deepEqual(res.issues, []);
});

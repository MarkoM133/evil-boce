// Claude predlaže fx (GDD 14: Claude predlaže, Marko potvrđuje), a ključ ostaje samo na ovom računalu.
// Card Studio (kod Marka ili Tarika) zapiše zahtjev u data/fx-requests/<kod>.json u zajedničkom folderu;
// ovaj radnik ga vidi, pita Claude API, provjeri retke gramatikom igre i zapiše odgovor u
// data/fx-claude/<kod>.json; Syncthing ga vrati onome tko je pitao. Bez ključa radnik ne radi ništa.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import Anthropic from '@anthropic-ai/sdk';
import { fxProblems } from '../js/fx-grammar.js';

const MODEL = 'claude-opus-5-5';
const POLL_MS = 4000;
const CODE_RE = /^[A-Za-z0-9][A-Za-z0-9-]{0,40}$/;

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['fx', 'unsure', 'notes'],
  properties: {
    fx: { type: 'string', description: 'The fx lines for the card, one effect per line; empty when the card needs none.' },
    unsure: { type: 'array', items: { type: 'string' }, description: 'Sentences of the card text the fx could not express exactly, each with why.' },
    notes: { type: 'string', description: 'One or two sentences for the person confirming: what to check.' },
  },
};

const hashText = s => crypto.createHash('sha1').update(String(s ?? '')).digest('hex').slice(0, 12);

async function readJson(file, fallback = null) {
  try { return JSON.parse(await fs.readFile(file, 'utf8')); } catch (e) { if (e.code === 'ENOENT') return fallback; throw e; }
}

// Pravila fx jezika i primjeri: ručno napisani fx iz igre uz tekst te karte iz baze. Stabilno, pa se kešira.
async function systemPrompt(root, drive) {
  const rules = await fs.readFile(path.join(root, 'game', 'docs', 'fx-keywords.md'), 'utf8');
  const hand = await readJson(path.join(root, 'game', 'data', 'placeholders', 'card_fx.json'), {});
  const db = await readJson(path.join(drive, 'data', 'cards.json'), { cards: [] });
  const byId = new Map(db.cards.map(c => [c.id, c]));
  const examples = Object.entries(hand).filter(([id]) => byId.get(id)?.text).slice(0, 30)
    .map(([id, fx]) => { const c = byId.get(id); return `Card ${id} "${c.name}" (${c.type}, ${c.color})\nText: ${c.text}\nfx:\n${fx}`; });
  return [
    'You translate the text of Evil Boće cards into the fx language the game runs. The language is defined below;',
    'use only its words, targets and verbs. Write one effect per line. Keep the meaning of the text exactly: when a',
    'sentence cannot be said in fx, leave it out of fx and list it under "unsure" with the reason. A card whose text',
    'needs nothing (or that the game reads by itself) may get an empty fx. A person checks every proposal before the game uses it.',
    '',
    '# The fx language (game/docs/fx-keywords.md)',
    rules,
    '',
    '# Confirmed examples (text and the fx the game uses for it)',
    examples.join('\n\n'),
  ].join('\n');
}

// Radnik bez rasporeda: tick() obradi sve zahtjeve koji čekaju (testovi ga zovu s lažnim klijentom).
export function createFxWorker({ root, drive, client, log = console.log }) {
  const reqDir = path.join(drive, 'data', 'fx-requests');
  const outDir = path.join(drive, 'data', 'fx-claude');
  let busy = false;

  async function answer(file) {
    const req = await readJson(file);
    const id = String(req?.id ?? '');
    if (!CODE_RE.test(id) || !req?.text) { await fs.rm(file, { force: true }); return; }
    const out = path.join(outDir, `${id}.json`);
    const textHash = hashText(req.text);
    const before = await readJson(out);
    if (before && before.textHash === textHash && before.askedAt === req.at && !before.error) { await fs.rm(file, { force: true }); return; }
    log(`fx: asking Claude for ${id} (${req.who || '?'})`);
    let result;
    try {
      const card = { id, name: req.name, type: req.type, color: req.color, bonusColors: req.bonusColors, hero: req.hero, cost: req.cost, traits: req.traits, text: req.text };
      const msg = await client.beta.messages.create({
        model: MODEL,
        max_tokens: 16000,
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default',
        output_config: { effort: 'high', format: { type: 'json_schema', schema: SCHEMA } },
        system: [{ type: 'text', text: await systemPrompt(root, drive), cache_control: { type: 'ephemeral' } }],
        messages: [{ role: 'user', content: `Propose the fx for this card:\n${JSON.stringify(card, null, 2)}` }],
      });
      if (msg.stop_reason === 'refusal') throw new Error('Claude declined this card');
      const text = msg.content.find(b => b.type === 'text')?.text ?? '';
      const parsed = JSON.parse(text);
      const fx = String(parsed.fx ?? '').trim();
      result = { id, at: new Date().toISOString(), askedAt: req.at, who: req.who, textHash, askedText: req.text, model: msg.model, fx, unsure: parsed.unsure ?? [], notes: parsed.notes ?? '', problems: fxProblems(fx) };
    } catch (e) {
      result = { id, at: new Date().toISOString(), askedAt: req.at, who: req.who, textHash, error: e?.message ?? String(e) };
    }
    await fs.mkdir(outDir, { recursive: true });
    await fs.writeFile(out, JSON.stringify(result, null, 2) + '\n');
    await fs.rm(file, { force: true });
    log(`fx: ${id} ${result.error ? 'failed: ' + result.error : 'answered'}`);
  }

  async function tick() {
    if (busy) return;
    busy = true;
    try {
      const names = (await fs.readdir(reqDir).catch(() => [])).filter(n => n.endsWith('.json'));
      for (const n of names) await answer(path.join(reqDir, n)).catch(e => log(`fx: ${n}: ${e.message}`));
    } finally {
      busy = false;
    }
  }

  return { tick, reqDir, outDir };
}

export function startFxWorker({ root, drive, apiKey, log = console.log }) {
  if (!apiKey && !process.env.ANTHROPIC_API_KEY) {
    log('fx: no "anthropicApiKey" in config.local.json, so Claude does not propose fx');
    return;
  }
  const client = new Anthropic(apiKey ? { apiKey } : {});
  const w = createFxWorker({ root, drive, client, log });
  setInterval(w.tick, POLL_MS);
  w.tick();
  log(`fx: Claude proposals on (${MODEL}), watching ${w.reqDir}`);
}

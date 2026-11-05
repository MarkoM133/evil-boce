// Card editor › Text guide: fraze i pravila teksta karata kao podatak (data/editor/text-guide.json).
// Editor iz njega radi gumbe fraza, prijedloge dok pišeš i upozorenja; md vodič se izvozi odavde.
import * as fs from './fsdir.js';

export const GUIDE_PATH = 'data/editor/text-guide.json';
const EMPTY = { version: 1, intro: '', phrases: [], avoid: [] };
// "[" nudi Range i riječi statova (karta ih crta kao ikone iza broja).
const BRACKET = [['[Range]', '[Range] '], ['Power', 'Power'], ['DMG', 'DMG'], ['HP', 'HP'], ['Range', 'Range'], ['Knockback', 'Knockback']];

export async function readGuide(store) {
  try {
    if (store.kind === 'folder') return { ...EMPTY, ...JSON.parse((await fs.readText(store.root, GUIDE_PATH)) ?? '{}') };
    const r = await fetch(GUIDE_PATH, { cache: 'no-store' });
    return r.ok ? { ...EMPTY, ...(await r.json()) } : { ...EMPTY };
  } catch {
    return { ...EMPTY };
  }
}

// Upozorenja iz pravila vodiča ("push" → Knockback …); pokvaren regex se preskače.
export function avoidWarnings(guide, text) {
  const out = [];
  for (const rule of guide?.avoid ?? []) {
    let re;
    // flags: "" makes a rule case-sensitive ("Once per turn" vs "Once Per Turn"); the default ignores case.
    try { re = new RegExp(rule.find, rule.flags ?? 'i'); } catch { continue; }
    if (re.test(text ?? '')) out.push(rule.say);
  }
  return out;
}

// Prijedlozi za riječ ispred kursora: "[" nudi Range i statove, a 2+ slova fraze koje tako počinju.
// Vraća { from, items: [{ label, insert }] }; from je početak dijela koji prijedlog zamijeni.
export function suggest(guide, text, caret) {
  const before = (text ?? '').slice(0, caret);
  if (before.endsWith('[')) return { from: caret - 1, items: BRACKET.map(([label, insert]) => ({ label, insert: insert.startsWith('[') ? insert : ` ${insert}` })) };
  const m = /([A-Za-z{][\w'{}]*(?: [\w'{}]+){0,3})$/.exec(before);
  if (!m) return { from: caret, items: [] };
  // Najduži kraj teksta (do 4 riječi) koji je početak neke fraze.
  const words = m[1].split(' ');
  for (let i = 0; i < words.length; i++) {
    const part = words.slice(i).join(' ');
    if (part.length < 2) continue;
    const low = part.toLowerCase();
    const items = (guide?.phrases ?? []).filter(p => p.text.toLowerCase().startsWith(low) && p.text.length > part.length)
      .slice(0, 6).map(p => ({ label: p.text.trim(), insert: p.text }));
    if (items.length) return { from: caret - part.length, items };
  }
  return { from: caret, items: [] };
}

export function guideMarkdown(guide) {
  const esc = s => String(s ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ⏎ ');
  return [
    '# Evil Boće – card text guide',
    '',
    guide.intro ?? '',
    '',
    '## Form',
    '',
    '```',
    '<Phase>: <effect>.',
    '<Phase> Once Per Turn: <effect>.',
    '<Phase>: If <condition>, <effect>.',
    '```',
    '',
    'Phases: Start Phase, Preroll Phase, Roll Phase, Postroll Phase, Battle Phase, End Phase. No phase = a lasting effect. `[Range]` at the start = in this Hero\'s range.',
    'Stats are words right after the number (`3 HP`, `+2000 Power`, `takes 3 DMG`); the card shows them as icons. Traits in braces: `{Sword}`.',
    '',
    '## Phrases (use exactly)',
    '',
    '| What | Phrase | Note |',
    '|---|---|---|',
    ...(guide.phrases ?? []).map(p => `| ${esc(p.label)} | \`${esc(p.text.trim())}\` | ${esc(p.note)} |`),
    '',
    '## Avoid',
    '',
    ...(guide.avoid ?? []).map(a => `- ${a.say}`),
    '',
  ].join('\n');
}

// ctx: { h, store, canWrite, who, render, guard, toast, onSaved(guide) }
export function createGuideView(ctx) {
  const { h } = ctx;
  const v = { guide: null, loading: false, dirty: false };

  async function load() {
    if (v.loading) return;
    v.loading = true;
    v.guide = await readGuide(ctx.store());
    v.loading = false;
    ctx.render();
  }

  async function save() {
    const g = { ...v.guide, updated: new Date().toISOString(), who: ctx.who() || undefined };
    for (const rule of g.avoid) {
      try { new RegExp(rule.find, 'i'); } catch { throw new Error(`Not a valid pattern: ${rule.find}`); }
    }
    g.phrases = g.phrases.filter(p => p.text.trim());
    g.avoid = g.avoid.filter(a => a.find.trim() && a.say.trim());
    await fs.writeFile(ctx.store().root, GUIDE_PATH, JSON.stringify(g, null, 2) + '\n');
    v.guide = g;
    v.dirty = false;
    ctx.onSaved(g);
    ctx.toast('Text guide saved. The editor uses it right away.');
    ctx.render();
  }

  function exportMd() {
    const blob = new Blob([guideMarkdown(v.guide)], { type: 'text/markdown' });
    const a = h('a', { href: URL.createObjectURL(blob), download: 'Evil Boce - card text guide.md' });
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 5000);
  }

  function render() {
    if (!v.guide) {
      load();
      return h('section', { class: 'panel' }, h('p', { class: 'muted' }, 'Loading the text guide…'));
    }
    const g = v.guide;
    const edit = (obj, k) => e => { obj[k] = e.target.value; v.dirty = true; };
    return h('section', { class: 'panel ce-guide' },
      h('div', { class: 'ce-title' }, h('h2', {}, 'Card text guide')),
      h('p', { class: 'muted' }, 'Phrases the game reads and the editor offers (buttons, suggestions while typing), and words to avoid (warnings). Saved in data/editor/text-guide.json.'),
      h('label', { class: 'ce-field' }, h('span', {}, 'Intro'), h('textarea', { rows: 2, value: g.intro ?? '', oninput: edit(g, 'intro') })),
      h('h3', {}, 'Phrases'),
      h('table', { class: 'ce-pub-table' },
        h('thead', {}, h('tr', {}, ['What', 'Phrase', 'Note', ''].map(t => h('th', {}, t)))),
        h('tbody', {}, g.phrases.map((p, i) => h('tr', {},
          h('td', {}, h('input', { value: p.label ?? '', oninput: edit(p, 'label') })),
          h('td', {}, h('input', { value: p.text ?? '', oninput: edit(p, 'text') })),
          h('td', {}, h('input', { value: p.note ?? '', oninput: edit(p, 'note') })),
          h('td', {}, h('button', { class: 'ghost', type: 'button', onclick: () => { g.phrases.splice(i, 1); v.dirty = true; ctx.render(); } }, '✕')))))),
      h('button', { class: 'ghost', type: 'button', onclick: () => { g.phrases.push({ label: '', text: '', note: '' }); ctx.render(); } }, '+ Phrase'),
      h('h3', {}, 'Avoid'),
      h('table', { class: 'ce-pub-table' },
        h('thead', {}, h('tr', {}, ['Pattern (regular expression)', 'Warning', ''].map(t => h('th', {}, t)))),
        h('tbody', {}, g.avoid.map((a, i) => h('tr', {},
          h('td', {}, h('input', { value: a.find ?? '', oninput: edit(a, 'find') })),
          h('td', {}, h('input', { value: a.say ?? '', oninput: edit(a, 'say') })),
          h('td', {}, h('button', { class: 'ghost', type: 'button', onclick: () => { g.avoid.splice(i, 1); v.dirty = true; ctx.render(); } }, '✕')))))),
      h('button', { class: 'ghost', type: 'button', onclick: () => { g.avoid.push({ find: '', say: '' }); ctx.render(); } }, '+ Rule'),
      h('div', { class: 'ce-actions' },
        h('button', { class: 'primary', type: 'button', disabled: !ctx.canWrite(), onclick: () => ctx.guard(save) }, 'Save guide'),
        h('button', { class: 'ghost', type: 'button', onclick: exportMd }, 'Export .md'),
        ctx.canWrite() ? null : h('small', { class: 'muted' }, 'Saving needs the shared folder (Chrome or Edge on a computer), or Card Studio opened through Marko\'s computer.')));
  }

  return { render, isDirty: () => v.dirty };
}

// Card editor › Sets: postavke seta (naziv, broj, karata u paketu, slika paketa, pozadina za Draft)
// i karte seta. Podaci su u data/sets/sets.json, slike u data/sets/<kod>/ (Syncthing, ne git).
// "default" je paket za Draft iz više setova (crni, s logom). Igra će ih čitati u Draftu.
import * as fs from './fsdir.js';

export const SETS_PATH = 'data/sets/sets.json';
const NOT_SETS = ['Stage', 'Core'];
const CODE_RE = /^[A-Z]{2,4}\d{1,2}$/;
const DEFAULT_PACK = 10;

// Setovi: iz sets.json i iz kodova karata (OP1-001 → OP1), redom po broju seta.
export function setList(saved, cards) {
  const byCode = new Map((saved?.sets ?? []).map(s => [s.code, { ...s }]));
  for (const c of cards) {
    const code = c.id.split('-')[0];
    if (NOT_SETS.includes(code) || byCode.has(code)) continue;
    byCode.set(code, { code, name: code, number: null, packSize: DEFAULT_PACK });
  }
  const list = [...byCode.values()];
  let n = Math.max(0, ...list.map(s => s.number ?? 0));
  for (const s of list) s.number ??= ++n;
  return list.sort((a, b) => a.number - b.number || a.code.localeCompare(b.code));
}

// ctx: { h, state, store, canWrite, who, render, guard, toast, go, newCard }
export function createSetsView(ctx) {
  const { h } = ctx;
  const v = { saved: null, loading: false, code: null, urls: {} };

  async function load() {
    if (v.loading) return;
    v.loading = true;
    try {
      if (ctx.store().kind === 'folder') v.saved = JSON.parse((await fs.readText(ctx.store().root, SETS_PATH)) ?? '{"sets":[]}');
      else {
        const r = await fetch(SETS_PATH, { cache: 'no-store' });
        v.saved = r.ok ? await r.json() : { sets: [] };
      }
    } catch {
      v.saved = { sets: [] };
    }
    v.loading = false;
    ctx.render();
  }

  async function imageUrl(code, name) {
    const key = `${code}/${name}`;
    if (!(key in v.urls)) v.urls[key] = (await ctx.store().dataUrl(`sets/${key}`).catch(() => null)) ?? null;
    return v.urls[key];
  }

  async function save(sets) {
    const fresh = JSON.parse((await fs.readText(ctx.store().root, SETS_PATH)) ?? '{"sets":[]}');
    fresh.sets = sets.map(({ code, name, number, packSize }) => ({ code, name, number, packSize }));
    fresh.updated = new Date().toISOString();
    fresh.who = ctx.who() || undefined;
    await fs.writeFile(ctx.store().root, SETS_PATH, JSON.stringify(fresh, null, 2) + '\n');
    v.saved = fresh;
  }

  async function upload(code, name, file) {
    if (!file) return;
    if (file.type !== 'image/png' && file.type !== 'image/jpeg' && file.type !== 'image/webp') throw new Error('The image must be PNG, JPEG or WebP.');
    // Uvijek .png u imenu: igra traži stalno ime (preglednik ga ionako dekodira po sadržaju).
    await fs.writeFile(ctx.store().root, `data/sets/${code}/${name}`, new Uint8Array(await file.arrayBuffer()));
    ctx.store().dropImageUrls?.();
    delete v.urls[`${code}/${name}`];
    ctx.toast(`Saved data/sets/${code}/${name}.`);
    ctx.render();
  }

  function render() {
    if (!v.saved) {
      load();
      return h('section', { class: 'panel' }, h('p', { class: 'muted' }, 'Loading the sets…'));
    }
    const cards = ctx.state.db.cards.filter(c => !c.deleted);
    const sets = setList(v.saved, cards);
    v.code ??= sets[0]?.code ?? 'default';
    const cur = v.code === 'default' ? null : sets.find(s => s.code === v.code);
    return h('div', { class: 'card-editor ce-sets' },
      h('aside', { class: 'ce-list' },
        h('ul', {}, [...sets.map(s => h('li', {}, h('button', { class: `ce-item${s.code === v.code ? ' active' : ''}`, type: 'button', onclick: () => { v.code = s.code; ctx.render(); } },
          h('span', { class: 'ce-id' }, `SET ${String(s.number).padStart(2, '0')}`), ' ', s.name, h('span', { class: 'muted small' }, ` · ${s.code}`)))),
        h('li', {}, h('button', { class: `ce-item${v.code === 'default' ? ' active' : ''}`, type: 'button', onclick: () => { v.code = 'default'; ctx.render(); } }, 'Default pack'))]),
        newSetForm(sets)),
      cur ? renderSet(cur, sets, cards) : renderDefault());
  }

  function newSetForm(sets) {
    const input = h('input', { placeholder: 'Code, e.g. NR1', maxlength: 6 });
    return h('div', { class: 'ce-new-form' }, input,
      h('div', { class: 'ce-list-head' },
        h('button', { class: 'ghost', type: 'button', disabled: !ctx.canWrite(), onclick: () => ctx.guard(async () => {
          const code = input.value.trim().toUpperCase();
          if (!CODE_RE.test(code)) throw new Error('A set code is 2–4 capital letters and a number, e.g. OP2 or NR1.');
          if (sets.some(s => s.code === code)) throw new Error(`Set ${code} already exists.`);
          await save([...sets, { code, name: code, number: Math.max(0, ...sets.map(s => s.number)) + 1, packSize: DEFAULT_PACK }]);
          v.code = code;
          ctx.render();
        }) }, '+ New set')));
  }

  function imageField(code, name, label, hint) {
    const img = h('img', { class: 'ce-set-img', alt: label });
    const none = () => img.replaceWith(h('div', { class: 'ce-set-img empty' }, 'none yet'));
    img.onerror = none;
    imageUrl(code, name).then(u => { if (u) img.src = u; else none(); });
    return h('div', { class: 'ce-field' }, h('span', {}, label), img,
      h('input', { type: 'file', accept: 'image/png,image/jpeg,image/webp', disabled: !ctx.canWrite(), onchange: e => ctx.guard(() => upload(code, name, e.target.files[0])) }),
      h('small', { class: 'muted' }, `data/sets/${code}/${name}${hint ? ` · ${hint}` : ''}`));
  }

  function renderSet(s, sets, cards) {
    const mine = cards.filter(c => c.id.startsWith(`${s.code}-`)).sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
    const byType = {};
    for (const c of mine) byType[c.type] = (byType[c.type] ?? 0) + 1;
    const work = { ...s };
    const field = (label, input, hint) => h('label', { class: 'ce-field' }, h('span', {}, label), input, hint ? h('small', { class: 'muted' }, hint) : null);
    return h('section', { class: 'ce-form ce-set' },
      h('div', { class: 'ce-title' }, h('h2', {}, `SET ${String(s.number).padStart(2, '0')} · ${s.code}`)),
      h('div', { class: 'ce-row' },
        field('Name', h('input', { value: s.name, oninput: e => { work.name = e.target.value; } })),
        field('Set number', h('input', { type: 'number', min: 1, value: s.number, oninput: e => { work.number = Number(e.target.value) || s.number; } })),
        field('Cards per pack', h('input', { type: 'number', min: 1, max: 30, value: s.packSize ?? DEFAULT_PACK, oninput: e => { work.packSize = Number(e.target.value) || DEFAULT_PACK; } }), 'Draft packs.')),
      h('div', { class: 'ce-actions' },
        h('button', { class: 'primary', type: 'button', disabled: !ctx.canWrite(), onclick: () => ctx.guard(async () => {
          await save(sets.map(x => (x.code === s.code ? work : x)));
          ctx.toast(`Set ${s.code} saved.`);
          ctx.render();
        }) }, 'Save set'),
        h('button', { class: 'ghost', type: 'button', onclick: () => ctx.newCard(s.code, 'Action') }, '+ New card in this set'),
        ctx.canWrite() ? null : h('small', { class: 'muted' }, 'Saving needs the shared folder (Chrome or Edge on a computer).')),
      h('div', { class: 'ce-row' },
        imageField(s.code, 'pack.png', 'Pack', 'the booster in Draft'),
        imageField(s.code, 'draft-bg.png', 'Draft background', 'behind the pack while it opens')),
      h('h3', {}, `${mine.length} cards`),
      h('p', { class: 'muted small' }, Object.entries(byType).map(([t, n]) => `${n} ${t}`).join(' · ') || 'No cards yet.'),
      h('ul', { class: 'ce-set-cards' }, mine.map(c => h('li', {},
        h('button', { class: 'ce-item', type: 'button', onclick: () => ctx.go(c.id) },
          h('span', { class: `ce-dot c-bg-${c.color}` }), h('span', { class: 'ce-id' }, c.id), ' ', c.name, h('span', { class: 'muted small' }, ` · ${c.type}`))))));
  }

  function renderDefault() {
    return h('section', { class: 'ce-form ce-set' },
      h('div', { class: 'ce-title' }, h('h2', {}, 'Default pack')),
      h('p', { class: 'muted' }, 'The pack for a Draft that mixes several sets (black, with the logo).'),
      h('div', { class: 'ce-row' },
        imageField('default', 'pack.png', 'Pack'),
        imageField('default', 'draft-bg.png', 'Draft background')));
  }

  return { render, reload: () => { v.saved = null; v.urls = {}; } };
}

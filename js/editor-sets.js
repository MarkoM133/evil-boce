// Card editor › Sets (mockup "06 Card editor - Sets"): kartice setova sa sličicom paketa, zaglavlje seta,
// filteri i mreža nacrtanih karata sa statusom (DONE, REVIEW, NEEDS FX, lock), pločica "New card" s idućim kodom.
// Stageovi i Coreovi imaju svoje kartice. Postavke seta su u data/sets/sets.json, slike u data/sets/<kod>/
// (Syncthing, ne git); "default" je paket za Draft iz više setova. Igra će ih čitati u Draftu.
import * as fs from './fsdir.js';

export const SETS_PATH = 'data/sets/sets.json';
const NOT_SETS = ['Stage', 'Core'];
const CODE_RE = /^[A-Z]{2,4}\d{1,2}$/;
const DEFAULT_PACK = 10;
const TYPES = ['Hero', 'Evolution', 'Action', 'Equipment', 'Assist'];
const NEW_TYPES = TYPES;
const COLORS = ['Cyan', 'Yellow', 'Purple', 'Red', 'Blue', 'Green'];
const STATUS_FILTERS = [['', 'All statuses'], ['draft', 'Draft'], ['review', 'Review'], ['done', 'Done'], ['fx', 'Needs fx'], ['edited', 'Unpublished changes'], ['noart', 'No art']];

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

// ctx: { h, state, store, canWrite, who, render, guard, toast, cards(), drafts(), locks(), thumbInto(canvas, card, px), go(id), newCard(set, type), nextId(set) }
export function createSetsView(ctx) {
  const { h } = ctx;
  const v = { saved: null, loading: false, code: null, urls: {}, q: '', type: '', color: '', status: '', settings: false };

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
    // Samo nađene slike se pamte: pack.png koji Syncthing donese kasnije se vidi pri idućem crtanju.
    if (!v.urls[key]) v.urls[key] = (await ctx.store().dataUrl(`sets/${key}`).catch(() => null)) ?? null;
    return v.urls[key];
  }

  // def: { packSize } of the default pack (a Draft that mixes sets); left as it is when not given.
  // Spremanje mijenja samo zadani set (one: { code, name, number, packSize }) u svježe pročitanoj datoteci,
  // da ne pregazi set koji je drugi stroj dodao ili promijenio u međuvremenu. def: veličina default paketa.
  async function save(one, def = null) {
    const text = await fs.readText(ctx.store().root, SETS_PATH);
    let fresh;
    try { fresh = text?.trim() ? JSON.parse(text) : { sets: [] }; } catch { throw new Error('sets.json is being written right now. Try again in a moment.'); }
    fresh.sets ??= [];
    if (one) {
      const row = { code: one.code, name: one.name, number: one.number, packSize: one.packSize };
      const i = fresh.sets.findIndex(x => x.code === one.code);
      if (i >= 0) fresh.sets[i] = row; else fresh.sets.push(row);
    }
    if (def) fresh.default = def;
    fresh.updated = new Date().toISOString();
    fresh.who = ctx.who() || undefined;
    await fs.writeFile(ctx.store().root, SETS_PATH, JSON.stringify(fresh, null, 2) + '\n');
    v.saved = fresh;
  }

  async function upload(code, name, file) {
    if (!file) return;
    if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) throw new Error('The image must be PNG, JPEG or WebP.');
    // Uvijek isto ime: igra traži stalno ime (preglednik ga ionako dekodira po sadržaju).
    await fs.writeFile(ctx.store().root, `data/sets/${code}/${name}`, new Uint8Array(await file.arrayBuffer()));
    ctx.store().dropImageUrls?.();
    delete v.urls[`${code}/${name}`];
    ctx.toast(`Saved data/sets/${code}/${name}.`);
    ctx.render();
  }

  const sets = () => setList(v.saved, ctx.state.db.cards.filter(c => !c.deleted));
  const nameOf = code => (code === 'Stage' ? 'Stages' : code === 'Core' ? 'Cores' : sets().find(s => s.code === code)?.name ?? code);

  function packImg(code, cls) {
    const img = h('img', { class: cls, alt: '' });
    img.onerror = () => img.replaceWith(h('span', { class: `${cls} empty` }));
    imageUrl(code, 'pack.png').then(u => { if (u) img.src = u; else img.onerror(); });
    return img;
  }

  function render() {
    if (!v.saved) {
      load();
      return h('section', { class: 'panel' }, h('p', { class: 'muted' }, 'Loading the sets…'));
    }
    const list = sets();
    v.code ??= list[0]?.code ?? 'Stage';
    // Lijevo setovi | Stages, Cores; desno rijetke stvari: Draft packs (default paket) i + New set (Marko 2026-11-03).
    const tab = ([code, label]) => h('button', { type: 'button', class: code === v.code ? 'active' : '', onclick: () => { v.code = code; ctx.render(); } },
      NOT_SETS.includes(code) ? null : packImg(code, 'ce-settab-pack'), label);
    return h('div', { class: 'ce-page ce-sets' },
      h('nav', { class: 'ce-settabs' },
        list.map(s => tab([s.code, `${s.name} · ${s.code}`])),
        h('span', { class: 'ce-settab-sep', 'aria-hidden': 'true' }),
        tab(['Stage', 'Stages']), tab(['Core', 'Cores']),
        h('span', { class: 'ce-settab-rest' },
          h('button', { type: 'button', class: `ce-settab-pref${v.code === 'default' ? ' active' : ''}`, title: 'Name, number, pack size, pack image and Draft background of every set, and of packs that mix sets', onclick: () => { v.code = 'default'; v.focus = null; ctx.render(); } }, '⚙ Sets & packs'),
          newSetButton(list))),
      v.code === 'default' ? renderAllSettings(list) : renderSet(list.find(s => s.code === v.code) ?? { code: v.code, name: nameOf(v.code) }, list));
  }

  function newSetButton(list) {
    return h('button', { type: 'button', class: 'ce-settab-add', disabled: !ctx.canWrite(), onclick: () => ctx.guard(async () => {
      const code = (prompt('Code of the new set, e.g. OP2 or NR1:') ?? '').trim().toUpperCase();
      if (!code) return;
      if (!CODE_RE.test(code)) throw new Error('A set code is 2–4 capital letters and a number, e.g. OP2 or NR1.');
      if (list.some(s => s.code === code)) throw new Error(`Set ${code} already exists.`);
      await save({ code, name: code, number: Math.max(0, ...list.map(s => s.number)) + 1, packSize: DEFAULT_PACK });
      v.code = 'default';
      v.focus = code;
      ctx.render();
    }) }, '+ New set');
  }

  // Every card plays a written fx (2026-11-05): without a confirmed one it needs fx.
  const needsFx = c => !!(c.text ?? '').trim() && c.type !== 'Core' && (!c.fx || c.fxStatus === 'check');

  function renderSet(s, list) {
    const special = NOT_SETS.includes(s.code);
    const all = ctx.cards().filter(c => c.id.startsWith(`${s.code}-`));
    const drafts = ctx.drafts()?.cards ?? {};
    const q = v.q.trim().toLowerCase();
    const shown = all.filter(c => {
      if (v.type && c.type !== v.type) return false;
      if (v.color && c.color !== v.color) return false;
      if (['draft', 'review', 'done'].includes(v.status) && (c.status ?? 'draft') !== v.status) return false;
      if (v.status === 'fx' && !needsFx(c)) return false;
      if (v.status === 'edited' && !drafts[c.id]) return false;
      if (v.status === 'noart' && c.art) return false;
      return !q || `${c.id} ${c.name} ${c.text ?? ''} ${(c.traits ?? []).join(' ')}`.toLowerCase().includes(q);
    });
    const newType = s.code === 'Stage' ? 'Stage' : s.code === 'Core' ? 'Core' : 'Action';
    const next = ctx.nextId(s.code);
    const sel = (value, items, onpick) => h('select', { onchange: e => onpick(e.target.value) }, items.map(([val, label]) => h('option', { value: val, selected: val === value }, label)));
    return h('section', { class: 'ce-set' },
      h('header', { class: 'ce-set-head' },
        special ? null : packImg(s.code, 'ce-set-pack'),
        h('div', { class: 'ce-set-title' },
          h('p', { class: 'muted small' }, `Card editor / Sets / ${s.code}`),
          h('h1', {}, s.name),
          h('p', { class: 'muted' }, special ? `${all.length} cards` : `Set ${String(s.number).padStart(2, '0')} · ${all.length} cards · ${s.packSize ?? DEFAULT_PACK} per pack`)),
        h('div', { class: 'ce-page-actions' },
          newCardButton(s.code, special ? [newType] : NEW_TYPES, 'primary'))),
      h('div', { class: 'ce-filters' },
        h('input', { type: 'search', placeholder: 'Search name, text or tag…', value: v.q, oninput: e => { v.q = e.target.value; clearTimeout(v.qt); v.qt = setTimeout(ctx.render, 250); } }),
        special ? null : sel(v.type, [['', 'All types'], ...TYPES.map(t => [t, t])], x => { v.type = x; ctx.render(); }),
        special ? null : sel(v.color, [['', 'All colors'], ...COLORS.map(c => [c, c])], x => { v.color = x; ctx.render(); }),
        sel(v.status, STATUS_FILTERS, x => { v.status = x; ctx.render(); })),
      ...groupedGrid(shown, drafts, h('div', { class: 'ce-tile ce-tile-new' },
          h('span', { class: 'plus' }, '+'), h('span', {}, 'New card'),
          h('div', { class: 'ce-newtypes' }, (special ? [newType] : NEW_TYPES).map(t => h('button', { type: 'button', class: 'ghost', onclick: () => ctx.newCard(s.code, t) }, t))),
          h('small', { class: 'muted' }, `Next code: ${next}`))));
  }

  // Heroji i evolucije su vodoravni, ostale karte okomite (Marko 2026-11-03): dvije mreže, a u prvoj ispod svakog
  // heroja njegove evolucije (po razini). Redoslijed mreže je i redoslijed za Prev / Next na stranici karte.
  function groupedGrid(shown, drafts, newTile) {
    const byId = (a, b) => a.id.localeCompare(b.id, undefined, { numeric: true });
    const heroes = shown.filter(c => c.type === 'Hero').sort(byId);
    const evos = shown.filter(c => c.type === 'Evolution');
    const wide = [];
    for (const hero of heroes) {
      wide.push(hero);
      wide.push(...evos.filter(e => e.hero === hero.name).sort((a, b) => (a.evo ?? 0) - (b.evo ?? 0) || byId(a, b)));
    }
    wide.push(...evos.filter(e => !wide.includes(e)).sort(byId));
    const tall = shown.filter(c => c.type !== 'Hero' && c.type !== 'Evolution').sort(byId);
    v.order = [...wide, ...tall].map(c => c.id);
    const out = [];
    if (wide.length) out.push(h('h3', { class: 'ce-grid-head' }, `Heroes & evolutions (${wide.length})`), h('div', { class: 'ce-grid wide' }, wide.map(c => tile(c, drafts[c.id]))));
    out.push(h('h3', { class: 'ce-grid-head' }, wide.length ? `Cards (${tall.length})` : `${tall.length} cards`), h('div', { class: 'ce-grid' }, tall.map(c => tile(c, drafts[c.id])), newTile));
    return out;
  }

  // Nova karta: tip se bira (Hero, Evolution, Action, Equipment, Assist); Stage i Core imaju svoj.
  function newCardButton(code, types, cls) {
    if (types.length === 1) return h('button', { class: cls, type: 'button', onclick: () => ctx.newCard(code, types[0]) }, 'New card');
    const menu = h('div', { class: 'ce-newmenu', hidden: true }, types.map(t => h('button', { type: 'button', onclick: () => ctx.newCard(code, t) }, t)));
    return h('div', { class: 'ce-newwrap' },
      h('button', { class: cls, type: 'button', 'aria-haspopup': 'menu', onclick: () => { menu.hidden = !menu.hidden; } }, 'New card ▾'), menu);
  }

  function tile(c, draft) {
    const lock = ctx.locks()[c.id];
    const canvas = h('canvas', { class: 'ce-tile-img' });
    ctx.thumbInto(canvas, c, c.type === 'Hero' || c.type === 'Evolution' ? 300 : 210);
    const badge = lock ? h('span', { class: 'ce-st lock' }, `🔒 ${lock.who.toUpperCase()}`)
      : needsFx(c) ? h('span', { class: 'ce-st fx' }, 'NEEDS FX')
        : h('span', { class: `ce-st ${c.status ?? 'draft'}` }, (c.status ?? 'draft').toUpperCase());
    return h('button', { class: `ce-tile${c.type === 'Hero' || c.type === 'Evolution' ? ' wide' : ''}`, type: 'button', onclick: () => ctx.go(c.id) },
      canvas,
      h('span', { class: 'ce-tile-name' }, h('strong', {}, c.name || 'New card'), badge),
      h('span', { class: 'muted small' }, `${c.id} · ${c.type}${draft ? (draft.new ? ' · new' : ' · edited') : ''}`));
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

  // Sve postavke setova i miješanih paketa na jednom mjestu (Marko 2026-11-03): blok po setu, Mixed packs na dnu.
  function renderAllSettings(list) {
    const page = h('section', { class: 'ce-set ce-all-settings' },
      h('header', { class: 'ce-set-head' },
        h('div', { class: 'ce-set-title' }, h('p', { class: 'muted small' }, 'Card editor / Sets'), h('h1', {}, 'Sets & packs'),
          h('p', { class: 'muted' }, 'Name, number and Draft pack of every set; the mixed pack is for a Draft whose cards come from several sets.'))),
      list.map(s => h('div', { class: 'ce-settings-block', id: `set-${s.code}` },
        h('div', { class: 'ce-settings-head' }, packImg(s.code, 'ce-settab-pack'), h('h2', {}, `${s.name} · ${s.code}`)),
        renderSettings(s, list))),
      h('div', { class: 'ce-settings-block', id: 'set-default' },
        h('div', { class: 'ce-settings-head' }, packImg('default', 'ce-settab-pack'), h('h2', {}, 'Mixed packs')),
        renderDefaultPanel()));
    if (v.focus) { const at = v.focus; v.focus = null; setTimeout(() => document.getElementById(`set-${at}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 50); }
    return page;
  }

  function renderSettings(s, list) {
    const work = { ...s };
    const field = (label, input, hint) => h('label', { class: 'ce-field' }, h('span', {}, label), input, hint ? h('small', { class: 'muted' }, hint) : null);
    return h('section', { class: 'ce-panel ce-set-settings' },
      h('div', { class: 'ce-row' },
        field('NAME', h('input', { value: s.name, oninput: e => { work.name = e.target.value; } })),
        field('SET NUMBER', h('input', { type: 'number', min: 1, value: s.number, oninput: e => { work.number = Number(e.target.value) || s.number; } })),
        field('CARDS PER PACK', h('input', { type: 'number', min: 1, max: 30, value: s.packSize ?? DEFAULT_PACK, oninput: e => { work.packSize = Number(e.target.value) || DEFAULT_PACK; } }), 'Draft packs.')),
      h('div', { class: 'ce-row' },
        imageField(s.code, 'pack.png', 'PACK', 'the booster in Draft'),
        imageField(s.code, 'draft-bg.png', 'DRAFT BACKGROUND', 'behind the pack while it opens')),
      h('div', { class: 'ce-actions' },
        h('button', { class: 'primary', type: 'button', disabled: !ctx.canWrite(), onclick: () => ctx.guard(async () => {
          await save(work);
          ctx.toast(`Set ${s.code} saved.`);
          ctx.render();
        }) }, 'Save set'),
        ctx.canWrite() ? null : h('small', { class: 'muted' }, 'Saving needs the shared folder (Chrome or Edge on a computer).')));
  }

  function renderDefaultPanel() {
    const size = { packSize: v.saved?.default?.packSize ?? DEFAULT_PACK };
    return h('section', { class: 'ce-panel ce-set-settings' },
        h('div', { class: 'ce-row' },
          h('label', { class: 'ce-field' }, h('span', {}, 'CARDS PER PACK'),
            h('input', { type: 'number', min: 1, max: 30, value: size.packSize, oninput: e => { size.packSize = Number(e.target.value) || DEFAULT_PACK; } }),
            h('small', { class: 'muted' }, 'When the cards of a Draft come from several sets.'))),
        h('div', { class: 'ce-row' },
          imageField('default', 'pack.png', 'PACK'),
          imageField('default', 'draft-bg.png', 'DRAFT BACKGROUND')),
        h('div', { class: 'ce-actions' },
          h('button', { class: 'primary', type: 'button', disabled: !ctx.canWrite(), onclick: () => ctx.guard(async () => {
            await save(null, size);
            ctx.toast('Mixed packs saved.');
            ctx.render();
          }) }, 'Save')));
  }

  return {
    render, nameOf, newCardButton, ensure: () => (v.saved ? null : load()),
    pick: code => { v.code = code; },
    current: () => (v.code && !NOT_SETS.includes(v.code) && v.code !== 'default' ? v.code : null),
    // Karte kako ih mreža seta zadnji put pokazala (s filterima): redoslijed za Prev / Next na stranici karte.
    order: () => v.order ?? [],
    reload: () => { v.saved = null; v.urls = {}; },
  };
}

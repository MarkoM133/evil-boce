// Card editor › Sets (mockup "06 Card editor - Sets"): kartice setova sa sličicom paketa, zaglavlje seta,
// filteri i mreža nacrtanih karata sa statusom (READY / NOT READY, NEEDS FX, lock), pločica "New card" s idućim kodom.
// Stageovi i Coreovi imaju svoje kartice. Postavke seta su u data/sets/sets.json, slike u data/sets/<kod>/
// (Syncthing, ne git); "default" je paket za Draft iz više setova. Igra će ih čitati u Draftu.
import * as fs from './fsdir.js';
import { fxProblems } from './fx-grammar.js';

export const SETS_PATH = 'data/sets/sets.json';
// Pseudo-setovi po prefiksu koda: Stage-001, Core-001, CB-001 (Combo karte, 2026-11-07).
const NOT_SETS = ['Stage', 'Core', 'CB'];
const CODE_RE = /^[A-Z]{2,4}\d{1,2}$/;
const DEFAULT_PACK = 10;
const TYPES = ['Hero', 'Evolution', 'Action', 'Equipment', 'Assist'];
const NEW_TYPES = TYPES;
const COLORS = ['Cyan', 'Yellow', 'Purple', 'Red', 'Blue', 'Green'];
const STATUS_FILTERS = [['', 'All statuses'], ['draft', 'Not ready'], ['done', 'Ready'], ['fx', 'Needs fx'], ['claude', 'Changed by Claude'], ['edited', 'Unpublished changes'], ['noart', 'No art'], ['redraw', 'Needs redraw']];
// Nacrt koji je zadnji spremio Claude Code: Marko ga treba pogledati (oznaka nestane kad netko spremi kartu).
const byClaude = d => d?.who === 'Claude Code';

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

// A set as it is saved in sets.json. series (Marko 2026-11-27): the series the set belongs to ("Dragon Quest" for
// DQ1 and DQ2, whatever the sets are named); the game's hero picker groups by it. Left out when empty.
export function setRow(one) {
  const series = (one.series ?? '').trim();
  return { code: one.code, name: one.name, number: one.number, packSize: one.packSize, ...(series ? { series } : {}), ...(one.wip ? { wip: true } : {}) };
}

// The series the sets already name, each once, in the order of the sets: offered while typing a set's series.
export function seriesNames(list) {
  return [...new Set(list.map(s => (s.series ?? '').trim()).filter(Boolean))];
}

// ctx: { h, state, store, canWrite, who, render, guard, toast, cards(), drafts(), locks(), thumbInto(canvas, card, px), go(id), newCard(set, type), nextId(set) }
export function createSetsView(ctx) {
  const { h } = ctx;
  // types / colors: several at once (Marko 2026-11-15, mockup 2B: the pills and dots of the Cards page).
  const v = { saved: null, loading: false, code: null, q: '', types: new Set(), colors: new Set(), status: '', settings: false };
  // Heroes whose evolutions are spread out on the set page (mockup 1B), kept in this browser.
  const EVO_KEY = 'evil-boce-evo-open';
  const evoOpen = (() => { try { return new Set(JSON.parse(localStorage.getItem(EVO_KEY) ?? '[]')); } catch { return new Set(); } })();
  const saveEvoOpen = () => { try { localStorage.setItem(EVO_KEY, JSON.stringify([...evoOpen])); } catch {} };

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

  // Adresa slike dolazi od storea svaki put: u Folder načinu su to object URL-ovi koje Objava opozove
  // (dropImageUrls), pa bi zapamćena adresa ostala mrtva (slike paketa su nestale nakon Objave, 5. 11. 2026).
  // Store sam pamti nađene; pack.png koji Syncthing donese kasnije se vidi pri idućem crtanju.
  async function imageUrl(code, name) {
    return (await ctx.store().dataUrl(`sets/${code}/${name}`).catch(() => null)) ?? null;
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
      // wip: Work in progress (Marko 2026-11-14), the set's cards stay out of Publish.
      const row = setRow(one);
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
    ctx.toast(`Saved data/sets/${code}/${name}.`);
    ctx.render();
  }

  const sets = () => setList(v.saved, ctx.state.db.cards.filter(c => !c.deleted));
  const isWip = code => !!v.saved?.sets?.find(s => s.code === code)?.wip;
  const wipChip = code => (isWip(code) ? h('span', { class: 'ce-st review ce-wip', title: 'Work in progress: its cards stay out of Publish' }, 'WIP') : null);
  const nameOf = code => (code === 'Stage' ? 'Stages' : code === 'Core' ? 'Cores' : code === 'CB' ? 'Combos' : sets().find(s => s.code === code)?.name ?? code);

  // zoom: a click shows the pack big over the page (Marko 2026-11-15); a click anywhere or Esc closes it.
  function packImg(code, cls, zoom = false) {
    const img = h('img', { class: cls, alt: '' });
    let url = null;
    const wrap = zoom ? h('button', { type: 'button', class: 'ce-pack-zoom', title: 'See the pack big', onclick: () => { if (url) bigPack(url, nameOf(code)); } }, img) : img;
    img.onerror = () => wrap.replaceWith(h('span', { class: `${cls} empty` }));
    imageUrl(code, 'pack.png').then(u => { if (u) { url = u; img.src = u; } else img.onerror(); });
    return wrap;
  }

  function bigPack(url, name) {
    const close = () => { box.remove(); document.removeEventListener('keydown', onKey); };
    const onKey = e => { if (e.key === 'Escape') close(); };
    const box = h('div', { class: 'ce-combo-big ce-pack-big', role: 'dialog', 'aria-label': `${name} pack`, onclick: close },
      h('img', { src: url, alt: `${name} pack` }));
    document.addEventListener('keydown', onKey);
    document.body.append(box);
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
      NOT_SETS.includes(code) ? null : packImg(code, 'ce-settab-pack'), label, wipChip(code));
    const nav = h('nav', { class: 'ce-settabs' },
        list.map(s => tab([s.code, `${s.name} · ${s.code}`])),
        h('span', { class: 'ce-settab-sep', 'aria-hidden': 'true' }),
        tab(['Stage', 'Stages']), tab(['Core', 'Cores']), tab(['CB', 'Combos']),
        h('span', { class: 'ce-settab-rest' },
          h('button', { type: 'button', class: `ce-settab-pref${v.code === 'default' ? ' active' : ''}`, title: 'Name, number, pack size, pack image and Draft background of every set, and of packs that mix sets', onclick: () => { v.code = 'default'; v.focus = null; ctx.render(); } }, '⚙ Sets & packs'),
          newSetButton(list)));
    // On a phone the tabs are one row that slides sideways: the open one comes into view.
    requestAnimationFrame(() => {
      const open = nav.querySelector('button.active');
      if (open && nav.scrollWidth > nav.clientWidth) nav.scrollLeft = open.offsetLeft - (nav.clientWidth - open.offsetWidth) / 2;
    });
    return h('div', { class: 'ce-page ce-sets' }, nav,
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
  const needsFx = c => !!(c.text ?? '').trim() && c.type !== 'Core' && (!c.fx || c.fxStatus === 'check' || fxProblems(c.fx).length > 0);

  function renderSet(s, list) {
    const special = NOT_SETS.includes(s.code);
    const all = ctx.cards().filter(c => c.id.startsWith(`${s.code}-`));
    const drafts = ctx.drafts()?.cards ?? {};
    const q = v.q.trim().toLowerCase();
    const shown = all.filter(c => {
      if (v.types.size && !v.types.has(c.type)) return false;
      if (v.colors.size && !v.colors.has(c.color || 'None')) return false;
      if (['draft', 'done'].includes(v.status) && (c.status === 'done' ? 'done' : 'draft') !== v.status) return false;
      if (v.status === 'fx' && !needsFx(c)) return false;
      if (v.status === 'edited' && !drafts[c.id]) return false;
      if (v.status === 'claude' && !byClaude(drafts[c.id])) return false;
      if (v.status === 'noart' && c.art) return false;
      if (v.status === 'redraw' && !ctx.pictureStale(c.id)) return false;
      return !q || `${c.id} ${c.name} ${c.text ?? ''} ${(c.traits ?? []).join(' ')}`.toLowerCase().includes(q);
    });
    const newType = s.code === 'Stage' ? 'Stage' : s.code === 'Core' ? 'Core' : s.code === 'CB' ? 'Combo' : 'Action';
    const next = ctx.nextId(s.code);
    const sel = (value, items, onpick) => h('select', { onchange: e => onpick(e.target.value) }, items.map(([val, label]) => h('option', { value: val, selected: val === value }, label)));
    return h('section', { class: 'ce-set' },
      h('header', { class: 'ce-set-head' },
        special ? null : packImg(s.code, 'ce-set-pack', true),
        h('div', { class: 'ce-set-title' },
          h('p', { class: 'muted small' }, `Card editor / Sets / ${s.code}`),
          h('h1', {}, s.name, wipChip(s.code)),
          h('p', { class: 'muted' }, special ? `${all.length} cards` : `Set ${String(s.number).padStart(2, '0')} · ${all.filter(c => !c.token).length} cards${all.some(c => c.token) ? ` · ${all.filter(c => c.token).length} tokens` : ''} · ${s.packSize ?? DEFAULT_PACK} per pack`)),
        h('div', { class: 'ce-page-actions' },
          redrawButton(`${s.code}-`, 'Redraw pictures'),
          special ? null : wipButton(s),
          newCardButton(s.code, special ? [newType] : NEW_TYPES, 'primary'))),
      h('div', { class: 'ce-filters' },
        h('input', { type: 'search', placeholder: 'Search name, text or tag…', value: v.q, oninput: e => { v.q = e.target.value; clearTimeout(v.qt); v.qt = setTimeout(ctx.render, 250); } }),
        sel(v.status, STATUS_FILTERS, x => { v.status = x; ctx.render(); }),
        special ? null : quickFilters()),
      ...groupedGrid(shown, drafts, h('div', { class: `ce-tile ce-tile-new${s.code === 'CB' ? ' wide' : ''}` },
          h('span', { class: 'plus' }, '+'), h('span', {}, 'New card'),
          h('div', { class: 'ce-newtypes' }, (special ? [newType] : NEW_TYPES).map(t => h('button', { type: 'button', class: 'ghost', onclick: () => ctx.newCard(s.code, t) }, t))),
          h('small', { class: 'muted' }, `Next code: ${next}`))));
  }

  // Tip i boja kao na stranici Cards (Marko 2026-11-15, mockup 2B): klik pali ili gasi; unutar skupine "ili"
  // (Action ili Equipment), između skupina "i". Clear sve vrati.
  function quickFilters() {
    const flip = (set, x) => { if (set.has(x)) set.delete(x); else set.add(x); ctx.render(); };
    const any = v.types.size || v.colors.size;
    return h('div', { class: 'quick ce-quick' },
      h('div', { class: 'qf-group' }, TYPES.map(t => h('button', { type: 'button', class: `qf${v.types.has(t) ? ' active' : ''}`, 'aria-pressed': String(v.types.has(t)),
        onclick: () => flip(v.types, t) }, t === 'Hero' ? 'Heroes' : t))),
      h('div', { class: 'qf-group' }, [...COLORS, 'None'].map(c => h('button', { type: 'button', class: `qf-color c-${c}${v.colors.has(c) ? ' active' : ''}`,
        title: c === 'None' ? 'Colorless' : c, 'aria-label': c === 'None' ? 'Colorless' : c, 'aria-pressed': String(v.colors.has(c)), onclick: () => flip(v.colors, c) }))),
      any ? h('button', { type: 'button', class: 'link small', onclick: () => { v.types.clear(); v.colors.clear(); ctx.render(); } }, 'Clear') : null);
  }

  // Heroji i evolucije su vodoravni, ostale karte okomite (Marko 2026-11-03): dvije mreže, a u prvoj ispod svakog
  // heroja njegove evolucije (po razini). Redoslijed mreže je i redoslijed za Prev / Next na stranici karte.
  // Evolucije su složene iza heroja kao mali špil, a gumb ih raširi iza njega (Marko 2026-11-15, mockup 1B).
  function groupedGrid(shown, drafts, newTile) {
    const byId = (a, b) => a.id.localeCompare(b.id, undefined, { numeric: true });
    const heroes = shown.filter(c => c.type === 'Hero').sort(byId);
    const evos = shown.filter(c => c.type === 'Evolution');
    // Combo karte su vodoravne kao heroji.
    const combos = shown.filter(c => c.type === 'Combo').sort(byId);
    const wide = [];
    const items = [];
    for (const hero of heroes) {
      const mine = evos.filter(e => e.hero === hero.name).sort((a, b) => (a.evo ?? 0) - (b.evo ?? 0) || byId(a, b));
      wide.push(hero, ...mine);
      items.push(mine.length ? heroWithEvos(hero, mine, drafts) : tile(hero, drafts[hero.id]));
      if (mine.length && evoOpen.has(hero.id)) items.push(...mine.map(e => tile(e, drafts[e.id], 'ce-evo-open')));
    }
    const loose = evos.filter(e => !wide.includes(e)).sort(byId);
    wide.push(...loose, ...combos);
    items.push(...loose.map(e => tile(e, drafts[e.id])), ...combos.map(c => tile(c, drafts[c.id])));
    const tall = shown.filter(c => !['Hero', 'Evolution', 'Combo'].includes(c.type)).sort(byId);
    v.order = [...wide, ...tall].map(c => c.id);
    const out = [];
    if (combos.length && combos.length === wide.length && !tall.length) {
      out.push(h('h3', { class: 'ce-grid-head' }, `${combos.length} ${combos.length === 1 ? 'combo' : 'combos'}`), h('div', { class: 'ce-grid wide' }, wide.map(c => tile(c, drafts[c.id])), newTile));
      return out;
    }
    if (wide.length) {
      const stacked = heroes.filter(hh => evos.some(e => e.hero === hh.name));
      const allOpen = stacked.length && stacked.every(hh => evoOpen.has(hh.id));
      out.push(h('div', { class: 'ce-grid-headrow' }, h('h3', { class: 'ce-grid-head' }, `Heroes & evolutions (${wide.length})`),
        stacked.length ? h('button', { type: 'button', class: 'link small accent', onclick: () => {
          for (const hh of stacked) { if (allOpen) evoOpen.delete(hh.id); else evoOpen.add(hh.id); }
          saveEvoOpen();
          ctx.render();
        } }, allOpen ? 'Hide all evolutions' : 'Show all evolutions') : null),
        h('div', { class: 'ce-grid wide' }, items));
    }
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

  // Pictures out of date with the renderer (NEEDS REDRAW on their tiles) drawn again with one click: a set's on its
  // page, every set's on Sets & packs (Marko 2026-11-13).
  function redrawButton(prefix, label) {
    ctx.checkPictures();
    const n = ctx.stalePictures(prefix);
    return h('button', { type: 'button', class: n ? '' : 'ghost', disabled: !ctx.canPublish() || !n,
      title: !ctx.canPublish() ? 'Redrawing writes the pictures: a computer with the shared folder.' : n ? 'Draw every out-of-date picture again with the renderer as it is now' : 'Every picture is up to date',
      onclick: () => ctx.guard(() => ctx.redrawAll(prefix)) }, n ? `${label} (${n})` : label);
  }

  // Work in progress on the set's own page (Marko 2026-11-14), one click on or off; also in Sets & packs.
  function wipButton(s) {
    const on = isWip(s.code);
    return h('button', { type: 'button', class: on ? 'ce-wip-btn on' : 'ghost ce-wip-btn', 'aria-pressed': String(on), disabled: !ctx.canWrite(),
      title: on ? 'Work in progress: the set\'s cards stay out of Publish. Click when the set is finished.' : 'Keep the set\'s cards out of Publish while it is not finished',
      onclick: () => ctx.guard(async () => {
        await save({ ...s, wip: !on });
        ctx.toast(on ? `${s.code} is finished: its cards can be published.` : `${s.code} is Work in progress: its cards stay out of Publish.`);
        ctx.render();
      }) }, on ? 'WIP: on' : 'Work in progress');
  }

  function tile(c, draft, extra = '', stack = 0) {
    const lock = ctx.locks()[c.id];
    const canvas = h('canvas', { class: 'ce-tile-img' });
    ctx.thumbInto(canvas, c, ['Hero', 'Evolution', 'Combo'].includes(c.type) ? 300 : 210);
    const badge = lock ? h('span', { class: 'ce-st lock' }, `🔒 ${lock.who.toUpperCase()}`)
      : needsFx(c) ? h('span', { class: 'ce-st fx' }, 'NEEDS FX')
        : ctx.pictureStale(c.id) ? h('span', { class: 'ce-st fx', title: 'The picture was drawn by an older renderer: Redraw picture, or Redraw all pictures' }, 'NEEDS REDRAW')
        : h('span', { class: `ce-st ${c.status === 'done' ? 'done' : 'draft'}` }, c.type === 'Core' ? 'CORE' : c.status === 'done' ? 'READY' : 'NOT READY');
    const claude = byClaude(draft) ? h('span', { class: 'ce-st claude', title: 'Changed by Claude Code: have a look, then Save' }, 'CLAUDE') : null;
    const token = c.token ? h('span', { class: 'ce-st token', title: 'A token: made by another card, never in a deck' }, 'TOKEN') : null;
    // WIP beside the status (Marko 2026-11-15): the card waits with its Work in progress set.
    const held = ctx.heldBy(c.id);
    const wip = held ? h('span', { class: 'ce-st review', title: `Set ${held} is Work in progress: this card stays out of Publish` }, `${held} WIP`) : null;
    const pic = stack ? h('span', { class: 'ce-tile-stack' }, h('span', { class: 'ce-stack-back b2' }), h('span', { class: 'ce-stack-back b1' }), canvas,
      h('span', { class: 'ce-stack-count' }, `+${stack}`)) : canvas;
    return h('button', { class: `ce-tile${c.type === 'Hero' || c.type === 'Evolution' ? ' wide' : ''}${extra ? ` ${extra}` : ''}`, type: 'button', onclick: () => ctx.go(c.id),
      style: `--cc: var(--c-${!c.color || c.color === 'None' ? 'colorless' : c.color})` },
      pic,
      h('span', { class: 'ce-tile-name' }, h('strong', {}, c.name || 'New card'), h('span', { class: 'ce-tile-badges' }, token, claude, wip, badge)),
      h('span', { class: 'muted small' }, `${c.id} · ${c.type}${draft ? (draft.new ? ' · new' : ' · edited') : ''}`));
  }

  // A hero with evolutions: a little deck while they are folded, and the button that spreads them out after it.
  function heroWithEvos(hero, mine, drafts) {
    const open = evoOpen.has(hero.id);
    return h('div', { class: 'ce-hero-evos' },
      tile(hero, drafts[hero.id], '', open ? 0 : mine.length),
      h('button', { type: 'button', class: `ce-evo-btn${open ? ' open' : ''}`, 'aria-expanded': String(open),
        onclick: () => { if (open) evoOpen.delete(hero.id); else evoOpen.add(hero.id); saveEvoOpen(); ctx.render(); } },
      h('span', { class: 'ce-evo-chev', 'aria-hidden': 'true' }, '▸'), `${mine.length} ${mine.length === 1 ? 'evolution' : 'evolutions'}`));
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
          h('p', { class: 'muted' }, 'Name, series, number and Draft pack of every set; the mixed pack is for a Draft whose cards come from several sets.')),
        h('div', { class: 'ce-page-actions' }, redrawButton('', 'Redraw all pictures'))),
      list.map(s => h('div', { class: 'ce-settings-block', id: `set-${s.code}` },
        h('div', { class: 'ce-settings-head' }, packImg(s.code, 'ce-settab-pack', true), h('h2', {}, `${s.name} · ${s.code}`, wipChip(s.code))),
        renderSettings(s, list))),
      // The series already named, offered in every set's SERIES field (so one series is spelled one way).
      h('datalist', { id: 'ce-series' }, seriesNames(list).map(n => h('option', { value: n }))),
      h('div', { class: 'ce-settings-block', id: 'set-default' },
        h('div', { class: 'ce-settings-head' }, packImg('default', 'ce-settab-pack', true), h('h2', {}, 'Mixed packs')),
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
        field('SERIES', h('input', { value: s.series ?? '', list: 'ce-series', placeholder: 'e.g. Dragon Quest', oninput: e => { work.series = e.target.value; } }),
          'Sets of one series stand together in the game. Empty: the set\'s own name.'),
        field('SET NUMBER', h('input', { type: 'number', min: 1, value: s.number, oninput: e => { work.number = Number(e.target.value) || s.number; } })),
        field('CARDS PER PACK', h('input', { type: 'number', min: 1, max: 30, value: s.packSize ?? DEFAULT_PACK, oninput: e => { work.packSize = Number(e.target.value) || DEFAULT_PACK; } }), 'Draft packs.')),
      h('label', { class: 'ce-check-row' },
        h('input', { type: 'checkbox', checked: !!s.wip, onchange: e => { work.wip = e.target.checked; } }),
        h('span', {}, h('strong', {}, 'Work in progress'), h('small', { class: 'muted' }, " The set's cards stay out of Publish until this is off. Switch it off when the set is finished; Publish then fixes the codes."))),
      h('div', { class: 'ce-row' },
        imageField(s.code, 'pack.png', 'PACK', 'the booster in Draft'),
        imageField(s.code, 'draft-bg.png', 'DRAFT BACKGROUND', 'behind the pack while it opens')),
      h('div', { class: 'ce-actions' },
        h('button', { class: 'primary', type: 'button', disabled: !ctx.canWrite(), onclick: () => ctx.guard(async () => {
          await save(work);
          ctx.toast(`Set ${s.code} saved.`);
          ctx.render();
        }) }, 'Save set'),
        ctx.canWrite() ? null : h('small', { class: 'muted' }, 'Saving needs the shared folder (Chrome or Edge on a computer), or Card Studio opened through Marko\'s computer.')));
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
    list: () => sets(),
    isWip,
    // Work in progress on or off from elsewhere (Publish: "Set is finished").
    setWip: async (code, on) => {
      const s = sets().find(x => x.code === code);
      if (!s) throw new Error(`No set ${code}.`);
      await save({ ...s, wip: on });
    },
    // Codes of the sets in Work in progress, read from the file now (Publish: the other computer may have changed it).
    freshWip: async () => {
      const text = await fs.readText(ctx.store().root, SETS_PATH);
      let doc;
      try { doc = text?.trim() ? JSON.parse(text) : { sets: [] }; } catch { throw new Error('sets.json is being written right now. Try again in a moment.'); }
      v.saved = doc;
      return new Set((doc.sets ?? []).filter(s => s.wip).map(s => s.code));
    },
    pick: code => { v.code = code; },
    current: () => (v.code && !NOT_SETS.includes(v.code) && v.code !== 'default' ? v.code : null),
    // Karte kako ih mreža seta zadnji put pokazala (s filterima): redoslijed za Prev / Next na stranici karte.
    order: () => v.order ?? [],
    reload: () => { v.saved = null; },
  };
}

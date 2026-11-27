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

// The fields typed into a set's settings that differ from what is saved: `edits` is {field: value}, `settled`
// brings a value to the form it is saved in (a series trimmed, no pack size as the default one).
export function unsavedKeys(saved, edits, settled = (key, x) => x) {
  return Object.keys(edits ?? {}).filter(key => settled(key, edits[key]) !== settled(key, saved[key]));
}

// The series a set stands under in the set row: the one it names, else its own name.
export const seriesOf = s => (s.series ?? '').trim() || s.name || s.code || '';

// The sets under their series, in the order of the sets: [[series, [set, …]], …].
export function bySeries(list) {
  const groups = new Map();
  for (const s of list) {
    const name = seriesOf(s);
    if (!groups.has(name)) groups.set(name, []);
    groups.get(name).push(s);
  }
  return [...groups];
}

// The sets pinned to the set row: what this browser remembers, less sets that are gone; every set while it
// remembers nothing (the row as it was before pins).
export function pinnedCodes(stored, list) {
  const codes = list.map(s => s.code);
  return Array.isArray(stored) ? stored.filter(c => codes.includes(c)) : codes;
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
  // `one` may be several sets (Save all): they are written in one go.
  async function save(one, def = null) {
    const text = await fs.readText(ctx.store().root, SETS_PATH);
    let fresh;
    try { fresh = text?.trim() ? JSON.parse(text) : { sets: [] }; } catch { throw new Error('sets.json is being written right now. Try again in a moment.'); }
    fresh.sets ??= [];
    for (const set of one ? [one].flat() : []) {
      // wip: Work in progress (Marko 2026-11-14), the set's cards stay out of Publish.
      const row = setRow(set);
      const i = fresh.sets.findIndex(x => x.code === set.code);
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

  // ---------- the set row (Marko 2026-11-27, mockups set-nav → set-pins → set-row, variant 1) ----------
  // Two states, kept in this browser like the pins: "pins", the sets you pinned as tabs and every set under All sets
  // at the right end; "all", every set out, the series in the row and the open series' sets under it. The two icons
  // at the right end switch between them.
  const PINS_KEY = 'evil-boce-set-pins';
  const ROW_KEY = 'evil-boce-set-row';
  const stored = key => { try { return JSON.parse(localStorage.getItem(key) ?? 'null'); } catch { return null; } };
  const store = (key, value) => { try { localStorage.setItem(key, JSON.stringify(value)); } catch {} };
  const rowMode = () => (stored(ROW_KEY) === 'all' ? 'all' : 'pins');
  const pins = list => pinnedCodes(stored(PINS_KEY), list);
  const PIN_ICON = on => `<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M9.6 1.2 14.8 6.4l-1.9.6-2.7 2.7.5 3.4-1.1 1.1-3.3-3.3-4 4-.7-.7 4-4L2.3 6.9l1.1-1.1 3.4.5 2.7-2.7z" fill="${on ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/></svg>`;
  const ROWS_ICON = '<svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M1 2.5h14V7H1zM1 9h4.2v4.5H1zM6.4 9h4.2v4.5H6.4z" fill="currentColor"/></svg>';
  const countOf = code => ctx.cards().filter(c => c.id.startsWith(`${code}-`) && !c.token).length;

  function togglePin(code, list) {
    const now = pins(list);
    store(PINS_KEY, now.includes(code) ? now.filter(c => c !== code) : list.map(s => s.code).filter(c => c === code || now.includes(c)));
    ctx.render();
  }

  function pinButton(code, list) {
    const on = pins(list).includes(code);
    return h('button', { type: 'button', class: `ce-pin${on ? ' on' : ''}`, 'aria-pressed': String(on), title: on ? 'Unpin from the row' : 'Pin to the row',
      innerHTML: PIN_ICON(on), onclick: e => { e.stopPropagation(); togglePin(code, list); } });
  }

  const prefButton = () => h('button', { type: 'button', class: `ce-settab-pref${v.code === 'default' ? ' active' : ''}`, title: 'Name, series, number, pack size, pack image and Draft background of every set, and of packs that mix sets',
    onclick: () => { closeAll(false); v.code = 'default'; v.focus = null; ctx.render(); } }, '⚙ Sets & packs');

  // All sets: the list is open while v.allOpen; a click outside it or Esc closes it.
  let offAll = null;
  function closeAll(draw = true) {
    if (!v.allOpen) return;
    v.allOpen = false;
    offAll?.();
    offAll = null;
    if (draw) ctx.render();
  }
  function openAll() {
    v.allOpen = true;
    v.allSeries = null;
    v.allQ = '';
    const onDoc = e => { if (!e.target.closest?.('.ce-allpanel, .ce-allsets')) closeAll(); };
    const onKey = e => { if (e.key === 'Escape') closeAll(); };
    setTimeout(() => document.addEventListener('click', onDoc), 0);
    document.addEventListener('keydown', onKey);
    offAll = () => { document.removeEventListener('click', onDoc); document.removeEventListener('keydown', onKey); };
    ctx.render();
  }

  // The list under All sets: the series on top, the open series' sets under them (a search looks through every
  // series), each with its pin; Sets & packs and New set at the foot.
  function allPanel(list) {
    const groups = bySeries(list);
    let series = v.allSeries ?? seriesOf(list.find(s => s.code === v.code) ?? list[0] ?? {});
    const tabsBox = h('div', { class: 'ce-all-series', role: 'tablist' });
    const tiles = h('div', { class: 'ce-all-tiles' });
    const search = h('input', { type: 'search', class: 'ce-all-find', placeholder: 'Search a set…', 'aria-label': 'Search a set', value: v.allQ ?? '', oninput: e => { v.allQ = e.target.value; fill(); } });
    const tile = s => h('div', { class: `ce-all-tile${s.code === v.code ? ' active' : ''}` },
      h('button', { type: 'button', class: 'ce-all-open', onclick: () => { closeAll(false); v.code = s.code; ctx.render(); } },
        packImg(s.code, 'ce-all-pack'), h('span', { class: 'ce-all-name' }, s.name, wipChip(s.code)), h('small', {}, `${s.code} · ${countOf(s.code)} cards`)),
      pinButton(s.code, list));
    const fill = () => {
      const q = (v.allQ ?? '').trim().toLowerCase();
      tabsBox.replaceChildren(...groups.map(([name, mine]) => h('button', { type: 'button', role: 'tab', class: !q && name === series ? 'active' : '', onclick: () => { series = v.allSeries = name; v.allQ = ''; search.value = ''; fill(); } },
        name, h('span', { class: 'ce-count' }, mine.length))));
      const shown = q ? list.filter(s => `${s.name} ${s.code} ${seriesOf(s)}`.toLowerCase().includes(q)) : groups.find(([n]) => n === series)?.[1] ?? [];
      tiles.replaceChildren(...(shown.length ? shown.map(tile) : [h('p', { class: 'muted small' }, 'No set by that name.')]));
    };
    fill();
    return h('div', { class: 'ce-allpanel', role: 'dialog', 'aria-label': 'All sets', onclick: e => e.stopPropagation() },
      h('div', { class: 'ce-all-head' }, tabsBox, search), tiles,
      h('div', { class: 'ce-all-foot' }, prefButton(), newSetButton(list), h('small', { class: 'muted' }, 'Pinned sets stay in the row')));
  }

  // Returns the row's nodes: the bar, and with every set out the row of the open series' sets under it.
  function rowNodes(list) {
    const mode = rowMode();
    const open = code => { closeAll(false); v.code = code; ctx.render(); };
    const plain = ([code, label]) => h('button', { type: 'button', class: code === v.code ? 'active' : '', onclick: () => open(code) }, label);
    const others = [h('span', { class: 'ce-settab-sep', 'aria-hidden': 'true' }), plain(['Stage', 'Stages']), plain(['Core', 'Cores']), plain(['CB', 'Combos'])];
    const setMode = m => { closeAll(false); store(ROW_KEY, m); ctx.render(); };
    const cur = list.find(s => s.code === v.code);
    let nav;
    let end;
    let under = null;
    if (mode === 'pins') {
      const pinned = pins(list);
      // A set as a tab with its pin (it shows under the pointer); the open set has a tab while it is not pinned.
      const setTab = (s, temp) => h('span', { class: `ce-settab${s.code === v.code ? ' active' : ''}${temp ? ' temp' : ''}` },
        h('button', { type: 'button', class: s.code === v.code ? 'active' : '', title: temp ? 'Open, not pinned: the pin keeps it in the row' : null, onclick: () => open(s.code) },
          packImg(s.code, 'ce-settab-pack'), `${s.name} · ${s.code}`, wipChip(s.code)),
        pinButton(s.code, list));
      nav = h('nav', { class: 'ce-settabs' }, list.filter(s => pinned.includes(s.code)).map(s => setTab(s, false)), cur && !pinned.includes(cur.code) ? setTab(cur, true) : null, others);
      // One control of two parts: All sets opens the list, the rows beside it put every set out.
      end = [h('span', { class: 'ce-allgroup' },
        h('button', { type: 'button', class: `ce-allsets${v.allOpen ? ' open' : ''}`, 'aria-expanded': String(!!v.allOpen), onclick: e => { e.stopPropagation(); if (v.allOpen) closeAll(); else openAll(); } },
          'All sets', h('span', { class: 'ce-count' }, list.length), h('span', { class: 'ce-caret', 'aria-hidden': 'true' }, v.allOpen ? '▴' : '▾')),
        h('button', { type: 'button', class: 'ce-allout', title: 'Put every set in the row, by series', 'aria-label': 'Put every set in the row, by series', innerHTML: ROWS_ICON, onclick: () => setMode('all') }))];
    } else {
      const groups = bySeries(list);
      if (cur) v.series = seriesOf(cur);
      v.series ??= groups[0]?.[0] ?? null;
      nav = h('nav', { class: 'ce-settabs' },
        groups.map(([name, mine]) => h('button', { type: 'button', class: cur && seriesOf(cur) === name ? 'active' : name === v.series ? 'near' : '',
          onclick: () => { v.series = name; if (!cur || seriesOf(cur) !== name) v.code = mine[0].code; ctx.render(); } }, name, h('span', { class: 'ce-count' }, mine.length))),
        others, h('span', { class: 'ce-settab-rest' }, prefButton(), newSetButton(list)));
      // The same place, the way back: the pinned row with All sets.
      end = [h('button', { type: 'button', class: 'ce-allsets ce-topins', title: 'Back to the pinned sets, with the rest under All sets', onclick: () => setMode('pins') },
        h('span', { class: 'ce-topins-ic', innerHTML: PIN_ICON(true) }), 'Pinned sets')];
      under = h('div', { class: 'ce-setrow2' }, h('span', { class: 'ce-setrow2-label' }, v.series ?? ''),
        (groups.find(([n]) => n === v.series)?.[1] ?? []).map(s => h('button', { type: 'button', class: `ce-setchip${s.code === v.code ? ' active' : ''}`, onclick: () => open(s.code) },
          packImg(s.code, 'ce-settab-pack'), s.name, h('small', {}, `${s.code} · ${countOf(s.code)}`), wipChip(s.code))));
    }
    // On a phone the tabs are one row that slides sideways: the open one comes into view.
    requestAnimationFrame(() => {
      const at = nav.querySelector('.ce-settab.active, button.active');
      if (at && nav.scrollWidth > nav.clientWidth) nav.scrollLeft = at.offsetLeft - (nav.clientWidth - at.offsetWidth) / 2;
    });
    return [h('div', { class: `ce-setbar ${mode}` }, nav, h('div', { class: 'ce-setbar-end' }, end), mode === 'pins' && v.allOpen ? allPanel(list) : null), under];
  }

  function render() {
    if (!v.saved) {
      load();
      return h('section', { class: 'panel' }, h('p', { class: 'muted' }, 'Loading the sets…'));
    }
    const list = sets();
    v.code ??= list[0]?.code ?? 'Stage';
    return h('div', { class: 'ce-page ce-sets' }, rowNodes(list),
      v.code === 'default' ? renderAllSettings(list) : renderSet(list.find(s => s.code === v.code) ?? { code: v.code, name: nameOf(v.code) }, list));
  }

  function newSetButton(list) {
    return h('button', { type: 'button', class: 'ce-settab-add', disabled: !ctx.canWrite(), onclick: () => ctx.guard(async () => {
      const code = (prompt('Code of the new set, e.g. OP2 or NR1:') ?? '').trim().toUpperCase();
      if (!code) return;
      if (!CODE_RE.test(code)) throw new Error('A set code is 2–4 capital letters and a number, e.g. OP2 or NR1.');
      if (list.some(s => s.code === code)) throw new Error(`Set ${code} already exists.`);
      await save({ code, name: code, number: Math.max(0, ...list.map(s => s.number)) + 1, packSize: DEFAULT_PACK });
      // The set you made is pinned to your row (only when the row remembers pins: without them every set is in it).
      if (Array.isArray(stored(PINS_KEY))) store(PINS_KEY, [...stored(PINS_KEY), code]);
      closeAll(false);
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
  // What is typed into a set's settings and not saved yet, by set code (v.edits). It used to live in the form alone:
  // Save set on one set drew the page again and threw away what was typed into the others (Marko 2026-11-27).
  v.edits ??= {};
  const settled = (key, x) => (key === 'series' ? (x ?? '').trim() : key === 'wip' ? !!x : key === 'packSize' ? x ?? DEFAULT_PACK : x);
  const isDirty = s => unsavedKeys(s, v.edits[s.code], settled).length > 0;
  const withEdits = s => ({ ...s, ...(v.edits[s.code] ?? {}) });
  // The page's Save all buttons and "not saved" marks follow what is typed, without drawing the page again.
  function markUnsaved(list) {
    const dirty = list.filter(isDirty);
    for (const s of list) document.getElementById(`set-${s.code}`)?.classList.toggle('unsaved', dirty.includes(s));
    for (const b of document.querySelectorAll('.ce-saveall')) {
      b.disabled = !dirty.length || !ctx.canWrite();
      b.textContent = dirty.length ? `Save all (${dirty.length})` : 'Save all';
      // Beside a set's own Save it shows only when another set waits too.
      if (b.dataset.own) b.hidden = !dirty.some(s => s.code !== b.dataset.own);
    }
  }
  const saveAllButton = (list, own = '') => h('button', { class: own ? 'ghost ce-saveall' : 'primary ce-saveall', type: 'button', 'data-own': own || null, hidden: !!own,
    title: 'Saves every set with changes that are not saved yet', onclick: () => ctx.guard(async () => {
      const dirty = sets().filter(isDirty);
      if (!dirty.length) return;
      await save(dirty.map(withEdits));
      for (const d of dirty) delete v.edits[d.code];
      ctx.toast(dirty.length === 1 ? `Set ${dirty[0].code} saved.` : `${dirty.length} sets saved: ${dirty.map(d => d.code).join(', ')}.`);
      ctx.render();
    }) }, 'Save all');

  function renderAllSettings(list) {
    const page = h('section', { class: 'ce-set ce-all-settings' },
      h('header', { class: 'ce-set-head' },
        h('div', { class: 'ce-set-title' }, h('p', { class: 'muted small' }, 'Card editor / Sets'), h('h1', {}, 'Sets & packs'),
          h('p', { class: 'muted' }, 'Name, series, number and Draft pack of every set; the mixed pack is for a Draft whose cards come from several sets.')),
        h('div', { class: 'ce-page-actions' }, redrawButton('', 'Redraw all pictures'), saveAllButton(list))),
      list.map(s => h('div', { class: 'ce-settings-block', id: `set-${s.code}` },
        h('div', { class: 'ce-settings-head' }, packImg(s.code, 'ce-settab-pack', true), h('h2', {}, `${s.name} · ${s.code}`, wipChip(s.code)),
          h('span', { class: 'ce-st review ce-unsaved' }, 'NOT SAVED')),
        renderSettings(s, list))),
      h('div', { class: 'ce-settings-block', id: 'set-default' },
        h('div', { class: 'ce-settings-head' }, packImg('default', 'ce-settab-pack', true), h('h2', {}, 'Mixed packs')),
        renderDefaultPanel()));
    if (v.focus) { const at = v.focus; v.focus = null; setTimeout(() => document.getElementById(`set-${at}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 50); }
    requestAnimationFrame(() => markUnsaved(list));
    return page;
  }

  // SERIES: the series the sets already name come up under the field as pills, the tag field's own (Marko 2026-11-27:
  // the browser's list did not look like the app), so one series is spelled one way. They show while the field has
  // the focus and narrow as you type; a click, or the arrows and Enter, takes one. What other sets have typed and not
  // saved yet is offered too.
  function seriesField(work, list, edit) {
    const box = h('div', { class: 'ce-tag-pills ce-series-pills', hidden: true });
    let items = [];
    let at = -1;
    const take = name => { input.value = name; edit('series', name); box.hidden = true; };
    const paint = () => {
      box.replaceChildren(h('div', { class: 'ce-tag-group-pills' }, items.map((name, i) =>
        h('button', { type: 'button', class: `ce-tag-pill${i === at ? ' on' : ''}`, onpointerdown: e => { e.preventDefault(); take(name); } }, name))));
      box.hidden = !items.length;
    };
    const show = (typing = true) => {
      const q = input.value.trim().toLowerCase();
      items = seriesNames(list.map(withEdits)).filter(name => name.toLowerCase() !== q && (!typing || !q || name.toLowerCase().includes(q)));
      at = -1;
      paint();
    };
    const input = h('input', { value: work.series ?? '', placeholder: 'e.g. Dragon Quest', autocomplete: 'off',
      onfocus: () => show(false), oninput: e => { edit('series', e.target.value); show(); },
      onblur: () => setTimeout(() => { if (document.activeElement !== input) box.hidden = true; }, 150),
      onkeydown: e => {
        if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && items.length) {
          e.preventDefault();
          at = (at + (e.key === 'ArrowUp' ? -1 : 1) + items.length) % items.length;
          paint();
        } else if (e.key === 'Enter' && at >= 0 && !box.hidden) { e.preventDefault(); take(items[at]); }
        else if (e.key === 'Escape') box.hidden = true;
      } });
    return h('label', { class: 'ce-field' }, h('span', {}, 'SERIES'), input, box,
      h('small', { class: 'muted' }, 'Sets of one series stand together in the game. Empty: the set\'s own name.'));
  }

  function renderSettings(s, list) {
    const work = withEdits(s);
    const edit = (key, value) => { (v.edits[s.code] ??= {})[key] = value; markUnsaved(list); };
    const field = (label, input, hint) => h('label', { class: 'ce-field' }, h('span', {}, label), input, hint ? h('small', { class: 'muted' }, hint) : null);
    return h('section', { class: 'ce-panel ce-set-settings' },
      h('div', { class: 'ce-row' },
        field('NAME', h('input', { value: work.name, oninput: e => edit('name', e.target.value) })),
        seriesField(work, list, edit),
        field('SET NUMBER', h('input', { type: 'number', min: 1, value: work.number, oninput: e => edit('number', Number(e.target.value) || s.number) })),
        field('CARDS PER PACK', h('input', { type: 'number', min: 1, max: 30, value: work.packSize ?? DEFAULT_PACK, oninput: e => edit('packSize', Number(e.target.value) || DEFAULT_PACK) }), 'Draft packs.')),
      h('label', { class: 'ce-check-row' },
        h('input', { type: 'checkbox', checked: !!work.wip, onchange: e => edit('wip', e.target.checked) }),
        h('span', {}, h('strong', {}, 'Work in progress'), h('small', { class: 'muted' }, " The set's cards stay out of Publish until this is off. Switch it off when the set is finished; Publish then fixes the codes."))),
      h('div', { class: 'ce-row' },
        imageField(s.code, 'pack.png', 'PACK', 'the booster in Draft'),
        imageField(s.code, 'draft-bg.png', 'DRAFT BACKGROUND', 'behind the pack while it opens')),
      h('div', { class: 'ce-actions' },
        h('button', { class: 'primary', type: 'button', disabled: !ctx.canWrite(), onclick: () => ctx.guard(async () => {
          // This set alone; what is typed into the others stays, with its NOT SAVED mark.
          await save(withEdits(s));
          delete v.edits[s.code];
          const left = sets().filter(isDirty).length;
          ctx.toast(`Set ${s.code} saved.${left ? ` ${left} other set${left === 1 ? ' is' : 's are'} not saved yet.` : ''}`);
          ctx.render();
        }) }, 'Save this set'),
        saveAllButton(list, s.code),
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

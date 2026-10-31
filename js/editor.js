// Card editor (zamjena za Card Engine): Edit za sve tipove karata (Action, Equipment, Assist, Hero,
// Evolution, Stage, Core). Forma i živi preview jedno uz drugo; izmjene se spremaju kao nacrti u
// data/editor/drafts.json, a igra ih vidi tek kad ih Objava prebaci u cards.json (Card editor › Publish).
// Art je u data/art/<kod>.<ext> (puna rezolucija), izrez je u karti (artCrop); amblemi u data/art/emblems/.
import { loadTemplate, renderCard, fontsReady, loadImage, parseEffect, templateName, TINTS } from './render.js';
import { firstTag, tagLabel, traitNames, INVALID } from './tags.js';
import { TERRAINS } from './parse.js';
import { applyDrafts, imageHashOf } from './importer.js';
import { lockPath, lockState, newLock, HEARTBEAT_MS, SETTLE_MS } from './locks.js';
import { createSetsView } from './editor-sets.js';
import { createGuideView, readGuide, avoidWarnings, suggest } from './editor-guide.js';
import * as fs from './fsdir.js';

export const DRAFTS_PATH = 'data/editor/drafts.json';
// Zadnja Objava iz editora: baza prije nje i objavljeni nacrti, za Undo.
const LAST_PUBLISH_PATH = 'data/editor/last-publish.json';
export const EDIT_TYPES = ['Hero', 'Evolution', 'Action', 'Equipment', 'Assist', 'Stage', 'Core'];
// Tip se mijenja samo unutar iste vrste karte (isti predložak i ista polja).
const PORTRAIT = ['Action', 'Equipment', 'Assist'];
const HEROISH = ['Hero', 'Evolution'];
const COLORS = Object.keys(TINTS);
const STATUSES = ['draft', 'review', 'done'];
const CORE_KINDS = ['Buff', 'Major', 'Debuff'];
const WHO_KEY = 'evil-boce-who';
const BONUS_KEYS = [['pwr', 'Power'], ['dmg', 'DMG'], ['hp', 'HP'], ['rng', 'Range'], ['kb', 'KB']];
const STAT_KEYS = [['hp', 'HP'], ['dmg', 'DMG'], ['pwr', 'Power'], ['rng', 'Range'], ['kb', 'KB']];
// Polja koja editor mijenja; nacrt čuva samo ona koja se razlikuju od karte u cards.json.
const FIELDS = ['name', 'type', 'color', 'cost', 'bonus', 'stats', 'evo', 'hero', 'abilityNames', 'traits', 'aliases', 'text', 'terrain',
  'art', 'artCrop', 'emblem', 'bg', 'template', 'status', 'notes'];
// Statovi se pišu riječima iza broja ("3 HP", "+2000 Power"): igra čita riječi, a karta ih crta kao ikone.
const INSERTS = [
  ['[Range]', '[Range] '], ['Start', 'Start Phase: '], ['Preroll', 'Preroll Phase: '], ['Roll', 'Roll Phase: '], ['Postroll', 'Postroll Phase: '],
  ['Battle', 'Battle Phase: '], ['End', 'End Phase: '], ['Once per turn', ' Once Per Turn'], ['Power', ' Power'], ['DMG', ' DMG'],
  ['HP', ' HP'], ['Range', ' Range'], ['Knockback', ' Knockback'],
];

// Prazan objekt ili popis je isto što i polje kojeg nema (Stage bez bonusa, karta bez tagova).
const empty = v => v == null || (typeof v === 'object' && Object.keys(v).length === 0);
const sameVal = (a, b) => (empty(a) && empty(b)) || JSON.stringify(a) === JSON.stringify(b);

// env: { state, h, toast, guard, render, go(id) }.
export function createEditor(env) {
  const { h } = env;
  const ed = {
    drafts: null, tpl: null, tpls: {}, ready: false, agency: true, loading: false, error: null,
    id: null, work: null, base: null, art: null, artFor: null, emblem: null, emblemFor: null,
    dirty: false, q: '', set: '', type: '', color: '', hero: '', show: '', canvas: null, warnBox: null, frame: 0,
  };
  const store = () => env.state.store;
  const canWrite = () => store()?.kind === 'folder';
  const who = () => { try { return localStorage.getItem(WHO_KEY) || ''; } catch { return ''; } };

  async function load() {
    if (ed.loading) return;
    ed.loading = true;
    try {
      ed.agency = await fontsReady();
      ed.drafts = await readDrafts();
      ed.guide = await readGuide(store());
      ed.ready = true;
    } catch (e) {
      ed.error = e.message || String(e);
    }
    ed.loading = false;
    env.render();
  }

  // Predlošci se učitavaju kad zatrebaju (data/card-frames/<ime>/).
  function templateFor(card) {
    const name = templateName(card);
    ed.tpls[name] ??= loadTemplate(name, rel => store().dataUrl(rel));
    return ed.tpls[name];
  }
  const landscape = card => ['hero', 'evolution'].includes(templateName(card));

  // Uvijek s diska (drugi stroj je mogao spremiti u međuvremenu; Syncthing donese datoteku).
  async function readDrafts() {
    try {
      if (store().kind === 'folder') {
        const t = await fs.readText(store().root, DRAFTS_PATH);
        return t ? JSON.parse(t) : { version: 1, cards: {} };
      }
      const r = await fetch(DRAFTS_PATH, { cache: 'no-store' });
      return r.ok ? await r.json() : { version: 1, cards: {} };
    } catch {
      return { version: 1, cards: {} };
    }
  }

  // Karte iz cards.json, nove karte iz nacrta (new: true) i nova karta koja još nije spremljena.
  const cards = () => {
    const db = env.state.db.cards;
    const fresh = Object.entries(ed.drafts?.cards ?? {}).filter(([id, d]) => d.new && !db.some(c => c.id === id)).map(([id, d]) => ({ id, ...d }));
    if (ed.work?.new && !fresh.some(c => c.id === ed.work.id)) fresh.push(ed.work);
    return [...db.filter(c => EDIT_TYPES.includes(c.type) && !c.deleted), ...fresh]
      .sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  };
  const setOf = c => c.id.split('-')[0];

  function open(id) {
    const draft = ed.drafts?.cards?.[id];
    const base = env.state.db.cards.find(c => c.id === id) ?? (draft?.new ? { id } : null);
    if (!base) { ed.id = null; ed.work = null; return; }
    ed.id = id;
    ed.base = base;
    ed.work = structuredClone({ ...base, ...(ed.drafts?.cards?.[id] ?? {}) });
    if (PORTRAIT.includes(base.type) || base.type === 'Core') ed.work.bonus ??= {};
    ed.work.traits ??= [];
    ed.work.artCrop ??= { x: 0.5, y: 0.5, zoom: 1 };
    if (HEROISH.includes(base.type)) ed.work.stats ??= {};
    ed.dirty = false;
    ed.art = null;
    ed.artFor = null;
    ed.emblem = null;
    ed.emblemFor = null;
  }

  // ---------- prikaz ----------

  function render() {
    if (!ed.ready && !ed.error) {
      load();
      return h('section', { class: 'panel' }, h('p', { class: 'muted' }, 'Loading the card editor…'));
    }
    if (ed.error) return h('section', { class: 'panel' }, h('p', { class: 'warn' }, ed.error));
    const want = env.state.editId;
    if (['publish', 'sets', 'guide', 'tags'].includes(want)) {
      ed.id = null;
      ed.work = null;
      syncLock();
      return h('div', {}, renderNav(want), { sets: sets.render, guide: guide.render, tags: renderTags, publish: renderPublish }[want]());
    }
    if (want && want !== ed.id) open(want);
    if (!want) { ed.id = null; ed.work = null; }
    syncLock();
    return h('div', {}, renderNav('edit'),
      h('div', { class: 'card-editor' }, renderList(), ed.work ? renderForm() : h('p', { class: 'muted ce-empty' }, 'Pick a card on the left.'), ed.work ? renderPreview() : null));
  }

  // Edit | Publish (broj nacrta) i "Ja sam" (Objavu klika samo Marko; dogovor, ne zaštita).
  function renderNav(view) {
    const n = Object.keys(ed.drafts?.cards ?? {}).length;
    const tab = (name, label, to) => h('button', { class: view === name ? 'primary' : 'ghost', type: 'button', onclick: () => go(to) }, label);
    return h('div', { class: 'ce-nav' },
      tab('edit', 'Edit', ed.lastId ?? null),
      tab('sets', 'Sets', 'sets'),
      tab('tags', 'Tags', 'tags'),
      tab('guide', 'Text guide', 'guide'),
      tab('publish', `Publish${n ? ` (${n})` : ''}`, 'publish'),
      h('label', { class: 'ce-who' }, 'I am ', h('select', { onchange: e => { try { localStorage.setItem(WHO_KEY, e.target.value); } catch {} env.render(); } },
        ['', 'Marko', 'Tarik'].map(x => h('option', { value: x, selected: x === who() }, x || '–')))));
  }

  // Filteri popisa gledaju kartu s nacrtom (art i status se mijenjaju u nacrtu).
  const SHOW = [['', 'Everything'], ['noart', 'No art'], ['fx', 'Needs fx'], ['draft', 'Status: draft'], ['review', 'Status: review'], ['done', 'Status: done'], ['unpublished', 'Unpublished changes']];
  const needsFx = c => !!(c.text ?? '').trim() && !['Stage', 'Core'].includes(c.type) && (!c.fx || c.fxStatus === 'check');
  const heroOf = c => (HEROISH.includes(c.type) ? c.hero || c.name : c.traits?.[0]);
  const shown = () => {
    const q = ed.q.trim().toLowerCase();
    return cards().filter(c => {
      const m = { ...c, ...(ed.drafts?.cards?.[c.id] ?? {}) };
      if (ed.set && setOf(c) !== ed.set) return false;
      if (ed.type && c.type !== ed.type) return false;
      if (ed.color && m.color !== ed.color) return false;
      if (ed.hero && heroOf(m) !== ed.hero) return false;
      if (ed.show === 'noart' && m.art) return false;
      if (ed.show === 'fx' && !needsFx(m)) return false;
      if (['draft', 'review', 'done'].includes(ed.show) && (m.status ?? 'draft') !== ed.show) return false;
      if (ed.show === 'unpublished' && !ed.drafts?.cards?.[c.id]) return false;
      return !q || `${c.id} ${m.name}`.toLowerCase().includes(q);
    });
  };

  function renderList() {
    const sets = [...new Set(cards().map(setOf))];
    return h('aside', { class: 'ce-list' },
      h('div', { class: 'ce-list-head' },
        h('select', { 'aria-label': 'Set', onchange: e => { ed.set = e.target.value; env.render(); } },
          h('option', { value: '' }, 'All sets'), sets.map(s => h('option', { value: s, selected: s === ed.set }, s))),
        h('select', { 'aria-label': 'Type', onchange: e => { ed.type = e.target.value; env.render(); } },
          h('option', { value: '' }, 'All types'), EDIT_TYPES.map(t => h('option', { value: t, selected: t === ed.type }, t)))),
      h('input', { class: 'ce-find', type: 'search', placeholder: 'Find', value: ed.q, oninput: e => { ed.q = e.target.value; refreshList(); } }),
      h('div', { class: 'ce-list-head' },
        h('select', { 'aria-label': 'Colour', onchange: e => { ed.color = e.target.value; env.render(); } },
          h('option', { value: '' }, 'All colours'), COLORS.map(c => h('option', { value: c, selected: c === ed.color }, c))),
        h('select', { 'aria-label': 'Hero', onchange: e => { ed.hero = e.target.value; env.render(); } },
          h('option', { value: '' }, 'All heroes'), heroNames().map(n => h('option', { value: n, selected: n === ed.hero }, n)))),
      h('select', { class: 'ce-find', 'aria-label': 'Show', onchange: e => { ed.show = e.target.value; env.render(); } },
        SHOW.map(([v, label]) => h('option', { value: v, selected: v === ed.show }, label))),
      h('p', { class: 'muted small' }, `${shown().length} of ${cards().length}`),
      renderNew(sets),
      h('ul', { id: 'ce-items' }, shown().map(c => item(c))));
  }

  // Nova karta: set i tip; kod je sljedeći slobodni broj u setu (cards.json i nacrti).
  function renderNew(sets) {
    if (!ed.newOpen) return h('button', { class: 'ghost ce-new', type: 'button', onclick: () => { ed.newOpen = true; env.render(); } }, '+ New card');
    const setSel = h('select', { 'aria-label': 'Set' }, sets.map(x => h('option', { value: x, selected: x === (ed.set || sets.find(y => !['Stage', 'Core'].includes(y))) }, x)));
    const typeSel = h('select', { 'aria-label': 'Type' }, EDIT_TYPES.map(t => h('option', { value: t, selected: t === (ed.type || 'Action') }, t)));
    // Stage i Core imaju svoje setove (Stage-001, Core-001).
    const sync = () => { if (['Stage', 'Core'].includes(typeSel.value)) setSel.value = typeSel.value; else if (['Stage', 'Core'].includes(setSel.value)) setSel.value = sets.find(y => !['Stage', 'Core'].includes(y)) ?? setSel.value; };
    typeSel.addEventListener('change', sync);
    sync();
    return h('div', { class: 'ce-new-form' },
      h('div', { class: 'ce-list-head' }, setSel, typeSel),
      h('div', { class: 'ce-list-head' },
        h('button', { class: 'primary', type: 'button', onclick: () => newCard(setSel.value, typeSel.value) }, 'Create'),
        h('button', { class: 'ghost', type: 'button', onclick: () => { ed.newOpen = false; env.render(); } }, 'Cancel')));
  }

  const heroNames = () => env.state.db.cards.filter(c => c.type === 'Hero' && !c.deleted).map(c => c.name).sort();

  // Duplikat: ista karta pod sljedećim kodom u istom setu, kao nova karta (nacrt do Objave).
  function duplicate() {
    const w = ed.work;
    if (ed.dirty && !confirm('Discard the unsaved changes to this card?')) return;
    const id = nextId(setOf(w));
    const copy = structuredClone(w);
    for (const k of ['image', 'imageHash', 'imageRot', 'imageRotHash', 'sprite', 'spriteHash', 'rev', 'deleted', 'fx', 'fxStatus', 'aliases']) delete copy[k];
    ed.id = id;
    ed.base = { id };
    ed.work = { ...copy, id, new: true, name: `${w.name ?? ''} (copy)`, status: 'draft' };
    ed.dirty = true;
    ed.art = ed.artFor = ed.emblem = ed.emblemFor = null;
    env.go(id);
  }

  function nextId(set) {
    const ids = [...env.state.db.cards.map(c => c.id), ...Object.keys(ed.drafts?.cards ?? {})];
    const nums = ids.filter(id => id.startsWith(`${set}-`)).map(id => Number(id.slice(set.length + 1))).filter(Number.isFinite);
    return `${set}-${String(Math.max(0, ...nums) + 1).padStart(3, '0')}`;
  }

  const NEW_DEFAULTS = {
    Action: { color: 'Cyan', cost: 1, bonus: {}, traits: ['General'], text: '' },
    Hero: { color: 'Cyan', stats: { hp: 8, dmg: 3, pwr: 2000, rng: 2, kb: 2 }, traits: [], abilityNames: [''], text: '' },
    Evolution: { color: 'Cyan', cost: 4, evo: 1, hero: '', stats: { hp: 8, dmg: 4, pwr: 3000, rng: 2, kb: 2 }, traits: [], abilityNames: [''], text: '' },
    Stage: { color: null, traits: [], text: 'Terrain: None', terrain: 'None' },
    Core: { color: null, traits: ['Buff'], bonus: { pwr: 1000 }, text: '' },
  };

  function newCard(set, type) {
    if (ed.dirty && !confirm('Discard the unsaved changes to this card?')) return;
    const id = nextId(set);
    const defaults = NEW_DEFAULTS[type] ?? NEW_DEFAULTS.Action;
    ed.id = id;
    ed.base = { id };
    ed.work = { id, new: true, name: '', type, ...structuredClone(defaults), artCrop: { x: 0.5, y: 0.5, zoom: 1 }, status: 'draft' };
    ed.work.bonus ??= {};
    ed.dirty = true;
    ed.art = ed.artFor = ed.emblem = ed.emblemFor = null;
    ed.newOpen = false;
    env.go(id);
  }

  function item(c) {
    const draft = ed.drafts?.cards?.[c.id];
    return h('li', {},
      h('button', { class: `ce-item${c.id === ed.id ? ' active' : ''}`, onclick: () => go(c.id) },
        h('span', { class: `ce-dot c-bg-${c.color}` }),
        h('span', { class: 'ce-id' }, c.id), ' ', c.name,
        draft ? h('span', { class: 'ce-draft', title: `Unpublished changes${draft.who ? ` by ${draft.who}` : ''}` }, '●') : null));
  }

  function refreshList() {
    const ul = document.getElementById('ce-items');
    if (!ul) return;
    ul.replaceChildren(...shown().map(item));
  }

  function go(id) {
    if (ed.dirty && id !== ed.id && !confirm('Discard the unsaved changes to this card?')) return;
    ed.dirty = false;
    if (ed.id) ed.lastId = ed.id;
    env.go(id);
  }

  function renderForm() {
    const w = ed.work;
    const db = env.state.db;
    const traits = traitNames(env.state.traits?.traits);
    const heroes = db.cards.filter(c => c.type === 'Hero' && !c.deleted && c.color === w.color);
    const portrait = PORTRAIT.includes(w.type);
    const heroish = HEROISH.includes(w.type);
    const set = (k, v) => { w[k] = v; changed(); };
    const field = (label, input, hint) => h('label', { class: 'ce-field' }, h('span', {}, label), input, hint ? h('small', { class: 'muted' }, hint) : null);
    const num = (value, oninput, opts = {}) => h('input', { type: 'number', value: value ?? '', placeholder: '–', oninput, ...opts });
    const sugBox = h('div', { class: 'ce-suggest' });
    const text = h('textarea', { rows: 5, value: w.text ?? '', oninput: e => { set('text', e.target.value); showSuggest(); } });
    // Prijedlozi iz vodiča za riječ ispred kursora; klik ili Tab zamijeni započeti dio frazom.
    let sug = { from: 0, items: [] };
    const take = item => {
      const at = text.selectionStart ?? text.value.length;
      text.value = text.value.slice(0, sug.from) + item.insert + text.value.slice(at);
      text.selectionStart = text.selectionEnd = sug.from + item.insert.length;
      text.focus();
      set('text', text.value);
      showSuggest();
    };
    const showSuggest = () => {
      sug = suggest(ed.guide, text.value, text.selectionStart ?? text.value.length);
      sugBox.replaceChildren(...sug.items.map((it, i) => h('button', { type: 'button', class: 'ghost', title: i ? '' : 'Tab', onclick: () => take(it) }, it.label)));
    };
    text.addEventListener('keydown', e => { if (e.key === 'Tab' && sug.items.length) { e.preventDefault(); take(sug.items[0]); } });
    text.addEventListener('click', showSuggest);
    text.addEventListener('blur', () => setTimeout(() => { if (document.activeElement !== text && !sugBox.contains(document.activeElement)) sugBox.replaceChildren(); }, 150));
    const insert = s => {
      const a = text.selectionStart ?? text.value.length;
      const b = text.selectionEnd ?? a;
      text.value = text.value.slice(0, a) + s + text.value.slice(b);
      text.selectionStart = text.selectionEnd = a + s.length;
      text.focus();
      set('text', text.value);
    };
    const bonusRow = keys => h('div', { class: 'ce-row' }, keys.map(([k, label]) => field(label, num(w.bonus[k], e => {
      const b = { ...w.bonus };
      if (e.target.value === '' || Number(e.target.value) === 0) delete b[k]; else b[k] = Number(e.target.value);
      set('bonus', b);
    }, { step: k === 'pwr' ? 1000 : 1 }))));
    const tagsList = (label, from, hint) => field(label, h('input', { list: 'ce-traits', value: w.traits.slice(from).join(', '), placeholder: 'Sword, Devil Fruit',
      oninput: e => set('traits', [...w.traits.slice(0, from), ...e.target.value.split(',').map(s => s.trim()).filter(Boolean)]) }), hint);

    // Vrsta karte određuje polja: uspravne akcije, heroji i evolucije, Stage, Core.
    let body;
    if (portrait) {
      const firstOptions = ['General', ...heroes.map(x => x.name), ...traits];
      if (w.traits[0] && !firstOptions.includes(w.traits[0])) firstOptions.push(w.traits[0]);
      body = [
        bonusRow(BONUS_KEYS),
        h('div', { class: 'ce-row' },
          field('First tag', h('select', { onchange: e => set('traits', [e.target.value, ...w.traits.slice(1)]) },
            h('option', { value: '' }, '–'), firstOptions.map(t => h('option', { value: t, selected: t === w.traits[0] }, t))), 'Who may play it.'),
          tagsList('Other tags', 1, 'For effects ("for every {Sword}"), comma between.')),
        field('Text', text), sugBox, inserts(insert),
      ];
    } else if (heroish) {
      const evoHeroes = db.cards.filter(c => c.type === 'Hero' && !c.deleted && c.color === w.color);
      body = [
        h('div', { class: 'ce-row' }, STAT_KEYS.map(([k, label]) => field(label, num(w.stats[k], e => {
          set('stats', { ...w.stats, [k]: e.target.value === '' ? undefined : Number(e.target.value) });
        }, { step: k === 'pwr' ? 1000 : 1 })))),
        h('div', { class: 'ce-row' },
          field('Ability name', h('input', { value: w.abilityNames?.[0] ?? '', oninput: e => set('abilityNames', [e.target.value, ...(w.abilityNames ?? []).slice(1)]) }), 'Bold and underlined above the text.'),
          w.type === 'Evolution' ? field('Level', h('select', { onchange: e => set('evo', Number(e.target.value)) }, [1, 2, 3].map(n => h('option', { value: n, selected: n === (w.evo ?? 1) }, `EVO ${n}`)))) : null,
          w.type === 'Evolution' ? field('Hero', h('select', { onchange: e => set('hero', e.target.value) },
            h('option', { value: '' }, '–'), evoHeroes.map(x => h('option', { value: x.name, selected: x.name === w.hero }, x.name)))) : null),
        tagsList('Tags', 0, 'Comma between.'),
        w.type === 'Hero' ? field('Aliases', h('input', { value: (w.aliases ?? []).join(', '), placeholder: 'Luffy, Straw Hat',
          oninput: e => set('aliases', e.target.value.split(',').map(x => x.trim()).filter(Boolean)) }), 'Other names a card\'s first tag may use for this hero.') : null,
        field('Text', text), sugBox, inserts(insert),
        h('fieldset', { class: 'ce-art' },
          h('legend', {}, 'Plate and background'),
          h('div', { class: 'ce-row' },
            field('Emblem', h('input', { type: 'file', accept: 'image/png,image/webp', disabled: !canWrite(), onchange: e => env.guard(() => uploadEmblem(e.target.files[0])) }),
              w.emblem ? `data/${w.emblem}` : 'None yet: a PNG with a clear background.'),
            field('Background behind the art', h('div', { class: 'ce-row' },
              h('input', { id: 'ce-bg', type: 'color', value: w.bg || ed.tpl?.layout?.bg?.[w.color] || '#000000', oninput: e => set('bg', e.target.value) }),
              w.bg ? h('button', { type: 'button', class: 'ghost', onclick: () => { delete w.bg; changed(); env.render(); } }, 'Colour default') : null)))),
      ];
    } else if (w.type === 'Stage') {
      body = [
        field('Terrain', h('select', { onchange: e => { setTerrain(e.target.value); env.render(); } },
          TERRAINS.map(t => h('option', { value: t, selected: t === (w.terrain ?? 'None') }, t))), 'Also writes the "Terrain:" line of the text.'),
        field('Text', text), sugBox, inserts(insert),
      ];
    } else {
      body = [
        field('Kind', h('select', { onchange: e => set('traits', [e.target.value]) },
          h('option', { value: '' }, '–'), CORE_KINDS.map(k => h('option', { value: k, selected: k === w.traits[0] }, k)))),
        bonusRow(BONUS_KEYS.filter(([k]) => ['pwr', 'dmg', 'kb'].includes(k))),
        field('Text', text, 'Only for a Core with an effect beyond its bonus.'),
      ];
    }

    const crop = (k, min, max, step) => h('input', { type: 'range', min, max, step, value: w.artCrop[k], oninput: e => { w.artCrop = { ...w.artCrop, [k]: Number(e.target.value) }; changed(); } });
    const group = portrait ? PORTRAIT : [w.type];
    return h('form', { class: 'ce-form', onsubmit: e => { e.preventDefault(); env.guard(saveDraft); } },
      h('div', { class: 'ce-title' },
        h('h2', {}, `${w.id}`),
        ed.drafts?.cards?.[w.id] ? h('span', { class: 'chip warn' }, 'unpublished') : null,
        ed.lock?.state === 'mine' ? h('span', { class: 'chip', title: 'Locked for you while it is open' }, '🔒 yours') : null),
      renderLock(),
      field('Name', h('input', { value: w.name ?? '', oninput: e => set('name', e.target.value) }), w.type === 'Evolution' ? '"Hero, Evolution name": the part after the comma is the big title.' : null),
      h('div', { class: 'ce-row' },
        field('Type', group.length > 1
          ? h('select', { onchange: e => set('type', e.target.value) }, group.map(t => h('option', { value: t, selected: t === w.type }, t)))
          : h('input', { value: w.type, disabled: true })),
        portrait || heroish ? field('Colour', h('select', { onchange: e => { set('color', e.target.value); env.render(); } }, COLORS.map(c => h('option', { value: c, selected: c === w.color }, c)))) : null,
        portrait || w.type === 'Evolution' ? field('Cost', num(w.cost ?? 0, e => set('cost', e.target.value === '' ? null : Number(e.target.value)), { min: 0, max: 10 })) : null),
      ...body,
      h('datalist', { id: 'ce-traits' }, traits.map(t => h('option', { value: t }))),
      h('fieldset', { class: 'ce-art' },
        h('legend', {}, w.type === 'Core' ? 'Image' : 'Art'),
        h('input', { type: 'file', accept: 'image/png,image/jpeg,image/webp', disabled: !canWrite(), onchange: e => env.guard(() => uploadArt(e.target.files[0])) }),
        w.art ? h('small', { class: 'muted' }, `data/${w.art}`) : h('small', { class: 'warn' }, w.type === 'Core' ? 'No image yet: the hexagon on a clear background, 1500×2100.' : 'No art yet.'),
        w.type === 'Core' ? null : [
          h('div', { class: 'ce-row' }, field('Zoom', crop('zoom', 0.5, 3, 0.01)), field('Left ↔ right', crop('x', 0, 1, 0.002)), field('Up ↕ down', crop('y', 0, 1, 0.002))),
          h('small', { class: 'muted' }, 'Or drag the picture in the preview; the wheel zooms.')]),
      h('div', { class: 'ce-row' },
        field('Status', h('select', { onchange: e => set('status', e.target.value) }, STATUSES.map(s => h('option', { value: s, selected: s === (w.status ?? 'draft') }, s)))),
        field('Notes', h('input', { value: w.notes ?? '', placeholder: 'For Marko or Tarik', oninput: e => set('notes', e.target.value) }))),
      h('div', { class: 'ce-actions' },
        h('button', { class: 'primary', type: 'submit', disabled: !canWrite() || ed.lock?.state === 'other' }, 'Save draft'),
        ed.drafts?.cards?.[w.id] ? h('button', { type: 'button', class: 'ghost', disabled: !canWrite(), onclick: () => env.guard(discardDraft) }, 'Discard draft') : null,
        h('button', { type: 'button', class: 'ghost', onclick: () => downloadPng() }, 'Download PNG'),
        h('button', { type: 'button', class: 'ghost', onclick: () => duplicate(), title: 'A new card with the next code in this set' }, 'Duplicate'),
        canWrite() ? null : h('small', { class: 'muted' }, 'Saving needs the shared folder (Chrome or Edge on a computer).')));
  }

  const inserts = insert => h('div', { class: 'ce-inserts' }, INSERTS.map(([label, s]) => h('button', { type: 'button', class: 'ghost', onclick: () => insert(s) }, label)),
    ed.guide?.phrases?.length ? h('select', { 'aria-label': 'Insert a phrase', onchange: e => { const p = ed.guide.phrases[Number(e.target.value)]; e.target.value = ''; if (p) insert(p.text); } },
      h('option', { value: '' }, 'Phrase from the guide…'), ed.guide.phrases.map((p, i) => h('option', { value: i, title: p.note ?? '' }, `${p.label}: ${p.text.trim()}`))) : null);

  // Terrain je i polje karte i zadnji red teksta ("Terrain: Ice"), kao na Card Engine kartama.
  function setTerrain(t) {
    const w = ed.work;
    w.terrain = t;
    const line = `Terrain: ${t}`;
    const txt = w.text ?? '';
    w.text = /^Terrain:.*$/m.test(txt) ? txt.replace(/^Terrain:.*$/m, line) : `${txt.trimEnd()}${txt.trim() ? '\n' : ''}${line}`;
    changed();
  }

  function renderPreview() {
    const wide = landscape(ed.work);
    ed.canvas = h('canvas', { class: `ce-canvas${wide ? ' wide' : ''}`, width: wide ? 2100 : 1500, height: wide ? 1500 : 2100 });
    ed.warnBox = h('ul', { class: 'ce-warnings' });
    ed.diffBox = h('div', { class: 'ce-diff' });
    ed.fxBox = h('div', { class: 'ce-fx' });
    hookDrag(ed.canvas);
    queueDraw();
    return h('section', { class: 'ce-preview' }, ed.canvas, ed.warnBox, ed.fxBox, ed.diffBox,
      ed.agency ? null : h('p', { class: 'warn small' }, 'Agency FB is not on this computer: a stand-in font is shown. PNGs are made on a computer that has it.'));
  }

  // ---------- zaključavanje ----------

  // Otvorena karta je zaključana na "Ja sam" dok je otvorena; tuđi lock gasi spremanje.
  async function readLock(id) {
    try { return JSON.parse((await fs.readText(store().root, lockPath(id))) ?? 'null'); } catch { return null; }
  }

  function syncLock() {
    const want = ed.id && canWrite() && who() ? { id: ed.id, who: who() } : null;
    if (ed.lock?.id === want?.id && ed.lock?.who === want?.who) return;
    releaseLock();
    if (want) claimLock(want.id, want.who);
  }

  async function claimLock(id, me, force = false) {
    ed.lock = { id, who: me, state: 'checking' };
    const old = await readLock(id);
    const st = lockState(old, me);
    if (st === 'other' && !force) {
      if (ed.lock?.id === id) { ed.lock = { id, who: me, state: 'other', other: old }; env.render(); }
      return;
    }
    const since = st === 'mine' ? old.since : null;
    await fs.writeFile(store().root, lockPath(id), JSON.stringify(newLock(me, new Date(), since)) + '\n');
    if (ed.lock?.id !== id) return;
    ed.lock = { id, who: me, state: 'mine', since: since ?? new Date().toISOString() };
    ed.lock.beat = setInterval(() => {
      if (ed.lock?.id === id && ed.lock.state === 'mine') fs.writeFile(store().root, lockPath(id), JSON.stringify(newLock(me, new Date(), ed.lock.since)) + '\n').catch(() => {});
    }, HEARTBEAT_MS);
    // Drugi stroj je možda zaključao u isto vrijeme: Syncthing to donese za par sekundi.
    if (!force) setTimeout(async () => {
      if (ed.lock?.id !== id || ed.lock.state !== 'mine') return;
      const now = await readLock(id);
      if (now?.who && now.who !== me && lockState(now, me) === 'other') {
        clearInterval(ed.lock.beat);
        ed.lock = { id, who: me, state: 'other', other: now };
        env.render();
      }
    }, SETTLE_MS);
    env.render();
  }

  function releaseLock() {
    const l = ed.lock;
    ed.lock = null;
    if (!l) return;
    clearInterval(l.beat);
    if (l.state !== 'mine' || !canWrite()) return;
    readLock(l.id).then(now => { if (now?.who === l.who) return fs.removeFile(store().root, lockPath(l.id)); }).catch(() => {});
  }
  window.addEventListener('beforeunload', () => releaseLock());

  function renderLock() {
    const l = ed.lock;
    if (canWrite() && !who()) return h('p', { class: 'muted small' }, 'Set "I am" at the top: the card is then locked for you while you edit it.');
    if (l?.state !== 'other') return null;
    const since = l.other?.since ? new Date(l.other.since).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '?';
    return h('div', { class: 'ce-lock warn' },
      `${l.other?.who ?? 'Someone'} is editing this card (since ${since}). Saving is off until they leave it.`,
      h('button', { type: 'button', class: 'ghost', onclick: () => env.guard(() => { releaseLock(); return claimLock(ed.id, who(), true); }) }, 'Take over'));
  }

  // ---------- tagovi ----------

  // Svi tagovi na kartama (s nacrtima): koliko karata ga ima prvog (tko smije) i koliko među ostalima.
  function renderTags() {
    const counts = new Map();
    for (const c of cards()) {
      const m = { ...c, ...(ed.drafts?.cards?.[c.id] ?? {}) };
      (m.traits ?? []).forEach((t, i) => {
        if (!t) return;
        const row = counts.get(t) ?? { first: 0, other: 0 };
        if (i === 0 && !HEROISH.includes(m.type)) row.first++; else row.other++;
        counts.set(t, row);
      });
    }
    const rows = [...counts.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    return h('section', { class: 'panel ce-tags' },
      h('div', { class: 'ce-title' }, h('h2', {}, 'Tags'),
        env.openTab ? h('button', { class: 'ghost', type: 'button', onclick: () => env.openTab('traits') }, 'Trait list and descriptions →') : null),
      h('p', { class: 'muted' }, 'Every tag on the cards. Renaming changes it on every card as drafts (Publish puts them into the game). The trait list with descriptions, which the first tag rule uses, is on the Traits tab; hero aliases are on each hero card here.'),
      h('table', { class: 'ce-pub-table' },
        h('thead', {}, h('tr', {}, ['Tag', 'First tag on', 'Other tag on', 'Rename to', ''].map(t => h('th', {}, t)))),
        h('tbody', {}, rows.map(([tag, n]) => {
          const to = h('input', { placeholder: tag });
          return h('tr', {}, h('td', {}, h('strong', {}, tag)), h('td', { class: 'num' }, n.first || '–'), h('td', { class: 'num' }, n.other || '–'),
            h('td', {}, to),
            h('td', {}, h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), onclick: () => env.guard(() => renameTag(tag, to.value.trim())) }, 'Rename')));
        }))));
  }

  // Preimenovanje taga na svim kartama kao nacrti (karta kojoj se vrati objavljeni popis ostane bez nacrta za tagove).
  async function renameTag(from, to) {
    if (!to || to === from) throw new Error('Write the new name first.');
    if (ed.dirty) throw new Error('Save or discard the open card first.');
    const fresh = await readDrafts();
    fresh.cards ??= {};
    const db = env.state.db.cards;
    let n = 0;
    for (const c of cards()) {
      const d = fresh.cards[c.id] ?? {};
      const traits = d.traits ?? c.traits ?? [];
      if (!traits.includes(from)) continue;
      const next = [...new Set(traits.map(t => (t === from ? to : t)))];
      const base = db.find(x => x.id === c.id);
      const nd = { ...d, traits: next, updated: new Date().toISOString(), who: who() || undefined };
      if (base && sameVal(next, base.traits)) delete nd.traits;
      if (Object.keys(nd).every(k => k === 'updated' || k === 'who')) delete fresh.cards[c.id];
      else fresh.cards[c.id] = nd;
      n++;
    }
    if (!n) throw new Error(`No card has the tag ${from}.`);
    await fs.writeFile(store().root, DRAFTS_PATH, JSON.stringify(fresh, null, 2) + '\n');
    ed.drafts = fresh;
    if (ed.id) open(ed.id);
    const inList = (env.state.traits?.traits ?? []).some(t => t.name === from);
    env.toast(`${from} → ${to} on ${n} ${n === 1 ? 'card' : 'cards'} (drafts).${inList ? ` ${from} is on the trait list: rename it on the Traits tab too.` : ''}`);
    env.render();
  }

  // ---------- objava ----------

  const KEEP = new Set(['updated', 'who']);
  const draftList = () => Object.entries(ed.drafts?.cards ?? {})
    .map(([id, d]) => ({ id, d, base: env.state.db.cards.find(c => c.id === id) }))
    .sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));

  // Zadnja Objava i Undo (samo Marko, dok se baza nije mijenjala).
  function renderLast(marko) {
    if (!canWrite()) return null;
    if (ed.last === undefined || ed.last === null) {
      ed.last = false;
      readLast().then(l => { ed.last = l ?? false; if (l) env.render(); });
      return null;
    }
    const l = ed.last;
    if (!l) return null;
    const ok = env.state.db.updated === l.after.updated;
    return h('div', { class: 'ce-last' },
      h('span', {}, `Last Publish: ${new Date(l.at).toLocaleString()}${l.who ? ` by ${l.who}` : ''}, ${Object.keys(l.drafts).length} cards${l.bumped ? `, version ${l.after.version}` : ''}.`),
      ok ? h('button', { class: 'ghost', type: 'button', disabled: !marko, onclick: () => env.guard(undoPublish) }, 'Undo last Publish')
        : h('small', { class: 'muted' }, 'Cards changed since then, so it can no longer be undone.'));
  }

  function renderPublish() {
    const list = draftList();
    const marko = who() === 'Marko';
    const why = !canWrite() ? 'Publishing needs the shared folder (Chrome or Edge on a computer).'
      : !marko ? 'Only Marko publishes (set "I am" to Marko).'
      : !ed.agency ? 'Agency FB is not on this computer: the card PNGs must be made on a computer that has it.'
      : !list.length ? 'Nothing waits for Publish.' : null;
    return h('section', { class: 'panel ce-publish' },
      h('h2', {}, 'Waiting for Publish'),
      h('p', { class: 'muted' }, 'Drafts saved in the Card editor. Publish draws each card\'s PNG, writes the cards into cards.json (with history) and makes the small and large images. The game sees them after that.'),
      list.length ? h('table', { class: 'ce-pub-table' },
        h('thead', {}, h('tr', {}, ['Card', 'Changes', 'By', 'Saved', 'Status', ''].map(t => h('th', {}, t)))),
        h('tbody', {}, list.map(({ id, d, base }) => {
          const card = { ...(base ?? {}), ...d };
          const fields = Object.keys(d).filter(k => !KEEP.has(k));
          return h('tr', {},
            h('td', {}, h('span', { class: 'ce-id' }, id), ' ', card.name ?? '?', base ? null : h('small', { class: 'chip' }, ' new')),
            h('td', {}, d.new ? 'new card' : fields.join(', ') || '–', card.art ? null : h('small', { class: d.new ? 'warn' : 'muted' }, d.new ? ' · no art: waits until it has art' : ' · no art: the old picture stays')),
            h('td', {}, d.who || '–'),
            h('td', {}, d.updated ? new Date(d.updated).toLocaleString() : '–'),
            h('td', {}, h('span', { class: `chip${card.status === 'done' ? '' : ' warn'}` }, card.status ?? 'draft')),
            h('td', {}, h('button', { class: 'ghost', type: 'button', onclick: () => go(id) }, 'Open')));
        }))) : null,
      renderLast(marko),
      h('div', { class: 'ce-actions' },
        h('button', { class: 'primary', type: 'button', disabled: !!why, onclick: () => env.guard(publishAll) }, `Publish ${list.length} ${list.length === 1 ? 'card' : 'cards'}`),
        why ? h('small', { class: 'muted' }, why) : null));
  }

  async function readLast() {
    try { return JSON.parse((await fs.readText(store().root, LAST_PUBLISH_PATH)) ?? 'null'); } catch { return null; }
  }

  // Undo zadnje Objave: baza kakva je bila prije nje (pod novom verzijom, da igra i deckovi vide promjenu),
  // nove slike van, objavljeni nacrti opet čekaju. Samo dok se baza u međuvremenu nije mijenjala.
  async function undoPublish() {
    await env.assertFresh();
    const last = await readLast();
    if (!last) throw new Error('No Publish to undo.');
    const db = env.state.db;
    if (db.updated !== last.after.updated) throw new Error('The cards changed after that Publish (Import or another save), so it can no longer be undone.');
    if (!confirm(`Undo the Publish of ${new Date(last.at).toLocaleString()} (${Object.keys(last.drafts).length} cards)? The cards go back to how they were and wait as drafts again.`)) return;
    const restored = { ...last.before, version: db.version + (last.bumped ? 1 : 0), updated: new Date().toISOString() };
    await env.commitDb(restored);
    const after = await readDrafts();
    after.cards ??= {};
    for (const [id, d] of Object.entries(last.drafts)) after.cards[id] ??= d;
    await fs.writeFile(store().root, DRAFTS_PATH, JSON.stringify(after, null, 2) + '\n');
    await fs.removeFile(store().root, LAST_PUBLISH_PATH).catch(() => {});
    ed.drafts = after;
    ed.last = null;
    env.toast(`Publish undone: ${Object.keys(last.drafts).length} cards are drafts again${last.bumped ? ` (version ${restored.version})` : ''}.`);
    env.render();
  }

  // Objava: PNG svake karte s artom (renderer), baza i povijest (env.commitDb), pa se nacrti brišu.
  // Karta bez arta zadržava staru sliku (Card Engine PNG); mijenjaju joj se samo polja.
  async function publishAll() {
    await env.assertFresh();
    const fresh = await readDrafts();
    const drafts = fresh.cards ?? {};
    const ids = Object.keys(drafts);
    if (!ids.length) throw new Error('Nothing waits for Publish.');
    if (!confirm(`Publish ${ids.length} ${ids.length === 1 ? 'card' : 'cards'} into the game?`)) return;
    // Nova Objava: Undo prethodne više nije moguć, pa njene stare slike mogu van.
    await env.dropOldImages();
    const before = env.state.db;
    const images = {};
    const kept = [];
    for (const id of ids) {
      const base = env.state.db.cards.find(c => c.id === id) ?? (drafts[id].new ? { id } : null);
      if (!base) continue;
      const card = { ...base, ...drafts[id] };
      const url = card.art ? await store().dataUrl(card.art) : null;
      const art = url ? await loadImage(url).catch(() => null) : null;
      // Nova karta bez arta čeka (igra treba sliku); postojeća zadrži staru.
      if (!art) { if (drafts[id].new) delete drafts[id]; kept.push(id); continue; }
      const eUrl = card.emblem ? await store().dataUrl(card.emblem) : null;
      const emblem = eUrl ? await loadImage(eUrl).catch(() => null) : null;
      const canvas = document.createElement('canvas');
      renderCard(canvas, card, await templateFor(card), art, emblem);
      const blob = await new Promise(r => canvas.toBlob(r, 'image/png'));
      const bytes = new Uint8Array(await blob.arrayBuffer());
      const hash = await imageHashOf(bytes);
      if (hash === base.imageHash) continue;
      await fs.writeFile(store().root, `data/images/${id}.${hash}.png`, bytes);
      images[id] = hash;
    }
    const { db, changed, bumped } = applyDrafts(env.state.db, drafts, images);
    const done = changed ? await env.commitDb(db, { keepOld: true }) : { old: 0, thumbs: 0 };
    if (changed) {
      const published = Object.fromEntries(ids.filter(id => drafts[id]).map(id => [id, drafts[id]]));
      await fs.writeFile(store().root, LAST_PUBLISH_PATH, JSON.stringify({ at: new Date().toISOString(), who: who(), bumped, after: { version: db.version, updated: db.updated }, drafts: published, before }) + '\n');
      ed.last = null;
    }
    // Nacrti spremljeni dok je Objava trajala ostaju za iduću.
    const after = await readDrafts();
    for (const id of ids) if (drafts[id] && after.cards?.[id]?.updated === drafts[id].updated) delete after.cards[id];
    await fs.writeFile(store().root, DRAFTS_PATH, JSON.stringify(after, null, 2) + '\n');
    ed.drafts = after;
    const parts = [`${changed} ${changed === 1 ? 'card' : 'cards'}`, `${Object.keys(images).length} new PNGs`];
    if (done.thumbs) parts.push(`${done.thumbs} resized images`);
    if (kept.length) parts.push(`no art yet (old picture kept, new cards wait): ${kept.join(', ')}`);
    env.toast(`Published${bumped ? ` (version ${db.version})` : changed ? ' (look only)' : ''}: ${parts.join(', ')}. Next: fx proposals for the Effect tab.`);
    env.render();
  }

  // ---------- crtanje ----------

  function changed() {
    ed.dirty = true;
    queueDraw();
  }

  // Više izmjena u istom trenutku daje jedno crtanje.
  function queueDraw() {
    if (ed.frame) return;
    ed.frame = 1;
    setTimeout(async () => {
      ed.frame = 0;
      await draw();
    }, 0);
  }

  async function draw() {
    const w = ed.work;
    if (!w || !ed.canvas) return;
    const tpl = await templateFor(w);
    ed.tpl = tpl;
    if (ed.artFor !== w.art) {
      ed.artFor = w.art;
      const url = w.art ? await store().dataUrl(w.art) : null;
      ed.art = url ? await loadImage(url).catch(() => null) : null;
    }
    if (ed.emblemFor !== w.emblem) {
      ed.emblemFor = w.emblem;
      const url = w.emblem ? await store().dataUrl(w.emblem) : null;
      ed.emblem = url ? await loadImage(url).catch(() => null) : null;
    }
    if (w !== ed.work || !ed.canvas) return;
    // Predložak stiže tek sad: zadana boja pozadine heroja za ovu boju karte.
    const bgInput = document.getElementById('ce-bg');
    if (bgInput && !w.bg && tpl.layout.bg?.[w.color]) bgInput.value = tpl.layout.bg[w.color];
    const warnings = renderCard(ed.canvas, w, tpl, ed.art, ed.emblem);
    warnings.push(...checks(w));
    ed.warnBox.replaceChildren(...warnings.map(x => h('li', {}, x)));
    ed.diffBox.replaceChildren(...renderDiff(w));
    ed.fxBox.replaceChildren(...renderFx(w));
  }

  // Kako igra čita tekst (data/fx-proposals.json, piše ga game/tools/fx_proposals.gd nakon Objave).
  // fx se potvrđuje na kartici Effect u pregledu karte (GDD 14), ne ovdje.
  function renderFx(w) {
    if (['Stage', 'Core'].includes(w.type) || !(w.text ?? '').trim()) return [];
    const p = env.state.fxProposals?.cards?.[w.id];
    const changed = !w.new && (w.text ?? '') !== (ed.base.text ?? '');
    const code = t => h('pre', { class: 'fx-code' }, t);
    let body;
    if (w.new || changed) body = [h('p', { class: 'small' }, 'The text is new or changed: the game reads it again after Publish (Claude runs the fx proposals), then the Effect tab shows whether it needs an fx.')];
    else if (ed.base.fx) body = [h('p', { class: 'small' }, ed.base.fxStatus === 'check' ? 'Confirmed fx, but the text changed after it: check it on the Effect tab.' : 'Confirmed fx (the game uses it):'), code(ed.base.fx)];
    else if (!p) body = [h('p', { class: 'small muted' }, 'No report from the game for this card yet.')];
    else if (p.unparsed?.length) body = [h('p', { class: 'small warn' }, 'The game does not understand part of the text:'), h('ul', { class: 'small' }, p.unparsed.map(u => h('li', {}, u))), p.proposal ? code(p.proposal) : null];
    else body = [h('p', { class: 'small' }, 'The game reads the text by itself:'), code(p.read)];
    return [h('details', { class: 'ce-fx-box', open: !!(p?.unparsed?.length && !changed) },
      h('summary', {}, 'Effect in the game'), ...body,
      env.openEffect && !w.new ? h('button', { class: 'ghost', type: 'button', onclick: () => env.openEffect(w.id) }, 'Open the Effect tab') : null)];
  }

  // Razlike prema objavljenoj karti (cards.json): staro → novo, po polju.
  function renderDiff(w) {
    if (w.new) return [h('p', { class: 'muted small' }, 'A new card: it is not in the game until Publish.')];
    const short = v => { const t = typeof v === 'string' ? v : JSON.stringify(v); return t === undefined ? '–' : t.length > 90 ? `${t.slice(0, 88)}…` : t; };
    const rows = FIELDS.filter(k => w[k] !== undefined && !sameVal(w[k], ed.base[k]));
    if (!rows.length) return [];
    return [h('p', { class: 'small' }, 'Against the published card:'),
      h('table', { class: 'ce-pub-table' }, h('tbody', {}, rows.map(k => h('tr', {},
        h('td', {}, k), h('td', { class: 'muted' }, short(ed.base[k])), h('td', {}, '→ ', short(w[k]))))))];
  }

  // Provjere dok pišeš (uz upozorenja renderera).
  function checks(w) {
    const out = [];
    if (!(w.name ?? '').trim()) out.push('No name yet.');
    if (PORTRAIT.includes(w.type)) {
      const kind = firstTag(env.state.db, w, env.state.traits?.traits);
      if (kind.kind === INVALID) out.push(`First tag: ${tagLabel(kind)}. Pick General, a hero of this colour or a trait.`);
      const e = parseEffect(w.text);
      if ((w.text ?? '').trim() && !e.phase && !/^(The equipped|Your|While|Each|All)\b/i.test(e.lines[0]?.text ?? '')) {
        out.push('The text does not start with a phase ("Battle Phase:" …). Fine for Equipment and Assist that always work.');
      }
    }
    if (HEROISH.includes(w.type)) {
      if (!w.abilityNames?.[0]) out.push('No ability name.');
      if (!w.emblem) out.push('No emblem on the plate.');
      if (w.type === 'Evolution' && !w.hero) out.push('Pick the hero this evolves from.');
    }
    if (w.type === 'Stage' && !/^Terrain:/m.test(w.text ?? '')) out.push('No "Terrain:" line: pick the terrain.');
    if (w.type === 'Core' && !CORE_KINDS.includes(w.traits[0])) out.push('Pick Buff, Major or Debuff.');
    out.push(...avoidWarnings(ed.guide, w.text));
    if (/\[(?!Range\])[^\]]*\]/i.test(w.text ?? '')) out.push('Only [Range] goes in brackets. Stats are words after the number ("3 HP", "+2000 Power"); the card shows the icon.');
    return out;
  }

  // Povlačenje arta mišem pomiče izrez, kotačić zumira.
  function hookDrag(canvas) {
    let from = null;
    canvas.addEventListener('pointerdown', e => { from = { x: e.clientX, y: e.clientY, crop: { ...ed.work.artCrop } }; canvas.setPointerCapture(e.pointerId); });
    canvas.addEventListener('pointermove', e => {
      if (!from || !ed.art || !ed.tpl?.layout.artBox) return;
      const scale = canvas.width / canvas.getBoundingClientRect().width;
      const [, , bw, bh] = ed.tpl.layout.artBox;
      const k = Math.max(bw / ed.art.width, bh / ed.art.height) * from.crop.zoom;
      ed.work.artCrop = { ...from.crop, x: from.crop.x - ((e.clientX - from.x) * scale) / (ed.art.width * k), y: from.crop.y - ((e.clientY - from.y) * scale) / (ed.art.height * k) };
      changed();
    });
    canvas.addEventListener('pointerup', () => { from = null; env.render(); });
    canvas.addEventListener('wheel', e => {
      if (ed.work.type === 'Core') return;
      e.preventDefault();
      const z = Math.min(3, Math.max(0.5, ed.work.artCrop.zoom * (e.deltaY < 0 ? 1.05 : 1 / 1.05)));
      ed.work.artCrop = { ...ed.work.artCrop, zoom: z };
      changed();
    }, { passive: false });
  }

  // ---------- spremanje ----------

  // Nacrt: polja koja se razlikuju od cards.json, tko i kad. Drugi nacrti se čitaju iznova prije pisanja.
  async function saveDraft() {
    const w = ed.work;
    if (ed.lock?.state === 'other') throw new Error(`${ed.lock.other?.who ?? 'Someone'} is editing this card.`);
    const diff = {};
    for (const k of FIELDS) {
      if (w[k] === undefined) continue;
      if (!sameVal(w[k], ed.base[k])) diff[k] = w[k];
    }
    const fresh = await readDrafts();
    const before = ed.drafts?.cards?.[w.id]?.updated;
    const now = fresh.cards?.[w.id]?.updated;
    if (now && now !== before && !confirm(`${fresh.cards[w.id].who || 'Someone'} saved this card in the meantime. Overwrite?`)) return;
    fresh.cards ??= {};
    if (w.new) diff.new = true;
    if (Object.keys(diff).length) fresh.cards[w.id] = { ...diff, updated: new Date().toISOString(), who: who() || undefined };
    else delete fresh.cards[w.id];
    await fs.writeFile(store().root, DRAFTS_PATH, JSON.stringify(fresh, null, 2) + '\n');
    ed.drafts = fresh;
    ed.dirty = false;
    env.toast(Object.keys(diff).length ? `Draft saved: ${w.name}. It goes into the game with the next Publish.` : 'No changes against the published card.');
    env.render();
  }

  async function discardDraft() {
    if (!confirm(ed.work?.new ? 'Throw away this new card?' : 'Throw away the unpublished changes to this card?')) return;
    const fresh = await readDrafts();
    delete fresh.cards?.[ed.id];
    await fs.writeFile(store().root, DRAFTS_PATH, JSON.stringify(fresh, null, 2) + '\n');
    ed.drafts = fresh;
    if (ed.work?.new) { ed.dirty = false; ed.work = null; env.go(null); return; }
    open(ed.id);
    env.render();
  }

  // Izvorni art ide u data/art/<kod>.<ext> u punoj rezoluciji; izrez se vraća na sredinu.
  async function uploadArt(file) {
    if (!file) return;
    const ext = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' }[file.type];
    if (!ext) throw new Error('Art must be PNG, JPEG or WebP.');
    const path = `art/${ed.work.id}.${ext}`;
    await fs.writeFile(store().root, `data/${path}`, new Uint8Array(await file.arrayBuffer()));
    store().dropImageUrls?.();
    ed.work.art = path;
    ed.work.artCrop = { x: 0.5, y: 0.5, zoom: 1 };
    ed.artFor = null;
    changed();
    env.render();
  }

  // Amblem u pločici heroja: data/art/emblems/<kod>.<ext>.
  async function uploadEmblem(file) {
    if (!file) return;
    const ext = { 'image/png': 'png', 'image/webp': 'webp' }[file.type];
    if (!ext) throw new Error('The emblem must be PNG or WebP (with a clear background).');
    const path = `art/emblems/${ed.work.id}.${ext}`;
    await fs.writeFile(store().root, `data/${path}`, new Uint8Array(await file.arrayBuffer()));
    store().dropImageUrls?.();
    ed.work.emblem = path;
    ed.emblemFor = null;
    changed();
    env.render();
  }

  function downloadPng() {
    if (!ed.canvas) return;
    ed.canvas.toBlob(b => {
      const a = h('a', { href: URL.createObjectURL(b), download: `${ed.work.id} ${ed.work.name}.png` });
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 5000);
    }, 'image/png');
  }

  const guide = createGuideView({ h, store, canWrite, who, render: env.render, guard: env.guard, toast: env.toast, onSaved: g => { ed.guide = g; } });
  const sets = createSetsView({ h, state: env.state, store, canWrite, who, render: env.render, guard: env.guard, toast: env.toast, go: id => go(id), newCard: (set, type) => newCard(set, type) });

  return { render, isDirty: () => ed.dirty, newCard };
}

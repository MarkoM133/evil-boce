// Card editor (zamjena za Card Engine): Edit za sve tipove karata (Action, Equipment, Assist, Hero,
// Evolution, Stage, Core). Forma i živi preview jedno uz drugo; izmjene se spremaju kao nacrti u
// data/editor/drafts.json, a igra ih vidi tek kad ih Objava prebaci u cards.json (Card editor › Publish).
// Art je u data/art/<kod>.<ext> (puna rezolucija), izrez je u karti (artCrop); amblemi u data/art/emblems/.
import { loadTemplate, renderCard, fontsReady, loadImage, parseEffect, templateName, TINTS } from './render.js';
import { firstTag, tagLabel, traitNames, INVALID } from './tags.js';
import { TERRAINS } from './parse.js';
import * as fs from './fsdir.js';

export const DRAFTS_PATH = 'data/editor/drafts.json';
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
const FIELDS = ['name', 'type', 'color', 'cost', 'bonus', 'stats', 'evo', 'hero', 'abilityNames', 'traits', 'text', 'terrain',
  'art', 'artCrop', 'emblem', 'bg', 'template', 'status', 'notes'];
const INSERTS = [
  ['[Range]', '[Range] '], ['Preroll', 'Preroll Phase: '], ['Roll', 'Roll Phase: '], ['Postroll', 'Postroll Phase: '],
  ['Battle', 'Battle Phase: '], ['Once per turn', ' Once Per Turn'], ['[PWR]', '[PWR]'], ['[DMG]', '[DMG]'],
  ['[HP]', '[HP]'], ['[RNG]', '[RNG]'], ['[KB]', '[KB]'],
];

// env: { state, h, toast, guard, render, go(id) }.
export function createEditor(env) {
  const { h } = env;
  const ed = {
    drafts: null, tpl: null, tpls: {}, ready: false, agency: true, loading: false, error: null,
    id: null, work: null, base: null, art: null, artFor: null, emblem: null, emblemFor: null,
    dirty: false, q: '', set: '', type: '', canvas: null, warnBox: null, frame: 0,
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

  const cards = () => env.state.db.cards.filter(c => EDIT_TYPES.includes(c.type) && !c.deleted)
    .sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  const setOf = c => c.id.split('-')[0];

  function open(id) {
    const base = env.state.db.cards.find(c => c.id === id);
    if (!base) return;
    ed.id = id;
    ed.base = base;
    ed.work = structuredClone({ ...base, ...(ed.drafts?.cards?.[id] ?? {}) });
    ed.work.bonus ??= {};
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
    if (want && want !== ed.id) open(want);
    if (!want) { ed.id = null; ed.work = null; }
    return h('div', { class: 'card-editor' }, renderList(), ed.work ? renderForm() : h('p', { class: 'muted ce-empty' }, 'Pick a card on the left.'), ed.work ? renderPreview() : null);
  }

  const shown = () => {
    const q = ed.q.trim().toLowerCase();
    return cards().filter(c => (!ed.set || setOf(c) === ed.set) && (!ed.type || c.type === ed.type) && (!q || `${c.id} ${c.name}`.toLowerCase().includes(q)));
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
      h('ul', { id: 'ce-items' }, shown().map(c => item(c))));
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
    const text = h('textarea', { rows: 5, value: w.text ?? '', oninput: e => set('text', e.target.value) });
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
        field('Text', text), inserts(insert),
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
        field('Text', text), inserts(insert),
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
        field('Text', text), inserts(insert),
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
        h('label', { class: 'ce-who' }, 'I am ', h('select', { onchange: e => { try { localStorage.setItem(WHO_KEY, e.target.value); } catch {} env.render(); } },
          ['', 'Marko', 'Tarik'].map(n => h('option', { value: n, selected: n === who() }, n || '–'))))),
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
        h('button', { class: 'primary', type: 'submit', disabled: !canWrite() }, 'Save draft'),
        ed.drafts?.cards?.[w.id] ? h('button', { type: 'button', class: 'ghost', disabled: !canWrite(), onclick: () => env.guard(discardDraft) }, 'Discard draft') : null,
        h('button', { type: 'button', class: 'ghost', onclick: () => downloadPng() }, 'Download PNG'),
        canWrite() ? null : h('small', { class: 'muted' }, 'Saving needs the shared folder (Chrome or Edge on a computer).')));
  }

  const inserts = insert => h('div', { class: 'ce-inserts' }, INSERTS.map(([label, s]) => h('button', { type: 'button', class: 'ghost', onclick: () => insert(s) }, label)));

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
    hookDrag(ed.canvas);
    queueDraw();
    return h('section', { class: 'ce-preview' }, ed.canvas, ed.warnBox,
      ed.agency ? null : h('p', { class: 'warn small' }, 'Agency FB is not on this computer: a stand-in font is shown. PNGs are made on a computer that has it.'));
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
  }

  // Provjere dok pišeš (uz upozorenja renderera).
  function checks(w) {
    const out = [];
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
    if (/\[(?!Range\]|PWR\]|DMG\]|HP\]|RNG\]|KB\])[^\]]*\]/i.test(w.text ?? '')) out.push('Unknown [icon] in the text: [Range], [PWR], [DMG], [HP], [RNG], [KB].');
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
    const diff = {};
    for (const k of FIELDS) {
      if (w[k] === undefined) continue;
      if (JSON.stringify(w[k]) !== JSON.stringify(ed.base[k])) diff[k] = w[k];
    }
    const fresh = await readDrafts();
    const before = ed.drafts?.cards?.[w.id]?.updated;
    const now = fresh.cards?.[w.id]?.updated;
    if (now && now !== before && !confirm(`${fresh.cards[w.id].who || 'Someone'} saved this card in the meantime. Overwrite?`)) return;
    fresh.cards ??= {};
    if (Object.keys(diff).length) fresh.cards[w.id] = { ...diff, updated: new Date().toISOString(), who: who() || undefined };
    else delete fresh.cards[w.id];
    await fs.writeFile(store().root, DRAFTS_PATH, JSON.stringify(fresh, null, 2) + '\n');
    ed.drafts = fresh;
    ed.dirty = false;
    env.toast(Object.keys(diff).length ? `Draft saved: ${w.name}. It goes into the game with the next Publish.` : 'No changes against the published card.');
    env.render();
  }

  async function discardDraft() {
    if (!confirm('Throw away the unpublished changes to this card?')) return;
    const fresh = await readDrafts();
    delete fresh.cards?.[ed.id];
    await fs.writeFile(store().root, DRAFTS_PATH, JSON.stringify(fresh, null, 2) + '\n');
    ed.drafts = fresh;
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

  return { render, isDirty: () => ed.dirty };
}

import { analyzeExport, buildPublish, applyAppEdits, obsoleteImages, emptyDb, CE_FIELDS } from './importer.js';
import { TYPES, COLOR_NAMES } from './parse.js';
import * as fs from './fsdir.js';

const DB_PATH = 'data/cards.json';
const STEAM_PATH = 'data/steam-urls.json';
// Logo je u Drive folderu, ne u javnom repou (§2 plana).
const LOGO_FILES = ['logo.png', 'logo.jpg', 'logo.jpeg', 'logo.webp'];

const state = {
  root: null,
  db: null,
  logo: null,
  analysis: null,
  tab: 'import',
  filter: { q: '', type: '', color: '', deleted: false },
  selected: null,
  busy: false,
};

const urls = new Map();

// ---------- DOM pomoćnici ----------

function h(tag, props = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k in el && k !== 'list') el[k] = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) if (kid !== null && kid !== undefined && kid !== false) el.append(kid instanceof Node ? kid : String(kid));
  return el;
}

const $ = sel => document.querySelector(sel);

function toast(msg, kind = 'ok') {
  const t = h('div', { class: `toast ${kind}`, role: 'status' }, msg);
  $('#toasts').append(t);
  setTimeout(() => t.remove(), kind === 'error' ? 9000 : 4500);
}

async function guard(fn) {
  if (state.busy) return;
  state.busy = true;
  document.body.classList.add('busy');
  try {
    await fn();
  } catch (e) {
    console.error(e);
    toast(e.message || String(e), 'error');
  } finally {
    state.busy = false;
    document.body.classList.remove('busy');
    render();
  }
}

function blobUrl(key, blob) {
  if (!urls.has(key)) urls.set(key, URL.createObjectURL(blob));
  return urls.get(key);
}

function dropUrls() {
  for (const u of urls.values()) URL.revokeObjectURL(u);
  urls.clear();
}

// ---------- podaci ----------

async function readDb() {
  const t = await fs.readText(state.root, DB_PATH);
  return t ? JSON.parse(t) : emptyDb();
}

async function loadDb() {
  state.db = await readDb();
  dropUrls();
}

// Drive sinkronizira između dva računala: prije pisanja provjeri da baza nije promijenjena u međuvremenu.
async function assertFresh() {
  const disk = await readDb();
  if (disk.version !== state.db.version) {
    state.db = disk;
    state.analysis = null;
    throw new Error(`cards.json je u međuvremenu promijenjen (verzija ${disk.version}). Ponovi Uvezi.`);
  }
}

async function writeDb(db) {
  await fs.writeFile(state.root, DB_PATH, JSON.stringify(db, null, 2) + '\n');
  state.db = db;
}

async function cardImageUrl(card) {
  if (!card.image) return null;
  const key = `db:${card.image}`;
  if (urls.has(key)) return urls.get(key);
  const f = await fs.getFile(state.root, `data/${card.image}`);
  return f ? blobUrl(key, f) : null;
}

// ---------- akcije ----------

async function connect(handle) {
  state.root = handle;
  state.analysis = null;
  state.selected = null;
  await loadDb();
  await loadLogo();
}

async function loadLogo() {
  if (state.logo) URL.revokeObjectURL(state.logo);
  state.logo = null;
  for (const name of LOGO_FILES) {
    const f = await fs.getFile(state.root, name);
    if (f) {
      state.logo = URL.createObjectURL(f);
      return;
    }
  }
}

async function pickFolder() {
  if (!window.showDirectoryPicker) throw new Error('Ovaj preglednik nema File System Access API. Otvori stranicu u Chromeu ili Edgeu.');
  const handle = await fs.pickRoot();
  await connect(handle);
  if (!(await fs.getDir(handle, 'export')) && !(await fs.getDir(handle, 'data'))) {
    toast(`U folderu "${handle.name}" nema ni export/ ni data/. Je li to folder "Evil Boce"?`, 'warn');
  }
}

async function resume(handle) {
  if ((await fs.permission(handle, true)) !== 'granted') throw new Error('Pristup folderu nije dopušten.');
  await connect(handle);
}

async function runImport() {
  const exportDir = await fs.getDir(state.root, 'export');
  if (!exportDir) throw new Error('Nema foldera export/ u odabranom folderu.');
  await loadDb();
  const files = await fs.walkFiles(exportDir, 'export');
  const xmlFiles = [];
  const pngFiles = [];
  for (const { path, file } of files) {
    if (/\.xml$/i.test(path)) xmlFiles.push({ path, text: await file.text(), lastModified: file.lastModified });
    else if (/\.png$/i.test(path)) pngFiles.push({ path, file, lastModified: file.lastModified, getBytes: async () => new Uint8Array(await file.arrayBuffer()) });
  }
  if (!xmlFiles.length) throw new Error('U export/ nema nijednog XML-a.');
  state.analysis = await analyzeExport({ xmlFiles, pngFiles, db: state.db });
  state.analysis.fileCount = { xml: xmlFiles.length, png: pngFiles.length };
}

async function publish() {
  const a = state.analysis;
  if (!a || a.errors.length) return;
  await assertFresh();
  const { db, writes, changed } = buildPublish(state.db, a);
  if (!changed) {
    toast('Nema promjena za objavu.');
    return;
  }
  for (const w of writes) await fs.writeFile(state.root, w.path, await w.png.getBytes());
  await writeDb(db);
  const steamText = await fs.readText(state.root, STEAM_PATH);
  const steam = steamText ? JSON.parse(steamText) : {};
  const old = obsoleteImages(db, await fs.listFileNames(state.root, 'data/images'), steam);
  for (const f of old) await fs.removeFile(state.root, `data/images/${f}`);
  state.analysis = null;
  dropUrls();
  toast(`Objavljeno: verzija ${db.version}, ${changed} karata${old.length ? `, obrisano ${old.length} starih slika` : ''}.`);
}

async function saveEdits(id, edits) {
  await assertFresh();
  const { db, changed } = applyAppEdits(state.db, { [id]: edits });
  if (!changed) {
    toast('Nema promjena.');
    return;
  }
  await writeDb(db);
  toast(`Spremljeno: verzija ${db.version}.`);
}

// ---------- prikaz ----------

function render() {
  const app = $('#app');
  if (state.root) app.replaceChildren(renderHeader(), renderMain());
  else app.replaceChildren(renderWelcome());
}

function wordmark(size) {
  return h('span', { class: `wordmark ${size}`, role: 'img', 'aria-label': 'Evil Boće' },
    h('span', { class: 'w-evil' }, 'Evil'), h('span', { class: 'w-boce' }, 'Boće'));
}

function renderHeader() {
  const n = state.db.cards.length;
  return h('header', { class: 'top' },
    h('div', { class: 'brand' },
      state.logo ? h('img', { class: 'logo', src: state.logo, alt: 'Evil Boće' }) : wordmark('small'),
      h('span', { class: 'brand-sub' }, 'Baza karata')),
    h('div', { class: 'folder' },
      h('span', { class: 'folder-name', title: 'Odabrani Drive folder' }, state.root.name),
      h('span', { class: 'folder-db' }, `Verzija ${state.db.version}`, h('span', { class: 'sep', 'aria-hidden': 'true' }), `${n} ${n === 1 ? 'karta' : 'karata'}`),
      h('button', { class: 'ghost', onclick: () => guard(pickFolder) }, 'Promijeni folder')));
}

function renderWelcome() {
  const actions = h('div', { class: 'welcome-actions' },
    h('button', { class: 'primary', onclick: () => guard(pickFolder) }, 'Odaberi folder'));
  const box = h('section', { class: 'welcome' },
    h('div', { class: 'emblem', 'aria-hidden': 'true' }, h('span', { class: 'ring' }), wordmark('big')),
    h('div', { class: 'welcome-text' },
      h('h1', {}, 'Baza karata'),
      h('p', {}, 'Odaberi zajednički Drive folder "Evil Boce". U njemu su export/ s exportima iz Card Enginea i data/ s bazom karata. Preglednik ga zapamti, pa se bira samo jednom.'),
      actions,
      !window.showDirectoryPicker ? h('p', { class: 'error-text' }, 'Ovaj preglednik ne može otvoriti folder. Otvori stranicu u Chromeu ili Edgeu.') : null));
  fs.loadRoot().then(handle => {
    if (!handle || state.root) return;
    actions.append(h('button', { class: 'ghost', onclick: () => guard(() => resume(handle)) }, `Nastavi s "${handle.name}"`));
  });
  return box;
}

function renderMain() {
  const tabs = [
    ['import', 'Uvoz'],
    ['browse', 'Pregled'],
  ];
  return h('main', {},
    h('nav', { class: 'tabs', role: 'tablist' },
      tabs.map(([key, label]) => h('button', { role: 'tab', 'aria-selected': String(state.tab === key), class: state.tab === key ? 'active' : '', onclick: () => { state.tab = key; render(); } }, label)),
      h('span', { class: 'soon' }, 'Deck builder i Katalog dolaze u kasnijim fazama')),
    state.tab === 'import' ? renderImport() : renderBrowse());
}

// ----- Uvoz -----

const STATUS_LABEL = { new: 'Nova', changed: 'Promijenjena', same: 'Bez promjene' };

function renderImport() {
  const a = state.analysis;
  const wrap = h('section', { class: 'panel' },
    h('div', { class: 'toolbar' },
      h('button', { class: 'primary', onclick: () => guard(runImport) }, a ? 'Ponovno učitaj export/' : 'Uvezi iz export/'),
      a ? h('button', { class: 'publish', disabled: a.errors.length > 0 || !a.entries.some(e => e.status !== 'same'), onclick: () => guard(publish) }, 'Objavi') : null,
      a?.errors.length ? h('span', { class: 'error-text' }, 'Objava je blokirana dok ima grešaka.') : null));
  if (!a) {
    wrap.append(h('p', { class: 'muted' }, 'Čita sve XML-ove i PNG-ove iz export/ (i podfoldera), uspoređuje ih s data/cards.json i pokaže što će se promijeniti. Ništa se ne zapisuje dok ne klikneš Objavi.'));
    return wrap;
  }
  const count = s => a.entries.filter(e => e.status === s).length;
  wrap.append(h('div', { class: 'stats' },
    stat('Nove', count('new'), 'new'),
    stat('Promijenjene', count('changed'), 'changed'),
    stat('Bez promjene', count('same'), 'same'),
    stat('Greške', a.errors.length, a.errors.length ? 'error' : ''),
    stat('Upozorenja', a.warnings.length, a.warnings.length ? 'warn' : ''),
    h('p', { class: 'muted small' }, `${a.fileCount.xml} XML, ${a.fileCount.png} PNG u export/`)));
  wrap.append(...[messages('Greške', a.errors, 'error'), messages('Upozorenja', a.warnings, 'warn'), messages('Info', a.infos, 'info', true)].filter(Boolean));
  const changes = a.entries.filter(e => e.status !== 'same');
  if (changes.length) wrap.append(h('h3', {}, 'Promjene'), h('div', { class: 'changes' }, changes.map(renderEntry)));
  const same = a.entries.filter(e => e.status === 'same');
  if (same.length) wrap.append(h('details', { class: 'same' }, h('summary', {}, `Bez promjene (${same.length})`), h('p', { class: 'muted' }, same.map(e => `${e.id} ${e.card.name}`).join(' · '))));
  return wrap;
}

function stat(label, n, kind) {
  return h('div', { class: `stat ${n ? kind : 'zero'}` }, h('strong', {}, n), h('span', {}, label));
}

function messages(title, list, kind, collapsed = false) {
  if (!list.length) return null;
  const items = h('ul', { class: `msgs ${kind}` }, list.map(m => h('li', {}, m.id ? h('code', {}, m.id) : null, ' ', m.msg)));
  return collapsed ? h('details', { class: 'msgbox' }, h('summary', {}, `${title} (${list.length})`), items) : h('div', { class: 'msgbox' }, h('h3', {}, title), items);
}

function fmt(v) {
  if (v === undefined) return '—';
  if (v === null) return 'null';
  if (Array.isArray(v)) return v.join(' / ');
  if (typeof v === 'object') return Object.entries(v).map(([k, x]) => `${k} ${x}`).join(', ') || '{}';
  return String(v);
}

function renderEntry(e) {
  const imgs = h('div', { class: 'thumbs' });
  if (e.old && e.imageChanged) {
    const oldImg = h('img', { alt: 'stara slika', loading: 'lazy' });
    cardImageUrl(e.old).then(u => { if (u) oldImg.src = u; else oldImg.replaceWith(h('div', { class: 'noimg' }, 'stara slika nije u data/images')); });
    imgs.append(h('figure', {}, oldImg, h('figcaption', {}, 'prije')));
  }
  if (e.png) imgs.append(h('figure', {}, h('img', { alt: e.card.name, src: blobUrl(`png:${e.png.path}`, e.png.file), loading: 'lazy' }), h('figcaption', {}, e.old ? (e.imageChanged ? 'nova slika' : 'slika ista') : 'slika')));
  const rows = e.old
    ? e.diffs.map(k => h('tr', {}, h('th', {}, k), h('td', { class: 'was' }, fmt(e.old[k])), h('td', { class: 'now' }, fmt(e.card[k]))))
    : CE_FIELDS.filter(k => e.card[k] !== undefined).map(k => h('tr', {}, h('th', {}, k), h('td', { colspan: 2 }, fmt(e.card[k]))));
  return h('article', { class: `entry ${e.status}` },
    h('header', {},
      h('span', { class: `badge ${e.status}` }, STATUS_LABEL[e.status]),
      h('code', {}, e.id), h('strong', {}, e.card.name),
      e.card.color ? h('span', { class: `chip c-${e.card.color}` }, e.card.color) : null,
      h('span', { class: 'muted small' }, e.file)),
    h('div', { class: 'entry-body' }, imgs,
      h('div', {},
        rows.length ? h('table', { class: 'diff' }, rows) : null,
        e.old && !e.diffs.length ? h('p', { class: 'muted' }, e.imageChanged ? 'Promijenjena je samo slika.' : '') : null)));
}

// ----- Pregled -----

function filtered() {
  const { q, type, color, deleted } = state.filter;
  const needle = q.trim().toLowerCase();
  return state.db.cards.filter(c =>
    (deleted || !c.deleted) &&
    (!type || c.type === type) &&
    (!color || c.color === color) &&
    (!needle || [c.id, c.name, c.text, ...(c.traits ?? [])].join(' ').toLowerCase().includes(needle)));
}

function renderBrowse() {
  const f = state.filter;
  const set = (k, v) => { f[k] = v; renderGrid(); };
  const panel = h('section', { class: 'panel' },
    h('div', { class: 'filters' },
      h('input', { type: 'search', placeholder: 'Traži ime, tekst, trait, kod…', value: f.q, oninput: e => set('q', e.target.value) }),
      h('select', { onchange: e => set('type', e.target.value) }, h('option', { value: '' }, 'Svi tipovi'), TYPES.map(t => h('option', { value: t, selected: f.type === t }, t))),
      h('select', { onchange: e => set('color', e.target.value) }, h('option', { value: '' }, 'Sve boje'), COLOR_NAMES.map(c => h('option', { value: c, selected: f.color === c }, c))),
      h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: f.deleted, onchange: e => set('deleted', e.target.checked) }), 'prikaži maknute')),
    h('div', { id: 'grid', class: 'grid' }),
    h('div', { id: 'detail' }));
  queueMicrotask(() => { renderGrid(); renderDetail(); });
  return panel;
}

function renderGrid() {
  const grid = $('#grid');
  if (!grid) return;
  const cards = filtered();
  if (!state.db.cards.length) {
    grid.replaceChildren(h('p', { class: 'muted' }, 'Baza je prazna. Napravi Uvoz i Objavi.'));
    return;
  }
  grid.replaceChildren(...(cards.length ? cards.map(tile) : [h('p', { class: 'muted' }, 'Nijedna karta ne odgovara filtru.')]));
}

function tile(c) {
  const img = h('img', { alt: '', loading: 'lazy' });
  cardImageUrl(c).then(u => { if (u) img.src = u; });
  return h('button', { class: `tile${c.deleted ? ' deleted' : ''}${state.selected === c.id ? ' selected' : ''}`, onclick: () => { state.selected = c.id; renderGrid(); renderDetail(); } },
    h('div', { class: 'art' }, img),
    h('div', { class: 'meta' },
      h('span', { class: `dot c-${c.color ?? 'none'}` }),
      h('span', { class: 'name' }, c.name),
      h('span', { class: 'sub' }, h('span', {}, c.id), h('span', {}, c.type), c.cost !== undefined ? h('span', { class: 'cost', title: 'Cost' }, c.cost) : null)));
}

function renderDetail() {
  const box = $('#detail');
  if (!box) return;
  const c = state.db.cards.find(x => x.id === state.selected);
  if (!c) { box.replaceChildren(); box.className = ''; return; }
  box.className = 'detail';
  const img = h('img', { alt: c.name });
  cardImageUrl(c).then(u => { if (u) img.src = u; });
  const edits = {};
  const field = (label, input) => h('label', { class: 'field' }, h('span', {}, label), input);
  const editor = h('form', { class: 'editor', onsubmit: e => { e.preventDefault(); guard(() => saveEdits(c.id, edits)); } },
    h('h3', {}, 'App polja'),
    c.type === 'Character' ? [
      field('Težina bakugana (wt)', h('input', { type: 'number', min: 1, step: 1, value: c.wt ?? '', oninput: e => { if (e.target.value === '') delete edits.wt; else edits.wt = Number(e.target.value); } })),
      field('Bakugan u TTS-u', h('input', { type: 'text', value: c.bakugan ?? '', oninput: e => { edits.bakugan = e.target.value.trim(); } })),
    ] : null,
    h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: !!c.deleted, onchange: e => { edits.deleted = e.target.checked; } }), 'Maknuta (deleted) – builder je više ne nudi'),
    h('button', { class: 'primary', type: 'submit' }, 'Spremi'));
  const rows = ['type', 'color', 'cost', 'evo', 'hero', 'stats', 'bonus', 'values', 'traits', 'text', 'rev', 'imageHash']
    .filter(k => c[k] !== undefined)
    .map(k => h('tr', {}, h('th', {}, k), h('td', {}, fmt(c[k]))));
  box.replaceChildren(
    h('div', { class: 'detail-head' }, h('div', {}, h('code', {}, c.id), h('h2', {}, c.name)), h('button', { class: 'ghost', onclick: () => { state.selected = null; renderGrid(); renderDetail(); } }, 'Zatvori')),
    h('div', { class: 'detail-body' }, h('div', { class: 'big' }, img), h('div', {}, h('table', { class: 'fields' }, rows), editor)));
}

// ---------- start ----------

render();

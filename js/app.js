import { analyzeExport, buildPublish, applyAppEdits, obsoleteImages, thumbPlan, thumbName, THUMB_WIDTH, CE_FIELDS } from './importer.js';
import { TYPES, COLOR_NAMES, DECK_TYPES } from './parse.js';
import { checkDeck, deckPool, randomFill, encodeDeck, decodeDeck, slugify, emptyDeck, heroCards, LIMITS, DECK_SIZE } from './deck.js';
import { probeServer, serverStore, folderStore, ConflictError } from './store.js';
import * as fs from './fsdir.js';

const DB_PATH = 'data/cards.json';
const STEAM_PATH = 'data/steam-urls.json';

const state = {
  store: null,
  db: null,
  logo: null,
  analysis: null,
  tab: 'import',
  filter: { q: '', type: '', color: '', deleted: false },
  selected: null,
  busy: false,
  decks: [],
  deck: null,
  deckView: 'pool',
  pool: { q: '', type: '', color: '' },
  focus: { color: '', value: 0.6 },
};

const pngUrls = new Map();

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

// replaceChildren bez praznih mjesta (null bi se ispisao kao tekst "null").
function fill(el, ...kids) {
  el.replaceChildren(...kids.flat().filter(k => k !== null && k !== undefined && k !== false));
}

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

// Sličica ako postoji, inače puna slika. full: true za detalj karte.
function cardImg(card, { full = false, ...props } = {}) {
  const img = h('img', { alt: props.alt ?? '', loading: 'lazy', ...props });
  if (card) imageFor(card, !full).then(u => { if (u) img.src = u; });
  return img;
}

const loaded = new Map();

function loads(url) {
  if (!loaded.has(url)) {
    loaded.set(url, new Promise(resolve => {
      const img = new Image();
      img.onload = () => resolve(true);
      img.onerror = () => resolve(false);
      img.src = url;
    }));
  }
  return loaded.get(url);
}

async function imageFor(card, thumb) {
  if (thumb) {
    const t = await state.store.imageUrl(card, { thumb: true });
    if (t && (await loads(t))) return t;
  }
  return state.store.imageUrl(card);
}

async function makeThumb(blob) {
  const bmp = await createImageBitmap(blob);
  const height = Math.round((bmp.height / bmp.width) * THUMB_WIDTH);
  const canvas = new OffscreenCanvas(THUMB_WIDTH, height);
  const ctx = canvas.getContext('2d');
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(bmp, 0, 0, THUMB_WIDTH, height);
  bmp.close();
  return canvas.convertToBlob({ type: 'image/jpeg', quality: 0.85 });
}

const cardById = id => state.db.cards.find(c => c.id === id);

// ---------- podaci ----------

async function useStore(store) {
  if (state.logo?.startsWith('blob:')) URL.revokeObjectURL(state.logo);
  state.store?.dropImageUrls?.();
  state.store = store;
  state.analysis = null;
  state.selected = null;
  state.db = await store.readDb();
  state.logo = await store.logoUrl();
  state.decks = await store.listDecks();
  state.deck = null;
}

async function reloadDb() {
  state.db = await state.store.readDb();
  state.store.dropImageUrls?.();
}

const root = () => state.store.root;

// Drive sinkronizira između dva računala: prije pisanja provjeri da baza nije promijenjena u međuvremenu.
async function assertFresh() {
  const disk = await state.store.readDb();
  if (disk.version !== state.db.version) {
    state.db = disk;
    state.analysis = null;
    throw new Error(`cards.json je u međuvremenu promijenjen (verzija ${disk.version}). Ponovi Uvezi.`);
  }
}

async function writeDb(db) {
  await fs.writeFile(root(), DB_PATH, JSON.stringify(db, null, 2) + '\n');
  state.db = db;
}

// ---------- akcije: folder i uvoz ----------

async function pickFolder() {
  if (!window.showDirectoryPicker) throw new Error('Ovaj preglednik ne može otvoriti folder. Otvori stranicu u Chromeu ili Edgeu na računalu.');
  const handle = await fs.pickRoot();
  await useStore(folderStore(handle));
  state.tab = 'import';
  if (!(await fs.getDir(handle, 'export')) && !(await fs.getDir(handle, 'data'))) {
    toast(`U folderu "${handle.name}" nema ni export/ ni data/. Je li to folder "Evil Boce"?`, 'warn');
  }
}

async function resume(handle) {
  if ((await fs.permission(handle, true)) !== 'granted') throw new Error('Pristup folderu nije dopušten.');
  await useStore(folderStore(handle));
}

async function runImport() {
  const exportDir = await fs.getDir(root(), 'export');
  if (!exportDir) throw new Error('Nema foldera export/ u odabranom folderu.');
  await reloadDb();
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
  state.analysis.missingThumbs = thumbPlan(state.db, await fs.listFileNames(root(), 'data/thumbs')).missing.length;
}

async function publish() {
  const a = state.analysis;
  if (!a || a.errors.length) return;
  await assertFresh();
  const { db, writes, changed } = buildPublish(state.db, a);
  let old = [];
  if (changed) {
    for (const w of writes) await fs.writeFile(root(), w.path, await w.png.getBytes());
    await writeDb(db);
    const steamText = await fs.readText(root(), STEAM_PATH);
    const steam = steamText ? JSON.parse(steamText) : {};
    old = obsoleteImages(db, await fs.listFileNames(root(), 'data/images'), steam);
    for (const f of old) await fs.removeFile(root(), `data/images/${f}`);
  }
  const thumbs = await updateThumbs(db);
  state.analysis = null;
  state.store.dropImageUrls();
  if (!changed && !thumbs) {
    toast('Nema promjena za objavu.');
    return;
  }
  const parts = [];
  if (changed) parts.push(`verzija ${db.version}, ${changed} karata`);
  if (thumbs) parts.push(`${thumbs} sličica`);
  if (old.length) parts.push(`obrisano ${old.length} starih slika`);
  toast(`Objavljeno: ${parts.join(', ')}.`);
}

// Sličice za sve karte kojima nedostaju; stare verzije se brišu.
async function updateThumbs(db) {
  const plan = thumbPlan(db, await fs.listFileNames(root(), 'data/thumbs'));
  for (const c of plan.missing) {
    const f = await fs.getFile(root(), `data/${c.image}`);
    if (f) await fs.writeFile(root(), `data/thumbs/${thumbName(c)}`, await makeThumb(f));
  }
  for (const f of plan.extra) await fs.removeFile(root(), `data/thumbs/${f}`);
  return plan.missing.length;
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

// ---------- prikaz: okvir ----------

function render() {
  const app = $('#app');
  if (state.store) {
    app.replaceChildren(renderHeader(), renderMain());
    updateStrip();
  } else app.replaceChildren(renderWelcome());
}

// Traka s herojima iza zaglavlja: svi heroji iz baze, kose kriške s crtežom s karte.
function heroStrip() {
  const heroes = heroCards(state.db).sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  if (!heroes.length) return null;
  return h('div', { class: 'hero-strip', id: 'hero-strip' }, heroes.map(c => {
    const art = h('span', { class: 'slice-art' });
    imageFor(c, true).then(u => { if (u) art.style.backgroundImage = `url("${u}")`; });
    return h('button', {
      class: `slice c-edge-${c.color}`,
      'data-id': c.id,
      title: c.name,
      'aria-label': `${c.name}: otvori u Pregledu`,
      onclick: () => { state.tab = 'browse'; state.selected = c.id; render(); },
    }, art, h('span', { class: 'slice-name' }, c.name));
  }));
}

// U deck builderu svijetle samo heroji iz decka.
function updateStrip() {
  const strip = $('#hero-strip');
  if (!strip) return;
  const picked = new Set(state.tab === 'decks' && state.deck ? state.deck.heroes : []);
  strip.classList.toggle('has-picked', picked.size > 0);
  for (const s of strip.children) s.classList.toggle('picked', picked.has(s.dataset.id));
}

function wordmark(size) {
  return h('span', { class: `wordmark ${size}`, role: 'img', 'aria-label': 'Evil Boće' },
    h('span', { class: 'w-evil' }, 'Evil'), h('span', { class: 'w-boce' }, 'Boće'));
}

function renderHeader() {
  const n = state.db.cards.length;
  const server = state.store.kind === 'server';
  return h('header', { class: 'top' },
    heroStrip(),
    h('div', { class: 'brand' },
      state.logo ? h('img', { class: 'logo', src: state.logo, alt: 'Evil Boće' }) : wordmark('small'),
      h('span', { class: 'brand-sub' }, 'Baza karata')),
    h('div', { class: 'folder' },
      h('span', { class: 'folder-name', title: server ? 'Podaci s računala preko servera' : 'Odabrani Drive folder' }, server ? `${state.store.name} preko servera` : state.store.name),
      h('span', { class: 'folder-db' }, `Verzija ${state.db.version}`, h('span', { class: 'sep', 'aria-hidden': 'true' }), `${n} ${n === 1 ? 'karta' : 'karata'}`),
      !server || window.showDirectoryPicker ? h('button', { class: 'ghost', onclick: () => guard(pickFolder) }, server ? 'Odaberi folder' : 'Promijeni folder') : null));
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
    if (!handle || state.store) return;
    actions.append(h('button', { class: 'ghost', onclick: () => guard(() => resume(handle)) }, `Nastavi s "${handle.name}"`));
  });
  return box;
}

function renderMain() {
  const tabs = [
    ['import', 'Uvoz'],
    ['browse', 'Pregled'],
    ['decks', 'Deckovi'],
  ];
  const view = { import: renderImport, browse: renderBrowse, decks: renderDecks }[state.tab]();
  return h('main', {},
    h('nav', { class: 'tabs', role: 'tablist' },
      tabs.map(([key, label]) => h('button', { role: 'tab', 'aria-selected': String(state.tab === key), class: state.tab === key ? 'active' : '', onclick: () => { state.tab = key; render(); } }, label)),
      h('span', { class: 'soon' }, 'Katalog i TTS dolaze u kasnijim fazama')),
    view);
}

// ---------- Uvoz ----------

const STATUS_LABEL = { new: 'Nova', changed: 'Promijenjena', same: 'Bez promjene' };

function renderImport() {
  if (!state.store.canImport) {
    return h('section', { class: 'panel' },
      h('p', { class: 'muted' }, 'Uvoz i Objava rade samo s odabranim Drive folderom, u Chromeu ili Edgeu na računalu. Ovdje su karte i deckovi s računala preko servera.'),
      window.showDirectoryPicker ? h('div', { class: 'toolbar' }, h('button', { class: 'primary', onclick: () => guard(pickFolder) }, 'Odaberi folder')) : null);
  }
  const a = state.analysis;
  const wrap = h('section', { class: 'panel' },
    h('div', { class: 'toolbar' },
      h('button', { class: 'primary', onclick: () => guard(runImport) }, a ? 'Ponovno učitaj export/' : 'Uvezi iz export/'),
      a ? h('button', { class: 'publish', disabled: a.errors.length > 0 || (!a.entries.some(e => e.status !== 'same') && !a.missingThumbs), onclick: () => guard(publish) }, 'Objavi') : null,
      a?.errors.length ? h('span', { class: 'error-text' }, 'Objava je blokirana dok ima grešaka.') : null,
      a?.missingThumbs ? h('span', { class: 'muted' }, `Nedostaje ${a.missingThumbs} malih sličica (za brže učitavanje); Objavi ih napravi.`) : null));
  if (!a) {
    wrap.append(h('p', { class: 'muted' }, 'Čita sve XML-ove i PNG-ove iz export/ (i podfoldera), uspoređuje ih s data/cards.json i pokaže što će se promijeniti. Ništa se ne zapisuje dok ne klikneš Objavi.'));
    return wrap;
  }
  const count = s => a.entries.filter(e => e.status === s).length;
  wrap.append(h('div', { class: 'stats' },
    stat('Nove', count('new'), 'new'),
    stat('Promijenjene', count('changed'), 'changed'),
    stat('Bez promjene', count('same'), 'same'),
    stat('Greške', a.errors.length, 'error'),
    stat('Upozorenja', a.warnings.length, 'warn'),
    h('p', { class: 'muted small' }, `${a.fileCount.xml} XML, ${a.fileCount.png} PNG u export/`)));
  wrap.append(...[messages('Greške', a.errors, 'error'), messages('Upozorenja', a.warnings, 'warn'), messages('Info', a.infos, 'info', true)].filter(Boolean));
  const changes = a.entries.filter(e => e.status !== 'same');
  if (changes.length) wrap.append(h('h3', {}, 'Promjene'), h('div', { class: 'changes' }, changes.map(renderEntry)));
  const same = a.entries.filter(e => e.status === 'same');
  if (same.length) wrap.append(h('details', { class: 'same' }, h('summary', {}, `Bez promjene (${same.length})`), h('p', { class: 'muted' }, same.map(e => `${e.id} ${e.card.name}`).join(', '))));
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
    state.store.imageUrl(e.old).then(u => { if (u) oldImg.src = u; else oldImg.replaceWith(h('div', { class: 'noimg' }, 'stara slika nije u data/images')); });
    imgs.append(h('figure', {}, oldImg, h('figcaption', {}, 'prije')));
  }
  if (e.png) {
    if (!pngUrls.has(e.png.path)) pngUrls.set(e.png.path, URL.createObjectURL(e.png.file));
    imgs.append(h('figure', {}, h('img', { alt: e.card.name, src: pngUrls.get(e.png.path), loading: 'lazy' }), h('figcaption', {}, e.old ? (e.imageChanged ? 'nova slika' : 'slika ista') : 'slika')));
  }
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

// ---------- Pregled ----------

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
  return h('button', { class: `tile${c.deleted ? ' deleted' : ''}${state.selected === c.id ? ' selected' : ''}`, onclick: () => { state.selected = c.id; renderGrid(); renderDetail(); } },
    h('div', { class: 'art' }, cardImg(c)),
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
  const edits = {};
  const field = (label, input) => h('label', { class: 'field' }, h('span', {}, label), input);
  const editor = state.store.canImport
    ? h('form', { class: 'editor', onsubmit: e => { e.preventDefault(); guard(() => saveEdits(c.id, edits)); } },
        h('h3', {}, 'App polja'),
        c.type === 'Character' ? [
          field('Težina bakugana (wt)', h('input', { type: 'number', min: 1, step: 1, value: c.wt ?? '', oninput: e => { if (e.target.value === '') delete edits.wt; else edits.wt = Number(e.target.value); } })),
          field('Bakugan u TTS-u', h('input', { type: 'text', value: c.bakugan ?? '', oninput: e => { edits.bakugan = e.target.value.trim(); } })),
        ] : null,
        h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: !!c.deleted, onchange: e => { edits.deleted = e.target.checked; } }), 'Maknuta (deleted) – builder je više ne nudi'),
        h('button', { class: 'primary', type: 'submit' }, 'Spremi'))
    : null;
  const rows = ['type', 'color', 'cost', 'evo', 'hero', 'stats', 'wt', 'bakugan', 'bonus', 'values', 'traits', 'text', 'rev', 'imageHash']
    .filter(k => c[k] !== undefined)
    .map(k => h('tr', {}, h('th', {}, k), h('td', {}, fmt(c[k]))));
  box.replaceChildren(
    h('div', { class: 'detail-head' }, h('div', {}, h('code', {}, c.id), h('h2', {}, c.name)), h('button', { class: 'ghost', onclick: () => { state.selected = null; renderGrid(); renderDetail(); } }, 'Zatvori')),
    h('div', { class: 'detail-body' }, h('div', { class: 'big' }, cardImg(c, { alt: c.name, full: true })), h('div', {}, h('table', { class: 'fields' }, rows), editor)));
}

// ---------- Deckovi ----------

function newDeck() {
  return { ...emptyDeck(''), slug: null, rev: 0, dirty: false };
}

function confirmDiscard() {
  return !state.deck?.dirty || window.confirm('Deck ima nespremljene promjene. Odbaciti ih?');
}

async function openDeck(slug) {
  const d = await state.store.readDeck(slug);
  state.deck = { slug: d.slug, name: d.name, heroes: d.heroes ?? [], cards: { ...d.cards }, rev: d.rev ?? 0, catalogVersion: d.catalogVersion, dirty: false };
  state.deckView = 'deck';
}

async function saveDeck() {
  const d = state.deck;
  const name = d.name.trim();
  if (!name) throw new Error('Upiši ime decka.');
  const slug = slugify(name);
  if (!slug) throw new Error('Ime decka mora imati barem jedno slovo ili broj.');
  let base = d.slug === slug ? d.rev : 0;
  if (d.slug !== slug) {
    const other = state.decks.find(x => x.slug === slug);
    if (other) {
      if (!window.confirm(`Deck "${other.name}" već postoji. Presnimiti ga?`)) return;
      base = other.rev;
    }
  }
  let saved;
  try {
    saved = await state.store.saveDeck(slug, { name, heroes: d.heroes, cards: d.cards, catalogVersion: state.db.version }, base);
  } catch (e) {
    if (e instanceof ConflictError) throw new Error('Deck je u međuvremenu spremljen na drugom uređaju. Otvori ga ponovno ili spremi pod drugim imenom.');
    throw e;
  }
  if (d.slug && d.slug !== slug) await state.store.deleteDeck(d.slug, d.rev).catch(() => {});
  state.deck = { ...d, slug, name, rev: saved.rev, dirty: false };
  state.decks = await state.store.listDecks();
  toast(`Spremljeno: ${name}`);
}

async function deleteDeck() {
  const d = state.deck;
  if (!d.slug || !window.confirm(`Obrisati deck "${d.name}"?`)) return;
  try {
    await state.store.deleteDeck(d.slug, d.rev);
  } catch (e) {
    if (e instanceof ConflictError) throw new Error('Deck je u međuvremenu promijenjen na drugom uređaju. Otvori ga ponovno prije brisanja.');
    throw e;
  }
  state.decks = await state.store.listDecks();
  state.deck = null;
  toast(`Obrisano: ${d.name}`);
}

function changeDeck(fn) {
  fn(state.deck);
  state.deck.dirty = true;
  refreshDeck();
}

function addCard(id, delta) {
  const c = cardById(id);
  changeDeck(d => {
    const n = Math.max(0, Math.min(LIMITS[c.type], (d.cards[id] ?? 0) + delta));
    if (n) d.cards[id] = n;
    else delete d.cards[id];
  });
}

function renderDecks() {
  return h('section', { class: 'decks' },
    h('aside', { class: 'deck-list' },
      h('div', { class: 'deck-list-head' },
        h('h2', {}, 'Moji deckovi'),
        h('button', { class: 'primary', onclick: () => { if (confirmDiscard()) { state.deck = newDeck(); state.deckView = 'pool'; render(); } } }, 'Novi deck')),
      state.decks.length
        ? h('ul', {}, state.decks.map(x => h('li', {},
            h('button', {
              class: `deck-item${state.deck?.slug === x.slug ? ' active' : ''}`,
              onclick: () => { if (confirmDiscard()) guard(() => openDeck(x.slug)); },
            },
              h('span', { class: 'deck-item-name' }, x.name),
              h('span', { class: 'deck-item-sub' }, x.broken ? 'neispravan file' : `${x.heroes.map(id => cardById(id)?.name ?? id).join(', ') || 'bez heroja'}`),
              h('span', { class: 'deck-item-count' }, x.broken ? '' : `${x.count}/${DECK_SIZE}`)))))
        : h('p', { class: 'muted' }, 'Još nema spremljenih deckova.'),
      h('details', { class: 'code-import' },
        h('summary', {}, 'Učitaj deck kod'),
        h('form', { onsubmit: e => { e.preventDefault(); importCode(e.target.elements.code.value); } },
          h('input', { name: 'code', placeholder: 'EB1|v1|…', autocomplete: 'off', spellcheck: false }),
          h('button', { type: 'submit' }, 'Učitaj')))),
    state.deck ? renderDeckEditor() : h('div', { class: 'deck-empty' },
      h('h2', {}, 'Složi deck'),
      h('p', { class: 'muted' }, 'Otvori spremljeni deck ili napravi novi: odabereš 3 heroja, pa dodaješ karte njihovih boja do 40.')));
}

function importCode(code) {
  let parsed;
  try {
    parsed = decodeDeck(code);
  } catch (e) {
    toast(e.message, 'error');
    return;
  }
  if (!confirmDiscard()) return;
  state.deck = { ...newDeck(), heroes: parsed.heroes, cards: parsed.cards, dirty: true };
  state.deckView = 'deck';
  if (parsed.catalogVersion > state.db.version) toast(`Kod je iz novije baze (v${parsed.catalogVersion}, ovdje v${state.db.version}). Neke karte možda nedostaju.`, 'warn');
  render();
}

function renderDeckEditor() {
  const d = state.deck;
  return h('div', { class: `deck-editor view-${state.deckView}` },
    h('div', { class: 'deck-head' },
      h('input', { class: 'deck-name', placeholder: 'Ime decka', value: d.name, 'aria-label': 'Ime decka', oninput: e => { d.name = e.target.value; d.dirty = true; renderDeckStatus(); } }),
      h('div', { id: 'deck-status' }),
      h('div', { class: 'deck-actions' },
        h('button', { class: 'publish', onclick: () => guard(saveDeck) }, 'Spremi'),
        h('button', { class: 'ghost', onclick: copyCode }, 'Kopiraj kod'),
        d.slug ? h('button', { class: 'ghost', onclick: () => guard(deleteDeck) }, 'Obriši') : null)),
    h('div', { id: 'deck-code' }),
    h('div', { id: 'deck-heroes', class: 'hero-slots' }),
    h('div', { class: 'view-switch', role: 'tablist' },
      h('button', { id: 'sw-pool', role: 'tab', onclick: () => setDeckView('pool') }, 'Bazen'),
      h('button', { id: 'sw-deck', role: 'tab', onclick: () => setDeckView('deck') }, 'Deck')),
    h('div', { class: 'deck-cols' },
      h('section', { class: 'pool-pane' },
        h('div', { class: 'filters' },
          h('input', { type: 'search', placeholder: 'Traži u bazenu…', value: state.pool.q, oninput: e => { state.pool.q = e.target.value; renderPool(); } }),
          h('select', { onchange: e => { state.pool.type = e.target.value; renderPool(); } }, h('option', { value: '' }, 'Svi tipovi'), DECK_TYPES.map(t => h('option', { value: t, selected: state.pool.type === t }, t))),
          h('select', { id: 'pool-color', onchange: e => { state.pool.color = e.target.value; renderPool(); } })),
        h('div', { id: 'pool', class: 'pool' })),
      h('section', { id: 'deck-panel', class: 'deck-panel' })),
    queueRefresh());
}

function queueRefresh() {
  queueMicrotask(refreshDeck);
  return null;
}

function setDeckView(v) {
  state.deckView = v;
  $('.deck-editor')?.classList.remove('view-pool', 'view-deck');
  $('.deck-editor')?.classList.add(`view-${v}`);
  renderSwitch();
}

function refreshDeck() {
  if (!state.deck || !$('.deck-editor')) return;
  renderHeroes();
  renderPool();
  renderDeckPanel();
  renderDeckStatus();
  renderSwitch();
  updateStrip();
}

function renderSwitch() {
  const n = Object.values(state.deck.cards).reduce((s, x) => s + x, 0);
  const pool = $('#sw-pool');
  const deck = $('#sw-deck');
  if (!pool) return;
  pool.className = state.deckView === 'pool' ? 'active' : '';
  deck.className = state.deckView === 'deck' ? 'active' : '';
  pool.setAttribute('aria-selected', String(state.deckView === 'pool'));
  deck.setAttribute('aria-selected', String(state.deckView === 'deck'));
  deck.textContent = `Deck ${n}/${DECK_SIZE}`;
}

function renderDeckStatus() {
  const box = $('#deck-status');
  if (!box) return;
  const r = checkDeck(state.db, state.deck);
  box.className = `deck-status ${r.ready ? 'ready' : 'not-ready'}`;
  fill(box,
    h('strong', {}, `${r.count}/${DECK_SIZE}`),
    h('span', {}, r.ready ? 'Spreman za igru' : 'Nije spreman'),
    state.deck.dirty ? h('span', { class: 'unsaved' }, 'nespremljeno') : null);
}

function renderHeroes() {
  const box = $('#deck-heroes');
  const d = state.deck;
  const taken = new Set(d.heroes);
  const free = heroCards(state.db).filter(c => !taken.has(c.id));
  const slots = [0, 1, 2].map(i => {
    const hero = cardById(d.heroes[i]);
    if (hero) {
      return h('div', { class: `hero-slot filled c-border-${hero.color}` },
        cardImg(hero, { alt: hero.name }),
        h('div', { class: 'hero-info' },
          h('span', { class: 'hero-name' }, hero.name),
          h('span', { class: 'muted small' }, hero.color),
          h('button', { class: 'ghost small-btn', onclick: () => changeDeck(x => { x.heroes = x.heroes.filter(id => id !== hero.id); }) }, 'Makni')));
    }
    return h('label', { class: 'hero-slot empty' },
      h('span', { class: 'muted' }, `Heroj ${i + 1}`),
      h('select', { onchange: e => { if (e.target.value) changeDeck(x => { x.heroes = [...x.heroes, e.target.value]; }); } },
        h('option', { value: '' }, 'Odaberi heroja'),
        free.map(c => h('option', { value: c.id }, `${c.name} (${c.color})`))));
  });
  box.replaceChildren(...slots);
}

function renderPool() {
  const box = $('#pool');
  if (!box) return;
  const d = state.deck;
  const all = deckPool(state.db, d.heroes);
  const colorSel = $('#pool-color');
  const colors = [...new Set(all.map(c => c.color))];
  if (state.pool.color && !colors.includes(state.pool.color)) state.pool.color = '';
  colorSel.replaceChildren(h('option', { value: '' }, 'Sve boje heroja'), ...colors.map(c => h('option', { value: c, selected: state.pool.color === c }, c)));
  if (!d.heroes.length) {
    box.replaceChildren(h('p', { class: 'muted' }, 'Odaberi heroje, pa se ovdje pokažu karte njihovih boja.'));
    return;
  }
  const { q, type, color } = state.pool;
  const needle = q.trim().toLowerCase();
  const cards = all
    .filter(c => (!type || c.type === type) && (!color || c.color === color) && (!needle || [c.name, c.text, ...(c.traits ?? [])].join(' ').toLowerCase().includes(needle)))
    .sort((a, b) => a.cost - b.cost || a.name.localeCompare(b.name));
  box.replaceChildren(...(cards.length ? cards.map(poolCard) : [h('p', { class: 'muted' }, 'Nijedna karta ne odgovara filtru.')]));
}

function poolCard(c) {
  const n = state.deck.cards[c.id] ?? 0;
  const max = LIMITS[c.type];
  return h('div', { class: `pool-card${n ? ' in-deck' : ''}${n >= max ? ' maxed' : ''}` },
    h('button', { class: 'pool-art', title: `Dodaj ${c.name}`, disabled: n >= max, onclick: () => addCard(c.id, 1) }, cardImg(c, { alt: c.name }),
      n ? h('span', { class: 'pool-count' }, `${n}/${max}`) : null),
    h('div', { class: 'pool-meta' },
      h('span', { class: 'pool-name' }, c.name),
      h('span', { class: 'stepper' },
        h('button', { class: 'step', 'aria-label': `Makni jednu ${c.name}`, disabled: !n, onclick: () => addCard(c.id, -1) }, '−'),
        h('button', { class: 'step', 'aria-label': `Dodaj jednu ${c.name}`, disabled: n >= max, onclick: () => addCard(c.id, 1) }, '+'))));
}

function renderDeckPanel() {
  const box = $('#deck-panel');
  if (!box) return;
  const d = state.deck;
  const r = checkDeck(state.db, d);
  const heroColors = [...new Set(d.heroes.map(id => cardById(id)?.color).filter(Boolean))];
  if (state.focus.color && !heroColors.includes(state.focus.color)) state.focus.color = '';

  const rows = Object.entries(d.cards)
    .map(([id, n]) => ({ c: cardById(id), id, n }))
    .sort((a, b) => DECK_TYPES.indexOf(a.c?.type) - DECK_TYPES.indexOf(b.c?.type) || (a.c?.cost ?? 0) - (b.c?.cost ?? 0) || String(a.c?.name).localeCompare(String(b.c?.name)));
  const groups = DECK_TYPES.map(t => [t, rows.filter(x => x.c?.type === t)]).filter(([, list]) => list.length);
  const unknown = rows.filter(x => !x.c);

  fill(box,
    h('div', { class: 'deck-count' },
      h('strong', {}, r.count), h('span', {}, `od ${DECK_SIZE}`),
      h('div', { class: 'meter', role: 'img', 'aria-label': `${r.count} od ${DECK_SIZE} karata` }, h('span', { style: `width:${Math.min(100, (r.count / DECK_SIZE) * 100)}%` }))),
    r.problems.length ? h('ul', { class: 'deck-problems' }, r.problems.map(p => h('li', { class: p.level }, p.msg))) : null,
    h('div', { class: 'random-box' },
      h('div', { class: 'random-row' },
        h('label', { class: 'field' }, h('span', {}, 'Naglasak boje'),
          h('select', { onchange: e => { state.focus.color = e.target.value; renderDeckPanel(); } },
            h('option', { value: '' }, 'Bez naglaska'),
            heroColors.map(c => h('option', { value: c, selected: state.focus.color === c }, c)))),
        state.focus.color ? h('label', { class: 'field' }, h('span', {}, 'Koliko'),
          h('input', { type: 'range', min: 0, max: 1, step: 0.1, value: state.focus.value, oninput: e => { state.focus.value = Number(e.target.value); } })) : null),
      h('div', { class: 'random-row' },
        h('button', { class: 'primary', disabled: d.heroes.length === 0 || r.count >= DECK_SIZE, onclick: fillRandom }, 'Popuni nasumično'),
        h('button', { class: 'ghost', disabled: !r.count, onclick: () => { if (window.confirm('Izbaciti sve karte iz decka? Heroji ostaju.')) changeDeck(x => { x.cards = {}; }); } }, 'Isprazni'))),
    r.count ? h('div', { class: 'deck-charts' }, costCurve(r.curve), colorSplit(r.byColor, r.count)) : null,
    groups.length || unknown.length
      ? h('div', { class: 'deck-rows' },
          groups.map(([t, list]) => h('div', { class: 'deck-group' },
            h('h3', {}, t, h('span', { class: 'muted' }, list.reduce((s, x) => s + x.n, 0))),
            list.map(deckRow))),
          unknown.length ? h('div', { class: 'deck-group' }, h('h3', {}, 'Nepoznate karte'), unknown.map(deckRow)) : null)
      : h('p', { class: 'muted' }, d.heroes.length ? 'Dodaj karte iz bazena ili klikni Popuni nasumično.' : 'Prvo odaberi heroje.'));
}

function deckRow({ c, id, n }) {
  return h('div', { class: 'deck-row' },
    h('span', { class: `dot c-${c?.color ?? 'none'}` }),
    h('span', { class: 'deck-row-cost', title: 'Cost' }, c?.cost ?? '?'),
    h('span', { class: 'deck-row-name' }, c?.name ?? id),
    h('span', { class: 'stepper' },
      h('button', { class: 'step', 'aria-label': `Makni jednu ${c?.name ?? id}`, onclick: () => (c ? addCard(id, -1) : changeDeck(d => { delete d.cards[id]; })) }, '−'),
      h('span', { class: 'deck-row-n' }, n),
      h('button', { class: 'step', 'aria-label': `Dodaj jednu ${c?.name ?? id}`, disabled: !c || n >= LIMITS[c.type], onclick: () => addCard(id, 1) }, '+')));
}

function fillRandom() {
  const next = randomFill(state.db, state.deck, { focusColor: state.focus.color || null, focus: state.focus.color ? state.focus.value : 0 });
  changeDeck(d => { d.cards = next.cards; });
  if (next.missing) toast(`Bazen nije dovoljan: nedostaje ${next.missing} karata do ${DECK_SIZE}.`, 'warn');
}

// Krivulja costova: jedna serija, stupci s brojem iznad, hover daje točan iznos.
function costCurve(curve) {
  const costs = Object.keys(curve).map(Number);
  const max = Math.max(...costs, 3);
  const top = Math.max(...Object.values(curve));
  const bars = [];
  for (let cost = 0; cost <= max; cost++) {
    const n = curve[cost] ?? 0;
    bars.push(h('div', { class: 'bar', title: `Cost ${cost}: ${n} ${n === 1 ? 'karta' : 'karata'}` },
      h('span', { class: 'bar-n' }, n || ''),
      h('span', { class: 'bar-fill', style: `height:${top ? (n / top) * 100 : 0}%` }),
      h('span', { class: 'bar-x' }, cost)));
  }
  return h('figure', { class: 'curve' }, h('figcaption', {}, 'Krivulja costova'), h('div', { class: 'bars' }, bars));
}

// Udio boja: boje su boje karata iz igre; svaka ima i natpis s brojem, pa boja nije jedini nositelj.
function colorSplit(byColor, total) {
  const entries = Object.entries(byColor).sort((a, b) => b[1] - a[1]);
  return h('figure', { class: 'split' },
    h('figcaption', {}, 'Boje'),
    h('div', { class: 'split-bar', role: 'img', 'aria-label': entries.map(([c, n]) => `${c} ${n}`).join(', ') },
      entries.map(([c, n]) => h('span', { class: `c-${c}`, style: `flex:${n}`, title: `${c}: ${n}` }))),
    h('ul', { class: 'split-legend' }, entries.map(([c, n]) => h('li', {}, h('span', { class: `dot c-${c}` }), `${c} ${n}`, h('span', { class: 'muted' }, ` ${Math.round((n / total) * 100)}%`)))));
}

async function copyCode() {
  const code = encodeDeck(state.deck, state.db.version);
  const box = $('#deck-code');
  try {
    await navigator.clipboard.writeText(code);
    toast('Deck kod je kopiran.');
    box.replaceChildren();
  } catch {
    // Bez HTTPS-a (npr. mobitel preko Tailscale adrese) preglednik ne da pisati u clipboard.
    const input = h('input', { readOnly: true, value: code, 'aria-label': 'Deck kod', onfocus: e => e.target.select() });
    box.replaceChildren(h('label', { class: 'field code-out' }, h('span', {}, 'Deck kod (označi i kopiraj)'), input));
    input.focus();
  }
}

// ---------- start ----------

window.addEventListener('beforeunload', e => {
  if (state.deck?.dirty) e.preventDefault();
});

const info = await probeServer();
if (info) {
  await useStore(serverStore(info));
  state.tab = 'decks';
}
render();

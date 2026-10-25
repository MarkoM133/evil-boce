import { analyzeExport, buildPublish, applyAppEdits, obsoleteImages, thumbPlan, thumbName, SIZES, CE_FIELDS, ARCHIVE_DIR, archiveFolder, archivePath,
  CHANGELOG_PATH, changelogEntry, appendChangelog, changesSince, describeChange, publishedPngPaths } from './importer.js';
import { TYPES, COLOR_NAMES, DECK_TYPES, HERO_TYPES, TERRAINS } from './parse.js';
import { checkDeck, deckPool, randomFill, encodeDeck, decodeDeck, slugify, emptyDeck, heroCards, deckChanges, LIMITS, DECK_SIZE } from './deck.js';
import { probeServer, serverStore, folderStore, ConflictError } from './store.js';
import { BALL_COLORS, DEFAULT_ACCENT, heroDefaultColor, ballColors } from './look.js';
import { renderTools } from './tools.js';
import * as fs from './fsdir.js';

const DB_PATH = 'data/cards.json';

const state = {
  store: null,
  db: null,
  logo: null,
  analysis: null,
  tab: 'browse',
  // Brzi filteri: unutar skupine "ili", između skupina "i".
  filter: { q: '', types: [], colors: [], sets: [], specials: [], sort: 'id', since: 0 },
  changelog: null,
  inbox: 0, // fileova u sanduču export/ (samo folder)
  detailTab: 'general', // kartica u detalju karte: general | effect | look
  qfOpen: false, // izbornik "Filters" (skupine brzih filtera koje ne stanu u red)
  selected: null,
  busy: false,
  decks: [],
  deck: null,
  deckView: 'pool',
  pool: { q: '', type: '', color: '', set: '', trait: '' },
  focus: { color: '', value: 0.6 },
  fxProposals: null, // kako igra čita tekst karata (data/fx-proposals.json), za karticu Effect
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

function toast(msg, kind = 'ok', ms = kind === 'error' ? 9000 : 4500) {
  const t = h('div', { class: `toast ${kind}`, role: 'status' }, msg);
  $('#toasts').append(t);
  setTimeout(() => t.remove(), ms);
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
  if (!card) return img;
  if (full) showBest(card, null, u => { img.src = u; });
  else imageFor(card, true).then(u => { if (u) img.src = u; });
  return img;
}

// Puna slika (PNG od ~2 MB) preko mreže se crta komad po komad: dok se cijela ne učita, stoji sličica.
// url: puna slika koja nije karta iz baze (npr. PNG u Uvozu). show(u) se zove sa sličicom, pa s punom slikom.
// Vraća promise koji završi kad je puna slika učitana (ili nije uspjela).
function showBest(card, url, show) {
  let full = false;
  if (card) state.store.imageUrl(card, { thumb: true }).then(u => u && loads(u).then(ok => { if (ok && !full) show(u); }));
  return (card && !url ? bigUrl(card) : loads(url).then(ok => ok && url)).then(u => { if (u) { full = true; show(u); } });
}

// Velika slika: JPEG od 1000 px (data/large); dok ga Objavi još nije napravio, originalni PNG.
async function bigUrl(card) {
  for (const opts of [{ large: true }, {}]) {
    const u = await state.store.imageUrl(card, opts);
    if (u && (await loads(u))) return u;
  }
  return null;
}

// Ikone kao SVG: znakovi poput ⤢ i ✕ na mobitelu dolaze iz drugog fonta i ne sjednu u krug.
const ICONS = {
  zoom: '<path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  prev: '<path d="M15 5l-7 7 7 7"/>',
  next: '<path d="M9 5l7 7-7 7"/>',
};

function icon(name) {
  const span = h('span', { class: 'icon', 'aria-hidden': 'true' });
  span.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</svg>`;
  return span;
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

// width je širina portrait karte; landscape karta (Hero, Evolution) dobije istu visinu, pa je jednako oštra.
async function makeThumb(blob, width) {
  const bmp = await createImageBitmap(blob);
  const scale = Math.min(1, bmp.width > bmp.height ? (width * 7) / 5 / bmp.height : width / bmp.width);
  width = Math.round(bmp.width * scale);
  const height = Math.round(bmp.height * scale);
  const canvas = new OffscreenCanvas(width, height);
  const ctx = canvas.getContext('2d');
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(bmp, 0, 0, width, height);
  bmp.close();
  return canvas.convertToBlob({ type: 'image/jpeg', quality: 0.85 });
}

const cardById = id => state.db.cards.find(c => c.id === id);

// ---------- slika preko cijelog ekrana ----------

// items: [{ card } | { url, title }]. Strelice, swipe i Esc; Natrag (gesta ili tipka) zatvara.
const viewer = { items: [], i: 0, el: null, back: null };
let skipPop = false;

function openViewer(items, i = 0) {
  if (!items.length) return;
  if (!viewer.el) {
    history.pushState(history.state, '', location.hash);
    viewer.back = document.activeElement;
    document.body.classList.add('viewer-open');
  }
  viewer.items = items;
  viewer.i = Math.max(0, i);
  showViewer();
}

function closeViewer(fromPop = false) {
  if (!viewer.el) return;
  viewer.el.remove();
  viewer.el = null;
  viewer.shown = null;
  document.body.classList.remove('viewer-open');
  viewer.back?.focus?.();
  if (!fromPop) {
    skipPop = true;
    history.back();
  }
}

function stepViewer(d) {
  const n = viewer.items.length;
  if (n < 2) return;
  viewer.i = (viewer.i + d + n) % n;
  showViewer();
}

const viewerTitle = it => it.title ?? (it.card ? `${it.card.id} · ${it.card.name}` : '');


// Okvir se gradi jednom; pri listanju ostaje stara slika dok nova nije učitana, pa nema bljeska.
function buildViewer() {
  const img = h('img', { class: 'viewer-img', alt: '' });
  const el = h('div', { class: 'viewer', role: 'dialog', 'aria-modal': 'true', onclick: e => { if (e.target === el || e.target === img) closeViewer(); } },
    img,
    h('div', { class: 'viewer-bar' }, h('span', { class: 'viewer-title' }), h('span', { class: 'viewer-n' })),
    h('button', { class: 'viewer-nav prev', 'aria-label': 'Previous card', onclick: () => stepViewer(-1) }, icon('prev')),
    h('button', { class: 'viewer-nav next', 'aria-label': 'Next card', onclick: () => stepViewer(1) }, icon('next')),
    h('button', { class: 'viewer-close', 'aria-label': 'Close', onclick: () => closeViewer() }, icon('close')));
  let x0 = null;
  el.addEventListener('touchstart', e => { x0 = e.touches.length === 1 && (window.visualViewport?.scale ?? 1) < 1.05 ? e.touches[0].clientX : null; }, { passive: true });
  el.addEventListener('touchend', e => {
    if (x0 === null) return;
    const dx = e.changedTouches[0].clientX - x0;
    x0 = null;
    if (Math.abs(dx) > 50) stepViewer(dx < 0 ? 1 : -1);
  });
  document.body.append(el);
  viewer.el = el;
  el.querySelector('.viewer-close').focus();
}

function showViewer() {
  if (!viewer.el) buildViewer();
  const it = viewer.items[viewer.i];
  const n = viewer.items.length;
  const el = viewer.el;
  const title = viewerTitle(it);
  el.setAttribute('aria-label', title);
  el.classList.toggle('single', n < 2);
  el.querySelector('.viewer-title').textContent = title;
  el.querySelector('.viewer-n').textContent = n > 1 ? `${viewer.i + 1}/${n}` : '';
  const img = el.querySelector('.viewer-img');
  img.alt = title;
  viewer.shown = it;
  if (it.card && !it.card.image) img.removeAttribute('src');
  const neighbours = n > 1 ? [1, -1].map(d => viewer.items[(viewer.i + d + n) % n]) : [];
  // Sličice susjeda odmah (male su), njihove pune slike tek kad je trenutna gotova, da joj ne uzimaju mrežu.
  for (const next of neighbours) if (next.card) state.store.imageUrl(next.card, { thumb: true }).then(u => u && loads(u));
  showBest(it.card, it.card ? null : it.url, u => { if (viewer.shown === it) img.src = u; })
    .then(() => { if (viewer.shown === it) for (const next of neighbours) if (next.card) bigUrl(next.card); else loads(next.url); });
}

// Pregled: klik bilo gdje izvan detalja karte ga zatvori. Klik na drugu kartu ili heroja u traci je otvori,
// a prikaz preko cijelog ekrana i poruke ga ne zatvaraju.
document.addEventListener('click', e => {
  if (state.tab !== 'browse' || !state.selected || viewer.el || state.busy) return;
  if (!e.target.isConnected || e.target.closest('#detail, .tile, .slice, .viewer, #toasts, .quick')) return;
  closeCard();
});

// Izbornik "Filters" se zatvori klikom izvan njega (klik na filter u njemu ga ostavlja otvorenog).
document.addEventListener('click', e => {
  if (!state.qfOpen || !e.target.isConnected || e.target.closest('.qf-more')) return;
  state.qfOpen = false;
  const more = $('.qf-more');
  if (more) { more.querySelector('.qf-panel').hidden = true; more.querySelector('.qf-more-btn').setAttribute('aria-expanded', 'false'); }
});

// Prečaci izvan polja za unos: / za tražilicu, Ctrl+Z za Poništi u decku.
document.addEventListener('keydown', e => {
  if (viewer.el || e.target.closest?.('input, textarea, select, [contenteditable]')) return;
  if (e.key === '/' && !e.ctrlKey && !e.metaKey && !e.altKey) {
    const search = $('main input[type=search]');
    if (search) {
      e.preventDefault();
      search.focus();
      search.select();
    }
  } else if (e.key.toLowerCase() === 'z' && (e.ctrlKey || e.metaKey) && !e.shiftKey && state.tab === 'decks' && state.deck?.undo?.length) {
    e.preventDefault();
    undoDeck();
  }
});

document.addEventListener('keydown', e => {
  if (!viewer.el) return;
  if (e.key === 'Escape') closeViewer();
  else if (e.key === 'ArrowLeft') stepViewer(-1);
  else if (e.key === 'ArrowRight') stepViewer(1);
  else return;
  e.preventDefault();
});

// Gumb koji otvara sliku karte preko cijelog ekrana; list je popis kroz koji se lista strelicama.
function zoomButton(card, list, label = 'Enlarge') {
  return h('button', { class: 'zoom', title: `${label}: ${card.name}`, 'aria-label': `${label}: ${card.name}`, onclick: e => { e.stopPropagation(); openViewer(list.map(c => ({ card: c })), list.indexOf(card)); } }, icon('zoom'));
}

// ---------- podaci ----------

async function useStore(store) {
  if (state.logo?.startsWith('blob:')) URL.revokeObjectURL(state.logo);
  state.store?.dropImageUrls?.();
  state.store = store;
  state.analysis = null;
  state.selected = null;
  state.db = await store.readDb();
  state.changelog = await store.readChangelog();
  state.fxProposals = await store.readFxProposals().catch(() => null);
  state.logo = await store.logoUrl();
  state.decks = await store.listDecks();
  state.deck = null;
  state.inbox = await countInbox();
  if (state.inbox) {
    const go = h('button', { class: 'toast-action', onclick: () => { go.closest('.toast')?.remove(); state.tab = 'import'; render(); } }, 'Import');
    toast([`${state.inbox} ${plural(state.inbox, 'file', 'files')} waiting in export/. `, go], 'ok', 10000);
  }
  replaceNext = true;
  whatsNew();
}

async function reloadDb() {
  state.db = await state.store.readDb();
  state.changelog = await state.store.readChangelog();
  state.store.dropImageUrls?.();
}

// Fileovi koji čekaju u sanduču export/ (bez arhive).
async function countInbox() {
  if (!state.store?.canImport) return 0;
  const dir = await fs.getDir(root(), 'export');
  return dir ? (await fs.walkFiles(dir, 'export', path => path === ARCHIVE_DIR)).length : 0;
}

// Kad se vratiš u app (npr. iz OneDrivea), broj u sanduču se osvježi bez ponovnog crtanja stranice.
window.addEventListener('focus', async () => {
  if (!state.store?.canImport || state.busy) return;
  const n = await countInbox().catch(() => state.inbox);
  if (n === state.inbox) return;
  state.inbox = n;
  document.querySelectorAll('.import-btn').forEach(b => b.replaceWith(importButton()));
  document.querySelectorAll('.side-data-badge').forEach(b => b.replaceChildren(...(n ? [h('span', { class: 'tab-badge' }, n)] : [])));
  if (state.tab === 'import' && !state.analysis) render();
});

const SEEN_KEY = 'evil-boce-seen-version';

// Nova verzija baze od zadnjeg otvaranja na ovom uređaju: kratka poruka što se promijenilo.
function whatsNew() {
  let seen = null;
  try { seen = Number(localStorage.getItem(SEEN_KEY)) || null; } catch {}
  try { localStorage.setItem(SEEN_KEY, String(state.db.version)); } catch {}
  if (!seen || state.db.version <= seen) return;
  const kinds = [...changesSince(state.changelog, seen).values()].map(list => (list.some(c => c.kind === 'new') ? 'new' : list.at(-1).kind));
  const count = (...k) => kinds.filter(x => k.includes(x)).length;
  const parts = [[count('new'), 'new'], [count('changed', 'restored'), 'changed'], [count('deleted'), 'deleted']]
    .filter(([n]) => n).map(([n, w]) => `${n} ${w}`);
  toast(`Cards updated to v${state.db.version}${parts.length ? `: ${parts.join(', ')}` : ''}. Details: click the version at the top.`);
}

const root = () => state.store.root;

// Drive sinkronizira između dva računala: prije pisanja provjeri da baza nije promijenjena u međuvremenu.
async function assertFresh() {
  const disk = await state.store.readDb();
  if (disk.version !== state.db.version || disk.updated !== state.db.updated) {
    state.db = disk;
    state.analysis = null;
    throw new Error(`cards.json was changed in the meantime (version ${disk.version}). Run Import again.`);
  }
}

// Uz bazu se zapiše i povijest promjena (razlika prema dosadašnjoj verziji).
async function writeDb(db) {
  const old = state.db;
  await fs.writeFile(root(), DB_PATH, JSON.stringify(db, null, 2) + '\n');
  state.db = db;
  const log = appendChangelog(await state.store.readChangelog(), changelogEntry(old, db));
  await fs.writeFile(root(), CHANGELOG_PATH, JSON.stringify(log, null, 2) + '\n');
  state.changelog = log;
  try { localStorage.setItem(SEEN_KEY, String(db.version)); } catch {}
}

// ---------- akcije: folder i uvoz ----------

async function pickFolder() {
  if (!window.showDirectoryPicker) throw new Error('This browser can\'t open a folder. Open the page in Chrome or Edge on a computer.');
  const handle = await fs.pickRoot();
  state.savedRoot = handle;
  await useStore(folderStore(handle));
  state.tab = 'browse';
  if (!(await fs.getDir(handle, 'export')) && !(await fs.getDir(handle, 'data'))) {
    toast(`The folder "${handle.name}" has neither export/ nor data/. Is it the "Evil Boce" folder?`, 'warn');
  }
}

async function resume(handle) {
  if ((await fs.permission(handle, true)) !== 'granted') throw new Error('Access to the folder was not allowed.');
  await useStore(folderStore(handle));
  await applyHash();
}

async function runImport() {
  const exportDir = await fs.getDir(root(), 'export');
  if (!exportDir) throw new Error('The chosen folder has no export/ folder.');
  await reloadDb();
  const files = await fs.walkFiles(exportDir, 'export', path => path === ARCHIVE_DIR);
  const xmlFiles = [];
  const pngFiles = [];
  for (const { path, file } of files) {
    if (/\.xml$/i.test(path)) xmlFiles.push({ path, text: await file.text(), lastModified: file.lastModified });
    else if (/\.png$/i.test(path)) pngFiles.push({ path, file, lastModified: file.lastModified, getBytes: async () => new Uint8Array(await file.arrayBuffer()) });
  }
  state.analysis = await analyzeExport({ xmlFiles, pngFiles, db: state.db });
  state.analysis.files = files.map(({ path, file }) => ({ path, lastModified: file.lastModified, size: file.size }));
  state.analysis.fileCount = { xml: xmlFiles.length, png: pngFiles.length };
  state.analysis.missingThumbs = await countMissingSizes(state.db);
}

async function publish() {
  const a = state.analysis;
  if (!a || a.errors.length) return;
  await assertFresh();
  const { db, writes, changed, bumped } = buildPublish(state.db, a);
  let old = [];
  if (changed) {
    for (const w of writes) await fs.writeFile(root(), w.path, await w.png.getBytes());
    await writeDb(db);
    old = obsoleteImages(db, await fs.listFileNames(root(), 'data/images'));
    for (const f of old) await fs.removeFile(root(), `data/images/${f}`);
  }
  const thumbs = await updateThumbs(db);
  const archived = await archiveExport(a.files, publishedPngPaths(a));
  state.inbox = await countInbox();
  state.analysis = null;
  state.store.dropImageUrls();
  const parts = [];
  if (changed) parts.push(bumped ? `version ${db.version}, ${changed} ${plural(changed, 'card', 'cards')}` : `look of ${changed} ${plural(changed, 'card', 'cards')} (version stays v${db.version})`);
  if (thumbs) parts.push(`${thumbs} ${plural(thumbs, 'resized image', 'resized images')}`);
  if (old.length) parts.push(`old images deleted: ${old.length}`);
  if (archived.moved) parts.push(`${archived.moved} ${plural(archived.moved, 'file', 'files')} moved from export/ to ${archived.folder}/`);
  if (archived.removed) parts.push(`${archived.removed} published ${plural(archived.removed, 'PNG', 'PNGs')} removed from export/ (already in data/)`);
  const msg = changed || thumbs ? `Published: ${parts.join(', ')}.`
    : parts.length ? `No card changes; ${parts.join(', ')}.` : 'Nothing to publish.';
  if (archived.left.length) toast(`${msg} Left in export/: ${archived.left.length} ${plural(archived.left.length, 'file', 'files')} changed after Import; run Import again.`, 'warn');
  else toast(msg);
}

// Sanduče export/: sve što je Uvoz pročitao ide u arhivu, osim fileova promijenjenih u međuvremenu.
// Objavljeni PNG-ovi (slike karata i spriteovi) se brišu jer su već u data/; u arhivu ide popis.json sa svime.
async function archiveExport(files, published) {
  const folder = archiveFolder();
  const left = [];
  const list = [];
  let moved = 0;
  let removed = 0;
  for (const f of files) {
    const now = await fs.getFile(root(), f.path);
    if (!now) continue;
    if (now.lastModified !== f.lastModified || now.size !== f.size) {
      left.push(f.path);
      continue;
    }
    const inData = published.has(f.path);
    if (inData) {
      await fs.removeFile(root(), f.path);
      removed++;
    } else {
      await fs.moveFile(root(), f.path, archivePath(f.path, folder));
      moved++;
    }
    list.push({ path: f.path, size: f.size, lastModified: new Date(f.lastModified).toISOString(), kept: inData ? 'data' : 'arhiva' });
  }
  if (list.length) await fs.writeFile(root(), `${folder}/popis.json`, JSON.stringify({ published: new Date().toISOString(), files: list }, null, 2) + '\n');
  // Prazni podfolderi sanduča, od najdubljih prema gore.
  const dirs = new Set();
  for (const f of files) {
    const parts = f.path.split('/').slice(1, -1);
    for (let i = parts.length; i > 0; i--) dirs.add(`export/${parts.slice(0, i).join('/')}`);
  }
  for (const d of [...dirs].sort((x, y) => y.split('/').length - x.split('/').length)) await fs.removeDirIfEmpty(root(), d);
  return { folder, moved, removed, left };
}

async function countMissingSizes(db) {
  let n = 0;
  for (const s of SIZES) n += thumbPlan(db, await fs.listFileNames(root(), `data/${s.dir}`)).missing.length;
  return n;
}

// Umanjene slike (male i velike) za sve karte kojima nedostaju; stare verzije se brišu.
async function updateThumbs(db) {
  let made = 0;
  for (const s of SIZES) {
    const plan = thumbPlan(db, await fs.listFileNames(root(), `data/${s.dir}`));
    for (const c of plan.missing) {
      const f = await fs.getFile(root(), `data/${c.image}`);
      if (f) await fs.writeFile(root(), `data/${s.dir}/${thumbName(c)}`, await makeThumb(f, s.width));
    }
    for (const f of plan.extra) await fs.removeFile(root(), `data/${s.dir}/${f}`);
    made += plan.missing.length;
  }
  return made;
}

async function saveEdits(id, edits) {
  await assertFresh();
  const { db, changed, bumped } = applyAppEdits(state.db, { [id]: edits });
  if (!changed) {
    toast('No changes.');
    return;
  }
  await writeDb(db);
  toast(bumped ? `Saved: version ${db.version}.` : `Saved (look only; version stays v${db.version}).`);
}

// ---------- prikaz: okvir ----------

function render() {
  const app = $('#app');
  if (state.store) {
    document.body.classList.remove('detail-open'); // pregled ga vrati kad nacrta detalj
    app.replaceChildren(renderHeader(), renderMain());
    updateStrip();
    cardPushed = false;
    syncHash();
  } else app.replaceChildren(renderWelcome());
}

// ---------- adresa: svaki pogled ima svoj #/…, pa gesta ili tipka Natrag vraća korak unatrag ----------

// history nije u izborniku: otvara se klikom na verziju u zaglavlju ili u detalju karte.
const TAB_SLUG = { import: 'import', browse: 'browse', decks: 'decks', tools: 'tools', history: 'history' };
const SLUG_TAB = Object.fromEntries(Object.entries(TAB_SLUG).map(([k, v]) => [v, k]));
// Stare hrvatske adrese (#/uvoz, #/pregled, #/deckovi/novi) i dalje rade.
const OLD_SLUG_TAB = { uvoz: 'import', pregled: 'browse', deckovi: 'decks' };
const NEW_DECK = 'new';
let replaceNext = true; // sljedeća promjena adrese zamjenjuje trenutnu umjesto da doda korak
let cardPushed = false; // karta je otvorena iz mreže, pa je Zatvori isto što i Natrag

function currentHash() {
  const parts = [TAB_SLUG[state.tab]];
  if (state.tab === 'browse' && state.selected) parts.push(state.selected);
  if (state.tab === 'decks' && state.deck) {
    parts.push(state.deck.slug ?? NEW_DECK);
    if (state.deckView === 'deck') parts.push('deck');
  }
  return '#/' + parts.map(encodeURIComponent).join('/');
}

function syncHash() {
  const hash = currentHash();
  if (hash !== location.hash) history[replaceNext ? 'replaceState' : 'pushState'](null, '', hash);
  replaceNext = false;
}

// Postavi stanje prema adresi. Vraća false ako korisnik ne želi odbaciti nespremljeni deck.
async function applyHash() {
  const [tabSlug, rawId, view] = location.hash.replace(/^#\/?/, '').split('/').map(decodeURIComponent);
  const old = Object.hasOwn(OLD_SLUG_TAB, tabSlug);
  const tab = old ? OLD_SLUG_TAB[tabSlug] : SLUG_TAB[tabSlug];
  if (!tab) return true;
  const id = old && rawId === 'novi' ? NEW_DECK : rawId;
  if (tab === 'decks') {
    const want = id || null;
    const have = state.deck ? (state.deck.slug ?? NEW_DECK) : null;
    if (want !== have) {
      if (!confirmDiscard()) return false;
      if (!want) state.deck = null;
      else if (want === NEW_DECK) state.deck = newDeck();
      else if (state.decks.some(d => d.slug === want && !d.broken)) await openDeck(want);
      else {
        state.deck = null;
        toast('That deck no longer exists.', 'warn');
      }
    }
    state.deckView = view === 'deck' ? 'deck' : 'pool';
  }
  if (tab === 'browse') state.selected = id && cardById(id) ? id : null;
  state.tab = tab;
  return true;
}

window.addEventListener('popstate', () => {
  if (skipPop) {
    skipPop = false;
    return;
  }
  if (viewer.el) {
    closeViewer(true);
    return;
  }
  if (!state.store) return;
  cardPushed = false;
  guard(async () => {
    // Odbijeno odbacivanje: render vrati adresu trenutnog decka.
    if (!(await applyHash())) replaceNext = false;
  });
});

// Traka s herojima na vrhu stranice, preko cijele širine: kose kriške s crtežom s karte, polako klize ulijevo.
// Popis se ponovi koliko treba da traka uvijek bude puna; pomak za jednu duljinu popisa izgleda kao beskonačna vrpca.
// Zaglavlje se crta iznova na svaki render, pa traka nastavlja s mjesta na kojem je bila (stripTime).
const STRIP_SPEED = 28; // px u sekundi
const STRIP_GAP = 6;
let stripAnim = null;
let stripTime = 0;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const sliceWidth = () => (matchMedia('(max-width: 760px)').matches ? 96 : 150);
const zoom = () => Number(getComputedStyle(document.documentElement).getPropertyValue('--z')) || 1;

function stripCopies(n) {
  if (reducedMotion.matches) return 1;
  const list = n * (sliceWidth() + STRIP_GAP);
  return Math.max(2, Math.ceil(innerWidth / zoom() / list) + 1);
}

function heroStrip() {
  const heroes = heroCards(state.db).sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  if (!heroes.length) return null;
  const w = sliceWidth();
  const copies = stripCopies(heroes.length);
  const slices = Array.from({ length: copies }, (_, copy) => heroes.map(c => {
    const art = h('span', { class: `slice-art${c.landscape ? ' wide-art' : ''}` });
    imageFor(c, true).then(u => { if (u) art.style.backgroundImage = `url("${u}")`; });
    // Ponovljene kopije su samo ukras: čitač ekrana i Tab vide svakog heroja jednom.
    return h('button', {
      class: `slice c-edge-${c.color}`,
      style: `width: ${w}px`,
      'data-id': c.id,
      title: c.name,
      'aria-label': `${c.name}: open in Browse, or add to / remove from the deck on Decks`,
      'aria-hidden': copy ? 'true' : null,
      tabindex: copy ? -1 : null,
      // Na Decks heroj ide u deck, inače se otvori u pregledu.
      onclick: () => { if (state.tab === 'decks') { pickHeroFromStrip(c); return; } state.tab = 'browse'; state.selected = c.id; render(); },
    }, art, h('span', { class: 'slice-name' }, c.name));
  }));
  const track = h('div', { class: 'strip-track' }, slices.flat());
  const strip = h('div', { class: 'hero-strip', id: 'hero-strip', 'data-copies': copies }, track);
  if (stripAnim) stripTime = stripAnim.currentTime ?? stripTime;
  const wasPaused = stripAnim?.playState === 'paused'; // miš je ostao na traci (npr. klik na heroja)
  stripAnim?.cancel();
  stripAnim = null;
  if (copies > 1) {
    const list = heroes.length * (w + STRIP_GAP);
    stripAnim = track.animate([{ transform: 'translateX(0)' }, { transform: `translateX(-${list}px)` }],
      { duration: (list / STRIP_SPEED) * 1000, iterations: Infinity });
    stripAnim.currentTime = stripTime;
    if (wasPaused) stripAnim.pause();
    // Stane dok je miš na traci, da se heroj može kliknuti.
    strip.addEventListener('pointerenter', e => { if (e.pointerType === 'mouse') stripAnim?.pause(); });
    strip.addEventListener('pointerleave', () => stripAnim?.play());
  }
  return strip;
}

// Promjena veličine prozora može tražiti više kopija; traka se tada složi iznova.
let resizeTimer = 0;
addEventListener('resize', () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    const old = $('#hero-strip');
    if (!old || !state.store) return;
    const n = heroCards(state.db).length;
    if (Number(old.dataset.copies) === stripCopies(n) && old.querySelector('.slice')?.style.width === `${sliceWidth()}px`) return;
    old.replaceWith(heroStrip());
    updateStrip();
  }, 200);
});

// U deck builderu svijetle samo heroji iz decka.
function updateStrip() {
  const strip = $('#hero-strip');
  if (!strip) return;
  const picked = new Set(state.tab === 'decks' && state.deck ? state.deck.heroes : []);
  strip.classList.toggle('has-picked', picked.size > 0);
  for (const s of strip.querySelectorAll('.slice')) s.classList.toggle('picked', picked.has(s.dataset.id));
}

function wordmark(size) {
  return h('span', { class: `wordmark ${size}`, role: 'img', 'aria-label': 'Evil Boće' },
    h('span', { class: 'w-evil' }, 'Evil'), h('span', { class: 'w-boce' }, 'Boće'));
}

// Logo i podaci: folder, verzija (link na povijest), broj karata, Import i odabir foldera. Na računalu stoje u bloku
// dolje lijevo (side-data), na mobitelu u traci ispod heroja (top-bar); CSS pokaže jedno od dvoje.
function brand() {
  return h('div', { class: 'brand' },
    state.logo ? h('img', { class: 'logo', src: state.logo, alt: 'Evil Boće' }) : wordmark('small'),
    h('span', { class: 'brand-sub' }, 'Evil Boće'));
}

// Blok dolje lijevo (računalo): sklopljen je samo logo i ime (s crvenim jezičcem iznad, kao ladica), klik ga digne
// s podacima, Importom i folderom.
// Stanje se pamti na uređaju; dok je sklopljen, broj fileova u export/ stoji uz ime.
const SIDE_OPEN_KEY = 'evil-boce-side-open';
function sideData() {
  let open = false;
  try { open = localStorage.getItem(SIDE_OPEN_KEY) === '1'; } catch {}
  const badge = () => (state.inbox && state.store.canImport ? h('span', { class: 'tab-badge', title: `${state.inbox} ${plural(state.inbox, 'file', 'files')} waiting in export/` }, state.inbox) : null);
  const box = h('div', { class: `side-data${open ? ' open' : ''}` });
  const toggle = h('button', { type: 'button', class: 'side-data-toggle', 'aria-expanded': String(open), title: 'Data, Import and folder', onclick: () => {
    open = !open;
    try { localStorage.setItem(SIDE_OPEN_KEY, open ? '1' : '0'); } catch {}
    box.classList.toggle('open', open);
    toggle.setAttribute('aria-expanded', String(open));
  } }, brand(), h('span', { class: 'side-data-badge' }, badge()));
  box.append(h('div', { class: 'side-data-body' }, h('div', {}, folderInfo())), toggle);
  return box;
}

function folderInfo() {
  const n = state.db.cards.length;
  const server = state.store.kind === 'server';
  return [
    h('span', { class: 'folder-name', title: server ? 'Data from the computer, via server' : 'Chosen Drive folder' }, server ? `${state.store.name} via server` : state.store.name),
    h('span', { class: 'folder-db' },
      h('button', { class: `version-link${state.tab === 'history' ? ' active' : ''}`, title: 'Change history', onclick: () => openHistory() }, `Version ${state.db.version}`),
      h('span', { class: 'sep', 'aria-hidden': 'true' }), `${n} ${plural(n, 'card', 'cards')}`),
    h('span', { class: 'folder-actions' },
      state.store.canImport ? importButton() : null,
      server && state.savedRoot ? h('button', { class: 'ghost', title: 'Folder for Import and editing', onclick: () => guard(() => resume(state.savedRoot)) }, `Continue with "${state.savedRoot.name}"`) : null,
      !server || window.showDirectoryPicker ? h('button', { class: 'ghost', onclick: () => guard(pickFolder) }, server ? (state.savedRoot ? 'Other folder' : 'Choose folder') : 'Change folder') : null),
  ];
}

function renderHeader() {
  return h('header', { class: 'top' },
    heroStrip(),
    h('div', { class: 'top-bar' }, brand(), h('div', { class: 'folder' }, folderInfo())));
}

function renderWelcome() {
  const actions = h('div', { class: 'welcome-actions' },
    h('button', { class: 'primary', onclick: () => guard(pickFolder) }, 'Choose folder'));
  const box = h('section', { class: 'welcome' },
    h('div', { class: 'emblem', 'aria-hidden': 'true' }, h('span', { class: 'ring' }), wordmark('big')),
    h('div', { class: 'welcome-text' },
      h('h1', {}, 'Card database'),
      h('p', {}, 'Choose the shared Drive folder "Evil Boce". It holds export/ with the Card Engine exports and data/ with the card database. The browser remembers it, so you only choose it once.'),
      actions,
      !window.showDirectoryPicker ? h('p', { class: 'error-text' }, 'This browser can\'t open a folder. Open the page in Chrome or Edge.') : null));
  fs.loadRoot().then(handle => {
    if (!handle || state.store) return;
    actions.append(h('button', { class: 'ghost', onclick: () => guard(() => resume(handle)) }, `Continue with "${handle.name}"`));
  });
  return box;
}

// Import je uz podatke gore (samo s odabranim folderom); kad u sanduču export/ nešto čeka, gumb je crven s brojem.
function importButton() {
  const n = state.inbox;
  return h('button', {
    class: `import-btn${n ? ' waiting' : ''}${state.tab === 'import' ? ' active' : ''}`,
    title: n ? `${n} ${plural(n, 'file', 'files')} waiting in export/` : 'Import from export/ and Publish',
    onclick: () => { state.tab = 'import'; render(); },
  }, 'Import', n ? h('span', { class: 'tab-badge' }, n) : null);
}

function renderMain() {
  const tabs = [
    ['browse', 'Browse'],
    ['decks', 'Decks'],
    ['tools', 'Tools'],
  ];
  const view = { import: renderImport, browse: renderBrowse, decks: renderDecks, tools: () => renderTools({ h, toast, loadModel: lamaModel }), history: renderHistory }[state.tab]();
  // Na desktopu je izbornik stupac lijevo (s listom deckova na kartici Deckovi), na mobitelu kartice gore.
  return h('div', { class: 'shell' },
    h('aside', { class: 'side' },
      h('nav', { class: 'tabs', role: 'tablist' },
        tabs.map(([key, label]) => h('button', { id: `tab-${key}`, role: 'tab', 'aria-selected': String(state.tab === key), class: state.tab === key ? 'active' : '', onclick: () => { state.tab = key; render(); } }, label))),
      state.tab === 'decks' ? renderDeckList() : null),
    sideData(),
    h('main', {}, view));
}

// LaMa za alat Erase text: tools/lama.onnx iz zajedničkog foldera (folder) ili sa servera.
async function lamaModel() {
  if (state.store.kind === 'folder') {
    const f = await fs.getFile(root(), 'tools/lama.onnx');
    if (!f) throw new Error('No tools/lama.onnx in the chosen folder (Syncthing may still be copying it).');
    return f.arrayBuffer();
  }
  const r = await fetch('tools/lama.onnx');
  if (!r.ok) throw new Error('The server has no tools/lama.onnx.');
  return r.arrayBuffer();
}

// ---------- Uvoz ----------

const STATUS_LABEL = { new: 'New', changed: 'Changed', same: 'Unchanged' };

function renderImport() {
  if (!state.store.canImport) {
    return h('section', { class: 'panel' },
      h('p', { class: 'muted' }, 'Import and Publish only work with a chosen Drive folder, in Chrome or Edge on a computer. Here you see the cards and decks from the computer, via server.'),
      window.showDirectoryPicker ? h('div', { class: 'toolbar' },
        state.savedRoot ? h('button', { class: 'primary', onclick: () => guard(() => resume(state.savedRoot)) }, `Continue with "${state.savedRoot.name}"`) : null,
        h('button', { class: state.savedRoot ? 'ghost' : 'primary', onclick: () => guard(pickFolder) }, state.savedRoot ? 'Other folder' : 'Choose folder')) : null);
  }
  const a = state.analysis;
  const wrap = h('section', { class: 'panel' },
    h('div', { class: 'toolbar' },
      h('button', { class: 'primary', onclick: () => guard(runImport) }, a ? 'Reload export/' : 'Import from export/'),
      a ? h('button', { class: 'publish', disabled: a.errors.length > 0 || (!a.entries.some(e => e.status !== 'same') && !a.missingThumbs && !a.files.length), onclick: () => guard(publish) }, 'Publish') : null,
      a?.errors.length ? h('span', { class: 'error-text' }, 'Publishing is blocked while there are errors.') : null,
      a?.missingThumbs ? h('span', { class: 'muted' }, `${a.missingThumbs} resized ${plural(a.missingThumbs, 'image', 'images')} missing (thumbnails and large images for faster loading); Publish creates them.`) : null));
  if (!a) {
    wrap.append(h('p', { class: `inbox-line${state.inbox ? ' waiting' : ''}` },
      state.inbox ? `${state.inbox} ${plural(state.inbox, 'file', 'files')} waiting in export/.` : 'export/ is empty: nothing new to import.'));
    wrap.append(h('p', { class: 'muted' }, 'Reads all XMLs and PNGs from export/ (and its subfolders), compares them with data/cards.json and shows what will change. Nothing is written until you click Publish. After Publish the files from export/ move to export/objavljeno/, so export/ only holds what is not published yet.'));
    return wrap;
  }
  if (!a.files.length) wrap.append(h('p', { class: 'muted' }, 'export/ is empty: everything is already published (the archive is in export/objavljeno/).'));
  const count = s => a.entries.filter(e => e.status === s).length;
  wrap.append(h('div', { class: 'stats' },
    stat('New', count('new'), 'new'),
    stat('Changed', count('changed'), 'changed'),
    stat('Unchanged', count('same'), 'same'),
    stat('Errors', a.errors.length, 'error'),
    stat('Warnings', a.warnings.length, 'warn'),
    h('p', { class: 'muted small' }, `${a.fileCount.xml} XML, ${a.fileCount.png} PNG in export/; after Publish they move to export/objavljeno/`)));
  wrap.append(...[messages('Errors', a.errors, 'error'), messages('Warnings', a.warnings, 'warn'), messages('Info', a.infos, 'info', true)].filter(Boolean));
  const changes = a.entries.filter(e => e.status !== 'same');
  if (changes.length) wrap.append(h('h3', {}, 'Changes'), h('div', { class: 'changes' }, changes.map(renderEntry)));
  const same = a.entries.filter(e => e.status === 'same');
  if (same.length) wrap.append(h('details', { class: 'same' }, h('summary', {}, `Unchanged (${same.length})`), h('p', { class: 'muted' }, same.map(e => `${e.id} ${e.card.name}`).join(', '))));
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

// Polje 'landscape' se u Uvozu i detalju prikazuje kao layout karte.
const fieldLabel = k => (k === 'landscape' ? 'layout' : k);
const fieldValue = (k, v) => (k === 'landscape' ? (v ? 'landscape' : 'portrait') : fmt(v));

function renderEntry(e) {
  const imgs = h('div', { class: 'thumbs' });
  // Klik na sliku: preko cijelog ekrana, strelicama prije/poslije.
  const items = [];
  const zoomable = (fig, item) => {
    const i = items.push(item) - 1;
    fig.classList.add('zoomable');
    fig.title = 'Full screen';
    fig.addEventListener('click', () => openViewer(items, i));
    return fig;
  };
  if (e.old && e.imageChanged) {
    const oldImg = h('img', { alt: 'old image', loading: 'lazy' });
    state.store.imageUrl(e.old).then(u => { if (u) oldImg.src = u; else oldImg.replaceWith(h('div', { class: 'noimg' }, 'old image is not in data/images')); });
    imgs.append(zoomable(h('figure', {}, oldImg, h('figcaption', {}, 'before')), { card: e.old, title: `${e.id} · before` }));
  }
  if (e.png) {
    if (!pngUrls.has(e.png.path)) pngUrls.set(e.png.path, URL.createObjectURL(e.png.file));
    imgs.append(zoomable(h('figure', {}, h('img', { alt: e.card.name, src: pngUrls.get(e.png.path), loading: 'lazy' }),
      h('figcaption', { class: e.staleImage ? 'stale' : null }, e.old ? (e.imageChanged ? 'new image' : e.staleImage ? 'same image: outdated?' : 'same image') : 'image')),
      { url: pngUrls.get(e.png.path), title: `${e.id} · ${e.card.name} · ${e.png.path}` }));
  } else if (e.staleImage) {
    const oldImg = h('img', { alt: 'old image', loading: 'lazy' });
    state.store.imageUrl(e.old).then(u => { if (u) oldImg.src = u; else oldImg.replaceWith(h('div', { class: 'noimg' }, 'old image is not in data/images')); });
    imgs.append(zoomable(h('figure', {}, oldImg, h('figcaption', { class: 'stale' }, 'no PNG: old one stays')), { card: e.old }));
  }
  if (e.spritePng) {
    const p = e.spritePng;
    if (!pngUrls.has(p.path)) pngUrls.set(p.path, URL.createObjectURL(p.file));
    imgs.append(zoomable(h('figure', { class: 'sprite' }, h('img', { alt: `${e.card.name} sprite`, src: pngUrls.get(p.path), loading: 'lazy' }),
      h('figcaption', {}, e.old ? (e.spriteChanged ? 'new sprite' : 'same sprite') : 'sprite')),
      { url: pngUrls.get(p.path), title: `${e.id} · ${e.card.name} · ${p.path}` }));
  }
  if (e.rotPng) {
    const p = e.rotPng;
    if (!pngUrls.has(p.path)) pngUrls.set(p.path, URL.createObjectURL(p.file));
    imgs.append(zoomable(h('figure', {}, h('img', { alt: `${e.card.name} rotated`, src: pngUrls.get(p.path), loading: 'lazy' }),
      h('figcaption', {}, e.old ? (e.rotChanged ? 'new rotated (deck)' : 'same rotated (deck)') : 'rotated (deck)')),
      { url: pngUrls.get(p.path), title: `${e.id} · ${e.card.name} · ${p.path}` }));
  }
  const only = [e.imageChanged && 'image', e.rotChanged && 'rotated image', e.spriteChanged && 'sprite'].filter(Boolean);
  const rows = e.old
    ? e.diffs.map(k => h('tr', {}, h('th', {}, fieldLabel(k)), h('td', { class: 'was' }, fieldValue(k, e.old[k])), h('td', { class: 'now' }, fieldValue(k, e.card[k]))))
    : CE_FIELDS.filter(k => e.card[k] !== undefined).map(k => h('tr', {}, h('th', {}, fieldLabel(k)), h('td', { colspan: 2 }, fieldValue(k, e.card[k]))));
  // Slike: vodoravna (landscape Hero / Evolution) dobije širi okvir kad se učita.
  for (const img of imgs.querySelectorAll('img')) {
    const mark = () => { if (img.naturalWidth > img.naturalHeight) img.closest('figure')?.classList.add('wide'); };
    if (img.complete) mark(); else img.addEventListener('load', mark, { once: true });
  }
  return h('article', { class: `entry ${e.status}` },
    h('header', {},
      h('span', { class: `badge ${e.status}` }, STATUS_LABEL[e.status]),
      e.staleImage ? h('span', { class: 'badge stale' }, 'Image may be outdated') : null,
      h('code', {}, e.id), h('strong', {}, e.card.name),
      e.card.color ? h('span', { class: `chip c-${e.card.color}` }, e.card.color) : null,
      h('span', { class: 'muted small' }, e.file)),
    h('div', { class: 'entry-body' }, imgs,
      h('div', {},
        rows.length ? h('table', { class: 'diff' }, rows) : null,
        e.old && !e.diffs.length && only.length ? h('p', { class: 'muted' }, `Only the ${only.join(' and ')} changed.`) : null)));
}

// ---------- Pregled ----------

const SORTS = {
  id: ['Code', () => 0],
  cost: ['Cost', (a, b) => (a.cost ?? 99) - (b.cost ?? 99)],
  name: ['Name', (a, b) => a.name.localeCompare(b.name)],
  type: ['Type', (a, b) => TYPES.indexOf(a.type) - TYPES.indexOf(b.type)],
};
const byCode = (a, b) => a.id.localeCompare(b.id, undefined, { numeric: true });

// Brzi filteri (gumbi iznad karata), uz tip i boju: set (prefiks koda) i posebni.
const setOf = c => c.id.split('-')[0];
const SPECIAL = {
  novo: ['New', 'Cards new or changed in the latest version (including look changes under it)'],
  bezSpritea: ['No sprite', 'Heroes and evolutions without a sprite (figurine)'],
  bezFx: ['Needs fx', 'The game cannot read the card text and the card has no confirmed fx yet (Effect tab)'],
  provjeriFx: ['Check fx', 'Cards whose text changed after the fx was written; the fx needs checking'],
};

function specialFilter(name) {
  if (name === 'novo') {
    const last = state.changelog?.entries.at(-1);
    const ids = new Set((last?.cards ?? []).map(c => c.id));
    return c => ids.has(c.id);
  }
  if (name === 'bezSpritea') return c => HERO_TYPES.includes(c.type) && !c.sprite;
  if (name === 'bezFx') return c => fxState(c) === 'missing';
  if (name === 'provjeriFx') return c => c.fxStatus === 'check';
  return () => true;
}

function filtered() {
  const { q, types, colors, sets, specials, sort, since } = state.filter;
  const matches = searchMatcher(q);
  const changed = since ? changesSince(state.changelog, since - 1) : null;
  const extras = specials.map(specialFilter);
  return state.db.cards.filter(c =>
    !c.deleted &&
    (!types.length || types.includes(c.type)) &&
    (!colors.length || colors.includes(c.color)) &&
    (!sets.length || sets.includes(setOf(c))) &&
    (!extras.length || extras.some(fn => fn(c))) &&
    (!changed || changed.has(c.id)) &&
    matches(c))
    .sort((a, b) => SORTS[sort][1](a, b) || byCode(a, b));
}

const plural = (n, one, other) => (n === 1 ? one : other);

// Pretraga karata (pregled i bazen decka): ime, tekst, traitovi i kod. Kod se nađe i bez vodećih nula
// ili crtice: "op1-22", "OP1 22", "op122" i "22" nađu OP1-022.
function searchMatcher(q) {
  const needle = q.trim().toLowerCase();
  if (!needle) return () => true;
  const flat = needle.replace(/[\s-]+/g, '');
  const num = /^0*(\d{1,3})$/.exec(needle);
  return c => {
    if ([c.id, c.name, c.text, ...(c.traits ?? [])].join(' ').toLowerCase().includes(needle)) return true;
    const m = /^(.+)-0*(\d+)$/.exec(c.id.toLowerCase());
    if (!m) return false;
    if (flat === m[1] + m[2]) return true;
    return !!num && m[2] === num[1];
  };
}

const shortDate = iso => (iso ? new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'numeric', year: 'numeric' }) : '');

// Povijest promjena baze (#/history), od najnovije verzije; imena karata otvaraju kartu u pregledu.
function renderHistory() {
  const entries = [...(state.changelog?.entries ?? [])].reverse();
  const cardLink = c => h('button', { class: 'link', onclick: () => showCard(c.id) }, `${c.id} ${c.name}`);
  return h('section', { class: 'panel history' },
    h('h2', {}, 'Change history'),
    entries.length ? null : h('p', { class: 'muted' }, 'No published versions yet.'),
    entries.map(e => {
      const fresh = e.cards.filter(c => c.kind === 'new');
      const rest = e.cards.filter(c => c.kind !== 'new');
      return h('section', { class: 'history-entry', id: `history-v${e.version}` },
        h('h3', {}, `v${e.version}`, h('span', { class: 'muted' }, ` ${shortDate(e.date)} · ${e.cards.length} ${plural(e.cards.length, 'card', 'cards')}`)),
        rest.length ? h('ul', {}, rest.map(c => h('li', {}, cardLink(c), h('span', { class: `change ${c.kind}` }, describeChange(c))))) : null,
        fresh.length ? h('p', { class: 'history-new' }, h('span', { class: 'change new' }, `new (${fresh.length}):`), ' ', fresh.flatMap((c, i) => [i ? ', ' : null, cardLink(c)]).filter(Boolean)) : null);
    }));
}

// Povijest, po želji odmah na zadanoj verziji.
function openHistory(version) {
  state.tab = 'history';
  render();
  if (version) $(`#history-v${version}`)?.scrollIntoView({ block: 'start' });
}

// Karta iz povijesti: pregled s otvorenom kartom (Natrag vraća u povijest).
function showCard(id) {
  state.tab = 'browse';
  state.selected = id;
  render();
}

// Deckovi u kojima je karta (kao heroj ili u decku).
const decksWith = id => state.decks.filter(d => !d.broken && (d.heroes.includes(id) || d.cards?.[id] > 0));

function renderBrowse() {
  const f = state.filter;
  const set = (k, v) => { f[k] = v; renderGrid(); };
  const panel = h('section', { class: 'panel' },
    h('div', { class: 'filters' },
      h('input', { type: 'search', placeholder: 'Search name, text, trait, code…', value: f.q, oninput: e => set('q', e.target.value) }),
      h('select', { 'aria-label': 'Sort', onchange: e => set('sort', e.target.value) }, Object.entries(SORTS).map(([k, [label]]) => h('option', { value: k, selected: f.sort === k }, `Sort: ${label}`))),
      state.changelog?.entries.length > 1
        ? h('select', { 'aria-label': 'Changes', onchange: e => set('since', Number(e.target.value)) },
            h('option', { value: 0 }, 'All cards'),
            [...state.changelog.entries].reverse().map(e => h('option', { value: e.version, selected: f.since === e.version }, `Changed since v${e.version} (${shortDate(e.date)})`)))
        : null),
    renderQuickFilters(),
    h('p', { id: 'grid-count', class: 'muted small' }),
    h('div', { id: 'grid', class: 'grid' }),
    h('div', { id: 'detail' }));
  queueMicrotask(() => { renderGrid(); renderDetail(); });
  return panel;
}

// Gumbi: tip, boja, set, posebni. Klik uključi ili isključi; unutar skupine "ili" (Action + Equipment),
// između skupina "i" (Heroji i crvena). Očisti sve vrati. Maknute karte se u pregledu ne prikazuju.
// Na računalu je red uvijek jedan: skupine koje ne stanu (npr. dok je otvoren detalj karte) idu, od kraja,
// u izbornik "Filters"; broj na njemu kaže koliko je filtera uključeno unutra.
function renderQuickFilters() {
  const f = state.filter;
  const on = (k, v) => f[k].includes(v);
  const toggle = (k, v) => { f[k] = on(k, v) ? f[k].filter(x => x !== v) : [...f[k], v]; render(); };
  const chip = (k, v, label, title) => h('button', { type: 'button', class: `qf${on(k, v) ? ' active' : ''}`, title: title ?? '', 'aria-pressed': String(on(k, v)), onclick: () => toggle(k, v) }, label);
  const sets = [...new Set(state.db.cards.filter(c => c.type !== 'Stage' && c.type !== 'Core').map(setOf))].sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  // Core se nudi tek kad u bazi ima coreova.
  const types = TYPES.filter(t => t !== 'Core' || state.db.cards.some(c => c.type === 'Core'));
  const any = f.types.length || f.colors.length || f.sets.length || f.specials.length || f.since || f.q;
  const group = (cls, active, ...kids) => Object.assign(h('div', { class: `qf-group${cls ? ` ${cls}` : ''}` }, ...kids), { activeCount: active });
  const groups = [
    group('', f.types.length, types.map(t => chip('types', t, t === 'Hero' ? 'Heroes' : t))),
    group('', f.colors.length, COLOR_NAMES.map(c => h('button', {
      type: 'button', class: `qf-color c-${c}${on('colors', c) ? ' active' : ''}`, title: c, 'aria-label': c, 'aria-pressed': String(on('colors', c)), onclick: () => toggle('colors', c),
    }))),
    sets.length > 1 ? group('', f.sets.length, sets.map(x => chip('sets', x, x, `Set ${x}`))) : null,
    group('qf-specials', f.specials.length,
      Object.entries(SPECIAL).map(([k, [label, title]]) => chip('specials', k, label, title))),
  ].filter(Boolean);
  const panel = h('div', { class: 'qf-panel', hidden: !state.qfOpen });
  const moreBtn = h('button', { type: 'button', class: 'qf qf-more-btn', 'aria-expanded': String(!!state.qfOpen), onclick: () => {
    state.qfOpen = !state.qfOpen;
    panel.hidden = !state.qfOpen;
    moreBtn.setAttribute('aria-expanded', String(state.qfOpen));
  } });
  const more = h('div', { class: 'qf-more', hidden: true }, moreBtn, panel);
  const clear = any ? h('button', { type: 'button', class: 'qf qf-clear', onclick: () => {
    Object.assign(f, { q: '', types: [], colors: [], sets: [], specials: [], since: 0 });
    render();
  } }, 'Clear') : null;
  const row = h('div', { class: 'quick' }, groups, more, clear);
  const layout = () => {
    for (const g of groups) row.insertBefore(g, more);
    more.hidden = true;
    if (matchMedia('(max-width: 760px)').matches) return; // na mobitelu se red smije prelomiti
    const fits = () => row.scrollWidth <= row.clientWidth + 1;
    if (fits()) return;
    more.hidden = false;
    const inRow = [...groups];
    while (!fits() && inRow.length) panel.prepend(inRow.pop());
    const n = groups.filter(g => !inRow.includes(g)).reduce((s, g) => s + g.activeCount, 0);
    moreBtn.replaceChildren(...['Filters', n ? h('span', { class: 'qf-count' }, n) : null, h('span', { 'aria-hidden': 'true' }, '▾')].filter(Boolean));
  };
  new ResizeObserver(layout).observe(row);
  return row;
}

function renderGrid() {
  const grid = $('#grid');
  if (!grid) return;
  const cards = filtered();
  if (!state.db.cards.length) {
    grid.replaceChildren(h('p', { class: 'muted' }, 'The database is empty. Run Import, then Publish.'));
    return;
  }
  grid.replaceChildren(...(cards.length ? cards.map(tile) : [h('p', { class: 'muted' }, 'No cards match the filter.')]));
  const all = state.db.cards.filter(c => !c.deleted).length;
  $('#grid-count')?.replaceChildren(cards.length === all ? `${all} ${plural(all, 'card', 'cards')}` : `${cards.length} of ${all} cards`);
}

function tile(c) {
  return h('button', { class: `tile${c.landscape ? ' wide' : ''}${c.deleted ? ' deleted' : ''}${state.selected === c.id ? ' selected' : ''}`, onclick: () => openCard(c.id) },
    h('div', { class: 'art' }, cardImg(c)),
    h('div', { class: 'meta' },
      h('span', { class: `dot c-${c.color ?? 'none'}` }),
      h('span', { class: 'name' }, c.name),
      h('span', { class: 'sub' }, h('span', {}, c.id), h('span', {}, c.type), c.cost !== undefined ? h('span', { class: 'cost', title: 'Cost' }, c.cost) : null)));
}

// Iz mreže u kartu je jedan korak; prelazak s karte na kartu ne dodaje nove, pa Natrag vodi ravno u mrežu.
function openCard(id) {
  if (state.selected) replaceNext = true;
  else cardPushed = true;
  state.selected = id;
  renderGrid();
  renderDetail();
  syncHash();
}

function closeCard() {
  if (cardPushed) {
    history.back();
    return;
  }
  state.selected = null;
  renderGrid();
  renderDetail();
  syncHash();
}

// Detalj karte: General (slika, polja, povijest), Effect (fx za igru) i, za heroje i evolucije, Look (kuglica, figurina).
// Kartice dijele izmjene i Save; prebacivanje ih ne crta iznova, pa nespremljeni odabir ostaje.
function renderDetail() {
  const box = $('#detail');
  if (!box) return;
  const c = state.db.cards.find(x => x.id === state.selected);
  // Dok je detalj otvoren, mreža karata se suzi lijevo od njega (CSS), pa se odabrana karta i dalje vidi.
  document.body.classList.toggle('detail-open', !!c);
  if (!c) { box.replaceChildren(); box.className = ''; return; }
  box.className = 'detail';
  requestAnimationFrame(() => $('.tile.selected')?.scrollIntoView({ block: 'nearest' }));
  const edits = {};
  const canEdit = state.store.canImport;
  const save = () => h('button', { class: 'primary', type: 'submit' }, 'Save');
  const form = (...kids) => h('form', { class: 'editor', onsubmit: e => { e.preventDefault(); guard(() => saveEdits(c.id, edits)); } }, ...kids);
  const rows = ['type', 'color', 'cost', 'evo', 'hero', 'stats', 'wt', 'bonus', 'values', 'traits', 'text', 'terrain', 'figure', 'heroSfx', 'rev', 'imageHash']
    .filter(k => c[k] !== undefined)
    .map(k => h('tr', {}, h('th', {}, k), h('td', {}, fmt(c[k]))));
  // Povijest ove karte; verzija otvara cijelu povijest na toj verziji.
  const changes = (state.changelog?.entries ?? []).flatMap(e => e.cards.filter(x => x.id === c.id).map(x => ({ v: e.version, x }))).reverse();
  if (changes.length) {
    rows.push(h('tr', {}, h('th', {}, 'changes'), h('td', {}, h('ul', { class: 'card-changes' }, changes.map(({ v, x }) =>
      h('li', {}, h('button', { class: 'link', title: `v${v} in Change history`, onclick: () => openHistory(v) }, `v${v}`), ' ', h('span', { class: `change ${x.kind}` }, describeChange(x))))))));
  }
  const inDecks = decksWith(c.id);
  if (inDecks.length) {
    rows.push(h('tr', {}, h('th', {}, 'in decks'), h('td', {}, inDecks.flatMap((d, i) => [i ? ', ' : null,
      h('button', { class: 'link', onclick: () => { if (confirmDiscard()) { state.tab = 'decks'; guard(() => openDeck(d.slug)); } } }, d.name)]).filter(Boolean))));
  }
  const general = h('div', { class: `detail-body${c.landscape ? ' wide' : ''}` },
    h('button', { class: 'big', title: 'Full screen', onclick: () => { const list = filtered(); openViewer((list.includes(c) ? list : [c]).map(x => ({ card: x })), list.includes(c) ? list.indexOf(c) : 0); } },
      cardImg(c, { alt: c.name, full: true }), h('span', { class: 'zoom', 'aria-hidden': 'true' }, icon('zoom'))),
    h('div', {}, h('table', { class: 'fields' }, rows),
      canEdit ? form(
        h('h3', {}, 'App fields'),
        c.type === 'Stage' ? h('label', { class: 'field' }, h('span', {}, 'Terrain'),
          h('select', { onchange: e => { edits.terrain = e.target.value || undefined; } },
            h('option', { value: '' }, '– not set –'),
            TERRAINS.map(t => h('option', { value: t, selected: c.terrain === t }, t === 'None' ? 'None (no terrain)' : t)))) : null,
        h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: !!c.deleted, onchange: e => { edits.deleted = e.target.checked; } }), 'Deleted – the deck builder no longer offers it'),
        save()) : null));
  const panes = { general };
  if (c.text?.trim() || c.fx) panes.effect = effectPane(c, canEdit ? edits : null, form);
  if (HERO_TYPES.includes(c.type)) panes.look = lookPane(c, canEdit ? edits : null, form);
  if (!panes[state.detailTab]) state.detailTab = 'general';
  const showPane = k => { for (const [pk, el] of Object.entries(panes)) el.hidden = pk !== k; };
  showPane(state.detailTab);
  // Kartice su okomita traka uz lijevi rub panela, cijelom visinom; sadržaj desno se lista sam.
  const labels = { general: 'General', effect: 'Effect', look: 'Look' };
  const tabs = Object.keys(panes).length > 1 ? h('nav', { class: 'detail-rail', role: 'tablist', 'aria-orientation': 'vertical' }, Object.keys(panes).map(k => [k, labels[k]]).map(([k, label]) =>
    h('button', { type: 'button', role: 'tab', class: state.detailTab === k ? 'active' : '', 'aria-selected': String(state.detailTab === k), onclick: e => {
      state.detailTab = k;
      showPane(k);
      for (const b of e.currentTarget.parentElement.children) { const on = b === e.currentTarget; b.classList.toggle('active', on); b.setAttribute('aria-selected', String(on)); }
    } }, h('span', {}, label)))) : null;
  box.className = tabs ? 'detail has-rail' : 'detail';
  const content = h('div', { class: 'detail-content' },
    h('div', { class: 'detail-head' }, h('div', {}, h('code', {}, c.id), h('h2', {}, c.name)), h('button', { class: 'ghost', onclick: closeCard }, 'Close')),
    ...Object.values(panes));
  box.replaceChildren(...[tabs, content].filter(Boolean));
}

// Stanje efekta karte za igru (kartica Effect, filter Needs fx): written = potvrđen fx, check = tekst se promijenio
// nakon fx-a, read = igra sama čita tekst, missing = igra ne razumije tekst a fx-a nema, unknown = nema izvještaja
// igre (data/fx-proposals.json, piše ga game/tools/fx_proposals.gd), none = karta nema teksta.
function fxState(c) {
  if (c.fx) return c.fxStatus === 'check' ? 'check' : 'written';
  if (!c.text?.trim()) return 'none';
  const p = state.fxProposals?.cards?.[c.id];
  if (!p) return 'unknown';
  return p.unparsed?.length ? 'missing' : 'read';
}

const FX_STATES = {
  written: ['ok', 'Confirmed fx', 'The game uses the fx below.'],
  read: ['ok', 'Read from the text', 'The game understands the card text; no fx needed.'],
  missing: ['bad', 'Needs fx', 'The game does not understand part of the text. Confirm the proposal or write an fx.'],
  check: ['warn', 'Check fx', 'The card text changed after the fx was written. Check it and confirm again.'],
  unknown: ['warn', 'Not checked yet', 'No report from the game for this card yet; ask Claude Code to run game/tools/fx_proposals.gd.'],
  none: ['', 'No text', 'The card has no text, so it has no effect.'],
};

// Kartica Effect: tekst karte, kako ga igra čita, prijedlog i fx koji se potvrđuje (GDD 14).
function effectPane(c, edits, form) {
  const p = state.fxProposals?.cards?.[c.id] ?? null;
  const st = fxState(c);
  const [tone, label, help] = FX_STATES[st];
  const report = state.fxProposals;
  const block = (title, body) => h('section', { class: 'fx-block' }, h('h3', {}, title), body);
  const code = text => h('pre', { class: 'fx-code' }, text || '–');
  const list = items => h('ul', { class: 'fx-list' }, items.map(s => h('li', {}, s)));
  const parts = [
    h('p', { class: `fx-state ${tone}` }, h('strong', {}, label), h('span', {}, help)),
    report && report.version !== state.db.version
      ? h('p', { class: 'muted small' }, `The game's report is for v${report.version}, the cards are v${state.db.version}; ask Claude Code to run it again.`) : null,
    block('Card text', h('p', { class: 'fx-text' }, c.text || '–')),
    p?.read ? block('The game reads', code(p.read)) : null,
    p?.unparsed?.length ? block('Not understood', list(p.unparsed)) : null,
    p?.fxErrors?.length ? block('Errors in the fx', list(p.fxErrors)) : null,
  ];
  if (!edits) return h('div', { class: 'editor fx-pane' }, ...parts, c.fx ? block('fx', code(c.fx)) : null);
  // Bez fx-a, a igra ne razumije tekst: prijedlog je već upisan, Confirm ga sprema.
  const start = c.fx ?? (st === 'missing' ? p?.proposal ?? '' : '');
  const area = h('textarea', { class: 'fx-edit', rows: 4, placeholder: 'One effect per line, e.g. POSTROLL ONCE OPTIONAL: MOVE SELF 2' }, start);
  area.spellcheck = false;
  const take = () => {
    const t = area.value.trim();
    edits.fx = t || undefined;
    edits.fxStatus = t ? 'ok' : undefined;
  };
  const useProposal = c.fx && p?.proposal && p.proposal !== c.fx
    ? h('button', { type: 'button', class: 'ghost', onclick: () => { area.value = p.proposal; } }, 'Use the proposal') : null;
  return form(...parts,
    p?.proposal && p.proposal !== p.read && p.proposal !== start ? block('Proposal', code(p.proposal)) : null,
    block('fx for the game', area),
    h('p', { class: 'muted small' }, 'Empty: the game reads the text itself. One effect per line; the words are in game/docs/fx-keywords.md.'),
    h('div', { class: 'fx-actions' }, useProposal,
      h('button', { class: 'primary', type: 'submit', onclick: take }, st === 'written' || st === 'read' ? 'Save' : 'Confirm')));
}

// Red boja: boje igre, posebni gumb (boja heroja / zadani akcent) i bilo koja boja.
function colorRow(label, get, set, special, rows) {
  const input = h('input', { type: 'color', 'aria-label': `${label}: any color`, oninput: e => set(e.target.value.toLowerCase()) });
  const extra = h('button', { type: 'button', class: 'ghost small-btn', onclick: () => set(special.value()) }, special.label);
  const el = h('div', { class: 'bk-row' }, h('span', { class: 'bk-label' }, label), h('div', { class: 'bk-colors' },
    Object.entries(BALL_COLORS).map(([name, hex]) => h('button', { type: 'button', class: 'bk-swatch', style: `--sw:${hex}`, 'data-color': hex, title: name, 'aria-label': `${label}: ${name}`, onclick: () => set(hex) })),
    extra, h('label', { class: 'bk-custom', title: 'Any color' }, input)));
  rows.push(() => {
    const v = get();
    el.querySelectorAll('.bk-swatch').forEach(s => s.classList.toggle('active', s.dataset.color === v));
    extra.classList.toggle('active', special.active());
    input.value = v ?? DEFAULT_ACCENT;
  });
  return el;
}

// Kartica Look: kuglica u igri (gornja polovica u boji tijela, donja u akcentu; tim je prsten ispod) i težina
// za heroje, figurina (sprite) za heroje i evolucije. Spremanje boje makne stara TTS polja bakuganColor*.
function lookPane(c, edits, form) {
  const parts = [];
  if (c.type === 'Hero') {
    let { body, accent } = ballColors(c);
    const ball = h('div', { class: 'ball-preview', 'aria-hidden': 'true' });
    const rows = [];
    const paint = () => {
      ball.style.setProperty('--top', body);
      ball.style.setProperty('--bottom', accent ?? DEFAULT_ACCENT);
      for (const sync of rows) sync();
    };
    const side = edits ? h('div', { class: 'bk-side' },
      colorRow('Body', () => body, v => { body = v; edits.ballColor = v; edits.bakuganColor = undefined; paint(); },
        { label: 'Hero color', value: () => heroDefaultColor(c), active: () => body === heroDefaultColor(c) }, rows),
      colorRow('Accent', () => accent, v => { accent = v; edits.ballColor2 = v ?? undefined; edits.bakuganColor2 = undefined; paint(); },
        { label: 'Default', value: () => null, active: () => accent === null }, rows),
      h('label', { class: 'field' }, h('span', {}, 'Weight (WT)'), h('input', { type: 'number', min: 1, step: 1, value: c.wt ?? '',
        oninput: e => { if (e.target.value === '') delete edits.wt; else edits.wt = Number(e.target.value); } })),
      h('p', { class: 'muted small' }, 'WT 1–3 fit one hex, WT 4 and up cover seven; heavier balls go less far and push harder.'))
      : h('p', { class: 'muted' }, `WT ${c.wt ?? 2}`);
    parts.push(h('section', { class: 'bk-part' }, h('h3', {}, 'Ball'), h('div', { class: 'look-ball' }, ball, side)));
    paint();
  }
  let figure;
  if (c.sprite) {
    const img = h('img', { class: 'sprite-img', alt: `${c.name} sprite` });
    state.store.dataUrl(c.sprite).then(u => { if (u) img.src = u; });
    figure = h('button', { type: 'button', class: 'sprite-btn', title: 'Full screen',
      onclick: () => state.store.dataUrl(c.sprite).then(u => u && openViewer([{ url: u, title: `${c.id} · ${c.name} · sprite` }])) }, img);
  } else {
    figure = h('p', { class: 'muted small' }, `No sprite yet. It comes through the export as "${c.name} Sprite.png".`);
  }
  parts.push(h('section', { class: 'bk-part' }, h('h3', {}, 'Figurine'), figure,
    h('p', { class: 'muted small' }, 'Shown standing on the ball when it opens.')));
  return edits && c.type === 'Hero'
    ? form(...parts, h('div', { class: 'fx-actions' }, h('button', { class: 'primary', type: 'submit' }, 'Save')))
    : h('div', { class: 'editor' }, ...parts);
}

// ---------- Deckovi ----------

function newDeck() {
  return { ...emptyDeck(''), slug: null, rev: 0, dirty: false };
}

function confirmDiscard() {
  return !state.deck?.dirty || window.confirm('The deck has unsaved changes. Discard them?');
}

async function openDeck(slug) {
  const d = await state.store.readDeck(slug);
  state.deck = { slug: d.slug, name: d.name, heroes: d.heroes ?? [], cards: { ...d.cards }, rev: d.rev ?? 0, catalogVersion: d.catalogVersion, dirty: false };
  state.deckView = 'deck';
}

async function saveDeck() {
  const d = state.deck;
  const name = d.name.trim();
  if (!name) throw new Error('Enter a deck name.');
  // "new" (i stari "novi") je adresa praznog decka (#/decks/new), pa deck tog imena dobije dodatak.
  const raw = slugify(name);
  const slug = ['new', 'novi'].includes(raw) ? `${raw}-deck` : raw;
  if (!slug) throw new Error('The deck name needs at least one letter or digit.');
  let base = d.slug === slug ? d.rev : 0;
  if (d.slug !== slug) {
    const other = state.decks.find(x => x.slug === slug);
    if (other) {
      if (!window.confirm(`Deck "${other.name}" already exists. Overwrite it?`)) return;
      base = other.rev;
    }
  }
  let saved;
  try {
    saved = await state.store.saveDeck(slug, { name, heroes: d.heroes, cards: d.cards, catalogVersion: state.db.version }, base);
  } catch (e) {
    if (e instanceof ConflictError) throw new Error('The deck was saved on another device in the meantime. Open it again or save it under a different name.');
    throw e;
  }
  if (d.slug && d.slug !== slug) await state.store.deleteDeck(d.slug, d.rev).catch(() => {});
  state.deck = { ...d, slug, name, rev: saved.rev, catalogVersion: state.db.version, dirty: false };
  replaceNext = true;
  state.decks = await state.store.listDecks();
  toast(`Saved: ${name}`);
}

async function deleteDeck() {
  const d = state.deck;
  if (!d.slug || !window.confirm(`Delete deck "${d.name}"?`)) return;
  try {
    await state.store.deleteDeck(d.slug, d.rev);
  } catch (e) {
    if (e instanceof ConflictError) throw new Error('The deck was changed on another device in the meantime. Open it again before deleting it.');
    throw e;
  }
  state.decks = await state.store.listDecks();
  state.deck = null;
  replaceNext = true;
  toast(`Deleted: ${d.name}`);
}

function changeDeck(fn) {
  const d = state.deck;
  d.undo ??= [];
  d.undo.push(JSON.stringify({ heroes: d.heroes, cards: d.cards }));
  if (d.undo.length > 100) d.undo.shift();
  fn(d);
  d.dirty = true;
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
  return state.deck ? renderDeckEditor() : h('div', { class: 'deck-empty' },
    h('h2', {}, 'Build a deck'),
    h('p', { class: 'muted' }, 'Open a saved deck or make a new one: pick 3 heroes, then add cards of their colors up to 40.'));
}

// Lijevi stupac na kartici Decks: novi deck, spremljeni deckovi (kriške heroja, ime, stanje, broj karata) i deck kod.
function renderDeckList() {
  const n = state.decks.length;
  const newDeckBtn = h('button', { class: 'primary deck-new', onclick: () => { if (confirmDiscard()) { state.deck = newDeck(); state.deckView = 'pool'; render(); } } },
    h('span', { 'aria-hidden': 'true' }, '+'), 'New deck');
  return h('section', { class: 'deck-list' },
    h('div', { class: 'deck-list-head' }, h('h2', {}, 'My decks'), n ? h('span', { class: 'deck-list-n' }, n) : null),
    newDeckBtn,
    n
      ? h('ul', {}, state.decks.map(x => h('li', {},
          h('button', {
            class: `deck-item${state.deck?.slug === x.slug ? ' active' : ''}`,
            onclick: () => { if (confirmDiscard()) guard(() => openDeck(x.slug)); },
          },
            deckHeroes(x),
            h('span', { class: 'deck-item-text' },
              h('span', { class: 'deck-item-name' }, x.name),
              h('span', { class: 'deck-item-sub' }, x.broken ? 'broken file' : `${x.heroes.map(id => cardById(id)?.name ?? id).join(', ') || 'no heroes'}`),
              x.broken ? null : deckFlags(x)),
            h('span', { class: `deck-item-count${!x.broken && x.count === DECK_SIZE ? ' full' : ''}` }, x.broken ? '' : `${x.count}/${DECK_SIZE}`)))))
      : h('p', { class: 'deck-list-empty' }, 'No saved decks yet. Start a new one or load a deck code.'),
    h('details', { class: 'code-import' },
      h('summary', {}, 'Load deck code'),
      h('form', { onsubmit: e => { e.preventDefault(); importCode(e.target.elements.code.value); } },
        h('input', { name: 'code', placeholder: 'EB1|v1|…', autocomplete: 'off', spellcheck: false, 'aria-label': 'Deck code' }),
        h('button', { type: 'submit', class: 'ghost' }, 'Load'))));
}

// Tri kose kriške s crtežom heroja iz decka (prazne dok heroj nije odabran), rub u boji heroja.
function deckHeroes(x) {
  return h('span', { class: 'deck-heroes', 'aria-hidden': 'true' }, [0, 1, 2].map(i => {
    const c = cardById(x.heroes?.[i]);
    const art = h('span', { class: `slice-art${c?.landscape ? ' wide-art' : ''}` });
    if (c) imageFor(c, true).then(u => { if (u) art.style.backgroundImage = `url("${u}")`; });
    return h('span', { class: `deck-hero${c ? ` c-edge-${c.color}` : ' empty'}` }, art);
  }));
}

// Karte iz decka promijenjene od kad je spremljen (prema povijesti promjena).
function changedInDeck(deck) {
  if (deck.catalogVersion === undefined || deck.catalogVersion >= state.db.version || !state.changelog) return [];
  return deckChanges(deck, changesSince(state.changelog, deck.catalogVersion));
}

// Na popisu: spreman ili ne, i koliko se karata promijenilo od spremanja.
function deckFlags(x) {
  const ready = checkDeck(state.db, x).ready;
  const changed = changedInDeck(x).length;
  return h('span', { class: 'deck-item-flags' },
    h('span', { class: ready ? 'ok' : 'bad' }, ready ? 'Ready' : 'Not ready'),
    changed ? h('span', { class: 'changed' }, `${changed} ${plural(changed, 'card changed', 'cards changed')}`) : null);
}

// U otvorenom decku: što se promijenilo od spremanja; nestane kad se deck ponovno spremi.
function renderDeckChanges() {
  const list = changedInDeck(state.deck);
  if (!list.length) return null;
  const cards = list.map(x => cardById(x.id)).filter(Boolean);
  return h('div', { class: 'deck-changes' },
    h('strong', {}, `Changed since the deck was saved (database v${state.deck.catalogVersion}):`),
    h('ul', {}, list.map(x => {
      const c = cardById(x.id);
      const what = x.changes.map(ch => `v${ch.version}: ${describeChange(ch)}`).join('; ');
      return h('li', {}, c ? h('button', { class: 'link', onclick: () => openViewer(cards.map(k => ({ card: k })), cards.indexOf(c)) }, c.name) : x.id, h('span', { class: 'muted' }, ` ${what}`));
    })),
    h('span', { class: 'muted small' }, 'Save the deck to clear this.'));
}

// Poništi: stanje heroja i karata prije svake promjene decka (ime ima svoj Ctrl+Z u polju).
function undoDeck() {
  const d = state.deck;
  const prev = d?.undo?.pop();
  if (!prev) return;
  Object.assign(d, JSON.parse(prev), { dirty: true });
  refreshDeck();
}

function duplicateDeck() {
  const d = state.deck;
  state.deck = { ...newDeck(), name: `${d.name.trim() || 'Deck'} (copy)`, heroes: [...d.heroes], cards: { ...d.cards }, catalogVersion: d.catalogVersion, dirty: true };
  state.deckView = 'deck';
  render();
  toast('Copy made. Rename it and save it.');
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
  state.deck = { ...newDeck(), heroes: parsed.heroes, cards: parsed.cards, catalogVersion: parsed.catalogVersion, dirty: true };
  state.deckView = 'deck';
  if (parsed.catalogVersion > state.db.version) toast(`The code is from a newer database (v${parsed.catalogVersion}, here v${state.db.version}). Some cards may be missing.`, 'warn');
  render();
}

function renderDeckEditor() {
  const d = state.deck;
  return h('div', { class: `deck-editor view-${state.deckView}` },
    h('div', { class: 'deck-head' },
      h('input', { class: 'deck-name', placeholder: 'Deck name', value: d.name, 'aria-label': 'Deck name', oninput: e => { d.name = e.target.value; d.dirty = true; renderDeckStatus(); } }),
      h('div', { id: 'deck-status' }),
      h('div', { class: 'deck-actions' },
        h('button', { class: 'publish', onclick: () => guard(saveDeck) }, 'Save'),
        h('button', { class: 'ghost', onclick: copyCode }, 'Copy code'),
        h('button', { id: 'undo-btn', class: 'ghost', title: 'Undo the last change to heroes or cards (Ctrl+Z)', onclick: undoDeck }, 'Undo'),
        h('button', { class: 'ghost', title: 'Make a copy of this deck under a new name', onclick: duplicateDeck }, 'Duplicate'),
        d.slug ? h('button', { class: 'ghost', onclick: () => guard(deleteDeck) }, 'Delete') : null)),
    h('div', { id: 'deck-code' }),
    renderDeckChanges(),
    h('div', { id: 'deck-heroes', class: 'hero-slots' }),
    h('div', { class: 'view-switch', role: 'tablist' },
      h('button', { id: 'sw-pool', role: 'tab', onclick: () => setDeckView('pool') }, 'Pool'),
      h('button', { id: 'sw-deck', role: 'tab', onclick: () => setDeckView('deck') }, 'Deck')),
    h('div', { class: 'deck-cols' },
      h('section', { class: 'pool-pane' },
        h('div', { class: 'filters' },
          h('input', { type: 'search', placeholder: 'Search the pool…', value: state.pool.q, oninput: e => { state.pool.q = e.target.value; renderPool(); } }),
          h('select', { onchange: e => { state.pool.type = e.target.value; renderPool(); } }, h('option', { value: '' }, 'All types'), DECK_TYPES.map(t => h('option', { value: t, selected: state.pool.type === t }, t))),
          h('select', { id: 'pool-color', onchange: e => { state.pool.color = e.target.value; renderPool(); } }),
          h('select', { id: 'pool-set', 'aria-label': 'Set', onchange: e => { state.pool.set = e.target.value; renderPool(); } }),
          h('select', { id: 'pool-trait', 'aria-label': 'Trait', onchange: e => { state.pool.trait = e.target.value; renderPool(); } })),
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
  syncHash();
}

function refreshDeck() {
  if (!state.deck || !$('.deck-editor')) return;
  renderHeroes();
  renderPool();
  renderDeckPanel();
  renderDeckStatus();
  renderSwitch();
  updateStrip();
  const undo = $('#undo-btn');
  if (undo) undo.disabled = !state.deck.undo?.length;
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
    h('span', {}, r.ready ? 'Ready to play' : 'Not ready'),
    state.deck.dirty ? h('span', { class: 'unsaved' }, 'unsaved') : null);
}

// Tri mjesta za heroje: odabrani heroj je ploča sa sličicom karte (klik je prikaže preko cijelog ekrana, × ga makne),
// prazno mjesto nudi izbornik ili klik na heroja u traci na vrhu.
function renderHeroes() {
  const box = $('#deck-heroes');
  const d = state.deck;
  const taken = new Set(d.heroes);
  const free = heroCards(state.db).filter(c => !taken.has(c.id));
  const heroes = d.heroes.map(cardById).filter(Boolean);
  const slots = [0, 1, 2].map(i => {
    const hero = cardById(d.heroes[i]);
    if (hero) {
      const st = hero.stats ?? {};
      return h('div', { class: `hero-slot filled c-edge-${hero.color}${hero.landscape ? ' wide' : ''}` },
        h('button', { class: 'hero-panel', title: `Full screen: ${hero.name}`, onclick: () => openViewer(heroes.map(x => ({ card: x })), heroes.indexOf(hero)) },
          cardImg(hero, { alt: hero.name }),
          h('span', { class: 'hero-text' },
            h('span', { class: 'hero-name' }, hero.name),
            h('span', { class: 'hero-stats' }, [['HP', st.hp], ['DMG', st.dmg], ['PWR', st.pwr], ['RNG', st.rng]].filter(([, v]) => v !== undefined).map(([k, v]) => h('span', {}, h('b', {}, v), ` ${k}`))))),
        h('button', { class: 'hero-remove', title: `Remove ${hero.name}`, 'aria-label': `Remove ${hero.name}`, onclick: () => changeDeck(x => { x.heroes = x.heroes.filter(id => id !== hero.id); }) }, icon('close')));
    }
    return h('label', { class: 'hero-slot empty' },
      h('span', { class: 'hero-empty-title' }, h('b', { 'aria-hidden': 'true' }, '+'), `Hero ${i + 1}`),
      h('span', { class: 'muted small' }, 'Click a hero in the banner, or choose:'),
      h('select', { onchange: e => { if (e.target.value) changeDeck(x => { x.heroes = [...x.heroes, e.target.value]; }); } },
        h('option', { value: '' }, 'Choose a hero'),
        free.map(c => h('option', { value: c.id }, `${c.name} (${c.color})`))));
  });
  box.replaceChildren(...slots);
}

// Klik na heroja u traci na kartici Decks: heroj ide na prvo slobodno mjesto (bez otvorenog decka počne novi),
// a heroj koji je već u decku se makne.
function pickHeroFromStrip(c) {
  if (!state.deck) {
    state.deck = newDeck();
    state.deckView = 'pool';
    state.deck.heroes = [c.id];
    state.deck.dirty = true;
    render();
    return;
  }
  const d = state.deck;
  if (d.heroes.includes(c.id)) { changeDeck(x => { x.heroes = x.heroes.filter(id => id !== c.id); }); return; }
  if (d.heroes.length >= 3) { toast('The deck already has 3 heroes. Remove one first.', 'warn'); return; }
  changeDeck(x => { x.heroes = [...x.heroes, c.id]; });
}

function renderPool() {
  const box = $('#pool');
  if (!box) return;
  const d = state.deck;
  const all = deckPool(state.db, d.heroes);
  const colorSel = $('#pool-color');
  const colors = [...new Set(all.map(c => c.color))];
  if (state.pool.color && !colors.includes(state.pool.color)) state.pool.color = '';
  colorSel.replaceChildren(h('option', { value: '' }, 'All hero colors'), ...colors.map(c => h('option', { value: c, selected: state.pool.color === c }, c)));
  // Setovi bazena (OP1, JO1, …); izbornik se vidi tek kad ih je više.
  const sets = [...new Set(all.map(setOf))].sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  if (state.pool.set && !sets.includes(state.pool.set)) state.pool.set = '';
  const setSel = $('#pool-set');
  if (setSel) {
    setSel.hidden = sets.length < 2;
    setSel.replaceChildren(h('option', { value: '' }, 'All sets'), ...sets.map(x => h('option', { value: x, selected: state.pool.set === x }, `${x} (${all.filter(c => setOf(c) === x).length})`)));
  }
  // Traitovi bazena, najčešći prvi (npr. {Luffy} karte za heroja ili evoluciju koja ih poziva).
  const traits = traitCounts(all.map(c => [c, 1]));
  if (state.pool.trait && !traits.some(([t]) => t === state.pool.trait)) state.pool.trait = '';
  $('#pool-trait')?.replaceChildren(h('option', { value: '' }, 'All traits'), ...traits.map(([t, n]) => h('option', { value: t, selected: state.pool.trait === t }, `${t} (${n})`)));
  if (!d.heroes.length) {
    box.replaceChildren(h('p', { class: 'muted' }, 'Pick heroes, and cards of their colors show up here.'));
    return;
  }
  const { q, type, color, set, trait } = state.pool;
  const matches = searchMatcher(q);
  const cards = all
    .filter(c => (!type || c.type === type) && (!color || c.color === color) && (!set || setOf(c) === set) && (!trait || (c.traits ?? []).includes(trait)) && matches(c))
    .sort((a, b) => a.cost - b.cost || a.name.localeCompare(b.name));
  box.replaceChildren(...(cards.length ? cards.map(c => poolCard(c, cards)) : [h('p', { class: 'muted' }, 'No cards match the filter.')]));
}

// [[trait, broj], ...] od najčešćeg; entries su [karta, kopija].
function traitCounts(entries) {
  const counts = new Map();
  for (const [c, n] of entries) for (const t of c?.traits ?? []) counts.set(t, (counts.get(t) ?? 0) + n);
  return [...counts].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
}

// Traitovi u decku (s kopijama); klik filtrira bazen po tom traitu.
function deckTraits(d) {
  const list = traitCounts(Object.entries(d.cards).map(([id, n]) => [cardById(id), n]));
  if (!list.length) return null;
  return h('figure', { class: 'traits' },
    h('figcaption', {}, 'Traits in the deck'),
    h('div', { class: 'trait-chips' }, list.map(([t, n]) => h('button', {
      class: `trait-chip${state.pool.trait === t ? ' active' : ''}`,
      title: `Pool: only cards with the trait ${t}`,
      onclick: () => { state.pool.trait = state.pool.trait === t ? '' : t; renderPool(); renderDeckPanel(); if (state.pool.trait) setDeckView('pool'); },
    }, t, h('span', {}, n)))));
}

function poolCard(c, list) {
  const n = state.deck.cards[c.id] ?? 0;
  const max = LIMITS[c.type];
  return h('div', { class: `pool-card${c.landscape ? ' wide' : ''}${n ? ' in-deck' : ''}${n >= max ? ' maxed' : ''}` },
    h('div', { class: 'pool-art-wrap' },
      // lijevi klik doda kopiju, desni makne jednu
      h('button', { class: 'pool-art', title: `${c.name}: click adds one, right-click removes one`, onclick: () => { if (n < max) addCard(c.id, 1); },
        oncontextmenu: e => { e.preventDefault(); if (n) addCard(c.id, -1); } }, cardImg(c, { alt: c.name }),
        n ? h('span', { class: 'pool-count' }, `${n}/${max}`) : null),
      zoomButton(c, list),
      h('span', { class: 'stepper' },
        h('button', { class: 'step', title: 'Remove one', 'aria-label': `Remove one ${c.name}`, disabled: !n, onclick: () => addCard(c.id, -1) }, '−'),
        h('button', { class: 'step', title: 'Add one', 'aria-label': `Add one ${c.name}`, disabled: n >= max, onclick: () => addCard(c.id, 1) }, '+'))),
    h('span', { class: 'pool-name', title: c.name }, c.name));
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
  const deckCards = groups.flatMap(([, list]) => list.map(x => x.c));

  fill(box,
    h('div', { class: 'deck-count' },
      h('strong', {}, r.count), h('span', {}, `of ${DECK_SIZE}`),
      h('div', { class: 'meter', role: 'img', 'aria-label': `${r.count} of ${DECK_SIZE} cards` }, h('span', { style: `width:${Math.min(100, (r.count / DECK_SIZE) * 100)}%` }))),
    r.problems.length ? h('ul', { class: 'deck-problems' }, r.problems.map(p => h('li', { class: p.level }, p.msg))) : null,
    h('div', { class: 'random-box' },
      h('div', { class: 'random-row' },
        h('label', { class: 'field' }, h('span', {}, 'Color focus'),
          h('select', { onchange: e => { state.focus.color = e.target.value; renderDeckPanel(); } },
            h('option', { value: '' }, 'No focus'),
            heroColors.map(c => h('option', { value: c, selected: state.focus.color === c }, c)))),
        state.focus.color ? h('label', { class: 'field' }, h('span', {}, 'How much'),
          h('input', { type: 'range', min: 0, max: 1, step: 0.1, value: state.focus.value, oninput: e => { state.focus.value = Number(e.target.value); } })) : null),
      h('div', { class: 'random-row' },
        h('button', { class: 'primary', disabled: d.heroes.length === 0 || r.count >= DECK_SIZE, onclick: fillRandom }, 'Random fill'),
        h('button', { class: 'ghost', disabled: !r.count, onclick: () => { changeDeck(x => { x.cards = {}; }); toast('Deck emptied (heroes stay). Undo or Ctrl+Z brings it back.'); } }, 'Empty'))),
    r.count ? h('div', { class: 'deck-charts' }, costCurve(r.curve), colorSplit(r.byColor, r.count)) : null,
    r.count ? deckTraits(d) : null,
    groups.length || unknown.length
      ? h('div', { class: 'deck-rows' },
          groups.map(([t, list]) => h('div', { class: 'deck-group' },
            h('h3', {}, t, h('span', { class: 'muted' }, list.reduce((s, x) => s + x.n, 0))),
            list.map(x => deckRow(x, deckCards)))),
          unknown.length ? h('div', { class: 'deck-group' }, h('h3', {}, 'Unknown cards'), unknown.map(x => deckRow(x, deckCards))) : null)
      : h('p', { class: 'muted' }, d.heroes.length ? 'Add cards from the pool or click Random fill.' : 'Pick heroes first.'));
}

function deckRow({ c, id, n }, deckCards) {
  return h('div', { class: 'deck-row' },
    h('span', { class: `dot c-${c?.color ?? 'none'}` }),
    h('span', { class: 'deck-row-cost', title: 'Cost' }, c?.cost ?? '?'),
    c ? h('button', { class: 'deck-row-name', title: `Full screen: ${c.name}`, onclick: () => openViewer(deckCards.map(x => ({ card: x })), deckCards.indexOf(c)) }, c.name)
      : h('span', { class: 'deck-row-name' }, id),
    h('span', { class: 'stepper' },
      h('button', { class: 'step', 'aria-label': `Remove one ${c?.name ?? id}`, onclick: () => (c ? addCard(id, -1) : changeDeck(d => { delete d.cards[id]; })) }, '−'),
      h('span', { class: 'deck-row-n' }, n),
      h('button', { class: 'step', 'aria-label': `Add one ${c?.name ?? id}`, disabled: !c || n >= LIMITS[c.type], onclick: () => addCard(id, 1) }, '+')));
}

function fillRandom() {
  const next = randomFill(state.db, state.deck, { focusColor: state.focus.color || null, focus: state.focus.color ? state.focus.value : 0 });
  changeDeck(d => { d.cards = next.cards; });
  if (next.missing) toast(`The pool isn't big enough: ${next.missing} ${plural(next.missing, 'card', 'cards')} short of ${DECK_SIZE}.`, 'warn');
}

// Krivulja costova: jedna serija, stupci s brojem iznad, hover daje točan iznos.
function costCurve(curve) {
  const costs = Object.keys(curve).map(Number);
  const max = Math.max(...costs, 3);
  const top = Math.max(...Object.values(curve));
  const bars = [];
  for (let cost = 0; cost <= max; cost++) {
    const n = curve[cost] ?? 0;
    bars.push(h('div', { class: 'bar', title: `Cost ${cost}: ${n} ${plural(n, 'card', 'cards')}` },
      h('span', { class: 'bar-n' }, n || ''),
      h('span', { class: 'bar-fill', style: `height:${top ? (n / top) * 100 : 0}%` }),
      h('span', { class: 'bar-x' }, cost)));
  }
  return h('figure', { class: 'curve' }, h('figcaption', {}, 'Cost curve'), h('div', { class: 'bars' }, bars));
}

// Udio boja: boje su boje karata iz igre; svaka ima i natpis s brojem, pa boja nije jedini nositelj.
function colorSplit(byColor, total) {
  const entries = Object.entries(byColor).sort((a, b) => b[1] - a[1]);
  return h('figure', { class: 'split' },
    h('figcaption', {}, 'Colors'),
    h('div', { class: 'split-bar', role: 'img', 'aria-label': entries.map(([c, n]) => `${c} ${n}`).join(', ') },
      entries.map(([c, n]) => h('span', { class: `c-${c}`, style: `flex:${n}`, title: `${c}: ${n}` }))),
    h('ul', { class: 'split-legend' }, entries.map(([c, n]) => h('li', {}, h('span', { class: `dot c-${c}` }), `${c} ${n}`, h('span', { class: 'muted' }, ` ${Math.round((n / total) * 100)}%`)))));
}

async function copyCode() {
  const code = encodeDeck(state.deck, state.db.version);
  const box = $('#deck-code');
  try {
    await navigator.clipboard.writeText(code);
    toast('Deck code copied.');
    box.replaceChildren();
  } catch {
    // Bez HTTPS-a (npr. mobitel preko Tailscale adrese) preglednik ne da pisati u clipboard.
    const input = h('input', { readOnly: true, value: code, 'aria-label': 'Deck code', onfocus: e => e.target.select() });
    box.replaceChildren(h('label', { class: 'field code-out' }, h('span', {}, 'Deck code (select and copy)'), input));
    input.focus();
  }
}

// ---------- start ----------

window.addEventListener('beforeunload', e => {
  if (state.deck?.dirty) e.preventDefault();
});

// Zapamćeni folder s trajnom dozvolom ("Dopusti pri svakom posjetu") otvara se sam, i na lokalnom serveru;
// inače preko servera (mobitel), ili početni ekran s "Nastavi s …".
state.savedRoot = window.showDirectoryPicker ? await fs.loadRoot() : null;
const info = await probeServer();
if (state.savedRoot && (await fs.permission(state.savedRoot).catch(() => 'denied')) === 'granted') {
  await useStore(folderStore(state.savedRoot));
  await applyHash().catch(e => toast(e.message || String(e), 'error'));
} else if (info) {
  await useStore(serverStore(info));
  state.tab = 'decks';
  await applyHash().catch(e => toast(e.message || String(e), 'error'));
}
render();

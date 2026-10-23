import { analyzeExport, buildPublish, applyAppEdits, obsoleteImages, thumbPlan, thumbName, SIZES, CE_FIELDS, ARCHIVE_DIR, archiveFolder, archivePath,
  CHANGELOG_PATH, changelogEntry, appendChangelog, changesSince, describeChange, publishedPngPaths } from './importer.js';
import { TYPES, COLOR_NAMES, DECK_TYPES } from './parse.js';
import { checkDeck, deckPool, randomFill, encodeDeck, decodeDeck, slugify, emptyDeck, heroCards, deckChanges, LIMITS, DECK_SIZE } from './deck.js';
import { probeServer, serverStore, folderStore, ConflictError } from './store.js';
import { GAME_COLORS, heroDefaultColor, paintThumb, createPreview } from './bakugan.js';
import { bakuganTextureId } from './tts.js';
import * as fs from './fsdir.js';

const DB_PATH = 'data/cards.json';
const STEAM_PATH = 'data/steam-urls.json';

const state = {
  store: null,
  db: null,
  logo: null,
  analysis: null,
  tab: 'import',
  // Brzi filteri: unutar skupine "ili", između skupina "i".
  filter: { q: '', types: [], colors: [], sets: [], specials: [], deleted: false, sort: 'id', since: 0 },
  changelog: null,
  inbox: 0, // fileova u sanduču export/ (samo folder)
  selected: null,
  busy: false,
  decks: [],
  deck: null,
  deckView: 'pool',
  pool: { q: '', type: '', color: '', trait: '' },
  focus: { color: '', value: 0.6 },
  bakugani: [], // biblioteka oblika bakugana (data/bakugani/catalog.json)
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

async function makeThumb(blob, width) {
  const bmp = await createImageBitmap(blob);
  width = Math.min(width, bmp.width);
  const height = Math.round((bmp.height / bmp.width) * width);
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
  if (!e.target.isConnected || e.target.closest('#detail, .tile, .slice, .viewer, #toasts')) return;
  closeCard();
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
  state.bakugani = (await store.readBakugani().catch(() => null))?.bakugani ?? [];
  state.logo = await store.logoUrl();
  state.decks = await store.listDecks();
  state.deck = null;
  state.inbox = await countInbox();
  if (store.canImport) await ensureBakuganTextures(state.db).catch(e => console.warn("bakugan textures", e));
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
  $('#tab-import')?.replaceChildren(...tabLabel('import', 'Import'));
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
  toast(`Cards updated to v${state.db.version}${parts.length ? `: ${parts.join(', ')}` : ''}. Details: Browse → Change history.`);
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
  state.tab = 'import';
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
    const steamText = await fs.readText(root(), STEAM_PATH);
    const steam = steamText ? JSON.parse(steamText) : {};
    old = obsoleteImages(db, await fs.listFileNames(root(), 'data/images'), steam);
    for (const f of old) await fs.removeFile(root(), `data/images/${f}`);
  }
  const thumbs = await updateThumbs(db);
  await ensureBakuganTextures(db);
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

// Obojane teksture bakugana (data/bakugani/boje/<oblik>-<rrggbb>.jpg) koje fale: siva tekstura oblika puta boja,
// isto množenje kao sličice u appu. TTS ne boji dijelove modela s teksturom, pa boja mora biti u teksturi.
async function ensureBakuganTextures(db) {
  let made = 0;
  const have = new Set(await fs.listFileNames(root(), 'data/bakugani/boje'));
  for (const c of db.cards) {
    const id = c.type === 'Character' && !c.deleted ? bakuganTextureId(c) : null;
    if (!id || have.has(`${id}.jpg`)) continue;
    const gray = await fs.getFile(root(), `data/bakugani/${c.bakuganShape}.jpg`);
    if (!gray) continue;
    const bmp = await createImageBitmap(gray);
    const canvas = new OffscreenCanvas(bmp.width, bmp.height);
    const g = canvas.getContext('2d');
    g.drawImage(bmp, 0, 0);
    bmp.close();
    g.globalCompositeOperation = 'multiply';
    g.fillStyle = `#${id.slice(-6)}`;
    g.fillRect(0, 0, canvas.width, canvas.height);
    await fs.writeFile(root(), `data/bakugani/boje/${id}.jpg`, await canvas.convertToBlob({ type: 'image/jpeg', quality: 0.9 }));
    have.add(`${id}.jpg`);
    made++;
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
  if ('bakuganShape' in edits || 'bakuganColor' in edits) await ensureBakuganTextures(db);
  toast(bumped ? `Saved: version ${db.version}.` : `Saved (look only; version stays v${db.version}).`);
}

// ---------- prikaz: okvir ----------

function render() {
  const app = $('#app');
  if (state.store) {
    app.replaceChildren(renderHeader(), renderMain());
    updateStrip();
    cardPushed = false;
    syncHash();
  } else app.replaceChildren(renderWelcome());
}

// ---------- adresa: svaki pogled ima svoj #/…, pa gesta ili tipka Natrag vraća korak unatrag ----------

const TAB_SLUG = { import: 'import', browse: 'browse', decks: 'decks' };
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
      'aria-label': `${c.name}: open in Browse`,
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
      h('span', { class: 'brand-sub' }, 'Card database')),
    h('div', { class: 'folder' },
      h('span', { class: 'folder-name', title: server ? 'Data from the computer, via server' : 'Chosen Drive folder' }, server ? `${state.store.name} via server` : state.store.name),
      h('span', { class: 'folder-db' }, `Version ${state.db.version}`, h('span', { class: 'sep', 'aria-hidden': 'true' }), `${n} ${plural(n, 'card', 'cards')}`),
      server && state.savedRoot ? h('button', { class: 'ghost', title: 'Folder for Import and editing', onclick: () => guard(() => resume(state.savedRoot)) }, `Continue with "${state.savedRoot.name}"`) : null,
      !server || window.showDirectoryPicker ? h('button', { class: 'ghost', onclick: () => guard(pickFolder) }, server ? (state.savedRoot ? 'Other folder' : 'Choose folder') : 'Change folder') : null));
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

// Uvoz nosi broj fileova koji čekaju u sanduču export/.
function tabLabel(key, label) {
  const n = key === 'import' ? state.inbox : 0;
  return [label, n ? h('span', { class: 'tab-badge', title: `${n} ${plural(n, 'file', 'files')} waiting in export/` }, n) : null].filter(Boolean);
}

function renderMain() {
  const tabs = [
    ['import', 'Import'],
    ['browse', 'Browse'],
    ['decks', 'Decks'],
  ];
  const view = { import: renderImport, browse: renderBrowse, decks: renderDecks }[state.tab]();
  // Na desktopu je izbornik stupac lijevo (s listom deckova na kartici Deckovi), na mobitelu kartice gore.
  return h('div', { class: 'shell' },
    h('aside', { class: 'side' },
      h('nav', { class: 'tabs', role: 'tablist' },
        tabs.map(([key, label]) => h('button', { id: `tab-${key}`, role: 'tab', 'aria-selected': String(state.tab === key), class: state.tab === key ? 'active' : '', onclick: () => { state.tab = key; render(); } }, tabLabel(key, label)))),
      state.tab === 'decks' ? renderDeckList() : null,
      h('p', { class: 'soon' }, 'Catalog and TTS come in later phases.')),
    h('main', {}, view));
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
  const only = [e.imageChanged && 'image', e.spriteChanged && 'sprite'].filter(Boolean);
  const rows = e.old
    ? e.diffs.map(k => h('tr', {}, h('th', {}, k), h('td', { class: 'was' }, fmt(e.old[k])), h('td', { class: 'now' }, fmt(e.card[k]))))
    : CE_FIELDS.filter(k => e.card[k] !== undefined).map(k => h('tr', {}, h('th', {}, k), h('td', { colspan: 2 }, fmt(e.card[k]))));
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
  bezBakugana: ['No bakugan', 'Heroes that have no bakugan chosen yet'],
  bezSpritea: ['No sprite', 'Heroes and evolutions without a sprite (figurine in TTS)'],
};

function specialFilter(name) {
  if (name === 'novo') {
    const last = state.changelog?.entries.at(-1);
    const ids = new Set((last?.cards ?? []).map(c => c.id));
    return c => ids.has(c.id);
  }
  if (name === 'bezBakugana') return c => c.type === 'Character' && !c.bakuganShape;
  if (name === 'bezSpritea') return c => (c.type === 'Character' || c.type === 'Evolution') && !c.sprite;
  return () => true;
}

function filtered() {
  const { q, types, colors, sets, specials, deleted, sort, since } = state.filter;
  const needle = q.trim().toLowerCase();
  const changed = since ? changesSince(state.changelog, since - 1) : null;
  const extras = specials.map(specialFilter);
  return state.db.cards.filter(c =>
    (deleted || !c.deleted) &&
    (!types.length || types.includes(c.type)) &&
    (!colors.length || colors.includes(c.color)) &&
    (!sets.length || sets.includes(setOf(c))) &&
    (!extras.length || extras.some(fn => fn(c))) &&
    (!changed || changed.has(c.id)) &&
    (!needle || [c.id, c.name, c.text, ...(c.traits ?? [])].join(' ').toLowerCase().includes(needle)))
    .sort((a, b) => SORTS[sort][1](a, b) || byCode(a, b));
}

const plural = (n, one, other) => (n === 1 ? one : other);
const shortDate = iso => (iso ? new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'numeric', year: 'numeric' }) : '');

// Povijest promjena baze, od najnovije verzije; imena karata otvaraju kartu.
function renderHistory() {
  const entries = [...(state.changelog?.entries ?? [])].reverse();
  if (!entries.length) return null;
  const cardLink = c => h('button', { class: 'link', onclick: () => openCard(c.id) }, `${c.id} ${c.name}`);
  return h('details', { class: 'history' },
    h('summary', {}, `Change history (${entries.length} ${plural(entries.length, 'version', 'versions')})`),
    entries.map(e => {
      const fresh = e.cards.filter(c => c.kind === 'new');
      const rest = e.cards.filter(c => c.kind !== 'new');
      return h('section', { class: 'history-entry' },
        h('h3', {}, `v${e.version}`, h('span', { class: 'muted' }, ` ${shortDate(e.date)} · ${e.cards.length} ${plural(e.cards.length, 'card', 'cards')}`)),
        rest.length ? h('ul', {}, rest.map(c => h('li', {}, cardLink(c), h('span', { class: `change ${c.kind}` }, describeChange(c))))) : null,
        fresh.length ? h('p', { class: 'history-new' }, h('span', { class: 'change new' }, `new (${fresh.length}):`), ' ', fresh.flatMap((c, i) => [i ? ', ' : null, cardLink(c)]).filter(Boolean)) : null);
    }));
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
    renderHistory(),
    h('div', { id: 'grid', class: 'grid' }),
    h('div', { id: 'detail' }));
  queueMicrotask(() => { renderGrid(); renderDetail(); });
  return panel;
}

// Gumbi: tip, boja, set, posebni. Klik uključi ili isključi; unutar skupine "ili" (Action + Equipment),
// između skupina "i" (Heroji i crvena). Maknute su prekidač; Očisti sve vrati.
function renderQuickFilters() {
  const f = state.filter;
  const on = (k, v) => f[k].includes(v);
  const toggle = (k, v) => { f[k] = on(k, v) ? f[k].filter(x => x !== v) : [...f[k], v]; render(); };
  const chip = (k, v, label, title) => h('button', { type: 'button', class: `qf${on(k, v) ? ' active' : ''}`, title: title ?? '', 'aria-pressed': String(on(k, v)), onclick: () => toggle(k, v) }, label);
  const sets = [...new Set(state.db.cards.filter(c => c.type !== 'Stage').map(setOf))].sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  const any = f.types.length || f.colors.length || f.sets.length || f.specials.length || f.deleted || f.since || f.q;
  return h('div', { class: 'quick' },
    h('div', { class: 'qf-group' }, TYPES.map(t => chip('types', t, t === 'Character' ? 'Heroes' : t))),
    h('div', { class: 'qf-group' }, COLOR_NAMES.map(c => h('button', {
      type: 'button', class: `qf-color c-${c}${on('colors', c) ? ' active' : ''}`, title: c, 'aria-label': c, 'aria-pressed': String(on('colors', c)), onclick: () => toggle('colors', c),
    }))),
    sets.length > 1 ? h('div', { class: 'qf-group' }, sets.map(x => chip('sets', x, x, `Set ${x}`))) : null,
    h('div', { class: 'qf-group qf-specials' },
      Object.entries(SPECIAL).map(([k, [label, title]]) => chip('specials', k, label, title)),
      h('button', { type: 'button', class: `qf${f.deleted ? ' active' : ''}`, title: 'Also show deleted cards', 'aria-pressed': String(f.deleted), onclick: () => { f.deleted = !f.deleted; render(); } }, 'Deleted')),
    any ? h('button', { type: 'button', class: 'qf qf-clear', onclick: () => {
      Object.assign(f, { q: '', types: [], colors: [], sets: [], specials: [], deleted: false, since: 0 });
      render();
    } }, 'Clear') : null);
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
  const all = state.db.cards.filter(c => state.filter.deleted || !c.deleted).length;
  $('#grid-count')?.replaceChildren(cards.length === all ? `${all} ${plural(all, 'card', 'cards')}` : `${cards.length} of ${all} cards`);
}

function tile(c) {
  return h('button', { class: `tile${c.deleted ? ' deleted' : ''}${state.selected === c.id ? ' selected' : ''}`, onclick: () => openCard(c.id) },
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
        h('h3', {}, 'App fields'),
        c.type === 'Character' ? [
          field('Bakugan weight (wt)', h('input', { type: 'number', min: 1, step: 1, value: c.wt ?? '', oninput: e => { if (e.target.value === '') delete edits.wt; else edits.wt = Number(e.target.value); } })),
          bakuganPicker(c, edits),
        ] : null,
        h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: !!c.deleted, onchange: e => { edits.deleted = e.target.checked; } }), 'Deleted – the deck builder no longer offers it'),
        h('button', { class: 'primary', type: 'submit' }, 'Save'))
    : null;
  const rows = ['type', 'color', 'cost', 'evo', 'hero', 'stats', 'wt', 'bonus', 'values', 'traits', 'text', 'rev', 'imageHash']
    .filter(k => c[k] !== undefined)
    .map(k => h('tr', {}, h('th', {}, k), h('td', {}, fmt(c[k]))));
  if (c.sprite) {
    const img = h('img', { class: 'sprite-img', alt: `${c.name} sprite` });
    state.store.dataUrl(c.sprite).then(u => { if (u) img.src = u; });
    rows.push(h('tr', {}, h('th', {}, 'sprite'), h('td', {}, h('button', { class: 'sprite-btn', title: 'Full screen',
      onclick: () => state.store.dataUrl(c.sprite).then(u => u && openViewer([{ url: u, title: `${c.id} · ${c.name} · sprite` }])) }, img))));
  }
  const history = (state.changelog?.entries ?? []).flatMap(e => e.cards.filter(x => x.id === c.id).map(x => `v${e.version}: ${describeChange(x)}`)).reverse();
  if (history.length) rows.push(h('tr', {}, h('th', {}, 'history'), h('td', {}, history.join(' · '))));
  const inDecks = decksWith(c.id);
  if (inDecks.length) {
    rows.push(h('tr', {}, h('th', {}, 'in decks'), h('td', {}, inDecks.flatMap((d, i) => [i ? ', ' : null,
      h('button', { class: 'link', onclick: () => { if (confirmDiscard()) { state.tab = 'decks'; guard(() => openDeck(d.slug)); } } }, d.name)]).filter(Boolean))));
  }
  box.replaceChildren(
    h('div', { class: 'detail-head' }, h('div', {}, h('code', {}, c.id), h('h2', {}, c.name)), h('button', { class: 'ghost', onclick: closeCard }, 'Close')),
    h('div', { class: 'detail-body' },
      h('button', { class: 'big', title: 'Full screen', onclick: () => { const list = filtered(); openViewer((list.includes(c) ? list : [c]).map(x => ({ card: x })), list.includes(c) ? list.indexOf(c) : 0); } },
        cardImg(c, { alt: c.name, full: true }), h('span', { class: 'zoom', 'aria-hidden': 'true' }, icon('zoom'))),
      h('div', {}, h('table', { class: 'fields' }, rows), c.type === 'Character' && !editor ? bakuganPicker(c, null) : null, editor)));
}

// Bakugan heroja: 3D pregled, boja (boje igre, boja heroja ili bilo koja) i oblik iz biblioteke.
// edits = null: samo pregled (preko servera se app polja ne mijenjaju).
function bakuganPicker(c, edits) {
  const lib = state.bakugani ?? [];
  if (!lib.length) return edits ? h('p', { class: 'muted small' }, 'No bakugan library (data/bakugani/catalog.json).') : null;
  let shape = lib.find(b => b.id === c.bakuganShape) ?? null;
  if (!edits && !shape) return null;
  let color = c.bakuganColor ?? heroDefaultColor(c);
  const canvas = h('canvas', { class: 'bk-3d', width: 240, height: 240, 'aria-label': 'Bakugan, 3D preview (drag to rotate)' });
  const preview = createPreview(canvas);
  const nameEl = h('span', { class: 'bk-name' });
  const thumbs = new Map();
  const show = () => {
    nameEl.textContent = shape ? shape.name : 'No shape chosen';
    if (shape) Promise.all([state.store.dataUrl(shape.mesh), state.store.dataUrl(shape.texture)]).then(([m, t]) => m && t && preview.show(m, t, color));
  };
  const recolor = () => {
    preview.setColor(color);
    for (const [b, cv] of thumbs) state.store.dataUrl(b.thumb).then(u => u && paintThumb(cv, u, color));
    picker.querySelectorAll('.bk-swatch').forEach(s => s.classList.toggle('active', s.dataset.color === color));
    if (colorInput) colorInput.value = color;
  };
  const setColor = v => { color = v.toLowerCase(); if (edits) edits.bakuganColor = color; recolor(); };
  const colorInput = edits ? h('input', { type: 'color', value: color, 'aria-label': 'Any color', oninput: e => setColor(e.target.value) }) : null;
  const swatches = edits ? h('div', { class: 'bk-colors' },
    Object.entries({ ...GAME_COLORS }).map(([name, hex]) => h('button', { type: 'button', class: 'bk-swatch', style: `--sw:${hex}`, 'data-color': hex, title: name, 'aria-label': name, onclick: () => setColor(hex) })),
    h('button', { type: 'button', class: 'ghost small-btn', onclick: () => setColor(heroDefaultColor(c)) }, 'Hero color'),
    h('label', { class: 'bk-custom', title: 'Any color' }, colorInput)) : null;
  const grid = edits ? h('div', { class: 'bk-grid' }, lib.map(b => {
    const cv = h('canvas', { width: 96, height: 96 });
    thumbs.set(b, cv);
    return h('button', { type: 'button', class: `bk-shape${shape === b ? ' active' : ''}`, title: b.name, onclick: e => {
      shape = b;
      edits.bakuganShape = b.id;
      grid.querySelectorAll('.bk-shape').forEach(x => x.classList.toggle('active', x === e.currentTarget));
      show();
    } }, cv, h('span', {}, b.name));
  })) : null;
  const picker = h('section', { class: 'bk' },
    h('h3', {}, 'Bakugan'),
    h('div', { class: 'bk-main' }, canvas, h('div', { class: 'bk-side' }, nameEl, swatches,
      edits ? h('p', { class: 'muted small' }, 'The color is multiplied with the gray texture, as in TTS. Choose a shape and a color, then Save.') : null)),
    grid);
  show();
  recolor();
  return picker;
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

function renderDeckList() {
  return h('section', { class: 'deck-list' },
    h('div', { class: 'deck-list-head' },
      h('h2', {}, 'My decks'),
      h('button', { class: 'primary', onclick: () => { if (confirmDiscard()) { state.deck = newDeck(); state.deckView = 'pool'; render(); } } }, 'New deck')),
    state.decks.length
      ? h('ul', {}, state.decks.map(x => h('li', {},
          h('button', {
            class: `deck-item${state.deck?.slug === x.slug ? ' active' : ''}`,
            onclick: () => { if (confirmDiscard()) guard(() => openDeck(x.slug)); },
          },
            h('span', { class: 'deck-item-name' }, x.name),
            h('span', { class: 'deck-item-sub' }, x.broken ? 'broken file' : `${x.heroes.map(id => cardById(id)?.name ?? id).join(', ') || 'no heroes'}`),
            x.broken ? null : deckFlags(x),
            h('span', { class: 'deck-item-count' }, x.broken ? '' : `${x.count}/${DECK_SIZE}`)))))
      : h('p', { class: 'muted' }, 'No saved decks yet.'),
    h('details', { class: 'code-import' },
      h('summary', {}, 'Load deck code'),
      h('form', { onsubmit: e => { e.preventDefault(); importCode(e.target.elements.code.value); } },
        h('input', { name: 'code', placeholder: 'EB1|v1|…', autocomplete: 'off', spellcheck: false }),
        h('button', { type: 'submit' }, 'Load'))));
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

function renderHeroes() {
  const box = $('#deck-heroes');
  const d = state.deck;
  const taken = new Set(d.heroes);
  const free = heroCards(state.db).filter(c => !taken.has(c.id));
  const slots = [0, 1, 2].map(i => {
    const hero = cardById(d.heroes[i]);
    if (hero) {
      const heroes = d.heroes.map(cardById).filter(Boolean);
      return h('div', { class: `hero-slot filled c-border-${hero.color}` },
        h('button', { class: 'hero-art', title: `Full screen: ${hero.name}`, onclick: () => openViewer(heroes.map(x => ({ card: x })), heroes.indexOf(hero)) }, cardImg(hero, { alt: hero.name })),
        h('div', { class: 'hero-info' },
          h('span', { class: 'hero-name' }, hero.name),
          h('span', { class: 'muted small' }, hero.color),
          h('button', { class: 'ghost small-btn', onclick: () => changeDeck(x => { x.heroes = x.heroes.filter(id => id !== hero.id); }) }, 'Remove')));
    }
    return h('label', { class: 'hero-slot empty' },
      h('span', { class: 'muted' }, `Hero ${i + 1}`),
      h('select', { onchange: e => { if (e.target.value) changeDeck(x => { x.heroes = [...x.heroes, e.target.value]; }); } },
        h('option', { value: '' }, 'Choose a hero'),
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
  colorSel.replaceChildren(h('option', { value: '' }, 'All hero colors'), ...colors.map(c => h('option', { value: c, selected: state.pool.color === c }, c)));
  // Traitovi bazena, najčešći prvi (npr. {Luffy} karte za heroja ili evoluciju koja ih poziva).
  const traits = traitCounts(all.map(c => [c, 1]));
  if (state.pool.trait && !traits.some(([t]) => t === state.pool.trait)) state.pool.trait = '';
  $('#pool-trait')?.replaceChildren(h('option', { value: '' }, 'All traits'), ...traits.map(([t, n]) => h('option', { value: t, selected: state.pool.trait === t }, `${t} (${n})`)));
  if (!d.heroes.length) {
    box.replaceChildren(h('p', { class: 'muted' }, 'Pick heroes, and cards of their colors show up here.'));
    return;
  }
  const { q, type, color, trait } = state.pool;
  const needle = q.trim().toLowerCase();
  const cards = all
    .filter(c => (!type || c.type === type) && (!color || c.color === color) && (!trait || (c.traits ?? []).includes(trait)) && (!needle || [c.name, c.text, ...(c.traits ?? [])].join(' ').toLowerCase().includes(needle)))
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
  return h('div', { class: `pool-card${n ? ' in-deck' : ''}${n >= max ? ' maxed' : ''}` },
    h('div', { class: 'pool-art-wrap' },
      h('button', { class: 'pool-art', title: `Add ${c.name}`, disabled: n >= max, onclick: () => addCard(c.id, 1) }, cardImg(c, { alt: c.name }),
        n ? h('span', { class: 'pool-count' }, `${n}/${max}`) : null),
      zoomButton(c, list)),
    h('div', { class: 'pool-meta' },
      h('span', { class: 'pool-name' }, c.name),
      h('span', { class: 'stepper' },
        h('button', { class: 'step', 'aria-label': `Remove one ${c.name}`, disabled: !n, onclick: () => addCard(c.id, -1) }, '−'),
        h('button', { class: 'step', 'aria-label': `Add one ${c.name}`, disabled: n >= max, onclick: () => addCard(c.id, 1) }, '+'))));
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

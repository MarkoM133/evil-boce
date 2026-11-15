// Card editor (zamjena za Card Engine), po Markovim mockupima (docs/private/mockups/card-editor/).
// Stranice: Sets (mreža karata seta), Publish, Traits & aliases, Text guide, Frames; otvorena karta je cijeli ekran
// s trakom (breadcrumb, lock, Undo, Close, Save), lijevo paneli (Checks, panel tipa, fx, Balance, Notes & history),
// u sredini karta, desno forma. Izmjene se spremaju kao nacrti (data/editor/drafts.json); igra ih vidi tek nakon Objave.
// Tekst je u editoru s tokenima ([HP], [PWR]…), u bazi riječima (js/card-text.js).
import { loadTemplate, renderCard, fontsReady, loadImage, parseEffect, templateName, coreMode, TINTS, PHASE_COLORS } from './render.js';
import { fxProblems } from './fx-grammar.js';
import { firstTag, traitNames, norm, GENERAL, HEROES, TRAIT, INVALID } from './tags.js';
import { TERRAINS } from './parse.js';
import { applyDrafts, imageHashOf } from './importer.js';
import { lockPath, lockState, newLock, pickLock, lockIdOf, isConflictCopy, isLive, LOCK_DIR, HEARTBEAT_MS, SETTLE_MS, IDLE_MS } from './locks.js';
import { createSetsView } from './editor-sets.js';
import { createGuideView, readGuide, avoidWarnings, suggest } from './editor-guide.js';
import { createFramesView } from './editor-frames.js';
import { toTokens, toWords, headAt, withHeadAt, stripTerrain, withTerrain, coreBonus, coreEffect, PHASES } from './card-text.js';
import { deckPool, heroEvolutions, setTraits } from './deck.js';
import { decorate, comboProblems, touchedIngredients, INGREDIENT_TYPES } from './combo.js';
import { planMove, targetCode, renameKeys, moveDrafts } from './card-move.js';
import * as fs from './fsdir.js';

export const DRAFTS_PATH = 'data/editor/drafts.json';
const NOTES_PATH = 'data/editor/notes.json';
const WISH_PATH = 'data/fx-wishlist.json';
const HISTORY_PATH = 'data/editor/history.json';
// Intent (Marko 2026-11-14): what a card should do in the author's own words, by card id: { text, who, at, forText }.
// forText is the card text it was last confirmed against. Players never see it; Claude gets it with every request.
const INTENT_PATH = 'data/editor/intent.json';
const INTENT_OPEN_KEY = 'evil-boce-intent-open';
// Zadnja Objava iz editora: baza prije nje i objavljeni nacrti, za Undo.
const LAST_PUBLISH_PATH = 'data/editor/last-publish.json';
export const EDIT_TYPES = ['Hero', 'Evolution', 'Action', 'Equipment', 'Assist', 'Stage', 'Core', 'Combo'];
export const PAGES = ['sets', 'publish', 'traits', 'guide', 'frames', 'wishlist', 'words'];
const PORTRAIT = ['Action', 'Equipment', 'Assist'];
const HEROISH = ['Hero', 'Evolution'];
// Vodoravne karte: heroji, evolucije i Combo karte (2026-11-07).
const WIDE = ['Hero', 'Evolution', 'Combo'];
const COLORS = Object.keys(TINTS);
// Karta je Ready ili Not ready (u podacima status done / draft; Marko 2026-11-15): prekidač ☐ Ready u traci karte,
// Publish pušta samo Ready.
const CORE_KINDS = ['Buff', 'Major', 'Debuff'];
const ROMAN = ['I', 'II', 'III'];
const WHO_KEY = 'evil-boce-who';
const TAB_KEY = 'evil-boce-tab';
const STAT_KEYS = [['hp', 'HP'], ['dmg', 'DMG'], ['pwr', 'PWR'], ['rng', 'RNG'], ['kb', 'KB']];
const TOKENS = ['HP', 'DMG', 'PWR', 'RNG', 'KB', 'EN'];
// Polja koja editor mijenja; nacrt čuva samo ona koja se razlikuju od karte u cards.json.
const FIELDS = ['name', 'type', 'token', 'color', 'bonusColors', 'cost', 'bonus', 'stats', 'evo', 'hero', 'abilityNames', 'traits', 'aliases', 'text', 'terrain',
  'fx', 'fxStatus', 'fxRead', 'art', 'artCrop', 'emblem', 'bg', 'template', 'coreImage', 'status', 'ingredients', 'extraCost', 'introducedIn'];
const TYPE_BADGE = { Hero: 'hero', Evolution: 'evolution', Action: 'action', Equipment: 'action', Assist: 'action', Stage: 'stage', Core: 'core', Combo: 'combo' };

// Prazan objekt ili popis je isto što i polje kojeg nema (Stage bez bonusa, karta bez tagova).
const empty = v => v == null || v === '' || (typeof v === 'object' && Object.keys(v).length === 0);
const sameVal = (a, b) => (empty(a) && empty(b)) || JSON.stringify(a) === JSON.stringify(b);
const setOf = id => id.split('-')[0];
const isDefaultCrop = c => !c || (c.x === 0.5 && c.y === 0.5 && (c.zoom ?? 1) === 1);
const when = iso => {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const today = new Date().toDateString() === d.toDateString();
  return today ? `today ${d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : `${d.getDate()}.${d.getMonth() + 1}.`;
};

// env: { state, h, toast, guard, render, go(id), openTab(tab), openEffect(id), assertFresh, commitDb, dropOldImages, renderTraits }
export function createEditor(env) {
  const { h } = env;
  const ed = {
    drafts: null, guide: null, notes: null, history: null, locks: {}, locksAt: 0, tpls: {}, ready: false, agency: true, loading: false, error: null,
    id: null, base: null, work: null, art: null, artFor: null, emblem: null, emblemFor: null, dirty: false,
    undo: [], snapAt: 0, view: 'card', artMode: false, lock: null, last: undefined, balOpen: true, pubOff: new Set(),
    canvas: null, frame: 0, from: 'sets', thumbs: new Map(),
    claude: {}, // Claude prijedlozi fx-a po karti: { waiting, at, res } (vidi askClaude)
    textCheck: {}, // Check text po karti, isti oblik (vidi checkText)
    intent: null, intentDraft: null, answers: {}, ctOpen: {},
    intentOpen: (() => { try { return localStorage.getItem(INTENT_OPEN_KEY) !== '0'; } catch { return true; } })(),
  };
  const store = () => env.state.store;
  // Spremanje: zajednički folder na računalu, ili server koji smije spremati (mobitel). Publish samo iz foldera.
  const canWrite = () => store()?.kind === 'folder' || !!store()?.root?.remote;
  const canPublish = () => store()?.kind === 'folder';
  const who = () => { try { return localStorage.getItem(WHO_KEY) || ''; } catch { return ''; } };
  const setWho = name => { try { localStorage.setItem(WHO_KEY, name); } catch {} };
  const db = () => env.state.db;

  async function load() {
    if (ed.loading) return;
    ed.loading = true;
    try {
      ed.agency = await fontsReady();
      [ed.drafts, ed.guide, ed.notes, ed.history, ed.wishlist, ed.intent] = await Promise.all([readJson(DRAFTS_PATH, { version: 1, cards: {} }), readGuide(store()), readJson(NOTES_PATH, { cards: {} }), readJson(HISTORY_PATH, { cards: {} }), readJson(WISH_PATH, { version: 1, items: [] }), readJson(INTENT_PATH, { cards: {} })]);
      await readLocks();
      await sets.ensure();
      ed.ready = true;
    } catch (e) {
      ed.error = e.message || String(e);
    }
    ed.loading = false;
    env.render();
  }

  // Uvijek s diska (drugi stroj je mogao spremiti u međuvremenu; Syncthing donese datoteku).
  // Datoteke koje nema daju fallback; datoteka koja se ne da pročitati (Syncthing je upravo mijenja) je greška,
  // da se pozivatelj ne bi zapisao prazan popis preko tuđih nacrta.
  async function readJson(path, fallback) {
    let text;
    if (store().kind === 'folder') text = await fs.readText(store().root, path);
    else {
      const r = await fetch(path, { cache: 'no-store' });
      if (r.status === 404) return structuredClone(fallback);
      if (!r.ok) throw new Error(`${path} could not be read (${r.status}).`);
      text = await r.text();
    }
    if (text == null || !text.trim()) return structuredClone(fallback);
    try {
      return JSON.parse(text);
    } catch {
      throw new Error(`${path} is being written right now (or is broken). Try again in a moment.`);
    }
  }
  const readDrafts = () => readJson(DRAFTS_PATH, { version: 1, cards: {} });
  const writeJson = (path, data) => fs.writeFile(store().root, path, JSON.stringify(data, null, 2) + '\n');

  // Predlošci se učitavaju kad zatrebaju (data/card-frames/<ime>/).
  function templateFor(card) {
    const name = templateName(card);
    ed.tpls[name] ??= loadTemplate(name, rel => store().dataUrl(rel));
    return ed.tpls[name];
  }

  // Karte iz cards.json s nacrtima, i nove karte iz nacrta (new: true).
  const merged = c => ({ ...c, ...(ed.drafts?.cards?.[c.id] ?? {}) });
  function allCards() {
    const list = db().cards.filter(c => EDIT_TYPES.includes(c.type) && !c.deleted).map(merged);
    for (const [id, d] of Object.entries(ed.drafts?.cards ?? {})) if (d.new && !db().cards.some(c => c.id === id)) list.push({ id, ...d });
    if (ed.work?.new && !list.some(c => c.id === ed.work.id)) list.push(cardOf(ed.work));
    return list.sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  }

  // ---------- radna kopija karte ----------

  // Forma drži tekst s tokenima; Stage bez reda "Terrain:", Core s efektom umjesto bonusa.
  function workOf(card) {
    const w = structuredClone(card);
    w.text = toTokens(card.type === 'Stage' ? stripTerrain(card.text) : card.text);
    w.traits ??= [];
    w.artCrop ??= { x: 0.5, y: 0.5, zoom: 1 };
    if (PORTRAIT.includes(card.type)) w.bonus ??= {};
    if (HEROISH.includes(card.type)) w.stats ??= {};
    if (card.type === 'Core') w.effect = coreEffect(card.bonus);
    return w;
  }

  // Karta kakvu vide renderer, nacrt i igra: riječi, red "Terrain:", bonus Corea iz efekta.
  function cardOf(w) {
    const c = { ...w, text: toWords(w.text) };
    if (w.type === 'Stage') c.text = withTerrain(c.text, w.terrain ?? 'None');
    if (w.type === 'Core') { c.bonus = coreBonus(w.effect); c.text = ''; }
    delete c.effect;
    return c;
  }

  function open(id) {
    const draft = ed.drafts?.cards?.[id];
    const base = db().cards.find(c => c.id === id) ?? (draft?.new ? { id } : null);
    if (!base) { ed.id = null; ed.work = null; return; }
    ed.id = id;
    ed.base = base;
    ed.work = workOf({ ...base, ...(draft ?? {}) });
    ed.opened = cardOf(ed.work);
    ed.canvas = null;
    ed.artCv = null;
    ed.dirty = false;
    ed.lastInput = Date.now();
    ed.undo = [];
    ed.artMode = false;
    ed.view = 'card';
    ed.art = ed.artFor = ed.emblem = ed.emblemFor = null;
  }

  const isCardPage = () => {
    const want = env.state.editId;
    return !!want && !PAGES.includes(want);
  };

  // ---------- prikaz ----------

  function render() {
    if (!ed.ready && !ed.error) {
      load();
      return h('section', { class: 'panel' }, h('p', { class: 'muted' }, 'Loading the card editor…'));
    }
    if (ed.error) return h('section', { class: 'panel' }, h('p', { class: 'warn' }, ed.error));
    const want = env.state.editId ?? 'sets';
    if (PAGES.includes(want)) {
      if (ed.id) {
        if (!leaveOk()) return renderCardPage();
        ed.id = null;
        ed.work = null;
      }
      syncLock();
      // Lockovi i cards.json s drugog stroja, najviše svakih 30 s.
      if (Date.now() - ed.locksAt > HEARTBEAT_MS) {
        Promise.all([readLocks(), refreshDb()]).then(([a, b]) => { if (a || b) env.render(); }).catch(() => {});
      }
      return h('div', { class: 'ce-page-wrap' }, readOnlyNote(), pageTabs(want), { sets: sets.render, guide: guide.render, traits: renderTraitsPage, words: renderTraitsPage, frames: frames.render, publish: renderPublish, wishlist: renderFxPage }[want]());
    }
    if (want !== ed.id) {
      if (!leaveOk()) return renderCardPage();
      open(want);
    }
    syncLock();
    if (!ed.work) return h('section', { class: 'panel' }, h('p', { class: 'warn' }, `No card ${want}.`), h('button', { class: 'ghost', onclick: () => go('sets') }, 'Back to Sets'));
    return renderCardPage();
  }

  // Nespremljene izmjene pri odlasku s karte (Natrag, druga stranica): pitaj; "ne" vrati adresu na kartu.
  function leaveOk() {
    if (!ed.dirty || !ed.work) return true;
    if (confirm('Discard the unsaved changes to this card?')) { ed.dirty = false; return true; }
    env.state.editId = ed.id;
    env.state.tab = 'editor';
    setTimeout(env.render, 0);
    return false;
  }

  // Odlazak iz Card editora na drugu stranicu appa: pitaj za nespremljeno i otpusti lock.
  function leave() {
    if (!leaveOk()) return false;
    ed.id = null;
    ed.work = null;
    releaseLock();
    return true;
  }
  window.addEventListener('beforeunload', e => { if (ed.dirty && ed.work) e.preventDefault(); });

  function go(id) {
    if (ed.dirty && id !== ed.id && !confirm('Discard the unsaved changes to this card?')) return;
    ed.dirty = false;
    if (id && !PAGES.includes(id) && (!ed.id || PAGES.includes(env.state.editId ?? 'sets'))) ed.from = env.state.editId ?? 'sets';
    env.go(id);
  }

  // ---------- stranica karte ----------

  // Pregled karta po karta (Marko 2026-11-03, iz mockupa): Prev / Next idu redom kojim je karta otvorena (mreža seta s
  // filterima, ili popis nacrta u Publishu). Looks good je maknut 2026-11-15: status je pločica u traci karte.
  function reviewOrder(id) {
    let ids = ed.from === 'publish' ? draftList().map(x => x.id) : sets.order();
    if (!ids.includes(id)) {
      const set = setOf(id);
      ids = allCards().filter(c => setOf(c.id) === set).map(c => c.id).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
    }
    return ids;
  }

  function step(dir) {
    const ids = reviewOrder(ed.id);
    const i = ids.indexOf(ed.id);
    const to = ids[i + dir];
    if (to) go(to);
    return !!to;
  }


  // ← i → listaju karte dok se ne tipka (polja, popisi, tekst).
  if (!globalThis.__ceArrows) {
    globalThis.__ceArrows = true;
    document.addEventListener('keydown', e => {
      if (ed.artMode && e.key === 'Escape') { e.preventDefault(); cancelArt(); return; }
      if (!ed.id || !ed.work || e.altKey || e.ctrlKey || e.metaKey || (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight')) return;
      const t = e.target;
      if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
      if (ed.artMode) return;
      e.preventDefault();
      step(e.key === 'ArrowRight' ? 1 : -1);
    });
  }

  // Uređivanje arta (Marko 2026-11-05): Cancel ili Esc vrati izrez kakav je bio prije Edit art, i Undo i "nespremljeno".
  function startArt() {
    ed.artBefore = { crop: structuredClone(ed.work.artCrop), dirty: ed.dirty, undo: ed.undo.length };
    ed.artMode = true;
    env.render();
  }

  function cancelArt() {
    const b = ed.artBefore;
    if (b && ed.work) {
      ed.work.artCrop = b.crop;
      ed.dirty = b.dirty;
      ed.undo.length = Math.min(ed.undo.length, b.undo);
    }
    ed.artBefore = null;
    ed.artMode = false;
    queueDraw();
    env.render();
  }

  // The page is drawn anew after most clicks (Check text, Save, Use this…): each column goes back to where it was
  // scrolled, as long as it is the same card (Marko 2026-11-14: Check text with this threw the form to the top).
  // Read before the new page replaces the old one, put back before the next frame is painted.
  const SCROLLED = ['.ce-form', '.ce-side', '.ce-centre', '.ce-cols'];
  function keepScroll(id) {
    const was = {};
    for (const sel of SCROLLED) { const n = document.querySelector(sel); if (n?.scrollTop) was[sel] = n.scrollTop; }
    const same = ed.scrolledFor === id;
    ed.scrolledFor = id;
    if (!same || !Object.keys(was).length) return;
    requestAnimationFrame(() => { for (const [sel, top] of Object.entries(was)) { const n = document.querySelector(sel); if (n) n.scrollTop = top; } });
  }

  // The wheel over the empty space beside the card scrolls the column on that side (Marko 2026-11-15): left of the
  // card the side blocks, right of it the form. Over the card, and over the columns themselves, as before.
  function wheelToColumn(e) {
    if (e.ctrlKey || e.target.closest('.ce-side, .ce-form')) return;
    const cols = e.currentTarget;
    const stage = cols.querySelector('.ce-stage')?.getBoundingClientRect();
    const side = cols.querySelector('.ce-side');
    const form = cols.querySelector('.ce-form');
    if (!stage) return;
    let to = null;
    if (e.clientX < stage.left && side && side.getBoundingClientRect().right <= stage.left) to = side;
    else if (e.clientX > stage.right && form && form.getBoundingClientRect().left >= stage.right) to = form;
    if (!to || to.scrollHeight <= to.clientHeight) return;
    e.preventDefault();
    to.scrollTop += e.deltaY * (e.deltaMode === 1 ? 32 : e.deltaMode === 2 ? to.clientHeight : 1);
  }

  function renderCardPage() {
    const w = ed.work;
    keepScroll(w.id);
    const setName = sets.nameOf(w.type === 'Core' ? 'Core' : w.type === 'Stage' ? 'Stage' : setOf(w.id));
    // Lokot samo kad treba (Marko 2026-11-15, mockup docs/private/mockups/topbar): kad uređuješ ti, mala ikona uz
    // naslov s tooltipom; kad uređuje netko drugi, crvena traka preko cijele širine ispod trake s Take over.
    const lockChip = canWrite() && !who() ? h('span', { class: 'ce-lockchip muted' }, 'Set "Signed in as" to lock the card') : null;
    const lockMini = ed.lock?.state === 'mine'
      ? h('span', { class: 'ce-lock-mini', title: 'You are editing: the card is locked under your name until you close it', 'aria-label': 'You are editing this card' }, '🔒') : null;
    const otherSince = lockBusy() && Number.isFinite(Date.parse(ed.lock.other?.since ?? ''))
      ? ` (since ${new Date(ed.lock.other.since).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })})` : '';
    const takeOver = label => h('button', { class: 'ghost', type: 'button', onclick: () => env.guard(() => { releaseLock(); return claimLock(ed.id, who(), true); }) }, label);
    const lockBand = ed.lock?.state === 'other'
      ? h('div', { class: 'ce-lock-band', role: 'status' }, '🔒 ', h('b', {}, ed.lock.other?.who ?? 'Someone'),
        ` is editing this card${otherSince}. You can look; Save is off until they close it.`, takeOver('Take over'))
      : ed.lock?.state === 'twin'
        ? h('div', { class: 'ce-lock-band', role: 'status' }, '🔒 You have this card open in another window', otherSince,
          '. Save is off here until you close it there.', takeOver('Use it here'))
        : ed.lock?.state === 'paused'
          ? h('div', { class: 'ce-lock-band paused', role: 'status' }, '⏸ Paused: you were away, so the card is free for others. Click or type anywhere to keep editing.')
          : null;
    const top = h('header', { class: 'ce-top' },
      h('nav', { class: 'ce-crumbs' },
        h('button', { class: 'link', type: 'button', onclick: () => go('sets') }, 'Card editor'), ' / ',
        h('button', { class: 'link', type: 'button', onclick: () => { sets.pick(w.type === 'Core' ? 'Core' : w.type === 'Stage' ? 'Stage' : setOf(w.id)); go('sets'); } }, setName), ' / ',
        h('strong', {}, `${w.id} ${w.name || 'New card'}`),
        h('span', { class: `ce-badge ${TYPE_BADGE[w.type]}${w.type === 'Action' || w.type === 'Equipment' || w.type === 'Assist' ? ` c-bg-${w.color}` : ''}` }, w.type.toUpperCase()),
        wipBadge(w.id), lockMini),
      h('div', { class: 'ce-top-actions' }, lockChip, readyToggle(w), reviewNav(w),
        w.type === 'Core' ? null : h('button', { class: 'ghost ce-act', type: 'button', title: 'Undo', 'aria-label': 'Undo', disabled: !ed.undo.length, onclick: undo }, h('span', { class: 'ce-act-ico', 'aria-hidden': 'true' }, '↶'), h('span', { class: 'ce-act-lbl' }, 'Undo')),
        h('button', { class: 'ghost ce-act', type: 'button', title: 'Close', 'aria-label': 'Close', onclick: () => go(ed.from) }, h('span', { class: 'ce-act-ico', 'aria-hidden': 'true' }, '✕'), h('span', { class: 'ce-act-lbl' }, 'Close')),
        h('button', { class: 'primary', type: 'button', disabled: !canWrite() || lockBusy(), onclick: () => env.guard(saveDraft) }, 'Save')));
    return h('div', { class: 'ce-full' }, top, lockBand, readOnlyNote(),
      h('div', { class: `ce-cols${WIDE.includes(w.type) ? ' wide' : ''}`, onwheel: wheelToColumn }, renderSide(), renderCentre(), renderForm()));
  }

  function reviewNav(w) {
    const ids = reviewOrder(w.id);
    const i = ids.indexOf(w.id);
    if (i < 0) return null;
    return h('span', { class: 'ce-review' },
      h('button', { class: 'ghost', type: 'button', disabled: i <= 0, title: 'Previous card (←)', onclick: () => step(-1) }, '‹'),
      h('span', { class: 'small muted' }, `${i + 1} / ${ids.length}`),
      h('button', { class: 'ghost', type: 'button', disabled: i >= ids.length - 1, title: 'Next card (→)', onclick: () => step(1) }, '›'));
  }

  // ☐ Ready / ☑ Ready among the bar's actions (Marko 2026-11-15, in place of Looks good and the form's STATUS switch;
  // a toggle, not a tag): a click flips it like any edit (Undo, Save). Publish lets only Ready cards go; a Core has none.
  function readyToggle(w) {
    if (w.type === 'Core') return null;
    const ready = (w.status ?? 'draft') === 'done';
    // In the app's own buttons: off like Undo and Close (ghost), on like Save but green (Marko 2026-11-15).
    return h('button', { class: `ce-ready-toggle ${ready ? 'on' : 'ghost'}`, type: 'button', role: 'switch', 'aria-checked': String(ready), disabled: !canWrite() || lockBusy(),
      title: ready ? 'Ready: Publish may take it. Click if it is not finished after all' : 'Not ready: it waits under Publish › Not ready. Click when the card is finished',
      onclick: () => { snap(true); w.status = ready ? 'draft' : 'done'; changed(); env.render(); } },
      h('span', { class: 'ce-ready-mark', 'aria-hidden': 'true' }, '✓'), 'Ready');
  }

  // Podaci preko servera su samo za gledanje: spremanje, upload i Objava trebaju otvoren zajednički folder.
  function readOnlyNote() {
    if (canWrite()) return null;
    return h('div', { class: 'ce-readonly' },
      h('span', {}, h('strong', {}, 'View only.'), ' The cards come through the server, so Save, art upload and Publish are off. Open the shared folder to edit (Chrome or Edge on a computer).'),
      env.openFolder ? h('button', { class: 'primary', type: 'button', onclick: () => env.openFolder() }, 'Open the folder') : null);
  }

  // ---------- lijevi paneli ----------

  function panel(title, ...kids) {
    return h('section', { class: 'ce-panel' }, h('h3', {}, title), ...kids);
  }

  function renderSide() {
    const w = ed.work;
    ed.checkBox = h('ul', { class: 'ce-checks' });
    // Stanje u naslovu kao kod fx (Marko 2026-11-06): Ready ili Not ready; klik pokaže i zelene kvačice.
    // Cijeli red naslova je gumb (mobitel: dodir bilo gdje u redu), pilula je samo oznaka.
    const toggleOks = () => { ed.oksOpen = !ed.oksOpen; queueDraw(); };
    // The head folds the block (Marko 2026-11-15); the pill shows or hides the green ticks.
    ed.checkPill = h('span', { class: 'ce-fx-state ce-check-pill', role: 'button', tabindex: 0, title: 'Show or hide what is fine', onclick: e => { e.stopPropagation(); toggleOks(); },
      onkeydown: e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); toggleOks(); } } });
    ed.checkHead = h('div', { class: 'ce-panel-head ce-check-head' }, h('h3', {}, 'Checks'), ed.checkPill);
    const parts = [h('section', { class: 'ce-panel' }, ed.checkHead, ed.checkBox)];
    // Same frame, Hero cards, Terrain i Cores su maknuti 2026-11-06: tip je u obrascu, evolucije ispod Aliasa.
    if (w.type !== 'Core') parts.push(fxPanel(w));
    if (PORTRAIT.includes(w.type)) { ed.balBox = h('div', {}); parts.push(ed.balBox); } else ed.balBox = null;
    parts.push(notesPanel(w));
    // Every block folds (Marko 2026-11-15): an arrow at the start of its head, remembered per block; Balance folds
    // by its own title (a details element).
    foldable(parts[0], 'checks');
    if (w.type !== 'Core') foldable(parts[1], 'fx');
    foldable(parts[parts.length - 1], 'notes');
    return h('aside', { class: 'ce-side' }, ...parts);
  }

  const FOLD_KEY = 'evil-boce-fold-';
  function foldable(section, key) {
    const head = section?.firstElementChild;
    if (!head) return section;
    let folded = false;
    try { folded = localStorage.getItem(FOLD_KEY + key) === '1'; } catch {}
    section.classList.add('ce-foldable');
    section.classList.toggle('folded', folded);
    const flip = () => {
      const now = !section.classList.contains('folded');
      section.classList.toggle('folded', now);
      chev.setAttribute('aria-expanded', String(!now));
      try { localStorage.setItem(FOLD_KEY + key, now ? '1' : '0'); } catch {}
    };
    const chev = h('button', { class: 'ce-panel-fold', type: 'button', 'aria-label': 'Fold', 'aria-expanded': String(!folded), onclick: e => { e.stopPropagation(); flip(); } }, '▾');
    let row = head;
    if (head.tagName === 'H3') {
      row = h('div', { class: 'ce-panel-head' }, chev, head.cloneNode(true));
      head.replaceWith(row);
    } else head.prepend(chev);
    // The whole head folds (Marko 2026-11-15), not only the arrow; what else is in it (a pill, a button) keeps its own click.
    row.classList.add('ce-fold-head');
    row.addEventListener('click', e => { if (e.target.closest('button, a, input, textarea, select, [role="button"]')) return; flip(); });
    return section;
  }

  // ---------- token karte (GDD 10, Marko 2026-11-14) ----------
  // Token je Action koju stvara druga karta ili ability heroja; kod mu je kod te karte s brojem (DQ1-010-1).
  // Nikad ne ide u deck, pakete ni Draft, nije sastojak comba; izgled mu daje renderer (ljubičast, sat i TOKEN).
  const isTokenId = id => String(id ?? '').split('-').length > 2;
  const makerOf = id => String(id).split('-').slice(0, 2).join('-');
  const tokensOf = makerId => allCards().filter(c => c.token && c.id.startsWith(`${makerId}-`) && !isTokenId(c.id.slice(makerId.length + 1)))
    .sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  const MAKER_TYPES = ['Hero', 'Evolution', 'Action', 'Equipment', 'Assist'];

  function nextTokenId(makerId) {
    const ids = [...db().cards.map(c => c.id), ...Object.keys(ed.drafts?.cards ?? {}), ed.work?.id ?? ''];
    const nums = ids.filter(id => id.startsWith(`${makerId}-`)).map(id => Number(id.slice(makerId.length + 1))).filter(Number.isFinite);
    return `${makerId}-${Math.max(0, ...nums) + 1}`;
  }

  // New token for this card: an Action in the maker's colour (a hero's token plays with the hero's colour).
  function newToken(maker) {
    if (ed.dirty && !confirm('Discard the unsaved changes to this card?')) return;
    const color = maker.color && (COLORS.includes(maker.color) || maker.color === 'None') ? maker.color : 'None';
    startCard(nextTokenId(maker.id), { name: '', type: 'Action', token: true, color, cost: 1, bonus: {}, traits: ['General'], text: '' });
  }

  function tokensRow(w) {
    if (w.token) {
      const maker = allCards().find(c => c.id === makerOf(w.id));
      return h('p', { class: 'small muted ce-token-of' }, h('span', { class: 'ce-st token' }, 'TOKEN'), ' of ',
        maker ? h('button', { class: 'link accent', type: 'button', onclick: () => go(maker.id) }, `${maker.name || 'New card'} (${maker.id})`) : `${makerOf(w.id)} (no such card yet)`,
        '. It waits beside the hand, is gone at the end of the turn, and is never in a deck.');
    }
    if (!MAKER_TYPES.includes(w.type) || ['Stage', 'Core', 'CB'].includes(setOf(w.id))) return null;
    const list = tokensOf(w.id);
    return h('small', { class: 'muted ce-evos' }, 'Tokens: ',
      list.length ? list.map((t, i) => [i ? ', ' : null, h('button', { class: 'link', type: 'button', onclick: () => go(t.id) }, `${t.name || 'New token'} (${t.id})`)]).flat().filter(Boolean) : 'none',
      ' · ', h('button', { class: 'link accent', type: 'button', disabled: !canWrite(), title: 'An Action this card makes: "Create a … Token." in its text', onclick: () => newToken(w) }, 'New token'));
  }

  // Evolucije heroja i nova evolucija (bila je ploča Hero cards lijevo; Marko 2026-11-06).
  function heroEvos(w) {
    const evos = db().cards.filter(c => c.type === 'Evolution' && !c.deleted && c.hero === w.name);
    return h('small', { class: 'muted ce-evos' }, 'Evolutions: ',
      evos.length ? evos.map((e, i) => [i ? ', ' : null, h('button', { class: 'link', type: 'button', onclick: () => go(e.id) }, e.name.split(/,\s*/).pop())]).flat().filter(Boolean) : 'none yet',
      ' · ', h('button', { class: 'link accent', type: 'button', onclick: () => newCard(setOf(w.id), 'Evolution', { hero: w.name, color: w.color }) }, 'New evolution'));
  }

  // Claude prijedlog fx-a (Marko 2026-11-03): zahtjev ide u data/fx-requests/ u zajedničkom folderu, server na
  // Markovom računalu (server/fx-claude.mjs, ključ samo tamo) pita Claude i vrati odgovor u data/fx-claude/.
  const CLAUDE_REQ = id => `data/fx-requests/${id}.json`;
  const CLAUDE_RES = id => `data/fx-claude/${id}.json`;
  const claudeText = w => toWords(w.text ?? '');

  function claudeRequest(c, text, at) {
    const p = env.state.fxProposals?.cards?.[c.id];
    const base = db().cards.find(x => x.id === c.id);
    // Čitanje parsera vrijedi samo za objavljeni tekst; server ga uspoređuje, Claude ga ne vidi.
    const read = p && !p.unparsed?.length && base && toWords(base.text ?? '') === text ? (p.read ?? '') : undefined;
    return { id: c.id, name: c.name, type: c.type, color: c.color, bonusColors: c.bonusColors, hero: c.hero, cost: c.cost,
      bonus: c.bonus && Object.keys(c.bonus).length ? c.bonus : undefined, traits: c.traits, text, read, intent: intentOf(c.id) || undefined,
      tokens: tokensOf(c.id).map(t => ({ id: t.id, name: t.name })).filter(t => t.name) || undefined, token: c.token || undefined, who: who(), at };
  }

  async function askClaude(w) {
    await syncIntent(w);
    const at = new Date().toISOString();
    const req = claudeRequest(w, claudeText(w), at);
    await fs.writeFile(store().root, CLAUDE_REQ(w.id), JSON.stringify(req, null, 2) + '\n');
    ed.claude[w.id] = { waiting: true, at, res: ed.claude[w.id]?.res ?? null };
    env.render();
    pollClaude(w.id, at);
  }

  // Čeka odgovor (Syncthing ga donese za par sekundi dok je Markov server upaljen); najviše ~10 minuta.
  async function pollClaude(id, at, tries = 0) {
    const res = await readJson(CLAUDE_RES(id), null).catch(() => null);
    const st = ed.claude[id];
    if (!st || st.at !== at) return;
    if (res && res.askedAt === at) {
      ed.claude[id] = { waiting: false, at, res };
      if (ed.id === id) env.render();
      return;
    }
    if (tries > 200) { ed.claude[id] = { ...st, waiting: false, late: true }; if (ed.id === id) env.render(); return; }
    setTimeout(() => pollClaude(id, at, tries + 1), 3000);
  }

  async function loadClaude(id) {
    if (ed.claude[id] || !store()) return;
    ed.claude[id] = { waiting: false, at: null, res: null };
    const res = await readJson(CLAUDE_RES(id), null).catch(() => null);
    if (res) { ed.claude[id] = { waiting: false, at: res.askedAt, res }; if (ed.id === id) env.render(); }
  }

  // Check text (Marko 2026-11-06): Claude čita tekst karte po vodiču za tekst i predloži prijepis.
  // Isti put kao Ask Claude: zahtjev u data/text-requests/, odgovor iz data/text-claude/ (server/fx-claude.mjs).
  const TEXT_REQ = id => `data/text-requests/${id}.json`;
  const TEXT_RES = id => `data/text-claude/${id}.json`;

  async function checkText(w) {
    await syncIntent(w);
    const at = new Date().toISOString();
    const req = { id: w.id, name: w.name, type: w.type, color: w.color, bonusColors: w.bonusColors, hero: w.hero, cost: w.cost,
      bonus: w.bonus && Object.keys(w.bonus).length ? w.bonus : undefined, traits: w.traits, abilityNames: w.abilityNames, text: claudeText(w),
      intent: intentOf(w.id) || undefined, who: who(), at };
    delete ed.answers[w.id];
    delete ed.ctOpen[w.id];
    await fs.writeFile(store().root, TEXT_REQ(w.id), JSON.stringify(req, null, 2) + '\n');
    ed.textCheck[w.id] = { waiting: true, at, res: ed.textCheck[w.id]?.res ?? null };
    env.render();
    pollText(w.id, at);
  }

  async function pollText(id, at, tries = 0) {
    const res = await readJson(TEXT_RES(id), null).catch(() => null);
    const st = ed.textCheck[id];
    if (!st || st.at !== at) return;
    if (res && res.askedAt === at) {
      ed.textCheck[id] = { waiting: false, at, res };
      if (ed.id === id) env.render();
      return;
    }
    if (tries > 200) { ed.textCheck[id] = { ...st, waiting: false, late: true }; if (ed.id === id) env.render(); return; }
    setTimeout(() => pollText(id, at, tries + 1), 3000);
  }

  async function loadTextCheck(id) {
    if (ed.textCheck[id] || !store()) return;
    ed.textCheck[id] = { waiting: false, at: null, res: null };
    const res = await readJson(TEXT_RES(id), null).catch(() => null);
    if (res) { ed.textCheck[id] = { waiting: false, at: res.askedAt, res }; if (ed.id === id) env.render(); }
  }

  function checkTextButton(w, label = 'Check text') {
    // In the CLAUDE box head (2026-11-14); the head's click folds the box, this button only asks.
    const st = ed.textCheck[w.id] ?? {};
    return h('button', { class: 'ce-add-effect ce-text-ask', type: 'button', disabled: !canWrite() || st.waiting || (!claudeText(w).trim() && !intentNow(w)),
      title: !canWrite() ? 'Open the shared folder to ask Claude' : 'Claude reads the text and the Intent against the text guide on Marko\'s computer, asks what is unclear and proposes a rewrite',
      onmousedown: e => e.preventDefault(), onclick: () => env.guard(() => checkText(w)) }, st.waiting ? '✦ Checking…' : `✦ ${label}`);
  }

  // ---------- Intent (Marko 2026-11-14) ----------
  // What the card should do in the author's own words: above the text, sent with Check text and Ask Claude.
  // Check text asks what is unclear in rounds; the answers go into the Intent as lines, and the next round reads them.

  const intentOf = id => ed.intent?.cards?.[id]?.text ?? '';
  // The Intent as it is on screen now (typed but not saved yet: it survives a redraw), or as saved.
  const intentNow = w => (ed.intentDraft?.id === w.id ? ed.intentDraft.value.trim() : intentOf(w.id));

  async function saveIntent(id, text, forText) {
    const fresh = await readJson(INTENT_PATH, { cards: {} });
    fresh.cards ??= {};
    const t = String(text ?? '').trim();
    const before = fresh.cards[id]?.text ?? '';
    if (!t) delete fresh.cards[id];
    else fresh.cards[id] = { text: t, who: who() || '', at: new Date().toISOString(), forText };
    await writeJson(INTENT_PATH, fresh);
    ed.intent = fresh;
    if (ed.intentDraft?.id === id) ed.intentDraft = null;
    if (before !== t) await logHistory(id, t ? 'intent changed' : 'intent cleared').catch(() => {});
  }

  // "Still holds": the Intent stays as it is, now confirmed against the card text as it is.
  async function intentHolds(id, forText) {
    const fresh = await readJson(INTENT_PATH, { cards: {} });
    const e = fresh.cards?.[id];
    if (!e) return;
    e.forText = forText;
    await writeJson(INTENT_PATH, fresh);
    ed.intent = fresh;
  }

  // Before asking Claude: what is typed in the Intent box is saved first (the button does not take the focus away).
  async function syncIntent(w) {
    const now = intentNow(w);
    if (canWrite() && now !== intentOf(w.id)) await saveIntent(w.id, now, claudeText(w));
  }

  // The card text changed after the Intent was confirmed against it (only once the card is saved: not while typing).
  function intentStale(w) {
    const e = ed.intent?.cards?.[w.id];
    return !!e && e.forText != null && !ed.dirty && e.forText !== claudeText(w);
  }

  // ---------- the CLAUDE box under the text (Marko 2026-11-14, mockup docs/private/mockups/text-block) ----------
  // Everything that goes to Claude and comes back, in one box: the status and the one Check text in its head, the
  // Intent as one line (a click opens it), the proposal as a diff on the card text with Use this under it, and the
  // questions. Folding and opening the Intent happen in place (no redraw).

  // Word diff of the whole text, line breaks kept: [['=', w] | ['+', w] | ['-', w] | ['\n']].
  function fullDiff(a, b) {
    const split = t => String(t).replace(/\n/g, ' \n ').split(/ +/).filter(Boolean);
    const x = split(a);
    const y = split(b);
    const L = Array.from({ length: x.length + 1 }, () => new Array(y.length + 1).fill(0));
    for (let i = x.length - 1; i >= 0; i--) for (let j = y.length - 1; j >= 0; j--) L[i][j] = x[i] === y[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
    const out = [];
    let i = 0;
    let j = 0;
    while (i < x.length || j < y.length) {
      if (i < x.length && j < y.length && x[i] === y[j]) { out.push(['=', x[i]]); i++; j++; } else if (j < y.length && (i >= x.length || L[i][j + 1] > L[i + 1][j])) { out.push(['+', y[j]]); j++; } else { out.push(['-', x[i]]); i++; }
    }
    return out.map(o => (o[1] === '\n' ? (o[0] === '-' ? null : ['\n']) : o)).filter(Boolean);
  }

  function diffView(a, b) {
    const parts = [];
    for (const o of fullDiff(a, b)) {
      if (o[0] === '\n') { parts.push(h('br')); continue; }
      parts.push(o[0] === '=' ? o[1] : h(o[0] === '+' ? 'ins' : 's', {}, o[1]), ' ');
    }
    return h('div', { class: 'ce-diff' }, parts);
  }

  // What Claude's last Check text means now: { r, st, stale, intentChanged, inUse, questions, label, tone }.
  function claudeState(w) {
    loadTextCheck(w.id);
    const st = ed.textCheck[w.id] ?? {};
    const r = st.res;
    const out = { st, r, stale: false, intentChanged: false, inUse: false, questions: [] };
    if (st.waiting) return { ...out, label: 'checking…', tone: 'none' };
    if (!r) return { ...out, label: 'not asked yet', tone: 'none' };
    if (r.error) return { ...out, label: 'could not check', tone: 'bad' };
    const now = claudeText(w);
    out.inUse = r.verdict === 'changes' && now.trim() === String(r.text).trim();
    out.intentChanged = (r.askedIntent ?? '') !== intentOf(w.id);
    out.stale = (!out.inUse && r.askedText !== now) || out.intentChanged;
    out.questions = out.stale ? [] : r.questions ?? [];
    if (out.stale) return { ...out, label: 'check again', tone: 'check' };
    if (out.questions.length) return { ...out, label: `${out.questions.length} ${out.questions.length === 1 ? 'question' : 'questions'}`, tone: 'check' };
    if (r.verdict === 'changes' && !out.inUse) return { ...out, label: 'rewrite ready', tone: 'claude' };
    return { ...out, label: '✓ follows the guide', tone: 'ok' };
  }

  function claudeBox(w) {
    const cs = claudeState(w);
    const r = cs.r;
    // Open unless everything is done; a click on the head is remembered for this answer.
    const auto = cs.tone !== 'ok';
    const open = ed.ctOpen[w.id]?.at === (r?.at ?? null) ? ed.ctOpen[w.id].open : auto;
    const toggle = ev => {
      if (ev.target.closest('button.ce-add-effect')) return;
      const box = ev.currentTarget.closest('.ce-claude-panel');
      const now = box.classList.contains('closed');
      ed.ctOpen[w.id] = { at: r?.at ?? null, open: now };
      box.classList.toggle('closed', !now);
      ev.currentTarget.setAttribute('aria-expanded', String(now));
    };
    const head = h('div', { class: 'ce-claude-head', role: 'button', tabindex: 0, 'aria-expanded': String(open), onclick: toggle,
      onkeydown: e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle(e); } } },
      h('span', { class: 'ce-fold-chev', 'aria-hidden': 'true' }, '▾'), h('span', { class: 'ce-claude-title' }, 'CLAUDE'),
      h('span', { class: `ce-fx-state ${cs.tone}` }, cs.label), checkTextButton(w));
    const body = h('div', { class: 'ce-claude-body' }, intentLine(w), ...answerParts(w, cs));
    return h('section', { class: `ce-claude-panel${open ? '' : ' closed'}` }, head, body);
  }

  // The Intent: one line; a click opens the box to write in (in place), Done saves it.
  function intentLine(w) {
    const e = ed.intent?.cards?.[w.id];
    const text = e?.text ?? '';
    const typed = ed.intentDraft?.id === w.id ? ed.intentDraft.value : null;
    const shown = (typed ?? text).trim();
    const lines = shown.split('\n').filter(l => l.trim());
    const stale = intentStale(w);
    const about = 'What the card should do, in your own words (any language). Players never see it; Claude gets it with Check text and Ask Claude. The fx is still made from the card text.';
    const summary = h('span', { class: `ce-intent-say${lines.length ? '' : ' muted'}` }, lines.length ? lines[0] : 'What should the card do? (any language)');
    const more = h('span', { class: 'small muted' }, lines.length > 1 ? `+${lines.length - 1} ${lines.length === 2 ? 'line' : 'lines'}` : '');
    const line = h('button', { class: 'ce-intent-line', type: 'button', title: about, disabled: !canWrite() && !text,
      onclick: () => { line.hidden = true; edit.hidden = false; area.focus(); } },
      h('span', { class: 'ce-intent-tag' }, 'INTENT'), summary, more, h('span', { class: 'small muted ce-intent-hint' }, canWrite() ? 'click to edit' : ''));
    const area = h('textarea', { class: 'ce-intent-text', rows: Math.min(10, Math.max(3, lines.length + 1)), value: typed ?? text, disabled: !canWrite(),
      placeholder: 'What the card should do, in your own words (any language). Claude asks what is unclear.',
      oninput: ev => { ed.intentDraft = { id: w.id, value: ev.target.value }; } });
    const done = () => env.guard(async () => { await saveIntent(w.id, area.value, claudeText(w)); env.render(); });
    const edit = h('div', { class: 'ce-intent-edit', hidden: true },
      h('div', { class: 'ce-intent-row' }, h('span', { class: 'ce-intent-tag' }, 'INTENT'), h('span', { class: 'ce-hint-i', title: about }, 'ⓘ'),
        e ? h('small', { class: 'muted' }, `${e.who || '–'} · ${when(e.at)}`) : null,
        h('button', { class: 'ghost ce-intent-done', type: 'button', disabled: !canWrite(), onclick: done }, 'Done')),
      area);
    // Typed but not saved yet (a redraw came in between): open, so it is not lost from sight.
    if (typed != null && typed !== text) { line.hidden = true; edit.hidden = false; }
    const parts = [line, edit];
    if (stale) parts.push(h('div', { class: 'ce-intent-stale small' },
      h('span', {}, h('strong', {}, 'The card text changed after the Intent was written.'), ' Does it still hold? Claude gets both.'),
      h('div', { class: 'ce-intent-row' },
        h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), onclick: () => env.guard(async () => { await intentHolds(w.id, claudeText(w)); env.render(); }) }, 'Still holds'))));
    return h('div', { class: 'ce-intent-wrap' }, parts);
  }

  // Claude's answer: what it says about the text, as a diff with Use this, the reasons, and the questions.
  function answerParts(w, cs) {
    const { st, r } = cs;
    const out = [];
    if (st.waiting) out.push(h('p', { class: 'small muted' }, 'Waiting for Claude. Marko\'s computer answers while its Card Studio server runs; the request waits in the folder otherwise.'));
    if (st.late) out.push(h('p', { class: 'small warn' }, 'No answer yet. Is the server on Marko\'s computer running? The request is still in the folder.'));
    if (!r) {
      if (!st.waiting) out.push(h('p', { class: 'small muted' }, 'Check text reads the text and the Intent against the text guide, asks what is unclear and proposes the text.'));
      return out;
    }
    if (r.error) { out.push(h('p', { class: 'small warn' }, `Claude could not check the text: ${r.error}`)); return out; }
    if (cs.stale) out.push(h('p', { class: 'small warn' }, cs.intentChanged ? 'Asked with another Intent: Check text again.' : 'Asked about an older text: Check text again.'));
    const use = () => {
      snap(true); w.text = toTokens(r.text); if (w.fx && w.fxStatus !== 'check') w.fxStatus = 'check'; changed(); env.render();
      // The text was written from this Intent: the Intent holds for it.
      if (intentOf(w.id) && (r.askedIntent ?? '') === intentOf(w.id)) intentHolds(w.id, claudeText(w)).catch(() => {});
    };
    if (r.verdict === 'changes' && !cs.inUse) {
      const still = avoidWarnings(ed.guide, r.text);
      out.push(
        diffView(toTokens(claudeText(w)), toTokens(r.text)),
        h('div', { class: 'ce-intent-row' },
          h('button', { class: 'ce-prop-use', type: 'button', disabled: cs.stale, title: cs.stale ? 'Check again: the text or the Intent changed' : 'Put this text on the card; the fx then waits for a new confirm', onclick: use }, 'Use this'),
          h('button', { class: 'ce-prop-use', type: 'button', disabled: cs.stale || !canWrite() || lockBusy(), title: 'Put this text on the card and ask Claude for its fx',
            onclick: () => env.guard(async () => { use(); await askClaude(w); }) }, 'Use this and ask for fx')),
        r.issues?.length ? h('ul', { class: 'small ce-text-issues' }, r.issues.map(i => h('li', {}, i.quote ? h('q', {}, i.quote) : null, ` ${i.problem}`, i.rule ? h('span', { class: 'muted' }, ` (${i.rule})`) : null))) : null,
        still.length ? h('p', { class: 'small warn' }, 'Still against the guide: ', still.join(' · ')) : null);
    } else if (!cs.stale) {
      out.push(h('p', { class: 'small ok' }, cs.inUse ? '✓ Claude\'s text is on the card.' : '✓ The text follows the guide and says what the Intent says.'));
    }
    if (r.notes) out.push(h('p', { class: 'small' }, r.notes));
    if (cs.questions.length) out.push(questionsBox(w, r, cs.questions));
    return out.filter(Boolean);
  }

  // Pitanja jednog kruga: polje za odgovor po pitanju, "Not sure yet" ga preskoči (Claude ga pita opet).
  function questionsBox(w, r, questions) {
    const a = ed.answers[w.id]?.at === r.at ? ed.answers[w.id] : (ed.answers[w.id] = { at: r.at, text: {}, skip: {} });
    const open = questions.filter((q, i) => !a.skip[i] && !(a.text[i] ?? '').trim()).length;
    const left = h('span', { class: 'small muted' }, open ? `${open} without an answer: asked again next round` : '');
    const refreshLeft = () => {
      const n = questions.filter((q, i) => !a.skip[i] && !(a.text[i] ?? '').trim()).length;
      left.textContent = n ? `${n} without an answer: asked again next round` : '';
    };
    const save = async () => {
      const lines = questions.map((q, i) => (!a.skip[i] && (a.text[i] ?? '').trim() ? `${q} → ${a.text[i].trim()}` : null)).filter(Boolean);
      if (!lines.length) throw new Error('Answer at least one question first.');
      const before = intentNow(w);
      await saveIntent(w.id, [before, ...lines].filter(Boolean).join('\n'), claudeText(w));
      delete ed.answers[w.id];
      await checkText(w);
    };
    return h('div', { class: 'ce-questions' },
      h('p', { class: 'small' }, 'For the author: the answers go into the Intent.'),
      h('ol', { class: 'ce-q-list' }, questions.map((q, i) => h('li', { class: a.skip[i] ? 'skip' : '' },
        h('span', { class: 'small' }, q),
        h('div', { class: 'ce-intent-row' },
          h('input', { value: a.text[i] ?? '', disabled: !!a.skip[i] || !canWrite(), placeholder: a.skip[i] ? 'Skipped: asked again next round' : 'Answer…',
            oninput: e => { a.text[i] = e.target.value; refreshLeft(); } }),
          h('button', { class: 'link small', type: 'button', onclick: () => { a.skip[i] = !a.skip[i]; if (a.skip[i]) a.text[i] = ''; env.render(); } }, a.skip[i] ? 'Answer it' : 'Not sure yet'))))),
      h('div', { class: 'ce-intent-row' },
        h('button', { class: 'ce-q-save', type: 'button', disabled: !canWrite() || lockBusy(), onclick: () => env.guard(save) }, 'Save answers to Intent and check again'),
        left));
  }

  const normFx = x => String(x ?? '').split('\n').map(l => l.trim().replace(/\s+/g, ' ').toUpperCase()).filter(Boolean).join('\n');
  // Claude i igra čitaju tekst drukčije, ali je potvrđeni fx jednak jednom od njih: Marko je presudio, nema više
  // što uspoređivati (Marko 2026-11-07: Conqueror's Haki i Elbaph stajali su na popisu bez izlaza).
  const claudeSettled = (c, r) => !!c.fx && c.fxStatus !== 'check' && (normFx(c.fx) === normFx(r?.fx) || normFx(c.fx) === normFx(r?.read));

  // Gumb Ask Claude: uvijek isti natpis i isto mjesto (desno u redu ispod fx kutije).
  function askClaudeButton(w) {
    const st = ed.claude[w.id] ?? {};
    return h('button', { class: 'ce-fx-ask', type: 'button', disabled: !canWrite() || st.waiting || !claudeText(w).trim(),
      title: !canWrite() ? 'Open the shared folder to ask Claude' : st.res ? 'Ask Claude again for this text' : 'Claude proposes the fx on Marko\'s computer; it comes back here in a few seconds',
      onclick: () => env.guard(() => askClaude(w)) }, st.waiting ? '✦ Asking…' : '✦ Ask Claude');
  }

  // Claudeov prijedlog ispod fx kutije. Ako je već u kutiji, jedan redak; napomene se otvaraju na klik.
  function claudeBlock(w, box, gameShown = false) {
    loadClaude(w.id);
    const st = ed.claude[w.id] ?? {};
    const r = st.res;
    const parts = [];
    if (st.waiting) parts.push(h('p', { class: 'small muted' }, 'Waiting for Claude. Marko\'s computer answers while its Card Studio server runs; the request waits in the folder otherwise.'));
    if (st.late) parts.push(h('p', { class: 'small warn' }, 'No answer yet. Is the server on Marko\'s computer running? The request is still in the folder.'));
    if (r?.error) parts.push(h('p', { class: 'small warn' }, `Claude could not answer: ${r.error}`));
    else if (r) {
      const intentChanged = (r.askedIntent ?? '') !== intentOf(w.id);
      const stale = (r.askedText != null && r.askedText !== claudeText(w)) || intentChanged;
      const use = () => { snap(true); w.fx = r.fx || undefined; w.fxStatus = r.fx ? 'check' : undefined; box.value = r.fx ?? ''; changed(); env.render(); };
      const inUse = !!r.fx && normFx(w.fx) === normFx(r.fx);
      const src = h('span', { class: 'ce-prop-src' }, 'Claude', r.who ? ` · ${r.who}` : '');
      const staleLine = stale ? h('p', { class: 'small warn' }, r.askedText != null && r.askedText !== claudeText(w) ? 'For an older text: ask again.'
        : r.askedIntent == null ? 'Asked before this card had an Intent: ask again.' : 'Asked with another Intent: ask again.') : null;
      const gameRead = env.state.fxProposals?.cards?.[w.id]?.read;
      // Sklopi se samo kad je prijedlog igre na ekranu (njegov Use this ostaje); inače bi karta ostala bez Use this.
      const sameAsGame = gameShown && !!r.fx && !!gameRead && normFx(r.fx) === normFx(gameRead) && !stale;
      const notes = [
        r.unsure?.length ? h('ul', { class: 'small ce-claude-unsure' }, r.unsure.map(u => h('li', {}, u))) : null,
        r.notes ? h('p', { class: 'small' }, r.notes) : null,
        r.agree === true ? h('p', { class: 'small ok' }, '✓ Claude reads the card the same way as the game.') : null,
      ].filter(Boolean);
      const warns = [
        r.problems?.length ? h('p', { class: 'small warn' }, 'The game would not read: ', r.problems.map(p => `${p.line} (${p.problem})`).join(' · ')) : null,
        r.agree === false && !claudeSettled(w, r) ? h('p', { class: 'small warn' }, 'Claude reads it differently from the game: compare the two and fix the text, or use Claude\'s fx.') : null,
        r.agree === false && claudeSettled(w, r) ? h('p', { class: 'small muted' }, 'Claude reads it differently from the game; the confirmed fx settles it.') : null,
        r.extensions?.length ? h('p', { class: 'small' }, 'Needs new words, on the ', h('button', { class: 'link', type: 'button', onclick: () => go('wishlist') }, 'fx wishlist'), ': ', r.extensions.map(x => x.word).join(' · ')) : null,
      ].filter(Boolean);
      const noteList = n => n.length ? h('details', { class: 'ce-prop-notes' }, h('summary', { class: 'small' }, `▸ ${n.length === 1 ? '1 note' : n.length + ' notes'}`), n) : null;
      if (inUse || sameAsGame) {
        parts.push(h('div', { class: 'ce-claude ce-prop-same' },
          h('p', { class: 'ce-prop-head' }, src, h('span', { class: 'small ok' }, inUse ? '✓ in the box' : '✓ same as the game')),
          staleLine, ...warns, noteList(notes)));
      } else {
        parts.push(h('div', { class: 'ce-claude' },
          h('p', { class: 'ce-prop-head' }, src, h('button', { class: 'ce-prop-use', type: 'button', disabled: !r.fx || !!r.problems?.length || stale,
            title: !r.fx ? 'Claude proposes no fx' : r.problems?.length ? 'The game would not read it' : stale ? 'Ask again: the text changed' : 'Put it in the fx box, still to be confirmed', onclick: use }, 'Use this')),
          staleLine,
          h('pre', { class: 'ce-fx-code ce-claude-fx' }, r.fx || '(no fx needed)'),
          ...warns, ...notes));
      }
    }
    return parts.length ? h('div', { class: 'ce-claude-box' }, parts) : null;
  }

  // Kartice na vrhu Words: Tags | Phrases (Marko 2026-11-03) | fx (2026-11-15).
  function pageTabs(want) {
    // Words: Tags, Phrases i fx (Marko 2026-11-15: ono što čeka igru ide s Publisha ovamo, adresa wishlist).
    const wishes = (ed.wishlist?.items ?? []).filter(i => i.status === 'open').length;
    const groups = [
      [['traits', 'Tags', 0], ['guide', 'Phrases', 0], ['wishlist', 'fx', wishes]],
    ];
    const cur = want === 'words' ? 'traits' : want;
    const group = groups.find(g => g.some(([k]) => k === cur));
    if (!group) return null;
    // Same tabs as Publish (Marko 2026-11-15: the grey switch did not look like the app).
    return h('div', { class: 'ce-pub-tabs ce-page-tabs', role: 'tablist' }, group.map(([k, label, n]) => h('button', { type: 'button', role: 'tab', 'aria-selected': String(k === cur),
      class: `t-wait${k === cur ? ' on' : ''}`, onclick: () => go(k) }, label, n ? h('span', { class: 'n', title: 'Words waiting for the game' }, String(n)) : null)));
  }

  // fx wishlist (Marko 2026-11-03): riječi koje fx jeziku fale, iz Claude prijedloga (server/fx-claude.mjs).
  // Glagoli, uvjeti i mete čekaju Claude Code da ih ugradi u igru ("napravi wishlist"); "rule" je pitanje za Marka.
  async function setWish(key, status) {
    const fresh = await readJson(WISH_PATH, { version: 1, items: [] });
    const item = fresh.items.find(i => i.key === key);
    if (!item) return;
    item.status = status;
    item.by = who();
    item.changedAt = new Date().toISOString();
    await writeJson(WISH_PATH, fresh);
    ed.wishlist = fresh;
    env.render();
  }

  // Claude pročita svaku kartu sam i server usporedi s parserom igre (Marko 2026-11-03).
  const checkable = () => allCards().filter(c => c.type !== 'Core' && !c.deleted && (c.text ?? '').trim());

  async function loadAllClaude() {
    if (ed.claudeAllAt && Date.now() - ed.claudeAllAt < HEARTBEAT_MS) return;
    ed.claudeAllAt = Date.now();
    await Promise.all(checkable().map(async c => {
      const res = await readJson(CLAUDE_RES(c.id), null).catch(() => null);
      if (res && !ed.claude[c.id]?.waiting) ed.claude[c.id] = { waiting: false, at: res.askedAt, res };
    }));
    env.render();
  }

  async function checkAll() {
    const todo = checkable().filter(c => {
      const r = ed.claude[c.id]?.res;
      return !ed.claude[c.id]?.waiting && (!r || r.error || r.askedText !== toWords(c.text ?? ''));
    });
    if (!todo.length) { env.toast('Every card already has an answer from Claude for its current text.'); return; }
    if (!confirm(`Ask Claude to read ${todo.length} cards (about ${Math.max(1, Math.round(todo.length * 0.03))} USD)? The answers come in while the server on Marko's computer runs.`)) return;
    for (const c of todo) {
      const at = new Date().toISOString();
      await fs.writeFile(store().root, CLAUDE_REQ(c.id), JSON.stringify(claudeRequest(c, toWords(c.text ?? ''), at), null, 2) + '\n');
      ed.claude[c.id] = { waiting: true, at, res: ed.claude[c.id]?.res ?? null };
      pollClaude(c.id, at);
    }
    env.toast(`${todo.length} cards asked.`);
    env.render();
  }

  function claudeCheckSection() {
    loadAllClaude();
    const cards = checkable();
    const st = c => ed.claude[c.id] ?? {};
    const differ = cards.filter(c => st(c).res?.agree === false && !claudeSettled(c, st(c).res));
    const settled = cards.filter(c => st(c).res?.agree === false && claudeSettled(c, st(c).res)).length;
    const agree = cards.filter(c => st(c).res?.agree === true).length;
    const waiting = cards.filter(c => st(c).waiting).length;
    const unchecked = cards.filter(c => !st(c).res && !st(c).waiting).length;
    return h('section', { class: 'ce-claude-check' },
      h('h3', {}, 'Claude reads every card'),
      h('p', { class: 'small' }, h('span', { title: 'Claude writes the fx of each card from its text on its own, and the server compares it with what the game reads.' }, `${agree} agree · ${differ.length} differ${settled ? ` · ${settled} settled by a confirmed fx` : ''} · ${waiting} waiting · ${unchecked} not checked`)),
      h('div', { class: 'ce-actions' },
        h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), title: 'Cards without fx get the game\'s reading, to confirm while you review them', onclick: () => env.guard(fillAllFx) }, 'Write fx on every card'),
        h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), onclick: () => env.guard(checkAll) }, 'Check every card with Claude')),
      differ.length ? h('div', { class: 'ce-wish-list' }, differ.map(c => h('article', { class: 'ce-wish' },
        h('div', { class: 'ce-wish-head' }, h('button', { class: 'link', type: 'button', onclick: () => go(c.id) }, `${c.id} ${c.name}`)),
        h('p', { class: 'small muted' }, toWords(c.text ?? '')),
        h('div', { class: 'ce-fx-pair' },
          h('div', {}, h('p', { class: 'small muted' }, 'The game reads'), h('pre', { class: 'ce-fx-code ce-claude-fx' }, st(c).res.read || '(nothing)')),
          h('div', {}, h('p', { class: 'small muted' }, 'Claude reads'), h('pre', { class: 'ce-fx-code ce-claude-fx' }, st(c).res.fx || '(nothing)')))))) : null);
  }

  function renderWishlist() {
    if (Date.now() - (ed.wishAt ?? 0) > HEARTBEAT_MS) {
      ed.wishAt = Date.now();
      readJson(WISH_PATH, { version: 1, items: [] }).then(x => { if (JSON.stringify(x) !== JSON.stringify(ed.wishlist)) { ed.wishlist = x; env.render(); } }).catch(() => {});
    }
    const items = ed.wishlist?.items ?? [];
    const card = (it, label) => h('article', { class: `ce-wish ${it.status}` },
      h('div', { class: 'ce-wish-head' }, h('code', {}, it.word), h('span', { class: 'ce-chip' }, label), it.status !== 'open' ? h('span', { class: 'muted small' }, it.status === 'done' ? 'in the game' : 'not needed') : null),
      h('p', {}, it.meaning),
      h('p', { class: 'small muted' }, it.why),
      h('ul', { class: 'small ce-wish-cards' }, it.cards.map(c => h('li', {}, h('button', { class: 'link', type: 'button', onclick: () => go(c.id) }, `${c.id} ${c.name ?? ''}`), c.fx ? [' ', h('code', {}, c.fx)] : null))),
      it.status === 'open' ? h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), onclick: () => env.guard(() => setWish(it.key, 'dismissed')) }, 'Not needed')
        : it.status === 'dismissed' ? h('button', { class: 'link small', type: 'button', disabled: !canWrite(), onclick: () => env.guard(() => setWish(it.key, 'open')) }, 'Back on the list') : null);
    const open = items.filter(i => i.status === 'open');
    const words = open.filter(i => i.kind !== 'rule');
    const rules = open.filter(i => i.kind === 'rule');
    const closed = items.filter(i => i.status !== 'open');
    // Prazni dijelovi se ne pokazuju (Marko 2026-11-06).
    return h('section', { class: 'ce-wishlist', id: 'ce-wish' },
      h('header', { class: 'ce-page-head' }, h('div', {}, h('h1', {}, 'fx'), h('p', { class: 'muted' }, 'What the game runs: each card\'s fx, and the words the fx language does not have yet.'))),
      claudeCheckSection(),
      words.length || rules.length ? h('p', { class: 'muted small' }, 'Words the fx language does not have yet, from Ask Claude. Verbs, conditions and targets wait for Claude Code ("napravi wishlist"); rules are questions for Marko.')
        : h('p', { class: 'muted small' }, 'No words wait for the game.'),
      words.length ? [h('h3', {}, `For the game (${words.length})`), h('div', { class: 'ce-wish-list' }, words.map(i => card(i, i.kind)))] : null,
      rules.length ? [h('h3', {}, `Rule questions for Marko (${rules.length})`), h('div', { class: 'ce-wish-list' }, rules.map(i => card(i, 'rule')))] : null,
      closed.length ? h('details', {}, h('summary', {}, `Done or not needed (${closed.length})`), h('div', { class: 'ce-wish-list' }, closed.map(i => card(i, i.kind)))) : null);
  }

  // Publish i ono što čeka igru na jednoj stranici; s adrese wishlist stranica skoči na taj dio.
  // Words › fx: Claude reads every card and the fx wishlist (words the game does not have yet, rule questions).
  function renderFxPage() {
    return h('div', { class: 'ce-page ce-fx-page' }, renderWishlist());
  }

  // fx za igru (Marko 2026-11-05): svaka karta ima zapisan fx i igra radi po njemu. Parser igre (data/fx-proposals.json,
  // nakon Objave) i Claude samo predlažu; čovjek potvrdi. Promjena teksta fx vrati na nepotvrđen.
  function gameProposal(w, p, textChanged) {
    if (textChanged || !p || p.unparsed?.length || !(w.text ?? '').trim()) return null;
    const read = p.read ?? '';
    if (w.fx && normFx(w.fx) === normFx(read)) return null;
    return h('div', { class: 'ce-claude ce-prop-game' },
      h('p', { class: 'ce-prop-head' }, h('span', { class: 'ce-prop-src' }, 'The game reads'),
        h('button', { class: 'ce-prop-use', type: 'button', disabled: !canWrite() || !read, title: 'Put it in the fx box, still to be confirmed', onclick: () => { snap(true); w.fx = read; w.fxStatus = 'check'; changed(); env.render(); } }, 'Use this')),
      h('pre', { class: 'ce-fx-code ce-claude-fx' }, read || '(nothing to run)'));
  }

  function fxPanel(w) {
    const p = env.state.fxProposals?.cards?.[w.id];
    const textChanged = !w.new && toWords(w.text ?? '') !== (ed.base.type === 'Stage' ? stripTerrain(ed.base.text) : ed.base.text ?? '');
    const fit = el => { el.style.height = 'auto'; el.style.height = `${el.scrollHeight + 2}px`; };
    const box = h('textarea', { class: 'ce-fx-code ce-fx-box', rows: 2, spellcheck: false, placeholder: 'Empty until you pick a proposal (Use this). Ask Claude reads the effect text by itself: no need to copy it here.', value: w.fx ?? '',
      oninput: e => { snap(); fit(e.target); w.fx = e.target.value.trim() ? e.target.value : undefined; w.fxStatus = w.fx ? 'ok' : undefined; changed(); } });
    requestAnimationFrame(() => fit(box));
    const bad = w.fx ? fxProblems(w.fx) : [];
    const state = !w.fx ? 'none' : bad.length ? 'bad' : w.fxStatus === 'check' ? 'check' : 'ok';
    const pill = h('span', { class: `ce-fx-state ${state}` }, { none: 'No fx', bad: 'Not fx', check: 'To confirm', ok: '✓ Confirmed' }[state]);
    // Objašnjenje samo kad treba nešto napraviti; potvrđen fx ima samo pločicu.
    const hint = state === 'ok' ? null : state === 'bad' ? `This box is for fx, not card text (${bad.map(p => p.problem).join(' · ')}). Clear it, then Ask Claude: it reads the effect text by itself.`
      : state === 'check' ? 'Check it against the text, then Confirm fx (or edit it) and Save.'
      : textChanged || w.new ? 'Tap Ask Claude: it reads the effect text by itself. The game\'s proposal comes after Publish.'
        : !p ? 'No report from the game for this card yet.' : p.unparsed?.length ? `The game does not understand: ${p.unparsed.join(' · ')}` : null;
    return h('section', { class: 'ce-panel ce-fx-panel' },
      h('div', { class: 'ce-panel-head' }, h('h3', {}, 'fx for the game'), pill),
      box,
      h('div', { class: 'ce-fx-actions' },
        state === 'check' ? h('button', { class: 'publish', type: 'button', onclick: () => { snap(true); w.fxStatus = 'ok'; changed(); env.render(); } }, 'Confirm fx')
          : state === 'bad' ? h('button', { class: 'ghost', type: 'button', title: 'Empty the fx box', onclick: () => { snap(true); w.fx = undefined; w.fxStatus = undefined; changed(); env.render(); } }, 'Clear')
            : h('span'),
        askClaudeButton(w)),
      hint ? h('p', { class: 'small muted' }, hint) : null,
      gameProposal(w, p, textChanged),
      claudeBlock(w, box, !!gameProposal(w, p, textChanged)),
      !w.new && env.openEffect ? h('button', { class: 'link ce-fx-more', type: 'button', onclick: () => env.openEffect(w.id) }, 'What the game reads →') : null);
  }

  // Jednom za sve: kartama bez fx-a upiše prijedlog igre (nepotvrđen); potvrđuje se tijekom pregleda.
  // Karta s potvrđenim čitanjem (fxRead, prijašnji način) dobije fx potvrđen.
  async function fillAllFx() {
    const fresh = await readDrafts();
    fresh.cards ??= {};
    const props = env.state.fxProposals?.cards ?? {};
    let n = 0;
    let confirmed = 0;
    for (const base of db().cards) {
      if (base.deleted || base.type === 'Core' || !(base.text ?? '').trim()) continue;
      const d = fresh.cards[base.id] ?? {};
      if ('text' in d && toWords(d.text ?? '') !== (base.text ?? '')) continue;
      if (d.fx ?? base.fx) continue;
      const p = props[base.id];
      if (!p || p.unparsed?.length || !p.read) continue;
      if (ed.locks[base.id] && lockState(ed.locks[base.id], who()) === 'other') continue;
      const was = d.fxRead ?? base.fxRead;
      const ok = was != null && was === p.read;
      const nd = { ...d, fx: p.read, fxStatus: ok ? 'ok' : 'check', updated: new Date().toISOString(), who: who() || undefined };
      delete nd.fxRead;
      fresh.cards[base.id] = nd;
      n++;
      if (ok) confirmed++;
    }
    if (!n) { env.toast('Every card with a game reading already has an fx.'); return; }
    await writeJson(DRAFTS_PATH, fresh);
    ed.drafts = fresh;
    env.toast(`fx written on ${n} ${n === 1 ? 'card' : 'cards'} (${n - confirmed} to confirm). They go into the game with the next Publish.`);
    env.render();
  }

  function notesPanel(w) {
    const notes = [...(ed.notes?.cards?.[w.id] ?? [])];
    if (typeof ed.base.notes === 'string' && ed.base.notes) notes.unshift({ who: '', at: '', text: ed.base.notes });
    const hist = [...(ed.history?.cards?.[w.id] ?? [])].reverse();
    // Objave prije povijesti editora: iz changelog.json (bez imena).
    const published = (env.state.changelog?.entries ?? []).filter(e => e.cards?.some(c => c.id === w.id)).map(e => ({ at: e.date, what: `published v${e.version}` })).reverse();
    // Samo zadnja objava (Marko 2026-11-06): svaka karta je u svakoj Objavi, pa su te stavke gušile prave promjene.
    const PUB = /^(published v\d+|Publish undone)/;
    const merged = [...hist, ...published.filter(p => !hist.some(x => x.what === p.what))];
    const lastPub = merged.find(x => /^published v\d+/.test(x.what));
    const lines = merged.filter(x => !PUB.test(x.what) || x === lastPub).slice(0, 8);
    const input = h('input', { placeholder: 'Add a note…', onkeydown: e => { if (e.key === 'Enter') { e.preventDefault(); env.guard(() => addNote(e.target.value)); } } });
    return panel('Notes & history',
      ...notes.map(n => h('div', { class: 'ce-note' }, h('p', { class: 'small' }, h('strong', { class: n.who === 'Marko' ? 'red' : '' }, n.who || 'Note'), n.at ? ` · ${when(n.at)}` : ''), h('p', {}, n.text))),
      canWrite() ? input : null,
      ...lines.map(x => h('p', { class: 'small' }, h('strong', {}, x.who || ''), `${x.who ? ' · ' : ''}${when(x.at)} · ${x.what}`)),
      lines.length || notes.length ? null : h('p', { class: 'small muted' }, 'Nothing yet.'));
  }

  // Move an unpublished card to another code in its set (Marko 2026-11-14; js/card-move.js). Everything
  // kept under the code follows it: the draft, notes, history, Intent and Claude's answers; Combo drafts follow by ingredient.
  // Art files keep their names (the draft points at them). Computer with the folder only: Claude's answers are files.
  async function moveCard() {
    if (!canPublish()) throw new Error('Moving a card needs the shared folder open on a computer (Chrome or Edge).');
    if (ed.dirty) throw new Error('Save the card first, then move it.');
    const from = ed.id;
    const set = setOf(from);
    const answer = prompt(`Move ${from} to which code? A number, e.g. 3 for ${set}-003.\nThe unpublished cards in between move one place; published cards keep their codes.`, '');
    if (answer == null || !answer.trim()) return;
    const to = targetCode(set, answer);
    if (!to) throw new Error(`"${answer.trim()}" is not a code in set ${set}. Type a number, e.g. 3.`);
    await env.assertFresh();
    const fresh = await readDrafts();
    await readLocks();
    const published = new Set(db().cards.filter(c => setOf(c.id) === set).map(c => c.id));
    const unpublished = new Set(Object.entries(fresh.cards ?? {}).filter(([id, d]) => d?.new && setOf(id) === set && !published.has(id)).map(([id]) => id));
    const plan = planMove({ from, to, published, unpublished });
    if (!plan.size) { env.toast(`${from} is already there.`); return; }
    const moved = [...plan.keys()];
    const busy = moved.find(id => ed.locks[id]);
    if (busy) throw new Error(`${ed.locks[busy].who} has ${busy} open. Try again after they close it.`);
    const usedBy = db().cards.find(c => !c.deleted && (c.ingredients ?? []).some(id => plan.has(id)));
    if (usedBy) throw new Error(`${usedBy.id} is published and uses ${usedBy.ingredients.find(id => plan.has(id))}, so that code cannot change.`);
    for (const id of moved) {
      for (const path of [CLAUDE_REQ(id), TEXT_REQ(id)]) {
        if ((await fs.readText(store().root, path).catch(() => null)) != null) throw new Error(`Claude is still reading ${id}. Try again in a minute.`);
      }
    }
    const others = moved.filter(id => id !== from).map(id => `${id} → ${plan.get(id)}`);
    if (!confirm(`Move ${from} to ${to}?${others.length ? `\n\nThese move one place:\n${others.join('\n')}` : ''}`)) return;
    fresh.cards = moveDrafts(fresh.cards, plan);
    await writeJson(DRAFTS_PATH, fresh);
    ed.drafts = fresh;
    for (const path of [NOTES_PATH, HISTORY_PATH, INTENT_PATH]) {
      const doc = await readJson(path, { cards: {} });
      doc.cards = renameKeys(doc.cards, plan);
      await writeJson(path, doc);
      if (path === NOTES_PATH) ed.notes = doc; else if (path === HISTORY_PATH) ed.history = doc; else ed.intent = doc;
    }
    ed.answers = renameKeys(ed.answers, plan);
    // Claude's answers in two steps (a temporary name first), so a card moving into a code never meets the old file.
    for (const res of [CLAUDE_RES, TEXT_RES]) {
      for (const id of moved) await fs.moveFile(store().root, res(id), `${res(plan.get(id))}.moving`);
      // An answer left under a new code by a card thrown away earlier is not this card's.
      for (const id of moved) await fs.removeFile(store().root, res(plan.get(id))).catch(() => {});
      for (const id of moved) await fs.moveFile(store().root, `${res(plan.get(id))}.moving`, res(plan.get(id)));
    }
    ed.claude = renameKeys(ed.claude, plan);
    ed.textCheck = renameKeys(ed.textCheck, plan);
    ed.pubOff = new Set([...ed.pubOff].map(id => plan.get(id) ?? id));
    ed.thumbs.clear();
    for (const id of moved) await logHistory(plan.get(id), `code changed from ${id}`).catch(() => {});
    env.toast(`${from} is now ${to}${others.length ? `; ${others.length} ${others.length === 1 ? 'card' : 'cards'} moved one place` : ''}.`);
    releaseLock();
    ed.id = null;
    ed.work = null;
    env.go(to);
  }

  async function addNote(text) {
    if (!text.trim()) return;
    const fresh = await readJson(NOTES_PATH, { cards: {} });
    (fresh.cards[ed.id] ??= []).push({ who: who() || '', at: new Date().toISOString(), text: text.trim() });
    await writeJson(NOTES_PATH, fresh);
    ed.notes = fresh;
    env.render();
  }

  async function logHistory(id, what) {
    const fresh = await readJson(HISTORY_PATH, { cards: {} });
    (fresh.cards[id] ??= []).push({ who: who() || '', at: new Date().toISOString(), what });
    if (fresh.cards[id].length > 50) fresh.cards[id] = fresh.cards[id].slice(-50);
    await writeJson(HISTORY_PATH, fresh);
    ed.history = fresh;
  }

  // ---------- sredina: karta ----------

  function renderCentre() {
    const w = ed.work;
    const views = w.type === 'Core' ? [] : w.type === 'Combo' ? [['card', 'Card'], ['old', 'Old vs new']] : HEROISH.includes(w.type) ? [['card', 'Card'], ['board', 'On the board'], ['old', 'Old vs new']]
      : w.type === 'Stage' ? [['card', 'Card'], ['map', 'On the map'], ['old', 'Old vs new']] : [['card', 'Card'], ['old', 'Old vs new']];
    if (!views.some(([k]) => k === ed.view)) ed.view = 'card';
    const wide = WIDE.includes(w.type);
    // Isto platno između crtanja: novo prazno platno bi na trenutak bljesnulo.
    const [cw, chh] = wide ? [2100, 1500] : [1500, 2100];
    if (!ed.canvas || ed.canvas.width !== cw || ed.canvas.height !== chh) ed.canvas = h('canvas', { width: cw, height: chh });
    ed.stage = h('div', { class: `ce-stage${wide ? ' wide' : ''}${ed.artMode ? ' art-mode' : ''}${w.type === 'Core' ? ' core' : ''}` });
    ed.warn = [];
    queueDraw();
    const fileIn = h('input', { type: 'file', accept: 'image/png,image/jpeg,image/webp', hidden: true, onchange: e => env.guard(() => uploadArt(e.target.files[0])) });
    const buttons = w.type === 'Core' ? [] : ed.artMode ? [] : [
      h('button', { class: 'ghost', type: 'button', disabled: !ed.artFor && !w.art, onclick: startArt }, 'Edit art'),
      h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), title: 'Choose a picture, or drag one from a folder onto the card', onclick: () => fileIn.click() }, w.art ? 'Replace art' : 'Add art'),
      w.type === 'Stage' ? null : h('button', { class: 'ghost', type: 'button', onclick: () => { if (!leaveOk()) return; ed.work = null; ed.id = null; env.toast('Remove background works on a plain background colour: save the PNG there, then Replace art.'); env.openTab('tools'); } }, 'Remove background'),
    ];
    // Rijetki gumbi u izborniku ⋯ (Marko 2026-11-06): Remove background, Duplicate, Download PNG. Radnje nad kartom
    // (Marko 2026-11-15): Move to another code i Throw away / Discard su tu, ne u Notes & history; i Core ga dobije.
    if (!ed.artMode) {
      const rare = buttons.splice(2).filter(Boolean);
      rare.push(h('button', { class: 'ghost', type: 'button', title: 'A new card with the next code in this set', onclick: duplicate }, 'Duplicate'),
        h('button', { class: 'ghost', type: 'button', onclick: downloadPng }, 'Download PNG'),
        // Ponovno crtanje objavljene karte (Marko 2026-11-07): Objava crta samo nacrte, a slika u bazi
        // ostane stara kad se promijeni samo renderer (Onigashima: "most Power" kao ikona).
        h('button', { class: 'ghost', type: 'button', title: 'Draw the published picture again with the current card look (no draft needed)',
          disabled: !canPublish() || w.new || !!ed.drafts?.cards?.[w.id], onclick: () => env.guard(redrawPicture) }, 'Redraw picture'));
      if (w.new && !w.token && ed.drafts?.cards?.[w.id]) rare.push(h('button', { class: 'ghost', type: 'button', disabled: !canPublish() || lockBusy(),
        title: canPublish() ? 'Give this card another code in its set; the unpublished cards in between move one place' : 'Moving a card needs the shared folder open on a computer',
        onclick: () => env.guard(moveCard) }, 'Move to another code…'));
      if (ed.drafts?.cards?.[w.id]) rare.push(h('div', { class: 'ce-more-sep', 'aria-hidden': 'true' }),
        h('button', { class: 'ghost ce-more-danger', type: 'button', disabled: !canWrite() || lockBusy(), onclick: () => env.guard(discardDraft) },
          w.new ? 'Throw away this new card' : 'Discard the unpublished changes'));
      const menu = h('div', { class: 'ce-more-menu', hidden: true }, rare);
      const close = () => { menu.hidden = true; };
      for (const b of rare) b.addEventListener('click', close);
      buttons.push(h('div', { class: 'ce-more' }, h('button', { class: 'ghost', type: 'button', title: 'More: Remove background, Duplicate, Download PNG, Redraw picture', 'aria-haspopup': 'menu',
        onclick: e => { e.stopPropagation(); menu.hidden = !menu.hidden; if (!menu.hidden) setTimeout(() => document.addEventListener('click', close, { once: true })); } }, 'More ▾'), menu));
    }
    return artDrop(h('section', { class: 'ce-centre' },
      views.length > 1 && !ed.artMode ? h('div', { class: 'ce-views' }, views.map(([k, label]) => h('button', { type: 'button', class: ed.view === k ? 'active' : '', onclick: e => {
        ed.view = k;
        for (const b of e.currentTarget.parentNode.children) b.classList.toggle('active', b === e.currentTarget);
        paintStage(cardOf(ed.work));
      } }, label))) : null,
      ed.stage,
      ed.artMode ? h('div', { class: 'ce-zoom' }, h('span', {}, 'ZOOM'),
        h('input', { type: 'range', min: 0.5, max: 3, step: 0.01, value: w.artCrop.zoom, oninput: e => { snap(); w.artCrop = { ...w.artCrop, zoom: Number(e.target.value) }; changed(); } }),
        h('button', { class: 'ghost', type: 'button', title: 'Put the art back as it was (Esc)', onclick: cancelArt }, 'Cancel'),
        h('button', { class: 'primary', type: 'button', onclick: () => { ed.artBefore = null; ed.artMode = false; env.render(); } }, 'Done')) : null,
      ed.artMode ? h('p', { class: 'muted small ce-hint' }, HEROISH.includes(w.type) ? 'Drag the art to move it, scroll to zoom. The frame covers the right edge of the art. Esc cancels.' : 'Drag the art to move it, scroll to zoom. The dashed line is the art window. Esc cancels.') : null,
      w.type === 'Core' ? h('p', { class: 'muted small ce-hint' }, 'Image only, no frame') : null,
      buttons.length ? h('div', { class: 'ce-art-buttons' }, buttons, fileIn) : null,
      ed.agency ? null : h('p', { class: 'warn small' }, 'Agency FB is not on this computer: a stand-in font is shown. PNGs are made on a computer that has it.')));
  }

  // Slika povučena iz foldera na kartu (stupac sa slikom) radi isto što i Replace art (Marko 2026-11-15).
  const draggingFile = e => [...(e.dataTransfer?.types ?? [])].includes('Files');
  function artDrop(el) {
    if (!canWrite() || ed.artMode) return el;
    let depth = 0;
    const off = () => { depth = 0; el.classList.remove('ce-drop-over'); };
    el.addEventListener('dragenter', e => { if (!draggingFile(e)) return; e.preventDefault(); depth++; el.classList.add('ce-drop-over'); });
    el.addEventListener('dragover', e => { if (!draggingFile(e)) return; e.preventDefault(); e.dataTransfer.dropEffect = 'copy'; });
    el.addEventListener('dragleave', () => { if (--depth <= 0) off(); });
    el.addEventListener('drop', e => {
      if (!draggingFile(e)) return;
      e.preventDefault();
      e.stopPropagation();
      off();
      const file = [...e.dataTransfer.files].find(f => /^image\/(png|jpeg|webp)$/.test(f.type));
      env.guard(() => { if (!file) throw new Error('Drop a PNG, JPEG or WebP picture.'); return uploadArt(file); });
    });
    return el;
  }
  // Slika ispuštena drugdje na stranici karte ne smije otvoriti sliku u pregledniku (i izgubiti nespremljeno).
  window.addEventListener('dragover', e => { if (ed.id && draggingFile(e)) e.preventDefault(); });
  window.addEventListener('drop', e => { if (ed.id && draggingFile(e)) e.preventDefault(); });

  // Više izmjena u istom trenutku daje jedno crtanje.
  function queueDraw() {
    if (ed.frame) return;
    ed.frame = 1;
    setTimeout(async () => {
      ed.frame = 0;
      await draw().catch(e => console.error(e));
    }, 0);
  }

  async function draw() {
    const w = ed.work;
    if (!w || !ed.canvas) return;
    const card = cardOf(w);
    const tpl = await templateFor(card);
    // Forma heroja čita zadanu boju pozadine iz predloška: kad predložak stigne prvi put, nacrta se iznova.
    const first = ed.tpl?.name !== tpl.name;
    ed.tpl = tpl;
    if (first && HEROISH.includes(w.type) && !w.bg) { env.render(); return; }
    if (ed.artFor !== w.art) {
      const want = w.art;
      ed.artFor = want;
      const url = want ? await store().dataUrl(want) : null;
      const img = url ? await loadImage(url).catch(() => null) : null;
      if (ed.artFor === want) ed.art = img;
    }
    const emblemPath = w.emblem ?? (w.type === 'Evolution' ? heroCard(w)?.emblem ?? ed.drafts?.cards?.[heroCard(w)?.id]?.emblem : null);
    if (ed.emblemFor !== emblemPath) {
      ed.emblemFor = emblemPath;
      const url = emblemPath ? await store().dataUrl(emblemPath) : null;
      ed.emblem = url ? await loadImage(url).catch(() => null) : null;
    }
    if (w !== ed.work) return;
    ed.warn = renderCard(ed.canvas, decorate(card, allCards()), tpl, ed.art, ed.emblem);
    paintStage(card);
    if (ed.checkBox) {
      const all = checks(w, card);
      const li = ([ok, text]) => h('li', { class: ok ? 'ok' : 'bad' }, h('span', { class: 'mark' }, ok ? '✓' : '!'), h('span', {}, text));
      const bad = all.filter(([ok]) => !ok);
      const oks = all.filter(([ok]) => ok);
      ed.checkPill.className = `ce-fx-state ce-check-pill ${bad.length ? 'check' : 'ok'}`;
      ed.checkPill.textContent = bad.length ? '! Not ready' : '✓ Ready';
      ed.checkPill.title = ed.oksOpen ? 'Hide the checks that pass' : `Show the ${oks.length} checks that pass`;
      ed.checkPill.setAttribute('aria-expanded', String(!!ed.oksOpen));
      // Problemi uvijek, prolazne provjere samo kad je pilula otvorena (ostaje otvorena dok se karta crta).
      ed.checkBox.replaceChildren(...bad.map(li), ...(ed.oksOpen ? oks.map(li) : []));
      ed.checkBox.hidden = !bad.length && !ed.oksOpen;
    }
    if (ed.balBox) ed.balBox.replaceChildren(...renderBalance(card));
  }

  const heroCard = w => {
    const name = w.hero;
    const c = db().cards.find(x => x.type === 'Hero' && !x.deleted && x.name === name);
    return c ? merged(c) : null;
  };

  // Pogled u sredini: karta, u ruci, uvećana, stara i nova, ili način uređivanja arta (slika i izvan karte).
  function paintStage(card) {
    const st = ed.stage;
    if (!st) return;
    if (ed.artMode) {
      const c = artCanvas();
      if (c.parentNode !== st) st.replaceChildren(c);
      return;
    }
    const view = ed.view;
    if (view === 'card') { st.replaceChildren(ed.canvas); ed.canvas.className = 'ce-canvas'; return; }
    const scaled = px => {
      const c = h('canvas', { width: px * 2, height: Math.round((px * 2 * ed.canvas.height) / ed.canvas.width) });
      c.style.width = `${px}px`;
      const g = c.getContext('2d');
      g.imageSmoothingQuality = 'high';
      g.drawImage(ed.canvas, 0, 0, c.width, c.height);
      return c;
    };
    const wide = ed.canvas.width > ed.canvas.height;
    if (view === 'hand') st.replaceChildren(h('figure', { class: 'ce-ctx' }, scaled(wide ? 168 : 120), h('figcaption', { class: 'muted small' }, 'Size in the hand')));
    else if (view === 'board') boardView(card).then(c => { if (ed.view === 'board' && ed.stage === st) st.replaceChildren(c); });
    else if (view === 'map') st.replaceChildren(mapView(card));
    else if (view === 'hover') st.replaceChildren(h('figure', { class: 'ce-ctx' }, scaled(wide ? 392 : 280), h('figcaption', { class: 'muted small' }, 'Size when you hover it in the game')));
    else {
      const old = h('img', { class: 'ce-old', alt: 'Published' });
      if (ed.base.image) store().imageUrl(ed.base).then(u => { if (u) old.src = u; });
      st.replaceChildren(h('div', { class: 'ce-oldnew' },
        h('figure', {}, ed.base.image ? old : h('div', { class: 'ce-old empty' }, 'Not published yet'), h('figcaption', { class: 'muted small' }, 'Published')),
        h('figure', {}, scaled(wide ? 360 : 260), h('figcaption', { class: 'muted small' }, 'New'))));
    }
  }

  // Ploča kao u igri: tamni heksi (šiljasti vrh), R polumjer, (cx, cy) središte; vraća središta.
  function hexBoard(g, W, H, R) {
    const dx = Math.sqrt(3) * R;
    const dy = 1.5 * R;
    const centres = [];
    g.fillStyle = '#231e1a';
    g.fillRect(0, 0, W, H);
    for (let row = -1; row * dy < H + R; row++) {
      for (let col = -1; col * dx < W + dx; col++) {
        const x = col * dx + (row % 2 ? dx / 2 : 0);
        const y = row * dy;
        hexPath(g, x, y, R - 1.5);
        g.fillStyle = '#3a312a';
        g.fill();
        centres.push([x, y]);
      }
    }
    return { dx, dy, centres };
  }

  function hexPath(g, x, y, r) {
    g.beginPath();
    for (let i = 0; i < 6; i++) {
      const a = Math.PI / 6 + (i * Math.PI) / 3;
      g[i ? 'lineTo' : 'moveTo'](x + r * Math.cos(a), y + r * Math.sin(a));
    }
    g.closePath();
  }

  // On the board: figurica heroja (sprite iz igre) na heksu s prstenom tima, i ploča heroja kao u igri.
  async function boardView(card) {
    const W = 960;
    const H = 600;
    const c = h('canvas', { class: 'ce-canvas', width: W, height: H });
    const g = c.getContext('2d');
    const R = 46;
    const { dx, dy } = hexBoard(g, W, H, R);
    const row = Math.round(380 / dy);
    const col = Math.round((W / 2 - (row % 2 ? dx / 2 : 0)) / dx);
    const x = col * dx + (row % 2 ? dx / 2 : 0);
    const y = row * dy;
    hexPath(g, x, y, R - 1.5);
    g.fillStyle = '#4a4036';
    g.fill();
    g.strokeStyle = '#2f6bff';
    g.lineWidth = 6;
    g.beginPath();
    g.ellipse(x, y, R * 0.62, R * 0.3, 0, 0, Math.PI * 2);
    g.stroke();
    const base = db().cards.find(b => b.id === card.id);
    const spritePath = card.sprite ?? base?.sprite ?? (card.type === 'Evolution' ? db().cards.find(b => b.type === 'Hero' && b.name === card.hero)?.sprite : null);
    const url = spritePath ? await store().dataUrl(spritePath) : null;
    const sprite = url ? await loadImage(url).catch(() => null) : null;
    if (sprite) {
      const sh = 230;
      const sw = (sprite.width / sprite.height) * sh;
      g.imageSmoothingEnabled = false;
      g.drawImage(sprite, x - sw / 2, y - sh + R * 0.2, sw, sh);
      g.imageSmoothingEnabled = true;
    } else {
      g.fillStyle = '#8d8a85';
      g.font = '600 20px "Barlow Semi Condensed", sans-serif';
      g.textAlign = 'center';
      g.fillText('No standee sprite yet', x, y - R * 1.4);
    }
    // Ploča heroja (lijevo gore), kao u igri: lice s arta, ime, HP kao crtice, statsi.
    const px = 24;
    const py = 24;
    g.fillStyle = 'rgba(12, 12, 12, 0.92)';
    g.fillRect(px, py, 420, 112);
    g.fillStyle = TINTS[card.color] ?? '#f4b62a';
    g.fillRect(px + 416, py, 4, 112);
    // Lice: kvadrat s vrha prozora arta na nacrtanoj karti.
    const win = ed.tpl?.layout?.artWindow;
    if (ed.art && win) g.drawImage(ed.canvas, win[0], win[1], win[2], win[2], px, py, 112, 112);
    g.fillStyle = '#f3efe7';
    g.textAlign = 'left';
    g.font = 'italic 800 30px "Barlow Condensed", sans-serif';
    const title = card.type === 'Evolution' ? (card.name ?? '').split(/,\s*/).pop() : card.name ?? '';
    g.fillText(title, px + 126, py + 38);
    const hp = card.stats?.hp ?? 0;
    for (let i = 0; i < hp; i++) {
      g.fillStyle = '#23b14d';
      g.fillRect(px + 126 + i * (270 / Math.max(hp, 1)), py + 52, 270 / Math.max(hp, 1) - 4, 9);
    }
    g.font = '700 17px "Barlow Condensed", sans-serif';
    const st = card.stats ?? {};
    const parts = [['PWR', st.pwr, '#f4b62a'], ['DMG', st.dmg, '#ff5a4f'], ['RNG', st.rng, '#22c7dd'], ['KB', st.kb, '#7fa2ff']];
    let tx = px + 126;
    for (const [label, v, col] of parts) {
      g.fillStyle = col;
      g.fillText(`${label} ${v ?? '–'}`, tx, py + 92);
      tx += g.measureText(`${label} ${v ?? '–'}`).width + 16;
    }
    return c;
  }

  // On the map: Stage kao cvijet od 7 heksa na ploči, art unutra, žuti obrub i oznaka terena kao u igri.
  function mapView(card) {
    const W = 960;
    const H = 600;
    const c = h('canvas', { class: 'ce-canvas', width: W, height: H });
    const g = c.getContext('2d');
    const R = 58;
    const { dx, dy } = hexBoard(g, W, H, R);
    const row = Math.round(300 / dy);
    const col = Math.round((W / 2 - (row % 2 ? dx / 2 : 0)) / dx);
    const cx = col * dx + (row % 2 ? dx / 2 : 0);
    const cy = row * dy;
    const flower = [[0, 0], [dx, 0], [-dx, 0], [dx / 2, dy], [-dx / 2, dy], [dx / 2, -dy], [-dx / 2, -dy]].map(([ox, oy]) => [cx + ox, cy + oy]);
    g.strokeStyle = '#f4c22f';
    g.lineWidth = 8;
    for (const [x, y] of flower) { hexPath(g, x, y, R); g.stroke(); }
    g.save();
    g.beginPath();
    for (const [x, y] of flower) {
      for (let i = 0; i < 6; i++) {
        const a = Math.PI / 6 + (i * Math.PI) / 3;
        g[i ? 'lineTo' : 'moveTo'](x + R * Math.cos(a), y + R * Math.sin(a));
      }
      g.closePath();
    }
    g.clip();
    const fw = dx * 3;
    const fh = R * 2 + dy * 2;
    if (ed.art) {
      const k = Math.max(fw / ed.art.width, fh / ed.art.height);
      g.drawImage(ed.art, cx - (ed.art.width * k) / 2, cy - (ed.art.height * k) / 2, ed.art.width * k, ed.art.height * k);
    } else {
      g.fillStyle = '#1b1b1f';
      g.fillRect(cx - fw / 2, cy - fh / 2, fw, fh);
    }
    g.fillStyle = 'rgba(0, 0, 0, 0.18)';
    g.fillRect(cx - fw / 2, cy - fh / 2, fw, fh);
    g.restore();
    const tc = { Ice: '#bfe9ff', Mud: '#c89a6a', Ramp: '#f4c22f', Wind: '#c8fff4' }[card.terrain];
    g.textAlign = 'center';
    if (tc) {
      g.font = 'italic 800 34px "Barlow Condensed", sans-serif';
      g.lineWidth = 6;
      g.strokeStyle = 'rgba(0, 0, 0, 0.75)';
      g.strokeText(card.terrain.toUpperCase(), cx, cy + dy + 12);
      g.fillStyle = tc;
      g.fillText(card.terrain.toUpperCase(), cx, cy + dy + 12);
    }
    g.font = 'italic 800 30px "Barlow Condensed", sans-serif';
    g.fillStyle = '#f3efe7';
    g.fillText(card.name ?? '', cx, cy - dy - R - 18);
    return c;
  }

  // Edit art: cijela slika (zatamnjena izvan karte), karta preko nje, isprekidani prozor arta; povlačenje i kotačić.
  function artCanvas() {
    const L = ed.tpl.layout;
    const W = ed.canvas.width;
    const H = ed.canvas.height;
    const M = Math.round(W * 0.07);
    // Jedno platno dok traje Edit art: povlačenje drži pointer na njemu, crta se samo iznova.
    let c = ed.artCv;
    if (!c || c.width !== W + M * 2 || c.height !== H + M * 2) {
      c = ed.artCv = h('canvas', { class: 'ce-canvas ce-artcanvas', width: W + M * 2, height: H + M * 2 });
      hookDrag(c);
    }
    const g = c.getContext('2d');
    g.setLineDash([]);
    g.fillStyle = '#141418';
    g.fillRect(0, 0, c.width, c.height);
    const art = ed.art;
    if (art) {
      const [bx, by, bw, bh] = L.artBox;
      const cr = { x: 0.5, y: 0.5, zoom: 1, ...ed.work.artCrop };
      const s = Math.max(bw / art.width, bh / art.height) * Math.max(cr.zoom, 0.05);
      const dw = art.width * s;
      const dh = art.height * s;
      g.globalAlpha = 0.45;
      g.drawImage(art, M + bx + bw / 2 - cr.x * dw, M + by + bh / 2 - cr.y * dh, dw, dh);
      g.globalAlpha = 1;
    }
    g.drawImage(ed.canvas, M, M);
    const win = L.artWindow ?? L.artBox;
    g.setLineDash([22, 14]);
    g.lineWidth = 5;
    g.strokeStyle = '#f4c22f';
    g.strokeRect(M + win[0], M + win[1], win[2], win[3]);
    return c;
  }

  // Povlačenje arta pomiče izrez, kotačić zumira (samo u načinu Edit art).
  function hookDrag(canvas) {
    let from = null;
    canvas.addEventListener('pointerdown', e => { from = { x: e.clientX, y: e.clientY, crop: { ...ed.work.artCrop } }; snap(true); canvas.setPointerCapture(e.pointerId); });
    canvas.addEventListener('pointermove', e => {
      if (!from || !ed.art) return;
      const scale = canvas.width / canvas.getBoundingClientRect().width;
      const [, , bw, bh] = ed.tpl.layout.artBox;
      const k = Math.max(bw / ed.art.width, bh / ed.art.height) * from.crop.zoom;
      ed.work.artCrop = { ...from.crop, x: from.crop.x - ((e.clientX - from.x) * scale) / (ed.art.width * k), y: from.crop.y - ((e.clientY - from.y) * scale) / (ed.art.height * k) };
      changed();
    });
    canvas.addEventListener('pointerup', () => { from = null; });
    canvas.addEventListener('wheel', e => {
      e.preventDefault();
      snap();
      const z = Math.min(3, Math.max(0.5, ed.work.artCrop.zoom * (e.deltaY < 0 ? 1.05 : 1 / 1.05)));
      ed.work.artCrop = { ...ed.work.artCrop, zoom: z };
      const slider = document.querySelector('.ce-zoom input');
      if (slider) slider.value = z;
      changed();
    }, { passive: false });
  }

  // Sličica karte (Sets, Same frame, Publish): nacrta se jednom po verziji karte i čuva.
  const thumbQueue = [];
  let thumbBusy = false;
  function thumbInto(canvas, card, px) {
    const key = JSON.stringify([card.id, card.type, card.updated ?? card.rev, card.art, card.artCrop, card.text, card.name, card.color, card.cost, card.traits, card.bonus, card.stats, card.emblem, card.coreImage]);
    const wide = WIDE.includes(card.type);
    canvas.width = px * 2;
    canvas.height = Math.round(px * 2 * (wide ? 1500 / 2100 : 2100 / 1500));
    canvas.style.width = `${px}px`;
    const paint = src => canvas.getContext('2d').drawImage(src, 0, 0, canvas.width, canvas.height);
    const done = ed.thumbs.get(key);
    if (done) { paint(done); return; }
    thumbQueue.push({ canvas, card, key, paint });
    pumpThumbs();
  }
  async function pumpThumbs() {
    if (thumbBusy) return;
    thumbBusy = true;
    while (thumbQueue.length) {
      const { card, key, paint } = thumbQueue.shift();
      try {
        if (!ed.thumbs.has(key)) {
          const tpl = await templateFor(card);
          const url = card.art ? await store().dataUrl(card.art) : null;
          const art = url ? await loadImage(url).catch(() => null) : null;
          const eu = card.emblem ? await store().dataUrl(card.emblem) : null;
          const emblem = eu ? await loadImage(eu).catch(() => null) : null;
          const full = document.createElement('canvas');
          renderCard(full, decorate(card, allCards()), tpl, art, emblem);
          const small = document.createElement('canvas');
          small.width = 360;
          small.height = Math.round((360 * full.height) / full.width);
          const g = small.getContext('2d');
          g.imageSmoothingQuality = 'high';
          g.drawImage(full, 0, 0, small.width, small.height);
          ed.thumbs.set(key, small);
        }
        paint(ed.thumbs.get(key));
      } catch (e) {
        console.error(e);
      }
      await new Promise(r => setTimeout(r, 0));
    }
    thumbBusy = false;
  }

  // ---------- combo: utori, tražilica, povećanje (Marko 2026-11-07) ----------

  function comboSlot(k, c, colourName) {
    const label = k === 0 ? 'FIRST CARD · LEFT COLOUR' : 'SECOND CARD · RIGHT COLOUR';
    const open = () => { ed.comboPick = k; ed.comboQ = ''; env.render(); };
    let pic;
    if (c) {
      const cv = h('canvas', { class: 'ce-combo-pic' });
      thumbInto(cv, c, 170);
      pic = h('button', { type: 'button', class: 'ce-combo-pic-btn', title: 'See it big', onclick: () => comboBig(c) }, cv);
    } else {
      pic = h('button', { type: 'button', class: 'ce-combo-pic empty', onclick: open }, '+ Pick a card');
    }
    return h('div', { class: `ce-combo-slot${ed.comboPick === k ? ' picking' : ''}` },
      h('span', { class: 'ce-combo-label' }, label),
      pic,
      c ? h('strong', { class: 'ce-combo-name' }, c.name) : null,
      c ? h('span', { class: 'small muted' }, `${c.id} · ${c.type} · ${colourName(c)}`) : null,
      h('span', { class: 'ce-combo-links' },
        h('button', { type: 'button', class: 'link', onclick: open }, c ? 'Change' : 'Pick'),
        c ? h('button', { type: 'button', class: 'link', onclick: () => go(c.id) }, 'Open card') : null));
  }

  // Tražilica s mrežom sličica: ime, kod ili tekst; samo Action i Assist.
  function comboPicker(pool, ing, colourName, choose) {
    const k = ed.comboPick;
    const grid = h('div', { class: 'ce-combo-grid' });
    const fill = () => {
      const q = (ed.comboQ ?? '').trim().toLowerCase();
      const list = pool.filter(c => !q || `${c.name} ${c.id} ${c.text ?? ''}`.toLowerCase().includes(q));
      grid.replaceChildren(...(list.length ? list.map(c => {
        const cv = h('canvas', { class: 'ce-combo-pic' });
        thumbInto(cv, c, 120);
        return h('button', { type: 'button', class: `ce-combo-option${c.id === ing[k] ? ' current' : ''}`, title: `${c.name} · ${c.id}`, onclick: () => choose(k, c.id) },
          cv, h('span', { class: 'small' }, c.name), h('span', { class: 'small muted' }, `${c.id} · ${colourName(c)}`));
      }) : [h('p', { class: 'small muted' }, 'No Action or Assist card matches.')]));
    };
    // Zatvaranje (Marko 2026-11-07): klik bilo gdje izvan tražilice ili Esc. Bez ponovnog crtanja forme,
    // da klik izvan stigne do polja na koje je kliknut.
    const off = () => { document.removeEventListener('pointerdown', onDown, true); document.removeEventListener('keydown', onKey, true); };
    const close = () => {
      off();
      ed.comboPick = null; ed.comboQ = '';
      box.remove();
      document.querySelectorAll('.ce-combo-slot.picking').forEach(x => x.classList.remove('picking'));
    };
    const onDown = e => {
      if (!box.isConnected) return off();
      if (box.contains(e.target) || e.target.closest?.('.ce-combo-slot, .ce-combo-big')) return;
      close();
    };
    const onKey = e => {
      if (!box.isConnected) return off();
      if (e.key === 'Escape' && !document.querySelector('.ce-combo-big')) { e.preventDefault(); close(); }
    };
    const input = h('input', { type: 'search', placeholder: `${k === 0 ? 'First' : 'Second'} card: name, code or text…`, value: ed.comboQ ?? '',
      'aria-label': k === 0 ? 'Search the first card' : 'Search the second card',
      oninput: e => { ed.comboQ = e.target.value; fill(); } });
    fill();
    const box = h('div', { class: 'ce-combo-picker' },
      h('div', { class: 'ce-combo-picker-head' },
        input),
      grid);
    document.addEventListener('pointerdown', onDown, true);
    document.addEventListener('keydown', onKey, true);
    requestAnimationFrame(() => input.focus());
    return box;
  }

  // Karta velika preko ekrana, s Open card; klik izvan ili Esc zatvara.
  function comboBig(c) {
    const cv = h('canvas', { class: 'ce-combo-big-card' });
    thumbInto(cv, c, 560);
    const close = () => { box.remove(); document.removeEventListener('keydown', onKey); };
    const onKey = e => { if (e.key === 'Escape') close(); };
    const box = h('div', { class: 'ce-combo-big', role: 'dialog', 'aria-label': c.name, onclick: e => { if (e.target === box) close(); } },
      h('div', { class: 'ce-combo-big-inner' }, cv,
        h('div', { class: 'ce-combo-big-actions' },
          h('button', { type: 'button', class: 'primary', onclick: () => { close(); go(c.id); } }, 'Open card'),
          h('button', { type: 'button', class: 'ghost', onclick: close }, 'Close'))));
    document.addEventListener('keydown', onKey);
    document.body.append(box);
  }

  // ---------- desna forma ----------

  function renderForm() {
    const w = ed.work;
    // Prijedlozi tagova: popis tagova i sve što karte već nose (posade, heroji, Yonko…; Marko 2026-11-05), bez Core oznaka.
    // Tag suggestions (Marko 2026-11-14): only descriptive tags (a card's first tag says who plays it and is never
    // offered here, nor any hero's name or alias), the ones this card's set already uses first, with their counts.
    const heroWords = new Set(allCards().filter(c => c.type === 'Hero').flatMap(c => [c.name, ...(c.aliases ?? [])]).map(norm));
    const described = c => (PORTRAIT.includes(c.type) ? (c.traits ?? []).slice(1) : (c.traits ?? []));
    const inSet = {};
    for (const c of allCards()) if (c.type !== 'Core' && c.id !== w.id && setOf(c.id) === setOf(w.id)) for (const t of described(c)) inSet[t] = (inSet[t] ?? 0) + 1;
    const traits = [...new Set([...traitNames(env.state.traits?.traits), ...allCards().filter(c => c.type !== 'Core').flatMap(described)])]
      .filter(t => t && norm(t) !== norm(GENERAL) && !heroWords.has(norm(t)))
      .sort((a, b) => (inSet[b] ?? 0) - (inSet[a] ?? 0) || a.localeCompare(b));
    traits.inSet = inSet;
    traits.setCode = setOf(w.id);
    const set = (k, v) => { snap(true); w[k] = v; changed(); };
    const field = (label, input, extra) => h('label', { class: 'ce-field' }, h('span', {}, label), input, extra ?? null);
    const num = (value, oninput, opts = {}) => h('input', { type: 'number', value: value ?? '', placeholder: '–', oninput, ...opts });
    const code = field('CODE', h('input', { value: w.id, disabled: true }));
    const seg = (items, value, onpick) => h('div', { class: 'ce-seg' }, items.map(([v, label]) => h('button', { type: 'button', class: v === value ? 'active' : '', onclick: () => onpick(v) }, label)));
    const text = textEditor(w);
    let body;
    if (w.type === 'Hero' || w.type === 'Evolution') {
      const evo = w.type === 'Evolution';
      const heroes = db().cards.filter(c => c.type === 'Hero' && !c.deleted);
      const bgVal = w.bg || ed.tpl?.layout?.bg?.[w.color] || '';
      const hc = evo ? heroCard(w) : null;
      const emblemFile = h('input', { type: 'file', accept: 'image/png,image/webp', hidden: true, onchange: e => env.guard(() => uploadEmblem(e.target.files[0])) });
      const unlock = evo && hc ? w.traits.filter(t => !(hc.traits ?? []).some(x => norm(x) === norm(t))) : [];
      body = [
        h('h2', {}, w.type),
        field('NAME', h('input', { value: w.name ?? '', oninput: e => set('name', e.target.value) })),
        evo ? h('div', { class: 'ce-row' },
          field('BASE HERO', h('select', { onchange: e => { const x = heroes.find(c => c.name === e.target.value); snap(true); w.hero = e.target.value; if (x) w.color = x.color; changed(); env.render(); } },
            h('option', { value: '' }, '–'), heroes.map(x => h('option', { value: x.name, selected: x.name === w.hero }, `${x.name} (${x.id})`)))),
          field('LEVEL', h('select', { onchange: e => set('evo', Number(e.target.value)) }, ROMAN.map((r, i) => h('option', { value: i + 1, selected: i + 1 === (w.evo ?? 1) }, r))))) : null,
        h('div', { class: 'ce-row' },
          evo ? field('COST', num(w.cost ?? 0, e => set('cost', e.target.value === '' ? null : Number(e.target.value)), { min: 0, max: 10 }))
            : field('COLOR', h('select', { onchange: e => { set('color', e.target.value); env.render(); } }, COLORS.map(c => h('option', { value: c, selected: c === w.color }, c)))),
          field('BACKGROUND', h('div', { class: 'ce-bg' },
            h('input', { type: 'color', value: /^#[0-9a-f]{6}$/i.test(bgVal) ? bgVal : '#000000', oninput: e => { set('bg', e.target.value); const t = e.target.nextSibling; if (t) t.value = e.target.value; } }),
            h('input', { value: bgVal, placeholder: 'colour default', oninput: e => { if (/^#[0-9a-f]{6}$/i.test(e.target.value)) set('bg', e.target.value); else if (!e.target.value) { snap(true); delete w.bg; changed(); } } }))),
          code),
        tokensRow(w),
        h('div', { class: 'ce-emblem' },
          h('span', { class: 'ce-emblem-dot' }, ed.emblem ? h('img', { src: ed.emblem.src, alt: '' }) : 'LOGO'),
          h('div', {}, h('span', { class: 'small muted' }, 'EMBLEM'),
            h('p', { class: 'small' }, w.emblem ? w.emblem.split('/').pop() : evo ? 'Taken from base hero' : 'None yet', ' · ',
              h('button', { class: 'link accent', type: 'button', disabled: !canWrite(), onclick: () => emblemFile.click() }, w.emblem || evo ? 'replace' : 'add'),
              w.emblem && evo ? [' · ', h('button', { class: 'link', type: 'button', onclick: () => { snap(true); delete w.emblem; ed.emblemFor = undefined; changed(); env.render(); } }, 'use base hero')] : null)),
          emblemFile),
        h('h2', {}, 'Stats'),
        h('div', { class: 'ce-row ce-stats' }, STAT_KEYS.map(([k, label]) => field(h('span', { class: `stat-${k}` }, label), num(w.stats[k], e => set('stats', { ...w.stats, [k]: e.target.value === '' ? undefined : Number(e.target.value) }), { step: k === 'pwr' ? 1000 : 1 })))),
        w.type === 'Hero' ? field('ALIASES', h('input', { value: (w.aliases ?? []).join(', '), placeholder: 'Trish', oninput: e => set('aliases', e.target.value.split(',').map(x => x.trim()).filter(Boolean)) }), h('small', { class: 'muted' }, 'Other names a card\'s first tag may use for this hero.')) : null,
        w.type === 'Hero' ? heroEvos(w) : null,
        h('h2', {}, 'Ability'),
        field('ABILITY NAME', h('input', { value: w.abilityNames?.[0] ?? '', oninput: e => set('abilityNames', [e.target.value, ...(w.abilityNames ?? []).slice(1)]) })),
        ...text,
        h('h2', {}, 'Traits'),
        chips(w, 0, traits, unlock),
        unlock.length ? h('p', { class: 'small muted' }, 'Cards with first tag ', h('strong', { class: 'accent' }, unlock.join(', ')), ' need this evolution in the deck.') : null,
      ];
    } else if (PORTRAIT.includes(w.type)) {
      // Colorless karta: prvi tag smije biti bilo koji heroj.
      body = [
        h('h2', {}, 'Card'),
        w.token ? tokensRow(w) : field('TYPE', seg(PORTRAIT.map(t => [t, t]), w.type, v => { set('type', v); env.render(); })),
        field('NAME', h('input', { value: w.name ?? '', oninput: e => set('name', e.target.value) })),
        h('div', { class: 'ce-row' }, field('COST', num(w.cost ?? 0, e => set('cost', e.target.value === '' ? null : Number(e.target.value)), { min: 0, max: 10 })), code),
        w.token ? null : tokensRow(w),
        field('COLOR', h('div', { class: 'ce-swatches' },
          COLORS.map(c => h('button', { type: 'button', class: `ce-swatch${c === w.color ? ' active' : ''}`, style: `--sw: var(--c-${c})`, title: c, 'aria-label': c, onclick: () => { snap(true); w.color = c; delete w.bonusColors; changed(); env.render(); } })),
          h('button', { type: 'button', class: `ce-swatch colorless${w.color === 'None' ? ' active' : ''}`, style: '--sw: var(--c-colorless)', title: 'Colorless: any hero may play it', 'aria-label': 'Colorless',
            onclick: () => { snap(true); if (w.color !== 'None' && COLORS.includes(w.color)) w.bonusColors = [w.color]; w.color = 'None'; changed(); env.render(); } }, 'C'))),
        w.color === 'None' ? field('BONUS COLOURS (UP TO 2)', h('div', { class: 'ce-bonuscols' }, COLORS.map(c => {
          const on = (w.bonusColors ?? []).includes(c);
          return h('button', { type: 'button', class: `ce-bonuscol${on ? ' on' : ''}`, style: `--sw: var(--c-${c})`, 'aria-pressed': String(on), onclick: () => {
            snap(true);
            const cur = w.bonusColors ?? [];
            w.bonusColors = on ? cur.filter(x => x !== c) : [...cur, c];
            if (!w.bonusColors.length) delete w.bonusColors;
            changed();
            env.render();
          } }, h('span', { class: 'dot' }), c);
        })), h('small', { class: 'muted' }, 'The bonus applies when the hero it is played for is one of these colours. Write it in the text as "Red Bonus: …".')) : null,
        field('BONUS', h('div', { class: 'ce-row ce-stats' }, STAT_KEYS.map(([k, label]) => field(h('span', { class: `stat-${k}` }, label), num(w.bonus[k], e => {
          const b = { ...w.bonus };
          if (e.target.value === '' || Number(e.target.value) === 0) delete b[k]; else b[k] = Number(e.target.value);
          set('bonus', b);
        }, { step: k === 'pwr' ? 1000 : 1 }))))),
        h('h2', {}, 'Effect text'),
        ...text,
        h('h2', {}, 'Tags'),
        firstTagField(w),
        chips(w, 1, traits, []),
      ];
    } else if (w.type === 'Combo') {
      // Sastojci: Action i Assist karte (Equipment i ability heroja nisu dio para), po imenu i kodu.
      const pool = allCards().filter(c => INGREDIENT_TYPES.includes(c.type) && !c.token).sort((a, b) => a.name.localeCompare(b.name));
      const ing = w.ingredients ?? ['', ''];
      const colourName = c => (c.color === 'None' ? 'Colorless' : c.color);
      const choose = (k, id) => { const next = [ing[0] ?? '', ing[1] ?? '']; next[k] = id; ed.comboPick = null; ed.comboQ = ''; set('ingredients', next); env.render(); };
      const setCodes = sets.list().map(s => s.code);
      body = [
        h('h2', {}, 'Combo'),
        field('NAME', h('input', { value: w.name ?? '', oninput: e => set('name', e.target.value) })),
        h('div', { class: 'ce-row' }, code,
          field('EXTRA ENERGY (X)', num(w.extraCost, e => set('extraCost', e.target.value === '' ? null : Number(e.target.value)), { min: 0, max: 10 })),
          field('INTRODUCED IN', h('select', { onchange: e => set('introducedIn', e.target.value) }, h('option', { value: '' }, '–'),
            setCodes.map(c => h('option', { value: c, selected: c === w.introducedIn }, c))))),
        // Dvije karte comboa (Marko 2026-11-07): dva utora, zamjena u sredini; klik na sliku je poveća (s Open card),
        // Change otvara tražilicu s mrežom sličica, Open otvara kartu.
        h('div', { class: 'ce-combo-slots' },
          comboSlot(0, pool.find(x => x.id === ing[0]), colourName),
          h('button', { type: 'button', class: 'ce-combo-swap', disabled: !ing[0] && !ing[1], title: 'Swap the two cards: the first gives the left colour of the rim and the COMBO tag', 'aria-label': 'Swap the two cards',
            onclick: () => { set('ingredients', [ing[1] ?? '', ing[0] ?? '']); env.render(); } }, '⇄'),
          comboSlot(1, pool.find(x => x.id === ing[1]), colourName)),
        ed.comboPick == null ? null : comboPicker(pool, ing, colourName, choose),
        h('p', { class: 'small muted' }, 'Both cards played for two of your heroes in the same battle: the player may pay X more energy to turn them into this card. The rim takes the colours of the two cards. Combo cards never go in a deck or a pack.'),
        h('h2', {}, 'Effect text'),
        ...text,
      ];
    } else if (w.type === 'Stage') {
      body = [
        h('h2', {}, 'Stage'),
        field('NAME', h('input', { value: w.name ?? '', oninput: e => set('name', e.target.value) })),
        h('div', { class: 'ce-row' }, field('TERRAIN', h('select', { onchange: e => set('terrain', e.target.value) }, TERRAINS.map(t => h('option', { value: t, selected: t === (w.terrain ?? 'None') }, t)))), code, introducedField(w)),
        h('p', { class: 'small muted' }, 'No cost, color or tags on Stage cards.'),
        h('h2', {}, 'Effect text'),
        ...text,
      ];
    } else {
      const mode = coreMode(cardOf(w));
      const fileIn = h('input', { type: 'file', accept: 'image/png,image/webp', hidden: true, onchange: e => env.guard(() => uploadArt(e.target.files[0])) });
      const effect = h('input', { class: 'mono', value: w.effect ?? '', oninput: e => { snap(); w.effect = e.target.value; changed(); } });
      const tok = t => { snap(true); const a = effect.selectionStart ?? effect.value.length; effect.value = `${effect.value.slice(0, a)}[${t}]${effect.value.slice(a)}`; w.effect = effect.value; changed(); };
      body = [
        h('h2', {}, 'Core'),
        field('NAME', h('input', { value: w.name ?? '', oninput: e => set('name', e.target.value) })),
        h('div', { class: 'ce-row' }, code, introducedField(w)),
        field('KIND', seg(CORE_KINDS.map(k => [k, k]), w.traits[0], v => { set('traits', [v]); env.render(); })),
        h('h2', {}, 'Effect'),
        h('div', { class: 'ce-tools' }, TOKENS.map(t => h('button', { type: 'button', class: `tok tok-${t.toLowerCase()}`, onclick: () => tok(t) }, `[${t}]`))),
        field('TEXT', effect),
        h('h2', {}, 'Image'),
        seg([['effect', 'Made from the effect'], ['upload', 'Upload image']], mode, v => { if (v === 'upload' && !w.art) { fileIn.click(); return; } set('coreImage', v); env.render(); }),
        h('p', { class: 'small muted' }, 'The editor draws the hexagon with the effect text and icon. Upload replaces it with your own picture.'),
        fileIn,
      ];
    }
    return h('section', { class: `ce-form c-tint-${w.color ?? 'none'}` }, ...body,
      canWrite() ? null : h('p', { class: 'small muted' }, 'Saving needs the shared folder (Chrome or Edge on a computer), or Card Studio opened through Marko\'s computer.'));
  }

  // Tagovi kao čipovi (× makne), polje "Add trait…" s prijedlozima iz popisa traitova. from: 1 = bez prvog taga.
  // Popis prijedloga je naš (Marko 2026-11-05): Brave na Androidu ne pokazuje datalist. Otvori se na dodir,
  // filtrira dok se tipka, dodir ili Enter doda tag.
  // Who may play the card (Marko 2026-11-14, mockup docs/private/mockups/tags): Any hero (General), One hero, or a
  // Trait; a hero or a trait is picked from a list that only holds what the first tag rule allows (heroes of the
  // card's colour with their aliases, any colour for a colorless card; the traits of the trait list). Typing filters
  // the list in place; "A & B" names two heroes.
  function firstTagField(w) {
    const traitList = env.state.traits?.traits ?? [];
    const tag = String(w.traits?.[0] ?? '').trim();
    const k = firstTag({ ...db(), cards: allCards() }, { traits: w.traits }, traitList);
    const kindNow = k.kind === GENERAL ? 'general' : k.kind === HEROES ? 'hero' : k.kind === TRAIT ? 'trait' : null;
    // The list shows while a hero or a trait is being picked and closes once one is (Marko 2026-11-14): then only
    // "Picked: X · change". It opens with One hero / Trait when nothing of that kind is picked, or with change.
    if (ed.ftFor !== w.id) { ed.ftFor = w.id; ed.ftKind = kindNow ?? 'hero'; ed.ftOpen = false; }
    const pickFirst = v => { snap(true); w.traits = [v, ...(w.traits ?? []).slice(1)]; ed.ftOpen = false; changed(); env.render(); };
    const openList = () => { ed.ftOpen = true; ed.ftReveal = true; env.render(); };
    const seg = h('div', { class: 'ce-seg ce-ft-seg' }, [['general', 'Any hero'], ['hero', 'One hero'], ['trait', 'Trait']].map(([key, label]) =>
      h('button', { type: 'button', class: ed.ftKind === key ? 'active' : '', onclick: () => {
        if (ed.ftKind === key && key !== 'general') return;
        ed.ftKind = key;
        if (key === 'general') pickFirst('General');
        else openList();
      } }, label)));
    const out = [h('span', {}, 'WHO MAY PLAY THE CARD'), seg];
    if (ed.ftKind === 'general') {
      out.push(h('small', { class: 'muted' }, w.color === 'None' ? 'General: any hero, of any colour.' : `General: any ${w.color} hero.`));
    } else {
      const items = ed.ftKind === 'hero'
        ? allCards().filter(c => c.type === 'Hero' && (w.color === 'None' || c.color === w.color)).sort((a, b) => a.name.localeCompare(b.name))
          .map(c => ({ value: c.name, words: [c.name, ...(c.aliases ?? [])], sub: (c.aliases ?? []).filter(a => a !== c.name).join(', '), color: c.color }))
        : traitNames(traitList).map(t => ({ value: t, words: [t], sub: (traitList.find(x => (x?.name ?? x) === t)?.description ?? '') }));
      const rows = items.map(it => h('li', { class: norm(it.value) === norm(tag) ? 'on' : '', role: 'option', onpointerdown: e => { e.preventDefault(); pickFirst(it.value); } },
        h('span', {}, it.color ? h('span', { class: 'ce-ft-dot', style: `--sw: var(--c-${it.color})` }) : null, it.value), h('small', { class: 'muted' }, it.sub)));
      const two = h('li', { role: 'option', hidden: true });
      const none = h('li', { class: 'muted', hidden: true }, h('small', {}, ed.ftKind === 'hero' ? `No ${w.color === 'None' ? '' : w.color + ' '}hero by that name.` : 'No such trait: new traits are added on the Traits page.'));
      const list = h('ul', { class: 'ce-ft-list', role: 'listbox' }, rows, two, none);
      const filter = q => {
        let shown = 0;
        items.forEach((it, i) => { const ok = !q || it.words.some(x => norm(x).includes(q)); rows[i].hidden = !ok; if (ok) shown++; });
        // "Shanks & Roger": two heroes in one first tag.
        const pair = ed.ftKind === 'hero' && q.includes('&') ? String(search.value).trim() : '';
        two.hidden = !pair;
        if (pair) { two.replaceChildren(h('span', {}, `Use "${pair}"`), h('small', { class: 'muted' }, 'two heroes')); two.onpointerdown = e => { e.preventDefault(); pickFirst(pair); }; }
        none.hidden = shown > 0 || !!pair;
      };
      const search = h('input', { placeholder: ed.ftKind === 'hero' ? 'Type a hero or an alias…' : 'Type a trait…', autocomplete: 'off',
        oninput: e => filter(norm(e.target.value)),
        onkeydown: e => { if (e.key === 'Enter') { e.preventDefault(); const first = rows.find(r => !r.hidden) ?? (two.hidden ? null : two); first?.dispatchEvent(new PointerEvent('pointerdown')); } } });
      const right = ed.ftKind === 'hero' ? kindNow === 'hero' : kindNow === 'trait';
      if (right && !ed.ftOpen) {
        out.push(h('div', { class: 'ce-ft-picked' }, h('span', { class: 'muted' }, 'Picked: '), h('strong', {}, tag), ' · ',
          h('button', { class: 'link accent', type: 'button', disabled: !canWrite(), onclick: openList }, 'change')));
      } else {
        out.push(search, list);
        out.push(h('small', { class: right ? 'muted' : 'warn' }, right ? `Picked: ${tag}` : tag ? `Now "${tag}": pick ${ed.ftKind === 'hero' ? 'a hero' : 'a trait'} from the list` : `Pick ${ed.ftKind === 'hero' ? 'a hero' : 'a trait'} from the list`));
        // Just opened: brought into view (the form scrolls on its own) and ready to type in.
        if (ed.ftReveal) {
          ed.ftReveal = false;
          requestAnimationFrame(() => requestAnimationFrame(() => { list.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); search.focus({ preventScroll: true }); }));
        }
      }
    }
    if (tag && !kindNow) out.push(h('small', { class: 'warn' }, `"${tag}" is not a hero, alias or trait: pick who plays the card.`));
    return h('div', { class: 'ce-field ce-first-tag' }, ...out);
  }

  function chips(w, from, traits, accent) {
    const addTag = value => {
      const t = String(value ?? add.value).trim();
      if (!t) return;
      snap(true);
      if (!w.traits.includes(t)) w.traits = [...(from && !w.traits.length ? [''] : []), ...w.traits, t];
      changed();
      env.render();
    };
    const pop = h('ul', { class: 'ce-ac ce-tag-ac', hidden: true, role: 'listbox' });
    let items = [];
    let pick = -1;
    const inSet = traits.inSet ?? {};
    const paint = () => {
      const lis = [];
      let group = null;
      items.forEach((t, i) => {
        const g = inSet[t] ? 'set' : 'other';
        if (g !== group && Object.keys(inSet).length) {
          lis.push(h('li', { class: 'ce-ac-head', 'aria-hidden': 'true' }, g === 'set' ? `IN ${traits.setCode ?? 'THIS SET'}` : 'OTHER SETS'));
          group = g;
        }
        lis.push(h('li', { class: i === pick ? 'on' : '', role: 'option', 'data-i': i, onpointerdown: e => { e.preventDefault(); addTag(t); } },
          h('span', {}, t), inSet[t] ? h('small', { class: 'muted' }, `${inSet[t]} ${inSet[t] === 1 ? 'card' : 'cards'}`) : null));
      });
      pop.replaceChildren(...lis);
      const was = pop.hidden;
      pop.hidden = !items.length;
      // Opening below a field near the bottom of the form: the form scrolls so the list is seen whole.
      if (was && !pop.hidden) requestAnimationFrame(() => pop.scrollIntoView({ block: 'nearest', behavior: 'smooth' }));
      pop.querySelector(`[data-i="${pick}"]`)?.scrollIntoView({ block: 'nearest' });
    };
    const show = () => {
      const q = add.value.trim().toLowerCase();
      const have = new Set(w.traits);
      // This set's tags first (most used first), then the rest; within each, what starts with the typed text first.
      items = traits.filter(t => !have.has(t) && (!q || t.toLowerCase().includes(q)))
        .sort((a, b) => ((inSet[b] ? 1 : 0) - (inSet[a] ? 1 : 0)) || (b.toLowerCase().startsWith(q) - a.toLowerCase().startsWith(q)) || (inSet[b] ?? 0) - (inSet[a] ?? 0) || a.localeCompare(b));
      pick = q && items.length ? 0 : -1;
      paint();
    };
    const add = h('input', { placeholder: from ? 'Add tag…' : 'Add trait…', autocomplete: 'off', 'aria-autocomplete': 'list',
      onfocus: show, oninput: show, onblur: () => setTimeout(() => { pop.hidden = true; }, 150),
      onkeydown: e => {
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          e.preventDefault();
          if (!items.length) return;
          pick = (pick + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
          paint();
        } else if (e.key === 'Enter') { e.preventDefault(); addTag(pick >= 0 ? items[pick] : undefined); }
        else if (e.key === 'Escape') { pop.hidden = true; }
      } });
    return h('div', { class: 'ce-chips' },
      w.traits.slice(from).map((t, i) => h('span', { class: `ce-chip${accent.includes(t) ? ' accent' : ''}` }, t,
        h('button', { type: 'button', 'aria-label': `Remove ${t}`, onclick: () => { snap(true); w.traits = w.traits.filter((_, j) => j !== i + from); changed(); env.render(); } }, '×'))),
      h('span', { class: 'ce-tag-add' }, add, pop),
      h('button', { class: 'ghost ce-chip-add', type: 'button', onclick: () => addTag() }, '+ Add'));
  }

  // Tekst s prekidačima faze, Once per turn i Range, tokenima statova i prijedlozima iz vodiča.
  function textEditor(w) {
    const stage = w.type === 'Stage';
    const area = h('textarea', { rows: 4, value: w.text ?? '' });
    // Prijedlozi dok pišeš: padajući izbornik ispod teksta (↑ ↓, Enter ili Tab uzme, Esc zatvori).
    // "[" nudi ikone statova; dva ili više slova nude fraze iz vodiča koje tako počinju.
    const pop = h('ul', { class: 'ce-ac', role: 'listbox', hidden: true });
    let caret = area.value.length;
    let sug = { from: 0, items: [] };
    let pick = 0;
    const sync = () => {
      snap();
      w.text = area.value;
      if (w.fx && w.fxStatus !== 'check') w.fxStatus = 'check';
      changed();
      refreshToggles();
    };
    const close = () => { pop.hidden = true; sug = { from: 0, items: [] }; };
    const take = item => {
      const at = area.selectionStart ?? area.value.length;
      const before = area.value.slice(0, sug.from);
      const after = area.value.slice(at);
      // Razmak ispred fraze (ne iza broja ili zagrade) i iza nje, ako ga nema.
      const lead = item.token || !before || /[\s([]$/.test(before) ? '' : ' ';
      const trail = item.token || /[\s:]$/.test(item.insert) || /^[\s.,;:!?]/.test(after) ? '' : ' ';
      const text = lead + item.insert + trail;
      area.value = before + text + after;
      area.selectionStart = area.selectionEnd = before.length + text.length;
      area.focus();
      close();
      sync();
    };
    const paint = () => {
      pop.replaceChildren(...sug.items.map((it, i) => h('li', { role: 'option', 'aria-selected': String(i === pick), class: i === pick ? 'on' : '',
        onmousedown: e => { e.preventDefault(); take(it); } },
      h('span', { class: it.token ? `tok tok-${it.token.toLowerCase()}` : '' }, it.label), it.note ? h('small', { class: 'muted' }, it.note) : null)));
      pop.hidden = !sug.items.length;
    };
    const showSuggest = () => {
      const caret = area.selectionStart ?? area.value.length;
      const before = area.value.slice(0, caret);
      if (before.endsWith('[')) {
        sug = { from: caret - 1, items: TOKENS.map(t => ({ label: `[${t}]`, insert: `[${t}]`, token: t, note: { HP: 'heal / health', DMG: 'damage', PWR: 'Power', RNG: 'Range', KB: 'Knockback', EN: 'Energy' }[t] })) };
      } else {
        const g = suggest(ed.guide, area.value, caret);
        const notes = new Map((ed.guide?.phrases ?? []).map(p => [p.text, p.label]));
        sug = { from: g.from, items: g.items.map(it => ({ label: toTokens(it.insert).trim(), insert: toTokens(it.insert).replace(/\s+$/, ''), note: notes.get(it.insert) })) };
      }
      pick = 0;
      paint();
    };
    area.addEventListener('input', () => { caret = area.selectionStart ?? caret; sync(); showSuggest(); });
    area.addEventListener('blur', () => setTimeout(close, 120));
    area.addEventListener('keydown', e => {
      if (pop.hidden || !sug.items.length) return;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        pick = (pick + (e.key === 'ArrowDown' ? 1 : -1) + sug.items.length) % sug.items.length;
        paint();
      } else if (e.key === 'Enter' || e.key === 'Tab') {
        e.preventDefault();
        take(sug.items[pick]);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        close();
      }
    });
    const insert = s => {
      snap(true);
      const a = area.selectionStart ?? area.value.length;
      const b = area.selectionEnd ?? a;
      area.value = area.value.slice(0, a) + s + area.value.slice(b);
      area.selectionStart = area.selectionEnd = a + s.length;
      area.focus();
      sync();
    };
    // Prekidači rade na efektu u kojem je kursor (karta može imati više efekata, svaki u svom retku).
    const here = () => headAt(area.value, caret);
    const setHead = patch => {
      snap(true);
      const r = withHeadAt(area.value, caret, patch);
      area.value = r.text;
      caret = r.caret;
      area.focus();
      area.selectionStart = area.selectionEnd = caret;
      sync();
    };
    const phaseBtns = PHASES.filter(p => !stage || ['Start', 'Battle', 'End'].includes(p)).map(p => h('button', { type: 'button', 'data-phase': p, style: `--tint: ${PHASE_COLORS[p.toUpperCase()]}`, onmousedown: e => e.preventDefault(), onclick: () => setHead({ phase: here().phase === p ? null : p }) }, p));
    // Passive: the effect has no phase (cards that stay in play draw a PASSIVE chip for it; Marko 2026-11-05).
    const passiveType = ['Hero', 'Evolution', 'Equipment', 'Assist'].includes(w.type);
    const passiveBtn = passiveType ? h('button', { type: 'button', 'data-passive': '1', style: `--tint: ${PHASE_COLORS.PASSIVE}`, title: 'No phase: the effect counts all the time', onmousedown: e => e.preventDefault(), onclick: () => setHead({ phase: null, once: false }) }, 'Passive') : null;
    // Once per turn and Range change the effect line the cursor is in: checkboxes under the phase.
    const check = (attr, label, title, onchange) => h('label', { class: 'ce-check', title },
      h('input', { type: 'checkbox', [attr]: '1', onchange }), label);
    const once = stage ? null : check('data-once', 'Once per turn', 'Once per turn, for the effect the cursor is in', () => { const hd = here(); setHead({ once: !hd.once, phase: hd.phase ?? 'Battle' }); });
    // Novi efekt: novi redak na kraju, kursor u njemu (pa se bira njegova faza).
    const addEffect = stage ? null : h('button', { type: 'button', class: 'ce-add-effect', onmousedown: e => e.preventDefault(), onclick: () => {
      snap(true);
      area.value = area.value.replace(/\s+$/, '') + (area.value.trim() ? '\n' : '');
      caret = area.value.length;
      area.focus();
      area.selectionStart = area.selectionEnd = caret;
      sync();
    } }, '+ Effect');
    for (const ev of ['click', 'keyup', 'select']) area.addEventListener(ev, () => { caret = area.selectionStart ?? caret; refreshToggles(); });
    const revealed = stage ? h('button', { type: 'button', onclick: () => { if (!/^When this Stage is revealed/i.test(area.value)) { area.value = `When this Stage is revealed, ${area.value}`; area.selectionStart = area.selectionEnd = area.value.length; sync(); } } }, 'When revealed') : null;
    const toks = TOKENS.map(t => h('button', { type: 'button', class: `tok tok-${t.toLowerCase()}`, title: `[${t}] at the cursor`, onmousedown: e => e.preventDefault(), onclick: () => insert(`[${t}]`) }, t));
    const trait = PORTRAIT.includes(w.type) ? h('button', { type: 'button', class: 'tok tok-trait', title: 'A trait in the text, e.g. {Sword}', onmousedown: e => e.preventDefault(), onclick: () => insert('{}') }, '{Trait}') : null;
    // Phrases from the Text guide (Card editor › Phrases): the same ones come up while typing; the list shows them all.
    const phrase = ed.guide?.phrases?.length ? h('select', { class: 'ce-phrase', 'aria-label': 'Insert a phrase from the Text guide', title: 'Phrases from the Text guide', onchange: e => { const p = ed.guide.phrases[Number(e.target.value)]; e.target.value = ''; if (p) insert(toTokens(p.text)); } },
      h('option', { value: '' }, 'Phrases'), ed.guide.phrases.map((p, i) => h('option', { value: i, title: p.note ?? '' }, `${p.label}: ${p.text.trim()}`))) : null;
    // Colorless: red s bonusom za odabrane boje ("Cyan / Purple Bonus: ").
    const bonusBtn = w.color === 'None' ? h('button', { type: 'button', class: 'ce-add-effect', onmousedown: e => e.preventDefault(), onclick: () => {
      const cols = (w.bonusColors ?? []).length ? w.bonusColors : ['Red'];
      snap(true);
      area.value = area.value.replace(/\s+$/, '') + (area.value.trim() ? '\n' : '') + `${cols.join(' / ')} Bonus: `;
      caret = area.value.length;
      area.focus();
      area.selectionStart = area.selectionEnd = caret;
      sync();
    } }, '+ Bonus') : null;
    const seg = h('div', { class: 'ce-phase-seg', role: 'group', 'aria-label': 'Phase of the effect the cursor is in' }, passiveBtn, phaseBtns);
    // Range nije prekidač (pravilo B, 2026-11-05): piše se u tekstu uz metu, "a friendly Hero in [RNG]".
    const mods = once || revealed ? h('div', { class: 'ce-mods' }, revealed, once) : null;
    const bar = h('div', { class: 'ce-tokbar' }, toks, trait ? h('span', { class: 'ce-tokbar-sep' }) : null, trait, phrase);
    // Check text (Marko 2026-11-06): desno u istom redu; odgovor ide ispod.
    // Savjet za pisanje kao ⓘ (Marko 2026-11-06): hover pokaže, dodir otvori ispod reda.
    const hintText = stage ? 'Type [ for a stat icon, or the start of a phrase from the Text guide: a list opens under the text.'
        : 'Each effect is its own line; the phase and Once per turn set the effect the cursor is in (+ Effect starts a new one). Range goes in the text next to its target: "a friendly Hero in [RNG]". Type [ for a stat icon or the start of a phrase for suggestions.';
    const hint = h('details', { class: 'ce-hint-i' }, h('summary', { title: hintText, 'aria-label': 'How to write the effect text' }, 'ⓘ'), h('p', { class: 'muted small' }, hintText));
    const adds = h('div', { class: 'ce-adds' }, addEffect, bonusBtn, hint);
    const tools = h('div', { class: 'ce-effect-tools' }, seg, mods);
    function refreshToggles() {
      const hd = here();
      for (const b of seg.querySelectorAll('[data-phase]')) b.classList.toggle('on', b.dataset.phase === hd.phase);
      seg.querySelector('[data-passive]')?.classList.toggle('on', !hd.phase && !!hd.rest?.trim());
      const o = mods?.querySelector('[data-once]');
      if (o) o.checked = !!hd.once;
    }
    refreshToggles();
    area.setAttribute('aria-label', 'Effect text');
    // The text first, then the one CLAUDE box (Intent, Check text, the answer) under it (Marko 2026-11-14).
    return [tools, h('div', { class: 'ce-field' }, h('span', {}, 'TEXT'), h('div', { class: 'ce-text-box' }, bar, h('div', { class: 'ce-ac-wrap' }, area, pop))), adds, claudeBox(w)];
  }

  // ---------- izmjene, Undo ----------

  // Snimka prije izmjene; tipkanje u nizu (do 1,5 s) je jedna snimka. force: svaka radnja svoja.
  function snap(force = false) {
    const now = Date.now();
    if (!force && now - ed.snapAt < 1500) { ed.snapAt = now; return; }
    ed.snapAt = now;
    ed.undo.push(JSON.stringify(ed.work));
    if (ed.undo.length > 100) ed.undo.shift();
    const btn = document.querySelector('.ce-top-actions button[disabled]');
    if (btn?.textContent === 'Undo') btn.disabled = false;
  }

  function undo() {
    const prev = ed.undo.pop();
    if (!prev) return;
    ed.work = JSON.parse(prev);
    ed.snapAt = 0;
    ed.dirty = true;
    env.render();
  }

  function changed() {
    ed.dirty = true;
    queueDraw();
  }

  // ---------- provjere ----------

  // [ok, tekst]: kvačice za ono što je u redu, ! za ono što treba pogledati.
  function checks(w, card) {
    const out = [];
    const traitList = env.state.traits?.traits;
    const fxp = env.state.fxProposals?.cards?.[w.id];
    const textChanged = !w.new && toWords(w.text ?? '') !== (ed.base.type === 'Stage' ? stripTerrain(ed.base.text) : ed.base.text ?? '');
    const gameReads = () => {
      if (!(card.text ?? '').trim()) return;
      if (w.fx && fxProblems(w.fx).length) out.push([false, 'The fx box holds something the game can\'t read']);
      else if (w.fx) out.push([w.fxStatus !== 'check', w.fxStatus === 'check' ? 'The fx is not confirmed yet' : 'fx confirmed for the game']);
      else out.push([false, 'No fx yet']);
      if (ed.drafts?.cards?.[w.id]?.who === 'Claude Code') out.push([false, 'Changed by Claude Code: have a look, then Save']);
      // Pravilo B (2026-11-05): range uz metu u tekstu, ne na početku retka.
      if (/^\[RNG\]/m.test(w.text ?? '')) out.push([false, 'Range at the start of a line: write it next to its target ("in [RNG]")']);
    };
    if (!(w.name ?? '').trim()) out.push([false, 'No name yet']);
    // Isto ime smije postojati (kod razlikuje; Marko 2026-11-07), ali neka se vidi.
    else { const twin = allCards().find(c => c.id !== w.id && c.type !== 'Core' && norm(c.name) === norm(w.name)); if (twin) out.push([false, 'Another card is called ' + twin.name + ' (' + twin.id + '): the code tells them apart']); }
    if (PORTRAIT.includes(w.type)) {
      const k = firstTag(db(), card, traitList);
      if (k.kind === HEROES) out.push([true, `First tag "${k.tag}" is a hero${k.heroes.length > 1 ? 'es' : ''}${k.heroes.some(n => n !== k.tag) ? ' alias' : ''}`]);
      else if (k.kind === TRAIT) out.push([true, `First tag "${k.tag}" is a trait`]);
      else if (k.kind === GENERAL) out.push([true, 'First tag General: any hero of this colour']);
      else out.push([false, k.tag ? `First tag "${k.tag}" is not a hero, alias or trait` : 'No first tag: who may play it?']);
      const avoid = avoidWarnings(ed.guide, card.text);
      out.push(avoid.length ? [false, avoid[0]] : [true, 'Phrases match the text guide']);
      gameReads();
    }
    if (w.token) {
      out.push(w.type === 'Action' ? [true, 'Token: an Action, never in a deck'] : [false, 'A token can only be an Action']);
      const maker = allCards().find(c => c.id === makerOf(w.id));
      if (!maker) out.push([false, `No card ${makerOf(w.id)} makes this token`]);
      else if (!new RegExp(`\\bcreate (?:an?|\\d+) ${(w.name ?? '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} tokens?\\b`, 'i').test(maker.text ?? '') && !(maker.fx ?? '').includes(w.id))
        out.push([false, `${maker.name || maker.id} does not say "Create a ${w.name || '…'} Token." yet`]);
      else out.push([true, `${maker.name || maker.id} makes it`]);
    }
    if (w.color === 'None' && PORTRAIT.includes(w.type)) {
      const cols = w.bonusColors ?? [];
      const lines = [...(w.text ?? '').matchAll(/^(Cyan|Yellow|Purple|Red|Blue|Green)((?:\s*\/\s*(?:Cyan|Yellow|Purple|Red|Blue|Green))*)\s+Bonus\s*:/gim)]
        .flatMap(m => m[0].replace(/\s+Bonus\s*:$/i, '').split('/').map(x => x.trim().toLowerCase()));
      // A colorless card without a colour bonus is a card like any other (Marko 2026-11-15), not a warning.
      if (!cols.length) out.push([true, 'Colorless, no colour bonus']);
      else if (cols.length > 2) out.push([false, 'More than 2 bonus colours: only as an exception, with the same bonus']);
      else out.push([true, `Colorless, bonus for ${cols.join(' / ')}`]);
      const missing = cols.filter(c => !lines.includes(c.toLowerCase()));
      const extra = lines.filter(l => !cols.some(c => c.toLowerCase() === l));
      if (missing.length) out.push([false, `No "${missing.join(' / ')} Bonus:" line in the text`]);
      if (extra.length) out.push([false, `The text has a bonus for ${extra.join(', ')}, which is not a bonus colour`]);
    }
    if (HEROISH.includes(w.type)) {
      if (w.type === 'Evolution') {
        const hc = heroCard(w);
        out.push(hc ? [true, `Base hero ${hc.name} is in the set`] : [false, 'Pick the base hero']);
      }
      const names = traitNames(traitList).map(norm);
      for (const t of w.traits.filter(t => names.includes(norm(t))).slice(0, 2)) out.push([true, `Trait "${t}" known`]);
      if (!w.abilityNames?.[0]) out.push([false, 'No ability name']);
      if (!w.emblem && !(w.type === 'Evolution' && heroCard(w)?.emblem)) out.push([false, 'No emblem on the plate']);
    }
    if (w.type === 'Stage') out.push([!!w.terrain && w.terrain !== '', `Terrain set (${w.terrain ?? 'None'})`]);
    if (w.type === 'Combo') {
      const bad = comboProblems(allCards(), w);
      for (const p of bad) out.push([false, p]);
      if (!bad.length) out.push([true, `${decorate(cardOf(w), allCards()).ingredientNames.join(' + ')}, +${w.extraCost} energy`]);
      if (!w.introducedIn) out.push([false, 'Pick the set it comes out with (Introduced in)']);
    }
    if (w.type === 'Core') {
      out.push(Object.keys(card.bonus ?? {}).length ? [true, 'The game reads the effect'] : [false, 'Write the bonus, e.g. +2000[PWR]']);
      if (!CORE_KINDS.includes(w.traits[0])) out.push([false, 'Pick Buff, Major or Debuff']);
    }
    if (w.type !== 'Core') {
      const atMin = ed.warn.some(x => /smallest size/.test(x));
      if ((card.text ?? '').trim()) out.push(atMin ? [false, 'The text only fits at the smallest size'] : [true, 'Text fits']);
      if (!w.art) out.push([false, 'No art yet']);
    }
    for (const x of ed.warn.filter(x => !/smallest size|No art yet/.test(x))) out.push([false, x.replace(/\.$/, '')]);
    if (w.type === 'Stage' || w.type === 'Combo' || HEROISH.includes(w.type)) gameReads();
    if (w.type === 'Hero') {
      const n = deckPool(liveDb(card), [w.id], heroEvolutions(liveDb(card), [w.id])).filter(c => c.color === w.color).length;
      out.push([n >= 8, `${w.name || 'This hero'} has ${n} cards to play`]);
    }
    if (/\[(?!HP\]|DMG\]|PWR\]|RNG\]|KB\]|EN\])[^\]]*\]/i.test(w.text ?? '')) out.push([false, 'Only [HP] [DMG] [PWR] [RNG] [KB] [EN] go in brackets']);
    return out;
  }

  const liveDb = card => setTraits({ ...db(), cards: [...db().cards.filter(c => c.id !== card.id).map(merged), card] }, db().traitList ?? env.state.traits?.traits);

  // Balans dok uređuješ (Marko 2026-11-15, mockup docs/private/mockups/balance, varijanta B): krivulja costa boje,
  // slične karte (ista boja i cost, tri pa "+N more"), i svi heroji boje karte kao male pločice po setu s brojem
  // karata svoje boje koje smiju uzeti (cilj 8; ispod 4 žuto). Svijetle oni koji ovu kartu smiju uzeti; za kartu u
  // boji uz broj piše prije → poslije. Heroji iz nacrta su tu (novi set); setovi se sklapaju na mjestu.
  function renderBalance(card) {
    if (!card.color) return [];
    const others = allCards().filter(c => c.id !== card.id && !c.deleted);
    const pool = [...others, card].filter(c => PORTRAIT.includes(c.type) && c.color === card.color);
    const costs = new Map();
    for (const c of pool) costs.set(c.cost ?? 0, (costs.get(c.cost ?? 0) ?? 0) + 1);
    const max = Math.max(1, ...costs.values());
    const top = Math.max(6, ...costs.keys());
    const curve = h('div', { class: 'ce-curve' }, Array.from({ length: top + 1 }, (_, k) => h('div', { class: `ce-bar${k === (card.cost ?? 0) ? ' mine' : ''}`, title: `Cost ${k}: ${costs.get(k) ?? 0}` },
      h('span', { style: `height:${((costs.get(k) ?? 0) / max) * 100}%` }), h('small', {}, String(k)))));
    const similar = pool.filter(c => c.id !== card.id && (c.cost ?? 0) === (card.cost ?? 0));
    const traitList = db().traitList ?? env.state.traits?.traits;
    const saved = db().cards.find(c => c.id === card.id && !c.deleted) ? merged(db().cards.find(c => c.id === card.id)) : (ed.drafts?.cards?.[card.id] ? { id: card.id, ...ed.drafts.cards[card.id] } : null);
    const pub = setTraits({ ...db(), cards: saved ? [...others, saved] : others }, traitList);
    const live = setTraits({ ...db(), cards: [...others, card] }, traitList);
    const heroes = others.filter(c => c.type === 'Hero' && (card.color === 'None' || c.color === card.color));
    const deck = (d, hero) => deckPool(d, [hero.id], heroEvolutions(d, [hero.id]));
    const own = (d, hero) => deck(d, hero).filter(c => c.color === hero.color);
    // Whether the hero may take the card is asked of its whole pool: a colorless card is never of the hero's colour.
    const rows = heroes.map(hero => ({ hero, before: own(pub, hero).length, after: own(live, hero).length, takes: deck(live, hero).some(c => c.id === card.id) }));
    const takes = rows.filter(r => r.takes).length;
    // Sets: the card's own first, then by code; one is open while it holds the card's set or a hero that takes it,
    // until it is folded by hand.
    const bySet = new Map();
    for (const r of rows) { const s = setOf(r.hero.id); if (!bySet.has(s)) bySet.set(s, []); bySet.get(s).push(r); }
    const setCodes = [...bySet.keys()].sort((a, b) => (b === setOf(card.id)) - (a === setOf(card.id)) || a.localeCompare(b));
    ed.balFold ??= {};
    const groups = setCodes.map(s => {
      const list = bySet.get(s).sort((a, b) => a.hero.name.localeCompare(b.hero.name));
      const open = ed.balFold[s] ?? (s === setOf(card.id) || list.some(r => r.takes));
      const tiles = h('div', { class: 'ce-bal-tiles', hidden: !open }, list.map(r => {
        const n = r.after;
        return h('button', { class: `ce-bal-tile${r.takes ? ' takes' : ''}`, type: 'button', onclick: () => go(r.hero.id),
          title: `${r.hero.name}: ${r.before === r.after ? n : `${r.before} → ${r.after}`} cards of its colour${r.takes ? '' : ' (cannot take this card)'}` },
          h('span', { class: 'ce-ft-dot', style: `--sw: var(--c-${r.hero.color})` }), h('span', {}, r.hero.name.length <= 10 ? r.hero.name : r.hero.name.split(/[ ,]/)[0]),
          h('b', { class: n < 4 ? 'low' : '' }, r.before === r.after ? String(n) : `${r.before}→${n}`));
      }));
      const head = h('button', { class: 'ce-bal-set', type: 'button', 'aria-expanded': String(open), onclick: ev => {
        const now = tiles.hidden;
        tiles.hidden = !now;
        ed.balFold[s] = now;
        ev.currentTarget.setAttribute('aria-expanded', String(now));
        ev.currentTarget.firstChild.textContent = now ? '▾' : '▸';
      } }, h('span', { class: 'ce-bal-chev' }, open ? '▾' : '▸'), h('span', {}, sets.nameOf(s) === s ? s : `${s} · ${sets.nameOf(s)}`),
        h('span', { class: 'muted' }, `${list.filter(r => r.takes).length}/${list.length}`));
      return [head, tiles];
    }).flat();
    const simList = h('ul', { class: 'small ce-similar' }, similar.slice(0, 3).map(c => h('li', {}, h('button', { class: 'link', type: 'button', onclick: () => go(c.id) }, c.name), ` · ${c.type}`)));
    const simMore = similar.length > 3 ? h('button', { class: 'link ce-bal-more', type: 'button', onclick: ev => {
      simList.replaceChildren(...similar.map(c => h('li', {}, h('button', { class: 'link', type: 'button', onclick: () => go(c.id) }, c.name), ` · ${c.type}`)));
      ev.currentTarget.remove();
    } }, `+${similar.length - 3} more`) : null;
    return [h('details', { class: 'ce-panel ce-balance', open: ed.balOpen, ontoggle: e => { ed.balOpen = e.target.open; } },
      h('summary', {}, h('h3', {}, 'Balance')),
      h('p', { class: 'small muted' }, `Cost curve of ${card.color === 'None' ? 'colorless' : card.color} cards:`), curve,
      h('p', { class: 'small' }, similar.length ? `Same colour and cost (${similar.length}):` : 'No other card of this colour has this cost.'),
      similar.length ? simList : null, simMore,
      h('p', { class: 'small' }, `Heroes: cards of their colour (goal 8). ${takes} of ${rows.length} may take this card.`),
      card.color === 'None' ? h('p', { class: 'small muted' }, 'Colorless: it does not change these counts.') : null,
      ...groups)];
  }

  // ---------- spremanje ----------

  // Nacrt: polja koja se razlikuju od cards.json, tko i kad. Drugi nacrti se čitaju iznova prije pisanja.
  async function saveDraft() {
    await ensureLock();
    if (await refreshDb()) {
      rebase();
      env.render();
      throw new Error('The cards were published in the meantime. Fields you did not touch now show the new version; check your changes and Save again.');
    }
    const w = ed.work;
    const card = cardOf(w);
    const diff = {};
    for (const k of FIELDS) {
      if (card[k] === undefined && ed.base[k] === undefined) continue;
      // Izrez na sredini bez zuma je isto što i izrez kojeg nema.
      if (k === 'artCrop' && ed.base[k] == null && isDefaultCrop(card[k])) continue;
      if (!sameVal(card[k], ed.base[k])) diff[k] = card[k] ?? null;
    }
    const fresh = await readDrafts();
    const before = ed.drafts?.cards?.[w.id]?.updated;
    const now = fresh.cards?.[w.id]?.updated;
    if (now && now !== before && !confirm(`${fresh.cards[w.id].who || 'Someone'} saved this card in the meantime. Overwrite?`)) return;
    fresh.cards ??= {};
    if (w.new) diff.new = true;
    const fields = Object.keys(diff).filter(k => k !== 'new');
    if (fields.length || w.new) fresh.cards[w.id] = { ...diff, updated: new Date().toISOString(), who: who() || undefined };
    else delete fresh.cards[w.id];
    await writeJson(DRAFTS_PATH, fresh);
    const prevFields = Object.keys(ed.drafts?.cards?.[w.id] ?? {});
    ed.drafts = fresh;
    ed.dirty = false;
    const what = w.new && !prevFields.length ? 'new card' : fields.filter(k => !prevFields.includes(k) || true).map(k => ({ artCrop: 'art crop', abilityNames: 'ability', traits: 'tags' }[k] ?? k)).join(', ') || 'no changes';
    await logHistory(w.id, `${what.replace(/\btext\b/, 'text changed')}`).catch(() => {});
    env.toast(fields.length || w.new ? `Saved: ${w.name || w.id}. It goes into the game with the next Publish.` : 'No changes against the published card.');
    env.render();
  }

  // cards.json s diska: ako se promijenio (Objava na drugom stroju), app ga preuzme. true kad je nov.
  async function refreshDb() {
    return env.reloadDb ? env.reloadDb() : false;
  }

  // Otvorena karta nakon Objave u međuvremenu: polja koja korisnik nije dirao dobiju novu objavljenu vrijednost.
  function rebase() {
    if (!ed.work || !ed.opened) return;
    const nb = db().cards.find(c => c.id === ed.id);
    if (!nb) return;
    const now = cardOf(ed.work);
    const draft = ed.drafts?.cards?.[ed.id] ?? {};
    const fresh = workOf({ ...nb, ...draft });
    const freshCard = cardOf(fresh);
    for (const k of FIELDS) if (sameVal(now[k], ed.opened[k]) && !(k in draft)) now[k] = freshCard[k];
    ed.base = nb;
    ed.work = workOf(now);
    ed.opened = cardOf(workOf({ ...nb, ...draft }));
  }

  async function discardDraft() {
    await ensureLock();
    if (!confirm(ed.work?.new ? 'Throw away this new card?' : 'Throw away the unpublished changes to this card?')) return;
    const fresh = await readDrafts();
    delete fresh.cards?.[ed.id];
    await writeJson(DRAFTS_PATH, fresh);
    ed.drafts = fresh;
    if (ed.work?.new) { ed.dirty = false; const back = ed.from; ed.work = null; ed.id = null; env.go(back); return; }
    await logHistory(ed.id, 'unpublished changes discarded').catch(() => {});
    open(ed.id);
    env.render();
  }

  // Izvorni art ide u data/art/<kod>.<ext> u punoj rezoluciji; izrez se vraća na sredinu.
  async function uploadArt(file) {
    if (!file) return;
    const ext = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' }[file.type];
    if (!ext) throw new Error('Art must be PNG, JPEG or WebP.');
    const bytes = new Uint8Array(await file.arrayBuffer());
    const path = `art/${ed.work.id}.${await imageHashOf(bytes)}.${ext}`;
    await fs.writeFile(store().root, `data/${path}`, bytes);
    store().dropImageUrls?.();
    snap(true);
    ed.work.art = path;
    ed.work.artCrop = { x: 0.5, y: 0.5, zoom: 1 };
    if (ed.work.type === 'Core') ed.work.coreImage = 'upload';
    ed.artFor = null;
    changed();
    env.render();
  }

  // Amblem u pločici heroja: data/art/emblems/<kod>.<ext>.
  async function uploadEmblem(file) {
    if (!file) return;
    const ext = { 'image/png': 'png', 'image/webp': 'webp' }[file.type];
    if (!ext) throw new Error('The emblem must be PNG or WebP (with a clear background).');
    const bytes = new Uint8Array(await file.arrayBuffer());
    const path = `art/emblems/${ed.work.id}.${await imageHashOf(bytes)}.${ext}`;
    await fs.writeFile(store().root, `data/${path}`, bytes);
    store().dropImageUrls?.();
    snap(true);
    ed.work.emblem = path;
    ed.emblemFor = undefined;
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

  // Nacrta objavljenu kartu iznova trenutnim rendererom i upiše novu sliku (novi hash) u bazu bez nove
  // verzije: izgled, ne igra. Samo na računalu s otvorenim folderom, samo za kartu bez nacrta
  // (nacrt crta Objava). Stara slika ostaje do iduće Objave, kao i kod Objave (Undo).
  // The picture a published card would get from the renderer as it is now: {bytes, hash}, or null without art.
  async function drawPublished(card) {
    const core = card.type === 'Core' && coreMode(card) === 'effect';
    const url = card.art ? await store().dataUrl(card.art) : null;
    const art = url ? await loadImage(url).catch(() => null) : null;
    if (!art && !core) return null;
    const heroOfCard = card.type === 'Evolution' ? db().cards.find(x => x.type === 'Hero' && x.name === card.hero) : null;
    const emblemPath = card.emblem ?? heroOfCard?.emblem ?? null;
    const eUrl = emblemPath ? await store().dataUrl(emblemPath) : null;
    const emblem = eUrl ? await loadImage(eUrl).catch(() => null) : null;
    const canvas = document.createElement('canvas');
    renderCard(canvas, decorate(card, db().cards.filter(c => !c.deleted)), await templateFor(card), art, emblem);
    const blob = await new Promise(r => canvas.toBlob(r, 'image/png'));
    const bytes = new Uint8Array(await blob.arrayBuffer());
    return { bytes, hash: await imageHashOf(bytes) };
  }

  // Which published pictures are out of date (Marko 2026-11-13: a new colour in the renderer, and no way to see which
  // cards it touched): each card without a draft is drawn again as the renderer draws it now and its hash compared
  // with the picture's. By card id: true out of date, false up to date; worked out once per database version.
  const stale = { version: null, ids: new Map(), running: false };
  async function checkPictures() {
    const version = db()?.version;
    // Only where pictures are drawn and written (a computer with the folder): another browser may draw a pixel
    // differently, and every card would look out of date there.
    if (!canPublish() || stale.running || version == null || stale.version === version) return;
    stale.running = true;
    try {
      await fontsReady();
      const ids = new Map();
      for (const card of db().cards) {
        if (card.deleted || ed.drafts?.cards?.[card.id] || !card.imageHash) continue;
        const pic = await drawPublished(card).catch(() => null);
        if (pic) ids.set(card.id, pic.hash !== card.imageHash);
      }
      stale.ids = ids;
      stale.version = version;
    } finally {
      stale.running = false;
    }
    env.render();
  }
  const pictureStale = id => stale.ids.get(id) === true;

  // Every out-of-date picture drawn again at once, one database write (no new card version: looks, not play);
  // `prefix` ('OP1-') keeps it to one set.
  async function redrawAll(prefix = '') {
    if (!canPublish()) throw new Error('Redrawing writes the pictures: open Card Studio on a computer with the shared folder.');
    await env.assertFresh();
    await fontsReady();
    const images = {};
    const names = [];
    for (const card of db().cards) {
      if (card.deleted || ed.drafts?.cards?.[card.id] || !card.imageHash || !card.id.startsWith(prefix)) continue;
      const pic = await drawPublished(card).catch(() => null);
      if (!pic || pic.hash === card.imageHash) continue;
      await fs.writeFile(store().root, `data/images/${card.id}.${pic.hash}.png`, pic.bytes);
      images[card.id] = pic.hash;
      names.push(card.id);
    }
    if (!names.length) { env.toast('Every picture is up to date.'); return; }
    const { db: next } = applyDrafts(db(), {}, images);
    await env.commitDb(next, { keepOld: true });
    for (const id of names) await logHistory(id, 'picture redrawn').catch(() => {});
    stale.version = null;
    env.toast(`${names.length} ${names.length === 1 ? 'picture' : 'pictures'} redrawn.`);
    env.render();
  }

  async function redrawPicture() {
    const id = ed.work?.id;
    const card = db().cards.find(c => c.id === id && !c.deleted);
    if (!card) throw new Error('This card is not published yet: Publish draws it.');
    if (ed.drafts?.cards?.[id]) throw new Error('This card has a draft: Publish draws it.');
    await env.assertFresh();
    const pic = await drawPublished(card);
    if (!pic) throw new Error('The card has no art to draw.');
    const { bytes, hash } = pic;
    if (hash === card.imageHash) { env.toast(`${card.name}: the picture is already up to date.`); return; }
    await fs.writeFile(store().root, `data/images/${id}.${hash}.png`, bytes);
    const { db: next } = applyDrafts(db(), {}, { [id]: hash });
    await env.commitDb(next, { keepOld: true });
    await logHistory(id, 'picture redrawn').catch(() => {});
    env.toast(`${card.name}: picture redrawn (v${next.version}).`);
    stale.version = null;
    env.render();
  }

  // ---------- nova karta, duplikat ----------

  function nextId(set) {
    const ids = [...db().cards.map(c => c.id), ...Object.keys(ed.drafts?.cards ?? {})];
    const nums = ids.filter(id => id.startsWith(`${set}-`)).map(id => Number(id.slice(set.length + 1))).filter(Number.isFinite);
    return `${set}-${String(Math.max(0, ...nums) + 1).padStart(3, '0')}`;
  }

  const NEW_DEFAULTS = {
    Action: { color: 'Cyan', cost: 1, bonus: {}, traits: ['General'], text: '' },
    Hero: { color: 'Cyan', stats: { hp: 8, dmg: 3, pwr: 2000, rng: 2, kb: 2 }, traits: [], abilityNames: [''], text: '' },
    Evolution: { color: 'Cyan', cost: 4, evo: 1, hero: '', stats: { hp: 8, dmg: 4, pwr: 3000, rng: 2, kb: 2 }, traits: [], abilityNames: [''], text: '' },
    Stage: { color: null, traits: [], text: '', terrain: 'None' },
    Core: { color: null, traits: ['Buff'], bonus: { pwr: 1000 }, text: '', coreImage: 'effect' },
    // Combo (2026-11-07): dvije karte (Action ili Assist) i dodatna energija X; boje dolaze od sastojaka.
    Combo: { color: null, traits: [], ingredients: ['', ''], extraCost: 1, introducedIn: '', text: 'Battle Phase: ' },
  };

  function startCard(id, card) {
    ed.id = id;
    ed.base = { id };
    ed.work = workOf({ ...card, id, new: true, status: 'draft' });
    ed.canvas = null;
    ed.artCv = null;
    ed.dirty = true;
    ed.undo = [];
    ed.artMode = false;
    ed.view = 'card';
    ed.art = ed.artFor = ed.emblem = ed.emblemFor = null;
    if (!PAGES.includes(env.state.editId ?? 'sets')) ed.from = ed.from ?? 'sets';
    else ed.from = env.state.editId ?? 'sets';
    env.go(id);
  }

  function newCard(set, type, extra = {}) {
    if (ed.dirty && !confirm('Discard the unsaved changes to this card?')) return;
    startCard(nextId(set), { name: '', type, ...structuredClone(NEW_DEFAULTS[type] ?? NEW_DEFAULTS.Action), ...extra });
  }

  // Duplikat: ista karta pod sljedećim kodom u istom setu, kao nova karta (nacrt do Objave).
  function duplicate() {
    const w = ed.work;
    if (ed.dirty && !confirm('Discard the unsaved changes to this card?')) return;
    const copy = cardOf(w);
    for (const k of ['image', 'imageHash', 'imageRot', 'imageRotHash', 'sprite', 'spriteHash', 'rev', 'deleted', 'fx', 'fxStatus', 'fxRead', 'aliases', 'updated', 'who', 'new']) delete copy[k];
    startCard(w.token ? nextTokenId(makerOf(w.id)) : nextId(setOf(w.id)), { ...copy, name: `${w.name ?? ''} (copy)` });
  }

  // ---------- zaključavanje ----------

  // Otvorena karta je zaključana na "Signed in as" dok je otvorena; tuđi lock gasi spremanje (vidi js/locks.js).
  // Ovaj prozor ima svoj tab id (ostaje kroz reload), da isto ime u drugom prozoru bude 'twin'.
  const TAB = (() => {
    const fresh = () => Math.random().toString(36).slice(2, 10);
    try { let t = sessionStorage.getItem(TAB_KEY); if (!t) { t = fresh(); sessionStorage.setItem(TAB_KEY, t); } return t; } catch { return fresh(); }
  })();
  const stateOf = (lock, me) => lockState(lock, me, Date.now(), TAB);
  const lockBusy = () => ed.lock?.state === 'other' || ed.lock?.state === 'twin';
  const busyText = () => ed.lock?.state === 'twin' ? 'This card is open in another window of yours. Close it there, or click "Use it here".'
    : `${ed.lock?.other?.who ?? 'Someone'} is editing this card.`;

  async function readLockFile(file) {
    try { return JSON.parse((await fs.readText(store().root, `${LOCK_DIR}/${file}`)) ?? 'null'); } catch { return null; }
  }

  // Sve verzije locka jedne karte (glavni i konfliktne kopije Syncthinga) i ona koja vrijedi.
  async function currentLock(id) {
    const names = await fs.listFileNames(store().root, LOCK_DIR).catch(() => null);
    const files = names ? names.filter(f => lockIdOf(f) === id) : [`${id}.json`];
    const copies = [];
    for (const file of files) { const l = await readLockFile(file); if (l) copies.push({ ...l, file }); }
    return { lock: pickLock(copies), copies };
  }

  // Svi lockovi (za Sets i Publish). Usput briše napuštene lockove i konfliktne kopije.
  async function readLocks() {
    ed.locksAt = Date.now();
    if (!canWrite()) return false;
    const byId = new Map();
    for (const file of await fs.listFileNames(store().root, LOCK_DIR).catch(() => [])) {
      const id = lockIdOf(file);
      if (!id) continue;
      const l = await readLockFile(file);
      if (!isLive(l)) { fs.removeFile(store().root, `${LOCK_DIR}/${file}`).catch(() => {}); continue; }
      if (!byId.has(id)) byId.set(id, []);
      byId.get(id).push(l);
    }
    const next = {};
    for (const [id, copies] of byId) {
      const l = pickLock(copies);
      if (lockState(l, who()) === 'other') next[id] = l;
    }
    const changed = JSON.stringify(next) !== JSON.stringify(ed.locks);
    ed.locks = next;
    return changed;
  }

  function syncLock() {
    const want = ed.id && canWrite() && who() ? { id: ed.id, who: who() } : null;
    if (ed.lock?.id === want?.id && ed.lock?.who === want?.who) return;
    releaseLock();
    if (want) claimLock(want.id, want.who);
  }

  async function claimLock(id, me, force = false) {
    ed.lock = { id, who: me, state: 'checking' };
    const { lock: cur } = await currentLock(id);
    if (ed.lock?.id !== id) return;
    const st = stateOf(cur, me);
    if ((st === 'other' || st === 'twin') && !force) {
      ed.lock = { id, who: me, state: st, other: cur };
      watchLock(id, me);
      env.render();
      return;
    }
    const since = st === 'mine' ? cur.since : null;
    const over = force || (st === 'mine' && !!cur.over);
    const mine = newLock(me, new Date(), since, TAB, over);
    await fs.writeFile(store().root, lockPath(id), JSON.stringify(mine) + '\n');
    if (ed.lock?.id !== id) {
      // Karta je u međuvremenu zatvorena: lock ne smije ostati.
      fs.removeFile(store().root, lockPath(id)).catch(() => {});
      return;
    }
    const l = { id, who: me, state: 'mine', since: mine.since, over };
    ed.lock = l;
    l.beat = setInterval(() => beat(l), HEARTBEAT_MS);
    // Drugi stroj je možda zaključao u isto vrijeme: Syncthing to donese za 10 do 15 s.
    l.settle = setTimeout(() => beat(l), SETTLE_MS);
    env.render();
  }

  // Svakih 30 s (i jednom nakon SETTLE_MS): je li karta još moja; ako jest, osvježi lock i obriši konfliktne kopije.
  // Bez unosa IDLE_MS i bez nespremljenog: pusti kartu (Paused), prvi klik ili tipka je opet zaključa.
  async function beat(l) {
    if (ed.lock !== l || l.state !== 'mine') return;
    const { lock: cur, copies } = await currentLock(l.id);
    if (ed.lock !== l) return;
    if (cur && stateOf(cur, l.who) !== 'mine') { stepDown(l, cur); return; }
    if (!ed.dirty && Date.now() - (ed.lastInput ?? 0) > IDLE_MS) { pauseLock(l); return; }
    await fs.writeFile(store().root, lockPath(l.id), JSON.stringify(newLock(l.who, new Date(), l.since, TAB, l.over)) + '\n').catch(() => {});
    for (const c of copies) if (isConflictCopy(c.file)) fs.removeFile(store().root, `${LOCK_DIR}/${c.file}`).catch(() => {});
  }

  function stopTimers(l) { clearInterval(l?.beat); clearTimeout(l?.settle); }

  // Netko drugi (ili moj drugi prozor) drži kartu: odstupi, spremanje se gasi.
  function stepDown(l, cur) {
    stopTimers(l);
    ed.lock = { id: l.id, who: l.who, state: stateOf(cur, l.who) === 'twin' ? 'twin' : 'other', other: cur };
    watchLock(l.id, l.who);
    env.render();
  }

  function pauseLock(l) {
    stopTimers(l);
    ed.lock = { id: l.id, who: l.who, state: 'paused' };
    fs.removeFile(store().root, lockPath(l.id)).catch(() => {});
    env.render();
  }

  // Tuđi lock: svakih 30 s pogledaj je li karta slobodna, pa je zaključaj za sebe.
  function watchLock(id, me) {
    const l = ed.lock;
    l.beat = setInterval(async () => {
      if (ed.lock !== l) { clearInterval(l.beat); return; }
      const { lock: cur } = await currentLock(id);
      if (ed.lock !== l) return;
      const st = stateOf(cur, me);
      if (st === 'free' || st === 'mine') {
        clearInterval(l.beat);
        claimLock(id, me);
      } else if (st !== l.state || cur.who !== l.other?.who || cur.tab !== l.other?.tab) {
        l.state = st;
        l.other = cur;
        env.render();
      }
    }, HEARTBEAT_MS);
  }

  // Prije spremanja: lock se ponovo pročita (Take over s drugog stroja se inače vidi tek za 30 s); Paused se vrati.
  async function ensureLock() {
    if (!ed.lock || !canWrite()) return;
    if (ed.lock.state === 'paused') await claimLock(ed.lock.id, ed.lock.who);
    const l = ed.lock;
    if (l?.state === 'mine') {
      const { lock: cur } = await currentLock(l.id);
      if (ed.lock === l && cur && stateOf(cur, l.who) !== 'mine') stepDown(l, cur);
    }
    if (lockBusy()) throw new Error(busyText());
  }

  // Svaki unos na stranici karte je znak da je netko tu; nakon Paused ga vraća.
  function touched() {
    ed.lastInput = Date.now();
    if (ed.lock?.state === 'paused' && ed.id === ed.lock.id) claimLock(ed.lock.id, ed.lock.who);
  }
  for (const t of ['pointerdown', 'keydown', 'wheel']) document.addEventListener(t, touched, { capture: true, passive: true });

  function releaseLock(unloading = false) {
    const l = ed.lock;
    ed.lock = null;
    if (!l) return;
    stopTimers(l);
    if (l.state !== 'mine' || !canWrite()) return;
    // Pri zatvaranju prozora nema vremena za čitanje: obriši odmah (server dobije zahtjev i nakon gašenja stranice).
    if (unloading) { fs.removeFile(store().root, lockPath(l.id)).catch(() => {}); return; }
    currentLock(l.id).then(({ copies }) => {
      const main = copies.find(c => c.file === `${l.id}.json`);
      if (main && stateOf(main, l.who) === 'mine') return fs.removeFile(store().root, lockPath(l.id));
    }).catch(() => {});
  }
  window.addEventListener('pagehide', () => releaseLock(true));
  // Stranica vraćena iz cachea preglednika (Natrag): zaključaj kartu ponovo.
  window.addEventListener('pageshow', e => { if (e.persisted) env.render(); });

  // ---------- Traits & aliases ----------

  // Popis traitova (kartica Traits iz appa), svi tagovi na kartama s preimenovanjem, i aliasi heroja.
  function renderTraitsPage() {
    const counts = new Map();
    for (const c of allCards()) {
      (c.traits ?? []).forEach((t, i) => {
        if (!t) return;
        const row = counts.get(t) ?? { first: 0, other: 0 };
        if (i === 0 && PORTRAIT.includes(c.type)) row.first++; else row.other++;
        counts.set(t, row);
      });
    }
    const rows = [...counts.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    return h('div', { class: 'ce-page' },
      env.renderTraits(),
      h('section', { class: 'panel' },
        h('h2', {}, 'Tags on the cards'),
        h('p', { class: 'muted' }, 'Every tag on the cards. Click a tag to rename it on every card (as drafts; Publish puts it into the game).'),
        h('table', { class: 'ce-pub-table ce-tag-table' },
          h('thead', {}, h('tr', {}, ['Tag', 'First tag on', 'Other tag on'].map(t => h('th', {}, t)))),
          h('tbody', {}, rows.map(([tag, n]) => {
            // Preimenovanje na klik (Marko 2026-11-06): ćelija postane polje s Rename i Cancel; Enter spremi, Esc odustane.
            const cell = h('td', {});
            const show = () => cell.replaceChildren(h('button', { class: 'link ce-tag-name', type: 'button', disabled: !canWrite(), title: canWrite() ? 'Rename this tag on every card' : '', onclick: edit }, tag));
            function edit() {
              const to = h('input', { value: tag, 'aria-label': `New name for ${tag}`, onkeydown: ev => { if (ev.key === 'Enter') { ev.preventDefault(); go2(); } else if (ev.key === 'Escape') show(); } });
              const go2 = () => env.guard(() => renameTag(tag, to.value.trim()));
              cell.replaceChildren(h('div', { class: 'ce-tag-rename' }, to, h('button', { class: 'ghost', type: 'button', onclick: go2 }, 'Rename'), h('button', { class: 'link', type: 'button', onclick: show }, 'Cancel')));
              to.focus();
              to.select();
            }
            show();
            return h('tr', {}, cell, h('td', { class: 'num' }, n.first || '–'), h('td', { class: 'num' }, n.other || '–'));
          })))));
  }

  // Preimenovanje taga na svim kartama kao nacrti (karta kojoj se vrati objavljeni popis ostane bez nacrta za tagove).
  async function renameTag(from, to) {
    if (!to || to === from) throw new Error('Write the new name first.');
    const fresh = await readDrafts();
    fresh.cards ??= {};
    let n = 0;
    const ids = [...db().cards.filter(c => EDIT_TYPES.includes(c.type) && !c.deleted).map(c => c.id),
      ...Object.entries(fresh.cards).filter(([id, d]) => d.new && !db().cards.some(c => c.id === id)).map(([id]) => id)];
    for (const c of ids.map(id => ({ id, ...(fresh.cards[id] ?? {}) }))) {
      const d = fresh.cards[c.id] ?? {};
      const traits = d.traits ?? db().cards.find(x => x.id === c.id)?.traits ?? c.traits ?? [];
      if (!traits.includes(from)) continue;
      const next = [...new Set(traits.map(t => (t === from ? to : t)))];
      const base = db().cards.find(x => x.id === c.id);
      const nd = { ...d, traits: next, updated: new Date().toISOString(), who: who() || undefined };
      if (base && sameVal(next, base.traits)) delete nd.traits;
      if (Object.keys(nd).every(k => k === 'updated' || k === 'who')) delete fresh.cards[c.id];
      else fresh.cards[c.id] = nd;
      n++;
    }
    if (!n) throw new Error(`No card has the tag ${from}.`);
    await writeJson(DRAFTS_PATH, fresh);
    ed.drafts = fresh;
    const inList = (env.state.traits?.traits ?? []).some(t => t.name === from);
    env.toast(`${from} → ${to} on ${n} ${n === 1 ? 'card' : 'cards'} (drafts).${inList ? ` ${from} is on the trait list above: rename it there too.` : ''}`);
    env.render();
  }

  // ---------- objava ----------

  const draftList = () => Object.entries(ed.drafts?.cards ?? {})
    .map(([id, d]) => ({ id, d, base: db().cards.find(c => c.id === id) ?? null }))
    .sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));

  // Razlike nacrta prema objavljenoj karti kao oznake (TEXT s riječima precrtano/zeleno, TAGS, FX, FRAME…).
  function changeChips(d, base) {
    const out = [];
    const card = { ...(base ?? {}), ...d };
    const chip = (label, ...body) => h('div', { class: 'ce-change' }, h('span', { class: 'ce-change-tag' }, label), h('span', {}, ...body));
    if (d.new) out.push(chip('NEW', 'new card'));
    if ('name' in d && base) out.push(chip('NAME', h('s', {}, base.name ?? ''), ' → ', h('span', { class: 'add' }, d.name ?? '')));
    if ('text' in d && base) out.push(chip('TEXT', ...wordDiff(base.text ?? '', d.text ?? '')));
    if ('traits' in d && base) {
      const a = base.traits ?? [];
      const b = d.traits ?? [];
      out.push(a[0] !== b[0] && PORTRAIT.includes(card.type) ? chip('TAGS', 'first tag ', h('s', {}, a[0] ?? '–'), ' → ', h('span', { class: 'add' }, b[0] ?? '–'))
        : chip('TAGS', b.filter(t => !a.includes(t)).map(t => `+${t}`).concat(a.filter(t => !b.includes(t)).map(t => `−${t}`)).join(' ')));
    }
    for (const k of ['cost', 'color', 'type', 'evo', 'hero', 'terrain']) if (k in d && base) out.push(chip(k.toUpperCase(), h('s', {}, String(base[k] ?? '–')), ' → ', h('span', { class: 'add' }, String(d[k] ?? '–'))));
    for (const k of ['stats', 'bonus']) if (k in d && base) out.push(chip(k.toUpperCase(), Object.entries(d[k] ?? {}).filter(([s, v]) => (base[k] ?? {})[s] !== v).map(([s, v]) => `${s.toUpperCase()} ${(base[k] ?? {})[s] ?? '–'} → ${v}`).join(', ') || 'changed'));
    if ('abilityNames' in d && base) out.push(chip('ABILITY', h('s', {}, base.abilityNames?.[0] ?? '–'), ' → ', h('span', { class: 'add' }, d.abilityNames?.[0] ?? '–')));
    if ('aliases' in d) out.push(chip('ALIASES', (d.aliases ?? []).join(', ')));
    if ('fx' in d || 'fxStatus' in d) out.push(chip('FX', d.fx ? `confirmed${d.who ? ` by ${d.who}` : ''}` : 'removed'));
    if (('art' in d || 'template' in d) && !base?.art) out.push(chip('FRAME', 'new frame (editor), art from Card Engine'));
    else if ('art' in d) out.push(chip('ART', 'new art'));
    else if ('artCrop' in d) out.push(chip('ART', 'art crop'));
    if ('emblem' in d || 'bg' in d) out.push(chip('PLATE', [d.emblem ? 'emblem' : null, d.bg ? `background ${d.bg}` : null].filter(Boolean).join(', ')));
    if ('coreImage' in d) out.push(chip('IMAGE', d.coreImage === 'effect' ? 'drawn from the effect' : 'uploaded'));
    if ('status' in d && Object.keys(d).length <= 4) out.push(chip('STATUS', d.status === 'done' ? 'ready' : 'not ready'));
    return out;
  }

  // The Work-in-progress set that holds a card back from Publish: its own set, or for a Combo the set of an
  // ingredient (a published Combo must not name a card the game does not have). null when nothing holds it.
  // WIP on the card itself (Marko 2026-11-15): the set is Work in progress, so this card waits for Publish.
  function wipBadge(id) {
    const code = wipSetOf(id, c => sets.isWip(c));
    return code ? h('span', { class: 'ce-st review ce-wip', title: `Set ${code} is Work in progress: this card stays out of Publish until the set is finished.` }, `${code} WIP`) : null;
  }

  // Introduced in for a Stage or Core (Marko 2026-11-15): optional; a card of a Work in progress set waits with it.
  function introducedField(w) {
    return h('label', { class: 'ce-field' }, h('span', {}, 'INTRODUCED IN'), h('select', { title: 'The set it comes out with. While that set is Work in progress, this card waits with it.',
      onchange: e => { snap(true); w.introducedIn = e.target.value || undefined; changed(); } }, h('option', { value: '' }, '–'),
      sets.list().map(s => h('option', { value: s.code, selected: s.code === w.introducedIn }, s.code))));
  }

  function wipSetOf(id, isWip) {
    if (isWip(setOf(id))) return setOf(id);
    const card = merged(db().cards.find(c => c.id === id) ?? { id });
    // A Stage or Core has no set in its code: it waits with the set it comes out with (Marko 2026-11-15).
    if (!/^[A-Z]+\d+$/.test(setOf(id)) && card.introducedIn && isWip(card.introducedIn)) return card.introducedIn;
    for (const ing of card.ingredients ?? []) if (ing && isWip(setOf(ing))) return setOf(ing);
    return null;
  }

  // Not ready › Ready: the card's draft gets status done without opening it (fresh read, so nothing else changes).
  async function markDone(id) {
    await readLocks();
    if (ed.locks[id]) throw new Error(`${ed.locks[id].who} has ${id} open. Try again after they close it.`);
    const fresh = await readDrafts();
    if (!fresh.cards?.[id]) throw new Error(`${id} has no draft any more.`);
    fresh.cards[id] = { ...fresh.cards[id], status: 'done', updated: new Date().toISOString(), who: who() || undefined };
    await writeJson(DRAFTS_PATH, fresh);
    ed.drafts = fresh;
    await logHistory(id, 'marked ready').catch(() => {});
    env.toast(`${id} is ready: it is in the Ready tab.`);
    env.render();
  }

  function renderPublish() {
    const list = draftList();
    const marko = who() === 'Marko';
    const locked = id => ed.locks[id] && lockState(ed.locks[id], who()) === 'other';
    const held = id => wipSetOf(id, id => sets.isWip(id));
    // A new card without art waits (Publish keeps it back), so it is not "ready".
    const noArt = ({ id, d, base }) => { const c = { ...(base ?? {}), ...d, id }; return !!d.new && !c.art && c.type !== 'Core'; };
    // Not ready (status draft) waits under Not ready (Marko 2026-11-15); a Core has no status.
    const notDone = ({ id, d, base }) => { const c = { ...(base ?? {}), ...d, id }; return c.type !== 'Core' && (c.status ?? 'draft') !== 'done'; };
    const ready = list.filter(x => !locked(x.id) && !held(x.id) && !noArt(x) && !notDone(x));
    const selected = ready.filter(x => !ed.pubOff.has(x.id));
    const why = !canPublish() ? 'Publish runs on a computer with the shared folder open (Chrome or Edge).'
      : !marko ? 'Only Marko publishes (Signed in as Marko).'
        : !ed.agency ? 'Agency FB is not on this computer: the card PNGs must be made on a computer that has it.'
          : !selected.length ? 'Nothing selected.' : null;
    const thumb = (card, px) => { const c = h('canvas', { class: 'ce-pub-thumb' }); thumbInto(c, card, px); return c; };
    const oldThumb = (base, px) => {
      const img = h('img', { class: 'ce-pub-thumb', alt: '' });
      img.style.width = `${px}px`;
      store().imageUrl(base, { thumb: true }).then(u => { if (u) img.src = u; });
      return img;
    };
    // Kartice (Marko 2026-11-15, mockup docs/private/mockups/publish, varijanta B): Ready s kvačicama je otvorena;
    // Work in progress (po setu, s "Set is finished"), No art i Being edited su kratki retci na svojim karticama.
    const wipList = list.filter(x => !locked(x.id) && held(x.id));
    const artList = list.filter(x => !locked(x.id) && !held(x.id) && noArt(x));
    const draftList2 = list.filter(x => !locked(x.id) && !held(x.id) && !noArt(x) && notDone(x));
    const lockList = list.filter(x => locked(x.id));
    const tabs = [['ready', 'Ready', ready.length, 't-ok'], ['draft', 'Not ready', draftList2.length, 't-wait'], ['wip', 'Work in progress', wipList.length, 't-wait'], ['art', 'No art', artList.length, 't-wait'], ['lock', 'Being edited', lockList.length, 't-lock']]
      .filter(([k, , n]) => k === 'ready' || n);
    if (!tabs.some(([k]) => k === ed.pubTab)) ed.pubTab = 'ready';
    const cardOfRow = ({ id, d, base }) => ({ ...(base ?? {}), ...d, id });
    const mini = (x, note, action = null) => {
      const card = cardOfRow(x);
      // The whole row opens the card in the editor (Marko 2026-11-15).
      return h('div', { class: 'ce-pub-mini', role: 'link', tabindex: 0, title: `Open ${x.id} in the editor`, onclick: () => go(x.id), onkeydown: e => { if (e.key === 'Enter') go(x.id); } },
        h('figure', {}, thumb(card, WIDE.includes(card.type) ? 84 : 60)),
        h('div', { class: 'ce-pub-body' }, h('h4', {}, card.name || x.id, h('small', {}, ` ${x.id}`)), h('p', { class: 'muted small' }, note)),
        action ?? h('span', { class: 'link accent' }, 'Open'));
    };
    const readyRow = ({ id, d, base }) => {
      const card = { ...(base ?? {}), ...d, id };
      const px = WIDE.includes(card.type) ? 168 : 120;
      return h('div', { class: 'ce-pub-row' },
        h('label', { class: 'ce-pub-check' }, h('input', { type: 'checkbox', checked: !ed.pubOff.has(id), onchange: e => { if (e.target.checked) ed.pubOff.delete(id); else ed.pubOff.add(id); env.render(); } })),
        h('div', { class: 'ce-pub-imgs' },
          base?.image ? h('figure', {}, oldThumb(base, px), h('figcaption', { class: 'muted small' }, 'Published')) : null,
          base?.image ? h('span', { class: 'ce-arrow' }, '→') : null,
          h('figure', {}, thumb(card, px), h('figcaption', { class: 'muted small' }, base?.image ? 'New' : 'New card'))),
        h('div', { class: 'ce-pub-body' },
          h('h3', {}, card.name || id, h('small', {}, ` ${id}`)),
          h('p', { class: 'muted small' }, `${d.who || '–'} · ${when(d.updated)}`),
          ...changeChips(d, base),
          !card.art && card.type !== 'Core' ? h('p', { class: 'muted small' }, 'No art: the old picture stays.') : null),
        h('button', { class: 'link accent', type: 'button', onclick: () => go(id) }, 'Open in editor'));
    };
    const toTab = k => () => { ed.pubTab = k; env.render(); };
    let body;
    if (ed.pubTab === 'wip') {
      const bySet = new Map();
      for (const x of wipList) { const s = held(x.id); if (!bySet.has(s)) bySet.set(s, []); bySet.get(s).push(x); }
      body = [...bySet].map(([code, xs]) => h('section', { class: 'ce-pub-set' },
        h('div', { class: 'ce-pub-set-head' }, h('h3', {}, sets.nameOf(code) === code ? code : sets.nameOf(code), h('small', {}, ` ${code} · ${xs.length} ${xs.length === 1 ? 'card' : 'cards'}`)),
          h('button', { class: 'ghost', type: 'button', disabled: !canWrite(), title: 'Switch Work in progress off: these cards move to Ready',
            onclick: () => env.guard(async () => { await sets.setWip(code, false); env.toast(`${code} is finished: its cards are in Ready.`); ed.pubTab = 'ready'; env.render(); }) }, 'Set is finished')),
        h('p', { class: 'muted small' }, `Set ${code} is Work in progress: its cards wait until it is finished.`),
        h('div', { class: 'ce-pub-minis' }, xs.map(x => mini(x, held(x.id) === setOf(x.id) || held(x.id) === cardOfRow(x).introducedIn && !cardOfRow(x).ingredients?.length
          ? `${x.d.who || '–'} · ${when(x.d.updated)}${noArt(x) ? ' · no art yet' : ''}`
          : `It uses a card of ${code}, so it waits with that set.`)))));
    } else if (ed.pubTab === 'draft') {
      body = [h('p', { class: 'muted small' }, 'Cards not marked Ready yet. ✓ Ready when one is finished: it moves to the Ready tab.'),
        h('div', { class: 'ce-pub-minis' }, draftList2.map(x => mini(x, `${x.d.who || '–'} · ${when(x.d.updated)}`,
          h('button', { class: 'ghost ce-pub-done', type: 'button', disabled: !canWrite(), title: 'Mark it Ready: it moves to the Ready tab',
            onclick: e => { e.stopPropagation(); env.guard(() => markDone(x.id)); } }, '✓ Ready'))))];
    } else if (ed.pubTab === 'art') {
      body = [h('p', { class: 'muted small' }, 'A new card waits until it has art: open it and add the art (or drag a picture onto it).'),
        h('div', { class: 'ce-pub-minis' }, artList.map(x => mini(x, `${x.d.who || '–'} · ${when(x.d.updated)}`)))];
    } else if (ed.pubTab === 'lock') {
      body = [h('div', { class: 'ce-pub-minis' }, lockList.map(x => mini(x, `🔒 ${ed.locks[x.id].who} is editing it now. It can be published after they save and close it.`)))];
    } else {
      const others = tabs.filter(([k]) => k !== 'ready');
      body = [...(ready.length ? ready.map(readyRow) : [h('p', { class: 'muted' }, list.length ? 'Nothing is ready to publish.' : 'Nothing waits for Publish.')]),
        others.length ? h('p', { class: 'small muted ce-pub-also' }, 'Also waiting: ', others.map(([k, label, n], i) => [i ? ' · ' : '',
          h('button', { class: 'link', type: 'button', onclick: toTab(k) }, k === 'wip' ? `${n} in ${[...new Set(wipList.map(x => held(x.id)))].join(', ')} (Work in progress)` : `${n} ${label.toLowerCase()}`)]).flat(), ' →') : null];
    }
    return h('div', { class: 'ce-page ce-publish' },
      h('header', { class: 'ce-page-head' },
        h('div', {}, h('h1', {}, 'Publish'), h('p', { class: 'muted' }, 'Changes saved in the editor. The game sees them only after you publish.')),
        h('div', { class: 'ce-page-actions' },
          sets.newCardButton(sets.current() ?? 'OP1', ['Hero', 'Evolution', 'Action', 'Equipment', 'Assist'], 'ghost'),
          h('button', { class: 'publish', type: 'button', disabled: !!why, title: why ?? '', onclick: () => env.guard(() => publishAll(selected.map(x => x.id))) }, `Publish ${selected.length} ${selected.length === 1 ? 'card' : 'cards'}`))),
      why && ready.length ? h('p', { class: 'muted small' }, why) : null,
      list.length ? h('div', { class: 'ce-pub-tabs', role: 'tablist' }, tabs.map(([k, label, n, kind]) => h('button', { type: 'button', role: 'tab', 'aria-selected': String(ed.pubTab === k),
        class: `${kind}${ed.pubTab === k ? ' on' : ''}`, onclick: toTab(k) }, label, h('span', { class: 'n' }, String(n))))) : null,
      h('div', { class: 'ce-pub-list' }, body),
      renderLast(marko));
  }

  // Riječi koje su otpale precrtane, nove zelene; isti dio sažet na "…" s ponešto riječi oko izmjene.
  function wordDiff(a, b) {
    const x = a.split(/\s+/).filter(Boolean);
    const y = b.split(/\s+/).filter(Boolean);
    const m = x.length;
    const n = y.length;
    const L = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
    for (let i = m - 1; i >= 0; i--) for (let j = n - 1; j >= 0; j--) L[i][j] = x[i] === y[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
    const ops = [];
    let i = 0;
    let j = 0;
    while (i < m || j < n) {
      if (i < m && j < n && x[i] === y[j]) { ops.push(['=', x[i]]); i++; j++; } else if (j < n && (i >= m || L[i][j + 1] >= L[i + 1][j])) { ops.push(['+', y[j]]); j++; } else { ops.push(['-', x[i]]); i++; }
    }
    const keep = new Set();
    ops.forEach((o, k) => { if (o[0] !== '=') for (let d = -3; d <= 3; d++) keep.add(k + d); });
    const out = [];
    let gap = false;
    ops.forEach((o, k) => {
      if (!keep.has(k)) { if (!gap && out.length) out.push('… '); gap = true; return; }
      if (gap && !out.length) out.push('… ');
      gap = false;
      out.push(o[0] === '=' ? `${o[1]} ` : h(o[0] === '+' ? 'span' : 's', { class: o[0] === '+' ? 'add' : '' }, o[1]), o[0] === '=' ? null : ' ');
    });
    if (gap) out.push('…');
    return out.filter(v => v !== null);
  }

  async function readLast() {
    return readJson(LAST_PUBLISH_PATH, null);
  }

  // Zadnja Objava i Undo (samo Marko, dok se baza nije mijenjala).
  function renderLast(marko) {
    if (!canWrite()) return null;
    if (ed.last === undefined) {
      ed.last = null;
      readLast().then(l => { ed.last = l ?? false; if (l) env.render(); });
      return null;
    }
    const l = ed.last;
    if (!l) return null;
    const ok = db().updated === l.after.updated;
    return h('div', { class: 'ce-last' },
      h('span', { class: 'small' }, `Last Publish: ${new Date(l.at).toLocaleString()}${l.who ? ` by ${l.who}` : ''}, ${Object.keys(l.drafts).length} cards${l.bumped ? `, version ${l.after.version}` : ''}.`),
      ok ? h('button', { class: 'ghost', type: 'button', disabled: !marko || !canPublish(), onclick: () => env.guard(undoPublish) }, 'Undo last Publish')
        : h('small', { class: 'muted' }, 'Cards changed since then, so it can no longer be undone.'));
  }

  // Undo zadnje Objave: baza kakva je bila prije nje (pod novom verzijom, da igra i deckovi vide promjenu),
  // nove slike van, objavljeni nacrti opet čekaju. Samo dok se baza u međuvremenu nije mijenjala.
  async function undoPublish() {
    await env.assertFresh();
    const last = await readLast();
    if (!last) throw new Error('No Publish to undo.');
    if (db().updated !== last.after.updated) throw new Error('The cards changed after that Publish (Import or another save), so it can no longer be undone.');
    if (!confirm(`Undo the Publish of ${new Date(last.at).toLocaleString()} (${Object.keys(last.drafts).length} cards)? The cards go back to how they were and wait as drafts again.`)) return;
    const restored = { ...last.before, version: db().version + (last.bumped ? 1 : 0), updated: new Date().toISOString() };
    await env.commitDb(restored);
    const after = await readDrafts();
    after.cards ??= {};
    for (const [id, d] of Object.entries(last.drafts)) after.cards[id] = after.cards[id] ? { ...d, ...after.cards[id] } : d;
    const files = await fs.listFileNames(store().root, 'data/images').catch(() => []);
    for (const [id, d] of Object.entries(last.drafts)) {
      if (!d.new) continue;
      for (const name of files.filter(n => n.startsWith(`${id}.`))) await fs.removeFile(store().root, `data/images/${name}`).catch(() => {});
    }
    await writeJson(DRAFTS_PATH, after);
    await fs.removeFile(store().root, LAST_PUBLISH_PATH).catch(() => {});
    ed.drafts = after;
    ed.last = false;
    for (const id of Object.keys(last.drafts)) await logHistory(id, 'Publish undone').catch(() => {});
    env.toast(`Publish undone: ${Object.keys(last.drafts).length} cards are drafts again${last.bumped ? ` (version ${restored.version})` : ''}.`);
    env.render();
  }

  // Objava odabranih nacrta: PNG svake karte s artom (renderer), baza i povijest (env.commitDb), nacrti van.
  // Karta bez arta zadržava staru sliku (Card Engine PNG); nova karta bez arta čeka.
  async function publishAll(ids) {
    await env.assertFresh();
    const fresh = await readDrafts();
    await readLocks();
    // The other computer may have switched a set to Work in progress since this page was drawn.
    const wip = await sets.freshWip();
    const drafts = {};
    const isDraft = id => { const c = { ...(db().cards.find(x => x.id === id) ?? {}), ...fresh.cards[id] }; return c.type !== 'Core' && (c.status ?? 'draft') !== 'done'; };
    for (const id of ids) if (fresh.cards?.[id] && !ed.locks[id] && !wipSetOf(id, code => wip.has(code)) && !isDraft(id)) drafts[id] = fresh.cards[id];
    const list = Object.keys(drafts);
    if (!list.length) throw new Error('Nothing to publish.');
    if (!confirm(`Publish ${list.length} ${list.length === 1 ? 'card' : 'cards'} into the game?`)) return;
    const before = db();
    // Nova Objava zamjenjuje zadnju: Undo prethodne više nije moguć, pa njene stare slike mogu van. To ide PRIJE
    // crtanja novih PNG-ova: poslije bi obrisalo baš njih (isti kod karte, drugi hash od objavljenog; 5. 11. 2026).
    await env.dropOldImages();
    const images = {};
    const kept = [];
    for (const id of list) {
      const base = db().cards.find(c => c.id === id) ?? (drafts[id].new ? { id } : null);
      if (!base) continue;
      const card = { ...base, ...drafts[id] };
      const core = card.type === 'Core' && coreMode(card) === 'effect';
      const url = card.art ? await store().dataUrl(card.art) : null;
      const art = url ? await loadImage(url).catch(() => null) : null;
      if (!art && !core) { if (drafts[id].new) delete drafts[id]; kept.push(id); continue; }
      const heroOfCard = card.type === 'Evolution' ? db().cards.find(x => x.type === 'Hero' && x.name === card.hero) : null;
      const emblemPath = card.emblem ?? (heroOfCard ? drafts[heroOfCard.id]?.emblem ?? heroOfCard.emblem : null);
      const eUrl = emblemPath ? await store().dataUrl(emblemPath) : null;
      const emblem = eUrl ? await loadImage(eUrl).catch(() => null) : null;
      const canvas = document.createElement('canvas');
      renderCard(canvas, decorate(card, applyDrafts(db(), drafts, {}).db.cards.filter(c => !c.deleted)), await templateFor(card), art, emblem);
      const blob = await new Promise(r => canvas.toBlob(r, 'image/png'));
      const bytes = new Uint8Array(await blob.arrayBuffer());
      const hash = await imageHashOf(bytes);
      if (hash === base.imageHash) continue;
      await fs.writeFile(store().root, `data/images/${id}.${hash}.png`, bytes);
      images[id] = hash;
    }
    // Combo (2026-11-07): the spark by the code shows on a card that is an ingredient of some combo, so the
    // ingredients of a published combo (old and new) are drawn again from the cards as they will be.
    const afterCards = applyDrafts(db(), drafts, {}).db.cards.filter(c => !c.deleted);
    const redo = new Set();
    for (const id of list) {
      const was = db().cards.find(c => c.id === id);
      const now = afterCards.find(c => c.id === id);
      if (was?.type === 'Combo' || now?.type === 'Combo') for (const x of touchedIngredients(was, now)) if (x && !drafts[x]) redo.add(x);
    }
    for (const id of redo) {
      const card = afterCards.find(c => c.id === id);
      if (!card?.art) continue;
      const url = await store().dataUrl(card.art);
      const art = url ? await loadImage(url).catch(() => null) : null;
      if (!art) continue;
      const canvas = document.createElement('canvas');
      renderCard(canvas, decorate(card, afterCards), await templateFor(card), art, null);
      const blob = await new Promise(r => canvas.toBlob(r, 'image/png'));
      const bytes = new Uint8Array(await blob.arrayBuffer());
      const hash = await imageHashOf(bytes);
      if (hash === card.imageHash) continue;
      await fs.writeFile(store().root, `data/images/${id}.${hash}.png`, bytes);
      images[id] = hash;
    }
    const { db: next, changed, bumped } = applyDrafts(db(), drafts, images);
    if (changed) {
      await env.commitDb(next, { keepOld: true });
      await writeJson(LAST_PUBLISH_PATH, { at: new Date().toISOString(), who: who(), bumped, after: { version: next.version, updated: next.updated }, drafts, before });
      ed.last = undefined;
    }
    // Nacrti spremljeni dok je Objava trajala ostaju za iduću.
    const after = await readDrafts();
    for (const id of Object.keys(drafts)) if (after.cards?.[id]?.updated === drafts[id].updated) delete after.cards[id];
    await writeJson(DRAFTS_PATH, after);
    ed.drafts = after;
    for (const id of Object.keys(drafts)) await logHistory(id, `published${bumped ? ` v${next.version}` : ''}`).catch(() => {});
    const parts = [`${changed} ${changed === 1 ? 'card' : 'cards'}`, `${Object.keys(images).length} new PNGs`];
    if (kept.length) parts.push(`no art yet (old picture kept, new cards wait): ${kept.join(', ')}`);
    env.toast(`Published${bumped ? ` (version ${next.version})` : changed ? ' (look only)' : ''}: ${parts.join(', ')}. Next: fx proposals for the game (ask Claude Code to run them).`);
    env.render();
  }

  // ---------- podstranice ----------

  const guide = createGuideView({ h, store, canWrite, who, render: env.render, guard: env.guard, toast: env.toast, onSaved: g => { ed.guide = g; } });
  // Spremljen okvir: editor ga učita iznova, sličice se crtaju iznova.
  const frames = createFramesView({ h, state: env.state, store, canWrite, who, render: env.render, guard: env.guard, toast: env.toast, drafts: () => ed.drafts, onSaved: name => { delete ed.tpls[name]; ed.thumbs.clear(); } });
  const sets = createSetsView({
    h, state: env.state, store, canWrite, who, render: env.render, guard: env.guard, toast: env.toast,
    cards: allCards, drafts: () => ed.drafts, locks: () => ed.locks, thumbInto, go: id => go(id), newCard, nextId,
    pictureStale, checkPictures, redrawAll, canPublish,
    // The Work in progress set a card waits with (its own, Introduced in, or a combo ingredient's), or null.
    heldBy: id => wipSetOf(id, code => sets.isWip(code)),
    stalePictures: (prefix = '') => [...stale.ids].filter(([id, out]) => out && id.startsWith(prefix)).length,
  });

  return {
    render, isCardPage, isDirty: () => ed.dirty, newCard, who, setWho, leave,
    waiting: () => Object.keys(ed.drafts?.cards ?? {}).length,
    wishes: () => (ed.wishlist?.items ?? []).filter(i => i.status === 'open').length,
  };
}

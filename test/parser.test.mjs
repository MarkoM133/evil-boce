// Testovi parsera i uvoza na izmišljenim kartama (repo je javan, prave karte su u docs/private).
// Pokretanje: node --test test/
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseCardEngineXml, cleanText } from '../js/parse.js';
import { analyzeExport, buildPublish, applyAppEdits, obsoleteImages, emptyDb, thumbPlan, archiveFolder, archivePath, emptyChangelog, changelogEntry, appendChangelog, changesSince, describeChange } from '../js/importer.js';
import { deckChanges } from '../js/deck.js';

const RGB = { Cyan: [0, 255, 255], Red: [255, 0, 0], White: [255, 255, 255], Odd: [10, 20, 30] };
const ICON = { kb: 24, pwr: 25, rng: 26, dmg: 27, hp: 28 };

function el(kind, t, x, y, rgb = [255, 255, 255], active = true) {
  const esc = String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return `<Element><ID>1</ID><Tag /><Active>${active}</Active><SizeDelta><x>1</x><y>1</y></SizeDelta>
    <Position><x>${x}</x><y>${y}</y></Position><Text>${esc}</Text><font />
    <color><r>${rgb[0]}</r><g>${rgb[1]}</g><b>${rgb[2]}</b><a>255</a></color>
    <Type>${kind === 'text' ? 0 : 1}</Type></Element>`;
}

function card({ name, code, type, color = 'Cyan', cost, evo, icons = {}, traits, text, extra = [] }) {
  const els = [el('image', 'frame_2', 0, 0)];
  if (color) els.push(el('image', 'p_frame_11', 0, 0, RGB[color]));
  els.push(el('text', name, 0, 460.97));
  if (code) els.push(el('text', code, 300, -480));
  if (type) els.push(el('text', type, -212.5, -150));
  if (cost !== undefined) els.push(el('text', cost, 283, 461));
  if (evo !== undefined) els.push(el('text', evo, -297, 461));
  let row = 0;
  for (const [k, v] of Object.entries(icons)) {
    const y = -60 - 40 * row++;
    els.push(el('image', `tabletop_icons_${ICON[k]}`, -60, y));
    els.push(el('text', v, 40, y + 1));
    els.push(el('text', '99', 200, y));
  }
  if (traits) els.push(el('text', traits, 158.00006, -456.31));
  if (text !== undefined) els.push(el('text', text, 0, -300));
  els.push(...extra);
  return `<Card><ID>123</ID><Quantity>1</Quantity><Name>${name}</Name><TemplateID>9</TemplateID>
    <Front><useMask>true</useMask><Elements>${els.join('')}</Elements></Front><Back /></Card>`;
}

const xml = (...cards) => `<?xml version="1.0" encoding="utf-8"?>\n<ArrayOfCard xmlns:xsd="x">${cards.join('')}</ArrayOfCard>`;

const HERO = { name: 'Hero A', code: 'OP9-001', type: 'Character', icons: { hp: '8', dmg: '3', pwr: '3000', rng: '4', kb: '3' }, traits: 'Crew/Fruit', text: '<sprite=3 color=#00FFFF><b>Postroll:</b> Hero A heals 2<sprite=0 color=#00FF00>.' };
const ACTION = { name: 'Punch', code: 'OP9-002', type: 'Action', cost: '1', icons: { pwr: '+2000' }, traits: 'Hero A', text: '<b>Battle Phase:</b>' };
const EVO = { name: 'Hero A, Big Form', code: 'OP9-003', type: 'Evolution', cost: '2', evo: '1', icons: { hp: '10', dmg: '3', pwr: '4000', rng: '4', kb: '3' }, traits: 'Crew', text: 'x' };
const STAGE = { name: 'Island', code: 'Stage-009', color: null, text: 'When revealed.' };
const TOKEN = { name: '+2 Damage', color: null, text: '+2 <sprite=1>' };

const png = (bytes, path, lastModified = 1) => ({ path, lastModified, getBytes: async () => new Uint8Array(bytes) });

test('cleanText: sprite, bold i vodeći Range', () => {
  assert.equal(cleanText(HERO.text), '[Range] Postroll: Hero A heals 2 HP.');
  assert.equal(cleanText('Gains +1000<sprite=2 color=#FFFF00> now .'), 'Gains +1000 Power now.');
});

test('parser: Character, Action, Evolution, Stage, token', () => {
  const r = parseCardEngineXml(xml(card(HERO), card(ACTION), card(EVO), card(STAGE), card(TOKEN)));
  assert.equal(r.length, 5);
  const [h, a, e, s, t] = r;
  assert.deepEqual(h.card, {
    id: 'OP9-001', name: 'Hero A', type: 'Character', color: 'Cyan',
    stats: { hp: 8, dmg: 3, pwr: 3000, rng: 4, kb: 3 },
    traits: ['Crew', 'Fruit'], text: '[Range] Postroll: Hero A heals 2 HP.',
  });
  assert.deepEqual(h.problems, []);
  assert.deepEqual(a.card, { id: 'OP9-002', name: 'Punch', type: 'Action', color: 'Cyan', cost: 1, bonus: { pwr: 2000 }, traits: ['Hero A'], text: 'Battle Phase:' });
  assert.equal(e.card.hero, 'Hero A');
  assert.equal(e.card.evo, 1);
  assert.equal(e.card.cost, 2);
  assert.equal(e.card.stats.pwr, 4000);
  assert.equal(s.card.type, 'Stage');
  assert.equal(s.card.color, null);
  assert.deepEqual(s.problems, []);
  assert.equal(t.skip, true);
});

test('parser: vrijednosti bez predznaka idu u values', () => {
  const [r] = parseCardEngineXml(xml(card({ ...ACTION, icons: { kb: '3', rng: '3', dmg: '-2' } })));
  assert.deepEqual(r.card.bonus, { dmg: -2 });
  assert.deepEqual(r.card.values, { rng: 3, kb: 3 });
  assert.equal(r.problems[0].level, 'warn');
});

test('parser: greške (kod, boja, cost, statsi)', () => {
  const r = parseCardEngineXml(xml(
    card({ ...ACTION, code: 'OP-032' }),
    card({ ...ACTION, code: 'OP9-010', color: 'White' }),
    card({ ...ACTION, code: 'OP9-011', color: 'Odd' }),
    card({ ...ACTION, code: 'OP9-012', cost: undefined }),
    card({ ...HERO, code: 'OP9-013', icons: { hp: '8' } }),
    card({ ...ACTION, code: 'OP9-014', type: undefined }),
  ));
  const msgs = r.map(x => x.problems.filter(p => p.level === 'error').map(p => p.msg).join(' | '));
  assert.match(msgs[0], /ne odgovara uzorku/);
  assert.match(msgs[1], /nepoznat ton/);
  assert.match(msgs[2], /nepoznat ton/);
  assert.match(msgs[3], /nema costa/);
  assert.match(msgs[4], /nedostaju statsi: dmg, pwr, rng, kb/);
  assert.match(msgs[5], /nema tipa/);
});

test('parser: neaktivni elementi se ignoriraju', () => {
  const [r] = parseCardEngineXml(xml(card({ ...ACTION, extra: [el('text', 'Equipment', -212.5, -150, undefined, false)] })));
  assert.equal(r.card.type, 'Action');
});

async function firstImport() {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/all.xml', text: xml(card(HERO), card(ACTION), card(EVO), card(STAGE), card(TOKEN)), lastModified: 1 }],
    pngFiles: [png([1], 'export/Hero A.png'), png([2], 'export/Punch.png'), png([3], 'export/Hero A, Big Form.png'), png([4], 'export/Island.png'), png([5], 'export/+2 Damage.png')],
    db: emptyDb(),
  });
  return { a, pub: buildPublish(emptyDb(), a, new Date('2026-10-22T10:00:00Z')) };
}

test('uvoz u praznu bazu', async () => {
  const { a, pub } = await firstImport();
  assert.deepEqual(a.errors, []);
  assert.deepEqual(a.entries.map(e => e.status), ['new', 'new', 'new', 'new']);
  assert.ok(a.infos.some(i => /tokeni/.test(i.msg)));
  assert.ok(a.infos.some(i => /\+2 Damage\.png/.test(i.msg)));
  assert.equal(pub.db.version, 1);
  assert.equal(pub.writes.length, 4);
  const hero = pub.db.cards.find(c => c.id === 'OP9-001');
  assert.equal(hero.wt, 2);
  assert.equal(hero.bakugan, 'Hero A');
  assert.equal(hero.rev, 1);
  assert.equal(hero.deleted, false);
  assert.match(hero.image, /^images\/OP9-001\.[0-9a-f]{8}\.png$/);
  assert.deepEqual(Object.keys(hero), ['id', 'name', 'type', 'color', 'stats', 'wt', 'traits', 'text', 'bakugan', 'image', 'imageHash', 'rev', 'deleted']);
  assert.equal(pub.db.cards.find(c => c.id === 'OP9-002').wt, undefined);
});

test('djelomični uvoz: promjena, ista karta, karta koje nema ostaje, app polja ostaju', async () => {
  const { pub } = await firstImport();
  const edited = applyAppEdits(pub.db, { 'OP9-001': { wt: 3, bakugan: 'Ball A' } }).db;
  assert.equal(edited.version, 2);
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/edit.xml', text: xml(card({ ...HERO, icons: { ...HERO.icons, hp: '9' } }), card(ACTION)), lastModified: 5 }],
    pngFiles: [png([1], 'export/Hero A.png'), png([9], 'export/Punch.png')],
    db: edited,
  });
  assert.deepEqual(a.errors, []);
  const [h, p] = a.entries;
  assert.equal(h.status, 'changed');
  assert.deepEqual(h.diffs, ['stats']);
  assert.equal(h.imageChanged, false);
  assert.equal(p.status, 'changed');
  assert.deepEqual(p.diffs, []);
  assert.equal(p.imageChanged, true);
  const next = buildPublish(edited, a).db;
  assert.equal(next.version, 3);
  assert.equal(next.cards.length, 4);
  const hero = next.cards.find(c => c.id === 'OP9-001');
  assert.equal(hero.stats.hp, 9);
  assert.equal(hero.wt, 3);
  assert.equal(hero.bakugan, 'Ball A');
  assert.equal(hero.rev, 3);
  assert.equal(next.cards.find(c => c.id === 'OP9-003').rev, 1);
});

test('isti uvoz drugi put ne mijenja verziju', async () => {
  const { pub } = await firstImport();
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/all.xml', text: xml(card(HERO), card(ACTION), card(EVO), card(STAGE)), lastModified: 1 }],
    pngFiles: [png([1], 'export/Hero A.png'), png([2], 'export/Punch.png'), png([3], 'export/Hero A, Big Form.png'), png([4], 'export/Island.png')],
    db: pub.db,
  });
  assert.ok(a.entries.every(e => e.status === 'same'));
  assert.equal(buildPublish(pub.db, a).changed, 0);
});

test('ista karta u dva XML-a: vrijedi noviji', async () => {
  const a = await analyzeExport({
    xmlFiles: [
      { path: 'export/new.xml', text: xml(card({ ...ACTION, cost: '3' })), lastModified: 9 },
      { path: 'export/old.xml', text: xml(card(ACTION)), lastModified: 1 },
    ],
    pngFiles: [png([2], 'export/Punch.png')],
    db: emptyDb(),
  });
  assert.equal(a.entries[0].card.cost, 3);
  assert.ok(a.warnings.some(w => /noviji export\/new\.xml/.test(w.msg)));
});

test('provjere: dupla imena, Evolution bez heroja, bez PNG-a', async () => {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(EVO), card(ACTION), card({ ...ACTION, code: 'OP9-020' })), lastModified: 1 }],
    pngFiles: [png([2], 'export/Punch.png')],
    db: emptyDb(),
  });
  const msgs = a.errors.map(e => `${e.id}: ${e.msg}`).join('\n');
  assert.match(msgs, /OP9-003: nova karta bez PNG-a/);
  assert.match(msgs, /OP9-002: PNG "Punch.png" ne zna se kojoj karti pripada/);
  assert.match(msgs, /heroj "Hero A" ne postoji/);
});

test('promijenjena karta bez PNG-a zadržava staru sliku', async () => {
  const { pub } = await firstImport();
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card({ ...ACTION, cost: '2' })), lastModified: 1 }],
    pngFiles: [],
    db: pub.db,
  });
  assert.deepEqual(a.errors, []);
  assert.match(a.warnings[0].msg, /ostaje stara slika/);
  const next = buildPublish(pub.db, a);
  assert.equal(next.writes.length, 0);
  const old = pub.db.cards.find(c => c.id === 'OP9-002');
  assert.equal(next.db.cards.find(c => c.id === 'OP9-002').image, old.image);
});

test('obsoleteImages: briše se tek kad nova verzija ima Steam URL', () => {
  const db = { version: 1, cards: [{ id: 'OP9-001', imageHash: 'bbbbbbbb' }] };
  const files = ['OP9-001.aaaaaaaa.png', 'OP9-001.bbbbbbbb.png'];
  assert.deepEqual(obsoleteImages(db, files, {}), []);
  assert.deepEqual(obsoleteImages(db, files, { 'OP9-001.bbbbbbbb': 'https://x' }), ['OP9-001.aaaaaaaa.png']);
});

test('thumbPlan: nedostajuće i stare sličice', () => {
  const db = { cards: [{ id: 'OP9-001', image: 'images/OP9-001.bbbbbbbb.png', imageHash: 'bbbbbbbb' }, { id: 'OP9-002', image: 'images/OP9-002.cccccccc.png', imageHash: 'cccccccc' }, { id: 'X', image: null, imageHash: null }] };
  const plan = thumbPlan(db, ['OP9-001.aaaaaaaa.jpg', 'OP9-002.cccccccc.jpg']);
  assert.deepEqual(plan.missing.map(c => c.id), ['OP9-001']);
  assert.deepEqual(plan.extra, ['OP9-001.aaaaaaaa.jpg']);
});

test('sanduče: arhiva po datumu, ista struktura podfoldera', () => {
  const folder = archiveFolder(new Date(2026, 9, 23, 9, 5));
  assert.equal(folder, 'export/objavljeno/2026-10-23 09.05');
  assert.equal(archivePath('export/Nove/Luffy.png', folder), 'export/objavljeno/2026-10-23 09.05/Nove/Luffy.png');
  assert.equal(archivePath('export/a.xml', folder), 'export/objavljeno/2026-10-23 09.05/a.xml');
});

test('prazan export/: nema grešaka ni promjena', async () => {
  const a = await analyzeExport({ xmlFiles: [], pngFiles: [], db: emptyDb() });
  assert.deepEqual([a.entries, a.errors, a.warnings], [[], [], []]);
});

test('promijenjeni podaci, a isti PNG: upozorenje da je slika možda stara', async () => {
  const { pub } = await firstImport();
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card({ ...ACTION, cost: '2' })), lastModified: 1 }],
    pngFiles: [png([2], 'export/Punch.png')],
    db: pub.db,
  });
  const e = a.entries.find(x => x.id === 'OP9-002');
  assert.equal(e.status, 'changed');
  assert.equal(e.staleImage, true);
  assert.match(a.warnings.map(w => w.msg).join('\n'), /promijenjeno \(cost\), a PNG je isti kao prije; slika je možda stara/);
  const fresh = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card({ ...ACTION, cost: '2' })), lastModified: 1 }],
    pngFiles: [png([9], 'export/Punch.png')],
    db: pub.db,
  });
  assert.equal(fresh.entries.find(x => x.id === 'OP9-002').staleImage, false);
  assert.deepEqual(fresh.warnings, []);
});

test('sam PNG bez XML-a: nova slika postojeće karte po imenu', async () => {
  const { pub } = await firstImport();
  const a = await analyzeExport({ xmlFiles: [], pngFiles: [png([9], 'export/Punch.png'), png([3], 'export/Hero A, Big Form.png'), png([7], 'export/Nepoznato.png')], db: pub.db });
  assert.deepEqual(a.errors, []);
  assert.deepEqual(a.entries.map(e => [e.id, e.status, e.imageChanged]), [['OP9-002', 'changed', true], ['OP9-003', 'same', false]]);
  assert.ok(a.infos.some(i => /Nepoznato\.png/.test(i.msg)));
  const next = buildPublish(pub.db, a);
  const old = pub.db.cards.find(c => c.id === 'OP9-002');
  const now = next.db.cards.find(c => c.id === 'OP9-002');
  assert.notEqual(now.imageHash, old.imageHash);
  assert.equal(now.rev, old.rev + 1);
  for (const k of ['name', 'type', 'cost', 'text', 'traits']) assert.deepEqual(now[k], old[k]);
  assert.equal(next.writes.length, 1);
});

test('povijest: zapis po verziji, promjene od verzije, promjene u decku', async () => {
  const { pub } = await firstImport();
  let log = appendChangelog(emptyChangelog(), changelogEntry(emptyDb(), pub.db));
  assert.equal(log.entries[0].version, 1);
  assert.deepEqual(log.entries[0].cards.map(c => c.kind), ['new', 'new', 'new', 'new']);

  // v2: Punch dobije novi cost i sliku; v3: Island maknut (app polje).
  const a = await analyzeExport({ xmlFiles: [{ path: 'export/x.xml', text: xml(card({ ...ACTION, cost: '2' })), lastModified: 1 }], pngFiles: [png([9], 'export/Punch.png')], db: pub.db });
  const v2 = buildPublish(pub.db, a, new Date('2026-10-23T10:00:00Z')).db;
  log = appendChangelog(log, changelogEntry(pub.db, v2));
  const v3 = applyAppEdits(v2, { 'Stage-009': { deleted: true } }).db;
  log = appendChangelog(log, changelogEntry(v2, v3));
  assert.deepEqual(log.entries.map(e => e.version), [1, 2, 3]);
  assert.deepEqual(log.entries[1].cards, [{ id: 'OP9-002', name: 'Punch', kind: 'changed', fields: ['cost'], image: true }]);
  assert.equal(describeChange(log.entries[1].cards[0]), 'cost, slika');
  assert.equal(describeChange(log.entries[2].cards[0]), 'maknuta');

  // Bez promjena nema novog zapisa.
  assert.equal(appendChangelog(log, changelogEntry(v3, v3)), log);

  const since1 = changesSince(log, 1);
  assert.deepEqual([...since1.keys()], ['OP9-002', 'Stage-009']);
  assert.deepEqual([...changesSince(log, 2).keys()], ['Stage-009']);

  const deck = { heroes: ['OP9-001'], cards: { 'OP9-002': 2, 'OP9-003': 0 } };
  assert.deepEqual(deckChanges(deck, since1).map(x => [x.id, x.changes.map(c => c.version)]), [['OP9-002', [2]]]);
  assert.deepEqual(deckChanges(deck, changesSince(log, 0)), [{ id: 'OP9-002', changes: [{ version: 2, kind: 'changed', fields: ['cost'], image: true }] }]);
});

test('kodovi drugih setova: DBZ-015 i JJ5-001 su ispravni, OP bez broja seta nije', () => {
  const parsed = parseCardEngineXml(xml(card({ ...ACTION, code: 'DBZ-015' }), card({ ...ACTION, name: 'Kick', code: 'JJ5-001' }), card({ ...ACTION, name: 'Bad', code: 'OP-033' })));
  assert.deepEqual(parsed.map(p => [p.code, p.problems.filter(x => x.level === 'error').length]), [['DBZ-015', 0], ['JJ5-001', 0], ['OP-033', 1]]);
});

test('PNG "KOD Ime.png": isto ime u dva seta, svaka karta svoju sliku', async () => {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(ACTION), card({ ...ACTION, code: 'DBZ-002', color: 'Red' })), lastModified: 1 }],
    pngFiles: [png([2], 'export/OP9-002 Punch.png'), png([7], 'export/DBZ/DBZ-002 Punch.png')],
    db: emptyDb(),
  });
  assert.deepEqual(a.errors, []);
  assert.match(a.warnings.map(w => w.msg).join('\n'), /isto ime "Punch" imaju DBZ-002, OP9-002; to je dopušteno/);
  assert.deepEqual(a.entries.map(e => [e.id, e.png.path]), [['DBZ-002', 'export/DBZ/DBZ-002 Punch.png'], ['OP9-002', 'export/OP9-002 Punch.png']]);
  assert.notEqual(a.entries[0].imageHash, a.entries[1].imageHash);
});

test('PNG s kodom ima prednost pred PNG-om s imenom; i sam kod je dovoljan', async () => {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(ACTION), card(HERO)), lastModified: 1 }],
    pngFiles: [png([2], 'export/Punch.png'), png([3], 'export/OP9-002 Punch.png'), png([1], 'export/OP9-001.png')],
    db: emptyDb(),
  });
  assert.deepEqual(a.errors, []);
  assert.deepEqual(a.entries.map(e => [e.id, e.png.path]), [['OP9-001', 'export/OP9-001.png'], ['OP9-002', 'export/OP9-002 Punch.png']]);
  assert.match(a.infos.map(i => i.msg).join('\n'), /preskočeno 1 PNG-ova.*Punch\.png/);
});

test('heroj s istim imenom kao druga karta je greška', async () => {
  const a = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(HERO), card({ ...ACTION, name: 'Hero A', code: 'DBZ-003' })), lastModified: 1 }],
    pngFiles: [png([1], 'export/OP9-001 Hero A.png'), png([2], 'export/DBZ-003 Hero A.png')],
    db: emptyDb(),
  });
  assert.match(a.errors.map(e => e.msg).join('\n'), /ime "Hero A" imaju .*heroj mora imati jedinstveno ime/);
});

test('sam PNG: po kodu radi uvijek, po imenu samo kad je ime jednoznačno', async () => {
  const first = await analyzeExport({
    xmlFiles: [{ path: 'export/x.xml', text: xml(card(ACTION), card({ ...ACTION, code: 'DBZ-002', color: 'Red' })), lastModified: 1 }],
    pngFiles: [png([2], 'export/OP9-002 Punch.png'), png([7], 'export/DBZ-002 Punch.png')],
    db: emptyDb(),
  });
  const db = buildPublish(emptyDb(), first).db;
  const byCode = await analyzeExport({ xmlFiles: [], pngFiles: [png([8], 'export/DBZ-002 Punch.png')], db });
  assert.deepEqual(byCode.errors, []);
  assert.deepEqual(byCode.entries.map(e => [e.id, e.status, e.imageChanged]), [['DBZ-002', 'changed', true]]);
  const byName = await analyzeExport({ xmlFiles: [], pngFiles: [png([8], 'export/Punch.png')], db });
  assert.match(byName.errors.map(e => e.msg).join('\n'), /isto ime imaju DBZ-002 i OP9-002; PNG mora počinjati kodom/);
  assert.deepEqual(byName.entries, []);
});

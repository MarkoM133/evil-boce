// Crtanje karte za editor karata: iz karte, predloška (data/card-frames/<predložak>/layout.json) i arta
// nacrta platno 1500×2100. Isti modul koriste preview u editoru, Objava (PNG) i provjere.
// Predložak je podatak: slojevi okvira (Card Engine exporti, bijeli, tintaju se bojom karte), prozor arta
// i kućice za tekst. Dok pravih slojeva nema, crta se privremeni okvir po boji (interim/<Boja>.png).

export const CARD_W = 1500;
export const CARD_H = 2100;

// Boje karata kao u Card Engineu (tinta okvira) i za oznake faza.
export const TINTS = { Cyan: '#00ffff', Yellow: '#ffff00', Purple: '#ff00ff', Red: '#ff0000', Blue: '#0000ff', Green: '#00ff00' };
const STAT_TINTS = { pwr: '#ffff00', dmg: '#ff0000', kb: '#0000ff', rng: '#00ffff', hp: '#00ff00' };
const LIGHT = new Set(['Cyan', 'Yellow', 'Green']);

const TITLE_FONT = '"Agency FB", "Barlow Condensed", "Arial Narrow", sans-serif';
const TEXT_FONT = '"Barlow Semi Condensed", "Barlow Condensed", "Arial Narrow", sans-serif';

const PHASE_RE = /^((?:Start|Preroll|Roll|Postroll|Battle|End)(?: Phase)?)(\s+Once Per Turn)?\s*:\s*/i;
const RANGE_RE = /^\[Range\]\s*/i;
const COND_RE = /^(If [^,]+,)\s*/;
// Ikone u tekstu: riječ stata iza broja ili iza more/less (kako je Card Engine crtao sprite: "heals 3 HP",
// "+2000 Power", "more HP"; HP i DMG su ikona i bez broja), stari tokeni [PWR]…, i {Trait} podebljano. Tekst karte ostaje u riječima (igra ih čita).
const ICON_RE = /\[(PWR|DMG|HP|RNG|KB)\]|\{([^}]+)\}|(?<=\d|\bmore|\bless)\s?(HP|DMG|Power|Range|Knockback)\b|\b(HP|DMG)\b/g;
const WORD_ICON = { HP: 'hp', DMG: 'dmg', Power: 'pwr', Range: 'rng', Knockback: 'kb' };

// ---------- predložak ----------

// Predložak za kartu: zadan na karti (template) ili po tipu.
export function templateName(card) {
  return card.template ?? ({ Hero: 'hero', Evolution: 'evolution', Stage: 'stage', Core: 'core' })[card.type] ?? 'action';
}

// Predložak iz data/card-frames/<name>/: layout.json i sve slike koje traži (slojevi, privremeni okviri, ikone).
// load(path) vraća URL za datoteku u data/ ili null.
export async function loadTemplate(name, load) {
  const base = `card-frames/${name}`;
  const url = await load(`${base}/layout.json`);
  if (!url) throw new Error(`No data/${base}/layout.json (card frames are in the shared folder).`);
  const layout = await (await fetch(url)).json();
  const images = new Map();
  const get = async rel => {
    if (!images.has(rel)) {
      const u = await load(rel.startsWith('../') ? `card-frames/${rel.slice(3)}` : `${base}/${rel}`);
      images.set(rel, u ? await loadImage(u).catch(() => null) : null);
    }
    return images.get(rel);
  };
  const icons = {};
  for (const [k, rel] of Object.entries(layout.icons ?? {})) icons[k] = await get(rel);
  // Core: slika, ili heksagon s efektom.
  if (layout.kind === 'image') return { name, layout, icons, hexagon: layout.hexagon ? await get(layout.hexagon) : null };
  // Heroj i evolucija: jedan gotov okvir po boji.
  if (layout.kind === 'hero') {
    const frames = {};
    for (const x of Object.values(FRAME_LETTER)) frames[x] = await get(layout.frame.replace('{letter}', x));
    return { name, layout, frames, icons };
  }
  // Pravi slojevi, ako su svi tu; inače privremeni okvir po boji.
  const layers = [];
  let real = true;
  for (const l of layout.layers) {
    if (l.art) { layers.push(l); continue; }
    const img = await get(l.src);
    if (!img) real = false;
    layers.push({ ...l, img });
  }
  const interim = {};
  if (!real) for (const c of Object.keys(TINTS)) interim[c] = await get(layout.interim.replace('{color}', c));
  return { name, layout, layers: real ? layers : null, interim, icons };
}

export function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error(`Image did not load: ${src}`));
    img.src = src;
  });
}

// Fontovi moraju biti učitani prije crtanja (canvas ne čeka). Agency FB je sistemski (Windows).
export async function fontsReady() {
  const want = [`106px ${TITLE_FONT}`, `bold 106px ${TITLE_FONT}`, `80px ${TEXT_FONT}`, `bold 80px ${TEXT_FONT}`, `600 80px ${TEXT_FONT}`];
  await Promise.all(want.map(f => document.fonts.load(f).catch(() => null)));
  return document.fonts.check('106px "Agency FB"');
}

// ---------- karta ----------

// Nacrta kartu na canvas (veličine CARD_W×CARD_H). art: učitana slika ili null.
// Vraća upozorenja za editor: tekst na najmanjem fontu, naslov smanjen do kraja, nema arta.
export function renderCard(canvas, card, tpl, art, emblem = null) {
  if (tpl.layout.kind === 'hero') return renderHero(canvas, card, tpl, art, emblem);
  if (tpl.layout.kind === 'image') return renderImage(canvas, card, tpl, art);
  canvas.width = CARD_W;
  canvas.height = CARD_H;
  const ctx = canvas.getContext('2d');
  const L = tpl.layout;
  const warnings = [];
  ctx.clearRect(0, 0, CARD_W, CARD_H);
  const color = TINTS[card.color] ? card.color : 'Purple';
  if (tpl.layers) {
    for (const l of tpl.layers) {
      if (l.art) drawArt(ctx, art, card.artCrop, L, true);
      else if (l.img) ctx.drawImage(tinted(l.img, l.tint === true ? TINTS[color] : l.tint || null), 0, 0, CARD_W, CARD_H);
    }
  } else {
    drawArt(ctx, art, card.artCrop, L);
    const frame = tpl.interim[color];
    if (frame) ctx.drawImage(frame, 0, 0, CARD_W, CARD_H);
  }
  if (!art) warnings.push('No art yet.');

  // Boja teksta po kućici (Stage: crni naslov i tekst); kućice koje predložak nema se preskaču.
  const ink = box => box?.color ?? '#ffffff';
  if (!fitLine(ctx, card.name ?? '', L.title, { font: TITLE_FONT, color: ink(L.title) })) warnings.push('The name is too long for the title bar.');
  fitLine(ctx, card.cost == null ? '' : String(card.cost), L.cost, { font: TITLE_FONT, color: ink(L.cost) });
  fitLine(ctx, card.type ?? '', L.type, { font: TITLE_FONT, color: ink(L.type) });
  fitLine(ctx, card.id ?? '', L.code, { font: TITLE_FONT, color: ink(L.code) });
  drawBonus(ctx, card.bonus ?? {}, L, tpl.icons);
  if (L.tags && !drawTags(ctx, card.traits ?? [], L.tags)) warnings.push('The tags are too long for the tag bar.');
  const t = drawEffect(ctx, card.text ?? '', color, L.effect, tpl.icons);
  if (t.atMin) warnings.push('The text only fits at the smallest size; shorten it.');
  return warnings;
}

// Art u kutiji arta (cover), s izrezom {x, y, zoom}: točka slike (x, y) u sredini kutije, zoom na cover.
// S pravim slojevima art pokriva cijelu kutiju (okvir iznad ga reže, kao u Card Engineu);
// uz privremeni okvir izrezan je na prozor (zaobljeni pravokutnik), da ne viri ispod prozirnih dijelova.
function drawArt(ctx, art, crop, L, full = false) {
  const [wx, wy, ww, wh, wr] = full ? [...L.artBox, 0] : L.artWindow;
  ctx.save();
  roundRect(ctx, wx, wy, ww, wh, wr);
  ctx.clip();
  if (!art) {
    ctx.fillStyle = '#1b1b1f';
    ctx.fillRect(wx, wy, ww, wh);
    ctx.fillStyle = '#55555c';
    ctx.font = `bold 80px ${TITLE_FONT}`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('NO ART', wx + ww / 2, wy + wh / 2);
    ctx.restore();
    return;
  }
  // A zoomed-out picture leaves no hole in the card.
  ctx.fillStyle = '#101014';
  ctx.fillRect(wx, wy, ww, wh);
  const [bx, by, bw, bh] = L.artBox;
  const c = { x: 0.5, y: 0.5, zoom: 1, ...(crop ?? {}) };
  const s = Math.max(bw / art.width, bh / art.height) * Math.max(c.zoom, 0.05);
  const dw = art.width * s;
  const dh = art.height * s;
  ctx.drawImage(art, bx + bw / 2 - c.x * dw, by + bh / 2 - c.y * dh, dw, dh);
  ctx.restore();
}

// Bijeli sloj obojen bojom karte (kao Card Engine: množenje), na zasebnom platnu.
const tintCache = new Map();
function tinted(img, color) {
  if (!color) return img;
  const key = img.src + color;
  if (tintCache.has(key)) return tintCache.get(key);
  const c = document.createElement('canvas');
  c.width = img.naturalWidth;
  c.height = img.naturalHeight;
  const x = c.getContext('2d');
  x.drawImage(img, 0, 0);
  x.globalCompositeOperation = 'multiply';
  x.fillStyle = color;
  x.fillRect(0, 0, c.width, c.height);
  x.globalCompositeOperation = 'destination-in';
  x.drawImage(img, 0, 0);
  tintCache.set(key, c);
  return c;
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

// Jedan redak u kućici, smanjuje se dok ne stane; false kad ni najmanji ne stane.
function fitLine(ctx, text, box, { font, color, bold = false }) {
  if (!box || !text) return true;
  const [x, y, w, h] = box.box;
  let size = box.size;
  const weight = bold || box.bold ? 'bold ' : '';
  ctx.font = `${weight}${size}px ${font}`;
  while (size > box.min && ctx.measureText(text).width > w) {
    size -= 2;
    ctx.font = `${weight}${size}px ${font}`;
  }
  ctx.fillStyle = color;
  ctx.textAlign = box.align ?? 'center';
  ctx.textBaseline = 'middle';
  const tx = ctx.textAlign === 'left' ? x : ctx.textAlign === 'right' ? x + w : x + w / 2;
  ctx.fillText(text, tx, y + h / 2 + size * 0.04);
  return ctx.measureText(text).width <= w;
}

// Bonusi statova (Action/Equipment: "+2000 Power"): ikona u boji stata i broj, na mjestima iz predloška.
function drawBonus(ctx, bonus, L, icons) {
  for (const [k, slot] of Object.entries(L.bonus ?? {})) {
    const v = bonus[k];
    if (!v) continue;
    const icon = icons[`stat-${k}`];
    if (icon) {
      const [ix, iy, iw, ih] = slot.icon;
      // A little inside its box, as Card Engine draws it.
      const s = Math.min(iw / icon.width, ih / icon.height) * 0.72;
      ctx.drawImage(tinted(icon, STAT_TINTS[k]), ix + (iw - icon.width * s) / 2, iy + (ih - icon.height * s) / 2, icon.width * s, icon.height * s);
    }
    fitLine(ctx, `${v > 0 ? '+' : ''}${v}`, { box: slot.value, size: slot.size ?? 106, min: 40 }, { font: TITLE_FONT, color: '#ffffff' });
  }
}

// Tagovi: prvi bijel i podebljan, ostali prigušeni, odvojeni točkom; do dva reda, uz smanjivanje.
function drawTags(ctx, tags, box) {
  if (!tags.length) return true;
  const [x, y, w, h] = box.box;
  const sep = '  ·  ';
  for (let size = box.size; size >= box.min; size -= 2) {
    const parts = tags.map((t, i) => ({ text: t, bold: i === 0, color: i === 0 ? '#ffffff' : 'rgba(255,255,255,0.62)' }));
    const lines = wrapRuns(ctx, parts, sep, w, size, TITLE_FONT);
    if (lines.length <= 2 && lines.length * size * 1.05 <= h + 8) {
      const lh = size * 1.05;
      let ly = y + h / 2 - (lines.length * lh) / 2 + lh / 2;
      for (const line of lines) {
        drawRunLine(ctx, line, x + w / 2, ly, size, TITLE_FONT);
        ly += lh;
      }
      return true;
    }
  }
  const parts = tags.map((t, i) => ({ text: t, bold: i === 0, color: i === 0 ? '#ffffff' : 'rgba(255,255,255,0.62)' }));
  drawRunLine(ctx, wrapRuns(ctx, parts, sep, Infinity, box.min, TITLE_FONT)[0], x + w / 2, y + h / 2, box.min, TITLE_FONT);
  return false;
}

// Tagovi kao "riječi" s razmakom-točkom; vraća retke (nizove dijelova).
function wrapRuns(ctx, parts, sep, maxW, size, font) {
  const lines = [[]];
  let lineW = 0;
  for (const p of parts) {
    ctx.font = `${p.bold ? 'bold ' : ''}${size}px ${font}`;
    const pw = ctx.measureText(p.text).width;
    ctx.font = `${size}px ${font}`;
    const sw = lines.at(-1).length ? ctx.measureText(sep).width : 0;
    if (lines.at(-1).length && lineW + sw + pw > maxW) {
      lines.push([]);
      lineW = 0;
    }
    if (lines.at(-1).length) {
      lines.at(-1).push({ text: sep, color: 'rgba(255,255,255,0.45)', w: ctx.measureText(sep).width });
      lineW += ctx.measureText(sep).width;
    }
    lines.at(-1).push({ ...p, w: pw });
    lineW += pw;
  }
  return lines;
}

function drawRunLine(ctx, line, cx, cy, size, font) {
  const total = line.reduce((s, p) => s + p.w, 0);
  let x = cx - total / 2;
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  for (const p of line) {
    ctx.font = `${p.bold ? 'bold ' : ''}${size}px ${font}`;
    ctx.fillStyle = p.color;
    ctx.fillText(p.text, x, cy);
    x += p.w;
  }
}

// ---------- tekst efekta ----------

// Rastavi tekst: [Range], faza (+ Once Per Turn), uvjet na početku, zatim tekst s ikonama i natuknicama.
// Karta može imati više efekata: svaki redak koji počinje fazom ili [Range] počinje novi efekt
// (s natuknicama ispod sebe). Tekst prije prvog takvog retka je prvi efekt (trajni, bez oznake).
export function parseEffects(text) {
  const blocks = [];
  let cur = [];
  for (const raw of (text ?? '').split('\n')) {
    const line = raw.trim();
    if (!line) continue;
    if ((RANGE_RE.test(line) || PHASE_RE.test(line)) && cur.length) { blocks.push(cur.join('\n')); cur = []; }
    cur.push(line);
  }
  if (cur.length) blocks.push(cur.join('\n'));
  return blocks.map(parseEffect);
}

export function parseEffect(text) {
  let t = (text ?? '').trim();
  const out = { range: false, phase: null, once: false, cond: null, lines: [] };
  if (RANGE_RE.test(t)) { out.range = true; t = t.replace(RANGE_RE, ''); }
  const m = t.match(PHASE_RE);
  if (m) {
    out.phase = m[1].replace(/ Phase$/i, '').toUpperCase() + ' PHASE';
    out.once = !!m[2];
    t = t.slice(m[0].length);
  }
  const c = t.match(COND_RE);
  if (c) { out.cond = c[1]; t = t.slice(c[0].length); }
  out.lines = t.split('\n').map(s => s.trim()).filter(Boolean).map(s => ({ bullet: /^[-•]\s*/.test(s), text: s.replace(/^[-•]\s*/, '') }));
  return out;
}

// Efekti jedan ispod drugog: svaki ima svoj red oznaka (faza i Once per turn jedna oznaka u dva dijela, RANGE)
// i svoj tekst. Font se smanjuje od najvećeg do najmanjeg dok sve ne stane; cijeli blok je okomito centriran.
function drawEffect(ctx, text, color, box, icons, heading = '') {
  const blocks = parseEffects(text);
  const [x, y, w, h] = box.box;
  const chipFull = box.chip ?? 64;
  const toParas = e => {
    const paras = [];
    if (e.cond) paras.push({ bullet: false, runs: [{ text: e.cond, bold: true }] });
    for (const l of e.lines) paras.push({ bullet: l.bullet, runs: /^Terrain:/i.test(l.text) ? [{ text: l.text, bold: true }] : richRuns(l.text) });
    return paras;
  };
  const groups = blocks.map(e => {
    const chips = [];
    if (e.phase) chips.push({ kind: 'phase', text: e.phase, once: e.once });
    if (e.range) chips.push({ kind: 'range', text: 'RANGE' });
    return { chips, paras: toParas(e) };
  });
  // Naziv sposobnosti heroja: podebljan i podvučen, iznad svih efekata.
  const head = heading ? [{ bullet: false, runs: [{ text: heading, bold: true, underline: true }] }] : [];
  const layout = size => {
    const chipH = Math.min(chipFull, Math.round(size * 1.05));
    const gap = Math.round(size * 0.22);
    const between = Math.round(size * 0.45);
    const top = head.length ? layoutParas(ctx, head, w - 56, size, icons) : null;
    let total = top ? top.height + between : 0;
    const laid = groups.map((g, i) => {
      const t = g.paras.length ? layoutParas(ctx, g.paras, w - 56, size, icons) : { lines: [], height: 0 };
      const hgt = (g.chips.length ? chipH + (t.height ? gap : 0) : 0) + t.height;
      total += hgt + (i ? between : 0);
      return { ...g, t, hgt };
    });
    return { top, laid, total, chipH, gap, between };
  };
  let size = box.size;
  let L = layout(size);
  for (; size > box.min && L.total > h - 16; size -= 2) L = layout(size);
  const atMin = L.total > h - 16;
  let cy = y + (h - L.total) / 2;
  const ink = box.color ?? '#ffffff';
  const drawLines = lines => {
    for (const line of lines) {
      drawRich(ctx, line, x + w / 2, cy + line.h / 2, size, icons, ink);
      cy += line.h;
    }
  };
  if (L.top) { drawLines(L.top.lines); cy += L.between; }
  L.laid.forEach((g, i) => {
    if (i) cy += L.between;
    if (g.chips.length) {
      drawChips(ctx, g.chips, x + w / 2, cy, L.chipH, color, icons);
      cy += L.chipH + (g.t.height ? L.gap : 0);
    }
    drawLines(g.t.lines);
  });
  return { atMin };
}

// "{Sword}" je podebljano ime taga, "3 HP" i [PWR]… ikone statova; ostalo običan tekst.
export function richRuns(s) {
  const runs = [];
  let last = 0;
  for (const m of s.matchAll(ICON_RE)) {
    if (m.index > last) runs.push({ text: s.slice(last, m.index) });
    if (m[1]) runs.push({ icon: m[1].toLowerCase() });
    else if (m[3] || m[4]) runs.push({ icon: WORD_ICON[m[3] || m[4]] });
    else runs.push({ text: m[2], bold: true });
    last = m.index + m[0].length;
  }
  if (last < s.length) runs.push({ text: s.slice(last) });
  return runs;
}

// Prelamanje po riječima uz ikone (ikona ostaje u retku sa svojim brojem: "3[DMG]" je jedna riječ).
function layoutParas(ctx, paras, maxW, size, icons) {
  const lines = [];
  const lh = size * 1.18;
  for (const p of paras) {
    const words = [];
    for (const r of p.runs) {
      if (r.icon) {
        const prev = words.at(-1);
        const iw = size * 0.95;
        if (prev && !prev.space) prev.parts.push({ icon: r.icon, w: iw });
        else words.push({ parts: [{ icon: r.icon, w: iw }] });
        continue;
      }
      const bits = r.text.split(/(\s+)/);
      for (const b of bits) {
        if (!b) continue;
        if (/^\s+$/.test(b)) { words.push({ space: true }); continue; }
        ctx.font = `${r.bold ? 'bold' : '500'} ${size}px ${TEXT_FONT}`;
        const prev = words.at(-1);
        const part = { text: b, bold: !!r.bold, underline: !!r.underline, w: ctx.measureText(b).width };
        if (prev && !prev.space) prev.parts.push(part);
        else words.push({ parts: [part] });
      }
    }
    ctx.font = `500 ${size}px ${TEXT_FONT}`;
    const spaceW = ctx.measureText(' ').width;
    const bulletW = p.bullet ? size * 0.9 : 0;
    let line = { parts: p.bullet ? [{ text: '•', bold: true, w: bulletW }] : [], w: bulletW, h: lh };
    let pendingSpace = false;
    for (const wd of words) {
      if (wd.space) { pendingSpace = line.parts.length > (p.bullet ? 1 : 0); continue; }
      const ww = wd.parts.reduce((s, q) => s + q.w, 0);
      const add = (pendingSpace ? spaceW : 0) + ww;
      if (line.parts.length > (p.bullet ? 1 : 0) && line.w + add > maxW) {
        lines.push(line);
        line = { parts: p.bullet ? [{ text: '', w: bulletW }] : [], w: bulletW, h: lh };
        pendingSpace = false;
      }
      if (pendingSpace) { line.parts.push({ text: ' ', w: spaceW }); line.w += spaceW; }
      line.parts.push(...wd.parts);
      line.w += ww;
      pendingSpace = false;
    }
    if (line.parts.length) lines.push(line);
  }
  return { lines, height: lines.reduce((s, l) => s + l.h, 0) };
}

function drawRich(ctx, line, cx, cy, size, icons, ink = '#ffffff') {
  let x = cx - line.w / 2;
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  for (const p of line.parts) {
    if (p.icon) {
      const img = icons[`text-${p.icon}`];
      if (img) {
        const s = (size * 0.9) / Math.max(img.width, img.height);
        ctx.drawImage(tinted(img, STAT_TINTS[p.icon]), x + (p.w - img.width * s) / 2, cy - (img.height * s) / 2, img.width * s, img.height * s);
      }
    } else {
      ctx.font = `${p.bold ? 'bold' : '500'} ${size}px ${TEXT_FONT}`;
      ctx.fillStyle = ink;
      ctx.fillText(p.text, x, cy + size * 0.03);
      if (p.underline) ctx.fillRect(x, cy + size * 0.42, p.w, Math.max(2, size * 0.06));
    }
    x += p.w;
  }
}

// Oznake: faza (puna boja karte, desno obrub s ONCE PER TURN) i RANGE (tamna, ikona u boji rangea).
function drawChips(ctx, chips, cx, top, h, color, icons) {
  const size = Math.round(h * 0.62);
  const pad = h * 0.42;
  ctx.font = `bold ${size}px ${TITLE_FONT}`;
  const widths = chips.map(c => {
    if (c.kind === 'phase') {
      const a = ctx.measureText(c.text).width + pad * 2;
      const b = c.once ? ctx.measureText('ONCE PER TURN').width + pad * 2 : 0;
      return { a, b, w: a + b };
    }
    const iw = h * 0.7;
    return { w: ctx.measureText(c.text).width + pad * 2 + iw + 10, iw };
  });
  const gap = 20;
  const total = widths.reduce((s, x) => s + x.w, 0) + gap * (chips.length - 1);
  let x = cx - total / 2;
  ctx.textBaseline = 'middle';
  ctx.textAlign = 'center';
  chips.forEach((c, i) => {
    const m = widths[i];
    if (c.kind === 'phase') {
      ctx.fillStyle = TINTS[color];
      roundRect(ctx, x, top, m.a + (m.b ? 12 : 0), h, m.b ? [12, 0, 0, 12] : 12);
      ctx.fill();
      ctx.fillStyle = LIGHT.has(color) ? '#000000' : '#ffffff';
      ctx.fillText(c.text, x + m.a / 2, top + h / 2 + 1);
      if (m.b) {
        ctx.strokeStyle = TINTS[color];
        ctx.lineWidth = 4;
        roundRect(ctx, x + m.a, top + 2, m.b - 2, h - 4, [0, 12, 12, 0]);
        ctx.fillStyle = 'rgba(0,0,0,0.55)';
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#ffffff';
        ctx.fillText('ONCE PER TURN', x + m.a + m.b / 2, top + h / 2 + 1);
      }
    } else {
      ctx.fillStyle = 'rgba(0,0,0,0.78)';
      roundRect(ctx, x, top, m.w, h, 12);
      ctx.fill();
      const img = icons['text-rng'];
      if (img) {
        const s = m.iw / Math.max(img.width, img.height);
        ctx.drawImage(tinted(img, STAT_TINTS.rng), x + pad * 0.7, top + (h - img.height * s) / 2, img.width * s, img.height * s);
      }
      ctx.fillStyle = '#ffffff';
      ctx.fillText(c.text, x + pad * 0.7 + m.iw + 10 + (m.w - pad * 0.7 - m.iw - 10) / 2, top + h / 2 + 1);
    }
    x += m.w + gap;
  });
}


// Core: gotova slika (hexagon na prozirnom), cijela u karti.
// Core: uploadana slika (coreImage 'upload'), ili heksagon s bonusom ("+2000" i ikona stata), kao u Card Engineu.
// Bez izbora: uploadana ako je ima.
export const coreMode = card => card.coreImage ?? (card.art ? 'upload' : 'effect');

function renderImage(canvas, card, tpl, art) {
  const L = tpl.layout;
  const [W, H] = L.size;
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, W, H);
  if (coreMode(card) === 'upload') {
    if (!art) return ['No image yet.'];
    const s = Math.min(W / art.width, H / art.height);
    ctx.drawImage(art, (W - art.width * s) / 2, (H - art.height * s) / 2, art.width * s, art.height * s);
    return [];
  }
  if (tpl.hexagon) ctx.drawImage(tpl.hexagon, 0, 0, W, H);
  const entries = Object.entries(card.bonus ?? {}).filter(([, v]) => v);
  if (!entries.length) return ['No effect yet: write the bonus, e.g. +2000[PWR].'];
  const [k, v] = entries[0];
  const [x, y, w, bh] = L.effect.box;
  const num = `${v > 0 ? '+' : ''}${v}`;
  const icon = tpl.icons[`text-${k}`];
  let size = L.effect.size;
  ctx.font = `${size}px ${TITLE_FONT}`;
  while (size > L.effect.min && ctx.measureText(num).width + size * 1.05 > w) ctx.font = `${(size -= 4)}px ${TITLE_FONT}`;
  const tw = ctx.measureText(num).width;
  const iw = size * 0.85;
  const left = x + (w - tw - iw - size * 0.08) / 2;
  ctx.fillStyle = '#ffffff';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  ctx.fillText(num, left, y + bh / 2 + size * 0.04);
  if (icon) {
    const s = iw / Math.max(icon.width, icon.height);
    ctx.drawImage(tinted(icon, STAT_TINTS[k]), left + tw + size * 0.08, y + bh / 2 - (icon.height * s) / 2, icon.width * s, icon.height * s);
  }
  return entries.length > 1 ? ['A Core shows one bonus; only the first is drawn.'] : [];
}

// ---------- heroji i evolucije (položene karte) ----------

// Slovo okvira po boji karte (Card Engine: Hero_templates_hero_frame_<X>).
export const FRAME_LETTER = { Cyan: 'C', Yellow: 'Y', Purple: 'M', Red: 'R', Blue: 'B', Green: 'G' };
const ROMAN = ['', 'I', 'II', 'III', 'IV', 'V'];

// Heroj ili evolucija: boja pozadine i art u prozoru, okvir u boji heroja, pločica s amblemom, oznakom
// (HERO, ili ime heroja kod evolucije) i nazivom, statsi u kućicama, naziv sposobnosti i tekst, RNG/KB,
// tagovi, kod. Evolucija ima i razinu u hexu lijevo od naziva i cost u pločici.
function renderHero(canvas, card, tpl, art, emblem) {
  const L = tpl.layout;
  const [W, H] = L.size;
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext('2d');
  const warnings = [];
  ctx.clearRect(0, 0, W, H);
  const color = FRAME_LETTER[card.color] ? card.color : 'Purple';
  const evo = L.name === 'evolution';
  const [wx, wy, ww, wh, wr] = L.artWindow;
  ctx.save();
  roundRect(ctx, wx, wy, ww, wh, wr);
  ctx.clip();
  ctx.fillStyle = card.bg || L.bg[color];
  ctx.fillRect(wx, wy, ww, wh);
  if (art) {
    const [bx, by, bw, bh] = L.artBox;
    const c = { x: 0.5, y: 0.5, zoom: 1, ...(card.artCrop ?? {}) };
    const s = Math.max(bw / art.width, bh / art.height) * Math.max(c.zoom, 0.05);
    ctx.drawImage(art, bx + bw / 2 - c.x * art.width * s, by + bh / 2 - c.y * art.height * s, art.width * s, art.height * s);
  } else warnings.push('No art yet.');
  ctx.restore();
  const frame = tpl.frames?.[FRAME_LETTER[color]];
  if (frame) ctx.drawImage(frame, 0, 0, W, H);
  if (emblem) {
    const [ex, ey, ew, eh] = L.emblem;
    const s = Math.min(ew / emblem.width, eh / emblem.height);
    ctx.drawImage(emblem, ex + (ew - emblem.width * s) / 2, ey + (eh - emblem.height * s) / 2, emblem.width * s, emblem.height * s);
  }
  const plate = L.plateColor;
  const [heroName, evoName] = evo && (card.name ?? '').includes(',') ? card.name.split(/,\s*/, 2) : [card.hero ?? '', card.name ?? ''];
  ctx.save();
  ctx.letterSpacing = `${L.label.spacing ?? 0}px`;
  fitLine(ctx, evo ? (card.hero || heroName).toUpperCase() : 'HERO', L.label, { font: TITLE_FONT, color: plate, bold: true });
  ctx.restore();
  const title = evo ? evoName : card.name ?? '';
  if (!fitLine(ctx, title, L.title, { font: TITLE_FONT, color: plate, bold: true })) warnings.push('The name is too long for the plate.');
  if (evo) {
    // Razina u hexu, odmah lijevo od naziva.
    const [tx, ty, tw, th] = L.title.box;
    const textW = Math.min(ctx.measureText(title).width, tw);
    const r = th * 0.42;
    const cx = tx + tw / 2 - textW / 2 - r - 22;
    const cy = ty + th / 2;
    ctx.beginPath();
    for (let i = 0; i < 6; i++) {
      const a = Math.PI / 6 + (i * Math.PI) / 3;
      ctx[i ? 'lineTo' : 'moveTo'](cx + r * Math.cos(a), cy + r * Math.sin(a));
    }
    ctx.closePath();
    ctx.fillStyle = plate;
    ctx.fill();
    fitLine(ctx, ROMAN[card.evo ?? 1] ?? String(card.evo), { box: [cx - r, cy - r, r * 2, r * 2], size: r * 1.05, min: 20 }, { font: TITLE_FONT, color: '#ffffff', bold: true });
    if (L.cost && card.cost != null) fitLine(ctx, String(card.cost), L.cost, { font: TITLE_FONT, color: '#ffffff' });
  }
  const tints = { ...STAT_TINTS, ...(L.statTints ?? {}) };
  for (const [k, slot] of Object.entries(L.stats)) {
    const v = card.stats?.[k];
    if (v == null) continue;
    const icon = tpl.icons[`stat-${k}`];
    if (icon) {
      const [ix, iy, iw, ih] = slot.icon;
      const s = Math.min(iw / icon.width, ih / icon.height) * 0.8;
      ctx.drawImage(tinted(icon, tints[k]), ix + (iw - icon.width * s) / 2, iy + (ih - icon.height * s) / 2, icon.width * s, icon.height * s);
    }
    fitLine(ctx, String(v), { box: slot.value, size: L.statSize ?? 84, min: 40 }, { font: TITLE_FONT, color: '#ffffff' });
  }
  const ability = card.ability ?? card.abilityNames?.[0] ?? '';
  const t = drawEffect(ctx, card.text ?? '', color, L.effect, tpl.icons, ability);
  if (t.atMin) warnings.push('The text only fits at the smallest size; shorten it.');
  if (!drawTags(ctx, card.traits ?? [], L.tags)) warnings.push('The tags are too long for the tag box.');
  fitLine(ctx, card.id ?? '', L.code, { font: TITLE_FONT, color: plate, bold: true });
  return warnings;
}

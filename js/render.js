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
const ICON_RE = /\[(PWR|DMG|HP|RNG|KB)\]|\{([^}]+)\}/g;

// ---------- predložak ----------

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
  const icons = {};
  for (const [k, rel] of Object.entries(layout.icons ?? {})) icons[k] = await get(rel);
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
export function renderCard(canvas, card, tpl, art) {
  canvas.width = CARD_W;
  canvas.height = CARD_H;
  const ctx = canvas.getContext('2d');
  const L = tpl.layout;
  const warnings = [];
  ctx.clearRect(0, 0, CARD_W, CARD_H);
  const color = TINTS[card.color] ? card.color : 'Purple';
  if (tpl.layers) {
    for (const l of tpl.layers) {
      if (l.art) drawArt(ctx, art, card.artCrop, L);
      else if (l.img) ctx.drawImage(tinted(l.img, l.tint ? TINTS[color] : null), 0, 0, CARD_W, CARD_H);
    }
  } else {
    drawArt(ctx, art, card.artCrop, L);
    const frame = tpl.interim[color];
    if (frame) ctx.drawImage(frame, 0, 0, CARD_W, CARD_H);
  }
  if (!art) warnings.push('No art yet.');

  const white = '#ffffff';
  if (!fitLine(ctx, card.name ?? '', L.title, { font: TITLE_FONT, color: white })) warnings.push('The name is too long for the title bar.');
  fitLine(ctx, card.cost == null ? '' : String(card.cost), L.cost, { font: TITLE_FONT, color: white });
  fitLine(ctx, card.type ?? '', L.type, { font: TITLE_FONT, color: white });
  fitLine(ctx, card.id ?? '', L.code, { font: TITLE_FONT, color: white });
  drawBonus(ctx, card.bonus ?? {}, L, tpl.icons);
  if (!drawTags(ctx, card.traits ?? [], L.tags)) warnings.push('The tags are too long for the tag bar.');
  const t = drawEffect(ctx, card.text ?? '', color, L.effect, tpl.icons);
  if (t.atMin) warnings.push('The text only fits at the smallest size; shorten it.');
  return warnings;
}

// Art u kutiji arta (cover), s izrezom {x, y, zoom}: točka slike (x, y) u sredini kutije, zoom na cover.
// Izrezan na prozor okvira (zaobljeni pravokutnik), da ne viri ispod prozirnih dijelova okvira.
function drawArt(ctx, art, crop, L) {
  const [wx, wy, ww, wh, wr] = L.artWindow;
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

// Uvjeti kao oznake u redu iznad teksta (faza i Once per turn jedna oznaka u dva dijela, RANGE),
// zatim tamna ploča s tekstom koji se smanjuje od najvećeg do najmanjeg fonta dok ne stane.
function drawEffect(ctx, text, color, box, icons) {
  const e = parseEffect(text);
  const [x, y, w, h] = box.box;
  const chipH = box.chip ?? 64;
  const gap = 18;
  const chips = [];
  if (e.phase) chips.push({ kind: 'phase', text: e.phase, once: e.once });
  if (e.range) chips.push({ kind: 'range', text: 'RANGE' });
  const runsFor = () => {
    const paras = [];
    if (e.cond) paras.push({ bullet: false, runs: [{ text: e.cond, bold: true }] });
    for (const l of e.lines) paras.push({ bullet: l.bullet, runs: richRuns(l.text) });
    return paras;
  };
  const paras = runsFor();
  const textTop = y + (chips.length ? chipH + gap : 0);
  const textH = y + h - textTop;
  let size = box.size;
  let laid = null;
  for (; size >= box.min; size -= 2) {
    laid = layoutParas(ctx, paras, w - 56, size, icons);
    if (laid.height <= textH - 32) break;
  }
  const atMin = size < box.min;
  if (atMin) { size = box.min; laid = layoutParas(ctx, paras, w - 56, size, icons); }
  // Oznake, centrirane; bez teksta ("Battle Phase:" i bonus) stoje na sredini prostora za tekst.
  if (chips.length) drawChips(ctx, chips, x + w / 2, paras.length ? y : y + (h - chipH) / 2, chipH, color, icons);
  if (paras.length) {
    const blockH = laid.height + 32;
    const by = textTop + (textH - blockH) / 2;
    ctx.fillStyle = 'rgba(0, 0, 0, 0.42)';
    roundRect(ctx, x + 8, by, w - 16, blockH, 22);
    ctx.fill();
    let ly = by + 16;
    for (const line of laid.lines) {
      drawRich(ctx, line, x + w / 2, ly + line.h / 2, size, icons);
      ly += line.h;
    }
  }
  return { atMin };
}

// "{Sword}" je podebljano ime taga, [PWR]… ikone statova; ostalo običan tekst.
function richRuns(s) {
  const runs = [];
  let last = 0;
  for (const m of s.matchAll(ICON_RE)) {
    if (m.index > last) runs.push({ text: s.slice(last, m.index) });
    if (m[1]) runs.push({ icon: m[1].toLowerCase() });
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
        const part = { text: b, bold: !!r.bold, w: ctx.measureText(b).width };
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

function drawRich(ctx, line, cx, cy, size, icons) {
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
      ctx.fillStyle = '#ffffff';
      ctx.fillText(p.text, x, cy + size * 0.03);
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

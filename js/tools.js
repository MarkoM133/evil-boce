// Alati za izradu karata, sve u pregledniku (slike nikamo ne idu):
//   Erase text: kistom se označi tekst na artu, LaMa (tools/lama.onnx u zajedničkom folderu) popuni to mjesto.
//   Remove background: pozadina logotipa postane prozirna (boja s klikom, tolerancija, mekani rub), PNG.
// app.js daje pomoćne funkcije (h, toast) i loadModel() koji vrati bajtove modela iz foldera ili sa servera.

const ORT_URL = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.30.0/dist/';
const SIZE = 512; // LaMa radi na 512×512; veća područja se smanje pa vrate
const UNDO_MAX = 12;

let ui; // { h, toast, loadModel }
let tab = 'erase';

// ---------- zajedničko ----------

function readImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error(`"${file.name}" is not an image the browser can open.`)); };
    img.src = url;
  });
}

function canvasOf(w, hgt) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = hgt;
  return c;
}

function download(canvas, name) {
  canvas.toBlob(blob => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }, 'image/png');
}

const baseName = name => (name || 'image').replace(/\.[^.]+$/, '');

// Odabir slike: gumb, povlačenje na stranicu ili Ctrl+V.
function picker(onFile) {
  const { h } = ui;
  const input = h('input', { type: 'file', accept: 'image/*', hidden: true, onchange: e => { const f = e.target.files[0]; if (f) onFile(f); e.target.value = ''; } });
  const drop = h('div', { class: 'tool-drop', onclick: () => input.click() },
    h('strong', {}, 'Choose an image'), h('span', { class: 'muted small' }, 'or drop it here, or paste with Ctrl+V'), input);
  drop.addEventListener('dragover', e => { e.preventDefault(); drop.classList.add('over'); });
  drop.addEventListener('dragleave', () => drop.classList.remove('over'));
  drop.addEventListener('drop', e => { e.preventDefault(); drop.classList.remove('over'); const f = e.dataTransfer.files[0]; if (f) onFile(f); });
  return { drop, open: () => input.click() };
}

let pasteTarget = null;
document.addEventListener('paste', e => {
  if (!pasteTarget || !document.querySelector('.tools')) return;
  const item = [...(e.clipboardData?.items ?? [])].find(i => i.type.startsWith('image/'));
  if (!item) return;
  e.preventDefault();
  const f = item.getAsFile();
  pasteTarget(new File([f], 'pasted.png', { type: f.type }));
});

// ---------- LaMa ----------

let session = null; // Promise<{ ort, sess, ep }>
let cpuOnly = false; // grafička kartica je jednom pukla pri računanju: dalje samo procesor
function lama(onStatus) {
  session ??= (async () => {
    onStatus('Loading the model runtime…');
    const ort = await import(`${ORT_URL}ort.webgpu.min.mjs`);
    ort.env.wasm.wasmPaths = ORT_URL;
    onStatus('Loading LaMa (208 MB, from the shared folder)…');
    const bytes = await ui.loadModel();
    onStatus('Starting LaMa…');
    // Grafička kartica ako je preglednik da (WebGPU), inače procesor.
    for (const providers of (navigator.gpu && !cpuOnly ? [['webgpu', 'wasm'], ['wasm']] : [['wasm']])) {
      try {
        const sess = await ort.InferenceSession.create(new Uint8Array(bytes), { executionProviders: providers });
        return { ort, sess, ep: providers[0] };
      } catch (e) {
        console.warn('LaMa', providers, e);
      }
    }
    throw new Error('LaMa could not start in this browser.');
  })().catch(e => { session = null; throw e; });
  return session;
}

// Popuni označeno: područje oko oznaka (s rubom) ide u LaMu na 512×512, rezultat se vrati u punoj rezoluciji
// i upiše samo na označena mjesta (malo omekšan rub).
async function inpaint(image, mask, onStatus) {
  const W = image.width, H = image.height;
  const md = mask.getContext('2d').getImageData(0, 0, W, H).data;
  let x0 = W, y0 = H, x1 = -1, y1 = -1;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (md[(y * W + x) * 4 + 3] > 0) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
  }
  if (x1 < 0) return false;
  const pad = Math.max(48, Math.round(Math.max(x1 - x0, y1 - y0) * 0.6));
  const side = Math.min(Math.max(W, H), Math.max(SIZE, Math.max(x1 - x0, y1 - y0) + 2 * pad));
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  const cw = Math.min(W, side), ch = Math.min(H, side);
  const rx = Math.round(Math.min(Math.max(0, cx - cw / 2), W - cw));
  const ry = Math.round(Math.min(Math.max(0, cy - ch / 2), H - ch));

  let { ort, sess, ep } = await lama(onStatus);
  onStatus(`Erasing… (${ep === 'webgpu' ? 'graphics card' : 'processor'})`);
  const src = canvasOf(SIZE, SIZE).getContext('2d', { willReadFrequently: true });
  src.drawImage(image, rx, ry, cw, ch, 0, 0, SIZE, SIZE);
  const msk = canvasOf(SIZE, SIZE).getContext('2d', { willReadFrequently: true });
  msk.drawImage(mask, rx, ry, cw, ch, 0, 0, SIZE, SIZE);
  const px = src.getImageData(0, 0, SIZE, SIZE).data;
  const mp = msk.getImageData(0, 0, SIZE, SIZE).data;
  const n = SIZE * SIZE;
  const img = new Float32Array(3 * n);
  const m = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    img[i] = px[i * 4] / 255;
    img[n + i] = px[i * 4 + 1] / 255;
    img[2 * n + i] = px[i * 4 + 2] / 255;
    m[i] = mp[i * 4 + 3] > 0 ? 1 : 0;
  }
  const t = performance.now();
  const feeds = () => ({ image: new ort.Tensor('float32', img, [1, 3, SIZE, SIZE]), mask: new ort.Tensor('float32', m, [1, 1, SIZE, SIZE]) });
  let out;
  try {
    out = await sess.run(feeds());
  } catch (e) {
    // Neki dijelovi modela (FFT) na nekim karticama ne prolaze: isto ponovo na procesoru.
    if (ep !== 'webgpu') throw e;
    console.warn('LaMa on WebGPU failed, using the processor', e);
    cpuOnly = true;
    session = null;
    ({ ort, sess, ep } = await lama(onStatus));
    onStatus('Erasing… (processor)');
    out = await sess.run(feeds());
  }
  const y = out.output.data;
  const scale = Math.max(...y.subarray(0, 4096)) <= 1.5 ? 255 : 1; // model vraća 0–255; za svaki slučaj i 0–1
  const res = new ImageData(SIZE, SIZE);
  for (let i = 0; i < n; i++) {
    res.data[i * 4] = y[i] * scale;
    res.data[i * 4 + 1] = y[n + i] * scale;
    res.data[i * 4 + 2] = y[2 * n + i] * scale;
    res.data[i * 4 + 3] = 255;
  }
  const filled = canvasOf(SIZE, SIZE);
  filled.getContext('2d').putImageData(res, 0, 0);
  const patch = canvasOf(cw, ch);
  const pg = patch.getContext('2d');
  pg.drawImage(filled, 0, 0, cw, ch);
  pg.globalCompositeOperation = 'destination-in';
  pg.filter = 'blur(1px)';
  pg.drawImage(mask, rx, ry, cw, ch, 0, 0, cw, ch);
  image.getContext('2d').drawImage(patch, rx, ry);
  return { ms: Math.round(performance.now() - t), ep };
}

// ---------- Erase text ----------

const er = { image: null, mask: null, name: '', undo: [], brush: 28, auto: true, busy: false };

function renderErase() {
  const { h, toast } = ui;
  const status = h('span', { class: 'muted small tool-status' });
  const setStatus = s => { status.textContent = s; };
  const stage = h('div', { class: 'tool-stage erase-stage' });
  const undoBtn = h('button', { class: 'ghost', disabled: !er.undo.length, onclick: () => {
    const last = er.undo.pop();
    if (last) er.image.getContext('2d').putImageData(last, 0, 0);
    undoBtn.disabled = !er.undo.length;
  } }, 'Undo');
  const clearMarks = () => er.mask?.getContext('2d').clearRect(0, 0, er.mask.width, er.mask.height);
  const run = async () => {
    if (!er.image || er.busy) return;
    er.busy = true;
    stage.classList.add('busy');
    try {
      const before = er.image.getContext('2d').getImageData(0, 0, er.image.width, er.image.height);
      const res = await inpaint(er.image, er.mask, setStatus);
      if (res === false) { setStatus('Mark the text first: paint over it with the brush.'); return; }
      er.undo.push(before);
      if (er.undo.length > UNDO_MAX) er.undo.shift();
      undoBtn.disabled = false;
      clearMarks();
      setStatus(`Done in ${(res.ms / 1000).toFixed(1)} s (${res.ep === 'webgpu' ? 'graphics card' : 'processor'}). Mark more, or download.`);
    } catch (e) {
      console.error(e);
      setStatus('');
      toast(e.message || String(e), 'error');
    } finally {
      er.busy = false;
      stage.classList.remove('busy');
    }
  };
  const show = () => {
    if (!er.image) { stage.replaceChildren(pick.drop); return; }
    const wrap = h('div', { class: 'erase-wrap' }, er.image, er.mask);
    stage.replaceChildren(wrap);
    er.image.className = 'erase-image';
    er.mask.className = 'erase-mask';
    attachBrush(er.mask, () => { if (er.auto) run(); });
  };
  const load = async file => {
    try {
      const img = await readImage(file);
      er.image = canvasOf(img.naturalWidth, img.naturalHeight);
      er.image.getContext('2d', { willReadFrequently: true }).drawImage(img, 0, 0);
      er.mask = canvasOf(img.naturalWidth, img.naturalHeight);
      er.name = file.name;
      er.undo = [];
      undoBtn.disabled = true;
      show();
      setStatus(`${img.naturalWidth}×${img.naturalHeight}. Paint over the text${er.auto ? '; it is erased when you let go' : ', then Erase'}.`);
      lama(() => {}).catch(() => {}); // model se počne učitavati odmah
    } catch (e) {
      toast(e.message, 'error');
    }
  };
  const pick = picker(load);
  pasteTarget = load;
  show();
  return h('div', { class: 'tool' },
    h('p', { class: 'muted' }, 'Paint over text or a watermark on the art; LaMa fills the spot so it fits the picture. Works best on backgrounds, clothes and hair; over faces it can look soft.'),
    h('div', { class: 'tool-bar' },
      h('button', { class: 'ghost', onclick: pick.open }, er.image ? 'Other image' : 'Choose image'),
      h('label', { class: 'tool-range' }, h('span', {}, 'Brush'),
        h('input', { type: 'range', min: 6, max: 120, value: er.brush, oninput: e => { er.brush = Number(e.target.value); } })),
      h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: er.auto, onchange: e => { er.auto = e.target.checked; } }), 'Erase when I let go'),
      h('button', { class: 'primary', onclick: run }, 'Erase'),
      h('button', { class: 'ghost', onclick: clearMarks }, 'Clear marks'),
      undoBtn,
      h('button', { class: 'publish', onclick: () => er.image ? download(er.image, `${baseName(er.name)}-clean.png`) : toast('Choose an image first.', 'warn') }, 'Download PNG')),
    status,
    stage);
}

// Kist na prozirnom sloju iznad slike; koordinate se preračunaju iz prikazane veličine u pravu.
function attachBrush(canvas, onDone) {
  const g = canvas.getContext('2d');
  let last = null;
  const at = e => {
    const r = canvas.getBoundingClientRect();
    return [(e.clientX - r.left) * canvas.width / r.width, (e.clientY - r.top) * canvas.height / r.height, canvas.width / r.width];
  };
  const dot = (x, y, k) => {
    g.fillStyle = '#e3120b';
    g.strokeStyle = '#e3120b';
    g.lineCap = 'round';
    g.lineWidth = er.brush * k;
    if (last) { g.beginPath(); g.moveTo(last[0], last[1]); g.lineTo(x, y); g.stroke(); }
    g.beginPath(); g.arc(x, y, er.brush * k / 2, 0, Math.PI * 2); g.fill();
    last = [x, y];
  };
  canvas.onpointerdown = e => { if (er.busy) return; try { canvas.setPointerCapture(e.pointerId); } catch {} last = null; dot(...at(e)); };
  canvas.onpointermove = e => { if (last) dot(...at(e)); };
  canvas.onpointerup = () => { if (!last) return; last = null; onDone(); };
}

// ---------- Remove background ----------

const bg = { src: null, name: '', key: null, tol: 18, soft: 8, edges: true, trim: true, out: null };

function removeBackground() {
  const { src, key } = bg;
  const W = src.width, H = src.height;
  const data = src.getContext('2d', { willReadFrequently: true }).getImageData(0, 0, W, H);
  const p = data.data;
  const t = bg.tol * 4.4, s = Math.max(1, bg.soft * 4.4); // 0–100 na udaljenost boja 0–441
  const n = W * H;
  const dist = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const dr = p[i * 4] - key[0], dg = p[i * 4 + 1] - key[1], db = p[i * 4 + 2] - key[2];
    dist[i] = Math.sqrt(dr * dr + dg * dg + db * db);
  }
  const reach = new Uint8Array(n);
  if (bg.edges) {
    // samo pozadina povezana s rubom slike (unutrašnjost logotipa iste boje ostaje)
    const stack = [];
    const push = i => { if (!reach[i] && dist[i] <= t + s) { reach[i] = 1; stack.push(i); } };
    for (let x = 0; x < W; x++) { push(x); push((H - 1) * W + x); }
    for (let y = 0; y < H; y++) { push(y * W); push(y * W + W - 1); }
    while (stack.length) {
      const i = stack.pop();
      const x = i % W;
      if (x > 0) push(i - 1);
      if (x < W - 1) push(i + 1);
      if (i >= W) push(i - W);
      if (i < n - W) push(i + W);
    }
  } else {
    for (let i = 0; i < n; i++) reach[i] = dist[i] <= t + s ? 1 : 0;
  }
  for (let i = 0; i < n; i++) if (reach[i]) p[i * 4 + 3] = Math.round(p[i * 4 + 3] * Math.min(1, Math.max(0, (dist[i] - t) / s)));
  let x0 = 0, y0 = 0, x1 = W - 1, y1 = H - 1;
  if (bg.trim) {
    x0 = W; y0 = H; x1 = -1; y1 = -1;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (p[(y * W + x) * 4 + 3] > 8) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    if (x1 < 0) { x0 = 0; y0 = 0; x1 = W - 1; y1 = H - 1; }
  }
  const out = canvasOf(x1 - x0 + 1, y1 - y0 + 1);
  out.getContext('2d').putImageData(data, -x0, -y0);
  out.offset = [x0, y0]; // gdje je obrezani prikaz u izvornoj slici (za odabir boje klikom)
  return out;
}

function renderBackground() {
  const { h, toast } = ui;
  const stage = h('div', { class: 'tool-stage bg-stage' });
  const status = h('span', { class: 'muted small tool-status' });
  const sw = h('span', { class: 'bg-swatch' });
  let queued = false;
  const update = () => {
    if (!bg.src || queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      bg.out = removeBackground();
      bg.out.className = 'bg-out';
      bg.out.title = 'Click a color to remove it';
      bg.out.onclick = e => pickColor(e);
      sw.style.background = `rgb(${bg.key.join(',')})`;
      stage.replaceChildren(h('div', { class: 'bg-wrap' }, bg.out));
      status.textContent = `${bg.src.width}×${bg.src.height} → ${bg.out.width}×${bg.out.height}. Click the image to pick the background color.`;
    });
  };
  // Klik na prikaz: boja s tog mjesta u izvornoj slici (prikaz je možda obrezan).
  const pickColor = e => {
    const r = e.currentTarget.getBoundingClientRect();
    const [ox, oy] = bg.out.offset;
    const x = Math.min(bg.src.width - 1, Math.round(ox + (e.clientX - r.left) / r.width * bg.out.width));
    const y = Math.min(bg.src.height - 1, Math.round(oy + (e.clientY - r.top) / r.height * bg.out.height));
    const d = bg.src.getContext('2d').getImageData(x, y, 1, 1).data;
    bg.key = [d[0], d[1], d[2]];
    update();
  };
  const load = async file => {
    try {
      const img = await readImage(file);
      bg.src = canvasOf(img.naturalWidth, img.naturalHeight);
      const g = bg.src.getContext('2d', { willReadFrequently: true });
      g.drawImage(img, 0, 0);
      bg.name = file.name;
      const c = g.getImageData(0, 0, 1, 1).data; // gornji lijevi kut je obično pozadina
      bg.key = [c[0], c[1], c[2]];
      update();
    } catch (e) {
      toast(e.message, 'error');
    }
  };
  const pick = picker(load);
  pasteTarget = load;
  const range = (label, k, max) => h('label', { class: 'tool-range' }, h('span', {}, label),
    h('input', { type: 'range', min: 0, max, value: bg[k], oninput: e => { bg[k] = Number(e.target.value); update(); } }));
  if (bg.src) update(); else stage.replaceChildren(pick.drop);
  return h('div', { class: 'tool' },
    h('p', { class: 'muted' }, 'For logos on a plain background: the background color becomes transparent. Click the image to pick another color; the checkerboard shows what is transparent.'),
    h('div', { class: 'tool-bar' },
      h('button', { class: 'ghost', onclick: pick.open }, bg.src ? 'Other image' : 'Choose image'),
      h('span', { class: 'bg-key' }, 'Color', sw),
      range('Tolerance', 'tol', 100),
      range('Soft edge', 'soft', 50),
      h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: bg.edges, onchange: e => { bg.edges = e.target.checked; update(); } }), 'Only from the edges'),
      h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: bg.trim, onchange: e => { bg.trim = e.target.checked; update(); } }), 'Trim empty border'),
      h('button', { class: 'publish', onclick: () => bg.out ? download(bg.out, `${baseName(bg.name)}-transparent.png`) : toast('Choose an image first.', 'warn') }, 'Download PNG')),
    status,
    stage);
}

// ---------- stranica ----------

export function renderTools(helpers) {
  ui = helpers;
  const { h } = ui;
  const body = h('div', {});
  const tabs = [['erase', 'Erase text'], ['bg', 'Remove background']];
  const bar = h('div', { class: 'bk-forms tool-tabs', role: 'tablist' }, tabs.map(([k, label]) =>
    h('button', { type: 'button', role: 'tab', class: tab === k ? 'active' : '', 'aria-selected': String(tab === k), onclick: () => { tab = k; draw(); } }, label)));
  const draw = () => {
    for (const b of bar.children) { const on = b.textContent === tabs.find(([k]) => k === tab)[1]; b.classList.toggle('active', on); b.setAttribute('aria-selected', String(on)); }
    body.replaceChildren(tab === 'erase' ? renderErase() : renderBackground());
  };
  draw();
  return h('section', { class: 'panel tools' }, h('h2', {}, 'Tools'), bar, body);
}

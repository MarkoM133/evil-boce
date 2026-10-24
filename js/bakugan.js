// Bakugan heroja: oblik iz biblioteke (data/bakugani/catalog.json) i dvije boje po želji.
// Tekstura je siva, pa je boje množe: sličice se boje u 2D canvasu, pregled je 3D (three.js), a za TTS se ista
// tekstura spremi kao slika (app, ensureBakuganTextures).

// Boje igre (RGB iz Card Enginea), za gumbe i kao zadana boja bakugana.
export const GAME_COLORS = { Cyan: '#00ffff', Yellow: '#ffff00', Purple: '#ff00ff', Red: '#ff0000', Blue: '#0000ff', Green: '#00ff00' };

export function heroDefaultColor(card) {
  return GAME_COLORS[card.color] ?? '#ffffff';
}

const images = new Map();
function image(url) {
  if (!images.has(url)) {
    images.set(url, new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = url;
    }));
  }
  return images.get(url);
}

// Dvije boje: glavna boji oklop, druga detalje (u originalnom modu zlatne); oči i kristali ostaju originalni.
// parts = { gray, accent, eyes }: slike istog kadra (tekstura ili sličica). accent i eyes mogu faliti (stara biblioteka).
// Prozirna pozadina sličice ostaje prozirna.
export function paintParts(canvas, parts, color, color2 = color) {
  const { width: w, height: hgt } = canvas;
  const g = canvas.getContext('2d');
  g.globalCompositeOperation = 'source-over';
  g.clearRect(0, 0, w, hgt);
  g.drawImage(parts.gray, 0, 0, w, hgt);
  g.globalCompositeOperation = 'multiply';
  g.fillStyle = color;
  g.fillRect(0, 0, w, hgt);
  if (parts.accent && color2 !== color) {
    const layer = new OffscreenCanvas(w, hgt);
    const lg = layer.getContext('2d');
    lg.drawImage(parts.gray, 0, 0, w, hgt);
    lg.globalCompositeOperation = 'multiply';
    lg.fillStyle = color2;
    lg.fillRect(0, 0, w, hgt);
    lg.globalCompositeOperation = 'destination-in';
    lg.drawImage(parts.accent, 0, 0, w, hgt);
    g.globalCompositeOperation = 'source-over';
    g.drawImage(layer, 0, 0);
  }
  g.globalCompositeOperation = 'source-over';
  if (parts.eyes) g.drawImage(parts.eyes, 0, 0, w, hgt);
  g.globalCompositeOperation = 'destination-in';
  g.drawImage(parts.gray, 0, 0, w, hgt);
  g.globalCompositeOperation = 'source-over';
}

// Slike dijelova po URL-ovima ({ gray, accent?, eyes? }); dio kojeg nema je null.
export async function loadParts(urls) {
  const [gray, accent, eyes] = await Promise.all([urls.gray, urls.accent, urls.eyes].map(u => (u ? image(u).catch(() => null) : null)));
  return { gray, accent, eyes };
}

export async function paintThumb(canvas, urls, color, color2) {
  paintParts(canvas, await loadParts(urls), color, color2);
}

let three = null;
async function loadThree() {
  three ??= Promise.all([import('three'), import('three/addons/loaders/OBJLoader.js')])
    .then(([THREE, { OBJLoader }]) => ({ THREE, OBJLoader }));
  return three;
}

// 3D pregled u zadanom canvasu: sam se vrti, povlačenje ga okreće. Staje kad canvas nestane sa stranice.
export function createPreview(canvas) {
  let api = null;
  let pending = null;
  const ready = loadThree().then(({ THREE, OBJLoader }) => {
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
    // canvas.currentCSSZoom: app je na računalu zumiran (CSS zoom), pa se crta u većoj rezoluciji da ne bude mutno
    renderer.setPixelRatio(Math.min(3, (window.devicePixelRatio || 1) * (canvas.currentCSSZoom || 1)));
    renderer.setSize(canvas.clientWidth || canvas.width, canvas.clientHeight || canvas.height, false);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    const scene = new THREE.Scene();
    scene.add(new THREE.HemisphereLight(0xffffff, 0x444444, 1.8));
    const key = new THREE.DirectionalLight(0xffffff, 2.0);
    key.position.set(2, 3, 4);
    scene.add(key);
    const camera = new THREE.PerspectiveCamera(30, 1, 0.01, 100);
    const material = new THREE.MeshStandardMaterial({ roughness: 0.5, metalness: 0.05 });
    let parts = null;
    let texCanvas = null;
    let colors = [];
    let queued = false;
    const pivot = new THREE.Group();
    scene.add(pivot);
    const loader = new OBJLoader();
    const meshes = new Map();
    let dragX = null;
    let spin = 0.6;

    canvas.addEventListener('pointerdown', e => { dragX = e.clientX; spin = 0; canvas.setPointerCapture(e.pointerId); });
    canvas.addEventListener('pointermove', e => { if (dragX !== null) { pivot.rotation.y += (e.clientX - dragX) * 0.01; dragX = e.clientX; } });
    canvas.addEventListener('pointerup', () => { dragX = null; spin = 0.6; });

    let last = performance.now();
    const tick = now => {
      if (!canvas.isConnected) { renderer.dispose(); return; }
      pivot.rotation.y += spin * (now - last) / 1000;
      last = now;
      renderer.render(scene, camera);
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);

    return {
      async show(meshUrl, textureUrls, color, color2) {
        if (!meshes.has(meshUrl)) meshes.set(meshUrl, fetch(meshUrl).then(r => r.text()).then(t => loader.parse(t)));
        const [obj, loaded] = await Promise.all([meshes.get(meshUrl), loadParts(textureUrls)]);
        parts = loaded;
        texCanvas = new OffscreenCanvas(parts.gray.naturalWidth || 1024, parts.gray.naturalHeight || 1024);
        const map = new THREE.CanvasTexture(texCanvas);
        map.colorSpace = THREE.SRGBColorSpace;
        material.map?.dispose();
        material.map = map;
        material.needsUpdate = true;
        colors = [color, color2];
        paintParts(texCanvas, parts, color, color2);
        map.needsUpdate = true;
        obj.traverse(m => { if (m.isMesh) m.material = material; });
        pivot.clear();
        const box = new THREE.Box3().setFromObject(obj);
        obj.position.sub(box.getCenter(new THREE.Vector3()));
        pivot.add(obj);
        const r = box.getSize(new THREE.Vector3()).length() / 2;
        camera.position.set(0, r * 0.9, r * 3.2);
        camera.lookAt(0, 0, 0);
      },
      // Tekstura se slaže iznova najviše jednom po sličici (boja se mijenja dok se vuče po biraču).
      setColors(color, color2) {
        colors = [color, color2];
        if (queued || !parts) return;
        queued = true;
        requestAnimationFrame(() => {
          queued = false;
          paintParts(texCanvas, parts, ...colors);
          material.map.needsUpdate = true;
        });
      },
    };
  });
  return {
    show(...args) { pending = args; ready.then(a => { api = a; if (pending === args) a.show(...args); }); },
    setColors(color, color2) { if (api) api.setColors(color, color2); else if (pending) { pending[2] = color; pending[3] = color2; } },
  };
}

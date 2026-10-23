// Bakugan heroja: oblik iz biblioteke (data/bakugani/catalog.json) i boja po želji.
// Tekstura je siva, pa je boja množi (isto radi TTS s ColorDiffuse): sličice se boje u 2D canvasu, pregled je 3D (three.js).

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

// Siva sličica × boja; prozirna pozadina ostaje prozirna.
export async function paintThumb(canvas, url, color) {
  const img = await image(url);
  const g = canvas.getContext('2d');
  g.clearRect(0, 0, canvas.width, canvas.height);
  g.globalCompositeOperation = 'source-over';
  g.drawImage(img, 0, 0, canvas.width, canvas.height);
  g.globalCompositeOperation = 'multiply';
  g.fillStyle = color;
  g.fillRect(0, 0, canvas.width, canvas.height);
  g.globalCompositeOperation = 'destination-in';
  g.drawImage(img, 0, 0, canvas.width, canvas.height);
  g.globalCompositeOperation = 'source-over';
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
      async show(meshUrl, textureUrl, color) {
        if (!meshes.has(meshUrl)) meshes.set(meshUrl, fetch(meshUrl).then(r => r.text()).then(t => loader.parse(t)));
        const [obj, img] = await Promise.all([meshes.get(meshUrl), image(textureUrl)]);
        const map = new THREE.Texture(img);
        map.colorSpace = THREE.SRGBColorSpace;
        map.needsUpdate = true;
        material.map?.dispose();
        material.map = map;
        material.color.set(color);
        material.needsUpdate = true;
        obj.traverse(m => { if (m.isMesh) m.material = material; });
        pivot.clear();
        const box = new THREE.Box3().setFromObject(obj);
        obj.position.sub(box.getCenter(new THREE.Vector3()));
        pivot.add(obj);
        const r = box.getSize(new THREE.Vector3()).length() / 2;
        camera.position.set(0, r * 0.9, r * 3.2);
        camera.lookAt(0, 0, 0);
      },
      setColor(color) { material.color.set(color); },
    };
  });
  return {
    show(...args) { pending = args; ready.then(a => { api = a; if (pending === args) a.show(...args); }); },
    setColor(color) { if (api) api.setColor(color); else if (pending) pending[2] = color; },
  };
}

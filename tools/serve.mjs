// Lokalni statični server za pregled appa prije GitHub Pagesa: npm start
// Sluša na 127.0.0.1; HOST=127.0.0.1,100.x.y.z doda i druge adrese (npr. Tailscale, za mobitel).
// Port 5101 (blok 5100–5109; 5100 je rezerviran za TTS server iz faze 2).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PORT) || 5101;
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

const HOSTS = (process.env.HOST || '127.0.0.1').split(',').map(s => s.trim()).filter(Boolean);

function handle(req, res) {
  let rel;
  try {
    rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  } catch {
    res.writeHead(400).end();
    return;
  }
  let file = path.join(ROOT, rel);
  if (!file.startsWith(ROOT)) {
    res.writeHead(403).end();
    return;
  }
  // docs/ (privatno) i .git/ samo za ovo računalo, ne za druge uređaje na mreži.
  const local = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
  const top = path.relative(ROOT, file).split(path.sep)[0].toLowerCase();
  if (!local && ['docs', '.git', 'node_modules'].includes(top)) {
    res.writeHead(404).end();
    return;
  }
  if (rel.endsWith('/')) file = path.join(file, 'index.html');
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('404');
      return;
    }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  });
}

for (const host of HOSTS) {
  http.createServer(handle).listen(PORT, host, () => console.log(`Evil Boće: http://${host === '127.0.0.1' ? 'localhost' : host}:${PORT}/`));
}

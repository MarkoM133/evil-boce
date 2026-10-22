// Mali XML parser za Card Engine export. Radi isto u browseru i u Nodeu (testovi),
// pa ne ovisi o DOMParseru. Atributi se ignoriraju; Card Engine ih ne koristi za podatke.

const ENTITIES = { lt: '<', gt: '>', amp: '&', quot: '"', apos: "'" };

function decode(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (m, e) => {
    if (e[0] === '#') {
      const n = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return String.fromCodePoint(n);
    }
    return ENTITIES[e] ?? m;
  });
}

export function parseXml(src) {
  const root = { tag: '#root', children: [], text: '' };
  const stack = [root];
  const re = /<\?[\s\S]*?\?>|<!--[\s\S]*?-->|<!\[CDATA\[([\s\S]*?)\]\]>|<(\/?)([A-Za-z_][\w.:-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>|([^<]+)/g;
  let m;
  while ((m = re.exec(src))) {
    const top = stack[stack.length - 1];
    if (m[1] !== undefined) top.text += m[1];
    else if (m[6] !== undefined) top.text += decode(m[6]);
    else if (m[3] !== undefined) {
      if (m[2] === '/') {
        if (top.tag !== m[3]) throw new Error(`XML: očekivan </${top.tag}>, a došao </${m[3]}>`);
        stack.pop();
      } else {
        const node = { tag: m[3], children: [], text: '' };
        top.children.push(node);
        if (m[5] !== '/') stack.push(node);
      }
    }
  }
  if (stack.length !== 1) throw new Error(`XML: nije zatvoren <${stack[stack.length - 1].tag}>`);
  return root;
}

export function child(node, path) {
  let n = node;
  for (const tag of path.split('/')) {
    n = n?.children.find(c => c.tag === tag);
    if (!n) return undefined;
  }
  return n;
}

export function children(node, tag) {
  return node ? node.children.filter(c => c.tag === tag) : [];
}

export function text(node, path) {
  const n = path ? child(node, path) : node;
  return n ? n.text : undefined;
}

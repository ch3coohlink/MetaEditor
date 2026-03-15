const nodes = new Map()
export const bridge = {
  create: (id, tag) => {
    const el = document.createElement(tag)
    nodes.set(id, el)
  },
  text: (id, text) => {
    const node = nodes.get(id)
    if (node) node.textContent = text
  },
  attr: (id, k, v) => {
    const node = nodes.get(id)
    if (node) node.setAttribute(k, v)
  },
  append: (pid, cid) => {
    const parent = pid === 0 ? document.body : nodes.get(pid)
    const child = nodes.get(cid)
    if (parent && child) parent.appendChild(child)
  }
}

// For MoonBit FFI access
if (typeof globalThis !== 'undefined') {
  globalThis.bridge = bridge
}

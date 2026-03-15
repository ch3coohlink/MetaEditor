const nodes = new Map()

/**
 * JS Thin Bridge for MoonBit MetaEditor
 */
export const bridge = {
  // Command executors
  create: (id, tag) => {
    const el = tag === "" ? document.createTextNode("") : document.createElement(tag)
    nodes.set(id, el)
  },
  text: (id, text) => {
    const node = nodes.get(id)
    if (node) node.textContent = text
  },
  attr: (id, k, v) => {
    const node = nodes.get(id)
    if (node && node.setAttribute) node.setAttribute(k, v)
  },
  append: (pid, cid) => {
    const parent = pid === 0 ? document.body : nodes.get(pid)
    const child = nodes.get(cid)
    if (parent && child) parent.appendChild(child)
  },
  updateText: (id, text) => {
    const node = nodes.get(id)
    if (node) node.textContent = text
  },
  updateAttr: (id, k, v) => {
    const node = nodes.get(id)
    if (node && node.setAttribute) node.setAttribute(k, v)
  },
  remove: (id) => {
    const node = nodes.get(id)
    if (node && node.parentNode) node.parentNode.removeChild(node)
    nodes.delete(id)
  },
  listen: (id, event, cb_id, trigger_fn) => {
    const node = nodes.get(id)
    if (node) {
      node.addEventListener(event, () => {
        trigger_fn(cb_id)
      })
    }
  },

  /**
   * Apply a batch of commands from MoonBit
   * @param {Array} cmds - Array of command objects (output from moon js target)
   * @param {Function} trigger_fn - Callback to trigger MBT events
   */
  apply: (cmds, trigger_fn) => {
    for (const cmd of cmds) {
      // MBT JS Target uses $tag for enum variants
      switch (cmd.$tag) {
        case 0: // Create(id, tag)
          bridge.create(cmd._0, cmd._1)
          break
        case 1: // Text(id, text)
          bridge.text(cmd._0, cmd._1)
          break
        case 2: // Attr(id, k, v)
          bridge.attr(cmd._0, cmd._1, cmd._2)
          break
        case 3: // Append(pid, cid)
          bridge.append(cmd._0, cmd._1)
          break
        case 4: // UpdateText(id, text)
          bridge.updateText(cmd._0, cmd._1)
          break
        case 5: // UpdateAttr(id, k, v)
          bridge.updateAttr(cmd._0, cmd._1, cmd._2)
          break
        case 6: // Remove(id)
          bridge.remove(cmd._0)
          break
        case 7: // Listen(id, event, cb_id)
          bridge.listen(cmd._0, cmd._1, cmd._2, trigger_fn)
          break
      }
    }
  }
}

// Attach to global for easy access from Wasm imports
if (typeof globalThis !== 'undefined') {
  globalThis.mbt_bridge = bridge
}

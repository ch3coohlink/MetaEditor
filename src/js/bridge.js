/**
 * JS Thin Bridge - Universal Version
 * Automatically connects to the host that served the page.
 */
; (function () {
  const nodes = new Map()

  const bridge = {
    create: (id, tag) => {
      const el = tag === '' ? document.createTextNode('') : document.createElement(tag)
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
    insertBefore: (pid, cid, rid) => {
      const parent = pid === 0 ? document.body : nodes.get(pid)
      const child = nodes.get(cid)
      const ref = nodes.get(rid)
      if (parent && child) {
        if (ref) parent.insertBefore(child, ref)
        else parent.appendChild(child)
      }
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
    setStyle: (id, k, v) => {
      const node = nodes.get(id)
      if (node && node.style) node.style[k] = v
    },
    removeStyle: (id, k) => {
      const node = nodes.get(id)
      if (node && node.style) node.style.removeProperty(k)
    },
    removeAttr: (id, k) => {
      const node = nodes.get(id)
      if (node && node.removeAttribute) node.removeAttribute(k)
    },
    hostCmd: (id, cmd) => {
      const node = nodes.get(id)
      if (node && typeof node[cmd] === 'function') node[cmd]()
    },
    apply: (cmds) => {
      for (const cmd of cmds) {
        switch (cmd[0]) {
          case 0: bridge.create(cmd[1], cmd[2]); break
          case 1: bridge.text(cmd[1], cmd[2]); break
          case 2: bridge.attr(cmd[1], cmd[2], cmd[3]); break
          case 3: bridge.append(cmd[1], cmd[2]); break
          case 4: bridge.updateText(cmd[1], cmd[2]); break
          case 5: bridge.updateAttr(cmd[1], cmd[2], cmd[3]); break
          case 6: bridge.remove(cmd[1]); break
          case 7: bridge.listen(cmd[1], cmd[2], cmd[3]); break
          case 8: /* Action */ break
          case 9: bridge.insertBefore(cmd[1], cmd[2], cmd[3]); break
          case 10: bridge.setStyle(cmd[1], cmd[2], cmd[3]); break
          case 11: bridge.removeStyle(cmd[1], cmd[2]); break
          case 12: bridge.removeAttr(cmd[1], cmd[2]); break
          case 13: bridge.hostCmd(cmd[1], cmd[2]); break
        }
      }
    },
    apply_batch: (data) => {
      const cmds = data.map(d => typeof d === 'string' ? JSON.parse(d) : d)
      bridge.apply(cmds)
    },
    connect_to_core: async () => {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
      const host = window.location.host
      const url = `${protocol}//${host}`

      console.log(`Connecting to Core: ${url}`)
      try {
        const socket = new WebSocket(url)
        bridge.ws = socket
        socket.onopen = () => {
          bridge.onstatus?.('connected')
          bridge._setupSocket()
        }
        socket.onerror = (e) => console.error('WS Connection error', e)
        socket.onclose = () => bridge.onstatus?.('disconnected')
      } catch (e) {
        console.error('Failed to initiate WS', e)
      }
    },
    _setupSocket: () => {
      bridge.ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data)
          if (Array.isArray(data)) bridge.apply_batch(data)
        } catch (e) { console.error('Parse error', e) }
      }
    },
    listen: (id, event, cb_id) => {
      const node = nodes.get(id)
      if (node) {
        const evt = event.startsWith('on') ? event.slice(2) : event
        const isKey = evt === 'keydown' || evt === 'keyup' || evt === 'keypress'
        node.addEventListener(evt, (e) => {
          if (bridge.ws && bridge.ws.readyState === 1) {
            if (isKey) {
              const data = [e.key, e.code, e.ctrlKey?1:0, e.shiftKey?1:0, e.altKey?1:0, e.metaKey?1:0].join('|')
              bridge.ws.send(JSON.stringify({ type: 'event_data', callback_id: cb_id, data }))
            } else {
              bridge.ws.send(JSON.stringify({ type: 'event', callback_id: cb_id }))
            }
          }
        })
      }
    },
  }

  globalThis.mbt_bridge = bridge
  console.log('Bridge (Universal) initialized.')
})()

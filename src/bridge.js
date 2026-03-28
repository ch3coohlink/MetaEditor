/**
 * JS Thin Bridge - Universal Version
 * Automatically connects to the host that served the page.
 */
; (function () {
  const nodes = new Map()
  let nodeIds = new WeakMap()
  const sessionKey = 'mbt_bridge_session_id'
  const isElement = node => node && node.nodeType === Node.ELEMENT_NODE
  const isText = node => node && node.nodeType === Node.TEXT_NODE
  const randomId = () => {
    if (globalThis.crypto?.randomUUID) {
      return globalThis.crypto.randomUUID()
    }
    return `${Date.now()}-${Math.random().toString(16).slice(2)}`
  }
  const toPlainRect = rect => ({
    x: rect.x,
    y: rect.y,
    top: rect.top,
    left: rect.left,
    right: rect.right,
    bottom: rect.bottom,
    width: rect.width,
    height: rect.height,
  })
  const getNodeId = node => {
    if (!node) {
      return null
    }
    if (nodeIds.has(node)) {
      return nodeIds.get(node)
    }
    if (isElement(node)) {
      const raw = node.getAttribute('data-mbt-id')
      return raw == null ? null : Number(raw)
    }
    return null
  }
  const readAttrs = node => {
    if (!isElement(node)) {
      return {}
    }
    const attrs = {}
    for (const attr of node.attributes) attrs[attr.name] = attr.value
    return attrs
  }
  const readVisibility = node => {
    if (!isElement(node)) {
      return { visible: false, reason: 'not-element' }
    }
    const style = window.getComputedStyle(node)
    const rect = node.getBoundingClientRect()
    const visible = style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      Number(style.opacity || '1') !== 0 &&
      rect.width > 0 &&
      rect.height > 0
    return { visible, display: style.display, visibility: style.visibility, opacity: style.opacity }
  }
  const snapshotNode = (id, node) => {
    if (!node) {
      return null
    }
    const parentId = getNodeId(node.parentNode)
    if (isText(node)) {
      return {
        id,
        kind: 'text',
        text: node.textContent ?? '',
        parent_id: parentId,
      }
    }
    if (!isElement(node)) {
      return {
        id,
        kind: 'other',
        parent_id: parentId,
      }
    }
    const rect = node.getBoundingClientRect()
    const visibility = readVisibility(node)
    return {
      id,
      kind: 'element',
      tag: node.tagName.toLowerCase(),
      text: node.textContent ?? '',
      value: 'value' in node ? node.value : undefined,
      checked: 'checked' in node ? !!node.checked : undefined,
      focused: document.activeElement === node,
      parent_id: parentId,
      child_ids: Array.from(node.childNodes).map(getNodeId).filter(value => value != null),
      attrs: readAttrs(node),
      rect: toPlainRect(rect),
      visible: visibility.visible,
      visibility,
    }
  }
  const snapshotAllNodes = () => Array.from(nodes.entries())
    .sort((a, b) => a[0] - b[0])
    .map(([id, node]) => snapshotNode(id, node))
    .filter(Boolean)
  const getViewportSnapshot = () => ({
    width: window.innerWidth,
    height: window.innerHeight,
    scroll_x: window.scrollX,
    scroll_y: window.scrollY,
    device_pixel_ratio: window.devicePixelRatio,
  })
  const findNodeByTarget = target => {
    if (!target) return null
    if (target.id != null) {
      const node = nodes.get(Number(target.id))
      if (node) {
        return { id: Number(target.id), node }
      }
    }
    if (target.selector) {
      const node = document.querySelector(target.selector)
      if (node) {
        return { id: getNodeId(node), node }
      }
    }
    return null
  }
  const emitResponse = (requestId, ok, result, error) => {
    if (bridge.ws && bridge.ws.readyState === 1) {
      bridge.ws.send(JSON.stringify({
        type: 'bridge:response',
        request_id: requestId,
        ok,
        result,
        error,
      }))
    }
  }
  const sendEvent = payload => {
    queueMicrotask(() => {
      if (bridge.ws && bridge.ws.readyState === 1) {
        bridge.ws.send(JSON.stringify(payload))
      }
    })
  }
  const resetManagedDom = () => {
    for (const node of nodes.values()) {
      if (node && node.parentNode) {
        node.parentNode.removeChild(node)
      }
    }
    for (const node of Array.from(document.body.childNodes)) {
      if (node.id === 'app-info') {
        continue
      }
      if (node.nodeType === Node.ELEMENT_NODE && node.tagName === 'SCRIPT') {
        continue
      }
      document.body.removeChild(node)
    }
    nodes.clear()
    nodeIds = new WeakMap()
  }

  const bridge = {
    ws: null,
    reconnect_timer: null,
    reconnect_delay_ms: 300,
    should_reconnect: true,
    state: 'idle',
    reject_reason: null,
    session_id: null,
    sessionId: () => {
      if (bridge.session_id) {
        return bridge.session_id
      }
      let sessionId = globalThis.localStorage?.getItem(sessionKey)
      if (!sessionId) {
        sessionId = randomId()
        globalThis.localStorage?.setItem(sessionKey, sessionId)
      }
      bridge.session_id = sessionId
      return sessionId
    },
    reconnectLater: () => {
      if (!bridge.should_reconnect || bridge.reconnect_timer != null) {
        return
      }
      bridge.state = 'reconnecting'
      bridge.onstatus?.('reconnecting')
      bridge.reconnect_timer = setTimeout(() => {
        bridge.reconnect_timer = null
        bridge.connect_to_core()
      }, bridge.reconnect_delay_ms)
    },
    create: (id, tag, ns) => {
      const el = tag === '' ? document.createTextNode('') :
        ns === 'http://www.w3.org/1999/xhtml' ? document.createElement(tag) :
        document.createElementNS(ns, tag)
      nodes.set(id, el)
      nodeIds.set(el, id)
      if (isElement(el)) {
        el.setAttribute('data-mbt-id', String(id))
      }
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
    remove: id => {
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
    apply: cmds => {
      for (const cmd of cmds) {
        switch (cmd[0]) {
          case 0: bridge.create(cmd[1], cmd[2], cmd[3]); break
          case 1: bridge.text(cmd[1], cmd[2]); break
          case 2: bridge.attr(cmd[1], cmd[2], cmd[3]); break
          case 3: bridge.append(cmd[1], cmd[2]); break
          case 4: bridge.updateText(cmd[1], cmd[2]); break
          case 5: bridge.updateAttr(cmd[1], cmd[2], cmd[3]); break
          case 6: bridge.remove(cmd[1]); break
          case 7: bridge.listen(cmd[1], cmd[2], cmd[3]); break
          case 8: break
          case 9: bridge.insertBefore(cmd[1], cmd[2], cmd[3]); break
          case 10: bridge.setStyle(cmd[1], cmd[2], cmd[3]); break
          case 11: bridge.removeStyle(cmd[1], cmd[2]); break
          case 12: bridge.removeAttr(cmd[1], cmd[2]); break
          case 13: bridge.hostCmd(cmd[1], cmd[2]); break
        }
      }
    },
    apply_batch: data => {
      const cmds = data.map(d => typeof d === 'string' ? JSON.parse(d) : d)
      bridge.apply(cmds)
    },
    query: query => {
      switch (query?.kind) {
        case 'ui':
          return {
            title: document.title,
            url: location.href,
            viewport: getViewportSnapshot(),
            active_element_id: getNodeId(document.activeElement),
            nodes: snapshotAllNodes(),
          }
        case 'viewport':
          return getViewportSnapshot()
        case 'focused': {
          const id = getNodeId(document.activeElement)
          if (id == null) {
            return null
          }
          return snapshotNode(id, document.activeElement)
        }
        case 'node': {
          const id = Number(query.id)
          return snapshotNode(id, nodes.get(id))
        }
        case 'selector': {
          const target = findNodeByTarget(query)
          return target ? snapshotNode(target.id, target.node) : null
        }
        case 'text': {
          const target = findNodeByTarget(query)
          return target ? { id: target.id, text: target.node.textContent ?? '' } : null
        }
        default:
          throw Error(`unsupported query kind: ${query?.kind}`)
      }
    },
    exec: command => {
      const target = findNodeByTarget(command)
      if (!target || !target.node) {
        throw Error('target not found')
      }
      const node = target.node
      switch (command.kind) {
        case 'click':
          if (!isElement(node)) {
            throw Error('click target is not element')
          }
          node.click()
          return { ok: true, kind: 'click', target: snapshotNode(target.id, node) }
        case 'focus':
          if (!isElement(node) || typeof node.focus !== 'function') {
            throw Error('focus target is not focusable')
          }
          node.focus()
          return { ok: true, kind: 'focus', target: snapshotNode(target.id, node) }
        case 'input':
          if (!isElement(node) || !('value' in node)) {
            throw Error('input target has no value')
          }
          node.value = command.text ?? ''
          node.dispatchEvent(new Event('input', { bubbles: true }))
          node.dispatchEvent(new Event('change', { bubbles: true }))
          return { ok: true, kind: 'input', target: snapshotNode(target.id, node) }
        default:
          throw Error(`unsupported exec kind: ${command.kind}`)
      }
    },
    sync: () => ({ ok: true }),
    connect_to_core: async () => {
      if (
        bridge.ws &&
        (bridge.ws.readyState === WebSocket.OPEN || bridge.ws.readyState === WebSocket.CONNECTING)
      ) {
        return
      }
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
      const host = window.location.host
      const url = `${protocol}//${host}`

      console.log(`Connecting to Core: ${url}`)
      try {
        bridge.should_reconnect = true
        bridge.state = 'connecting'
        bridge.onstatus?.('connecting')
        const socket = new WebSocket(url)
        bridge.ws = socket
        socket.onopen = () => {
          bridge._setupSocket()
          socket.send(JSON.stringify({
            type: 'bridge:hello',
            role: 'browser',
            user_agent: navigator.userAgent,
            session_id: bridge.sessionId(),
          }))
        }
        socket.onerror = e => console.error('WS Connection error', e)
        socket.onclose = () => {
          bridge.ws = null
          if (bridge.state === 'rejected') {
            return
          }
          bridge.state = 'disconnected'
          bridge.onstatus?.('disconnected')
          bridge.reconnectLater()
        }
      } catch (e) {
        console.error('Failed to initiate WS', e)
        bridge.reconnectLater()
      }
    },
    _setupSocket: () => {
      bridge.ws.onmessage = event => {
        try {
          const data = JSON.parse(event.data)
          if (Array.isArray(data)) {
            bridge.apply_batch(data)
          } else if (data.type === 'bridge:hello_ack') {
            resetManagedDom()
            bridge.state = 'connected'
            bridge.reject_reason = null
            bridge.should_reconnect = true
            bridge.onstatus?.('connected')
          } else if (data.type === 'bridge:rejected') {
            bridge.state = 'rejected'
            bridge.reject_reason = data.reason
            bridge.should_reconnect = false
            if (bridge.reconnect_timer != null) {
              clearTimeout(bridge.reconnect_timer)
              bridge.reconnect_timer = null
            }
            bridge.onstatus?.('rejected')
            bridge.ws?.close()
          } else if (data.type === 'bridge:request') {
            try {
              const result = data.action === 'query'
                ? bridge.query(data.query)
                : data.action === 'exec'
                  ? bridge.exec(data.command)
                  : data.action === 'sync'
                    ? bridge.sync()
                    : (() => { throw Error(`unsupported request action: ${data.action}`) })()
              emitResponse(data.request_id, true, result)
            } catch (error) {
              emitResponse(data.request_id, false, null, error.message)
            }
          }
        } catch (e) {
          console.error('Parse error', e)
        }
      }
    },
    listen: (id, event, cb_id) => {
      const node = nodes.get(id)
      if (node) {
        const evt = event.startsWith('on') ? event.slice(2) : event
        const isKey = evt === 'keydown' || evt === 'keyup' || evt === 'keypress'
        node.addEventListener(evt, e => {
          if (bridge.ws && bridge.ws.readyState === 1) {
            if (isKey) {
              const data = [e.key, e.code, e.ctrlKey ? 1 : 0, e.shiftKey ? 1 : 0, e.altKey ? 1 : 0, e.metaKey ? 1 : 0].join('|')
              sendEvent({ type: 'event_data', callback_id: cb_id, data })
            } else {
              sendEvent({ type: 'event', callback_id: cb_id })
            }
          }
        })
      }
    },
  }

  globalThis.mbt_bridge = bridge
  console.log('Bridge (Universal) initialized.')
})()

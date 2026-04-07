"strict mode"
/**
 * JS Thin Bridge - Universal Version
 * Automatically connects to the host that served the page.
 */
const DOM_CMD = Object.freeze({
  CREATE: 0,
  TEXT: 1,
  ATTR: 2,
  APPEND: 3,
  REMOVE: 6,
  LISTEN: 7,
  INSERT_BEFORE: 8,
  SET_STYLE: 9,
  REMOVE_STYLE: 10,
  REMOVE_ATTR: 11,
  HOST_CMD: 12,
  SET_CSS: 13,
  REMOVE_CSS: 14,
})
const MSG = Object.freeze({
  PING: 'bridge:ping',
  RESPONSE: 'bridge:response',
  HELLO: 'bridge:hello',
  HELLO_ACK: 'bridge:hello_ack',
  PONG: 'bridge:pong',
  REJECTED: 'bridge:rejected',
  REQUEST: 'bridge:request',
})
const nodes = new Map()
const stylesheets = new Map()
let pingSeq = 1
let pingPending = null
let pingTimer = null
let latencyMs = null
let nodeIds = new WeakMap()
let nextRequestId = 1
const pendingRequests = new Map()
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
  if (!node) { return null }
  if (nodeIds.has(node)) { return nodeIds.get(node) }
  return null
}
const readAttrs = node => {
  if (!isElement(node)) { return {} }
  const attrs = {}
  for (const attr of node.attributes) { attrs[attr.name] = attr.value }
  return attrs
}
const snapshotNode = (id, node) => {
  if (!node) { return null }
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
  const style = window.getComputedStyle(node)
  const visibility = {
    visible: style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      Number(style.opacity || '1') !== 0 &&
      rect.width > 0 &&
      rect.height > 0,
    display: style.display,
    visibility: style.visibility,
    opacity: style.opacity,
  }
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
const removeNodeTree = node => {
  if (!node) { return }
  for (const child of Array.from(node.childNodes ?? [])) { removeNodeTree(child) }
  const id = getNodeId(node)
  if (id != null) { nodes.delete(id) }
}
const resolveNode = target => {
  const id = target?.id != null ? Number(target.id) : null
  return id != null && nodes.has(id) ? { id, node: nodes.get(id) } : null
}
const queryPathId = async path => {
  const result = await bridge.request('query', { query: { kind: 'path', path } })
  const id = Number(result?.id)
  return Number.isFinite(id) ? id : null
}
const eventInt = v => (typeof v === 'number' && Number.isFinite(v)) ? Math.round(v) : 0
const sendPing = () => {
  if (!bridge.ws || bridge.ws.readyState !== 1 || pingPending) {
    return
  }
  pingPending = {
    seq: pingSeq,
    sentAt: performance.now(),
  }
  pingSeq += 1
  bridge.ws.send(JSON.stringify({
    type: MSG.PING,
    seq: pingPending.seq,
    latency_ms: latencyMs == null ? undefined : Math.round(latencyMs),
  }))
}
const resetPing = () => {
  pingPending = null
  latencyMs = null
}
const ensurePingLoop = () => {
  if (pingTimer != null) {
    return
  }
  pingTimer = setInterval(() => {
    sendPing()
  }, 2000)
}
const emitResponse = (requestId, ok, result, error) => {
  if (bridge.ws && bridge.ws.readyState === 1) {
    bridge.ws.send(JSON.stringify({
      type: MSG.RESPONSE,
      request_id: requestId,
      ok,
      result,
      error,
    }))
  }
}
const settlePendingRequest = (requestId, ok, result, error) => {
  const pending = pendingRequests.get(requestId)
  if (!pending) {
    return false
  }
  pendingRequests.delete(requestId)
  if (ok) {
    pending.resolve(result)
  } else {
    pending.reject(Error(error ?? 'bridge request failed'))
  }
  return true
}
const rejectPendingRequests = error => {
  for (const [requestId, pending] of pendingRequests.entries()) {
    pendingRequests.delete(requestId)
    pending.reject(error)
  }
}
const serializeEventData = e => [
  e?.key ?? '', e?.code ?? '', e?.ctrlKey ? 1 : 0, e?.shiftKey ? 1 : 0,
  e?.altKey ? 1 : 0, e?.metaKey ? 1 : 0, eventInt(e?.clientX),
  eventInt(e?.clientY), eventInt(e?.button), eventInt(e?.buttons), eventInt(e?.pointerId),
].join('|')
const sendEvent = payload => {
  queueMicrotask(() => {
    if (bridge.ws && bridge.ws.readyState === 1) {
      bridge.ws.send(JSON.stringify(payload))
    }
  })
}
const addDragListeners = (target, move, up) => {
  target.addEventListener('pointermove', move)
  target.addEventListener('pointerup', up)
  target.addEventListener('pointercancel', up)
}
const removeDragListeners = (target, move, up) => {
  target.removeEventListener('pointermove', move)
  target.removeEventListener('pointerup', up)
  target.removeEventListener('pointercancel', up)
}
const drag = (event, move, up, stop = true) => {
  if (stop) { event.stopPropagation() }
  const target = event.currentTarget
  if (!target || typeof target.setPointerCapture !== 'function') { return }
  const pointerId = event.pointerId
  const finish = nextEvent => {
    if (target.hasPointerCapture?.(pointerId)) {
      target.releasePointerCapture(pointerId)
    }
    removeDragListeners(target, move, finish)
    up?.(nextEvent)
  }
  target.setPointerCapture(pointerId)
  addDragListeners(target, move, finish)
}
const resetManagedDom = () => {
  for (const node of nodes.values()) {
    if (node && node.parentNode) {
      node.parentNode.removeChild(node)
    }
  }
  document.body.replaceChildren()
  nodes.clear()
  for (const style of stylesheets.values()) {
    if (style && style.parentNode) {
      style.parentNode.removeChild(style)
    }
  }
  stylesheets.clear()
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
  request: (action, payload = {}) => {
    if (!bridge.ws || bridge.ws.readyState !== 1) {
      return Promise.reject(Error('bridge is not connected'))
    }
    const requestId = nextRequestId
    nextRequestId += 1
    return new Promise((resolve, reject) => {
      pendingRequests.set(requestId, { resolve, reject })
      try {
        bridge.ws.send(JSON.stringify({
          type: MSG.REQUEST,
          request_id: requestId,
          action,
          ...payload,
        }))
      } catch (error) {
        pendingRequests.delete(requestId)
        reject(error)
      }
    })
  },
  sessionId: () => {
    if (bridge.session_id) { return bridge.session_id }
    let sessionId = globalThis.localStorage?.getItem(sessionKey)
    if (!sessionId) {
      sessionId = randomId()
      globalThis.localStorage?.setItem(sessionKey, sessionId)
    }
    bridge.session_id = sessionId
    return sessionId
  },
  reconnectLater: () => {
    if (!bridge.should_reconnect || bridge.reconnect_timer != null) { return }
    bridge.state = 'reconnecting'
    resetPing()
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
  },
  text: (id, text) => {
    const node = nodes.get(id)
    if (node) { node.textContent = text }
  },
  attr: (id, k, v) => {
    const node = nodes.get(id)
    if (node && node.setAttribute) { node.setAttribute(k, v) }
  },
  append: (pid, cid) => {
    const parent = pid === 0 ? document.body : nodes.get(pid)
    const child = nodes.get(cid)
    if (parent && child) { parent.appendChild(child) }
  },
  insertBefore: (pid, cid, rid) => {
    const parent = pid === 0 ? document.body : nodes.get(pid)
    const child = nodes.get(cid)
    const ref = nodes.get(rid)
    if (parent && child) {
      if (ref) { parent.insertBefore(child, ref) }
      else { parent.appendChild(child) }
    }
  },
  remove: id => {
    const node = nodes.get(id)
    if (node) {
      removeNodeTree(node)
      if (node.parentNode) { node.parentNode.removeChild(node) }
    } else { nodes.delete(id) }
  },
  setStyle: (id, k, v) => {
    const node = nodes.get(id)
    if (node && node.style) { node.style.setProperty(k, v) }
  },
  removeStyle: (id, k) => {
    const node = nodes.get(id)
    if (node && node.style) { node.style.removeProperty(k) }
  },
  removeAttr: (id, k) => {
    const node = nodes.get(id)
    if (node && node.removeAttribute) { node.removeAttribute(k) }
  },
  setCss: (id, text) => {
    let node = stylesheets.get(id)
    if (!node) {
      node = document.createElement('style')
      node.setAttribute('data-mbt-css', id)
      stylesheets.set(id, node)
      document.head.appendChild(node)
    }
    node.textContent = text
  },
  removeCss: id => {
    const node = stylesheets.get(id)
    if (node && node.parentNode) { node.parentNode.removeChild(node) }
    stylesheets.delete(id)
  },
  hostCmd: (id, cmd) => {
    const node = nodes.get(id)
    if (node && typeof node[cmd] === 'function') node[cmd]()
  },
  apply: cmds => {
    for (const cmd of cmds) {
      switch (cmd[0]) {
        case DOM_CMD.CREATE: bridge.create(cmd[1], cmd[2], cmd[3]); break
        case DOM_CMD.TEXT: bridge.text(cmd[1], cmd[2]); break
        case DOM_CMD.ATTR: bridge.attr(cmd[1], cmd[2], cmd[3]); break
        case DOM_CMD.APPEND: bridge.append(cmd[1], cmd[2]); break
        case DOM_CMD.REMOVE: bridge.remove(cmd[1]); break
        case DOM_CMD.LISTEN: bridge.listen(cmd[1], cmd[2], cmd[3]); break
        case DOM_CMD.INSERT_BEFORE: bridge.insertBefore(cmd[1], cmd[2], cmd[3]); break
        case DOM_CMD.SET_STYLE: bridge.setStyle(cmd[1], cmd[2], cmd[3]); break
        case DOM_CMD.REMOVE_STYLE: bridge.removeStyle(cmd[1], cmd[2]); break
        case DOM_CMD.REMOVE_ATTR: bridge.removeAttr(cmd[1], cmd[2]); break
        case DOM_CMD.HOST_CMD: bridge.hostCmd(cmd[1], cmd[2]); break
        case DOM_CMD.SET_CSS: bridge.setCss(cmd[1], cmd[2]); break
        case DOM_CMD.REMOVE_CSS: bridge.removeCss(cmd[1]); break
      }
    }
  },
  apply_batch: data => {
    const cmds = data.map(d => typeof d === 'string' ? JSON.parse(d) : d)
    bridge.apply(cmds)
  },
  queryLocal: query => {
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
        const target = resolveNode(query)
        return target ? snapshotNode(target.id, target.node) : null
      }
      case 'text': {
        const target = resolveNode(query)
        return target ? { id: target.id, text: target.node.textContent ?? '' } : null
      }
      default:
        throw Error(`unsupported query kind: ${query?.kind}`)
    }
  },
  query: async query => {
    if (typeof query === 'string') {
      const id = await queryPathId(query)
      return Number.isFinite(id) ? snapshotNode(id, nodes.get(id)) : null
    }
    return bridge.queryLocal(query)
  },
  queryNodeForTest: async target => {
    const id = typeof target === 'string' ? await queryPathId(target) : target?.id
    return Number.isFinite(Number(id)) ? nodes.get(Number(id)) ?? null : null
  },
  command: async (cmd, arg = '') => {
    const result = await bridge.request('command', { cmd, arg })
    return typeof result === 'string' ? result : ''
  },
  // 仅供 service 的 CLI / REPL 远程控制入口按已解析好的 VNode id 触发浏览器本地动作。
  // browser test 的正式动作路径不走这里
  trigger: cmd => {
    const target = resolveNode(cmd)
    if (!target) { throw Error('target not found') }
    const { id, node } = target
    const evt = (n, pts = {}) => new (globalThis.PointerEvent ?? MouseEvent)(n, {
      bubbles: true, clientX: eventInt(pts.x ?? cmd.x),
      clientY: eventInt(pts.y ?? cmd.y), button: eventInt(cmd.button),
      buttons: eventInt(cmd.buttons ?? (pts.btns ?? 0))
    })
    switch (cmd.kind) {
      case 'pointer': case 'click': case 'dblclick': {
        const name = cmd.name || cmd.kind
        if (name === 'click') { node.click() }
        else if (name === 'dblclick') {
          ['mousedown', 'mouseup', 'click', 'mousedown', 'mouseup',
            'click', 'dblclick'].forEach(n => node.dispatchEvent(evt(n)))
        } else {
          node.dispatchEvent(evt(name === 'down' ? 'pointerdown' :
            name === 'move' ? 'pointermove' : name === 'up' ? 'pointerup' : name))
        }
        return { ok: true, kind: 'pointer', name, target: snapshotNode(id, node) }
      }
      case 'focus': {
        node.focus()
        return { ok: true, kind: 'focus', target: snapshotNode(id, node) }
      }
      case 'input': {
        node.value = cmd.text ?? ''
        node.dispatchEvent(new Event('input', { bubbles: true }))
        node.dispatchEvent(new Event('change', { bubbles: true }))
        return { ok: true, kind: 'input', target: snapshotNode(id, node) }
      }
      case 'key': {
        const name = cmd.name ?? 'keydown'
        node.dispatchEvent(new KeyboardEvent(name, {
          bubbles: true, key: cmd.key ?? '', code: cmd.code ?? '',
          ctrlKey: !!cmd.ctrlKey, shiftKey: !!cmd.shiftKey,
          altKey: !!cmd.altKey, metaKey: !!cmd.metaKey
        }))
        return { ok: true, kind: 'key', name, target: snapshotNode(id, node) }
      }
      case 'drag': {
        const pts = Array.isArray(cmd.points) ? cmd.points : []
        if (pts.length < 2) throw Error('drag expects at least two points')
        node.dispatchEvent(evt('pointerdown', { ...pts[0], btns: 1 }))
        pts.slice(1, -1).forEach(p => node.dispatchEvent(evt('pointermove', { ...p, btns: 1 })))
        node.dispatchEvent(evt('pointerup', { ...pts[pts.length - 1], btns: 0 }))
        return { ok: true, kind: 'drag', target: snapshotNode(id, node) }
      }
      default: { throw Error(`unsupported trigger kind: ${cmd.kind}`) }
    }
  },
  sync: () => ({ ok: true }),
  resetForTest: () => {
    bridge.should_reconnect = false
    bridge.reject_reason = null
    if (bridge.reconnect_timer != null) {
      clearTimeout(bridge.reconnect_timer)
      bridge.reconnect_timer = null
    }
    const oldWs = bridge.ws
    if (oldWs) {
      oldWs.onopen = null
      oldWs.onmessage = null
      oldWs.onclose = null
      oldWs.onerror = null
      oldWs.close?.()
    }
    bridge.ws = null
    rejectPendingRequests(Error('bridge reset'))
    bridge.state = 'idle'
    resetManagedDom()
    resetPing()
  },
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
          type: MSG.HELLO,
          role: 'browser',
          user_agent: navigator.userAgent,
          session_id: bridge.sessionId(),
        }))
      }
      socket.onerror = e => console.error('WS Connection error', e)
      socket.onclose = () => {
        bridge.ws = null
        rejectPendingRequests(Error('bridge disconnected'))
        if (bridge.state === 'rejected') {
          return
        }
        bridge.state = 'disconnected'
        resetPing()
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
        } else if (data.type === MSG.HELLO_ACK) {
          resetManagedDom()
          bridge.state = 'connected'
          bridge.reject_reason = null
          bridge.should_reconnect = true
          ensurePingLoop()
          sendPing()
          bridge.onstatus?.('connected')
        } else if (data.type === MSG.PONG) {
          if (pingPending && data.seq === pingPending.seq) {
            latencyMs = performance.now() - pingPending.sentAt
            pingPending = null
          }
        } else if (data.type === MSG.RESPONSE) {
          settlePendingRequest(data.request_id, !!data.ok, data.result, data.error)
        } else if (data.type === MSG.REJECTED) {
          bridge.state = 'rejected'
          bridge.reject_reason = data.reason
          bridge.should_reconnect = false
          rejectPendingRequests(Error(data.reason ?? 'bridge rejected'))
          resetPing()
          if (bridge.reconnect_timer != null) {
            clearTimeout(bridge.reconnect_timer)
            bridge.reconnect_timer = null
          }
          bridge.onstatus?.('rejected')
          bridge.ws?.close()
        } else if (data.type === MSG.REQUEST) {
          Promise.resolve()
            .then(() => {
              if (data.action === 'query') {
                return bridge.queryLocal(data.query)
              }
              if (data.action === 'trigger') {
                return bridge.trigger(data.command)
              }
              if (data.action === 'sync') {
                return bridge.sync()
              }
              throw Error(`unsupported request action: ${data.action}`)
            })
            .then(result => {
              emitResponse(data.request_id, true, result)
            })
            .catch(error => {
              emitResponse(data.request_id, false, null, error.message)
            })
        }
      } catch (e) {
        console.error('Parse error', e)
      }
    }
  },
  listen: (id, event, _targetName) => {
    const node = nodes.get(id)
    if (node) {
      const evt = event.startsWith('on') ? event.slice(2) : event
      const wantsData = evt.startsWith('key') ||
        evt.startsWith('pointer') ||
        evt.startsWith('mouse')
      node.addEventListener(evt, e => {
        if (evt === 'dblclick') {
          e.preventDefault()
        }
        if (bridge.ws && bridge.ws.readyState === 1) {
          if (wantsData) {
            const data = serializeEventData(e)
            sendEvent({ type: 'event_data', id, event, data })
          } else {
            sendEvent({ type: 'event', id, event })
          }
        }
      })
    }
  },
}

bridge.DOM_CMD = DOM_CMD
bridge.MSG = MSG
bridge.drag = drag
globalThis.mbt_bridge = bridge
console.log('Bridge (Universal) initialized.')

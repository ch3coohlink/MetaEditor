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
  REMOVE: 4,
  LISTEN: 5,
  INSERT_BEFORE: 6,
  SET_STYLE: 7,
  REMOVE_STYLE: 8,
  REMOVE_ATTR: 9,
  SET_CSS: 10,
  REMOVE_CSS: 11,
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
let ws = null
let reconnectTimer = null
let shouldReconnect = true
let bridgeState = 'idle'
let rejectReason = null
let sessionIdValue = null
let statusListener = null
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
    visible: style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      Number(style.opacity || '1') !== 0 &&
      rect.width > 0 &&
      rect.height > 0,
  }
}
const removeNodeTree = node => {
  if (!node) { return }
  for (const child of Array.from(node.childNodes ?? [])) { removeNodeTree(child) }
  const id = getNodeId(node)
  if (id != null) { nodes.delete(id) }
}
const eventInt = v => (typeof v === 'number' && Number.isFinite(v)) ? Math.round(v) : 0
const sendPing = () => {
  if (!ws || ws.readyState !== 1 || pingPending) {
    return
  }
  pingPending = {
    seq: pingSeq,
    sentAt: performance.now(),
  }
  pingSeq += 1
  ws.send(JSON.stringify({
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
  if (ws && ws.readyState === 1) {
    ws.send(JSON.stringify({
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
    if (ws && ws.readyState === 1) {
      ws.send(JSON.stringify(payload))
    }
  })
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
const managed = target => {
  const id = target?.id != null ? Number(target.id) : Number(target)
  const node = Number.isFinite(id) ? nodes.get(id) ?? null : null
  return node ? { id, node } : null
}
const listenerConfig = event => {
  const parts = String(event ?? '').split('.').filter(Boolean)
  const base = parts[0] ?? ''
  return {
    event: base,
    stop: parts.includes('stop'),
  }
}
const queryById = (target, kind = 'node', value = undefined) => {
  const current = managed(target)
  const node = current ? snapshotNode(current.id, current.node) : null
  if (!node || kind === 'node') { return node }
  if (kind === 'text') { return { id: node.id, text: node.text ?? '' } }
  if (kind === 'style') {
    const key = typeof value === 'string' ? value : ''
    if (key === '') {
      throw Error('query style expects property name')
    }
    if (!isElement(current?.node)) {
      throw Error('query style expects element node')
    }
    return {
      id: node.id,
      kind,
      key,
      value: window.getComputedStyle(current.node).getPropertyValue(key),
    }
  }
  throw Error(`unsupported query kind: ${kind}`)
}
const keyCommand = value => ({
  key: value?.key ?? '',
  key_event: value?.event ?? undefined,
  code: value?.code ?? undefined,
  ctrl_key: !!value?.ctrlKey,
  shift_key: !!value?.shiftKey,
  alt_key: !!value?.altKey,
  meta_key: !!value?.metaKey,
})
const getStatus = () => ({
  state: bridgeState,
  reason: rejectReason ?? undefined,
})
const emitStatus = () => {
  statusListener?.(getStatus())
}
const setStatus = (state, reason = null) => {
  bridgeState = state
  rejectReason = reason
  emitStatus()
}
const sendRequest = (action, payload = {}) => {
  if (!ws || ws.readyState !== 1) {
    return Promise.reject(Error('bridge is not connected'))
  }
  const requestId = nextRequestId
  nextRequestId += 1
  return new Promise((resolve, reject) => {
    pendingRequests.set(requestId, { resolve, reject })
    try {
      ws.send(JSON.stringify({
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
}
const ensureSessionId = () => {
  if (sessionIdValue) { return sessionIdValue }
  let sessionId = globalThis.localStorage?.getItem(sessionKey)
  if (!sessionId) {
    sessionId = randomId()
    globalThis.localStorage?.setItem(sessionKey, sessionId)
  }
  sessionIdValue = sessionId
  return sessionId
}
const resolvePath = async path => {
  if (typeof path !== 'string') {
    throw Error('query path must be a string')
  }
  const result = await sendRequest('query', { path })
  const id = Number(result?.id)
  return Number.isFinite(id) ? id : null
}
const updateReconnect = nextReconnect => {
  shouldReconnect = nextReconnect
}
const reconnectLater = () => {
  if (!shouldReconnect || reconnectTimer != null) { return }
  setStatus('reconnecting')
  resetPing()
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null
    bridge.init()
  }, 300)
}
const domOps = {
  [DOM_CMD.CREATE]: (id, tag, ns) => {
    const el = tag === '' ? document.createTextNode('') :
      ns === 'http://www.w3.org/1999/xhtml' ? document.createElement(tag) :
        document.createElementNS(ns, tag)
    nodes.set(id, el)
    nodeIds.set(el, id)
  },
  [DOM_CMD.TEXT]: (id, text) => {
    const node = managed(id)?.node
    if (node) { node.textContent = text }
  },
  [DOM_CMD.ATTR]: (id, k, v) => {
    const node = managed(id)?.node
    if (node && node.setAttribute) { node.setAttribute(k, v) }
  },
  [DOM_CMD.APPEND]: (pid, cid) => {
    const parent = Number(pid) === 0 ? document.body : managed(pid)?.node
    const child = managed(cid)?.node
    if (parent && child) { parent.appendChild(child) }
  },
  [DOM_CMD.REMOVE]: id => {
    const node = managed(id)?.node
    if (node) {
      removeNodeTree(node)
      if (node.parentNode) { node.parentNode.removeChild(node) }
    } else {
      nodes.delete(Number(id))
    }
  },
  [DOM_CMD.LISTEN]: (id, event) => {
    const node = managed(id)?.node
    if (!node) { return }
    const listener = listenerConfig(event)
    const evt = listener.event.startsWith('on') ? listener.event.slice(2) : listener.event
    const wantsData = evt.startsWith('key') || evt.startsWith('pointer') || evt.startsWith('mouse')
    node.addEventListener(evt, e => {
      if (listener.stop) {
        e.stopPropagation()
      }
      if (evt === 'dblclick') {
        e.preventDefault()
      }
      if (ws && ws.readyState === 1) {
        if (wantsData) {
          sendEvent({ type: 'event_data', id, event: listener.event, data: serializeEventData(e) })
        } else {
          sendEvent({ type: 'event', id, event: listener.event })
        }
      }
    })
  },
  [DOM_CMD.INSERT_BEFORE]: (pid, cid, rid) => {
    const parent = Number(pid) === 0 ? document.body : managed(pid)?.node
    const child = managed(cid)?.node
    const ref = managed(rid)?.node
    if (parent && child) {
      if (ref) { parent.insertBefore(child, ref) }
      else { parent.appendChild(child) }
    }
  },
  [DOM_CMD.SET_STYLE]: (id, k, v) => managed(id)?.node?.style?.setProperty(k, v),
  [DOM_CMD.REMOVE_STYLE]: (id, k) => managed(id)?.node?.style?.removeProperty(k),
  [DOM_CMD.REMOVE_ATTR]: (id, k) => managed(id)?.node?.removeAttribute?.(k),
  [DOM_CMD.SET_CSS]: (id, text) => {
    let node = stylesheets.get(id)
    if (!node) {
      node = document.createElement('style')
      node.setAttribute('data-mbt-css', id)
      stylesheets.set(id, node)
      document.head.appendChild(node)
    }
    node.textContent = text
  },
  [DOM_CMD.REMOVE_CSS]: id => {
    const node = stylesheets.get(id)
    node?.parentNode?.removeChild(node)
    stylesheets.delete(id)
  },
}
const apply = cmds => {
  for (const [type, ...content] of cmds) { domOps[type](...content) }
}
const applyDomBatch = data => {
  const cmds = data.map(d => typeof d === 'string' ? JSON.parse(d) : d)
  apply(cmds)
}
const triggerResult = (id, kind, extra = {}) => ({ ok: true, kind, id, ...extra })
const pointerEventFor = (cmd, name, pts = {}) => new (globalThis.PointerEvent ?? MouseEvent)(name, {
  bubbles: true,
  clientX: eventInt(pts.x ?? cmd.x),
  clientY: eventInt(pts.y ?? cmd.y),
  button: eventInt(cmd.button),
  buttons: eventInt(cmd.buttons ?? (pts.btns ?? 0)),
})
const pointerEventName = name => (
  name === 'down' ? 'pointerdown' :
    name === 'move' ? 'pointermove' :
      name === 'up' ? 'pointerup' : name
)
const triggerPointer = (id, node, cmd) => {
  const name = cmd.name || cmd.kind
  if (name === 'click') {
    if (typeof node.click === 'function') {
      node.click()
    } else {
      ['mousedown', 'mouseup', 'click'].forEach(event => {
        node.dispatchEvent(pointerEventFor(cmd, event))
      })
    }
  } else if (name === 'dblclick') {
    ['mousedown', 'mouseup', 'click', 'mousedown', 'mouseup', 'click', 'dblclick']
      .forEach(event => node.dispatchEvent(pointerEventFor(cmd, event)))
  } else {
    node.dispatchEvent(pointerEventFor(cmd, pointerEventName(name)))
  }
  return triggerResult(id, 'pointer', { name })
}
const rectCenter = rect => ({ x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 })
const triggerDrag = (id, node, targetId, cmd) => {
  const target = managed(targetId)
  if (!target) { throw Error('drag target not found') }
  const start = rectCenter(node.getBoundingClientRect())
  const end = rectCenter(target.node.getBoundingClientRect())
  node.dispatchEvent(pointerEventFor(cmd, 'pointerdown', { ...start, btns: 1 }))
  node.dispatchEvent(pointerEventFor(cmd, 'pointermove',
    { x: (start.x + end.x) / 2, y: (start.y + end.y) / 2, btns: 1 }))
  node.dispatchEvent(pointerEventFor(cmd, 'pointerup', { ...end, btns: 0 }))
  return triggerResult(id, 'drag_to', { target_id: target.id })
}
const triggerById = cmd => {
  const target = managed(cmd)
  if (!target) { throw Error('target not found') }
  const { id, node } = target
  switch (cmd.kind) {
    case 'pointer': case 'click': case 'dblclick':
      return triggerPointer(id, node, cmd)
    case 'focus':
      node.focus()
      return triggerResult(id, 'focus')
    case 'blur':
      node.blur()
      return triggerResult(id, 'blur')
    case 'scrollIntoView':
      node.scrollIntoView()
      return triggerResult(id, 'scrollIntoView')
    case 'input':
      node.value = cmd.text ?? ''
      node.dispatchEvent(new Event('input', { bubbles: true }))
      node.dispatchEvent(new Event('change', { bubbles: true }))
      return triggerResult(id, 'input')
    case 'key': {
      const name = cmd.key_event ?? 'press'
      const keyobj = {
        bubbles: true, key: cmd.key ?? '', code: cmd.code ?? '',
        ctrlKey: !!cmd.ctrl_key, shiftKey: !!cmd.shift_key,
        altKey: !!cmd.alt_key, metaKey: !!cmd.meta_key,
      }
      if (name === 'press') {
        node.dispatchEvent(new KeyboardEvent('keydown', keyobj))
        node.dispatchEvent(new KeyboardEvent('keyup', keyobj))
      } else {
        node.dispatchEvent(new KeyboardEvent(name, keyobj))
      }
      return triggerResult(id, 'key', { name })
    }
    case 'drag_to':
      return triggerDrag(id, node, cmd.target_id, cmd)
    default:
      throw Error(`unsupported trigger kind: ${cmd.kind}`)
  }
}
const triggerCommand = async (path, kind, value) => {
  if (typeof path !== 'string' || path === '') {
    throw Error('trigger path must be a string')
  }
  if (typeof kind !== 'string' || kind === '') {
    throw Error('trigger kind must be a string')
  }
  const id = await resolvePath(path)
  if (id == null) {
    throw Error(`trigger target not found: ${path}`)
  }
  if (kind === 'input') {
    return { id, kind, text: typeof value === 'string' ? value : '' }
  }
  if (kind === 'key') {
    if (typeof value === 'string') {
      return { id, kind, key: value }
    }
    return { id, kind, ...keyCommand(value) }
  }
  if (kind !== 'drag_to') {
    return { id, kind }
  }
  if (typeof value !== 'string' || value === '') {
    throw Error('trigger drag_to expects target path string')
  }
  const targetId = await resolvePath(value)
  if (targetId == null) {
    throw Error(`trigger target not found: ${value}`)
  }
  return { id, kind, target_id: targetId }
}
const requestHandlers = {
  query: data => queryById(data.query?.id, data.query?.kind ?? 'node', data.query?.value),
  trigger: data => triggerById(data.command),
  sync: () => ({ ok: true }),
}
const handleSocketRequest = data => Promise.resolve().then(() => {
  const handler = requestHandlers[data.action]
  if (!handler) { throw Error(`unsupported request action: ${data.action}`) }
  return handler(data)
})
  .then(result => {
    emitResponse(data.request_id, true, result)
  })
  .catch(error => {
    emitResponse(data.request_id, false, null, error.message)
  })
const messageHandlers = {
  [MSG.HELLO_ACK]: data => {
    resetManagedDom()
    updateReconnect(true)
    ensurePingLoop()
    sendPing()
    setStatus('connected')
  },
  [MSG.PONG]: data => {
    if (pingPending && data.seq === pingPending.seq) {
      latencyMs = performance.now() - pingPending.sentAt
      pingPending = null
    }
  },
  [MSG.RESPONSE]: data => {
    settlePendingRequest(data.request_id, !!data.ok, data.result, data.error)
  },
  [MSG.REJECTED]: data => {
    updateReconnect(false)
    rejectPendingRequests(Error(data.reason ?? 'bridge rejected'))
    resetPing()
    if (reconnectTimer != null) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
    setStatus('rejected', data.reason ?? null)
    ws?.close()
  },
  [MSG.REQUEST]: data => {
    handleSocketRequest(data)
  },
}
const handleSocketMessage = data => {
  if (Array.isArray(data)) {
    applyDomBatch(data)
  } else {
    messageHandlers[data.type]?.(data)
  }
}
const setupSocket = socket => {
  socket.onmessage = event => {
    try {
      handleSocketMessage(JSON.parse(event.data))
    } catch (e) {
      console.error('Parse error', e)
    }
  }
}
const bridge = { // 正式 API
  status: () => getStatus(),
  setStatusListener: listener => {
    statusListener = typeof listener === 'function' ? listener : null
  },
  query: async (path, kind = 'node', value = undefined) => {
    const id = await resolvePath(path)
    return id == null ? null : queryById(id, kind, value)
  },
  trigger: async (path, kind, value = undefined) =>
    triggerById(await triggerCommand(path, kind, value)),
  command: async (cmd, arg = '') => {
    const result = await sendRequest('command', { cmd, arg })
    return typeof result === 'string' ? result : ''
  },
  reset: () => {
    updateReconnect(false)
    rejectReason = null
    if (reconnectTimer != null) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
    const oldWs = ws
    if (oldWs) {
      oldWs.onopen = null
      oldWs.onmessage = null
      oldWs.onclose = null
      oldWs.onerror = null
      oldWs.close?.()
    }
    ws = null
    rejectPendingRequests(Error('bridge reset'))
    resetManagedDom()
    resetPing()
    setStatus('idle')
  },
  init: async () => {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
      return
    }
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const host = window.location.host
    const url = `${protocol}//${host}`

    console.log(`Connecting to Core: ${url}`)
    try {
      updateReconnect(true)
      setStatus('connecting')
      const socket = new WebSocket(url)
      ws = socket
      socket.onopen = () => {
        setupSocket(socket)
        socket.send(JSON.stringify({
          type: MSG.HELLO,
          role: 'browser',
          user_agent: navigator.userAgent,
          session_id: ensureSessionId(),
        }))
      }
      socket.onerror = e => console.error('WS Connection error', e)
      socket.onclose = () => {
        ws = null
        rejectPendingRequests(Error('bridge disconnected'))
        if (bridgeState === 'rejected') {
          return
        }
        setStatus('disconnected')
        resetPing()
        reconnectLater()
      }
    } catch (e) {
      console.error('Failed to initiate WS', e)
      reconnectLater()
    }
  },
  bridgeTest: { // bridge 白盒测试专用 API （普通测试禁用）
    DOM_CMD, apply, queryById, triggerById, keyCommand,
    connectFake: onSend => {
      bridge.reset()
      updateReconnect(false)
      ws = {
        readyState: 1,
        send(data) {
          let parsed = data
          try { parsed = JSON.parse(data) } catch { }
          onSend?.(parsed)
        },
        close() { },
      }
      setStatus('connected')
      return bridge.status()
    },
  },
}
globalThis.mbt_bridge = bridge
console.log('Bridge (Universal) initialized.')

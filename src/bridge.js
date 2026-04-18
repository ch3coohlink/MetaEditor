"use strict"
const DOM_CMD = Object.freeze({
  CREATE: 0,
  INSERT: 1,
  REMOVE: 2,
  ATTR: 3,
  STYLE: 4,
  PROP: 5,
  LISTENER: 6,
  POINTER: 7,
})
const DOM_ROOT = Object.freeze({
  HEAD: 1,
  BODY: 2,
})
const NS = Object.freeze({
  0: 'http://www.w3.org/1999/xhtml',
  1: 'http://www.w3.org/2000/svg',
  2: 'http://www.w3.org/1998/Math/MathML',
})
const REQ = Object.freeze({
  HELLO: 'hello',
  QUERY: 'query',
  DISPATCH: 'dispatch',
  TRIGGER: 'trigger',
  CLI: 'cli',
  PING: 'ping',
})
const nodes = new Map()
let pingPending = null
let pingTimer = null
let nodeIds = new WeakMap()
let nextPacketId = 1
const pendingRequests = new Map()
const sessionKey = 'mbt_bridge_session_id'
let ws = null
let reconnectTimer = null
let shouldReconnect = true
let bridgeState = 'idle'
let rejectReason = null
let sessionIdValue = null
const isElement = node => node && node.nodeType === Node.ELEMENT_NODE
const isText = node => node && node.nodeType === Node.TEXT_NODE
const randomId = () => {
  if (globalThis.crypto?.randomUUID) { return globalThis.crypto.randomUUID() }
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`
}
const getNodeId = node => {
  if (!node) { return null }
  if (nodeIds.has(node)) { return nodeIds.get(node) }
  return null
}
const removeNodeTree = node => {
  if (!node) { return }
  for (const child of Array.from(node.childNodes ?? [])) { removeNodeTree(child) }
  const id = getNodeId(node)
  if (id != null) { nodes.delete(id) }
}
const eventInt = v => (typeof v === 'number' && Number.isFinite(v)) ? Math.round(v) : 0
const packetId = () => { const id = nextPacketId; nextPacketId += 1; return id }
const resetPing = () => { pingPending = null }
const sendPacket = packet => {
  if (!ws || ws.readyState !== 1) { throw Error('bridge is not connected') }
  ws.send(JSON.stringify(packet))
}
const sendPing = () => {
  if (!ws || ws.readyState !== 1 || pingPending) { return }
  const id = packetId()
  pingPending = { id, sentAt: performance.now() }
  sendPacket({ id, type: REQ.PING })
}
const ensurePingLoop = () => {
  if (pingTimer != null) { return }
  pingTimer = setInterval(() => { sendPing() }, 2000)
}
const settlePendingRequest = (id, ok, result, error) => {
  const pending = pendingRequests.get(id)
  if (!pending) { return false }
  pendingRequests.delete(id)
  if (ok) { pending.resolve(result) }
  else { pending.reject(Error(error ?? 'bridge request failed')) }
  return true
}
const rejectPendingRequests = error => {
  for (const [id, pending] of pendingRequests.entries()) {
    pendingRequests.delete(id)
    pending.reject(error)
  }
}
const resetManagedDom = () => {
  for (const node of nodes.values()) {
    if (node && node.parentNode) { node.parentNode.removeChild(node) }
  }
  document.body.replaceChildren()
  nodes.clear()
  nodeIds = new WeakMap()
}
const managed = target => {
  const id = target?.id != null ? Number(target.id) : Number(target)
  const node = Number.isFinite(id) ? nodes.get(id) ?? null : null
  return node ? { id, node } : null
}
const rootNode = id => {
  const n = Number(id)
  if (n === DOM_ROOT.BODY) { return document.body }
  if (n === DOM_ROOT.HEAD) { return document.head }
  return managed(n)?.node ?? null
}
const eventNameOfKind = kind => typeof kind === 'string' ? kind.toLowerCase() : ''
const listenerKey = (id, kind) => `${id}:${kind}`
const capturePointer = (node, pointerId) => {
  if (pointerId == null || !isElement(node) || !node.setPointerCapture) { return }
  try {
    node.setPointerCapture(pointerId)
  } catch {}
}
const releasePointer = (node, pointerId) => {
  if (pointerId == null || !isElement(node) || !node.releasePointerCapture) { return }
  try {
    if (!node.hasPointerCapture || node.hasPointerCapture(pointerId)) {
      node.releasePointerCapture(pointerId)
    }
  } catch {}
}
const listenerStore = node => {
  if (!node.__mbt_listeners) { node.__mbt_listeners = {} }
  return node.__mbt_listeners
}
const removeListenerCmd = (node, payload = {}) => {
  const kind = typeof payload.kind === 'string' ? payload.kind : ''
  const id = typeof payload.id === 'number' ? payload.id : 0
  const store = node?.__mbt_listeners
  const key = listenerKey(id, kind)
  if (!kind || !store || !store[key]) { return }
  const prev = store[key]
  node.removeEventListener(eventNameOfKind(kind), prev.handler, prev.options)
  delete store[key]
}
const setListenerCmd = (node, payload = {}) => {
  const kind = typeof payload.kind === 'string' ? payload.kind : ''
  const cfg = payload.cfg && typeof payload.cfg === 'object' ? payload.cfg : {}
  const id = typeof payload.id === 'number' ? payload.id : 0
  const bind = payload.bind !== false
  const name = eventNameOfKind(kind)
  if (!kind || !name) { return }
  const store = listenerStore(node)
  const key = listenerKey(id, kind)
  if (store[key]) {
    node.removeEventListener(name, store[key].handler, store[key].options)
    delete store[key]
  }
  if (!bind) { return }
  const options = { capture: !!cfg.capture }
  const handler = async e => {
    if (cfg.stop) { e.stopPropagation() }
    if (cfg.prevent) { e.preventDefault() }
    const event = eventFromName(name, e, node)
    if (!event || id <= 0) { return }
    try {
      await sendRequest(REQ.TRIGGER, { node: id, event })
    } catch (error) {
      console.error('Trigger error', error)
    }
  }
  store[key] = { handler, options }
  node.addEventListener(name, handler, options)
}
const setPointerCmd = (node, payload = {}) => {
  const pointerId = typeof payload.pointer_id === 'number' ? payload.pointer_id : null
  if (payload.capture) { capturePointer(node, pointerId) }
  else { releasePointer(node, pointerId) }
}
const pointOf = id => {
  const node = managed(id)?.node
  if (!isElement(node)) { return null }
  node.scrollIntoView({ block: 'center', inline: 'center' })
  const rect = node.getBoundingClientRect()
  if (!(rect.width > 0 && rect.height > 0)) { return null }
  return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 }
}
const eventFromName = (name, event, node) => {
  switch (name) {
    case 'click': return baseDispatch('Click')
    case 'focus': return baseDispatch('Focus')
    case 'blur': return baseDispatch('Blur')
    case 'change': return ['Input', { kind: 'Change', value: node?.value ?? '' }]
    case 'input': return ['Input', { kind: 'Input', value: node?.value ?? '' }]
    case 'pointerdown': return mouseDispatch('PointerDown', event)
    case 'pointerup': return mouseDispatch('PointerUp', event)
    case 'pointermove': return mouseDispatch('PointerMove', event)
    case 'pointercancel': return mouseDispatch('PointerCancel', event)
    case 'keydown': return keyDispatch('KeyDown', event)
    case 'keyup': return keyDispatch('KeyUp', event)
    default: return null
  }
}
const encodeQuery = (kind, value) => {
  if (kind === 'node' || kind === 'Node') { return 'Node' }
  if (kind === 'text' || kind === 'Text') { return 'Text' }
  if (kind === 'attr' || kind === 'Attr') {
    return ['Attr', typeof value === 'string' ? value : '']
  }
  if (kind === 'prop' || kind === 'Prop') {
    return ['Prop', typeof value === 'string' ? value : '']
  }
  if (kind === 'style' || kind === 'Style') {
    return ['Style', typeof value === 'string' ? value : '']
  }
  return kind
}
const getStatus = () => ({ state: bridgeState, reason: rejectReason ?? undefined, })
const setStatus = (state, reason = null) => { bridgeState = state, rejectReason = reason }
const sendRequest = (type, payload = {}) => {
  if (!ws || ws.readyState !== 1) { return Promise.reject(Error('bridge is not connected')) }
  const id = packetId()
  return new Promise((resolve, reject) => {
    pendingRequests.set(id, { resolve, reject })
    try { sendPacket({ id, type, ...payload }) } catch (error) {
      pendingRequests.delete(id); reject(error)
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
const domOps = {
  [DOM_CMD.CREATE]: (id, tag, value = null, ns = 0) => {
    const nsValue = typeof ns === 'number' ? (NS[ns] ?? NS[0]) : ns
    const el = tag === '' ? document.createTextNode('') :
      nsValue === NS[0] ? document.createElement(tag) :
        document.createElementNS(nsValue, tag)
    if (value != null) { el.textContent = value }
    nodes.set(id, el)
    nodeIds.set(el, id)
  },
  [DOM_CMD.ATTR]: (id, k, v) => {
    const node = managed(id)?.node
    if (!node?.setAttribute) { return }
    if (v == null) { node.removeAttribute(k) } else { node.setAttribute(k, v) }
  },
  [DOM_CMD.INSERT]: (pid, cid, rid = 0, after = true) => {
    const parent = rootNode(pid)
    const child = managed(cid)?.node
    const ref = rootNode(rid)
    if (!(parent && child)) { return }
    if (!ref || ref.parentNode !== parent) { parent.appendChild(child); return }
    const anchor = after ? ref.nextSibling : ref
    parent.insertBefore(child, anchor ?? null)
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
  [DOM_CMD.STYLE]: (id, k, v) => {
    const style = managed(id)?.node?.style
    if (!style) { return }
    if (v == null) {
      style.removeProperty(k)
    } else {
      style.setProperty(k, v)
    }
  },
  [DOM_CMD.PROP]: (id, k, v) => {
    const node = managed(id)?.node
    if (!node) { return }
    node[k] = v
  },
  [DOM_CMD.LISTENER]: payload => {
    const node = managed(payload?.id)?.node
    if (!node) { return }
    if (payload?.bind === false) { removeListenerCmd(node, payload); return }
    setListenerCmd(node, payload)
  },
  [DOM_CMD.POINTER]: payload => {
    const node = managed(payload?.id)?.node
    if (!node) { return }
    setPointerCmd(node, payload)
  },
}
const apply = cmds => {
  for (const [type, ...content] of cmds) { domOps[type](...content) }
}
const modkey = value => ({
  ctrl: !!value?.ctrlKey, shift: !!value?.shiftKey,
  alt: !!value?.altKey, meta: !!value?.metaKey,
})
const baseDispatch = kind => ['Base', { kind }]
const inputDispatch = value => ['Input', { kind: 'Input', value: typeof value === 'string' ? value : '' }]
const mouseDispatch = (kind, value = {}) => ['Mouse', {
  kind, mod: modkey(value), x: eventInt(value?.x), y: eventInt(value?.y),
  button: eventInt(value?.button),
  buttons: eventInt(value?.buttons),
  pointer_id: eventInt(value?.pointerId),
}]
const keyDispatch = (kind, value = {}) => ['Key', {
  kind,
  mod: modkey(value),
  key: value?.key ?? '',
  code: value?.code ?? '',
}]
const dispatchPayload = (path, kind, value) => {
  if (typeof path !== 'string' || path === '') { throw Error('dispatch path must be a string') }
  switch (kind) {
    case 'click': return { path, event: baseDispatch('Click') }
    case 'focus': return { path, event: baseDispatch('Focus') }
    case 'blur': return { path, event: baseDispatch('Blur') }
    case 'input': return { path, event: inputDispatch(value) }
    case 'pointerdown': return { path, event: mouseDispatch('PointerDown', value) }
    case 'pointerup': return { path, event: mouseDispatch('PointerUp', value) }
    case 'pointermove': return { path, event: mouseDispatch('PointerMove', value) }
    case 'key': {
      if (typeof value === 'string') {
        return { path, event: keyDispatch('KeyDown', { key: value }) }
      }
      return { path, event: keyDispatch(value?.event === 'keyup' ? 'KeyUp' : 'KeyDown', value) }
    }
    default:
      throw Error(`unsupported dispatch kind: ${kind}`)
  }
}
const packetBody = body => {
  if (typeof body === 'string') { return { tag: body, value: undefined } }
  if (Array.isArray(body) && body.length === 2 && typeof body[0] === 'string') {
    return { tag: body[0], value: body[1] }
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) { return null }
  const keys = Object.keys(body)
  if (keys.length !== 1) { return null }
  return { tag: keys[0], value: body[keys[0]] }
}
const onHelloAck = () => {
  resetManagedDom()
  updateReconnect(true)
  ensurePingLoop()
  sendPing()
  setStatus('connected')
}
const handlePacket = packet => {
  const body = packetBody(packet?.body)
  if (!body) { return }
  switch (body.tag) {
    case 'HelloAck': return onHelloAck()
    case 'Pong':
      if (pingPending && pingPending.id === packet.id) { pingPending = null }
      return
    case 'Query':
      settlePendingRequest(packet.id, true, body.value, null)
      return
    case 'Cli':
      settlePendingRequest(packet.id, true, body.value, null)
      return
    case 'Ok':
      settlePendingRequest(packet.id, true, true, null)
      return
    case 'Err': {
      const msg = typeof body.value === 'string' ? body.value : 'request failed'
      if (settlePendingRequest(packet.id, false, null, msg)) { return }
      updateReconnect(false)
      rejectPendingRequests(Error(msg))
      resetPing()
      if (reconnectTimer != null) { clearTimeout(reconnectTimer); reconnectTimer = null }
      setStatus('rejected', msg)
      ws?.close()
      return
    }
  }
}
const handleMessage = data => {
  if (Array.isArray(data)) {
    apply(data)
    return
  }
  handlePacket(data)
}
const setupSocket = socket => {
  socket.onmessage = event => {
    try { handleMessage(JSON.parse(event.data)) } catch (e) { console.error('Parse error', e) }
  }
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
globalThis.mbt_bridge = { // 正式 API
  status: () => getStatus(),
  query: async (path, kind = 'node', value = undefined) =>
    sendRequest(REQ.QUERY, { path, query: encodeQuery(kind, value) }),
  dispatch: async (path, kind, value = undefined) => {
    if (kind === 'key' && value?.event === 'press') {
      await sendRequest(REQ.DISPATCH, { path, event: keyDispatch('KeyDown', value) })
      return sendRequest(REQ.DISPATCH, { path, event: keyDispatch('KeyUp', value) })
    }
    return sendRequest(REQ.DISPATCH, dispatchPayload(path, kind, value))
  },
  cli: async (cmd, arg = '') => {
    const line = arg === '' ? cmd : `${cmd} ${arg}`
    const out = await sendRequest(REQ.CLI, { cmd: line })
    return typeof out === 'string' ? out : ''
  },
  reset: async (root = '') => {
    const cmd = root === '' ? 'reset' : `reset ${root}`
    resetManagedDom()
    resetPing()
    rejectReason = null
    await sendRequest(REQ.CLI, { cmd })
  },
  init: async () => {
    if (ws && (
      ws.readyState === WebSocket.OPEN ||
      ws.readyState === WebSocket.CONNECTING)) { return }
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const host = window.location.host
    const url = `${protocol}//${host}/_meta/ws`
    try {
      updateReconnect(true)
      setStatus('connecting')
      const socket = new WebSocket(url)
      ws = socket
      socket.onopen = () => {
        setupSocket(socket)
        sendPacket({ id: packetId(), type: REQ.HELLO, role: 'Browser', session: ensureSessionId() })
      }
      socket.onerror = e => console.error('WS Connection error', e)
      socket.onclose = () => {
        ws = null
        rejectPendingRequests(Error('bridge disconnected'))
        if (bridgeState === 'rejected') { return }
        setStatus('disconnected')
        resetPing()
        reconnectLater()
      }
    } catch (e) {
      console.error('Failed to initiate WS', e)
      reconnectLater()
    }
  },
}
globalThis.__mbt_bridge_internal = { pointOf }

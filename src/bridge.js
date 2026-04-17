"use strict"
const DOM_CMD = Object.freeze({
  CREATE: 0,
  INSERT: 1,
  REMOVE: 2,
  ATTR: 3,
  STYLE: 4,
  PROP: 5,
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
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID()
  }
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
  if (id != null) {
    nodes.delete(id)
  }
}
const eventInt = v => (typeof v === 'number' && Number.isFinite(v)) ? Math.round(v) : 0
const packetId = () => {
  const id = nextPacketId
  nextPacketId += 1
  return id
}
const resetPing = () => {
  pingPending = null
}
const sendPacket = packet => {
  if (!ws || ws.readyState !== 1) {
    throw Error('bridge is not connected')
  }
  ws.send(JSON.stringify(packet))
}
const sendPing = () => {
  if (!ws || ws.readyState !== 1 || pingPending) {
    return
  }
  const id = packetId()
  pingPending = { id, sentAt: performance.now() }
  sendPacket({ id, type: REQ.PING })
}
const ensurePingLoop = () => {
  if (pingTimer != null) {
    return
  }
  pingTimer = setInterval(() => {
    sendPing()
  }, 2000)
}
const settlePendingRequest = (id, ok, result, error) => {
  const pending = pendingRequests.get(id)
  if (!pending) {
    return false
  }
  pendingRequests.delete(id)
  if (ok) {
    pending.resolve(result)
  } else {
    pending.reject(Error(error ?? 'bridge request failed'))
  }
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
    if (node && node.parentNode) {
      node.parentNode.removeChild(node)
    }
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
const eventPropSpec = raw => {
  const pair = Array.isArray(raw) ? raw : []
  const cfg = pair[1] && typeof pair[1] === 'object' && !Array.isArray(pair[1]) ? pair[1] : {}
  return {
    prevent: !!cfg?.prevent,
    stop: !!cfg?.stop,
  }
}
const encodeQuery = (kind, value) => {
  if (kind === 'node' || kind === 'Node') {
    return 'Node'
  }
  if (kind === 'text' || kind === 'Text') {
    return 'Text'
  }
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
const getStatus = () => ({
  state: bridgeState,
  reason: rejectReason ?? undefined,
})
const setStatus = (state, reason = null) => {
  bridgeState = state
  rejectReason = reason
}
const sendRequest = (type, payload = {}) => {
  if (!ws || ws.readyState !== 1) {
    return Promise.reject(Error('bridge is not connected'))
  }
  const id = packetId()
  return new Promise((resolve, reject) => {
    pendingRequests.set(id, { resolve, reject })
    try {
      sendPacket({ id, type, ...payload })
    } catch (error) {
      pendingRequests.delete(id)
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
    if (v == null) {
      node.removeAttribute(k)
    } else {
      node.setAttribute(k, v)
    }
  },
  [DOM_CMD.INSERT]: (pid, cid, rid = 0, after = true) => {
    const parent = rootNode(pid)
    const child = managed(cid)?.node
    const ref = rootNode(rid)
    if (!(parent && child)) { return }
    if (!ref || ref.parentNode !== parent) {
      parent.appendChild(child)
      return
    }
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
    if (typeof k === 'string' && k.startsWith('on')) {
      const spec = eventPropSpec(v)
      node[k] = e => {
        if (spec.stop) {
          e.stopPropagation()
        }
        if (spec.prevent) {
          e.preventDefault()
        }
      }
      return
    }
    node[k] = v
  },
}
const apply = cmds => {
  for (const [type, ...content] of cmds) { domOps[type](...content) }
}
const modkey = value => ({
  ctrl: !!value?.ctrlKey,
  shift: !!value?.shiftKey,
  alt: !!value?.altKey,
  meta: !!value?.metaKey,
})
const baseDispatch = kind => ['Base', { kind }]
const inputDispatch = value => ['Input', { kind: 'Input', value: typeof value === 'string' ? value : '' }]
const mouseDispatch = (kind, value = {}) => ['Mouse', {
  kind,
  mod: modkey(value),
  x: eventInt(value?.x),
  y: eventInt(value?.y),
  button: eventInt(value?.button),
  buttons: eventInt(value?.buttons),
}]
const keyDispatch = (kind, value = {}) => ['Key', {
  kind,
  mod: modkey(value),
  key: value?.key ?? '',
  code: value?.code ?? '',
}]
const dispatchPayload = (path, kind, value) => {
  if (typeof path !== 'string' || path === '') {
    throw Error('dispatch path must be a string')
  }
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
  if (typeof body === 'string') {
    return { tag: body, value: undefined }
  }
  if (Array.isArray(body) && body.length === 2 && typeof body[0] === 'string') {
    return { tag: body[0], value: body[1] }
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return null
  }
  const keys = Object.keys(body)
  if (keys.length !== 1) {
    return null
  }
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
      if (reconnectTimer != null) {
        clearTimeout(reconnectTimer)
        reconnectTimer = null
      }
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
    try {
      handleMessage(JSON.parse(event.data))
    } catch (e) {
      console.error('Parse error', e)
    }
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
const bridge = { // 正式 API
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
  reset: (root = '') => {
    const cmd = root === '' ? 'reset' : `reset ${root}`
    sendPacket({ id: packetId(), type: REQ.CLI, cmd })
    resetManagedDom()
    resetPing()
    rejectReason = null
  },
  init: async () => {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
      return
    }
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
}
globalThis.mbt_bridge = bridge

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
const getManagedNode = id => {
  const nodeId = Number(id)
  return Number.isFinite(nodeId) ? nodes.get(nodeId) ?? null : null
}
const snapshotById = id => {
  const nodeId = Number(id)
  const node = getManagedNode(nodeId)
  return node ? snapshotNode(nodeId, node) : null
}
const textById = id => {
  const nodeId = Number(id)
  const node = getManagedNode(nodeId)
  return node ? { id: nodeId, text: node.textContent ?? '' } : null
}
const resolveInternalNode = target => {
  const id = target?.id != null ? Number(target.id) : null
  const node = getManagedNode(id)
  return node && id != null ? { id, node } : null
}
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
const queryPathId = async path => {
  if (typeof path !== 'string') {
    throw Error('query path must be a string')
  }
  const result = await sendRequest('query', { query: { kind: 'path', path } })
  const id = Number(result?.id)
  return Number.isFinite(id) ? id : null
}
const queryPathSnapshot = async path => {
  const id = await queryPathId(path)
  return id == null ? null : snapshotById(id)
}
const queryPathNode = async path => {
  const id = await queryPathId(path)
  return id == null ? null : getManagedNode(id)
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
const createNode = (id, tag, ns) => {
  const el = tag === '' ? document.createTextNode('') :
    ns === 'http://www.w3.org/1999/xhtml' ? document.createElement(tag) :
      document.createElementNS(ns, tag)
  nodes.set(id, el)
  nodeIds.set(el, id)
}
const setText = (id, text) => {
  const node = getManagedNode(id)
  if (node) { node.textContent = text }
}
const setAttr = (id, k, v) => {
  const node = getManagedNode(id)
  if (node && node.setAttribute) { node.setAttribute(k, v) }
}
const appendNode = (pid, cid) => {
  const parent = Number(pid) === 0 ? document.body : getManagedNode(pid)
  const child = getManagedNode(cid)
  if (parent && child) { parent.appendChild(child) }
}
const insertNodeBefore = (pid, cid, rid) => {
  const parent = Number(pid) === 0 ? document.body : getManagedNode(pid)
  const child = getManagedNode(cid)
  const ref = getManagedNode(rid)
  if (parent && child) {
    if (ref) { parent.insertBefore(child, ref) }
    else { parent.appendChild(child) }
  }
}
const removeNode = id => {
  const node = getManagedNode(id)
  if (node) {
    removeNodeTree(node)
    if (node.parentNode) { node.parentNode.removeChild(node) }
  } else {
    nodes.delete(Number(id))
  }
}
const setNodeStyle = (id, k, v) => {
  const node = getManagedNode(id)
  if (node && node.style) { node.style.setProperty(k, v) }
}
const removeNodeStyle = (id, k) => {
  const node = getManagedNode(id)
  if (node && node.style) { node.style.removeProperty(k) }
}
const removeNodeAttr = (id, k) => {
  const node = getManagedNode(id)
  if (node && node.removeAttribute) { node.removeAttribute(k) }
}
const setStylesheet = (id, text) => {
  let node = stylesheets.get(id)
  if (!node) {
    node = document.createElement('style')
    node.setAttribute('data-mbt-css', id)
    stylesheets.set(id, node)
    document.head.appendChild(node)
  }
  node.textContent = text
}
const removeStylesheet = id => {
  const node = stylesheets.get(id)
  if (node && node.parentNode) { node.parentNode.removeChild(node) }
  stylesheets.delete(id)
}
const runHostCommand = (id, cmd) => {
  const node = getManagedNode(id)
  if (node && typeof node[cmd] === 'function') { node[cmd]() }
}
const applyDomCommands = cmds => {
  for (const cmd of cmds) {
    switch (cmd[0]) {
      case DOM_CMD.CREATE: createNode(cmd[1], cmd[2], cmd[3]); break
      case DOM_CMD.TEXT: setText(cmd[1], cmd[2]); break
      case DOM_CMD.ATTR: setAttr(cmd[1], cmd[2], cmd[3]); break
      case DOM_CMD.APPEND: appendNode(cmd[1], cmd[2]); break
      case DOM_CMD.REMOVE: removeNode(cmd[1]); break
      case DOM_CMD.LISTEN: listen(cmd[1], cmd[2]); break
      case DOM_CMD.INSERT_BEFORE: insertNodeBefore(cmd[1], cmd[2], cmd[3]); break
      case DOM_CMD.SET_STYLE: setNodeStyle(cmd[1], cmd[2], cmd[3]); break
      case DOM_CMD.REMOVE_STYLE: removeNodeStyle(cmd[1], cmd[2]); break
      case DOM_CMD.REMOVE_ATTR: removeNodeAttr(cmd[1], cmd[2]); break
      case DOM_CMD.HOST_CMD: runHostCommand(cmd[1], cmd[2]); break
      case DOM_CMD.SET_CSS: setStylesheet(cmd[1], cmd[2]); break
      case DOM_CMD.REMOVE_CSS: removeStylesheet(cmd[1]); break
    }
  }
}
const applyDomBatch = data => {
  const cmds = data.map(d => typeof d === 'string' ? JSON.parse(d) : d)
  applyDomCommands(cmds)
}
const queryRequest = query => {
  if (query?.kind === 'node') {
    return snapshotById(query.id)
  }
  if (query?.kind === 'text') {
    return textById(query.id)
  }
  throw Error(`unsupported request query kind: ${query?.kind}`)
}
const finishTrigger = (id, kind, extra = {}) => ({
  ok: true,
  kind,
  ...extra,
  target: snapshotById(id),
})
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
    node.click()
  } else if (name === 'dblclick') {
    ['mousedown', 'mouseup', 'click', 'mousedown', 'mouseup', 'click', 'dblclick']
      .forEach(event => node.dispatchEvent(pointerEventFor(cmd, event)))
  } else {
    node.dispatchEvent(pointerEventFor(cmd, pointerEventName(name)))
  }
  return finishTrigger(id, 'pointer', { name })
}
const triggerFocus = (id, node) => {
  node.focus()
  return finishTrigger(id, 'focus')
}
const triggerInput = (id, node, cmd) => {
  node.value = cmd.text ?? ''
  node.dispatchEvent(new Event('input', { bubbles: true }))
  node.dispatchEvent(new Event('change', { bubbles: true }))
  return finishTrigger(id, 'input')
}
const triggerKey = (id, node, cmd) => {
  const name = cmd.name ?? 'keydown'
  node.dispatchEvent(new KeyboardEvent(name, {
    bubbles: true,
    key: cmd.key ?? '',
    code: cmd.code ?? '',
    ctrlKey: !!cmd.ctrlKey,
    shiftKey: !!cmd.shiftKey,
    altKey: !!cmd.altKey,
    metaKey: !!cmd.metaKey,
  }))
  return finishTrigger(id, 'key', { name })
}
const triggerDrag = (id, node, cmd) => {
  const points = Array.isArray(cmd.points) ? cmd.points : []
  if (points.length < 2) { throw Error('drag expects at least two points') }
  node.dispatchEvent(pointerEventFor(cmd, 'pointerdown', { ...points[0], btns: 1 }))
  points.slice(1, -1).forEach(point => {
    node.dispatchEvent(pointerEventFor(cmd, 'pointermove', { ...point, btns: 1 }))
  })
  node.dispatchEvent(pointerEventFor(cmd, 'pointerup', {
    ...points[points.length - 1],
    btns: 0,
  }))
  return finishTrigger(id, 'drag')
}
const triggerRequest = cmd => {
  const target = resolveInternalNode(cmd)
  if (!target) { throw Error('target not found') }
  const { id, node } = target
  switch (cmd.kind) {
    case 'pointer':
    case 'click':
    case 'dblclick':
      return triggerPointer(id, node, cmd)
    case 'focus':
      return triggerFocus(id, node)
    case 'input':
      return triggerInput(id, node, cmd)
    case 'key':
      return triggerKey(id, node, cmd)
    case 'drag':
      return triggerDrag(id, node, cmd)
    default:
      throw Error(`unsupported trigger kind: ${cmd.kind}`)
  }
}
const handleSocketRequest = data => Promise.resolve()
  .then(() => {
    if (data.action === 'query') {
      return queryRequest(data.query)
    }
    if (data.action === 'trigger') {
      return triggerRequest(data.command)
    }
    if (data.action === 'sync') {
      return { ok: true }
    }
    throw Error(`unsupported request action: ${data.action}`)
  })
  .then(result => {
    emitResponse(data.request_id, true, result)
  })
  .catch(error => {
    emitResponse(data.request_id, false, null, error.message)
  })
const handleSocketMessage = data => {
  if (Array.isArray(data)) {
    applyDomBatch(data)
    return
  }
  if (data.type === MSG.HELLO_ACK) {
    resetManagedDom()
    updateReconnect(true)
    ensurePingLoop()
    sendPing()
    setStatus('connected')
    return
  }
  if (data.type === MSG.PONG) {
    if (pingPending && data.seq === pingPending.seq) {
      latencyMs = performance.now() - pingPending.sentAt
      pingPending = null
    }
    return
  }
  if (data.type === MSG.RESPONSE) {
    settlePendingRequest(data.request_id, !!data.ok, data.result, data.error)
    return
  }
  if (data.type === MSG.REJECTED) {
    updateReconnect(false)
    rejectPendingRequests(Error(data.reason ?? 'bridge rejected'))
    resetPing()
    if (reconnectTimer != null) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
    setStatus('rejected', data.reason ?? null)
    ws?.close()
    return
  }
  if (data.type === MSG.REQUEST) {
    handleSocketRequest(data)
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
const listen = (id, event) => {
  const node = getManagedNode(id)
  if (!node) { return }
  const evt = event.startsWith('on') ? event.slice(2) : event
  const wantsData = evt.startsWith('key') || evt.startsWith('pointer') || evt.startsWith('mouse')
  node.addEventListener(evt, e => {
    if (evt === 'dblclick') {
      e.preventDefault()
    }
    if (ws && ws.readyState === 1) {
      if (wantsData) {
        sendEvent({ type: 'event_data', id, event, data: serializeEventData(e) })
      } else {
        sendEvent({ type: 'event', id, event })
      }
    }
  })
}

const bridge = {
  // 正式 API
  status: () => getStatus(),
  setStatusListener: listener => {
    statusListener = typeof listener === 'function' ? listener : null
  },
  query: async path => {
    return queryPathSnapshot(path)
  },
  queryNode: async path => {
    return queryPathNode(path)
  },
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
  // 测试 API
  test: {
    DOM_CMD,
    apply: applyDomCommands,
    snapshot: snapshotById,
    node: getManagedNode,
    connectFake: onSend => {
      bridge.reset()
      updateReconnect(false)
      ws = {
        readyState: 1,
        send(data) {
          let parsed = data
          try {
            parsed = JSON.parse(data)
          } catch {}
          onSend?.(parsed)
        },
        close() {},
      }
      setStatus('connected')
      return bridge.status()
    },
  },
}
globalThis.mbt_bridge = bridge
console.log('Bridge (Universal) initialized.')

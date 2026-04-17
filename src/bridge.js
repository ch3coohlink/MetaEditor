"use strict"
const DOM_CMD = Object.freeze({
  CREATE: 0,
  INSERT: 1,
  REMOVE: 2,
  ATTR: 3,
  STYLE: 4,
  PROP: 5,
  LISTEN: 6,
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
  PING: 'ping',
})
const nodes = new Map()
const listeners = new Map()
let pingPending = null
let pingTimer = null
let latencyMs = null
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
  if (id != null) {
    clearListeners(id)
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
  latencyMs = null
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
  for (const id of listeners.keys()) { clearListeners(id) }
  for (const node of nodes.values()) {
    if (node && node.parentNode) {
      node.parentNode.removeChild(node)
    }
  }
  document.body.replaceChildren()
  nodes.clear()
  listeners.clear()
  nodeIds = new WeakMap()
}
const managed = target => {
  const id = target?.id != null ? Number(target.id) : Number(target)
  const node = Number.isFinite(id) ? nodes.get(id) ?? null : null
  return node ? { id, node } : null
}
const rootNode = id => {
  const n = Number(id)
  if (n === DOM_ROOT.BODY || n === DOM_ROOT.BODY) { return document.body }
  if (n === DOM_ROOT.HEAD || n === DOM_ROOT.HEAD) { return document.head }
  return managed(n)?.node ?? null
}
const clearListeners = id => {
  const slots = listeners.get(id)
  if (!slots) { return }
  for (const { event, handler, capture } of slots.values()) {
    managed(id)?.node?.removeEventListener?.(event, handler, capture)
  }
  listeners.delete(id)
}
const boolOr = (value, fallback) => typeof value === 'boolean' ? value : fallback
const listenerSpec = raw => {
  const event = typeof raw?.event === 'string' ? raw.event : String(raw ?? '')
  return {
    event,
    capture: !!raw?.capture,
    passive: !!raw?.passive,
    prevent: !!raw?.prevent,
    stop: !!raw?.stop,
    policies: Array.isArray(raw?.policies) ? raw.policies : [],
  }
}
const policyMatches = (policy, e) => {
  if (policy?.key != null && policy.key !== (e?.key ?? '')) { return false }
  if (policy?.code != null && policy.code !== (e?.code ?? '')) { return false }
  if (policy?.ctrl != null && !!policy.ctrl !== !!e?.ctrlKey) { return false }
  if (policy?.shift != null && !!policy.shift !== !!e?.shiftKey) { return false }
  if (policy?.alt != null && !!policy.alt !== !!e?.altKey) { return false }
  if (policy?.meta != null && !!policy.meta !== !!e?.metaKey) { return false }
  return true
}
const listenerBehavior = (spec, e) => {
  let prevent = spec.prevent
  let stop = spec.stop
  for (const policy of spec.policies) {
    if (!policyMatches(policy, e)) { continue }
    prevent = boolOr(policy?.prevent, prevent)
    stop = boolOr(policy?.stop, stop)
  }
  return { prevent, stop }
}
const queryById = (target, kind = 'node', value = undefined) => {
  const current = managed(target)
  const node = current ? snapshotNode(current.id, current.node) : null
  if (!node || kind === 'node') { return node }
  if (kind === 'text') { return { id: node.id, text: node.text ?? '' } }
  if (kind === 'attr') {
    const key = typeof value === 'string' ? value : ''
    if (key === '') {
      throw Error('query attr expects property name')
    }
    if (!isElement(current?.node)) {
      throw Error('query attr expects element node')
    }
    return { id: node.id, kind, key, value: current.node.getAttribute(key) ?? '' }
  }
  if (kind === 'style') {
    const key = typeof value === 'string' ? value : ''
    if (key === '') {
      throw Error('query style expects property name')
    }
    if (!isElement(current?.node)) {
      throw Error('query style expects element node')
    }
    return { id: node.id, kind, key, value: window.getComputedStyle(current.node).getPropertyValue(key) }
  }
  if (kind === 'prop') {
    const key = typeof value === 'string' ? value : ''
    if (key === '') {
      throw Error('query prop expects property name')
    }
    const raw = current?.node?.[key]
    return { id: node.id, kind, key, value: raw == null ? '' : String(raw) }
  }
  throw Error(`unsupported query kind: ${kind}`)
}
const encodeQuery = (kind, value) => {
  if (kind === 'node' || kind === 'text') {
    return kind
  }
  return { kind, value: typeof value === 'string' ? value : '' }
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
      clearListeners(Number(id))
      nodes.delete(Number(id))
    }
  },
  [DOM_CMD.LISTEN]: (id, rawSpec) => {
    const node = managed(id)?.node
    if (!node) { return }
    const spec = listenerSpec(rawSpec)
    const evt = spec.event.startsWith('on') ? spec.event.slice(2) : spec.event
    let slots = listeners.get(id)
    if (!slots) {
      slots = new Map()
      listeners.set(id, slots)
    }
    const current = slots.get(evt)
    if (current) {
      node.removeEventListener(evt, current.handler, current.capture)
    }
    const handler = e => {
      const behavior = listenerBehavior(spec, e)
      if (behavior.stop) {
        e.stopPropagation()
      }
      if (behavior.prevent) {
        e.preventDefault()
      }
    }
    node.addEventListener(evt, handler, { capture: spec.capture, passive: spec.passive })
    slots.set(evt, { event: evt, handler, capture: spec.capture })
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
}
const apply = cmds => {
  for (const [type, ...content] of cmds) { domOps[type](...content) }
}
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
const triggerResult = (id, kind, extra = {}) => ({ ok: true, kind, id, ...extra })
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
  node.dispatchEvent(pointerEventFor(cmd, 'pointermove', {
    x: (start.x + end.x) / 2, y: (start.y + end.y) / 2, btns: 1,
  }))
  node.dispatchEvent(pointerEventFor(cmd, 'pointerup', { ...end, btns: 0 }))
  return triggerResult(id, 'drag_to', { target_id: target.id })
}
const triggerById = cmd => {
  const target = managed(cmd)
  if (!target) { throw Error('target not found') }
  const { id, node } = target
  switch (cmd.kind) {
    case 'pointer': case 'click': case 'dblclick':
    case 'pointerdown': case 'pointermove': case 'pointerup':
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
        bubbles: true,
        key: cmd.key ?? '',
        code: cmd.code ?? '',
        ctrlKey: !!cmd.ctrl_key,
        shiftKey: !!cmd.shift_key,
        altKey: !!cmd.alt_key,
        metaKey: !!cmd.meta_key,
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
const modkey = value => ({
    ctrl: !!value?.ctrlKey, shift: !!value?.shiftKey,
    alt: !!value?.altKey, meta: !!value?.metaKey, })
const mouseDispatch = (kind, value = {}) => ({
  kind, mod: modkey(value),
  x: eventInt(value?.x),
  y: eventInt(value?.y),
  button: eventInt(value?.button),
  buttons: eventInt(value?.buttons),
})
const keyDispatch = (kind, value = {}) => ({
  kind, mod: modkey(value),
  key: value?.key ?? '',
  code: value?.code ?? '',
})
const dispatchPayload = (path, kind, value) => {
  if (typeof path !== 'string' || path === '') {
    throw Error('dispatch path must be a string')
  }
  switch (kind) {
    case 'click': return { path, event: { kind: 'click' } }
    case 'focus': return { path, event: { kind: 'focus' } }
    case 'blur': return { path, event: { kind: 'blur' } }
    case 'input': return { path, event: { kind: 'input', value: typeof value === 'string' ? value : '' } }
    case 'pointerdown': return { path, event: mouseDispatch('pointerdown', value) }
    case 'pointerup': return { path, event: mouseDispatch('pointerup', value) }
    case 'pointermove': return { path, event: mouseDispatch('pointermove', value) }
    case 'key': {
      if (typeof value === 'string') {
        return { path, event: keyDispatch('keydown', { key: value }) }
      }
      return { path, event: keyDispatch(value?.event === 'keyup' ? 'keyup' : 'keydown', value) }
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
  if (!body) {
    return
  }
  switch (body.tag) {
    case 'HelloAck':
      onHelloAck()
      return
    case 'Pong':
      if (pingPending && pingPending.id === packet.id) {
        latencyMs = performance.now() - pingPending.sentAt
        pingPending = null
      }
      return
    case 'Query':
      settlePendingRequest(packet.id, true, body.value, null)
      return
    case 'Ok':
      settlePendingRequest(packet.id, true, true, null)
      return
    case 'Err': {
      const msg = typeof body.value === 'string' ? body.value : 'request failed'
      if (settlePendingRequest(packet.id, false, null, msg)) {
        return
      }
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
  setStatusListener: listener => {
    statusListener = typeof listener === 'function' ? listener : null
  },
  query: async (path, kind = 'node', value = undefined) =>
    sendRequest(REQ.QUERY, { path, query: encodeQuery(kind, value) }),
  trigger: async (path, kind, value = undefined) => {
    if (kind === 'key' && value?.event === 'press') {
      await sendRequest(REQ.DISPATCH, { path, event: keyDispatch('keydown', value) })
      return sendRequest(REQ.DISPATCH, { path, event: keyDispatch('keyup', value) })
    }
    return sendRequest(REQ.DISPATCH, dispatchPayload(path, kind, value))
  },
  command: async (cmd, arg = '') => {
    const res = await fetch('/_meta/command', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ cmd, arg }),
    })
    const body = await res.json()
    if (body?.ok) {
      return typeof body.result === 'string' ? body.result : ''
    }
    throw Error(body?.error ?? 'command failed')
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
  bridgeTest: { // bridge 白盒测试专用 API （普通测试禁用）
    DOM_CMD,
    apply,
    queryById,
    triggerById,
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
        close() {},
      }
      setStatus('connected')
      return bridge.status()
    },
  },
}
globalThis.mbt_bridge = bridge

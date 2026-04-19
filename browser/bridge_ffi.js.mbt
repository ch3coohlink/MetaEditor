#external
type HostNode
extern "js" fn body_root() -> HostNode =
  #| () => document.body
extern "js" fn head_root() -> HostNode =
  #| () => document.head
extern "js" fn create_host_node(tag: String, value: String?, ns: @shared.DomNs) -> HostNode =
  #| (tag, value, ns) => {
  #|   const namespaces = {
  #|     0: 'http://www.w3.org/1999/xhtml',
  #|     1: 'http://www.w3.org/2000/svg',
  #|     2: 'http://www.w3.org/1998/Math/MathML',
  #|   }
  #|   const node = tag === ''
  #|     ? document.createTextNode(value ?? '')
  #|     : (ns === 0
  #|       ? document.createElement(tag)
  #|       : document.createElementNS(namespaces[ns] ?? namespaces[0], tag))
  #|   if (value != null && tag !== '') {
  #|     node.textContent = value
  #|   }
  #|   return node
  #| }
extern "js" fn insert_host_node(
  parent: HostNode,
  child: HostNode,
  anchor: HostNode?,
  after: Bool,
) =
  #| (parent, child, anchor, after) => {
  #|   if (!anchor || anchor.parentNode !== parent) {
  #|     parent.appendChild(child)
  #|     return
  #|   }
  #|   const target = after ? anchor.nextSibling : anchor
  #|   parent.insertBefore(child, target ?? null)
  #| }
extern "js" fn remove_host_node(node: HostNode) =
  #| node => {
  #|   if (node?.parentNode) {
  #|     node.parentNode.removeChild(node)
  #|   }
  #| }
extern "js" fn clear_host_children(node: HostNode) =
  #| node => node.replaceChildren()
extern "js" fn set_host_attr(node: HostNode, key: String, value: String?) =
  #| (node, key, value) => {
  #|   if (!node?.setAttribute) {
  #|     return
  #|   }
  #|   if (value == null) {
  #|     node.removeAttribute(key)
  #|   } else {
  #|     node.setAttribute(key, value)
  #|   }
  #| }
extern "js" fn set_host_style(node: HostNode, key: String, value: String?) =
  #| (node, key, value) => {
  #|   const style = node?.style
  #|   if (!style) {
  #|     return
  #|   }
  #|   if (value == null) {
  #|     style.removeProperty(key)
  #|   } else {
  #|     style.setProperty(key, value)
  #|   }
  #| }
extern "js" fn clear_host_prop(node: HostNode, key: String) =
  #| (node, key) => {
  #|   if (node) {
  #|     node[key] = undefined
  #|   }
  #| }
extern "js" fn set_host_prop_string(node: HostNode, key: String, value: String) =
  #| (node, key, value) => {
  #|   if (node) {
  #|     node[key] = value
  #|   }
  #| }
extern "js" fn set_host_prop_int(node: HostNode, key: String, value: Int) =
  #| (node, key, value) => {
  #|   if (node) {
  #|     node[key] = value
  #|   }
  #| }
extern "js" fn set_host_prop_float(node: HostNode, key: String, value: Double) =
  #| (node, key, value) => {
  #|   if (node) {
  #|     node[key] = value
  #|   }
  #| }

#external
type ListenerHandle
extern "js" fn bind_host_listener(
  node: HostNode, name: String, capture: Bool, stop: Bool, prevent: Bool, f: (HostEvent) -> Unit,
) -> ListenerHandle =
  #| (node, name, capture, stop, prevent, f) => {
  #|   const handler = event => {
  #|     if (stop) {
  #|       event.stopPropagation()
  #|     }
  #|     if (prevent) {
  #|       event.preventDefault()
  #|     }
  #|     f(event)
  #|   }
  #|   const options = { capture: !!capture }
  #|   node.addEventListener(name, handler, options)
  #|   return { name, handler, options }
  #| }
extern "js" fn unbind_host_listener(node: HostNode, handle: ListenerHandle) =
  #| (node, handle) => {
  #|   if (node && handle) {
  #|     node.removeEventListener(handle.name, handle.handler, handle.options)
  #|   }
  #| }

#external
type HostEvent
extern "js" fn event_ctrl_key(event: HostEvent) -> Bool =
  #| event => !!event?.ctrlKey
extern "js" fn event_shift_key(event: HostEvent) -> Bool =
  #| event => !!event?.shiftKey
extern "js" fn event_alt_key(event: HostEvent) -> Bool =
  #| event => !!event?.altKey
extern "js" fn event_meta_key(event: HostEvent) -> Bool =
  #| event => !!event?.metaKey
extern "js" fn event_client_x(event: HostEvent) -> Int =
  #| event => Number.isFinite(event?.clientX) ? Math.round(event.clientX) : 0
extern "js" fn event_client_y(event: HostEvent) -> Int =
  #| event => Number.isFinite(event?.clientY) ? Math.round(event.clientY) : 0
extern "js" fn event_local_x(event: HostEvent) -> Int =
  #| event => Number.isFinite(event?.x) ? Math.round(event.x) : 0
extern "js" fn event_local_y(event: HostEvent) -> Int =
  #| event => Number.isFinite(event?.y) ? Math.round(event.y) : 0
extern "js" fn event_button(event: HostEvent) -> Int =
  #| event => Number.isFinite(event?.button) ? Math.round(event.button) : 0
extern "js" fn event_buttons(event: HostEvent) -> Int =
  #| event => Number.isFinite(event?.buttons) ? Math.round(event.buttons) : 0
extern "js" fn event_pointer_id(event: HostEvent) -> Int =
  #| event => Number.isFinite(event?.pointerId) ? Math.round(event.pointerId) : 0
extern "js" fn event_key(event: HostEvent) -> String =
  #| event => event?.key ?? ''
extern "js" fn event_code(event: HostEvent) -> String =
  #| event => event?.code ?? ''
extern "js" fn node_value(node: HostNode) -> String =
  #| node => node?.value ?? ''
extern "js" fn set_pointer_capture(node: HostNode, pointer_id: Int, capture: Bool) =
  #| (node, pointerId, capture) => {
  #|   if (!node || !node.setPointerCapture || pointerId <= 0) {
  #|     return
  #|   }
  #|   try {
  #|     if (capture) {
  #|       node.setPointerCapture(pointerId)
  #|     } else if (!node.hasPointerCapture || node.hasPointerCapture(pointerId)) {
  #|       node.releasePointerCapture(pointerId)
  #|     }
  #|   } catch {}
  #| }
extern "js" fn set_host_focus(node: HostNode, focus: Bool) =
  #| (node, focus) => {
  #|   if (!node) {
  #|     return
  #|   }
  #|   if (focus) {
  #|     node.focus?.()
  #|   } else {
  #|     node.blur?.()
  #|   }
  #| }
extern "js" fn point_of_host_node(node: HostNode) -> String? =
  #| node => {
  #|   if (!node?.scrollIntoView || !node?.getBoundingClientRect) {
  #|     return null
  #|   }
  #|   node.scrollIntoView({ block: 'center', inline: 'center' })
  #|   const rect = node.getBoundingClientRect()
  #|   if (!(rect.width > 0 && rect.height > 0)) {
  #|     return null
  #|   }
  #|   return JSON.stringify({ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 })
  #| }
extern "js" fn box_of_host_node(node: HostNode) -> String? =
  #| node => {
  #|   if (!node?.getBoundingClientRect) {
  #|     return null
  #|   }
  #|   const rect = node.getBoundingClientRect()
  #|   return JSON.stringify({
  #|     x: Math.round(rect.left),
  #|     y: Math.round(rect.top),
  #|     w: Math.round(rect.width),
  #|     h: Math.round(rect.height),
  #|   })
  #| }
extern "js" fn view_of_host_node(node: HostNode) -> String? =
  #| node => {
  #|   if (!node) {
  #|     return null
  #|   }
  #|   const w = Number.isFinite(node.clientWidth) ? Math.round(node.clientWidth) : 0
  #|   const h = Number.isFinite(node.clientHeight) ? Math.round(node.clientHeight) : 0
  #|   return JSON.stringify({ x: 0, y: 0, w, h })
  #| }
extern "js" fn scroll_of_host_node(node: HostNode) -> String? =
  #| node => {
  #|   if (!node) {
  #|     return null
  #|   }
  #|   const x = Number.isFinite(node.scrollLeft) ? Math.round(node.scrollLeft) : 0
  #|   const y = Number.isFinite(node.scrollTop) ? Math.round(node.scrollTop) : 0
  #|   const w = Number.isFinite(node.scrollWidth) ? Math.round(node.scrollWidth) : 0
  #|   const h = Number.isFinite(node.scrollHeight) ? Math.round(node.scrollHeight) : 0
  #|   return JSON.stringify({ x, y, w, h })
  #| }
extern "js" fn measure_host_texts(font: String, texts: Array[String]) -> Array[Int] =
  #| (font, texts) => {
  #|   const keyOf = text => `${font}\n${text}`
  #|   const cache = globalThis.__mbt_text_measure_cache ??=
  #|     { map: new Map(), canvas: document.createElement('canvas') }
  #|   const ctx = cache.canvas.getContext('2d')
  #|   if (!ctx) {
  #|     return texts.map(() => 0)
  #|   }
  #|   ctx.font = font
  #|   return texts.map(text => {
  #|     const key = keyOf(text)
  #|     const hit = cache.map.get(key)
  #|     if (hit != null) {
  #|       return hit
  #|     }
  #|     const width = Math.round(ctx.measureText(text).width)
  #|     cache.map.set(key, width)
  #|     return width
  #|   })
  #| }
extern "js" fn ws_url() -> String =
  #| () => {
  #|   const protocol = globalThis.location?.protocol === 'https:' ? 'wss:' : 'ws:'
  #|   return `${protocol}//${globalThis.location.host}/_meta/ws`
  #| }
extern "js" fn ensure_session_id(key: String) -> String =
  #| key => {
  #|   let id = globalThis.localStorage?.getItem(key)
  #|   if (!id) {
  #|     id = globalThis.crypto?.randomUUID?.() ??
  #|       `${Date.now()}-${Math.random().toString(16).slice(2)}`
  #|     globalThis.localStorage?.setItem(key, id)
  #|   }
  #|   return id
  #| }


#external
type HostSocket
extern "js" fn socket_ready_state(socket: HostSocket) -> Int =
  #| socket => socket?.readyState ?? 3
extern "js" fn socket_send_text(socket: HostSocket, value: String) =
  #| (socket, value) => socket.send(value)
extern "js" fn socket_close(socket: HostSocket) =
  #| socket => socket?.close()
extern "js" fn connect_socket(
  url: String,
  on_open: () -> Unit,
  on_message: (String) -> Unit,
  on_close: () -> Unit,
  on_error: (String) -> Unit,
) -> HostSocket =
  #| (url, onOpen, onMessage, onClose, onError) => {
  #|   const socket = new WebSocket(url)
  #|   socket.onopen = () => onOpen()
  #|   socket.onmessage = event => {
  #|     try {
  #|       onMessage(typeof event.data === 'string' ? event.data : '')
  #|     } catch (error) {
  #|       onError(error?.message ?? String(error))
  #|     }
  #|   }
  #|   socket.onclose = () => onClose()
  #|   socket.onerror = error => onError(error?.message ?? 'websocket error')
  #|   return socket
  #| }

#external
type TimerHandle
extern "js" fn set_timeout_ms(delay: Int, f: () -> Unit) -> TimerHandle =
  #| (delay, f) => setTimeout(f, delay)
extern "js" fn set_interval_ms(delay: Int, f: () -> Unit) -> TimerHandle =
  #| (delay, f) => setInterval(f, delay)
extern "js" fn clear_timer(handle: TimerHandle) =
  #| handle => {
  #|   clearTimeout(handle)
  #|   clearInterval(handle)
  #| }
extern "js" fn console_error(msg: String) =
  #| msg => console.error(msg)
extern "js" fn install_bridge_api(
  status: () -> String,
  init: () -> Promise[Unit],
  query: (String, String) -> Promise[String],
  read: (String) -> Promise[String],
  dispatch: (String, String) -> Promise[String],
  cli: (String, String) -> Promise[String],
  reset: (String) -> Promise[String],
  point_of: (Int) -> String?,
) =
  #| (status, init, query, read, dispatch, cli, reset, pointOf) => {
  #|   const parse = value => value == null || value === '' ? null : JSON.parse(value)
  #|   globalThis.mbt_bridge = {
  #|     status: () => parse(status()),
  #|     init,
  #|     query: async (path, spec = 'Node') => parse(await query(path, JSON.stringify(spec))),
  #|     read: async spec => parse(await read(JSON.stringify(spec))),
  #|     dispatch: async (path, event) => parse(await dispatch(path, JSON.stringify(event))),
  #|     cli: (cmd, arg = '') => cli(cmd, arg),
  #|     reset: async (root = '') => parse(await reset(root)),
  #|   }
  #|   globalThis.__mbt_bridge_internal = {
  #|     pointOf: id => parse(pointOf(id)),
  #|   }
  #| }

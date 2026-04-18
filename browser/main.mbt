using @json { from_json }

let dom_root_head: Int = 1
let dom_root_body: Int = 2
let session_key: String = "mbt_bridge_session_id"

enum Incoming { Open; Message(Json); Closed; Error(String); Ping; Reconnect }
enum PendingRes { Ok(Json); Err(String) }

struct ManagedNode {
  node: HostNode
  mut parent: Int
  mut children: Array[Int]
  listeners: Map[Int, ListenerHandle]
}

struct PendingReq { q: @aqueue.Queue[PendingRes] }

struct Bridge {
  inbound: @aqueue.Queue[Incoming]
  nodes: Map[Int, ManagedNode]
  pending: Map[Int, PendingReq]
  mut next_id: Int
  mut ws: HostSocket?
  mut ping_id: Int
  mut ping_timer: TimerHandle?
  mut reconnect_timer: TimerHandle?
  mut should_reconnect: Bool
  mut state: String
  mut reason: String?
}

fn Bridge::new() -> Bridge {{
  inbound: @aqueue.Queue::new(kind=Unbounded),
  nodes: Map::new(),
  pending: Map::new(),
  next_id: 1,
  ws: None,
  ping_id: 0,
  ping_timer: None,
  reconnect_timer: None,
  should_reconnect: true,
  state: "idle",
  reason: None,
}}

let bridge = Bridge::new()

fn queue_put(msg: Incoming) -> Unit {
  ignore(bridge.inbound.try_put(msg))
}

fn next_packet_id() -> Int {
  let id = bridge.next_id
  bridge.next_id += 1
  id
}

fn set_status(state: String, reason?: String = "") -> Unit {
  bridge.state = state
  bridge.reason = if reason == "" { None } else { Some(reason) }
}

fn status_json() -> Json {
  let obj = Map::new()
  obj.set("state", bridge.state.to_json())
  match bridge.reason {
    Some(reason) => obj.set("reason", reason.to_json())
    None => ()
  }
  Json::object(obj)
}

fn clear_ping_timer() -> Unit {
  match bridge.ping_timer {
    Some(timer) => { clear_timer(timer); bridge.ping_timer = None }
    None => ()
  }
}

fn clear_reconnect_timer() -> Unit {
  match bridge.reconnect_timer {
    Some(timer) => { clear_timer(timer); bridge.reconnect_timer = None }
    None => ()
  }
}

fn reset_ping() -> Unit {
  bridge.ping_id = 0
}

fn reject_pending(msg: String) -> Unit {
  let ids = []
  for id, _ in bridge.pending { ids.push(id) }
  for id in ids {
    match bridge.pending.get(id) {
      Some(pending) => {
        bridge.pending.remove(id)
        ignore(pending.q.try_put(Err(msg)))
      }
      None => ()
    }
  }
}

fn settle_pending(id: Int, res: PendingRes) -> Bool {
  match bridge.pending.get(id) {
    Some(pending) => {
      bridge.pending.remove(id)
      ignore(pending.q.try_put(res))
      true
    }
    None => false
  }
}

fn socket_open() -> Bool {
  match bridge.ws {
    Some(ws) => socket_ready_state(ws) == 1
    None => false
  }
}

fn socket_live() -> Bool {
  match bridge.ws {
    Some(ws) => {
      let state = socket_ready_state(ws)
      state == 0 || state == 1
    }
    None => false
  }
}

fn send_packet(packet: Json) -> Unit raise {
  match bridge.ws {
    Some(ws) => {
      if socket_ready_state(ws) != 1 { fail("bridge is not connected") }
      socket_send_json(ws, packet)
    }
    None => fail("bridge is not connected")
  }
}

async fn send_request(packet: Json) -> Json raise {
  guard socket_open() else { fail("bridge is not connected") }
  let id = match packet {
    Object(obj) => match obj.get("id") {
      Some(Number(v, _)) => v.to_int()
      _ => fail("request id missing")
    }
    _ => fail("invalid packet")
  }
  let pending = { q: @aqueue.Queue::new(kind=Unbounded) }
  bridge.pending.set(id, pending)
  try {
    send_packet(packet)
    match pending.q.get() {
      Ok(value) => value
      Err(msg) => fail(msg)
    }
  } catch {
    err => {
      bridge.pending.remove(id)
      raise err
    }
  }
}

fn event_name(kind: @shared.EventKind) -> String {
  match kind {
    Click => "click"
    Input => "input"
    Change => "change"
    Focus => "focus"
    Blur => "blur"
    KeyDown => "keydown"
    KeyUp => "keyup"
    PointerDown => "pointerdown"
    PointerUp => "pointerup"
    PointerMove => "pointermove"
    PointerCancel => "pointercancel"
  }
}

fn event_mod(event: HostEvent) -> @shared.Modify {
  @shared.Modify::new(
    ctrl=event_ctrl_key(event),
    shift=event_shift_key(event),
    alt=event_alt_key(event),
    meta=event_meta_key(event),
  )
}

fn event_from_name(name: String, event: HostEvent, node: HostNode) -> @shared.Event? {
  match name {
    "click" => Some(@shared.Event::pointer(Click))
    "focus" => Some(@shared.Event::pointer(Focus))
    "blur" => Some(@shared.Event::pointer(Blur))
    "change" => Some(@shared.Event::new(Change, Input({ value: node_value(node) })))
    "input" => Some(@shared.Event::new(Input, Input({ value: node_value(node) })))
    "pointerdown" => Some(@shared.Event::pointer(PointerDown,
      mod=event_mod(event),
      x=event_client_x(event),
      y=event_client_y(event),
      vx=event_local_x(event),
      vy=event_local_y(event),
      button=event_button(event),
      buttons=event_buttons(event),
      pointer_id=event_pointer_id(event),
    ))
    "pointerup" => Some(@shared.Event::pointer(PointerUp,
      mod=event_mod(event),
      x=event_client_x(event),
      y=event_client_y(event),
      vx=event_local_x(event),
      vy=event_local_y(event),
      button=event_button(event),
      buttons=event_buttons(event),
      pointer_id=event_pointer_id(event),
    ))
    "pointermove" => Some(@shared.Event::pointer(PointerMove,
      mod=event_mod(event),
      x=event_client_x(event),
      y=event_client_y(event),
      vx=event_local_x(event),
      vy=event_local_y(event),
      button=event_button(event),
      buttons=event_buttons(event),
      pointer_id=event_pointer_id(event),
    ))
    "pointercancel" => Some(@shared.Event::pointer(PointerCancel,
      mod=event_mod(event),
      x=event_client_x(event),
      y=event_client_y(event),
      vx=event_local_x(event),
      vy=event_local_y(event),
      button=event_button(event),
      buttons=event_buttons(event),
      pointer_id=event_pointer_id(event),
    ))
    "keydown" => Some(@shared.Event::new(KeyDown,
      Key({ mod: event_mod(event), key: event_key(event), code: event_code(event) })))
    "keyup" => Some(@shared.Event::new(KeyUp,
      Key({ mod: event_mod(event), key: event_key(event), code: event_code(event) })))
    _ => None
  }
}

fn node_of(id: Int) -> ManagedNode? {
  bridge.nodes.get(id)
}

fn root_node(id: Int) -> HostNode? {
  if id == dom_root_body { Some(body_root()) }
  else if id == dom_root_head { Some(head_root()) }
  else { node_of(id).map(v => v.node) }
}

fn remove_child_id(children: Array[Int], id: Int) -> Unit {
  let mut i = 0
  while i < children.length() {
    if children[i] == id {
      children.remove(i)
      return
    }
    i += 1
  }
}

fn detach_child(id: Int) -> Unit {
  match node_of(id) {
    Some(child) => {
      if child.parent > 0 {
        match bridge.nodes.get(child.parent) {
          Some(parent) => remove_child_id(parent.children, id)
          None => ()
        }
        child.parent = 0
      }
    }
    None => ()
  }
}

fn remove_node_tree(id: Int) -> Unit {
  match node_of(id) {
    Some(entry) => {
      let child_ids = entry.children.copy()
      for child in child_ids { remove_node_tree(child) }
      detach_child(id)
      remove_host_node(entry.node)
      bridge.nodes.remove(id)
    }
    None => ()
  }
}

fn reset_dom() -> Unit {
  let ids = []
  for id, _ in bridge.nodes { ids.push(id) }
  for id in ids { remove_node_tree(id) }
  clear_host_children(body_root())
  bridge.nodes.clear()
}

fn insert_child(parent_id: Int, child_id: Int, target_id: Int, after: Bool) -> Unit {
  let parent = root_node(parent_id)
  let child = node_of(child_id)
  guard parent is Some(parent) && child is Some(child) else { return }
  detach_child(child_id)
  let ref = if target_id == 0 { None } else { root_node(target_id) }
  insert_host_node(parent, child.node, ref, after)
  child.parent = if parent_id == dom_root_body || parent_id == dom_root_head { 0 } else { parent_id }
  if child.parent > 0 {
    match bridge.nodes.get(child.parent) {
      Some(parent_node) => {
        let index = if target_id == 0 {
          parent_node.children.length()
        } else {
          let mut hit = parent_node.children.length()
          for i = 0; i < parent_node.children.length(); i += 1 {
            if parent_node.children[i] == target_id {
              hit = if after { i + 1 } else { i }
              break
            }
          }
          hit
        }
        parent_node.children.insert(index, child_id)
      }
      None => ()
    }
  }
}

async fn send_trigger(node: Int, event: @shared.Event) -> Unit raise {
  ignore(send_request({ "id": next_packet_id(), "type": "trigger", "node": node, "event": event }))
}

fn bind_prop_listener(node: HostNode, key: String, payload: @shared.ListenerValue) -> Unit {
  set_host_prop_listener(node, key, payload.cfg.stop, payload.cfg.prevent, event => {
    match event_from_name(event_name(payload.kind), event, node) {
      Some(ev) => ignore(@js_async.Promise::from_async(() => send_trigger(payload.nid, ev)))
      None => ()
    }
  })
}

fn bind_listener(node_id: Int, payload: @shared.ListenerCmd) -> Unit {
  match bridge.nodes.get(node_id) {
    Some(entry) => {
      match entry.listeners.get(payload.id) {
        Some(prev) => { unbind_host_listener(entry.node, prev); entry.listeners.remove(payload.id) }
        None => ()
      }
      if !payload.bind { return }
      let name = event_name(payload.kind)
      let handle = bind_host_listener(
        entry.node,
        name,
        payload.cfg.capture,
        payload.cfg.stop,
        payload.cfg.prevent,
        event => match event_from_name(name, event, entry.node) {
          Some(ev) => ignore(@js_async.Promise::from_async(() => send_trigger(payload.nid, ev)))
          None => ()
        },
      )
      entry.listeners.set(payload.id, handle)
    }
    None => ()
  }
}

fn apply_prop(node: HostNode, key: String, value: @shared.JsValue) -> Unit {
  match value {
    Empty => clear_host_prop(node, key)
    String(v) => set_host_prop_string(node, key, v)
    Int(v) => set_host_prop_int(node, key, v)
    Float(v) => set_host_prop_float(node, key, v)
    Listener(payload) => bind_prop_listener(node, key, payload)
  }
}

fn apply_dom_cmd(cmd: @shared.DomCmd) -> Unit {
  match cmd {
    Create({ id, tag, ns, value }) => {
      let text = match value { Empty => None; String(v) => Some(v) }
      bridge.nodes.set(id, { node: create_host_node(tag, text, ns), parent: 0, children: [], listeners: Map::new() })
    }
    Insert({ parent, child, target, after }) => insert_child(parent, child, target, after)
    Remove(id) => remove_node_tree(id)
    Attr(id, key, value) => match node_of(id) {
      Some(entry) => set_host_attr(entry.node, key, match value { Empty => None; String(v) => Some(v) })
      None => ()
    }
    Style(id, key, value) => match node_of(id) {
      Some(entry) => set_host_style(entry.node, key, match value { Empty => None; String(v) => Some(v) })
      None => ()
    }
    Prop(id, key, value) => match node_of(id) {
      Some(entry) => apply_prop(entry.node, key, value)
      None => ()
    }
    Listener(payload) => bind_listener(payload.nid, payload)
    Pointer(payload) => match node_of(payload.id) {
      Some(entry) => set_pointer_capture(entry.node, payload.pointer_id, payload.capture)
      None => ()
    }
    Focus(payload) => match node_of(payload.id) {
      Some(entry) => set_host_focus(entry.node, payload.focus)
      None => ()
    }
  }
}

fn apply_dom_batch(value: Json) -> Unit {
  match value {
    Array(items) => for i in 0..<items.length() {
      let cmd: @shared.DomCmd = from_json(items[i], path=@json.JsonPath::new()) catch {
        _ => { console_error("invalid dom cmd"); continue }
      }
      apply_dom_cmd(cmd)
    }
    _ => ()
  }
}

fn on_hello_ack() -> Unit {
  reset_dom()
  bridge.should_reconnect = true
  clear_reconnect_timer()
  clear_ping_timer()
  bridge.ping_timer = Some(set_interval_ms(2000, () => queue_put(Ping)))
  reset_ping()
  set_status("connected")
  queue_put(Ping)
}

fn schedule_reconnect() -> Unit {
  if !bridge.should_reconnect || bridge.reconnect_timer is Some(_) { return }
  set_status("reconnecting")
  bridge.reconnect_timer = Some(set_timeout_ms(300, () => queue_put(Reconnect)))
}

fn handle_response(res: @shared.ResMsg) -> Unit {
  match res.body {
    HelloAck(_) => on_hello_ack()
    Pong => if bridge.ping_id == res.id { reset_ping() }
    Query(value) => ignore(settle_pending(res.id, Ok(value.to_json())))
    Cli(value) => ignore(settle_pending(res.id, Ok(value.to_json())))
    Ok => ignore(settle_pending(res.id, Ok(true.to_json())))
    Err(msg) => {
      if settle_pending(res.id, Err(msg)) { return }
      bridge.should_reconnect = false
      reject_pending(msg)
      reset_ping()
      clear_reconnect_timer()
      set_status("rejected", reason=msg)
      match bridge.ws { Some(ws) => socket_close(ws); None => () }
    }
  }
}

fn handle_message(value: Json) -> Unit {
  match value {
    Array(_) => apply_dom_batch(value)
    Object(_) => {
      let res: @shared.ResMsg = from_json(value) catch {
        _ => { console_error("invalid response packet"); return }
      }
      handle_response(res)
    }
    _ => ()
  }
}

fn ensure_socket() -> Unit {
  if socket_live() { return }
  bridge.should_reconnect = true
  clear_reconnect_timer()
  set_status("connecting")
  let socket = connect_socket(
    ws_url(),
    () => queue_put(Open),
    value => queue_put(Message(value)),
    () => queue_put(Closed),
    msg => queue_put(Error(msg)),
  )
  bridge.ws = Some(socket)
}

fn encode_query(kind: String, value: Json?) -> @shared.NodeQuery {
  match kind {
    "node" | "Node" => Node
    "text" | "Text" => Text
    "attr" | "Attr" => Attr(match value { Some(String(v)) => v; _ => "" })
    "prop" | "Prop" => Prop(match value { Some(String(v)) => v; _ => "" })
    "style" | "Style" => Style(match value { Some(String(v)) => v; _ => "" })
    _ => Node
  }
}

fn json_int(value: Json?, key: String) -> Int {
  match value {
    Some(Object(obj)) => match obj.get(key) {
      Some(Number(v, _)) => v.to_int()
      _ => 0
    }
    _ => 0
  }
}

fn json_bool(value: Json?, key: String) -> Bool {
  match value {
    Some(Object(obj)) => match obj.get(key) {
      Some(True) => true
      Some(False) => false
      _ => false
    }
    _ => false
  }
}

fn json_string(value: Json?, key: String) -> String {
  match value {
    Some(Object(obj)) => match obj.get(key) {
      Some(String(v)) => v
      _ => ""
    }
    _ => ""
  }
}

fn dispatch_event(kind: String, value: Json?) -> @shared.Event raise {
  match kind {
    "click" => @shared.Event::pointer(Click)
    "focus" => @shared.Event::pointer(Focus)
    "blur" => @shared.Event::pointer(Blur)
    "input" => @shared.Event::new(Input, Input({ value: match value { Some(String(v)) => v; _ => "" } }))
    "pointerdown" => @shared.Event::pointer(PointerDown,
      mod=@shared.Modify::new(
        ctrl=json_bool(value, "ctrlKey"),
        shift=json_bool(value, "shiftKey"),
        alt=json_bool(value, "altKey"),
        meta=json_bool(value, "metaKey"),
      ),
      x=json_int(value, "clientX"),
      y=json_int(value, "clientY"),
      vx=match json_int(value, "x") { 0 => json_int(value, "vx"); v => v },
      vy=match json_int(value, "y") { 0 => json_int(value, "vy"); v => v },
      button=json_int(value, "button"),
      buttons=json_int(value, "buttons"),
      pointer_id=json_int(value, "pointerId"),
    )
    "pointerup" => @shared.Event::pointer(PointerUp,
      mod=@shared.Modify::new(
        ctrl=json_bool(value, "ctrlKey"),
        shift=json_bool(value, "shiftKey"),
        alt=json_bool(value, "altKey"),
        meta=json_bool(value, "metaKey"),
      ),
      x=json_int(value, "clientX"),
      y=json_int(value, "clientY"),
      vx=match json_int(value, "x") { 0 => json_int(value, "vx"); v => v },
      vy=match json_int(value, "y") { 0 => json_int(value, "vy"); v => v },
      button=json_int(value, "button"),
      buttons=json_int(value, "buttons"),
      pointer_id=json_int(value, "pointerId"),
    )
    "pointermove" => @shared.Event::pointer(PointerMove,
      mod=@shared.Modify::new(
        ctrl=json_bool(value, "ctrlKey"),
        shift=json_bool(value, "shiftKey"),
        alt=json_bool(value, "altKey"),
        meta=json_bool(value, "metaKey"),
      ),
      x=json_int(value, "clientX"),
      y=json_int(value, "clientY"),
      vx=match json_int(value, "x") { 0 => json_int(value, "vx"); v => v },
      vy=match json_int(value, "y") { 0 => json_int(value, "vy"); v => v },
      button=json_int(value, "button"),
      buttons=json_int(value, "buttons"),
      pointer_id=json_int(value, "pointerId"),
    )
    "key" => @shared.Event::new(
      if json_string(value, "event") == "keyup" { KeyUp } else { KeyDown },
      Key({
        mod: @shared.Modify::new(
          ctrl=json_bool(value, "ctrlKey"),
          shift=json_bool(value, "shiftKey"),
          alt=json_bool(value, "altKey"),
          meta=json_bool(value, "metaKey"),
        ),
        key: if value is Some(String(v)) { v } else { json_string(value, "key") },
        code: json_string(value, "code"),
      }),
    )
    _ => fail("unsupported dispatch kind: \{kind}")
  }
}

async fn query_api(path: String, kind: String, value: Json?) -> Json raise {
  send_request({
    "id": next_packet_id(),
    "type": "query",
    "path": path,
    "query": encode_query(kind, value),
  })
}

async fn dispatch_api(path: String, kind: String, value: Json?) -> Json raise {
  if kind == "key" && json_string(value, "event") == "press" {
    ignore(send_request({
      "id": next_packet_id(),
      "type": "dispatch",
      "path": path,
      "event": @shared.Event::new(KeyDown, Key({
        mod: @shared.Modify::new(
          ctrl=json_bool(value, "ctrlKey"),
          shift=json_bool(value, "shiftKey"),
          alt=json_bool(value, "altKey"),
          meta=json_bool(value, "metaKey"),
        ),
        key: json_string(value, "key"),
        code: json_string(value, "code"),
      })),
    }))
    return send_request({
      "id": next_packet_id(),
      "type": "dispatch",
      "path": path,
      "event": @shared.Event::new(KeyUp, Key({
        mod: @shared.Modify::new(
          ctrl=json_bool(value, "ctrlKey"),
          shift=json_bool(value, "shiftKey"),
          alt=json_bool(value, "altKey"),
          meta=json_bool(value, "metaKey"),
        ),
        key: json_string(value, "key"),
        code: json_string(value, "code"),
      })),
    })
  }
  send_request({
    "id": next_packet_id(),
    "type": "dispatch",
    "path": path,
    "event": dispatch_event(kind, value),
  })
}

async fn cli_api(cmd: String, arg: String) -> String raise {
  let line = if arg == "" { cmd } else { "\{cmd} \{arg}" }
  match send_request({ "id": next_packet_id(), "type": "cli", "cmd": line }) {
    String(v) => v
    _ => ""
  }
}

async fn reset_api(root: String) -> Unit raise {
  reset_dom()
  reset_ping()
  bridge.reason = None
  ignore(send_request({
    "id": next_packet_id(),
    "type": "cli",
    "cmd": if root == "" { "reset" } else { "reset \{root}" },
  }))
}

fn point_of_api(id: Int) -> Json? {
  match node_of(id) {
    Some(entry) => point_of_host_node(entry.node)
    None => None
  }
}

fn install_api() -> Unit {
  install_bridge_api(
    status_json,
    () => @js_async.Promise::from_async(() => { ensure_socket() }),
    (path, kind, value) => @js_async.Promise::from_async(() => query_api(path, kind, value)),
    (path, kind, value) => @js_async.Promise::from_async(() => dispatch_api(path, kind, value)),
    (cmd, arg) => @js_async.Promise::from_async(() => cli_api(cmd, arg)),
    root => @js_async.Promise::from_async(() => reset_api(root)),
    point_of_api,
  )
}

async fn bridge_loop {
  for ;; {
    match bridge.inbound.get() {
      Open => {
        try {
          send_packet({
            "id": next_packet_id(),
            "type": "hello",
            "role": "Browser",
            "session": ensure_session_id(session_key),
          })
        } catch { err => console_error(err.to_string()) }
      }
      Message(value) => handle_message(value)
      Closed => {
        bridge.ws = None
        reject_pending("bridge disconnected")
        if bridge.state == "rejected" { continue }
        set_status("disconnected")
        reset_ping()
        schedule_reconnect()
      }
      Error(msg) => console_error(msg)
      Ping => {
        if socket_open() && bridge.ping_id == 0 {
          let id = next_packet_id()
          bridge.ping_id = id
          try { send_packet({ "id": id, "type": "ping" }) } catch { err => console_error(err.to_string()) }
        }
      }
      Reconnect => {
        bridge.reconnect_timer = None
        ensure_socket()
      }
    }
  }
}

async fn main {
  install_api()
  bridge_loop()
}

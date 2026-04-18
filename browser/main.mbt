using @async {}
using @json { from_json }

let dom_root_head: Int = 1
let dom_root_body: Int = 2
let session_key: String = "mbt_bridge_session_id"

enum Incoming { Open; Message(Json); Closed; Error(String); Ping; Reconnect }
enum PendingRes { Ok(@shared.Res); Err(String) }
enum BridgeCall { Query(String, Json); Dispatch(String, Json); Cli(String, String); Reset(String) }

struct HostEntry {
  node: HostNode
  mut parent: Int
  children: Array[Int]
  listeners: Map[Int, ListenerHandle]
}

struct PendingReq { q: @aqueue.Queue[PendingRes] }

struct HostDom { nodes: Map[Int, HostEntry] }
fn HostDom::new() -> HostDom {{ nodes: Map::new() }}
fn HostDom::apply(
  self: HostDom,
  conn: Conn,
  cmd: @shared.DomCmd,
) -> Unit {
  fn root(id: Int) -> HostNode? {
    if id == dom_root_body { Some(body_root()) }
    else if id == dom_root_head { Some(head_root()) }
    else { self.nodes.get(id).map(v => v.node) }
  }
  fn detach(id: Int) -> Unit {
    match self.nodes.get(id) {
      Some(child) => {
        if child.parent > 0 {
          match self.nodes.get(child.parent) {
            Some(parent) => {
              let mut i = 0
              while i < parent.children.length() {
                if parent.children[i] == id {
                  ignore(parent.children.remove(i))
                  break
                }
                i += 1
              }
            }
            None => ()
          }
          child.parent = 0
        }
      }
      None => ()
    }
  }
  fn remove_tree(id: Int) -> Unit {
    match self.nodes.get(id) {
      Some(entry) => {
        let child_ids = entry.children.copy()
        for child in child_ids { remove_tree(child) }
        detach(id)
        remove_host_node(entry.node)
        self.nodes.remove(id)
      }
      None => ()
    }
  }
  fn insert(parent_id: Int, child_id: Int, target_id: Int, after: Bool) -> Unit {
    let parent = root(parent_id)
    let child = self.nodes.get(child_id)
    guard parent is Some(parent) && child is Some(child) else { return }
    detach(child_id)
    let anchor = if target_id == 0 { None } else { root(target_id) }
    insert_host_node(parent, child.node, anchor, after)
    child.parent = if parent_id == dom_root_body || parent_id == dom_root_head { 0 } else { parent_id }
    if child.parent > 0 {
      match self.nodes.get(child.parent) {
        Some(parent_node) => {
          let index = if target_id == 0 {
            parent_node.children.length()
          } else {
            let mut hit = parent_node.children.length()
            for i = 0; i < parent_node.children.length(); i = i + 1 {
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
  fn bind(payload: @shared.ListenerCmd) -> Unit {
    fn mod_of(event: HostEvent) -> @shared.Modify {
      @shared.Modify::new(
        ctrl=event_ctrl_key(event),
        shift=event_shift_key(event),
        alt=event_alt_key(event),
        meta=event_meta_key(event),
      )
    }
    fn event_of(name: String, event: HostEvent, node: HostNode) -> @shared.Event? {
      match name {
        "click" => Some(@shared.Event::pointer(Click))
        "focus" => Some(@shared.Event::pointer(Focus))
        "blur" => Some(@shared.Event::pointer(Blur))
        "change" => Some(@shared.Event::new(Change, Input({ value: node_value(node) })))
        "input" => Some(@shared.Event::new(Input, Input({ value: node_value(node) })))
        "pointerdown" => Some(@shared.Event::pointer(PointerDown,
          mod=mod_of(event),
          x=event_client_x(event),
          y=event_client_y(event),
          vx=event_local_x(event),
          vy=event_local_y(event),
          button=event_button(event),
          buttons=event_buttons(event),
          pointer_id=event_pointer_id(event),
        ))
        "pointerup" => Some(@shared.Event::pointer(PointerUp,
          mod=mod_of(event),
          x=event_client_x(event),
          y=event_client_y(event),
          vx=event_local_x(event),
          vy=event_local_y(event),
          button=event_button(event),
          buttons=event_buttons(event),
          pointer_id=event_pointer_id(event),
        ))
        "pointermove" => Some(@shared.Event::pointer(PointerMove,
          mod=mod_of(event),
          x=event_client_x(event),
          y=event_client_y(event),
          vx=event_local_x(event),
          vy=event_local_y(event),
          button=event_button(event),
          buttons=event_buttons(event),
          pointer_id=event_pointer_id(event),
        ))
        "pointercancel" => Some(@shared.Event::pointer(PointerCancel,
          mod=mod_of(event),
          x=event_client_x(event),
          y=event_client_y(event),
          vx=event_local_x(event),
          vy=event_local_y(event),
          button=event_button(event),
          buttons=event_buttons(event),
          pointer_id=event_pointer_id(event),
        ))
        "keydown" => Some(@shared.Event::new(KeyDown, Key({
          mod: mod_of(event),
          key: event_key(event),
          code: event_code(event),
        })))
        "keyup" => Some(@shared.Event::new(KeyUp, Key({
          mod: mod_of(event),
          key: event_key(event),
          code: event_code(event),
        })))
        _ => None
      }
    }
    match self.nodes.get(payload.nid) {
      Some(entry) => {
        match entry.listeners.get(payload.id) {
          Some(prev) => {
            unbind_host_listener(entry.node, prev)
            entry.listeners.remove(payload.id)
          }
          None => ()
        }
        if !payload.bind { return }
        let name = match payload.kind {
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
        let handle = bind_host_listener(
          entry.node,
          name,
          payload.cfg.capture,
          payload.cfg.stop,
          payload.cfg.prevent,
          event => match event_of(name, event, entry.node) {
            Some(event) => ignore(@js_async.Promise::from_async(
              () => { ignore(conn.send_req(Trigger({ node: payload.nid, event }))) }
            ))
            None => ()
          },
        )
        entry.listeners.set(payload.id, handle)
      }
      None => ()
    }
  }
  match cmd {
    Create({ id, tag, ns, value }) => {
      let text = match value { Empty => None; String(v) => Some(v) }
      self.nodes.set(id, {
        node: create_host_node(tag, text, ns),
        parent: 0,
        children: [],
        listeners: Map::new(),
      })
    }
    Insert({ parent, child, target, after }) => insert(parent, child, target, after)
    Remove(id) => remove_tree(id)
    Attr(id, key, value) => match self.nodes.get(id) {
      Some(entry) => set_host_attr(entry.node, key, match value { Empty => None; String(v) => Some(v) })
      None => ()
    }
    Style(id, key, value) => match self.nodes.get(id) {
      Some(entry) => set_host_style(entry.node, key, match value { Empty => None; String(v) => Some(v) })
      None => ()
    }
    Prop(id, key, value) => match self.nodes.get(id) {
      Some(entry) => match value {
        Empty => clear_host_prop(entry.node, key)
        String(v) => set_host_prop_string(entry.node, key, v)
        Int(v) => set_host_prop_int(entry.node, key, v)
        Float(v) => set_host_prop_float(entry.node, key, v.to_double())
      }
      None => ()
    }
    Listener(payload) => bind(payload)
    Pointer(payload) => match self.nodes.get(payload.id) {
      Some(entry) => set_pointer_capture(entry.node, payload.pointer_id, payload.capture)
      None => ()
    }
    Focus(payload) => match self.nodes.get(payload.id) {
      Some(entry) => set_host_focus(entry.node, payload.focus)
      None => ()
    }
  }
}
fn HostDom::apply_batch(
  self: HostDom,
  conn: Conn,
  value: Json,
) -> Unit {
  match value {
    Array(items) => for i in 0..<items.length() {
      let cmd: @shared.DomCmd = from_json(items[i]) catch {
        _ => { console_error("invalid dom cmd"); continue }
      }
      self.apply(conn, cmd)
    }
    _ => ()
  }
}
fn HostDom::reset(self: HostDom) -> Unit {
  fn detach(id: Int) -> Unit {
    match self.nodes.get(id) {
      Some(child) => {
        if child.parent > 0 {
          match self.nodes.get(child.parent) {
            Some(parent) => {
              let mut i = 0
              while i < parent.children.length() {
                if parent.children[i] == id {
                  ignore(parent.children.remove(i))
                  break
                }
                i += 1
              }
            }
            None => ()
          }
          child.parent = 0
        }
      }
      None => ()
    }
  }
  fn remove_tree(id: Int) -> Unit {
    match self.nodes.get(id) {
      Some(entry) => {
        let child_ids = entry.children.copy()
        for child in child_ids { remove_tree(child) }
        detach(id)
        remove_host_node(entry.node)
        self.nodes.remove(id)
      }
      None => ()
    }
  }
  let ids = []
  for id, _ in self.nodes { ids.push(id) }
  for id in ids { remove_tree(id) }
  clear_host_children(body_root())
  self.nodes.clear()
}
fn HostDom::point_of(self: HostDom, id: Int) -> Json? {
  match self.nodes.get(id) {
    Some(entry) => point_of_host_node(entry.node)
    None => None
  }
}

struct Conn {
  inbound: @aqueue.Queue[Incoming]
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
fn Conn::new() -> Conn {{
  inbound: @aqueue.Queue::new(kind=Unbounded),
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
fn Conn::status(self: Conn) -> Json {
  let obj = Map::new()
  obj.set("state", self.state.to_json())
  match self.reason {
    Some(reason) => obj.set("reason", reason.to_json())
    None => ()
  }
  Json::object(obj)
}
async fn Conn::send_req(self: Conn, body: @shared.Req) -> @shared.Res raise {
  fn socket_open() -> Bool {
    match self.ws {
      Some(ws) => socket_ready_state(ws) == 1
      None => false
    }
  }
  fn next_id() -> Int {
    let id = self.next_id
    self.next_id += 1
    id
  }
  fn send(id: Int, body: @shared.Req) -> Unit raise {
    let msg: @shared.ReqMsg = { id, body }
    match self.ws {
      Some(ws) => {
        if socket_ready_state(ws) != 1 { fail("bridge is not connected") }
        socket_send_json(ws, msg.to_json())
      }
      None => fail("bridge is not connected")
    }
  }
  guard socket_open() else { fail("bridge is not connected") }
  let id = next_id()
  let pending = { q: @aqueue.Queue::new(kind=Unbounded) }
  self.pending.set(id, pending)
  try {
    send(id, body)
    match pending.q.get() {
      Ok(value) => value
      Err(msg) => fail(msg)
    }
  } catch {
    err => {
      self.pending.remove(id)
      raise err
    }
  }
}
fn Conn::connect(self: Conn) -> Unit {
  fn socket_live() -> Bool {
    match self.ws {
      Some(ws) => {
        let state = socket_ready_state(ws)
        state == 0 || state == 1
      }
      None => false
    }
  }
  fn clear_reconnect() -> Unit {
    match self.reconnect_timer {
      Some(timer) => {
        clear_timer(timer)
        self.reconnect_timer = None
      }
      None => ()
    }
  }
  if socket_live() { return }
  self.should_reconnect = true
  clear_reconnect()
  self.state = "connecting"
  self.reason = None
  self.ws = Some(connect_socket(
    ws_url(),
    () => ignore(self.inbound.try_put(Open) catch { _ => false }),
    value => ignore(self.inbound.try_put(Message(value)) catch { _ => false }),
    () => ignore(self.inbound.try_put(Closed) catch { _ => false }),
    msg => ignore(self.inbound.try_put(Error(msg)) catch { _ => false }),
  ))
}
fn Conn::handle(
  self: Conn,
  host: HostDom,
  msg: Incoming,
) -> Unit {
  fn queue(msg: Incoming) -> Unit {
    ignore(self.inbound.try_put(msg) catch { _ => false })
  }
  fn next_id() -> Int {
    let id = self.next_id
    self.next_id += 1
    id
  }
  fn clear_ping() -> Unit {
    match self.ping_timer {
      Some(timer) => {
        clear_timer(timer)
        self.ping_timer = None
      }
      None => ()
    }
  }
  fn clear_reconnect() -> Unit {
    match self.reconnect_timer {
      Some(timer) => {
        clear_timer(timer)
        self.reconnect_timer = None
      }
      None => ()
    }
  }
  fn reset_ping() -> Unit { self.ping_id = 0 }
  fn settle(id: Int, res: PendingRes) -> Bool {
    match self.pending.get(id) {
      Some(pending) => {
        self.pending.remove(id)
        ignore(pending.q.try_put(res) catch { _ => false })
        true
      }
      None => false
    }
  }
  fn reject(msg: String) -> Unit {
    let ids = []
    for id, _ in self.pending { ids.push(id) }
    for id in ids {
      match self.pending.get(id) {
        Some(pending) => {
          self.pending.remove(id)
          ignore(pending.q.try_put(Err(msg)) catch { _ => false })
        }
        None => ()
      }
    }
  }
  fn send(id: Int, body: @shared.Req) -> Unit raise {
    let msg: @shared.ReqMsg = { id, body }
    match self.ws {
      Some(ws) => {
        if socket_ready_state(ws) != 1 { fail("bridge is not connected") }
        socket_send_json(ws, msg.to_json())
      }
      None => fail("bridge is not connected")
    }
  }
  fn open() -> Unit {
    host.reset()
    self.should_reconnect = true
    clear_reconnect()
    clear_ping()
    self.ping_timer = Some(set_interval_ms(2000, () => queue(Ping)))
    reset_ping()
    self.state = "connected"
    self.reason = None
    queue(Ping)
  }
  fn schedule_reconnect() -> Unit {
    if !self.should_reconnect || self.reconnect_timer is Some(_) { return }
    self.state = "reconnecting"
    self.reconnect_timer = Some(set_timeout_ms(300, () => queue(Reconnect)))
  }
  fn handle_res(res: @shared.ResMsg) -> Unit {
    match res.body {
      HelloAck(_) => open()
      Pong => if self.ping_id == res.id { reset_ping() }
      Query(value) => ignore(settle(res.id, PendingRes::Ok(Query(value))))
      Cli(value) => ignore(settle(res.id, PendingRes::Ok(Cli(value))))
      Ok => ignore(settle(res.id, PendingRes::Ok(@shared.Res::Ok)))
      Err(msg) => {
        if settle(res.id, Err(msg)) { return }
        self.should_reconnect = false
        reject(msg)
        reset_ping()
        clear_reconnect()
        self.state = "rejected"
        self.reason = Some(msg)
        match self.ws {
          Some(ws) => socket_close(ws)
          None => ()
        }
      }
    }
  }
  match msg {
    Open => try {
      send(next_id(), Hello({ role: Browser, session: ensure_session_id(session_key) }))
    } catch { err => console_error(err.to_string()) }
    Message(value) => match value {
      Array(_) => host.apply_batch(self, value)
      Object(_) => {
        let res: @shared.ResMsg = from_json(value) catch {
          _ => { console_error("invalid response packet"); return }
        }
        handle_res(res)
      }
      _ => ()
    }
    Closed => {
      self.ws = None
      reject("bridge disconnected")
      if self.state == "rejected" { return }
      self.state = "disconnected"
      reset_ping()
      schedule_reconnect()
    }
    Error(msg) => console_error(msg)
    Ping => {
      match self.ws {
        Some(ws) if socket_ready_state(ws) == 1 && self.ping_id == 0 => {
          let id = next_id()
          self.ping_id = id
          try { send(id, Ping) } catch { err => console_error(err.to_string()) }
        }
        _ => ()
      }
    }
    Reconnect => {
      self.reconnect_timer = None
      self.connect()
    }
  }
}

struct Bridge { host: HostDom; conn: Conn }
fn Bridge::new() -> Bridge {{ host: HostDom::new(), conn: Conn::new() }}
fn Bridge::start(self: Bridge) -> Unit {
  self.install()
  self.conn.connect()
}
fn Bridge::status(self: Bridge) -> Json { self.conn.status() }
async fn Bridge::call(self: Bridge, call: BridgeCall) -> Json raise {
  match call {
    Query(path, query) => {
      let query: @shared.NodeQuery = from_json(query)
      match self.conn.send_req(Query({ path, query })) {
        Query(value) => value.to_json()
        _ => fail("invalid query response")
      }
    }
    Dispatch(path, event) => {
      let event: @shared.Event = from_json(event)
      match self.conn.send_req(Dispatch({ path, event })) {
        Ok => true.to_json()
        _ => fail("invalid dispatch response")
      }
    }
    Cli(cmd, arg) => {
      let line = if arg == "" { cmd } else { "\{cmd} \{arg}" }
      match self.conn.send_req(Cli(line)) {
        Cli(v) => v.to_json()
        _ => "".to_json()
      }
    }
    Reset(root) => {
      self.host.reset()
      self.conn.reason = None
      self.conn.ping_id = 0
      ignore(self.conn.send_req(Cli(if root == "" { "reset" } else { "reset \{root}" })))
      true.to_json()
    }
  }
}
fn Bridge::install(self: Bridge) -> Unit {
  install_bridge_api(
    () => self.status(),
    () => @js_async.Promise::from_async(() => { self.conn.connect() }),
    (path, query) => @js_async.Promise::from_async(() => self.call(Query(path, query))),
    (path, event) => @js_async.Promise::from_async(() => self.call(Dispatch(path, event))),
    (cmd, arg) => @js_async.Promise::from_async(() => match self.call(Cli(cmd, arg)) {
      String(v) => v
      _ => ""
    }),
    root => @js_async.Promise::from_async(() => { ignore(self.call(Reset(root))) }),
    id => self.host.point_of(id),
  )
}
fn Bridge::handle(self: Bridge, msg: Incoming) -> Unit {
  self.conn.handle(self.host, msg)
}

let bridge: Bridge = Bridge::new()

async fn main {
  bridge.start()
  for ;; { bridge.handle(bridge.conn.inbound.get()) }
}

using @async {}
using @js_async { type Promise }
using @json { from_json, parse }
using @shared {
  type Box, type Read, type ReadValue, type Scroll,
  type DomCmd, type Event, type EventKind, type ListenerCmd, type Modify,
  type NodeQuery, type Req, type ReqMsg, type Res, type ResMsg,
}

let dom_root_head: Int = 1
let dom_root_body: Int = 2
let session_key: String = "mbt_bridge_session_id"
let event_kinds: Array[EventKind] = [
  Click, Input, Change, Focus, Blur, KeyDown, KeyUp,
  PointerDown, PointerUp, PointerMove, PointerCancel,
]
let event_kind_map: Map[String, EventKind] = {
  let map = Map::new(); for kind in event_kinds {
    if kind.to_json() is String(name) { map.set(name.to_lower(), kind) }
  }; map
}
fn kick_async() -> Unit { ignore(Promise::from_async(() => ())) }

struct HostEntry {
  node: HostNode
  mut parent: Int
  children: Array[Int]
  listeners: Map[Int, ListenerHandle]
}

struct PendingReq { q: @aqueue.Queue[Result[Res, String]] }

struct HostDom { nodes: Map[Int, HostEntry] }
fn HostDom::new() -> HostDom {{ nodes: Map::new() }}
fn HostDom::apply(
  self: HostDom,
  conn: Conn,
  cmd: DomCmd,
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
  fn bind(payload: ListenerCmd) -> Unit {
    fn mod_of(event: HostEvent) -> Modify {
      Modify::new(
        ctrl=event_ctrl_key(event),
        shift=event_shift_key(event),
        alt=event_alt_key(event),
        meta=event_meta_key(event),
      )
    }
    fn pointer_of(kind: EventKind, event: HostEvent) -> Event {
      Event::pointer(kind,
        mod=mod_of(event),
        x=event_client_x(event),
        y=event_client_y(event),
        vx=event_local_x(event),
        vy=event_local_y(event),
        button=event_button(event),
        buttons=event_buttons(event),
        pointer_id=event_pointer_id(event),
      )
    }
    fn event_name(kind: EventKind) -> String {
      match kind.to_json() { String(name) => name.to_lower(); _ => "" }
    }
    fn event_of(kind: EventKind, event: HostEvent, node: HostNode) -> Event {
      match kind {
        Click | Focus | Blur => Event::pointer(kind)
        Change | Input => Event::new(kind, Input({ value: node_value(node) }))
        PointerDown | PointerUp | PointerMove | PointerCancel => pointer_of(kind, event)
        KeyDown | KeyUp => Event::new(kind, Key({
          mod: mod_of(event), key: event_key(event), code: event_code(event),
        }))
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
        let name = event_name(payload.kind)
        let handle = bind_host_listener(
          entry.node,
          name,
          payload.cfg.capture,
          payload.cfg.stop,
          payload.cfg.prevent,
          event => match event_kind_map.get(name) {
            Some(kind) => ignore(Promise::from_async(
              () => {
                let event = event_of(kind, event, entry.node)
                ignore(conn.send_req(Trigger({ node: payload.nid, event })))
              }
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
    Reset => self.reset()
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
fn HostDom::point_of(self: HostDom, id: Int) -> String? {
  match self.nodes.get(id) {
    Some(entry) => point_of_host_node(entry.node)
    None => None
  }
}
fn HostDom::read(self: HostDom, reads: Array[Read]) -> Array[ReadValue] {
  fn node(id: Int) -> HostNode? {
    match self.nodes.get(id) {
      Some(entry) => Some(entry.node)
      None => if id == dom_root_body { Some(body_root()) }
      else if id == dom_root_head { Some(head_root()) }
      else { None }
    }
  }
  fn parse_box(json: String?) -> Box? {
    match json {
      Some(json) => Some(from_json(parse(json)) catch { _ => return None })
      None => None
    }
  }
  fn parse_scroll(json: String?) -> Scroll? {
    match json {
      Some(json) => Some(from_json(parse(json)) catch { _ => return None })
      None => None
    }
  }
  let values = []
  for read in reads {
    match read {
      Box(id) => values.push(ReadValue::Box(match node(id) {
        Some(node) => parse_box(box_of_host_node(node))
        None => None
      }))
      View(id) => values.push(ReadValue::View(match node(id) {
        Some(node) => parse_box(view_of_host_node(node))
        None => None
      }))
      Scroll(id) => values.push(ReadValue::Scroll(match node(id) {
        Some(node) => parse_scroll(scroll_of_host_node(node))
        None => None
      }))
      Text(font, texts) => values.push(ReadValue::Text(Some(measure_host_texts(font, texts))))
    }
  }
  values
}

struct Conn {
  pending: Map[Int, PendingReq]; session: String; mut next_id: Int; mut ws: HostSocket?; mut ping_id: Int
  mut ping_timer: TimerHandle?; mut reconnect_timer: TimerHandle?
  mut should_reconnect: Bool; mut state: String; mut reason: String?
}
fn Conn::new() -> Conn {{
  pending: Map::new(), session: ensure_session_id(session_key),
  next_id: 1, ws: None, ping_id: 0, ping_timer: None,
  reconnect_timer: None, should_reconnect: true, state: "idle", reason: None,
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
async fn Conn::send_req(self: Conn, body: Req) -> Res raise {
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
  guard socket_open() else { fail("bridge is not connected") }
  let id = next_id()
  let pending = { q: @aqueue.Queue::new(kind=Unbounded) }
  self.pending.set(id, pending)
  try {
    self.send(id, body)
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
fn Conn::settle(self: Conn, id: Int, res: Result[Res, String]) -> Bool {
  match self.pending.get(id) {
    Some(pending) => {
      self.pending.remove(id)
      ignore(pending.q.try_put(res) catch { _ => false })
      kick_async()
      true
    }
    None => false
  }
}
fn Conn::reject(self: Conn, msg: String) -> Unit {
  let ids = []
  for id, _ in self.pending { ids.push(id) }
  for id in ids {
    match self.pending.get(id) {
      Some(pending) => {
        self.pending.remove(id)
        ignore(pending.q.try_put(Result::Err(msg)) catch { _ => false })
        kick_async()
      }
      None => ()
    }
  }
}
fn Conn::clear_ping(self: Conn) -> Unit {
  match self.ping_timer {
    Some(timer) => {
      clear_timer(timer)
      self.ping_timer = None
    }
    None => ()
  }
}
fn Conn::clear_reconnect(self: Conn) -> Unit {
  match self.reconnect_timer {
    Some(timer) => {
      clear_timer(timer)
      self.reconnect_timer = None
    }
    None => ()
  }
}
fn Conn::reset_ping(self: Conn) -> Unit { self.ping_id = 0 }
fn Conn::send_json(self: Conn, json: Json) -> Unit raise {
  match self.ws {
    Some(ws) => {
      if socket_ready_state(ws) != 1 { fail("bridge is not connected") }
      socket_send_text(ws, json.stringify())
    }
    None => fail("bridge is not connected")
  }
}
fn Conn::send(self: Conn, id: Int, body: Req) -> Unit raise {
  self.send_json(({ id, body }: ReqMsg).to_json())
}
fn Conn::reply(self: Conn, id: Int, body: Res) -> Unit raise {
  self.send_json(({ id, body }: ResMsg).to_json())
}
fn Conn::on_open(self: Conn) -> Unit {
  let id = self.next_id
  self.next_id += 1
  try { self.send(id, Hello({ role: Browser, session: self.session })) }
  catch { err => console_error(err.to_string()) }
}
fn Conn::on_connected(self: Conn, host: HostDom) -> Unit {
  host.reset()
  self.should_reconnect = true
  self.clear_reconnect()
  self.clear_ping()
  self.ping_timer = Some(set_interval_ms(2000, () => self.ping()))
  self.reset_ping()
  self.state = "connected"
  self.reason = None
  self.ping()
}
fn Conn::on_closed(self: Conn, host: HostDom) -> Unit {
  self.ws = None
  self.reject("bridge disconnected")
  if self.state == "rejected" { return }
  self.state = "disconnected"
  self.reset_ping()
  self.schedule_reconnect(host)
}
fn Conn::on_error(self: Conn, msg: String) -> Unit {
  console_error(msg)
  match self.ws { Some(ws) => socket_close(ws); None => () }
}
fn Conn::handle_res(self: Conn, host: HostDom, res: ResMsg) -> Unit {
  match res.body {
    DomCmd(cmd) => host.apply(self, cmd)
    DomCmds(cmds) => for cmd in cmds { host.apply(self, cmd) }
    HelloAck(_) => self.on_connected(host)
    Pong => if self.ping_id == res.id { self.reset_ping() }
    QueryRes(v) => ignore(self.settle(res.id, Result::Ok(QueryRes(v))))
    ReadRes(v) => ignore(self.settle(res.id, Result::Ok(ReadRes(v))))
    CliRes(v) => ignore(self.settle(res.id, Result::Ok(CliRes(v))))
    Ok => ignore(self.settle(res.id, Result::Ok(Ok)))
    Err(msg) => {
      if self.settle(res.id, Result::Err(msg)) { return }
      self.should_reconnect = false
      self.reject(msg)
      self.reset_ping()
      self.clear_reconnect()
      self.state = "rejected"
      self.reason = Some(msg)
      match self.ws {
        Some(ws) => socket_close(ws)
        None => ()
      }
    }
  }
}
fn Conn::on_message(self: Conn, host: HostDom, text: String) -> Unit {
  let value = parse(text) catch {
    _ => { console_error("invalid websocket json"); return }
  }
  match value {
    Object(_) => {
      match (match value { Object(obj) => obj.get("body"); _ => None }) {
        Some(Array([String("ReadReq"), _])) => {
          let req: ReqMsg = from_json(value) catch { _ => { console_error("invalid request packet"); return } }
          let res = match req.body {
            ReadReq({ browser, reads }) => if browser == self.session { Res::ReadRes(host.read(reads)) }
              else { Res::Err("wrong_browser") }
            _ => Res::Err("unsupported_browser_req")
          }
          try { self.reply(req.id, res) } catch { err => console_error(err.to_string()) }
        }
        _ => {
          let res: ResMsg = from_json(value) catch { _ => { console_error("invalid response packet"); return } }
          self.handle_res(host, res)
        }
      }
    }
    _ => ()
  }
}
fn Conn::ping(self: Conn) -> Unit {
  match self.ws {
    Some(ws) if socket_ready_state(ws) == 1 && self.ping_id == 0 => {
      let id = self.next_id
      self.next_id += 1
      self.ping_id = id
      try { self.send(id, Ping) } catch { err => console_error(err.to_string()) }
    }
    _ => ()
  }
}
fn Conn::schedule_reconnect(self: Conn, host: HostDom) -> Unit {
  if !self.should_reconnect || self.reconnect_timer is Some(_) { return }
  self.state = "reconnecting"
  self.reconnect_timer = Some(set_timeout_ms(300, () => {
    self.reconnect_timer = None
    self.connect(host)
  }))
}
fn Conn::connect(self: Conn, host: HostDom) -> Unit {
  fn socket_live() -> Bool {
    match self.ws {
      Some(ws) => {
        let state = socket_ready_state(ws)
        state == 0 || state == 1
      }
      None => false
    }
  }
  if socket_live() { return }
  self.should_reconnect = true
  self.clear_reconnect()
  self.state = "connecting"
  self.reason = None
  self.ws = Some(connect_socket(
    ws_url(),
    () => self.on_open(),
    value => self.on_message(host, value),
    () => self.on_closed(host),
    msg => self.on_error(msg),
  ))
}

struct Bridge { host: HostDom; conn: Conn }
fn Bridge::new() -> Bridge {{ host: HostDom::new(), conn: Conn::new() }}
fn Bridge::status(self: Bridge) -> String { self.conn.status().stringify() }
async fn Bridge::query(self: Bridge, path: String, value: String) -> String raise {
  let query: NodeQuery = from_json(parse(value))
  match self.conn.send_req(QueryReq({ browser: self.conn.session, path, query })) {
    QueryRes(value) => value.to_json().stringify()
    _ => fail("invalid query response")
  }
}
async fn Bridge::read(self: Bridge, value: String) -> String raise {
  let items: Array[Read] = from_json(parse(value))
  match self.conn.send_req(ReadReq({ browser: self.conn.session, reads: items })) {
    ReadRes(value) => value.to_json().stringify()
    _ => fail("invalid read response")
  }
}
async fn Bridge::dispatch(self: Bridge, path: String, value: String) -> String raise {
  let event: Event = from_json(parse(value))
  match self.conn.send_req(Dispatch({ browser: self.conn.session, path, event })) {
    Ok => true.to_json().stringify()
    _ => fail("invalid dispatch response")
  }
}
async fn Bridge::cli(self: Bridge, cmd: String, arg: String) -> Json raise {
  let line = if arg == "" { cmd } else { "\{cmd} \{arg}" }
  match self.conn.send_req(CliReq(line)) {
    CliRes(value) => value.to_json()
    _ => "".to_json()
  }
}
async fn Bridge::reset(self: Bridge, root: String) -> String raise {
  self.conn.reason = None
  self.conn.ping_id = 0
  ignore(self.conn.send_req(CliReq(if root == "" { "reset" } else { "reset \{root}" })))
  true.to_json().stringify()
}
let bridge: Bridge = Bridge::new()
fn install_bridge() -> Unit {
  install_bridge_api(
    () => bridge.status(),
    () => Promise::from_async(() => bridge.conn.connect(bridge.host)),
    (path, query) => Promise::from_async(() => bridge.query(path, query)),
    reads => Promise::from_async(() => bridge.read(reads)),
    (path, event) => Promise::from_async(() => bridge.dispatch(path, event)),
    (cmd, arg) => Promise::from_async(() => match bridge.cli(cmd, arg) {
      String(v) => v
      _ => ""
    }),
    root => Promise::from_async(() => bridge.reset(root)),
    id => bridge.host.point_of(id),
  )
}
fn main {
  install_bridge()
  bridge.conn.connect(bridge.host)
}

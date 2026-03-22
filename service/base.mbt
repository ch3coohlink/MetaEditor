// ======== 常量和外部接口 ========
let nil_at : Int64 = -1L
let default_port : Int = 8080
let max_port_tries : Int = 32
let lock_file_name : String = ".meta-editor-service.lock"
let state_file_name : String = ".meta-editor-service.json"
let pid_file_name : String = ".meta-editor-service.pid"
let state_file_size : Int = 1024
let control_path : String = "/_meta/command"

extern "C" fn temp_dir_ffi() -> String? = "metaeditor_service_get_tmp_path"
extern "C" fn current_pid_ffi() -> Int = "metaeditor_service_current_pid"

// ======== 核心类型 ========
pub(all) enum RejectReason {
  UnsupportedRole
  MissingSessionId
  SessionBusy
} derive(Eq, Show)

pub(all) enum HelloResult {
  Ack(Bool)
  Rejected(RejectReason)
} derive(Eq, Show)

pub(all) struct ServiceState {
  session_id : Ref[String]
  browser_connected : Ref[Bool]
  disconnected_at : Ref[Int64]
}

pub(all) struct SessionView {
  connected : Bool
  locked : Bool
  session_id : String
  disconnected_at : Int64
} derive(Eq, Show, ToJson)

struct Runtime {
  state : ServiceState
  root_dir : String
  ui_history : Array[Json]
  app_actions : Map[String, Int]
  next_conn_id : Ref[Int]
  active_conn_id : Ref[Int]
  browser_ws : Ref[@websocket.Conn?]
  live_batches : @aqueue.Queue[Json]
  stop_service : Ref[(() -> Unit)?]
  stop_requested : Ref[Bool]
  shutting_down : Ref[Bool]
}

struct ServiceLock {
  file : @fs.File
}

suberror ServiceError {
  ServiceError(String)
} derive(Show, ToJson)

// ======== session 和运行时 ========
pub fn new_state() -> ServiceState {
  {
    session_id: Ref::new(""),
    browser_connected: Ref::new(false),
    disconnected_at: Ref::new(nil_at),
  }
}

pub fn make_runtime(root_dir : String) -> Runtime {
  {
    state: new_state(),
    root_dir,
    ui_history: [],
    app_actions: {},
    next_conn_id: Ref::new(1),
    active_conn_id: Ref::new(0),
    browser_ws: Ref::new(None),
    live_batches: @aqueue.Queue::new(kind=Unbounded),
    stop_service: Ref::new(None),
    stop_requested: Ref::new(false),
    shutting_down: Ref::new(false),
  }
}

pub fn session_state(state : ServiceState) -> SessionView {
  let session_id = state.session_id.val
  {
    connected: state.browser_connected.val,
    locked: session_id != "",
    session_id,
    disconnected_at: state.disconnected_at.val,
  }
}

pub fn accept_hello(
  state : ServiceState,
  role : String,
  session_id : String,
  _user_agent : String,
) -> HelloResult {
  if role != "browser" { return Rejected(UnsupportedRole) }
  if session_id == "" { return Rejected(MissingSessionId) }
  if state.browser_connected.val { return Rejected(SessionBusy) }
  let reconnected = state.session_id.val == session_id
  if state.session_id.val != "" && !reconnected { return Rejected(SessionBusy) }
  state.session_id.val = session_id
  state.browser_connected.val = true
  state.disconnected_at.val = nil_at
  Ack(reconnected)
}

pub fn disconnect_browser(state : ServiceState, at : Int64) -> Unit {
  state.browser_connected.val = false
  state.disconnected_at.val = at
}

fn reject_reason_code(reason : RejectReason) -> String {
  match reason {
    UnsupportedRole => "unsupported_role"
    MissingSessionId => "missing_session_id"
    SessionBusy => "session_busy"
  }
}

fn invoke_stop_service(_runtime : Runtime) -> Unit {
  @sys.exit(0)
}

fn request_stop_service(runtime : Runtime) -> Unit {
  if runtime.shutting_down.val {
    return
  }
  runtime.shutting_down.val = true
  runtime.stop_requested.val = true
  runtime.live_batches.close(clear=true)
}

// ======== 本地路径和锁文件 ========
fn temp_dir() -> String {
  match temp_dir_ffi() {
    Some(path) => path
    None => abort("failed to get temp dir")
  }
}

fn current_pid() -> Int {
  current_pid_ffi()
}

fn temp_file(name : String) -> String {
  let dir = temp_dir()
  match dir {
    [.., .. "/"] | [.., .. "\\"] => "\{dir}\{name}"
    _ => "\{dir}/\{name}"
  }
}

pub fn service_state_path() -> String { temp_file(state_file_name) }
pub fn service_lock_path() -> String { temp_file(lock_file_name) }
pub fn service_pid_path() -> String { temp_file(pid_file_name) }

pub async fn try_acquire_service_lock() -> ServiceLock? raise {
  let file = @fs.open(service_lock_path(), mode=ReadWrite, create=0o644)
  let locked = file.try_lock(Exclusive)
  if !locked {
    file.close()
    return None
  }
  Some({ file: file })
}

pub async fn acquire_service_lock() -> ServiceLock raise {
  match try_acquire_service_lock() {
    Some(lock) => lock
    None => raise ServiceError("service already running")
  }
}

pub fn release_service_lock(lock : ServiceLock) -> Unit {
  lock.file.unlock()
  lock.file.close()
}

async fn write_service_state(port : Int) -> Unit {
  let text = Json::object({ "port": port.to_json() }).stringify()
  let padded = if text.length() < state_file_size {
    text + " ".repeat(state_file_size - text.length())
  } else {
    text
  }
  @fs.write_file(service_state_path(), @utf8.encode(padded), create=0o644, truncate=true)
}

async fn clear_service_state_file() -> Unit {
  let path = service_state_path()
  if @fs.exists(path) {
    @fs.remove(path)
  }
}

pub fn parse_service_port_text(text : String) -> Int raise {
  let state = @json.parse(text.trim())
  match json_int(state, "port") {
    Some(port) => port
    None => raise ServiceError("invalid service state file")
  }
}

async fn read_service_port() -> Int raise {
  let path = service_state_path()
  if !@fs.exists(path) {
    raise ServiceError("service is not running")
  }
  parse_service_port_text(@fs.read_file(path).text())
}

async fn write_service_pid(pid : Int) -> Unit {
  @fs.write_file(service_pid_path(), @utf8.encode("\{pid}"), create=0o644, truncate=true)
}

async fn remove_service_pid() -> Unit {
  let path = service_pid_path()
  if @fs.exists(path) {
    @fs.remove(path)
  }
}

pub fn parse_service_pid_text(text : String) -> Int raise {
  let parsed : Result[Int, _] = try? @strconv.parse_int(text.trim())
  match parsed {
    Ok(pid) => pid
    Err(_) => raise ServiceError("invalid service pid file")
  }
}

// ======== JSON、HTTP 和静态文件辅助 ========
fn root_file(runtime : Runtime, path : String) -> String {
  if runtime.root_dir == "." {
    path
  } else {
    "\{runtime.root_dir}/\{path}"
  }
}

fn content_type(path : String) -> String {
  match path {
    [.., .. ".html"] => "text/html"
    [.., .. ".js"] => "text/javascript"
    [.., .. ".css"] => "text/css"
    _ => "text/plain"
  }
}

fn json_field(json : Json, key : String) -> Json? {
  match json { Object(m) => m.get(key); _ => None }
}

fn json_string(json : Json, key : String) -> String? {
  match json_field(json, key) { Some(String(v)) => Some(v); _ => None }
}

fn json_int(json : Json, key : String) -> Int? {
  match json_field(json, key) {
    Some(v) =>
      match (try? @json.from_json(v) : Result[Int, _]) { Ok(n) => Some(n); _ => None }
    _ => None
  }
}

fn json_bool(json : Json, key : String) -> Bool? {
  match json_field(json, key) { Some(True) => Some(true); Some(False) => Some(false); _ => None }
}

pub async fn respond_json(
  conn : @http.ServerConnection,
  status : Int,
  reason : String,
  payload : Json,
) -> Unit {
  let _ = try {
    conn
    ..send_response(status, reason, extra_headers={ "Content-Type": "application/json" })
    ..write(payload.stringify())
    .end_response()
  } catch {
    _ => ()
  }
}

pub async fn respond_ok(conn : @http.ServerConnection, result : Json) -> Unit {
  respond_json(conn, 200, "OK", { "ok": true, "result": result })
}

pub async fn respond_err(
  conn : @http.ServerConnection,
  status : Int,
  reason : String,
  msg : String,
) -> Unit {
  respond_json(conn, status, reason, { "ok": false, "error": msg })
}

async fn serve_file(runtime: Runtime, conn: @http.ServerConnection, path: String) -> Unit {
  let full_path = root_file(runtime, path)
  if !@fs.exists(full_path) {
    respond_err(conn, 404, "NotFound", "Not Found")
    return
  }
  let body = @fs.read_file(full_path)
  let _ = try {
    conn
    ..send_response(200, "OK", extra_headers={
      "Content-Type": content_type(path),
      "Cache-Control": "no-cache",
    })
    ..write(body.binary())
    .end_response()
  } catch {
    _ => ()
  }
}

fn next_addr(addr: @socket.Addr, offset: Int) -> @socket.Addr {
  @socket.Addr::new(addr.ip(), addr.port() + offset)
}

pub fn bind_http_server(addr: @socket.Addr, max_tries: Int) -> @http.Server raise {
  let mut tries = 0
  let mut last_error: Error? = None
  while tries < max_tries {
    let candidate = next_addr(addr, tries)
    match (try? @http.Server::new(candidate) : Result[@http.Server, _]) {
      Ok(server) => return server
      Err(err) => {
        last_error = Some(err)
        tries += 1
      }
    }
  }
  match last_error {
    Some(err) => raise err
    None => raise ServiceError("failed to bind service port")
  }
}

// ======== host UI 和 action ========
fn action_callback_id(runtime: Runtime, name: String) -> Int? {
  runtime.app_actions.get(name)
}

fn track_batch(runtime: Runtime, cmds: Array[String]) -> Unit {
  let batch: Array[Json] = []
  for cmd in cmds {
    let json = @json.parse(cmd) catch { _ => null }
    if json is Array([Number(tag, ..), String(name), Number(callback_id, ..)]) {
      if tag == 8 {
        let parsed: Result[Int, _] = try? @json.from_json(callback_id.to_json())
        match parsed {
          Ok(id) => runtime.app_actions[name] = id
          Err(_) => ()
        }
      }
    }
    batch.push(json)
    runtime.ui_history.push(json)
  }
  let _ = runtime.live_batches.try_put(Json::array(batch)) catch { _ => false }
}

fn render_host_app(runtime: Runtime) -> @src.VNode {
  let stop_service = @src.reg_action("host_stop_service", fn() { request_stop_service(runtime) })
  @src.h("div", [
    ("style", @src.S("padding: 24px; font-family: sans-serif;"))
  ], [
    @src.Node(@src.h("h1", [], [@src.Str("MetaEditor Host")])),
    @src.Node(@src.h("div", [("style", @src.S("margin-bottom: 16px; color: #555;"))], [
      @src.Str("Service is running. Use the host action below to stop it.")
    ])),
    @src.Node(@src.h("button", [
      ("onclick", stop_service),
      ("style", @src.S("padding: 10px 14px; background: #b42318; color: white; border: none; border-radius: 8px; cursor: pointer;"))
    ], [@src.Str("Stop Service")]))
  ])
}

fn render_active_app(runtime: Runtime) -> @src.Child {
  runtime.app_actions.clear()
  @src.Node(render_host_app(runtime))
}

fn init_app(runtime: Runtime) -> Unit {
  @src.init_bridge(fn(cmds) { track_batch(runtime, cmds) })
  let _ = try {
    @src.scope(fn() {
      let root = @src.h("div", [], [@src.Dyn(fn() { render_active_app(runtime) })])
      @src.emit(@src.Append(0, root.id))
    })
  } catch {
    _ => fn() {}
  }
  let _ = try { @src.flush() } catch { _ => () }
}

pub fn init_app_for_test(runtime: Runtime) -> Unit {
  init_app(runtime)
}

pub fn ui_history_json(runtime: Runtime) -> Json {
  Json::array(runtime.ui_history)
}

async fn run_action(runtime: Runtime, name: String, settle_ms: Int) -> String raise {
  match action_callback_id(runtime, name) {
    Some(callback_id) => {
      @src.trigger_callback(callback_id)
      @async.sleep(settle_ms)
      "\{name}\n"
    }
    None => raise ServiceError("unknown action: \{name}")
  }
}

// ======== browser bridge ========
pub fn handle_event(data : Json) -> Unit {
  if json_int(data, "callback_id") is Some(id) {
    if json_string(data, "data") is Some(raw_ev) {
      @src.trigger_callback_ev(id, @src.EventData::from_json(raw_ev))
    } else {
      @src.trigger_callback(id)
    }
  }
}

async fn flush_live_batches(runtime: Runtime) -> Unit {
  for ;; {
    let batch = runtime.live_batches.get() catch {
      _ => return
    }
    match runtime.browser_ws.val {
      Some(ws) => {
        let _ = try { ws.send_text(batch.stringify()) } catch { _ => () }
      }
      None => ()
    }
  }
}

async fn send_json(ws: @websocket.Conn, json: Json) -> Unit {
  ws.send_text(json.stringify())
}

async fn reject_browser(ws: @websocket.Conn, reason: RejectReason) -> Unit {
  send_json(ws, { "type": "bridge:rejected", "reason": reject_reason_code(reason) })
  let _ = try { ws.send_close(reason=reject_reason_code(reason)) } catch { _ => () }
}

pub fn browser_init_messages(
  ui_history: Array[Json],
  session_id: String,
  reconnected: Bool,
) -> Array[Json] {
  let messages: Array[Json] = [
    { "type": "bridge:hello_ack", "session_id": session_id, "reconnected": reconnected },
  ]
  if ui_history.length() > 0 { messages.push(Json::array(ui_history)) }
  messages
}

async fn accept_browser(
  runtime: Runtime,
  ws: @websocket.Conn,
  conn_id: Int,
  session_id: String,
  reconnected: Bool,
) -> Unit {
  runtime.browser_ws.val = Some(ws)
  runtime.active_conn_id.val = conn_id
  for message in browser_init_messages(runtime.ui_history, session_id, reconnected) {
    send_json(ws, message)
  }
}

async fn handle_bridge_hello(
  runtime: Runtime,
  ws: @websocket.Conn,
  conn_id: Int,
  data: Json,
) -> Unit {
  let role = json_string(data, "role").unwrap_or("")
  let session_id = json_string(data, "session_id").unwrap_or("")
  let user_agent = json_string(data, "user_agent").unwrap_or("")
  match accept_hello(runtime.state, role, session_id, user_agent) {
    Ack(reconnected) => accept_browser(runtime, ws, conn_id, session_id, reconnected)
    Rejected(reason) => reject_browser(ws, reason)
  }
}

fn on_browser_disconnect(runtime: Runtime, conn_id: Int) -> Unit {
  if runtime.active_conn_id.val == conn_id {
    runtime.browser_ws.val = None
    runtime.active_conn_id.val = 0
    disconnect_browser(runtime.state, @async.now())
  }
}

async fn handle_browser_message(
  runtime: Runtime,
  ws: @websocket.Conn,
  conn_id: Int,
  data: Json,
) -> Unit {
  let kind = json_string(data, "type").unwrap_or("")
  match kind {
    "bridge:hello" => handle_bridge_hello(runtime, ws, conn_id, data)
    "event" | "event_data" => handle_event(data)
    _ => ()
  }
  if runtime.stop_requested.val {
    runtime.stop_requested.val = false
    invoke_stop_service(runtime)
  }
}

async fn serve_websocket(
  runtime: Runtime,
  request: @http.Request,
  conn: @http.ServerConnection,
) -> Unit {
  let ws = @websocket.from_http_server(request, conn)
  let conn_id = runtime.next_conn_id.val
  runtime.next_conn_id.val = conn_id + 1
  defer {
    on_browser_disconnect(runtime, conn_id)
    ws.close()
  }
  try {
    for ;; {
      let msg = ws.recv()
      match msg.kind {
        Text => handle_browser_message(runtime, ws, conn_id, msg.read_all().json())
        Binary => ()
      }
    }
  } catch {
    @websocket.ConnectionClosed(_, _) => ()
    _ => ()
  }
}

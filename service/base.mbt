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

pub(all) enum RejectReason {
  UnsupportedRole
  MissingSessionId
  SessionBusy
} derive(Eq, Show)

pub(all) enum HelloResult {
  Ack(Bool)
  Rejected(RejectReason)
} derive(Eq, Show)

pub(all) struct SessionView {
  connected : Bool
  locked : Bool
  session_id : String
  disconnected_at : Int64
} derive(Eq, Show, ToJson)

pub(all) struct ManagedAppInfo {
  id : String
  title : String
} derive(Eq, Show, ToJson)

pub(all) struct ServiceState {
  session_id : Ref[String]
  browser_connected : Ref[Bool]
  disconnected_at : Ref[Int64]
}

enum RequestResult {
  Ok(Json)
  Err(String)
}

struct Runtime {
  state : ServiceState
  root_dir : String
  apps : Array[ManagedAppInfo]
  active_app : @src.Store[String]
  preview_app : @src.Store[String]
  ui_history : Array[Json]
  app_actions : Map[String, Int]
  next_request_id : Ref[Int]
  next_conn_id : Ref[Int]
  active_conn_id : Ref[Int]
  browser_ws : Ref[@websocket.Conn?]
  live_batches : @aqueue.Queue[Json]
  responses : Map[Int, RequestResult]
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

pub fn new_state() -> ServiceState {
  {
    session_id: Ref::new(""),
    browser_connected: Ref::new(false),
    disconnected_at: Ref::new(nil_at),
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

fn managed_apps() -> Array[ManagedAppInfo] {
  [
    { id: "host", title: "MetaEditor Host" },
    { id: "counter", title: "Counter Test App" },
  ]
}

pub fn make_runtime(root_dir : String) -> Runtime {
  {
    state: new_state(),
    root_dir,
    apps: managed_apps(),
    active_app: @src.new_store("host"),
    preview_app: @src.new_store(""),
    ui_history: [],
    app_actions: {},
    next_request_id: Ref::new(1),
    next_conn_id: Ref::new(1),
    active_conn_id: Ref::new(0),
    browser_ws: Ref::new(None),
    live_batches: @aqueue.Queue::new(kind=Unbounded),
    responses: {},
    stop_service: Ref::new(None),
    stop_requested: Ref::new(false),
    shutting_down: Ref::new(false),
  }
}

pub fn default_active_app_id() -> String {
  make_runtime(".").active_app.read()
}

pub fn default_preview_app_id() -> String {
  make_runtime(".").preview_app.read()
}

pub fn default_managed_apps() -> Array[ManagedAppInfo] {
  managed_apps()
}

fn temp_dir() -> String {
  match temp_dir_ffi() {
    Some(path) => path
    None => abort("failed to get temp dir")
  }
}

fn current_pid() -> Int {
  current_pid_ffi()
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

fn session_json(runtime : Runtime) -> Json {
  session_state(runtime.state).to_json()
}

fn app_actions_json(runtime : Runtime) -> Json {
  let actions : Array[Json] = []
  for name in runtime.app_actions.keys() {
    actions.push(Json::string(name))
  }
  Json::array(actions)
}

fn enrich_ui_snapshot(runtime : Runtime, snapshot : Json) -> Json {
  match snapshot {
    Object(map) => {
      map["app_actions"] = app_actions_json(runtime)
      map["host"] = {
        "connected_browsers": if runtime.state.browser_connected.val { 1 } else { 0 },
        "command_history": runtime.ui_history.length(),
        "session": session_json(runtime),
      }
      Json::object(map)
    }
    _ => snapshot
  }
}

fn status_json(runtime : Runtime) -> Json {
  {
    "clients": if runtime.state.browser_connected.val { 1 } else { 0 },
    "browsers": if runtime.state.browser_connected.val { 1 } else { 0 },
    "cmd_history": runtime.ui_history.length(),
    "app_actions": app_actions_json(runtime),
    "active_app": runtime.active_app.read(),
    "preview_app": runtime.preview_app.read(),
    "apps": runtime.apps,
    "session": session_json(runtime),
  }
}

fn json_bool(json : Json, key : String) -> Bool? {
  match json_field(json, key) { Some(True) => Some(true); Some(False) => Some(false); _ => None }
}


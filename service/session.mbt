// extern "C" fn temp_dir_ffi() -> String? = "metaeditor_service_get_tmp_path"
// extern "C" fn current_pid_ffi() -> Int = "metaeditor_service_current_pid"
// #borrow(path)
// extern "C" fn retain_state_file_ffi(path : String) -> Bool = "metaeditor_service_retain_state_file"
// extern "C" fn release_state_file_ffi() -> Unit = "metaeditor_service_release_state_file"

// pub(all) enum RejectReason {
//   UnsupportedRole
//   MissingSessionId
//   SessionBusy
// } derive(Eq, Show)

// pub(all) enum HelloResult {
//   Ack(Bool)
//   Rejected(RejectReason)
// } derive(Eq, Show)

// pub(all) struct SessionView {
//   connected : Bool
//   locked : Bool
//   session_id : String
//   disconnected_at : Int64
// } derive(Eq, Show, ToJson)

// pub(all) struct ServiceLock {
//   file : @fs.File
// }

// struct ServiceStateFile {
//   pid : Int
//   port : Int
// } derive(FromJson)

// let state_dir_ref : Ref[String] = Ref::new(Session::temp_dir())

// pub struct Session {
//   session_id : Ref[String]
//   browser_connected : Ref[Bool]
//   disconnected_at : Ref[Int64]
//   next_conn_id : Ref[Int]
//   next_request_id : Ref[Int]
//   active_id : Ref[Int]
//   ws : Ref[@websocket.Conn?]
//   pending : Ref[Map[Int, @aqueue.Queue[Json]]]
// }

// pub fn Session::new() -> Session {
//   {
//     session_id: Ref::new(""),
//     browser_connected: Ref::new(false),
//     disconnected_at: Ref::new(nil_at),
//     next_conn_id: Ref::new(1),
//     next_request_id: Ref::new(1),
//     active_id: Ref::new(0),
//     ws: Ref::new(None),
//     pending: Ref::new(Map::new()),
//   }
// }

// pub fn Session::view(self : Session) -> SessionView {
//   let session_id = self.session_id.val
//   {
//     connected: self.browser_connected.val,
//     locked: session_id != "",
//     session_id,
//     disconnected_at: self.disconnected_at.val,
//   }
// }

// pub fn Session::hello(
//   self : Session,
//   role : String,
//   session_id : String,
//   _user_agent : String,
// ) -> HelloResult {
//   if role != "browser" { return Rejected(UnsupportedRole) }
//   if session_id == "" { return Rejected(MissingSessionId) }
//   if self.browser_connected.val { return Rejected(SessionBusy) }
//   let reconnected = self.session_id.val == session_id
//   if self.session_id.val != "" && !reconnected { return Rejected(SessionBusy) }
//   self.session_id.val = session_id
//   self.browser_connected.val = true
//   self.disconnected_at.val = nil_at
//   Ack(reconnected)
// }

// pub fn Session::disconnect(self : Session, at : Int64) -> Unit {
//   self.browser_connected.val = false
//   self.disconnected_at.val = at
// }

// pub fn Session::bind(self : Session, ws : @websocket.Conn, conn_id : Int) -> Unit {
//   self.ws.val = Some(ws)
//   self.active_id.val = conn_id
// }

// pub fn Session::unbind(self : Session, conn_id : Int) -> Unit {
//   if self.active_id.val != conn_id { return }
//   self.ws.val = None
//   self.active_id.val = 0
//   self.pending.val.clear()
//   self.disconnect(@async.now())
// }

// pub fn Session::next_conn(self : Session) -> Int {
//   let id = self.next_conn_id.val
//   self.next_conn_id.val = id + 1
//   id
// }

// pub fn Session::next_request(self : Session) -> Int {
//   let id = self.next_request_id.val
//   self.next_request_id.val = id + 1
//   id
// }

// pub fn Session::track(self : Session, request_id : Int, queue : @aqueue.Queue[Json]) -> Unit {
//   self.pending.val.set(request_id, queue)
// }

// pub fn Session::untrack(self : Session, request_id : Int) -> Unit {
//   self.pending.val.remove(request_id)
// }

// pub fn Session::resolve_pending(self : Session, request_id : Int, data : Json) -> Unit {
//   if self.pending.val.get(request_id) is Some(queue) {
//     let _ = queue.try_put(data) catch { _ => false }
//   }
// }

// pub fn Session::connected_ws(self : Session) -> @websocket.Conn? {
//   self.ws.val
// }

// pub fn Session::reject_reason_code(reason : RejectReason) -> String {
//   match reason {
//     UnsupportedRole => "unsupported_role"
//     MissingSessionId => "missing_session_id"
//     SessionBusy => "session_busy"
//   }
// }

// pub fn Session::temp_dir() -> String {
//   match temp_dir_ffi() {
//     Some(path) => path
//     None => abort("failed to get temp dir")
//   }
// }

// pub fn Session::current_pid() -> Int {
//   current_pid_ffi()
// }

// pub fn Session::state_dir() -> String {
//   state_dir_ref.val
// }

// pub async fn Session::set_state_dir(dir : String) -> Unit {
//   @fs.mkdir(dir, permission=0o755, recursive=true) catch { _ => () }
//   state_dir_ref.val = dir
// }

// pub fn Session::state_path(name : String) -> String {
//   let dir = Session::state_dir()
//   if dir.has_suffix("/") || dir.has_suffix("\\") { "\{dir}\{name}" } else { "\{dir}/\{name}" }
// }

// pub fn Session::state_file_path() -> String {
//   Session::state_path(state_file_name)
// }

// pub fn Session::lock_file_path() -> String {
//   Session::state_path(lock_file_name)
// }

// pub fn Session::retain_state_file(path : String) -> Bool {
//   retain_state_file_ffi(path)
// }

// pub fn Session::release_state_file() -> Unit {
//   release_state_file_ffi()
// }

// pub async fn Session::try_acquire_lock() -> ServiceLock? raise {
//   let file = @fs.open(Session::lock_file_path(), mode=ReadWrite, create=0o644)
//   let locked = file.try_lock(Exclusive)
//   if !locked {
//     file.close()
//     return None
//   }
//   Some({ file })
// }

// pub async fn Session::acquire_lock() -> ServiceLock raise {
//   match Session::try_acquire_lock() {
//     Some(lock) => lock
//     None => raise ServiceError("service already running")
//   }
// }

// pub fn Session::release_lock(lock : ServiceLock) -> Unit {
//   lock.file.unlock()
//   lock.file.close()
// }

// pub async fn Session::write_state(pid : Int, port : Int) -> Unit {
//   let text = Json::object({
//     "pid": pid.to_json(),
//     "port": port.to_json(),
//   }).stringify()
//   let padded = if text.length() < state_file_size {
//     text + " ".repeat(state_file_size - text.length())
//   } else {
//     text
//   }
//   @fs.write_file(Session::state_file_path(), @utf8.encode(padded), create=0o644, truncate=true)
// }

// pub async fn Session::clear_state_file() -> Unit {
//   let path = Session::state_file_path()
//   if @fs.exists(path) {
//     @fs.remove(path)
//   }
// }

// pub async fn Session::clear_lock_file() -> Unit {
//   let path = Session::lock_file_path()
//   if @fs.exists(path) {
//     @fs.remove(path)
//   }
// }

// fn parse_state_text(text : String) -> ServiceStateFile raise {
//   try {
//     @json.from_json(@json.parse(text.trim()))
//   } catch {
//     _ => raise ServiceError("invalid service state file")
//   }
// }

// pub async fn Session::read_port() -> Int raise {
//   let path = Session::state_file_path()
//   if !@fs.exists(path) {
//     raise ServiceError("service is not running")
//   }
//   parse_state_text(@fs.read_file(path).text()).port
// }

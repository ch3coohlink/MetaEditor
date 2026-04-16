extern "C" fn pid_exists_ffi(pid: Int) -> Bool = "pid_exists"
extern "C" fn temp_dir_ffi() -> String? = "get_tmp_path"
extern "C" fn current_pid_ffi() -> Int = "current_pid"
#borrow(path)
extern "C" fn retain_state_file_ffi(path: String) -> Bool = "retain_state_file"
extern "C" fn release_state_file_ffi() -> Unit = "release_state_file"
type WS = @websocket.Conn
type AQueue[T] = @aqueue.Queue[T]
type Addr = @socket.Addr
type HttpServer = @http.Server
type HttpConn = @http.ServerConnection
type HttpReq = @http.Request
type IoData = &@io.Data
type IoReader = &@io.Reader
type Header = Map[String, String]

pub struct Conn { id: Int; role: String; ws: WS; out: AQueue[Json] }
pub fn Conn::close(self: Conn) -> Unit { self.out.close(clear=true) }
pub fn Conn::send(self: Conn, data: Json) -> Unit raise {
  if !self.out.try_put(data) { fail("conn \{self.id} closed") }
}
pub async fn Conn::flush(self: Conn) -> Unit raise {
  let data = self.out.get() catch { _ => fail("conn \{self.id} closed") }
  self.ws.send_text(data.stringify()) catch { err => fail("conn \{self.id} flush: \{err}") }
}
pub async fn Conn::recv(self: Conn) -> @websocket.Message raise {
  self.ws.recv() catch { err => fail("conn \{self.id} recv: \{err}") }
}

let default_port: Int = 8080
let max_port_tries: Int = 32
fn _rt(root: String, push: (Json) -> Unit raise, on_err: (String) -> Unit) -> @src.Runtime {
  fn cmd_batch(cs: Array[@src.DomCmd]) -> Json { Json::array(cs.map(c => c.to_json())) }
  let on_cmd = cs => push(cmd_batch(cs)) catch { e => on_err(e.to_string()) }
  @src.Runtime::new(root, on_cmd~, on_err~)
}
pub struct Runtime { conns: Map[Int, Conn]; pending: Map[Int, Int]
  mut rt: @src.Runtime; conn_id: () -> Int; req_id: () -> Int
  mut port: Int; mut stop: Bool; root: String; files: String; lock: Lock
  on_err: (String) -> Unit }
fn Runtime::report(self: Runtime, msg: Error) -> Unit { (self.on_err)(msg.to_string()) }
fn Runtime::conn(self: Runtime, conn_id: Int) -> Conn raise {
  match self.conns.get(conn_id) { Some(c) => c; None => fail("unknown conn: \{conn_id}") }
}
pub fn Runtime::new(root~: String = "host", files~: String = ".", state_dir~: String = "",
  on_err~: (String) -> Unit = msg => println("[service] \{msg}")) -> Runtime {
  let cs: Map[Int, Conn] = Map::new()
  { rt: _rt(root, (d: Json) => for _, c in cs { c.send(d) }, on_err), conns: cs, pending: Map::new(),
    conn_id: @src.gen_id(1), req_id: @src.gen_id(1), port: default_port, stop: false, root, files,
    lock: Lock::new(dir=state_dir), on_err }
}
pub fn Runtime::reset(self: Runtime, root: String) -> Unit {
  self.rt = _rt(root, d => self.cast(d), self.on_err)
}
pub fn Runtime::cast(self: Runtime, data: Json) -> Unit {
  for _, c in self.conns { c.send(data) catch { e => self.report(e) } }
}
pub fn Runtime::send(self: Runtime, conn_id: Int, data: Json) -> Unit {
  try { self.conn(conn_id).send(data) } catch { e => self.report(e) }
}
pub fn Runtime::add(self: Runtime, ws: WS, role: String) -> Conn {
  let id = (self.conn_id)()
  let c = { id, role, ws, out: AQueue::new(kind=Unbounded) }
  self.conns.set(id, c); c
}
pub fn Runtime::drop(self: Runtime, conn_id: Int) -> Unit {
  try { self.conn(conn_id).close()} catch { e => self.report(e) }
  self.conns.remove(conn_id)
  let stale = []
  for req_id, owner in self.pending { if owner == conn_id { stale.push(req_id) } }
  for req_id in stale { self.pending.remove(req_id) }
}
pub fn Runtime::next_req(self: Runtime) -> Int { (self.req_id)() }
pub fn Runtime::track(self: Runtime, req_id: Int, conn_id: Int) -> Unit { self.pending.set(req_id, conn_id) }
pub fn Runtime::untrack(self: Runtime, req_id: Int) -> Unit { self.pending.remove(req_id) }
pub fn Runtime::owner(self: Runtime, req_id: Int) -> Int? { self.pending.get(req_id) }
pub fn Runtime::take_owner(self: Runtime, req_id: Int) -> Int? {
  let owner = self.pending.get(req_id); self.pending.remove(req_id); owner
}
pub async fn Runtime::flush(self: Runtime, conn_id: Int) -> Unit {
  try { self.conn(conn_id).flush() } catch { e => self.report(e) }
}
pub async fn Runtime::detect(self: Runtime) -> Int? raise {
  self.lock.state() catch { _ => { self.lock.clear(); None } } noraise { 
    state => if pid_exists_ffi(state.pid) { Some(state.port) } else { self.lock.clear(); None }
  }
}
pub async fn Runtime::status(self: Runtime) -> String raise {
  if self.detect() is Some(p) { "running http://localhost:\{p}\n" }
  else { "service is not running\n" }
}
pub async fn Runtime::launch(self: Runtime, port: Int) -> Unit raise {
  let exe = @env.args()[0]; let dir = self.lock.dir
  let args = [boot_flag, "--state-dir", dir, "--port", "\{port}"]
  ignore(@process.spawn_orphan(exe, args, cwd="."))
}
pub async fn Runtime::start(self: Runtime, port: Int) -> String raise {
  if self.detect() is Some(p) { "already running http://localhost:\{p}\n" } else {
    self.lock.clear(); self.launch(port)
    let rp = poll_until(() => {
      let p = self.lock.port(); ignore(rpc(p, "status", "")); Some(p)
    }, 1000) catch { _ => raise ServiceError("service did not start") }
    "started http://localhost:\{rp}\n"
  }
}
pub async fn Runtime::stop(self: Runtime) -> String raise {
  if !self.lock.held() { self.lock.clear(); return "service is not running\n" }
  let port = self.lock.port()
  ignore(rpc(port, "stop", ""))
  poll_until(() => if !self.lock.held() { Some(()) } else { None }, 1000)
    catch { _ => raise ServiceError("service did not stop cleanly") }
  self.lock.clear()
  "stopped\n"
}
pub async fn Runtime::restart(self: Runtime, port: Int?) -> String raise {
  let next = match port { Some(p) => p; None => self.lock.port() catch { _ => default_port } }
  ignore(self.stop()); self.start(next)
}
pub async fn Runtime::run(self: Runtime, port~: Int = default_port) -> Unit raise {
  let clear = () => { release_state_file_ffi(); self.lock.release() }
  try {
    self.lock.get()
    let addr = Addr::parse("0.0.0.0:\{port}") catch { _ => fail("invalid addr: \{port}") }
    let server = HTTP::boot(addr)
    self.port = server.addr().port()
    self.lock.write(self.port)
    self.lock.retain()
    let http = HTTP::new((cmd, _) => match cmd {
        "status" => "running http://localhost:\{self.port}\n"
        "stop" => { self.stop = true; "stopped\n" }
        _ => raise ServiceError("unknown command: \{cmd}")
      }, root=self.files, on_ws= (_, ws) => {
        let conn = self.add(ws, "browser")
        defer { self.drop(conn.id) }; for ;; { self.serve_ws(conn) }
      })
    server.run_forever((req, body, conn) => {
      http.serve(req, body, conn); if self.stop { @sys.exit(0) }
    })
    clear()
  } catch { e => { clear(); raise e } }
}

pub struct HTTP { root: String; on_ws: async (HttpReq, WS) -> Unit raise
  run: async (String, String) -> String raise }
pub fn HTTP::boot(addr: Addr) -> HttpServer raise {
  let mut last: Error? = None
  for i = 0; i < max_port_tries; i = i + 1 {
    let next = Addr::new(addr.ip(), addr.port() + i)
    match (try? HttpServer::new(next) : Result[HttpServer, _]) {
      Ok(server) => return server
      Err(err) => last = Some(err)
    }
  }
  match last { Some(err) => raise err; None => raise ServiceError("failed to bind service port") }
}
fn HTTP::resolve(self: HTTP, path: String) -> String {
  if self.root == "." { path } else { "\{self.root}/\{path}" }
}
pub async fn HTTP::send(conn: HttpConn, body: IoData,
  status: Int, reason: String, header~: Header = {}) -> Unit {
  conn..send_response(status, reason, extra_headers=header)..write(body).end_response()
}
pub async fn HTTP::error(conn: HttpConn, status: Int, reason: String, msg: String) -> Unit {
  let payload = { ok: false, error: Some(msg), result: None }.to_json()
  HTTP::send(conn, payload.stringify(), status, reason,
    header={ "Content-Type": "application/json" })
}
fn HTTP::content_type(path: String) -> String {
  if path.has_suffix(".html") { "text/html" }
  else if path.has_suffix(".js") { "text/javascript" }
  else if path.has_suffix(".css") { "text/css" }
  else { "text/plain" }
}
pub fn HTTP::new(run: async (String, String) -> String raise, root~: String = ".",
  on_ws~: async (HttpReq, WS) -> Unit raise = (_, ws) => ws.close()) -> HTTP {{ root, run, on_ws }}
pub async fn HTTP::file(self: HTTP, conn: HttpConn, path: String) -> Unit {
  let full = self.resolve(path)
  if !@fs.exists(full) { return HTTP::error(conn, 404, "NotFound", "Not Found") }
  let body = @fs.read_file(full)
  HTTP::send(conn, body.binary(), 200, "OK", header={
    "Content-Type": HTTP::content_type(path), "Cache-Control": "no-cache" })
}
pub struct Command { cmd: String?; arg: String? } derive(ToJson, FromJson)
pub struct HttpRes { ok: Bool; error: String?; result: Json? } derive(ToJson, FromJson)
async fn rpc(port: Int, cmd: String, arg: String) -> Json raise {
  let payload = { cmd: Some(cmd), arg: Some(arg) }.to_json().stringify()
  let (res, body) = @http.post("http://127.0.0.1:\{port}\{http_path_ctrl}", payload,
    headers={ "Content-Type": "application/json" })
  if res.code != 200 { raise ServiceError(body.text()) }
  let msg: HttpRes = try { @json.from_json(@json.parse(body.text())) }
    catch { _ => raise ServiceError("invalid service response") }
  if msg.ok { msg.result.unwrap_or(Json::string("")) }
  else { raise ServiceError(msg.error.unwrap_or("request failed")) }
}
pub async fn HTTP::cmd(self: HTTP, body: IoReader, conn: HttpConn) -> Unit {
  try {
    let payload = body.read_all().json()
    let msg = (try? @json.from_json(payload)).unwrap_or({ cmd: None, arg: None })
    let result = (self.run)(msg.cmd.unwrap_or(""), msg.arg.unwrap_or(""))
    let payload = { ok: true, error: None, result: Some(Json::string(result)) }.to_json()
    HTTP::send(conn, payload.stringify(), 200, "OK", header={ "Content-Type": "application/json" })
  } catch {
    ServiceError(msg) => HTTP::error(conn, 400, "BadRequest", msg)
    err => HTTP::error(conn, 500, "InternalError", err.to_string())
  }
}
pub async fn HTTP::ws(self: HTTP, req: HttpReq, conn: HttpConn) -> Unit {
  let ws = @websocket.from_http_server(req, conn)
  (self.on_ws)(req, ws) catch { err => { ws.close(); raise err } }
}
let http_path_ctrl: String = "/_meta/command"
let http_path_ws: String = "/_meta/ws"
pub async fn HTTP::serve(self: HTTP, req: HttpReq, body: IoReader, conn: HttpConn) -> Unit {
  if req.path == http_path_ctrl { return self.cmd(body, conn) }
  if req.path == http_path_ws { return self.ws(req, conn) }
  let path = if req.path == "/" { "index.html" }
  else if req.path.has_prefix("/") { req.path[1:].to_string() }
  else { req.path }
  self.file(conn, path)
}

let state_file_name: String = ".meta-editor-service.json"
let lock_file_name: String = ".meta-editor-service.lock"
let state_file_size: Int = 1024
pub struct State { pid: Int; port: Int } derive(FromJson, ToJson)
pub struct Lock { dir: String; mut file: @fs.File?; mut state: State? }
pub fn Lock::new(dir~: String = "") -> Lock {{
  dir: if dir != "" { dir } else {
    match temp_dir_ffi() { Some(path) => path; None => abort("failed to get temp dir") }
  }, file: None, state: None
}}
fn Lock::path(self: Lock, name: String) -> String {
  let dir = self.dir
  if dir.has_suffix("/") || dir.has_suffix("\\") { "\{dir}\{name}" } else { "\{dir}/\{name}" }
}
pub async fn Lock::open(self: Lock) -> Bool raise {
  let file = @fs.open(self.path(lock_file_name), mode=ReadWrite, create=0o644)
  if !file.try_lock(Exclusive) { file.close(); return false }
  self.file = Some(file)
  true
}
pub async fn Lock::get(self: Lock) -> Unit raise {
  if !self.open() { raise ServiceError("service already running") }
}
pub async fn Lock::clear(self: Lock) -> Unit {
  self.state = None
  let state = self.path(state_file_name)
  if @fs.exists(state) { @fs.remove(state) }
  let lock = self.path(lock_file_name)
  if @fs.exists(lock) { @fs.remove(lock) }
}
pub async fn Lock::release(self: Lock) -> Unit {
  if self.file is Some(file) { file.unlock(); file.close() }
  self.file = None; self.state = None; self.clear()
}
pub async fn Lock::write(self: Lock, port: Int) -> Unit {
  let state: State = { pid: current_pid_ffi(), port }
  let text = state.to_json().stringify()
  let body = if text.length() < state_file_size {
    text + " ".repeat(state_file_size - text.length())
  } else { text }
  @fs.write_file(self.path(state_file_name), @utf8.encode(body), create=0o644, truncate=true)
  self.state = Some(state)
}
// 和 hold 重复, 很可能是多余的
pub fn Lock::retain(self: Lock) -> Unit raise {
  if !retain_state_file_ffi(self.path(lock_file_name)) {
    raise ServiceError("failed to retain service lock file")
  }
}
async fn Lock::read(self: Lock) -> State raise {
  let path = self.path(state_file_name)
  if !@fs.exists(path) { raise ServiceError("service is not running") }
  try { @json.from_json(@json.parse(@fs.read_file(path).text().trim())) }
  catch { _ => raise ServiceError("invalid service state file") }
}
pub async fn Lock::state(self: Lock) -> State raise {
  if self.state is Some(s) { s } else { let s = self.read(); self.state = Some(s); s }
}
pub async fn Lock::pid(self: Lock) -> Int raise { self.state().pid }
pub async fn Lock::port(self: Lock) -> Int raise { self.state().port }
pub async fn Lock::held(self: Lock) -> Bool {
  match (try? self.open() : Result[Bool, _]) {
    Ok(true) => { self.release(); false }
    Ok(false) | Err(_) => true
  }
}

let boot_flag: String = "--internal_boot_as_service"
async fn main {
  let args = @env.args()
  guard args.contains(boot_flag) else { return }
  let port = match arg_value(args, "--port") {
    Some(v) => @string.parse_int(v) catch { _ => default_port }
    None => default_port
  }
  let state_dir = arg_value(args, "--state-dir").unwrap_or("")
  Runtime::new(state_dir=state_dir).run(port=port)
}

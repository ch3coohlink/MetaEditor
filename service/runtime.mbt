extern "C" fn pid_exists(pid: Int) -> Bool = "pid_exists"
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
async fn call(port: Int, cmd: String, arg: String) -> Json raise {
  let payload = ({ cmd: Some(cmd), arg: Some(arg) } : CommandMsg).to_json().stringify()
  let (res, body) = @http.post("http://127.0.0.1:\{port}\{control_path}", payload,
    headers={ "Content-Type": "application/json" })
  if res.code != 200 { raise ServiceError(body.text()) }
  let msg: ResponseMsg = try { @json.from_json(@json.parse(body.text())) }
    catch { _ => raise ServiceError("invalid service response") }
  if msg.ok == Some(true) { msg.result.unwrap_or(Json::string("")) }
  else { raise ServiceError(msg.error.unwrap_or("request failed")) }
}
pub async fn Runtime::detect(self: Runtime) -> Int? raise {
  self.lock.state() catch { _ => { self.lock.clear(); None } } noraise { 
    state => if pid_exists(state.pid) { Some(state.port) } else { self.lock.clear(); None }
  }
}
pub async fn Runtime::status(self: Runtime) -> String raise {
  if self.detect() is Some(p) { "running http://localhost:\{p}\n" }
  else { "service is not running\n" }
}
pub async fn Runtime::launch(self: Runtime, port: Int) -> Unit raise {
  let exe = @env.args()[0]; let dir = self.lock.dir
  let args = [boot_service, "--state-dir", dir, "--port", "\{port}"]
  ignore(@process.spawn_orphan(exe, args, cwd="."))
}
pub async fn Runtime::start(self: Runtime, port: Int) -> String raise {
  if self.detect() is Some(p) { "already running http://localhost:\{p}\n" } else {
    self.lock.clear(); self.launch(port)
    let rp = poll_until(() => {
      let p = self.lock.port(); ignore(call(p, "status", "")); Some(p)
    }, 1000) catch { _ => raise ServiceError("service did not start") }
    "started http://localhost:\{rp}\n"
  }
}
pub async fn Runtime::stop(self: Runtime) -> String raise {
  if !self.lock.held() { self.lock.clear(); return "service is not running\n" }
  let port = self.lock.port()
  ignore(call(port, "stop", ""))
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
    if !retain_state_file_ffi(self.lock.path(lock_file_name)) {
      raise ServiceError("failed to retain service lock file")
    }
    let http = HTTP::new((cmd, _) => match cmd {
        "status" => Response::Text("running http://localhost:\{self.port}\n")
        "stop" => { self.stop = true; Response::Text("stopped\n") }
        _ => raise ServiceError("unknown command: \{cmd}")
      }, root=self.files)
    server.run_forever((req, body, conn) => {
      http.serve(req, body, conn); if self.stop { @sys.exit(0) }
    })
    clear()
  } catch { e => { clear(); raise e } }
}

pub struct HTTP { root: String; on_ws: async (HttpReq, WS) -> Unit raise
  run: async (String, String) -> Response raise }
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
  let payload = { ok: Some(false), error: Some(msg), result: None }.to_json()
  HTTP::send(conn, payload.stringify(), status, reason,
    header={ "Content-Type": "application/json" })
}
fn HTTP::content_type(path: String) -> String {
  if path.has_suffix(".html") { "text/html" }
  else if path.has_suffix(".js") { "text/javascript" }
  else if path.has_suffix(".css") { "text/css" }
  else { "text/plain" }
}
pub fn HTTP::new(run: async (String, String) -> Response raise, root~: String = ".",
  on_ws~: async (HttpReq, WS) -> Unit raise = (_, ws) => ws.close()) -> HTTP {{ root, run, on_ws }}
pub async fn HTTP::file(self: HTTP, conn: HttpConn, path: String) -> Unit {
  let full = self.resolve(path)
  if !@fs.exists(full) { return HTTP::error(conn, 404, "NotFound", "Not Found") }
  let body = @fs.read_file(full)
  HTTP::send(conn, body.binary(), 200, "OK", header={
    "Content-Type": HTTP::content_type(path), "Cache-Control": "no-cache" })
}
pub async fn HTTP::cmd(self: HTTP, body: IoReader, conn: HttpConn) -> Unit {
  let payload = body.read_all().json()
  let msg: CommandMsg = try { @json.from_json(payload) } catch { _ => { cmd: None, arg: None } }
  try { (self.run)(msg.cmd.unwrap_or(""), msg.arg.unwrap_or("")).send_http(conn) } catch {
    ServiceError(msg) => HTTP::error(conn, 400, "BadRequest", msg)
    err => HTTP::error(conn, 500, "InternalError", err.to_string())
  }
}
pub async fn HTTP::ws(self: HTTP, req: HttpReq, conn: HttpConn) -> Unit {
  let ws = @websocket.from_http_server(req, conn)
  (self.on_ws)(req, ws) catch { err => { ws.close(); raise err } }
}
pub async fn HTTP::serve(self: HTTP, req: HttpReq, body: IoReader, conn: HttpConn) -> Unit {
  if req.path == control_path { return self.cmd(body, conn) }
  if req.path == "/_meta/ws" { return self.ws(req, conn) }
  let path = if req.path == "/" { "index.html" }
  else if req.path.has_prefix("/") { req.path[1:].to_string() }
  else { req.path }
  self.file(conn, path)
}

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

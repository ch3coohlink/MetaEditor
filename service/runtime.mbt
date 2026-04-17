extern "C" fn pid_exists_ffi(pid: Int) -> Bool = "pid_exists"
extern "C" fn terminate_process_ffi(pid: Int) -> Bool = "terminate_process"
extern "C" fn temp_dir_ffi() -> String? = "get_tmp_path"
extern "C" fn current_pid_ffi() -> Int = "current_pid"
type WS = @websocket.Conn
type AQueue[T] = @aqueue.Queue[T]
type Addr = @socket.Addr
type HttpServer = @http.Server
type HttpConn = @http.ServerConnection
type HttpReq = @http.Request
type IoData = &@io.Data
type Header = Map[String, String]

pub struct Conn { id: Int; mut role: String; ws: WS; out: AQueue[Json] }
pub fn Conn::close(self: Conn) -> Unit { self.out.close(clear=true) }
pub fn Conn::send(self: Conn, data: Json) -> Unit raise {
  if !self.out.try_put(data) { fail("conn \{self.id} closed") }
}
pub async fn Conn::flush(self: Conn) -> Unit raise {
  while self.out.try_get() is Some(data) {
    self.ws.send_text(data.stringify()) catch { err => fail("conn \{self.id} flush: \{err}") }
  }
}
pub async fn Conn::recv(self: Conn) -> @websocket.Message raise {
  self.ws.recv() catch { err => fail("conn \{self.id} recv: \{err}") }
}

let default_port: Int = 8080
let max_port_tries: Int = 32
let lifecycle_timeout_ms: Int = 2500
fn cmd_batch(cs: Array[@src.DomCmd]) -> Json { Json::array(cs.map(c => c.to_json())) }
fn _rt(root: String, push: (Json) -> Unit raise, on_err: (String) -> Unit) -> @src.Runtime {
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
pub fn Runtime::replay(self: Runtime, conn_id: Int) -> Unit {
  self.send(conn_id, cmd_batch(self.rt.replay()))
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
  if self.detect() is Some(p) { Client::exec(p, "status") }
  else { "service is not running\n" }
}
pub fn Runtime::status_local(self: Runtime) -> String { "running http://localhost:\{self.port}\n" }
pub async fn Runtime::launch(self: Runtime, port: Int) -> Unit raise {
  let exe = @env.args()[0]; let dir = self.lock.dir
  let args = [boot_flag, "--state-dir", dir, "--port", "\{port}"]
  ignore(@process.spawn_orphan(exe, args, cwd="."))
}
pub async fn Runtime::start(self: Runtime, port: Int) -> String raise {
  if self.detect() is Some(p) { "already running http://localhost:\{p}\n" } else {
    self.lock.clear(); self.launch(port)
    let rp = poll_until(() => {
      try { let p = self.lock.port(); ignore(Client::exec(p, "status")); Some(p) }
      catch { _ => None }
    }, lifecycle_timeout_ms) catch { _ => raise ServiceError("service did not start") }
    "started http://localhost:\{rp}\n"
  }
}
pub async fn Runtime::stop(self: Runtime) -> String raise {
  if !self.lock.held() { self.lock.clear(); return "service is not running\n" }
  let pid = self.lock.pid()
  ignore(Client::exec(self.lock.port(), "stop"))
  poll_until(() => if !pid_exists_ffi(pid) { Some(()) } else { None }, 500)
    catch { _ => ignore(terminate_process_ffi(pid)) }
  self.lock.clear()
  "stopped\n"
}
pub fn Runtime::stop_local(self: Runtime) -> String { self.stop = true; "stopped\n" }
pub async fn Runtime::restart(self: Runtime, port: Int?) -> String raise {
  let next = match port { Some(p) => p; None => self.lock.port() catch { _ => default_port } }
  ignore(self.stop()); self.start(next)
}
pub async fn Runtime::run(self: Runtime, port~: Int = default_port) -> Unit raise {
  let clear = () => self.lock.release()
  try {
    self.lock.get()
    let addr = Addr::parse("0.0.0.0:\{port}") catch { _ => fail("invalid addr: \{port}") }
    let server = HTTP::boot(addr)
    self.port = server.addr().port()
    self.lock.write(self.port)
    let http = HTTP::new(root=self.files, on_ws= (_, ws) => {
        let conn = self.add(ws, ""); defer { self.drop(conn.id) }
        for ;; { self.serve_ws(conn); if self.stop { return } }
      })
    server.run_forever((req, _, conn) => {
      http.serve(req, conn); if self.stop { @sys.exit(0) }
    })
    clear()
  } catch { e => { clear(); raise e } }
}

pub struct HTTP { root: String; on_ws: async (HttpReq, WS) -> Unit raise }
pub fn HTTP::boot(addr: Addr) -> HttpServer raise {
  let mut last: Error? = None
  for i = 0; i < max_port_tries; i = i + 1 {
    let next = Addr::new(addr.ip(), addr.port() + i)
    match (try? HttpServer::new(next): Result[HttpServer, _]) {
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
  HTTP::send(conn, msg, status, reason, header={ "Content-Type": "text/plain" })
}
fn HTTP::content_type(path: String) -> String {
  if path.has_suffix(".html") { "text/html" }
  else if path.has_suffix(".js") { "text/javascript" }
  else if path.has_suffix(".css") { "text/css" }
  else { "text/plain" }
}
pub fn HTTP::new(root~: String = ".", on_ws~: async (HttpReq, WS) -> Unit raise
  = (_, ws) => ws.close()) -> HTTP {{ root, on_ws }}
pub async fn HTTP::file(self: HTTP, conn: HttpConn, path: String) -> Unit {
  let full = self.resolve(path)
  if !@fs.exists(full) { return HTTP::error(conn, 404, "NotFound", "Not Found") }
  let body = @fs.read_file(full)
  HTTP::send(conn, body.binary(), 200, "OK", header={
    "Content-Type": HTTP::content_type(path), "Cache-Control": "no-cache" })
}
pub async fn HTTP::ws(self: HTTP, req: HttpReq, conn: HttpConn) -> Unit {
  let ws = @websocket.from_http_server(req, conn)
  (self.on_ws)(req, ws) catch { err => { ws.close(); raise err } }
}
let http_path_ws: String = "/_meta/ws"
pub async fn HTTP::serve(self: HTTP, req: HttpReq, conn: HttpConn) -> Unit {
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
async fn Lock::read(self: Lock) -> State raise {
  let path = self.path(state_file_name)
  if !@fs.exists(path) { raise ServiceError("service is not running") }
  try { from_json(parse(@fs.read_file(path).text().trim())) }
  catch { _ => raise ServiceError("invalid service state file") }
}
pub async fn Lock::state(self: Lock) -> State raise {
  if self.state is Some(s) { s } else { let s = self.read(); self.state = Some(s); s }
}
pub async fn Lock::pid(self: Lock) -> Int raise { self.state().pid }
pub async fn Lock::port(self: Lock) -> Int raise { self.state().port }
pub async fn Lock::held(self: Lock) -> Bool {
  match (try? self.open(): Result[Bool, _]) {
    Ok(true) => { self.release(); false }
    Ok(false) | Err(_) => true
  }
}

let boot_flag: String = "--internal_boot_as_service"
enum FlagValue { Present; Value(String) }
struct CLIArgs { subcmd: String?; rest: Array[String]; flags: Map[String, FlagValue] }
fn CLIArgs::split(line: String) -> Array[String] raise {
  let parts = []
  let mut cur = ""
  let mut in_quote = false
  let mut i = 0
  while i < line.length() {
    let ch = line[i:i + 1].to_string()
    if ch == "\\" && i + 1 < line.length() {
      i = i + 1
      cur += line[i:i + 1].to_string()
    } else if ch == "\"" {
      in_quote = !in_quote
    } else if !in_quote && (ch == " " || ch == "\t" || ch == "\n" || ch == "\r") {
      if cur != "" { parts.push(cur); cur = "" }
    } else {
      cur += ch
    }
    i = i + 1
  }
  if in_quote { raise ServiceError("unterminated quote") }
  if cur != "" { parts.push(cur) }
  parts
}
fn CLIArgs::parse(args: Array[String]) -> CLIArgs raise {
  let known_flag = (flag: String) => {
    flag == boot_flag || flag == "--state-dir" || flag == "--port"
  }
  let needs_value = (flag: String) => { flag == "--state-dir" || flag == "--port" }
  let flags = Map::new(); let rest = []
  let mut subcmd: String? = None; let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg.has_prefix("--") {
      if !known_flag(arg) { raise ServiceError("unknown flag: \{arg}") }
      if flags.get(arg) is Some(_) { raise ServiceError("duplicate flag: \{arg}") }
      if needs_value(arg) {
        if i + 1 >= args.length() || args[i + 1].has_prefix("--") {
          raise ServiceError("missing value for flag: \{arg}")
        }
        flags.set(arg, Value(args[i + 1]))
        i = i + 2
      } else { flags.set(arg, Present); i = i + 1 }
    } else {
      if subcmd is None { subcmd = Some(arg) } else { rest.push(arg) }
      i = i + 1
    }
  }
  { subcmd, rest, flags }
}
fn CLIArgs::flag(self: CLIArgs, name: String) -> String? {
  match self.flags.get(name) { Some(Value(v)) => Some(v); _ => None }
}
fn CLIArgs::has(self: CLIArgs, name: String) -> Bool {
  match self.flags.get(name) { Some(_) => true; None => false }
}

struct CMD { args: CLIArgs; rt: Runtime }
fn CMD::new(raw: Array[String], rt~: Runtime? = None) -> CMD raise {
  let args = CLIArgs::parse(raw)
  let state_dir = args.flag("--state-dir").unwrap_or("")
  let rt = match rt { Some(rt) => rt; None => Runtime::new(state_dir~) }
  { args, rt }
}
fn CMD::cmd(self: CMD) -> String { self.args.subcmd.unwrap_or("start") }
fn CMD::port(self: CMD) -> Int? {
  match self.args.flag("--port") {
    Some(v) => Some(@string.parse_int(v) catch { _ => return None })
    None => if self.args.rest.length() > 0 {
      Some(@string.parse_int(self.args.rest[0]) catch { _ => return None })
    } else { None }
  }
}
async fn CMD::request(self: CMD, req: (Int) -> Json) -> Json raise {
  let client = self.client(); defer client.close(); client.request(req)
}
async fn CMD::boot(self: CMD) -> Unit raise {
  self.rt.run(port=self.port().unwrap_or(default_port))
}
fn CMD::reset(self: CMD) -> String {
  let root = if self.args.rest.length() > 0 { self.args.rest[0] } else { self.rt.root }
  self.rt.reset(root)
  "reset\n"
}
async fn CMD::query(self: CMD) -> String raise {
  let usage = "usage: query PATH [node|text|attr PROP|prop PROP|style PROP|QUERY_JSON]"
  let (path, raw) = match self.args.rest {
    [path] => (path, Json::string("Node"))
    [path, "node"] => (path, Json::string("Node"))
    [path, "text"] => (path, Json::string("Text"))
    [path, "attr", prop] => (path, Json::array([Json::string("Attr"), Json::string(prop)]))
    [path, "prop", prop] => (path, Json::array([Json::string("Prop"), Json::string(prop)]))
    [path, "style", prop] => (path, Json::array([Json::string("Style"), Json::string(prop)]))
    [path, raw] => (path, parse(raw) catch { _ => raise ServiceError(usage) })
    _ => raise ServiceError(usage)
  }
  let _query: @src.NodeQuery = from_json(raw) // 这个地方到底怎么写???
  match self.request(id => {
    { "id": id, "type": "query", "path": path, "query": raw }}) {
    Array([String("Query"), value]) => value.stringify() + "\n"
    _ => raise ServiceError("invalid query response")
  }
}
async fn CMD::dispatch(self: CMD) -> String raise {
  let usage = "usage: dispatch PATH EVENT_JSON"
  guard self.args.rest.length() >= 2 else { raise ServiceError(usage) }
  let path = self.args.rest[0]
  let raw = parse(self.args.rest[1:].iter().join(" ")) catch { _ => raise ServiceError(usage) }
  let _event: @src.DomEvent = from_json(raw) // 这个地方到底怎么写???
  match self.request(id => {
    { "id": id, "type": "dispatch", "path": path, "event": raw }}) {
    String("Ok") => "ok\n"
    _ => raise ServiceError("invalid dispatch response")
  }
}
async fn CMD::client(self: CMD) -> Client raise {
  let port = self.rt.detect()
  guard port is Some(port) else { raise ServiceError("service is not running") }
  Client::connect(port)
}
async fn CMD::repl(self: CMD) -> String raise {
  let client = self.client()
  defer client.close()
  while @stdio.stdin.read_until("\n") is Some(line) {
    try {
      let line = line.trim().to_string()
      let argv = CLIArgs::split(line)
      if argv.length() == 0 { continue }
      match client.request(id => {{ "id": id, "type": "cli", "cmd": line }}) {
        Array([String("Cli"), String(out)]) => if out != "" { @stdio.stdout.write(out) }
        _ => raise ServiceError("invalid exec response")
      }
    } catch { e => { println(e.to_string()); continue } }
  }
  ""
}
async fn CMD::exec(self: CMD, is_repl~: Bool = false, is_local~: Bool = false) -> String raise {
  match self.cmd() {
    "start" => self.rt.start(self.port().unwrap_or(default_port))
    "restart" => self.rt.restart(self.port())
    "stop" => if is_local { self.rt.stop_local() } else { self.rt.stop() }
    "status" => if is_local { self.rt.status_local() } else { self.rt.status() }
    "reset" => self.reset()
    "query" => self.query()
    "dispatch" => self.dispatch()
    "repl" => if is_repl { raise ServiceError("repl is not allowed in repl") } else { self.repl() }
    cmd => raise ServiceError("unknown command: \{cmd}")
  }
}
async fn CMD::run(self: CMD) -> String raise { self.exec() }
async fn main {
  try {
    let cmd = CMD::new(@env.args())
    if cmd.args.has(boot_flag) { return cmd.boot() }
    println(cmd.run())
  } catch {
    ServiceError(m) => { println(m); @sys.exit(1) }
    e => { println(e.to_string()); @sys.exit(1) }
  }
}

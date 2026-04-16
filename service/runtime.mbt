type WS = @websocket.Conn
type AQueue[T] = @aqueue.Queue[T]
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
  mut port: Int; mut stop: Bool; root: String; files: String; on_err: (String) -> Unit }
fn Runtime::report(self: Runtime, msg: Error) -> Unit { (self.on_err)(msg.to_string()) }
fn Runtime::conn(self: Runtime, conn_id: Int) -> Conn raise {
  match self.conns.get(conn_id) { Some(c) => c; None => fail("unknown conn: \{conn_id}") }
}
pub fn Runtime::new(root~: String = "host", files~: String = ".",
  on_err~: (String) -> Unit = msg => println("[service] \{msg}")) -> Runtime {
  let cs: Map[Int, Conn] = Map::new()
  { rt: _rt(root, (d: Json) => for _, c in cs { c.send(d) }, on_err), conns: cs, pending: Map::new(),
    conn_id: @src.gen_id(1), req_id: @src.gen_id(1), port: default_port, stop: false, root, files, on_err }
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

type HttpConn = @http.ServerConnection
type HttpReq = @http.Request
type IoData = &@io.Data
type IoReader = &@io.Reader
type Header = Map[String, String]
pub struct HTTP { root: String; run: async (String, String) -> Response raise }
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
pub fn HTTP::new(run: async (String, String) -> Response raise,
  root~: String = ".") -> HTTP {{ root, run }}
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
pub async fn HTTP::serve(self: HTTP, req: HttpReq, body: IoReader, conn: HttpConn) -> Unit {
  if req.path == control_path { return self.cmd(body, conn) }
  let path = if req.path == "/" { "index.html" }
  else if req.path.has_prefix("/") { req.path[1:].to_string() }
  else { req.path }
  self.file(conn, path)
}

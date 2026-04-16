pub struct Conn { id: Int; role: String; ws: @websocket.Conn; out: @aqueue.Queue[Json] }
pub struct Runtime { conns: Map[Int, Conn]; pending: Map[Int, Int]
  mut rt: @src.Runtime; conn_id: () -> Int; req_id: () -> Int; on_err: (String) -> Unit }

pub fn Conn::send(self: Conn, data: Json) -> Unit raise {
  if !self.out.try_put(data) { fail("conn \{self.id} closed") }
}
pub fn Conn::close(self: Conn) -> Unit { self.out.close(clear=true) }
pub async fn Conn::flush(self: Conn) -> Unit raise {
  let data = self.out.get() catch { _ => fail("conn \{self.id} closed") }
  self.ws.send_text(data.stringify()) catch { err => fail("conn \{self.id} flush: \{err}") }
}
fn rt(push: (Json) -> Unit raise, on_err: (String) -> Unit) -> @src.Runtime {
  fn cmd_batch(cs: Array[@src.DomCmd]) -> Json { Json::array(cs.map(c => c.to_json())) }
  let on_cmd = cs => push(cmd_batch(cs)) catch { e => on_err(e.to_string()) }
  @src.Runtime::new(@src.host, on_cmd~, on_err~)
}
fn Runtime::report(self: Runtime, msg: Error) -> Unit { (self.on_err)(msg.to_string()) }
fn Runtime::get_conn(self: Runtime, conn_id: Int) -> Conn raise {
  match self.conns.get(conn_id) { Some(c) => c; None => fail("unknown conn: \{conn_id}") }
}
pub fn Runtime::new(on_err~: (String) -> Unit = msg => println("[service] \{msg}")) -> Runtime {
  let conns: Map[Int, Conn] = Map::new()
  { rt: rt((d: Json) => for _, c in conns { c.send(d) }, on_err),
    conns, pending: Map::new(), conn_id: @src.gen_id(1), req_id: @src.gen_id(1), on_err }
}
pub fn Runtime::reset(self: Runtime) -> Unit { self.rt = rt(d => self.cast(d), self.on_err) }
pub fn Runtime::cast(self: Runtime, data: Json) -> Unit {
  for _, c in self.conns { c.send(data) catch { e => self.report(e) } }
}
pub fn Runtime::send(self: Runtime, conn_id: Int, data: Json) -> Unit {
  try { self.get_conn(conn_id).send(data) } catch { e => self.report(e) }
}
pub fn Runtime::add(self: Runtime, ws: @websocket.Conn, role: String) -> Conn {
  let id = (self.conn_id)()
  let conn = { id, role, ws, out: @aqueue.Queue::new(kind=Unbounded) }
  self.conns.set(id, conn)
  conn
}
pub fn Runtime::drop(self: Runtime, conn_id: Int) -> Unit {
  try {
    self.get_conn(conn_id).close()
    self.conns.remove(conn_id)
    let stale: Array[Int] = []
    for req_id, owner in self.pending { if owner == conn_id { stale.push(req_id) } }
    for req_id in stale { self.pending.remove(req_id) }
  } catch { e => self.report(e) }
}
pub fn Runtime::next_req(self: Runtime) -> Int { (self.req_id)() }
pub fn Runtime::track(self: Runtime, req_id: Int, conn_id: Int) -> Unit { self.pending.set(req_id, conn_id) }
pub fn Runtime::untrack(self: Runtime, req_id: Int) -> Unit { self.pending.remove(req_id) }
pub fn Runtime::owner(self: Runtime, req_id: Int) -> Int? { self.pending.get(req_id) }
pub fn Runtime::take_owner(self: Runtime, req_id: Int) -> Int? {
  let owner = self.pending.get(req_id); self.pending.remove(req_id); owner
}
pub async fn Runtime::flush(self: Runtime, conn_id: Int) -> Unit {
  try { self.get_conn(conn_id).flush() } catch { e => self.report(e) }
}

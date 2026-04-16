pub struct HelloReq { role: Role; session: String } derive(FromJson)
pub struct HelloRes { session: String } derive(ToJson)
pub struct QueryReq { path: String; query: Json }
pub struct DispatchReq { path: String; event: Json }
pub struct SpawnReq { entry: String; id: String? } derive(FromJson)
pub struct SpawnRes { id: String } derive(ToJson)
pub struct CloseReq { id: String } derive(FromJson)
pub enum Req { Hello(HelloReq); Query(QueryReq)
  Dispatch(DispatchReq); Spawn(SpawnReq); Close(CloseReq); Ping }
pub enum Res { HelloAck(HelloRes); Query(@src.NodeValue)
  Spawn(SpawnRes); Pong; Ok; Err(String) } derive(ToJson)

pub enum Role { Browser; Client } derive(FromJson, ToJson)
pub struct ReqMsg { id: Int; body: Req }
pub struct ResMsg { id: Int; body: Res } derive(ToJson)
impl FromJson for QueryReq with from_json(json, path) {
  let obj = json_obj(json, path)
  let path_v: String = obj.get("path")
  let query_v: Json = obj.get("query")
  { path: path_v, query: query_v }
}
impl FromJson for DispatchReq with from_json(json, path) {
  let obj = json_obj(json, path)
  let path_v: String = obj.get("path")
  let event_v: Json = obj.get("event")
  { path: path_v, event: event_v }
}
impl FromJson for Req with from_json(json, path) {
  let obj = json_obj(json, path)
  match obj.get("type") {
    "hello" => Hello(from_json(json, path~))
    "query" => Query(from_json(json, path~))
    "dispatch" => Dispatch(from_json(json, path~))
    "spawn" => Spawn(from_json(json, path~))
    "close" => Close(from_json(json, path~))
    "ping" => Ping; _ => bad_json(path, "unknown type")
  }
}
impl FromJson for ReqMsg with from_json(json, path) {
  let obj = json_obj(json, path)
  let id: Int = obj.get("id")
  let body: Req = from_json(json, path~)
  { id, body }
}

fn err(id: Int, msg: String) -> ResMsg {{ id, body: Err(msg) }}
fn pong(id: Int) -> ResMsg {{ id, body: Pong }}
fn hello_ack(id: Int, session: String) -> ResMsg {{ id, body: HelloAck({ session: session }) }}
async fn Runtime::reject(self: Runtime, conn: Conn, id: Int, msg: String) -> Unit raise {
  self.flush(conn..send(err(id, msg).to_json()).id)
}
pub async fn Runtime::serve_ws(self: Runtime, conn: Conn) -> Unit raise {
  let msg = conn.recv()
  guard msg.kind is Text else { return self.reject(conn, 0, "text_only") }
  let json = parse(msg.read_all().text()) catch {
    _ => return self.reject(conn, 0, "invalid_json")
  }
  let req: ReqMsg = from_json(json) catch {
    _ => return self.reject(conn, 0, "invalid_message")
  }
  let res = match req.body {
    Hello(hello) => match hello.role {
      Browser => if hello.session == "" { err(req.id, "missing_session") }
        else { hello_ack(req.id, hello.session) }
      Client => err(req.id, "unsupported_role")
    }
    Ping => pong(req.id)
    Query(_) => err(req.id, "unimplemented")
    Dispatch(_) => err(req.id, "unimplemented")
    Spawn(_) => err(req.id, "unimplemented")
    Close(_) => err(req.id, "unimplemented")
  }
  conn.send(res.to_json())
  self.flush(conn.id)
}

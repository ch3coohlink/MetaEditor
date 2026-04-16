using @json { from_json, parse, type JsonPath, type JsonDecodeError }

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
    "ping" => Ping; _ => bad_req(path, "unknown type")
  }
}
impl FromJson for ReqMsg with from_json(json, path) {
  let obj = json_obj(json, path)
  let id: Int = obj.get("id")
  let body: Req = from_json(json, path~)
  { id, body }
}

fn[T] bad_req(path: JsonPath, msg: String) -> T raise JsonDecodeError {
  raise JsonDecodeError((path, "ReqMsg::from_json: \{msg}"))
}
struct JsonObj { obj: Map[String, Json]; path: JsonPath }
fn json_obj(json: Json, path: JsonPath) -> JsonObj raise JsonDecodeError {
  match json { Object(obj) => { obj, path }; _ => bad_req(path, "expected object") }
}
fn[T: FromJson] JsonObj::get(self: JsonObj, key: String) -> T raise JsonDecodeError {
  let v = match self.obj.get(key) { Some(v) => v; None => bad_req(self.path, "missing \{key}") }
  from_json(v, path=self.path.add_key(key)) catch { _ => bad_req(self.path, "bad \{key}") }
}

fn err(id: Int, msg: String) -> ResMsg {{ id, body: Err(msg) }}
fn pong(id: Int) -> ResMsg {{ id, body: Pong }}
fn hello_ack(id: Int, session: String) -> ResMsg {{ id, body: HelloAck({ session: session }) }}
pub async fn Runtime::serve_ws(self: Runtime, conn: Conn) -> Unit raise {
  let msg = conn.recv()
  guard msg.kind is Text else {
    conn.send(err(0, "text_only").to_json())
    self.flush(conn.id)
    return
  }
  let json = parse(msg.read_all().text()) catch {
    _ => {
      conn.send(err(0, "invalid_json").to_json())
      self.flush(conn.id)
      return
    }
  }
  let req: ReqMsg = from_json(json) catch {
    _ => {
      conn.send(err(0, "invalid_message").to_json())
      self.flush(conn.id)
      return
    }
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

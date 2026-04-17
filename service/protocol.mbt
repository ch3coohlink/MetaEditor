pub enum Role { Browser; Client } derive(FromJson, ToJson)
pub struct HelloReq { role: Role; session: String } derive(FromJson)
pub struct HelloRes { session: String } derive(ToJson)
pub struct QueryReq { path: String; query: @src.NodeQuery }
pub struct DispatchReq { path: String; event: @src.DomEvent }
pub enum Req { Hello(HelloReq); Query(QueryReq); Dispatch(DispatchReq); Cli(String); Ping }
pub enum Res { HelloAck(HelloRes); Query(@src.NodeValue); Cli(String); Pong; Ok; Err(String) } derive(ToJson)
pub struct ReqMsg { id: Int; body: Req }
pub struct ResMsg { id: Int; body: Res } derive(ToJson)
impl FromJson for QueryReq with from_json(json, path) {
  let obj = json_obj(json, path)
  let path_v: String = obj.get("path")
  let query_v: @src.NodeQuery = obj.get("query")
  { path: path_v, query: query_v }
}
impl FromJson for DispatchReq with from_json(json, path) {
  let obj = json_obj(json, path)
  let path_v: String = obj.get("path")
  let event_v: @src.DomEvent = obj.get("event")
  { path: path_v, event: event_v }
}
impl FromJson for Req with from_json(json, path) {
  let obj = json_obj(json, path)
  match obj.get("type") {
    "hello" => Hello(from_json(json, path~))
    "query" => Query(from_json(json, path~))
    "dispatch" => Dispatch(from_json(json, path~))
    "cli" => Cli(from_json(json, path~))
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
  let res = (match req.body {
    Hello(hello) => {
      let res = match hello.role {
        Browser => if hello.session == "" { err(req.id, "missing_session") }
          else { hello_ack(req.id, hello.session) }
        Client => if hello.session == "" { err(req.id, "missing_session") }
          else { hello_ack(req.id, hello.session) }
      }
      conn.role = match hello.role { Browser => "Browser"; Client => "Client" }
      conn.send(res.to_json()); self.flush(conn.id)
      guard res.body is HelloAck(_) else { return }
      if conn.role == "Browser" { self.replay(conn.id); self.flush(conn.id) }
      return
    }
    Ping => pong(req.id)
    Query(q) => { id: req.id, body: Res::Query(self.rt.query(q.path, q.query)) }
    Dispatch(q) => { self.rt.dispatch(q.path, q.event); { id: req.id, body: Ok } }
    Cli(q) => {
      let cli = CLI::new(["repl", ..CLIArgs::split(q)])
      { id: req.id, body: Res::Cli(cli.exec(is_repl=true, is_local=true)) }
    }
  }) catch { e => err(req.id, e.to_string()) }
  conn.send(res.to_json())
  self.flush(conn.id)
}

struct Client { ws: WS; mut id: Int }
fn Client::new(ws: WS) -> Client {{ ws, id: 1 }}
pub fn Client::close(self: Client) -> Unit { self.ws.close() }
pub async fn Client::connect(port: Int) -> Client raise {
  let client = Client::new(@websocket.connect("ws://127.0.0.1:\{port}\{http_path_ws}"))
  match client.request(id => {{
    "id": id, "type": "hello", "role": "Client", "session": "client-\{current_pid_ffi()}"
  }}) {
    Array([String("HelloAck"), ..]) => client
    _ => { client.close(); raise ServiceError("invalid hello response") }
  }
}
fn Client::read(text: String, expected: Int) -> Json raise {
  match parse(text) {
    Object(fields) => {
      let id = match fields.get("id") { Some(Number(v, ..)) => v.to_int(); _ => -1 }
      if id != expected { raise ServiceError("unexpected response id: \{id}") }
      match fields.get("body") {
        Some(Array([String("Err"), String(msg)])) => raise ServiceError(msg)
        Some(body) => body
        None => raise ServiceError("invalid response")
      }
    }
    _ => raise ServiceError("invalid response")
  }
}
async fn Client::send(self: Client, req: Json) -> Json raise {
  let id = self.id
  self.ws.send_text(req.stringify())
  let body = Client::read(self.ws.recv().read_all().text(), id)
  self.id = self.id + 1
  body
}
async fn Client::request(self: Client, req: (Int) -> Json) -> Json raise {
  self.send(req(self.id))
}
pub async fn Client::cli(self: Client, cmd: String) -> String raise {
  match self.request(id => {{ "id": id, "type": "cli", "cmd": cmd }}) {
    Array([String("Cli"), String(out)]) => out
    _ => raise ServiceError("invalid cli response")
  }
}
pub async fn Client::exec(port: Int, cmd: String) -> String raise {
  let client = Client::connect(port)
  defer client.close()
  client.cli(cmd)
}

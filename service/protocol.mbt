pub struct CommandMsg { cmd: String?; arg: String? } derive(ToJson, FromJson)
pub struct ResponseMsg { ok: Bool?; error: String?; result: Json? } derive(ToJson, FromJson)
pub enum Response { Text(String); Json(Json) }
pub fn Response::to_json(self: Response) -> Json {
  match self { Text(s) => Json::string(s); Json(v) => v }
}
pub async fn Response::send_http(self: Response, conn: @http.ServerConnection) -> Unit {
  let payload = ({ ok: Some(true), error: None, result: Some(self.to_json()) } : ResponseMsg).to_json()
  HTTP::send(conn, payload.stringify(), 200, "OK", header={ "Content-Type": "application/json" })
}

pub struct BridgeHelloMsg { role: String; session_id: String; user_agent: String } derive(FromJson)
pub struct BridgePingMsg { seq: Int; latency_ms: Int? } derive(FromJson)
pub struct BridgeResponseMsg { request_id: Int; ok: Bool; result: Json?; error: String? } derive(FromJson)
pub struct BridgeRequestMsg { request_id: Int; action: String; path: String?; cmd: String?; arg: String? }
  derive(FromJson)
pub struct BridgeEventMsg { id: Int; event: String?; data: Json? } derive(FromJson)
pub enum BridgeIncomingMsg { Hello(BridgeHelloMsg); Ping(BridgePingMsg); Response(BridgeResponseMsg);
  Request(BridgeRequestMsg); Event(BridgeEventMsg) }
fn[T] bad_msg(path: @json.JsonPath, msg: String) -> T raise @json.JsonDecodeError {
  raise @json.JsonDecodeError((path, "BridgeIncomingMsg::from_json: \{msg}"))
}
impl @json.FromJson for BridgeIncomingMsg with from_json(json, path) {
  let type_ = match json {
    Object(fields) => match fields.get("type") {
      Some(String(v)) => v
      _ => bad_msg(path, "missing type")
    }
    _ => bad_msg(path, "expected object")
  }
  match type_ {
    "bridge:hello" => Hello(@json.from_json(json, path=path))
    "bridge:ping" => Ping(@json.from_json(json, path=path))
    "bridge:response" => Response(@json.from_json(json, path=path))
    "bridge:request" => Request(@json.from_json(json, path=path))
    "bridge:event" => Event(@json.from_json(json, path=path))
    _ => bad_msg(path, "unknown type")
  }
}

struct WsHelloAck { session_id: String; reconnected: Bool } derive(ToJson)
struct WsRejected { reason: String } derive(ToJson)
enum WsOut { HelloAck(WsHelloAck); Rejected(WsRejected) }
impl ToJson for WsOut with to_json(self: WsOut) -> Json {
  match self {
    HelloAck(msg) => {
      { "type": "bridge:hello_ack", "session_id": msg.session_id, "reconnected": msg.reconnected }
    }
    Rejected(msg) => { "type": "bridge:rejected", "reason": msg.reason }
  }
}
fn hello_ack(session_id: String) -> WsOut { HelloAck({ session_id, reconnected: false }) }
fn rejected(reason: String) -> WsOut { Rejected({ reason, }) }

pub async fn Runtime::serve_ws(self: Runtime, conn: Conn) -> Unit raise {
  let msg = conn.recv()
  guard msg.kind is Text else {
    conn.send(rejected("text_only").to_json())
    self.flush(conn.id)
    return
  }
  let json = @json.parse(msg.read_all().text()) catch {
    _ => {
      conn.send(rejected("invalid_json").to_json())
      self.flush(conn.id)
      return
    }
  }
  let incoming: BridgeIncomingMsg = @json.from_json(json) catch {
    _ => {
      conn.send(rejected("invalid_message").to_json())
      self.flush(conn.id)
      return
    }
  }
  match incoming {
    Hello(hello) => {
      let res = if hello.role != "browser" { rejected("unsupported_role") }
      else if hello.session_id == "" { rejected("missing_session_id") }
      else { hello_ack(hello.session_id) }
      conn.send(res.to_json())
    }
    _ => conn.send(rejected("unsupported_message").to_json())
  }
  self.flush(conn.id)
}

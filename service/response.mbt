// pub(all) enum Response {
//   Text(String)
//   Json(Json)
// }

// pub(all) struct ResponseMsg {
//   ok : Bool?
//   error : String?
//   result : Json?
// } derive(ToJson, FromJson)

// struct BridgePongMsg {
//   seq: Int
// }

// struct BridgeHelloAckMsg {
//   session_id: String
//   reconnected: Bool
// }

// struct BridgeRejectedMsg {
//   reason: String
// }

// struct BridgeResultMsg {
//   type_: String
//   request_id: Int
//   ok: Bool
//   result: Json
//   error: String
// }

// impl ToJson for BridgePongMsg with to_json(self: BridgePongMsg) -> Json {
//   { "type": "bridge:pong", "seq": self.seq }
// }

// impl ToJson for BridgeHelloAckMsg with to_json(self: BridgeHelloAckMsg) -> Json {
//   { "type": "bridge:hello_ack", "session_id": self.session_id, "reconnected": self.reconnected }
// }

// impl ToJson for BridgeRejectedMsg with to_json(self: BridgeRejectedMsg) -> Json {
//   { "type": "bridge:rejected", "reason": self.reason }
// }

// impl ToJson for BridgeResultMsg with to_json(self: BridgeResultMsg) -> Json {
//   {
//     "type": self.type_,
//     "request_id": self.request_id,
//     "ok": self.ok,
//     "result": self.result,
//     "error": self.error,
//   }
// }

// pub fn Response::to_json(self : Response) -> Json {
//   match self {
//     Text(s) => Json::string(s)
//     Json(v) => v
//   }
// }

// fn format_query_text(result : Json) -> String {
//   let kind = json_string(result, "kind").unwrap_or("")
//   if kind == "text" && json_field(result, "id") is Some(_) {
//     let id = json_int(result, "id").unwrap_or(0)
//     let text = json_string(result, "text").unwrap_or("")
//     return "id: \{id}\ntext: \{text}\n"
//   }
//   if kind == "attr" || kind == "prop" || kind == "style" {
//     let id = json_int(result, "id").unwrap_or(0)
//     let key = json_string(result, "key").unwrap_or("")
//     let value = json_string(result, "value").unwrap_or("")
//     return "kind: \{kind}\nid: \{id}\nkey: \{key}\nvalue: \{value}\n"
//   }
//   let out = StringBuilder::new()
//   out.write_string("kind: \{kind}\n")
//   if json_field(result, "id") is Some(_) {
//     let id = json_int(result, "id").unwrap_or(0)
//     out.write_string("id: \{id}\n")
//   }
//   if json_field(result, "tag") is Some(_) {
//     let tag = json_string(result, "tag").unwrap_or("")
//     out.write_string("tag: \{tag}\n")
//   }
//   if json_field(result, "text") is Some(_) {
//     let text = json_string(result, "text").unwrap_or("")
//     out.write_string("text: \{text}\n")
//   }
//   if json_field(result, "value") is Some(_) {
//     let value = json_string(result, "value").unwrap_or("")
//     out.write_string("value: \{value}\n")
//   }
//   if json_field(result, "checked") is Some(_) {
//     let checked = json_bool(result, "checked").unwrap_or(false)
//     out.write_string("checked: \{checked}\n")
//   }
//   if json_field(result, "focused") is Some(_) {
//     let focused = json_bool(result, "focused").unwrap_or(false)
//     out.write_string("focused: \{focused}\n")
//   }
//   if json_field(result, "visible") is Some(_) {
//     let visible = json_bool(result, "visible").unwrap_or(false)
//     out.write_string("visible: \{visible}\n")
//   }
//   if out.to_string() == "kind: \n" { result.stringify() + "\n" } else { out.to_string() }
// }

// fn format_trigger_text(result : Json) -> String {
//   let kind = json_string(result, "kind").unwrap_or("")
//   let ok = json_bool(result, "ok").unwrap_or(true)
//   let out = StringBuilder::new()
//   out.write_string("ok: \{ok}\n")
//   out.write_string("kind: \{kind}\n")
//   if json_field(result, "id") is Some(_) {
//     let id = json_int(result, "id").unwrap_or(0)
//     out.write_string("id: \{id}\n")
//   }
//   if json_field(result, "event") is Some(_) {
//     let event = json_string(result, "event").unwrap_or("")
//     out.write_string("event: \{event}\n")
//   }
//   if json_field(result, "name") is Some(_) {
//     let name = json_string(result, "name").unwrap_or("")
//     out.write_string("event: \{name}\n")
//   }
//   if json_field(result, "target_id") is Some(_) {
//     let target_id = json_int(result, "target_id").unwrap_or(0)
//     out.write_string("target_id: \{target_id}\n")
//   }
//   out.to_string()
// }

// fn format_output(format: OutputFormat, result: Json) -> String {
//   match format {
//     StringResult => match result { String(s) => s; _ => result.stringify() + "\n" }
//     Query => format_query_text(result)
//     Trigger => format_trigger_text(result)
//     Fixed(text) => text
//   }
// }

// pub fn Response::to_cli(self : Response, format : OutputFormat, as_json : Bool) -> String {
//   let result = self.to_json()
//   if as_json { return result.stringify() + "\n" }
//   format_output(format, result)
// }

// pub async fn Response::send_http(self : Response, conn : @http.ServerConnection) -> Unit {
//   let payload = {
//     ok: Some(true),
//     error: None,
//     result: Some(self.to_json()),
//   }.to_json()
//   HTTP::send(
//     conn,
//     payload.stringify(),
//     200,
//     "OK",
//     header={ "Content-Type": "application/json" },
//   )
// }

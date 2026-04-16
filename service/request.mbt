// pub(all) struct CommandMsg {
//   cmd : String?
//   arg : String?
// } derive(ToJson, FromJson)

// pub(all) struct FlagDef {
//   name : String
//   has_value : Bool
// }

// struct CmdContext {
//   args : Array[String]
//   flags : Map[String, String?]
// }

// fn CmdContext::get_bool(self : CmdContext, key : String) -> Bool {
//   self.flags.get(key) is Some(_)
// }

// fn CmdContext::get_string(self : CmdContext, key : String) -> String? {
//   match self.flags.get(key) {
//     Some(Some(v)) => Some(v)
//     _ => None
//   }
// }

// pub(all) enum UiPathTriggerKind {
//   Click(String)
//   Input(String)
//   Key(String, String, String, Bool, Bool, Bool, Bool)
//   DragToPath(String)
//   DragToId(Int)
// }

// pub(all) enum UiPathRequest {
//   Query(String, String)
//   Trigger(UiPathTriggerKind)
//   Sync
// }

// pub fn ui_path_query(kind: String, value~: String = "") -> UiPathRequest {
//   UiPathRequest::Query(kind, value)
// }

// pub fn ui_path_trigger_click(kind: String) -> UiPathRequest {
//   UiPathRequest::Trigger(UiPathTriggerKind::Click(kind))
// }

// pub fn ui_path_trigger_input(text: String) -> UiPathRequest {
//   UiPathRequest::Trigger(UiPathTriggerKind::Input(text))
// }

// pub fn ui_path_trigger_key(
//   key: String,
//   key_event~ : String = "press",
//   code~ : String = "",
//   ctrl_key~ : Bool = false,
//   shift_key~ : Bool = false,
//   alt_key~ : Bool = false,
//   meta_key~ : Bool = false,
// ) -> UiPathRequest {
//   UiPathRequest::Trigger(UiPathTriggerKind::Key(
//     key,
//     key_event,
//     code,
//     ctrl_key,
//     shift_key,
//     alt_key,
//     meta_key,
//   ))
// }

// pub fn ui_path_trigger_drag_to_path(path: String) -> UiPathRequest {
//   UiPathRequest::Trigger(UiPathTriggerKind::DragToPath(path))
// }

// pub fn ui_path_trigger_drag_to_id(id: Int) -> UiPathRequest {
//   UiPathRequest::Trigger(UiPathTriggerKind::DragToId(id))
// }

// pub fn ui_path_sync() -> UiPathRequest {
//   UiPathRequest::Sync
// }

// struct BridgeEventMsg {
//   id: Int
//   event: String?
//   data: Json?
// } derive(FromJson)

// struct BridgeRequestMsg {
//   request_id: Int
//   action: String
//   path: String?
//   cmd: String?
//   arg: String?
// } derive(FromJson)

// struct BridgeResponseMsg {
//   request_id: Int
//   ok: Bool
//   result: Json?
//   error: String?
// } derive(FromJson)

// struct BridgePingMsg {
//   seq: Int
//   latency_ms: Int?
// } derive(FromJson)

// pub(all) struct BridgeHelloClientMsg {
//   role: String
//   session_id: String
//   user_agent: String
// }

// struct BridgeHelloMsg {
//   role: String
//   session_id: String
//   user_agent: String
// } derive(FromJson)

// struct ReplRequestMsg {
//   request_id: Int
//   cmd: String
//   arg: String
// } derive(FromJson)

// enum BridgeIncomingMsg {
//   Hello(BridgeHelloMsg)
//   Ping(BridgePingMsg)
//   Response(BridgeResponseMsg)
//   Request(BridgeRequestMsg)
//   Event(BridgeEventMsg)
// }

// enum ReplIncomingMsg {
//   Request(ReplRequestMsg)
// }

// pub(all) struct BridgeEventOutMsg {
//   id: Int
//   event: String
//   data: Json?
// }

// struct BridgeRequestOutMsg {
//   request_id: Int
//   action: String
//   query: Json?
//   command: Json?
// }

// pub(all) struct ReplRequestOutMsg {
//   request_id: Int
//   cmd: String
//   arg: String
// }

// enum CmdAction {
//   Local(async (CmdContext) -> Unit raise)
//   Remote(async (Runtime, CmdContext) -> Response raise)
// }

// enum OutputFormat {
//   StringResult
//   Query
//   Trigger
//   Fixed(String)
// }

// struct RequestCmd {
//   name : String
//   usage : String
//   desc : String
//   flags : Array[FlagDef]
//   allow_unknown : Bool
//   action : CmdAction
//   output : OutputFormat
//   client_fallback : (CmdContext) -> String?
// }

// fn RequestCmd::is_local(self : RequestCmd) -> Bool {
//   match self.action {
//     Local(_) => true
//     Remote(_) => false
//   }
// }

// fn request_cmd(
//   name: String,
//   desc: String,
//   action: CmdAction,
//   usage~ : String = "",
//   flags~ : Array[FlagDef] = [],
//   allow_unknown~ : Bool = false,
//   output~ : OutputFormat = StringResult,
//   client_fallback~ : (CmdContext) -> String? = _ => None,
// ) -> RequestCmd {
//   { name, usage, desc, flags, allow_unknown, action, output, client_fallback }
// }

// fn start_flags() -> Array[FlagDef] {
//   [
//     { name: "silent", has_value: false },
//     { name: "port", has_value: true },
//   ]
// }

// fn parse_flags(
//   defs : Array[FlagDef],
//   argv : Array[String],
//   allow_unknown : Bool,
// ) -> CmdContext raise {
//   let args : Array[String] = []
//   let flags : Map[String, String?] = Map::new()
//   let mut i = 0
//   while i < argv.length() {
//     let token = argv[i]
//     if !token.has_prefix("--") {
//       args.push(token)
//       i += 1
//       continue
//     }
//     let name = token[2:].to_string()
//     let mut def : FlagDef? = None
//     for item in defs {
//       if item.name == name {
//         def = Some(item)
//         break
//       }
//     }
//     match def {
//       Some({ has_value: true, .. }) => {
//         if i + 1 >= argv.length() { raise ServiceError("missing value for --\{name}") }
//         flags.set(name, Some(argv[i + 1]))
//         i += 2
//       }
//       Some(_) => {
//         flags.set(name, None)
//         i += 1
//       }
//       None => {
//         if !allow_unknown { raise ServiceError("unknown flag: --\{name}") }
//         flags.set(name, None)
//         i += 1
//       }
//     }
//   }
//   { args, flags }
// }

// fn split_shell_args(line : String) -> Array[String] raise {
//   let parts : Array[String] = []
//   let mut cur = ""
//   let mut in_quote = false
//   let mut i = 0
//   while i < line.length() {
//     let ch = line[i:i + 1].to_string()
//     if ch == "\\" && i + 1 < line.length() {
//       i += 1
//       cur += line[i:i + 1].to_string()
//     } else if ch == "\"" {
//       in_quote = !in_quote
//     } else if !in_quote && (ch == " " || ch == "\t" || ch == "\n" || ch == "\r") {
//       if cur != "" {
//         parts.push(cur)
//         cur = ""
//       }
//     } else {
//       cur += ch
//     }
//     i += 1
//   }
//   if in_quote { raise ServiceError("unterminated quote") }
//   if cur != "" { parts.push(cur) }
//   parts
// }

// fn get_commands() -> Array[RequestCmd] {
//   [
//     request_cmd(
//       "start",
//       "Start the service.",
//       Local(async fn(ctx) { Runtime::start(Runtime::parse_port(ctx).unwrap_or(default_port), ctx.get_bool("silent")) }),
//       flags=start_flags(),
//     ),
//     request_cmd(
//       "restart",
//       "Restart the service.",
//       Local(async fn(ctx) { Runtime::restart(Runtime::parse_port(ctx), ctx.get_bool("silent")) }),
//       flags=start_flags(),
//     ),
//     request_cmd(
//       "status",
//       "Show whether the service is running.",
//       Remote(async fn(runtime, _ctx) { Response::Text(runtime.status_text()) }),
//     ),
//     request_cmd(
//       "stop",
//       "Stop the service.",
//       Local(async fn(_ctx) { Runtime::stop() }),
//     ),
//     request_cmd(
//       "roots",
//       "Replace top-level root entry.",
//       Remote(async fn(runtime, ctx) {
//         Response::Text(runtime.mount_roots(ctx.args))
//       }),
//       usage="[ENTRY_ID]",
//     ),
//     request_cmd(
//       "sync",
//       "Wait browser bridge sync.",
//       Remote(async fn(runtime, _ctx) {
//         runtime.sync_browser()
//         Response::Text("ok")
//       }),
//       output=Fixed("synced\n"),
//     ),
//     request_cmd(
//       "query",
//       "Read one browser node by ui-id path.",
//       Remote(async fn(runtime, ctx) {
//         match ctx.args {
//           [path, "attr", prop] => Response::Json(runtime.query_ui(path, "attr", value=prop))
//           [path, "prop", prop] => Response::Json(runtime.query_ui(path, "prop", value=prop))
//           [path, "style", prop] => Response::Json(runtime.query_ui(path, "style", value=prop))
//           [path, "text"] => Response::Json(runtime.query_ui(path, "text"))
//           [path, "node"] => Response::Json(runtime.query_ui(path, "node"))
//           [path] => Response::Json(runtime.query_ui(path, "node"))
//           _ => raise ServiceError("Usage: query PATH [node|text|attr PROP|prop PROP|style PROP] [--json]")
//         }
//       }),
//       usage="PATH [node|text|attr PROP|prop PROP|style PROP]",
//       flags=[{ name: "json", has_value: false }],
//       output=Query,
//     ),
//     request_cmd(
//       "trigger",
//       "Trigger one browser DOM action.",
//       Remote(async fn(runtime, ctx) {
//         if ctx.args.length() < 2 { raise ServiceError("Invalid trigger arguments") }
//         match ctx.args {
//           [path, ("focus" | "blur" | "click" | "dblclick" | "scrollIntoView" as k)] =>
//             Response::Json(runtime.trigger_ui(path, k))
//           [path, "input", t] =>
//             Response::Json(runtime.trigger_ui(path, "input", text=Some(t)))
//           [path, "drag_to", t] =>
//             Response::Json(runtime.trigger_ui(path, "drag_to", target_path=Some(t)))
//           [path, "key", k] =>
//             Response::Json(runtime.trigger_ui(
//               path,
//               "key",
//               key=Some(k),
//               key_event=Some(ctx.get_string("event").unwrap_or("press")),
//               code=ctx.get_string("code"),
//               ctrl_key=ctx.get_bool("ctrl"),
//               shift_key=ctx.get_bool("shift"),
//               alt_key=ctx.get_bool("alt"),
//               meta_key=ctx.get_bool("meta"),
//             ))
//           _ => raise ServiceError("Invalid trigger arguments")
//         }
//       }),
//       usage="PATH <ACTION> [ARGS...]",
//       flags=[
//         { name: "event", has_value: true },
//         { name: "code", has_value: true },
//         { name: "ctrl", has_value: false },
//         { name: "shift", has_value: false },
//         { name: "alt", has_value: false },
//         { name: "meta", has_value: false },
//         { name: "json", has_value: false },
//       ],
//       output=Trigger,
//     ),
//     request_cmd(
//       "repl",
//       "Start a long-lived command session.",
//       Local(async fn(_ctx) { Runtime::repl() }),
//     ),
//   ]
// }

// fn find_command(cmd: String) -> RequestCmd? {
//   for c in get_commands() { if c.name == cmd { return Some(c) } }
//   None
// }

// impl @json.FromJson for BridgeIncomingMsg with from_json(json, path) {
//   let owner = "BridgeIncomingMsg::from_json"
//   let kind = match json_string(json, "type") {
//     Some(kind) => kind
//     None => raise @json.JsonDecodeError((path, "\{owner}: missing type"))
//   }
//   match kind {
//     "bridge:hello" => Hello(@json.from_json(json))
//     "bridge:ping" => Ping(@json.from_json(json))
//     "bridge:response" => Response(@json.from_json(json))
//     "bridge:request" => Request(@json.from_json(json))
//     "event" | "event_data" => Event(@json.from_json(json))
//     kind => raise @json.JsonDecodeError((path, "\{owner}: invalid type \{kind}"))
//   }
// }

// impl @json.FromJson for ReplIncomingMsg with from_json(json, path) {
//   let owner = "ReplIncomingMsg::from_json"
//   let kind = match json_string(json, "type") {
//     Some(kind) => kind
//     None => raise @json.JsonDecodeError((path, "\{owner}: missing type"))
//   }
//   match kind {
//     "repl:request" => Request(@json.from_json(json))
//     kind => raise @json.JsonDecodeError((path, "\{owner}: invalid type \{kind}"))
//   }
// }

// impl ToJson for BridgeHelloClientMsg with to_json(self: BridgeHelloClientMsg) -> Json {
//   {
//     "type": "bridge:hello",
//     "role": self.role,
//     "session_id": self.session_id,
//     "user_agent": self.user_agent,
//   }
// }

// pub impl ToJson for BridgeEventOutMsg with to_json(self: BridgeEventOutMsg) -> Json {
//   let fields : Map[String, Json] = Map::new()
//   fields.set("type", Json::string("event"))
//   fields.set("id", self.id.to_json())
//   fields.set("event", Json::string(self.event))
//   match self.data {
//     Some(data) => fields.set("data", data)
//     None => ()
//   }
//   Json::object(fields)
// }

// impl ToJson for BridgeRequestOutMsg with to_json(self: BridgeRequestOutMsg) -> Json {
//   let fields : Map[String, Json] = Map::new()
//   fields.set("type", Json::string("bridge:request"))
//   fields.set("request_id", self.request_id.to_json())
//   fields.set("action", Json::string(self.action))
//   match self.query {
//     Some(query) => fields.set("query", query)
//     None => ()
//   }
//   match self.command {
//     Some(command) => fields.set("command", command)
//     None => ()
//   }
//   Json::object(fields)
// }

// impl ToJson for ReplRequestOutMsg with to_json(self: ReplRequestOutMsg) -> Json {
//   {
//     "type": "repl:request",
//     "request_id": self.request_id,
//     "cmd": self.cmd,
//     "arg": self.arg,
//   }
// }

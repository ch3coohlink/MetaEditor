struct BridgeEventMsg {
  id: Int
  event: String?
  data: Json?
} derive(FromJson)

pub(all) struct BridgeEventOutMsg {
  id: Int
  event: String
  data: Json?
}

struct BridgeRequestMsg {
  request_id: Int
  action: String
  path: String?
  cmd: String?
  arg: String?
} derive(FromJson)

struct BridgeResponseMsg {
  request_id: Int
  ok: Bool
  result: Json?
  error: String?
} derive(FromJson)

struct BridgeQueryResult {
  id: Int
} derive(ToJson)

struct BridgePongMsg {
  seq: Int
}

struct BridgeHelloAckMsg {
  session_id: String
  reconnected: Bool
}

struct BridgeRejectedMsg {
  reason: String
}

struct BridgeResultMsg {
  type_: String
  request_id: Int
  ok: Bool
  result: Json
  error: String
}

struct BridgeRequestOutMsg {
  request_id: Int
  request: @src.UiRequest
}

struct BridgePingMsg {
  seq: Int
  latency_ms: Int?
} derive(FromJson)

pub(all) struct BridgeHelloClientMsg {
  role: String
  session_id: String
  user_agent: String
}

struct BridgeHelloMsg {
  role: String
  session_id: String
  user_agent: String
} derive(FromJson)

struct ReplRequestMsg {
  request_id: Int
  cmd: String
  arg: String
} derive(FromJson)

enum BridgeIncomingMsg {
  Hello(BridgeHelloMsg)
  Ping(BridgePingMsg)
  Response(BridgeResponseMsg)
  Request(BridgeRequestMsg)
  Event(BridgeEventMsg)
}

enum ReplIncomingMsg {
  Request(ReplRequestMsg)
}

pub(all) struct ReplRequestOutMsg {
  request_id: Int
  cmd: String
  arg: String
}

pub(all) enum UiPathTriggerKind {
  Click(String)
  Input(String)
  Key(String, String, String, Bool, Bool, Bool, Bool)
  DragToPath(String)
  DragToId(Int)
}

pub(all) enum UiPathRequest {
  Query(String, String)
  Trigger(UiPathTriggerKind)
  Sync
}

pub fn ui_path_query(kind: String, value~: String = "") -> UiPathRequest {
  UiPathRequest::Query(kind, value)
}

pub fn ui_path_trigger_click(kind: String) -> UiPathRequest {
  UiPathRequest::Trigger(UiPathTriggerKind::Click(kind))
}

pub fn ui_path_trigger_input(text: String) -> UiPathRequest {
  UiPathRequest::Trigger(UiPathTriggerKind::Input(text))
}

pub fn ui_path_trigger_key(
  key: String,
  key_event~ : String = "press",
  code~ : String = "",
  ctrl_key~ : Bool = false,
  shift_key~ : Bool = false,
  alt_key~ : Bool = false,
  meta_key~ : Bool = false,
) -> UiPathRequest {
  UiPathRequest::Trigger(UiPathTriggerKind::Key(
    key,
    key_event,
    code,
    ctrl_key,
    shift_key,
    alt_key,
    meta_key,
  ))
}

pub fn ui_path_trigger_drag_to_path(path: String) -> UiPathRequest {
  UiPathRequest::Trigger(UiPathTriggerKind::DragToPath(path))
}

pub fn ui_path_trigger_drag_to_id(id: Int) -> UiPathRequest {
  UiPathRequest::Trigger(UiPathTriggerKind::DragToId(id))
}

pub fn ui_path_sync() -> UiPathRequest {
  UiPathRequest::Sync
}

pub impl ToJson for BridgeEventOutMsg with to_json(self: BridgeEventOutMsg) -> Json {
  let fields : Map[String, Json] = Map::new()
  fields.set("type", Json::string("event"))
  fields.set("id", self.id.to_json())
  fields.set("event", Json::string(self.event))
  match self.data {
    Some(data) => fields.set("data", data)
    None => ()
  }
  Json::object(fields)
}

impl ToJson for BridgePongMsg with to_json(self: BridgePongMsg) -> Json {
  { "type": "bridge:pong", "seq": self.seq }
}

impl ToJson for BridgeHelloAckMsg with to_json(self: BridgeHelloAckMsg) -> Json {
  { "type": "bridge:hello_ack", "session_id": self.session_id, "reconnected": self.reconnected }
}

impl ToJson for BridgeRejectedMsg with to_json(self: BridgeRejectedMsg) -> Json {
  { "type": "bridge:rejected", "reason": self.reason }
}

impl ToJson for BridgeResultMsg with to_json(self: BridgeResultMsg) -> Json {
  {
    "type": self.type_,
    "request_id": self.request_id,
    "ok": self.ok,
    "result": self.result,
    "error": self.error,
  }
}

impl ToJson for BridgeRequestOutMsg with to_json(self: BridgeRequestOutMsg) -> Json {
  let fields = match self.request.to_json() {
    Object(fields) => fields
    _ => abort("UiRequest::to_json must return object")
  }
  fields.set("type", Json::string("bridge:request"))
  fields.set("request_id", self.request_id.to_json())
  Json::object(fields)
}

impl ToJson for BridgeHelloClientMsg with to_json(self: BridgeHelloClientMsg) -> Json {
  {
    "type": "bridge:hello",
    "role": self.role,
    "session_id": self.session_id,
    "user_agent": self.user_agent,
  }
}

impl ToJson for ReplRequestOutMsg with to_json(self: ReplRequestOutMsg) -> Json {
  {
    "type": "repl:request",
    "request_id": self.request_id,
    "cmd": self.cmd,
    "arg": self.arg,
  }
}

impl @json.FromJson for BridgeIncomingMsg with from_json(json, path) {
  let owner = "BridgeIncomingMsg::from_json"
  let kind = match json_string(json, "type") {
    Some(kind) => kind
    None => raise @json.JsonDecodeError((path, "\{owner}: missing type"))
  }
  match kind {
    "bridge:hello" => Hello(@json.from_json(json))
    "bridge:ping" => Ping(@json.from_json(json))
    "bridge:response" => Response(@json.from_json(json))
    "bridge:request" => Request(@json.from_json(json))
    "event" | "event_data" => Event(@json.from_json(json))
    kind => raise @json.JsonDecodeError((path, "\{owner}: invalid type \{kind}"))
  }
}

impl @json.FromJson for ReplIncomingMsg with from_json(json, path) {
  let owner = "ReplIncomingMsg::from_json"
  let kind = match json_string(json, "type") {
    Some(kind) => kind
    None => raise @json.JsonDecodeError((path, "\{owner}: missing type"))
  }
  match kind {
    "repl:request" => Request(@json.from_json(json))
    kind => raise @json.JsonDecodeError((path, "\{owner}: invalid type \{kind}"))
  }
}

fn handle_event(msg: BridgeEventMsg) -> Unit {
  let event = msg.event.unwrap_or("onclick")
  if msg.data is Some(raw_ev) {
    let ev : @src.EventData = try { @json.from_json(raw_ev) } catch { _ => return }
    @src.trigger_node_ev(msg.id, event, ev)
  } else {
    @src.trigger_node(msg.id, event)
  }
}

fn handle_response(runtime: Runtime, data: Json, msg: BridgeResponseMsg) -> Unit {
  if runtime.browser_conn.pending.val.get(msg.request_id) is Some(queue) {
    let _ = queue.try_put(data) catch { _ => false }
  }
}

async fn respond_request(
  ws: @websocket.Conn,
  type_: String,
  request_id: Int,
  ok: Bool,
  result: Json,
  error: String,
) -> Unit {
  let msg : BridgeResultMsg = { type_, request_id, ok, result, error }
  ws.send_text(msg.to_json().stringify())
}

fn resolve_query_id(runtime: Runtime, path: String) -> Int raise {
  @src.runtime_resolve_query(editor_runtime(runtime), path) catch {
    err => raise ServiceError("\{err}")
  }
}

fn request_headless(runtime: Runtime, request: @src.UiRequest) -> Json raise {
  (@src.mock_request(runtime.mock_browser, request) catch {
    err => raise ServiceError("\{err}")
  }).to_json()
}

fn request_action(request: @src.UiRequest) -> String {
  match request {
    @src.UiRequest::Query(_, _, _) => "query"
    @src.UiRequest::Trigger(_, _) => "trigger"
    @src.UiRequest::Sync => "sync"
  }
}

async fn handle_browser_command(runtime: Runtime, cmd: String, arg: String) -> Json raise {
  if cmd == "sync" {
    // browser test 走 bridge 快路径发 command sync 时，不能再回头走 sync_browser(runtime)。
    // 否则会在同一条 browser websocket 上形成 request 里再等 response 的递归等待。
    // 这里把 sync 收成一个空 barrier，实际收敛继续由后面的 query/exists 等待承担。
    return Json::string("synced\n")
  }
  Json::string(run_command(runtime, cmd, arg))
}

async fn browser_request_result(runtime: Runtime, msg: BridgeRequestMsg) -> Json raise {
  match msg.action {
    "query" => { id: resolve_query_id(runtime, msg.path.unwrap_or("")) }.to_json()
    "command" => handle_browser_command(runtime, msg.cmd.unwrap_or(""), msg.arg.unwrap_or(""))
    action => raise ServiceError("unsupported browser request action: \{action}")
  }
}

fn browser_response_result(response: BridgeResponseMsg, request: @src.UiRequest) -> Json raise {
  if !response.ok {
    raise ServiceError(response.error.unwrap_or("browser request failed"))
  }
  match request {
    @src.UiRequest::Query(_, _, _) => {
      let result : @src.UiQueryResult = try {
        @json.from_json(response.result.unwrap_or(null))
      } catch {
        err => raise ServiceError("\{err}")
      }
      result.to_json()
    }
    @src.UiRequest::Trigger(_, _) => {
      let result : @src.UiTriggerResult = try {
        @json.from_json(response.result.unwrap_or(null))
      } catch {
        err => raise ServiceError("\{err}")
      }
      result.to_json()
    }
    @src.UiRequest::Sync =>
      @src.UiResponse::Sync.to_json()
  }
}

async fn handle_browser_request(runtime: Runtime, ws: @websocket.Conn, msg: BridgeRequestMsg) -> Unit {
  try {
    let result = browser_request_result(runtime, msg)
    respond_request(ws, "bridge:response", msg.request_id, true, result, "")
  } catch {
    ServiceError(message) => respond_request(ws, "bridge:response", msg.request_id, false, null, message)
    err => respond_request(ws, "bridge:response", msg.request_id, false, null, "\{err}")
  }
}

pub async fn flush_live_batches(runtime: Runtime) -> Unit {
  for ;; {
    let batch = runtime.live_batches.get() catch {
      _ => return
    }
    match runtime.browser_conn.ws.val {
      Some(ws) => {
        let _ = try { ws.send_text(batch.stringify()) } catch { _ => () }
      }
      None => ()
    }
  }
}

fn build_browser_request(runtime: Runtime, query: String, request: UiPathRequest) -> @src.UiRequest raise {
  let id = resolve_query_id(runtime, query)
  match request {
    Query(kind, value) => @src.ui_query_request(id, kind, value)
    Trigger(trigger) =>
      match trigger {
        Click(kind) => @src.ui_trigger_click(id, kind)
        Input(text) => @src.ui_trigger_input(id, text)
        Key(key, key_event, code, ctrl_key, shift_key, alt_key, meta_key) =>
          @src.ui_trigger_key(id, key, key_event~, code~, ctrl_key~, shift_key~, alt_key~, meta_key~)
        DragToPath(target_path) => @src.ui_trigger_drag_to(id, resolve_query_id(runtime, target_path))
        DragToId(target_id) => @src.ui_trigger_drag_to(id, target_id)
      }
    Sync => @src.ui_sync_request()
  }
}

async fn request_browser(runtime: Runtime, request: @src.UiRequest) -> Json raise {
  let ws = match runtime.browser_conn.ws.val {
    Some(ws) => ws
    None => raise ServiceError("browser is not connected")
  }
  let action = request_action(request)
  let request_id = runtime.browser_conn.next_request_id.val
  runtime.browser_conn.next_request_id.val = request_id + 1
  let queue : @aqueue.Queue[Json] = @aqueue.Queue::new(kind=Unbounded)
  runtime.browser_conn.pending.val.set(request_id, queue)
  let request_json = ({ request_id, request } : BridgeRequestOutMsg).to_json()
  defer {
    runtime.browser_conn.pending.val.remove(request_id)
  }
  let _ = ws
  let _ = runtime.live_batches.try_put(request_json) catch { _ => false }
  let response = wait_timeout(
    "browser response: \{action}#\{request_id}",
    () => queue.try_get() catch { _ => None },
    timeout_ms=6000,
  ) catch {
    err => raise ServiceError("\{err}")
  }
  let resp : BridgeResponseMsg = try {
    @json.from_json(response)
  } catch {
    _ => raise ServiceError("invalid browser response")
  }
  browser_response_result(resp, request)
}

pub async fn sync_browser(runtime : Runtime) -> Unit raise {
  if runtime.browser_conn.ws.val is Some(_) {
    ignore(request_browser(runtime, @src.ui_sync_request()))
  }
}

async fn request_ui_path(runtime: Runtime, request: @src.UiRequest) -> Json raise {
  match runtime.browser_conn.ws.val {
    Some(_) => request_browser(runtime, request)
    None => request_headless(runtime, request)
  }
}

pub async fn query_ui(
  runtime: Runtime,
  path: String,
  kind: String,
  value? : String = "",
) -> @src.UiQueryResult raise {
  try {
    @json.from_json(request_ui_path(
      runtime,
      @src.ui_query_request(resolve_query_id(runtime, path), kind, value),
    ))
  } catch {
    err => raise ServiceError("\{err}")
  }
}

pub async fn trigger_ui(
  runtime: Runtime,
  path: String,
  kind: String,
  text? : String? = None,
  key? : String? = None,
  key_event? : String? = None,
  code? : String? = None,
  ctrl_key? : Bool = false,
  shift_key? : Bool = false,
  alt_key? : Bool = false,
  meta_key? : Bool = false,
  target_path? : String? = None,
) -> @src.UiTriggerResult raise {
  let id = resolve_query_id(runtime, path)
  let request = match kind {
    "input" => @src.ui_trigger_input(id, text.unwrap_or(""))
    "key" => @src.ui_trigger_key(
      id,
      key.unwrap_or(""),
      key_event=key_event.unwrap_or("press"),
      code=code.unwrap_or(""),
      ctrl_key~,
      shift_key~,
      alt_key~,
      meta_key~,
    )
    "drag_to" => @src.ui_trigger_drag_to(
      id,
      match target_path { Some(v) => resolve_query_id(runtime, v); None => 0 },
    )
    _ => @src.ui_trigger_click(id, kind)
  }
  try {
    @json.from_json(request_ui_path(runtime, request))
  } catch {
    err => raise ServiceError("\{err}")
  }
}

pub async fn request_browser_path(runtime: Runtime, query: String, request: UiPathRequest) -> Json raise {
  let built = build_browser_request(runtime, query, request)
  request_ui_path(runtime, built)
}

fn respond_pong(runtime: Runtime, msg: BridgePingMsg) -> Unit {
  if msg.latency_ms is Some(latency_ms) {
    let tray = @src.get_host_tray()
    @src.set_host_tray("\{latency_ms}ms", tray.time_text)
    @src.try_flush() // websocket 回调里改 reactive 状态不走 src 事件主路径，需要手动 flush
  }
  let pong : BridgePongMsg = { seq: msg.seq }
  let _ = runtime.live_batches.try_put(pong.to_json()) catch { _ => false }
}

fn respond_hello_ack(runtime: Runtime, session_id: String, reconnected: Bool) -> Unit {
  let ack : BridgeHelloAckMsg = { session_id, reconnected }
  let _ = runtime.live_batches.try_put(ack.to_json()) catch { _ => false }
}

async fn reject_browser(ws: @websocket.Conn, reason: RejectReason) -> Unit {
  let msg : BridgeRejectedMsg = { reason: reject_reason_code(reason) }
  ws.send_text(msg.to_json().stringify())
  let _ = try { ws.send_close(reason=reject_reason_code(reason)) } catch { _ => () }
}

fn accept_browser(
  runtime: Runtime,
  ws: @websocket.Conn,
  conn_id: Int,
  session_id: String,
  reconnected: Bool,
) -> Unit {
  runtime.browser_conn.ws.val = Some(ws)
  runtime.browser_conn.active_id.val = conn_id
  respond_hello_ack(runtime, session_id, reconnected)
  @src.set_host_tray("0ms", format_tray_time(@async.now()))
  @src.runtime_render(editor_runtime(runtime))
}

async fn handle_bridge_hello(
  runtime: Runtime,
  ws: @websocket.Conn,
  conn_id: Int,
  msg: BridgeHelloMsg,
) -> Unit {
  match accept_hello(runtime.state, msg.role, msg.session_id, msg.user_agent) {
    Ack(reconnected) => accept_browser(runtime, ws, conn_id, msg.session_id, reconnected)
    Rejected(reason) => reject_browser(ws, reason)
  }
}

fn on_browser_disconnect(runtime: Runtime, conn_id: Int) -> Unit {
  if runtime.browser_conn.active_id.val == conn_id {
    runtime.browser_conn.ws.val = None
    runtime.browser_conn.active_id.val = 0
    runtime.browser_conn.pending.val.clear()
    disconnect_browser(runtime.state, @async.now())
  }
}

async fn handle_repl_request(runtime: Runtime, ws: @websocket.Conn, msg: ReplRequestMsg) -> Unit {
  try {
    let result = if msg.cmd == "stop" {
      request_stop_service(runtime)
      Json::string("stopped\n")
    } else {
      run_command_result(runtime, msg.cmd, msg.arg)
    }
    respond_request(ws, "repl:response", msg.request_id, true, result, "")
  } catch {
    ServiceError(message) =>
      respond_request(ws, "repl:response", msg.request_id, false, Json::string(""), message)
    e => respond_request(ws, "repl:response", msg.request_id, false, Json::string(""), "\{e}")
  }
  if runtime.shutting_down.val {
    invoke_stop_service(runtime)
  }
}

async fn handle_browser_message(
  runtime: Runtime,
  ws: @websocket.Conn,
  conn_id: Int,
  data: Json,
) -> Unit {
  let msg : BridgeIncomingMsg = try { @json.from_json(data) } catch { _ => return }
  match msg {
    Hello(msg) => handle_bridge_hello(runtime, ws, conn_id, msg)
    Ping(msg) => respond_pong(runtime, msg)
    Response(msg) => handle_response(runtime, data, msg)
    Request(msg) => handle_browser_request(runtime, ws, msg)
    Event(msg) => handle_event(msg)
  }
  if runtime.shutting_down.val {
    invoke_stop_service(runtime)
  }
}

async fn handle_repl_message(
  runtime: Runtime,
  ws: @websocket.Conn,
  _conn_id: Int,
  data: Json,
) -> Unit {
  let msg : ReplIncomingMsg = try { @json.from_json(data) } catch { _ => return }
  match msg { Request(msg) => handle_repl_request(runtime, ws, msg) }
  if runtime.shutting_down.val {
    invoke_stop_service(runtime)
  }
}

async fn serve_ws_generic(
  runtime: Runtime,
  request: @http.Request,
  conn: @http.ServerConnection,
  on_disconnect: (Runtime, Int) -> Unit,
  handle_msg: async (Runtime, @websocket.Conn, Int, Json) -> Unit,
) -> Unit {
  let ws = @websocket.from_http_server(request, conn)
  let conn_id = runtime.browser_conn.next_id.val
  runtime.browser_conn.next_id.val = conn_id + 1
  defer {
    on_disconnect(runtime, conn_id)
    ws.close()
  }
  try {
    for ;; {
      let msg = ws.recv()
      match msg.kind {
        Text => handle_msg(runtime, ws, conn_id, msg.read_all().json())
        Binary => ()
      }
    }
  } catch {
    @websocket.ConnectionClosed(_, _) => ()
    _ => ()
  }
}

pub async fn serve_websocket(runtime: Runtime, request: @http.Request, conn: @http.ServerConnection) -> Unit {
  serve_ws_generic(runtime, request, conn, on_browser_disconnect, handle_browser_message)
}

pub async fn serve_repl_websocket(runtime: Runtime, request: @http.Request, conn: @http.ServerConnection) -> Unit {
  serve_ws_generic(runtime, request, conn, fn(_r, _c) { () }, handle_repl_message)
}

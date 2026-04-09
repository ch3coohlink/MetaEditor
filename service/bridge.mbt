struct BridgeEventMsg {
  event: String?
  id: Int?
  data: String?
} derive(FromJson)

struct BridgeRequestMsg {
  request_id: Int?
  action: String?
  path: String?
  cmd: String?
  arg: String?
} derive(FromJson)

struct BridgeResponseMsg {
  request_id: Int?
} derive(FromJson)

struct BridgePingMsg {
  seq: Int?
  latency_ms: Int?
} derive(FromJson)

struct BridgeHelloMsg {
  role: String?
  session_id: String?
  user_agent: String?
} derive(FromJson)

struct ReplRequestMsg {
  request_id: Int?
  cmd: String?
  arg: String?
} derive(FromJson)

fn json_type(data: Json) -> String {
  match data { Object(m) => match m.get("type") { Some(String(v)) => v; _ => "" }; _ => "" }
}

fn handle_event(data : Json) -> Unit {
  let msg : BridgeEventMsg = try { @json.from_json(data) } catch { _ => return }
  let event = msg.event.unwrap_or("onclick")
  if msg.id is Some(id) {
    if msg.data is Some(raw_ev) {
      @src.trigger_node_ev(id, event, @src.EventData::from_json(raw_ev))
    } else {
      @src.trigger_node(id, event)
    }
  }
}

fn handle_response(runtime : Runtime, data : Json) -> Unit {
  let msg : BridgeResponseMsg = try { @json.from_json(data) } catch { _ => return }
  if msg.request_id is Some(id) {
    if runtime.browser_conn.pending.val.get(id) is Some(queue) {
      let _ = queue.try_put(data) catch { _ => false }
    }
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
  ws.send_text(Json::object({
    "type": Json::string(type_),
    "request_id": request_id.to_json(),
    "ok": ok.to_json(),
    "result": result,
    "error": Json::string(error),
  }).stringify())
}

fn resolve_query_id(runtime: Runtime, path: String) -> Int raise {
  @src.runtime_resolve_query(editor_runtime(runtime), path) catch {
    err => raise ServiceError("\{err}")
  }
}

fn request_headless(runtime: Runtime, request: @src.UiRequest) -> Json raise {
  @src.mock_request(runtime.mock_browser, request) catch {
    err => raise ServiceError("\{err}")
  }
}

fn request_action(request: @src.UiRequest) -> String {
  match request {
    @src.UiRequest::Query(_, _, _) => "query"
    @src.UiRequest::Trigger(_, _, _, _, _, _, _, _, _, _, _) => "trigger"
    @src.UiRequest::Sync => "sync"
  }
}

fn request_to_json(request: @src.UiRequest) -> Json {
  match request {
    @src.UiRequest::Query(id, kind, value) => {
      "action": "query",
      "id": id.to_json(),
      "kind": Json::string(kind),
      "value": Json::string(value),
    }
    @src.UiRequest::Trigger(id, kind, text, key, key_event, code, ctrl_key, shift_key, alt_key, meta_key, target_id) => {
      let fields : Map[String, Json] = {
        "action": Json::string("trigger"),
        "id": id.to_json(),
        "kind": Json::string(kind),
      }
      match text { Some(v) => fields.set("text", Json::string(v)); None => () }
      match key { Some(v) => fields.set("key", Json::string(v)); None => () }
      match key_event { Some(v) => fields.set("key_event", Json::string(v)); None => () }
      match code { Some(v) => fields.set("code", Json::string(v)); None => () }
      if ctrl_key { fields.set("ctrl_key", true.to_json()) }
      if shift_key { fields.set("shift_key", true.to_json()) }
      if alt_key { fields.set("alt_key", true.to_json()) }
      if meta_key { fields.set("meta_key", true.to_json()) }
      match target_id { Some(v) => fields.set("target_id", v.to_json()); None => () }
      Json::object(fields)
    }
    @src.UiRequest::Sync => { "action": "sync" }
  }
}

fn json_string_field(fields: Map[String, Json], key: String, fallback~ : String = "") -> String {
  match fields.get(key) {
    Some(String(v)) => v
    _ => fallback
  }
}

fn json_opt_string_field(fields: Map[String, Json], key: String) -> String? {
  match fields.get(key) {
    Some(String(v)) => Some(v)
    _ => None
  }
}

fn json_is_true(value: Json?) -> Bool {
  match value {
    Some(True) => true
    _ => false
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

async fn handle_browser_request(runtime: Runtime, ws: @websocket.Conn, data: Json) -> Unit {
  let msg : BridgeRequestMsg = try { @json.from_json(data) } catch { _ => return }
  let request_id = msg.request_id.unwrap_or(0)
  try {
    let result = match msg.action.unwrap_or("") {
      "query" => Json::object({
        "id": resolve_query_id(runtime, msg.path.unwrap_or("")).to_json(),
      })
      "command" => handle_browser_command(runtime, msg.cmd.unwrap_or(""), msg.arg.unwrap_or(""))
      action => raise ServiceError("unsupported browser request action: \{action}")
    }
    respond_request(ws, "bridge:response", request_id, true, result, "")
  } catch {
    ServiceError(message) => respond_request(ws, "bridge:response", request_id, false, null, message)
    err => respond_request(ws, "bridge:response", request_id, false, null, "\{err}")
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

fn build_browser_request(runtime: Runtime, query: String, request: Json) -> @src.UiRequest raise {
  match request {
    Object(fields) => {
      let id = resolve_query_id(runtime, query)
      match fields.get("action") {
        Some(String("query")) => {
          @src.ui_query_request(
            id,
            json_string_field(fields, "kind", fallback="node"),
            json_string_field(fields, "value"),
          )
        }
        Some(String("trigger")) => {
          let target_id = match fields.get("target_path") {
            Some(String(target_path)) => Some(resolve_query_id(runtime, target_path))
            _ => None
          }
          @src.ui_trigger_request(
            id,
            json_string_field(fields, "kind"),
            text=json_opt_string_field(fields, "text"),
            key=json_opt_string_field(fields, "key"),
            key_event=json_opt_string_field(fields, "key_event"),
            code=json_opt_string_field(fields, "code"),
            ctrl_key=json_is_true(fields.get("ctrl_key")),
            shift_key=json_is_true(fields.get("shift_key")),
            alt_key=json_is_true(fields.get("alt_key")),
            meta_key=json_is_true(fields.get("meta_key")),
            target_id=target_id,
          )
        }
        Some(String("sync")) => @src.ui_sync_request()
        _ => raise ServiceError("invalid browser request")
      }
    }
    _ => raise ServiceError("invalid browser request")
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
  let request = match request_to_json(request) {
    Object(fields) => {
      fields.set("type", Json::string("bridge:request"))
      fields.set("request_id", request_id.to_json())
      Json::object(fields)
    }
    _ => raise ServiceError("invalid browser request")
  }
  defer {
    runtime.browser_conn.pending.val.remove(request_id)
  }
  let _ = ws
  let _ = runtime.live_batches.try_put(request) catch { _ => false }
  let response = wait_timeout(
    "browser response: \{action}#\{request_id}",
    () => queue.try_get() catch { _ => None },
    timeout_ms=6000,
  ) catch {
    err => raise ServiceError("\{err}")
  }
  let resp : ResponseMsg = try {
    @json.from_json(response)
  } catch {
    _ => raise ServiceError("invalid browser response")
  }
  if resp.ok != Some(true) {
    raise ServiceError(resp.error.unwrap_or("browser request failed"))
  }
  resp.result.unwrap_or(null)
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

pub async fn query_ui(runtime: Runtime, path: String, kind: String, value? : String = "") -> Json raise {
  request_ui_path(runtime, @src.ui_query_request(resolve_query_id(runtime, path), kind, value))
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
) -> Json raise {
  request_ui_path(
    runtime,
    @src.ui_trigger_request(
      resolve_query_id(runtime, path), kind, text~, key~, key_event~, code~,
      ctrl_key~, shift_key~, alt_key~, meta_key~,
      target_id=match target_path { Some(v) => Some(resolve_query_id(runtime, v)); None => None },
    ),
  )
}

pub async fn request_browser_path(runtime: Runtime, query: String, request: Json) -> Json raise {
  let built = build_browser_request(runtime, query, request)
  request_ui_path(runtime, built)
}

fn respond_pong(runtime: Runtime, data: Json) -> Unit {
  let msg : BridgePingMsg = try { @json.from_json(data) } catch { _ => return }
  if msg.latency_ms is Some(latency_ms) {
    let tray = @src.get_host_tray()
    @src.set_host_tray("\{latency_ms}ms", tray.time_text)
    @src.try_flush() // websocket 回调里改 reactive 状态不走 src 事件主路径，需要手动 flush
  }
  let _ = runtime.live_batches.try_put({
    "type": "bridge:pong",
    "seq": msg.seq.unwrap_or(0).to_json(),
  }) catch { _ => false }
}

fn respond_hello_ack(runtime: Runtime, session_id: String, reconnected: Bool) -> Unit {
  let _ = runtime.live_batches.try_put({
    "type": "bridge:hello_ack",
    "session_id": session_id,
    "reconnected": reconnected,
  }) catch { _ => false }
}

async fn reject_browser(ws: @websocket.Conn, reason: RejectReason) -> Unit {
  ws.send_text(Json::object({
    "type": Json::string("bridge:rejected"),
    "reason": Json::string(reject_reason_code(reason)),
  }).stringify())
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
  data: Json,
) -> Unit {
  let msg : BridgeHelloMsg = try { @json.from_json(data) } catch { _ => return }
  let role = msg.role.unwrap_or("")
  let session_id = msg.session_id.unwrap_or("")
  let user_agent = msg.user_agent.unwrap_or("")
  match accept_hello(runtime.state, role, session_id, user_agent) {
    Ack(reconnected) => accept_browser(runtime, ws, conn_id, session_id, reconnected)
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

async fn handle_repl_request(runtime: Runtime, ws: @websocket.Conn, data: Json) -> Unit {
  let msg : ReplRequestMsg = try { @json.from_json(data) } catch { _ => return }
  let request_id = msg.request_id.unwrap_or(0)
  let cmd = msg.cmd.unwrap_or("")
  try {
    let result = if cmd == "stop" {
      request_stop_service(runtime)
      "stopped\n"
    } else {
      run_command(runtime, cmd, msg.arg.unwrap_or(""))
    }
    respond_request(ws, "repl:response", request_id, true, Json::string(result), "")
  } catch {
    ServiceError(message) => respond_request(ws, "repl:response", request_id, false, Json::string(""), message)
    e => respond_request(ws, "repl:response", request_id, false, Json::string(""), "\{e}")
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
  let kind = json_type(data)
  match kind {
    "bridge:hello" => handle_bridge_hello(runtime, ws, conn_id, data)
    "bridge:ping" => respond_pong(runtime, data)
    "bridge:response" => handle_response(runtime, data)
    "bridge:request" => handle_browser_request(runtime, ws, data)
    "event" | "event_data" => handle_event(data)
    _ => ()
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
  let kind = json_type(data)
  match kind {
    "repl:request" => handle_repl_request(runtime, ws, data)
    _ => ()
  }
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

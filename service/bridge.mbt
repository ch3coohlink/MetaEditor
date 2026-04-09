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

struct BridgeJsonResult {
  type_: String
  request_id: Int
  ok: Bool
  result: Json
  error: String
}

struct BridgeJsonMsg {
  type_: String
  fields: Array[(String, Json)]
}

fn bridge_json_msg(type_: String, fields: Array[(String, Json)]) -> BridgeJsonMsg {
  { type_, fields }
}

fn json_fields_to_value(fields_data: Array[(String, Json)]) -> Json {
  let fields : Map[String, Json] = Map::new()
  for field in fields_data {
    fields.set(field.0, field.1)
  }
  Json::object(fields)
}

fn bridge_json_to_value(msg: BridgeJsonMsg) -> Json {
  json_fields_to_value([("type", Json::string(msg.type_)), ..msg.fields])
}

fn bridge_result_to_json(msg: BridgeJsonResult) -> Json {
  bridge_json_to_value(bridge_json_msg(msg.type_, [
    ("request_id", msg.request_id.to_json()),
    ("ok", msg.ok.to_json()),
    ("result", msg.result),
    ("error", Json::string(msg.error)),
  ]))
}

fn ui_request_to_json(request: @src.UiRequest) -> Json {
  let fields : Array[(String, Json)] = []
  match request {
    @src.UiRequest::Query(id, kind, value) => {
      fields.push(("id", id.to_json()))
      fields.push(("action", Json::string("query")))
      fields.push(("kind", Json::string(kind)))
      fields.push(("value", Json::string(value)))
    }
    @src.UiRequest::Trigger(id, trigger) => {
      fields.push(("id", id.to_json()))
      fields.push(("action", Json::string("trigger")))
      match trigger {
        @src.UiTriggerKind::Click(kind) => {
          fields.push(("kind", Json::string(kind)))
        }
        @src.UiTriggerKind::Input(text) => {
          fields.push(("kind", Json::string("input")))
          fields.push(("text", Json::string(text)))
        }
        @src.UiTriggerKind::Key(key, key_event, code, ctrl_key, shift_key, alt_key, meta_key) => {
          fields.push(("kind", Json::string("key")))
          fields.push(("key", Json::string(key)))
          fields.push(("key_event", Json::string(key_event)))
          if code != "" { fields.push(("code", Json::string(code))) }
          if ctrl_key { fields.push(("ctrl_key", true.to_json())) }
          if shift_key { fields.push(("shift_key", true.to_json())) }
          if alt_key { fields.push(("alt_key", true.to_json())) }
          if meta_key { fields.push(("meta_key", true.to_json())) }
        }
        @src.UiTriggerKind::DragTo(target_id) => {
          fields.push(("kind", Json::string("drag_to")))
          fields.push(("target_id", target_id.to_json()))
        }
      }
    }
    @src.UiRequest::Sync => {
      fields.push(("action", Json::string("sync")))
    }
  }
  bridge_json_to_value(bridge_json_msg("bridge:request", fields))
}

fn bridge_query_result_to_json(id: Int) -> Json {
  json_fields_to_value([("id", id.to_json())])
}

fn bridge_pong_to_json(seq: Int) -> Json {
  bridge_json_to_value(bridge_json_msg("bridge:pong", [("seq", seq.to_json())]))
}

fn bridge_hello_ack_to_json(session_id: String, reconnected: Bool) -> Json {
  bridge_json_to_value(bridge_json_msg("bridge:hello_ack", [
    ("session_id", Json::string(session_id)),
    ("reconnected", reconnected.to_json()),
  ]))
}

fn bridge_rejected_to_json(reason: String) -> Json {
  bridge_json_to_value(bridge_json_msg("bridge:rejected", [("reason", Json::string(reason))]))
}

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
  ws.send_text(bridge_result_to_json({ type_, request_id, ok, result, error }).stringify())
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

async fn handle_browser_request(runtime: Runtime, ws: @websocket.Conn, data: Json) -> Unit {
  let msg : BridgeRequestMsg = try { @json.from_json(data) } catch { _ => return }
  let request_id = msg.request_id.unwrap_or(0)
  try {
    let result = match msg.action.unwrap_or("") {
      "query" => bridge_query_result_to_json(resolve_query_id(runtime, msg.path.unwrap_or("")))
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
  let id = resolve_query_id(runtime, query)
  let action = json_string(request, "action").unwrap_or("")
  match action {
    "query" => @src.ui_query_request(
      id,
      json_string(request, "kind").unwrap_or("node"),
      json_string(request, "value").unwrap_or(""),
    )
    "trigger" =>
      match json_string(request, "kind").unwrap_or("") {
        "input" => @src.ui_trigger_input(id, json_string(request, "text").unwrap_or(""))
        "key" => @src.ui_trigger_key(
          id,
          json_string(request, "key").unwrap_or(""),
          key_event=json_string(request, "key_event").unwrap_or("press"),
          code=json_string(request, "code").unwrap_or(""),
          ctrl_key=json_bool(request, "ctrl_key").unwrap_or(false),
          shift_key=json_bool(request, "shift_key").unwrap_or(false),
          alt_key=json_bool(request, "alt_key").unwrap_or(false),
          meta_key=json_bool(request, "meta_key").unwrap_or(false),
        )
        "drag_to" => @src.ui_trigger_drag_to(
          id,
          match json_string(request, "target_path") {
            Some(target_path) => resolve_query_id(runtime, target_path)
            None => json_int(request, "target_id").unwrap_or(0)
          },
        )
        kind => @src.ui_trigger_click(id, kind)
      }
    "sync" => @src.ui_sync_request()
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
  let request = match ui_request_to_json(request) {
    Object(fields) => {
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
  request_ui_path(runtime, request)
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
  let _ = runtime.live_batches.try_put(bridge_pong_to_json(msg.seq.unwrap_or(0))) catch { _ => false }
}

fn respond_hello_ack(runtime: Runtime, session_id: String, reconnected: Bool) -> Unit {
  let _ = runtime.live_batches.try_put(
    bridge_hello_ack_to_json(session_id, reconnected)
  ) catch { _ => false }
}

async fn reject_browser(ws: @websocket.Conn, reason: RejectReason) -> Unit {
  ws.send_text(bridge_rejected_to_json(reject_reason_code(reason)).stringify())
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
      Json::string("stopped\n")
    } else {
      run_command_result(runtime, cmd, msg.arg.unwrap_or(""))
    }
    respond_request(ws, "repl:response", request_id, true, result, "")
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

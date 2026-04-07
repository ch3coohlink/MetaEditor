struct BridgeEventMsg {
  event: String?
  id: Int?
  data: String?
} derive(FromJson)

struct BridgeResponseMsg {
  request_id: Int?
  ok: Bool?
  error: String?
  result: Json?
} derive(FromJson)

struct BridgeRequestMsg {
  request_id: Int?
  action: String?
} derive(FromJson)

struct BridgeQueryPathMsg {
  path: String?
} derive(FromJson)

struct BridgeTriggerPathMsg {
  path: String?
  kind: String?
  text: String?
  key: String?
  key_event: String?
  code: String?
  ctrl_key: Bool?
  shift_key: Bool?
  alt_key: Bool?
  meta_key: Bool?
  target_path: String?
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

async fn respond_browser_response(
  ws: @websocket.Conn,
  request_id: Int,
  ok: Bool,
  result: Json,
  error: String,
) -> Unit {
  ws.send_text(Json::object({
    "type": Json::string("bridge:response"),
    "request_id": request_id.to_json(),
    "ok": ok.to_json(),
    "result": result,
    "error": Json::string(error),
  }).stringify())
}

fn handle_browser_query_from_path(runtime: Runtime, data: Json) -> Json raise {
  let msg : BridgeQueryPathMsg = try { @json.from_json(data) } catch { _ => raise ServiceError("missing browser query") }
  let path = msg.path.unwrap_or("")
  let id = @src.runtime_resolve_query(editor_runtime(runtime), path) catch {
    err => raise ServiceError("\{err}")
  }
  {
    "id": id,
  }
}

async fn handle_browser_trigger_from_path(runtime: Runtime, data: Json) -> Json raise {
  let msg : BridgeTriggerPathMsg = try { @json.from_json(data) } catch { _ => raise ServiceError("missing browser trigger") }
  let path = msg.path.unwrap_or("")
  let id = @src.runtime_resolve_query(editor_runtime(runtime), path) catch {
    err => raise ServiceError("\{err}")
  }
  let kind = msg.kind.unwrap_or("")
  let request : Map[String, Json] = {
    "action": Json::string("trigger"),
    "id": id.to_json(),
    "kind": Json::string(kind),
  }
  match msg.text {
    Some(text) => request["text"] = Json::string(text)
    None => ()
  }
  match msg.key {
    Some(key) => request["key"] = Json::string(key)
    None => ()
  }
  match msg.key_event {
    Some(key_event) => request["key_event"] = Json::string(key_event)
    None => ()
  }
  match msg.code {
    Some(code) => request["code"] = Json::string(code)
    None => ()
  }
  if msg.ctrl_key == Some(true) { request["ctrl_key"] = true.to_json() }
  if msg.shift_key == Some(true) { request["shift_key"] = true.to_json() }
  if msg.alt_key == Some(true) { request["alt_key"] = true.to_json() }
  if msg.meta_key == Some(true) { request["meta_key"] = true.to_json() }
  match msg.target_path {
    Some(target_path) => {
      let target_id = @src.runtime_resolve_query(editor_runtime(runtime), target_path) catch {
        err => raise ServiceError("\{err}")
      }
      request["target_id"] = target_id.to_json()
    }
    None => ()
  }
  request_browser(runtime, Json::object(request))
}

async fn handle_browser_command(runtime: Runtime, data: Json) -> Json raise {
  let c : Command = try { @json.from_json(data) } catch { _ => { cmd: None, arg: None } }
  let cmd = c.cmd.unwrap_or("")
  let arg = c.arg.unwrap_or("")
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
  let action = msg.action.unwrap_or("")
  try {
    let result = match action {
      "query" => handle_browser_query_from_path(runtime, data)
      "trigger" => handle_browser_trigger_from_path(runtime, data)
      "command" => handle_browser_command(runtime, data)
      _ => raise ServiceError("unsupported browser request action: \{action}")
    }
    respond_browser_response(ws, request_id, true, result, "")
  } catch {
    ServiceError(message) => respond_browser_response(ws, request_id, false, null, message)
    err => respond_browser_response(ws, request_id, false, null, "\{err}")
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

async fn request_browser(runtime: Runtime, request: Json) -> Json raise {
  let ws = match runtime.browser_conn.ws.val {
    Some(ws) => ws
    None => raise ServiceError("browser is not connected")
  }
  let action = match request {
    Object(m) => match m.get("action") { Some(String(v)) => v; _ => "request" }
    _ => "request"
  }
  let request_id = runtime.browser_conn.next_request_id.val
  runtime.browser_conn.next_request_id.val = request_id + 1
  let queue : @aqueue.Queue[Json] = @aqueue.Queue::new(kind=Unbounded)
  runtime.browser_conn.pending.val.set(request_id, queue)
  let request = match request {
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
  let resp : BridgeResponseMsg = try {
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
  ignore(request_browser(runtime, { "action": "sync" }))
}

pub(all) enum BrowserQueryRequest {
  Node
  Text
}

pub async fn request_browser_query(
  runtime : Runtime,
  query : String,
  request : BrowserQueryRequest,
) -> Json raise {
  let id = @src.runtime_resolve_query(editor_runtime(runtime), query) catch {
    err => raise ServiceError("\{err}")
  }
  request_browser(runtime, match request {
    Node => { "action": "query", "kind": "node", "id": id }
    Text => { "action": "query", "kind": "text", "id": id }
  })
}

pub async fn request_browser_trigger(
  runtime : Runtime,
  query : String,
  kind : String,
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
  let id = @src.runtime_resolve_query(editor_runtime(runtime), query) catch {
    err => raise ServiceError("\{err}")
  }
  let request : Map[String, Json] = {
    "action": Json::string("trigger"),
    "kind": Json::string(kind),
    "id": id.to_json(),
  }
  match text {
    Some(text) => request["text"] = Json::string(text)
    None => ()
  }
  match key {
    Some(key) => request["key"] = Json::string(key)
    None => ()
  }
  match key_event {
    Some(key_event) => request["key_event"] = Json::string(key_event)
    None => ()
  }
  match code {
    Some(code) => request["code"] = Json::string(code)
    None => ()
  }
  if ctrl_key { request["ctrl_key"] = true.to_json() }
  if shift_key { request["shift_key"] = true.to_json() }
  if alt_key { request["alt_key"] = true.to_json() }
  if meta_key { request["meta_key"] = true.to_json() }
  match target_path {
    Some(target_path) => {
      let target_id = @src.runtime_resolve_query(editor_runtime(runtime), target_path) catch {
        err => raise ServiceError("\{err}")
      }
      request["target_id"] = target_id.to_json()
    }
    None => ()
  }
  request_browser(runtime, Json::object(request))
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

async fn respond_repl(
  ws: @websocket.Conn,
  request_id: Int,
  ok: Bool,
  result: String,
  error: String,
) -> Unit {
  ws.send_text(Json::object({
    "type": Json::string("repl:response"),
    "request_id": request_id.to_json(),
    "ok": ok.to_json(),
    "result": Json::string(result),
    "error": Json::string(error),
  }).stringify())
}

async fn handle_repl_request(runtime: Runtime, ws: @websocket.Conn, data: Json) -> Unit {
  let msg : ReplRequestMsg = try { @json.from_json(data) } catch { _ => return }
  let request_id = msg.request_id.unwrap_or(0)
  let cmd = msg.cmd.unwrap_or("")
  let arg = msg.arg.unwrap_or("")
  if cmd == "stop" {
    request_stop_service(runtime)
    respond_repl(ws, request_id, true, "stopped\n", "")
    invoke_stop_service(runtime)
    return
  }
  try {
    let result = run_command(runtime, cmd, arg)
    respond_repl(ws, request_id, true, result, "")
    if runtime.shutting_down.val {
      invoke_stop_service(runtime)
    }
  } catch {
    ServiceError(message) => respond_repl(ws, request_id, false, "", message)
    e => respond_repl(ws, request_id, false, "", "\{e}")
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

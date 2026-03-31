fn handle_event(data : Json) -> Unit {
  let event = json_string(data, "event").unwrap_or("onclick")
  if json_int(data, "id") is Some(id) {
    if json_string(data, "data") is Some(raw_ev) {
      @src.trigger_node_ev(id, event, @src.EventData::from_json(raw_ev))
    } else {
      @src.trigger_node(id, event)
    }
    return
  }
  if json_string(data, "ui_id") is Some(ui_id) {
    if json_string(data, "data") is Some(raw_ev) {
      @src.trigger_ui_ev(ui_id, event, @src.EventData::from_json(raw_ev))
    } else {
      @src.trigger_ui(ui_id, event)
    }
  }
}

fn handle_response(runtime : Runtime, data : Json) -> Unit {
  match json_int(data, "request_id") {
    Some(id) =>
      match runtime.browser_conn.pending.val.get(id) {
        Some(queue) => {
          let _ = queue.try_put(data) catch { _ => false }
        }
        None => ()
      }
    None => ()
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

fn browser_connected(runtime : Runtime) -> Bool {
  match runtime.browser_conn.ws.val {
    Some(_) => true
    None => false
  }
}

async fn request_browser(runtime: Runtime, request: Json) -> Json raise {
  let ws = match runtime.browser_conn.ws.val {
    Some(ws) => ws
    None => raise ServiceError("browser is not connected")
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
  for tries = 0; tries < 300; tries = tries + 1 {
    match queue.try_get() {
      Some(response) => {
        if !json_bool(response, "ok").unwrap_or(false) {
          raise ServiceError(json_string(response, "error").unwrap_or("browser request failed"))
        }
        return json_field(response, "result").unwrap_or(null)
      }
      None => @async.sleep(20)
    }
  }
  raise ServiceError("browser request timed out")
}

pub async fn query_browser(runtime : Runtime, query : Json) -> Json raise {
  request_browser(runtime, { "action": "query", "query": query })
}

pub async fn exec_browser(runtime : Runtime, command : Json) -> Json raise {
  request_browser(runtime, { "action": "exec", "command": command })
}

pub async fn sync_browser(runtime : Runtime) -> Unit raise {
  ignore(request_browser(runtime, { "action": "sync" }))
}

pub async fn sync_browser_if_connected(runtime : Runtime) -> Unit raise {
  if !browser_connected(runtime) { return }
  sync_browser(runtime)
}

async fn send_json(ws: @websocket.Conn, json: Json) -> Unit {
  ws.send_text(json.stringify())
}

async fn reject_browser(ws: @websocket.Conn, reason: RejectReason) -> Unit {
  send_json(ws, { "type": "bridge:rejected", "reason": reject_reason_code(reason) })
  let _ = try { ws.send_close(reason=reject_reason_code(reason)) } catch { _ => () }
}

async fn accept_browser(
  runtime: Runtime,
  ws: @websocket.Conn,
  conn_id: Int,
  session_id: String,
  reconnected: Bool,
) -> Unit {
  runtime.browser_conn.ws.val = Some(ws)
  runtime.browser_conn.active_id.val = conn_id
  send_json(ws, { "type": "bridge:hello_ack", "session_id": session_id, "reconnected": reconnected })
  render_app(runtime)
}

async fn handle_bridge_hello(
  runtime: Runtime,
  ws: @websocket.Conn,
  conn_id: Int,
  data: Json,
) -> Unit {
  let role = json_string(data, "role").unwrap_or("")
  let session_id = json_string(data, "session_id").unwrap_or("")
  let user_agent = json_string(data, "user_agent").unwrap_or("")
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
  send_json(ws, {
    "type": "repl:response",
    "request_id": request_id,
    "ok": ok,
    "result": result,
    "error": error,
  })
}

async fn handle_repl_request(runtime: Runtime, ws: @websocket.Conn, data: Json) -> Unit {
  let request_id = json_int(data, "request_id").unwrap_or(0)
  let cmd = json_string(data, "cmd").unwrap_or("")
  let arg = json_string(data, "arg").unwrap_or("")
  if cmd == "stop" {
    request_stop_service(runtime)
    respond_repl(ws, request_id, true, "stopped\n", "")
    invoke_stop_service(runtime)
    return
  }
  try {
    let result = run(runtime, cmd, arg)
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
  let kind = json_string(data, "type").unwrap_or("")
  match kind {
    "bridge:hello" => handle_bridge_hello(runtime, ws, conn_id, data)
    "bridge:response" => handle_response(runtime, data)
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
  let kind = json_string(data, "type").unwrap_or("")
  match kind {
    "repl:request" => handle_repl_request(runtime, ws, data)
    _ => ()
  }
  if runtime.shutting_down.val {
    invoke_stop_service(runtime)
  }
}

pub async fn serve_websocket(
  runtime: Runtime,
  request: @http.Request,
  conn: @http.ServerConnection,
) -> Unit {
  let ws = @websocket.from_http_server(request, conn)
  let conn_id = runtime.browser_conn.next_id.val
  runtime.browser_conn.next_id.val = conn_id + 1
  defer {
    on_browser_disconnect(runtime, conn_id)
    ws.close()
  }
  try {
    for ;; {
      let msg = ws.recv()
      match msg.kind {
        Text => handle_browser_message(runtime, ws, conn_id, msg.read_all().json())
        Binary => ()
      }
    }
  } catch {
    @websocket.ConnectionClosed(_, _) => ()
    _ => ()
  }
}

pub async fn serve_repl_websocket(
  runtime: Runtime,
  request: @http.Request,
  conn: @http.ServerConnection,
) -> Unit {
  let ws = @websocket.from_http_server(request, conn)
  let conn_id = runtime.browser_conn.next_id.val
  runtime.browser_conn.next_id.val = conn_id + 1
  defer {
    ws.close()
  }
  try {
    for ;; {
      let msg = ws.recv()
      match msg.kind {
        Text => handle_repl_message(runtime, ws, conn_id, msg.read_all().json())
        Binary => ()
      }
    }
  } catch {
    @websocket.ConnectionClosed(_, _) => ()
    _ => ()
  }
}

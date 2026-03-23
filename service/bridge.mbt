pub fn handle_event(data : Json) -> Unit {
  if json_int(data, "callback_id") is Some(id) {
    if json_string(data, "data") is Some(raw_ev) {
      @src.trigger_callback_ev(id, @src.EventData::from_json(raw_ev))
    } else {
      @src.trigger_callback(id)
    }
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
    disconnect_browser(runtime.state, @async.now())
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
    "event" | "event_data" => handle_event(data)
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

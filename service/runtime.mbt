fn action_callback_id(runtime : Runtime, name : String) -> Int? {
  runtime.app_actions.get(name)
}

fn track_batch(runtime : Runtime, cmds : Array[String]) -> Unit {
  let batch : Array[Json] = []
  for cmd in cmds {
    let json = @json.parse(cmd) catch { _ => null }
    if json is Array([Number(tag, ..), String(name), Number(callback_id, ..)]) {
      if tag == 8 {
        let parsed : Result[Int, _] = try? @json.from_json(callback_id.to_json())
        match parsed {
          Ok(id) => runtime.app_actions[name] = id
          Err(_) => ()
        }
      }
    }
    batch.push(json)
    runtime.ui_history.push(json)
  }
  let _ = runtime.live_batches.try_put(Json::array(batch)) catch { _ => false }
}

fn init_app(runtime : Runtime) -> Unit {
  @src.init_bridge(fn(cmds) { track_batch(runtime, cmds) })
  let _ = try {
    @src.scope(fn() { @app.start() })
  } catch {
    _ => fn() {}
  }
}

async fn flush_live_batches(runtime : Runtime) -> Unit {
  for ;; {
    let batch = runtime.live_batches.get()
    match runtime.browser_ws.val {
      Some(ws) => {
        let _ = try { ws.send_text(batch.stringify()) } catch { _ => () }
      }
      None => ()
    }
  }
}

async fn send_json(ws : @websocket.Conn, json : Json) -> Unit {
  ws.send_text(json.stringify())
}

async fn reject_browser(ws : @websocket.Conn, reason : RejectReason) -> Unit {
  send_json(ws, { "type": "bridge:rejected", "reason": reject_reason_code(reason) })
  let _ = try { ws.send_close(reason=reject_reason_code(reason)) } catch { _ => () }
}

pub fn browser_init_messages(
  ui_history : Array[Json],
  session_id : String,
  reconnected : Bool,
) -> Array[Json] {
  let messages : Array[Json] = [{
    "type": "bridge:hello_ack",
    "session_id": session_id,
    "reconnected": reconnected,
  }]
  if ui_history.length() > 0 {
    messages.push(Json::array(ui_history))
  }
  messages
}

async fn accept_browser(
  runtime : Runtime,
  ws : @websocket.Conn,
  conn_id : Int,
  session_id : String,
  reconnected : Bool,
) -> Unit {
  runtime.browser_ws.val = Some(ws)
  runtime.active_conn_id.val = conn_id
  for message in browser_init_messages(runtime.ui_history, session_id, reconnected) {
    send_json(ws, message)
  }
}

async fn handle_bridge_hello(
  runtime : Runtime,
  ws : @websocket.Conn,
  conn_id : Int,
  data : Json,
) -> Unit {
  let role = json_string(data, "role").unwrap_or("")
  let session_id = json_string(data, "session_id").unwrap_or("")
  let user_agent = json_string(data, "user_agent").unwrap_or("")
  match accept_hello(runtime.state, role, session_id, user_agent) {
    Ack(reconnected) => accept_browser(runtime, ws, conn_id, session_id, reconnected)
    Rejected(reason) => reject_browser(ws, reason)
  }
}

fn on_browser_disconnect(runtime : Runtime, conn_id : Int) -> Unit {
  if runtime.active_conn_id.val == conn_id {
    runtime.browser_ws.val = None
    runtime.active_conn_id.val = 0
    disconnect_browser(runtime.state, @async.now())
  }
}

fn response_request_id(json : Json) -> Int? {
  json_int(json, "request_id")
}

fn response_ok(json : Json) -> Bool {
  if json is { "ok": True, .. } {
    true
  } else if json is { "ok": False, .. } {
    false
  } else {
    true
  }
}

fn handle_bridge_response(runtime : Runtime, data : Json) -> Unit {
  match response_request_id(data) {
    Some(request_id) => {
      if response_ok(data) {
        if data is { "result"?: result, .. } {
          runtime.responses[request_id] = Ok(result.unwrap_or(null))
        } else {
          runtime.responses[request_id] = Ok(null)
        }
      } else {
        let error = json_string(data, "error").unwrap_or("browser request failed")
        runtime.responses[request_id] = Err(error)
      }
    }
    None => ()
  }
}

fn handle_event(data : Json) -> Unit {
  match json_int(data, "callback_id") {
    Some(callback_id) => @src.trigger_callback(callback_id)
    None => ()
  }
}

fn handle_event_data(data : Json) -> Unit {
  match json_int(data, "callback_id") {
    Some(callback_id) =>
      @src.trigger_callback_ev(
        callback_id,
        @src.EventData::from_json(json_string(data, "data").unwrap_or("")),
      )
    None => ()
  }
}

async fn handle_browser_message(
  runtime : Runtime,
  ws : @websocket.Conn,
  conn_id : Int,
  data : Json,
) -> Unit {
  let kind = json_string(data, "type").unwrap_or("")
  match kind {
    "bridge:hello" => handle_bridge_hello(runtime, ws, conn_id, data)
    "bridge:response" => handle_bridge_response(runtime, data)
    "event" => handle_event(data)
    "event_data" => handle_event_data(data)
    _ => ()
  }
}

async fn serve_websocket(
  runtime : Runtime,
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let ws = @websocket.from_http_server(request, conn)
  let conn_id = runtime.next_conn_id.val
  runtime.next_conn_id.val = conn_id + 1
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

async fn serve_file(runtime : Runtime, conn : @http.ServerConnection, path : String) -> Unit {
  let full_path = root_file(runtime, path)
  if !@fs.exists(full_path) {
    conn.send_response(404, "NotFound")
    conn.write("Not Found")
    conn.end_response()
    return
  }
  let body = @fs.read_file(full_path)
  conn
  ..send_response(200, "OK", extra_headers={
    "Content-Type": content_type(path),
    "Cache-Control": "no-cache",
  })
  ..write(body.binary())
  .end_response()
}

fn next_addr(addr : @socket.Addr, offset : Int) -> @socket.Addr {
  @socket.Addr::new(addr.ip(), addr.port() + offset)
}

pub fn bind_http_server(addr : @socket.Addr, max_tries : Int) -> @http.Server raise {
  let mut tries = 0
  let mut last_error : Error? = None
  while tries < max_tries {
    let candidate = next_addr(addr, tries)
    match (try? @http.Server::new(candidate) : Result[@http.Server, _]) {
      Ok(server) => return server
      Err(err) => {
        last_error = Some(err)
        tries += 1
      }
    }
  }
  match last_error {
    Some(err) => raise err
    None => raise ServiceError("failed to bind service port")
  }
}

async fn request_browser(runtime : Runtime, payload : Json, timeout_ms : Int) -> Json raise {
  let request_id = runtime.next_request_id.val
  runtime.next_request_id.val = request_id + 1
  let request_map : Map[String, Json] = {}
  match payload {
    Object(map) => {
      for key, value in map {
        request_map[key] = value
      }
    }
    _ => ()
  }
  request_map["type"] = Json::string("bridge:request")
  request_map["request_id"] = request_id.to_json()
  let request = Json::object(request_map)
  match runtime.browser_ws.val {
    Some(ws) => ws.send_text(request.stringify())
    None => raise ServiceError("no browser client connected")
  }
  let started = @async.now()
  for ;; {
    match runtime.responses.get(request_id) {
      Some(Ok(result)) => {
        runtime.responses.remove(request_id)
        return result
      }
      Some(Err(error)) => {
        runtime.responses.remove(request_id)
        raise ServiceError(error)
      }
      None => ()
    }
    if @async.now() - started > timeout_ms.to_int64() {
      raise ServiceError("browser request timeout")
    }
    @async.sleep(10)
  }
}

async fn run_query(runtime : Runtime, raw : String) -> Json raise {
  let query = parse_query(raw)
  let result = request_browser(runtime, {
    "action": "query",
    "query": query_to_json(query),
  }, 3000)
  if query is Ui {
    enrich_ui_snapshot(runtime, result)
  } else {
    result
  }
}

async fn run_action(runtime : Runtime, name : String, settle_ms : Int) -> Json raise {
  match action_callback_id(runtime, name) {
    Some(callback_id) => {
      @src.trigger_callback(callback_id)
      @async.sleep(settle_ms)
      { "ok": true, "kind": "action", "name": name }
    }
    None => raise ServiceError("unknown action: \{name}")
  }
}

async fn run_exec(runtime : Runtime, raw : String) -> Json raise {
  let command = parse_exec(raw)
  match command {
    Action(name, settle_ms) => run_action(runtime, name, settle_ms)
    _ => {
      let result = request_browser(runtime, {
        "action": "exec",
        "command": exec_to_json(command),
      }, 3000)
      let settle_ms = match command {
        Click(_) | Focus(_) | Input(_, _) => 50
        Action(_, settle_ms) => settle_ms
      }
      @async.sleep(settle_ms)
      result
    }
  }
}

async fn query_json(runtime : Runtime, query : Json) -> Json raise {
  let request = request_browser(runtime, {
    "action": "query",
    "query": query,
  }, 3000)
  if json_string(query, "kind").unwrap_or("") == "ui" {
    enrich_ui_snapshot(runtime, request)
  } else {
    request
  }
}

async fn exec_json(runtime : Runtime, command : Json) -> Json raise {
  let result = request_browser(runtime, {
    "action": "exec",
    "command": command,
  }, 3000)
  let settle_ms = match json_string(command, "kind").unwrap_or("") {
    "click" => 50
    "focus" => 50
    "input" => 50
    _ => 0
  }
  if settle_ms > 0 {
    @async.sleep(settle_ms)
  }
  result
}

async fn run_app_test(runtime : Runtime) -> Json raise {
  if !runtime.state.browser_connected.val {
    raise ServiceError("app test requires a connected browser page")
  }
  let initial_ui = query_json(runtime, { "kind": "ui" })
  let add_button = find_snapshot_node(initial_ui, tag="button", text="Add")
  let undo_button = find_snapshot_node(initial_ui, tag="button", text="Undo")
  let redo_button = find_snapshot_node(initial_ui, tag="button", text="Redo")
  let add_id = expect_json_int(add_button, "id")
  let undo_id = expect_json_int(undo_button, "id")
  let redo_id = expect_json_int(redo_button, "id")
  assert_count(initial_ui, 0, 0)

  let viewport = query_json(runtime, { "kind": "viewport" })
  if expect_json_int(viewport, "width") <= 0 || expect_json_int(viewport, "height") <= 0 {
    raise ServiceError("invalid viewport snapshot")
  }

  let first_button = query_json(runtime, {
    "kind": "selector",
    "selector": "button",
  })
  if expect_json_int(first_button, "id") != add_id {
    raise ServiceError("selector query did not resolve Add button")
  }

  if expect_json_string(query_json(runtime, { "kind": "node", "id": add_id }), "text") != "Add" {
    raise ServiceError("unexpected Add button text")
  }
  if expect_json_string(query_json(runtime, { "kind": "node", "id": undo_id }), "text") != "Undo" {
    raise ServiceError("unexpected Undo button text")
  }
  if expect_json_string(query_json(runtime, { "kind": "node", "id": redo_id }), "text") != "Redo" {
    raise ServiceError("unexpected Redo button text")
  }

  let _ = exec_json(runtime, { "kind": "focus", "id": add_id })
  let focused = query_json(runtime, { "kind": "focused" })
  if expect_json_int(focused, "id") != add_id || !expect_json_bool(focused, "focused") {
    raise ServiceError("focus op did not focus Add button")
  }

  let _ = exec_json(runtime, { "kind": "click", "id": add_id })
  assert_count(query_json(runtime, { "kind": "ui" }), 1, 1)

  let _ = run_action(runtime, "add", 50)
  assert_count(query_json(runtime, { "kind": "ui" }), 2, 2)

  let _ = exec_json(runtime, { "kind": "click", "id": undo_id })
  assert_count(query_json(runtime, { "kind": "ui" }), 1, 1)

  let _ = run_action(runtime, "undo", 50)
  assert_count(query_json(runtime, { "kind": "ui" }), 0, 0)

  let _ = run_action(runtime, "redo", 50)
  assert_count(query_json(runtime, { "kind": "ui" }), 1, 1)

  let _ = exec_json(runtime, { "kind": "click", "id": redo_id })
  let final_ui = query_json(runtime, { "kind": "ui" })
  assert_count(final_ui, 2, 2)
  require_action(final_ui, "add")
  require_action(final_ui, "undo")
  require_action(final_ui, "redo")
  match json_field(final_ui, "host") {
    Some(host) =>
      if expect_json_int(host, "connected_browsers") < 1 {
        raise ServiceError("ui host snapshot missing browser connection info")
      }
    None => raise ServiceError("ui snapshot missing host info")
  }
  {
    "ok": true,
    "name": "current_app",
    "count": 2,
    "version": 2,
    "buttons": {
      "add": add_id,
      "undo": undo_id,
      "redo": redo_id,
    },
  }
}


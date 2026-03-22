fn action_callback_id(runtime : Runtime, name : String) -> Int? {
  runtime.app_actions.get(name)
}

struct HostButtonSpec {
  app_id : String
  label : String
  style : String
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

fn app_title(runtime : Runtime, app_id : String) -> String {
  for app in runtime.apps {
    if app.id == app_id {
      return app.title
    }
  }
  app_id
}

fn set_active_app(runtime : Runtime, app_id : String) -> Unit {
  let _ = @src.apply_local(runtime.active_app, "switch:\{app_id}", fn(_) { app_id })
}

fn host_switch_action_name(app_id : String) -> String {
  "host_switch_\{app_id}"
}

fn host_switch_button_specs() -> Array[HostButtonSpec] {
  [
    {
      app_id: "host",
      label: "Switch to Host",
      style: "padding: 10px 14px; background: #1d4ed8; color: white; border: none; border-radius: 8px; cursor: pointer;",
    },
    {
      app_id: "counter",
      label: "Switch to Counter",
      style: "padding: 10px 14px; background: #0f766e; color: white; border: none; border-radius: 8px; cursor: pointer;",
    },
  ]
}

fn host_switch_action(runtime : Runtime, app_id : String) -> @src.Prop {
  @src.reg_action(host_switch_action_name(app_id), fn() { set_active_app(runtime, app_id) })
}

fn render_counter_app(_runtime : Runtime, embedded : Bool) -> @src.VNode {
  @app.build_counter_app(
    title=if embedded { "Counter Preview" } else { "Counter Test App" },
    compact=embedded,
  )
}

fn render_workspace_app(runtime : Runtime, app_id : String) -> @src.Child {
  match app_id {
    "host" => @src.Node(@src.h("div", [
      ("style", @src.S("padding: 18px; border: 1px dashed #c7cfdb; border-radius: 12px; color: #667085; background: #fff;"))
    ], [
      @src.Node(@src.h("div", [("style", @src.S("font-weight: 600; margin-bottom: 8px;"))], [@src.Str("Host Dashboard")])),
      @src.Node(@src.h("div", [], [@src.Str("Select a managed app from the host controls.")]))
    ]))
    "counter" => @src.Node(render_counter_app(runtime, false))
    _ => @src.Node(@src.h("div", [], [@src.Str("Unsupported app: \{app_id}")]))
  }
}

fn render_host_app(runtime : Runtime) -> @src.VNode {
  let switch_actions : Map[String, @src.Prop] = {}
  for spec in host_switch_button_specs() {
    switch_actions[spec.app_id] = host_switch_action(runtime, spec.app_id)
  }
  let stop_service = @src.reg_action("host_stop_service", fn() { request_stop_service(runtime) })
  let top_buttons : Array[@src.Child] = []
  for spec in host_switch_button_specs() {
    match switch_actions.get(spec.app_id) {
      Some(action) =>
        top_buttons.push(@src.Node(@src.h("button", [
          ("onclick", action),
          ("style", @src.S(spec.style))
        ], [@src.Str(spec.label)])))
      None => ()
    }
  }
  top_buttons.push(@src.Node(@src.h("button", [
    ("onclick", stop_service),
    ("style", @src.S("padding: 10px 14px; background: #b42318; color: white; border: none; border-radius: 8px; cursor: pointer;"))
  ], [@src.Str("Stop Service")])))
  let app_rows : Array[@src.Child] = []
  for app in runtime.apps {
    if app.id == "host" {
      continue
    }
    match switch_actions.get(app.id) {
      Some(open_action) =>
        app_rows.push(@src.Node(@src.h("div", [
          ("style", @src.S("display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 0; border-bottom: 1px solid #e6e8ec;"))
        ], [
          @src.Node(@src.h("div", [], [
            @src.Node(@src.h("div", [("style", @src.S("font-weight: 600;"))], [@src.Str(app.title)])),
            @src.Node(@src.h("div", [("style", @src.S("font-size: 12px; color: #667085;"))], [@src.Str("id: \{app.id}")])),
          ])),
          @src.Node(@src.h("div", [("style", @src.S("display: flex; align-items: center; gap: 10px;"))], [
            @src.Dyn(fn() { @src.Str(if runtime.active_app.read() == app.id { "active" } else { "idle" }) }),
            @src.Node(@src.h("button", [
              ("onclick", open_action),
              ("style", @src.S("padding: 8px 12px; background: #111827; color: white; border: none; border-radius: 8px; cursor: pointer;"))
            ], [@src.Str("Open")]))
          ]))
        ])))
      None => ()
    }
  }
  @src.h("div", [
    ("style", @src.S("padding: 24px; font-family: sans-serif; background: #f4f6fb; min-height: 100vh; box-sizing: border-box;"))
  ], [
    @src.Node(@src.h("h1", [("style", @src.S("margin: 0 0 12px;"))], [@src.Str("MetaEditor Host")])),
    @src.Node(@src.h("div", [("style", @src.S("color: #667085; margin-bottom: 20px;"))], [
      @src.Dyn(fn() { @src.Str("Active: \{app_title(runtime, runtime.active_app.read())}") })
    ])),
    @src.Node(@src.h("div", [("style", @src.S("display: flex; gap: 12px; margin-bottom: 20px; flex-wrap: wrap;"))], [
      @src.Arr(top_buttons)
    ])),
    @src.Node(@src.h("div", [("style", @src.S("display: grid; grid-template-columns: minmax(280px, 360px) minmax(320px, 1fr); gap: 24px; align-items: start;"))], [
      @src.Node(@src.h("section", [
        ("style", @src.S("padding: 18px; background: white; border-radius: 14px; box-shadow: 0 10px 30px rgba(15, 23, 42, 0.06);"))
      ], [
        @src.Node(@src.h("h2", [("style", @src.S("margin-top: 0;"))], [@src.Str("Managed Apps")])),
        @src.Arr(app_rows),
      ])),
      @src.Node(@src.h("section", [
        ("style", @src.S("padding: 18px; background: white; border-radius: 14px; box-shadow: 0 10px 30px rgba(15, 23, 42, 0.06);"))
      ], [
        @src.Node(@src.h("h2", [("style", @src.S("margin-top: 0;"))], [@src.Str("Workspace")])),
        @src.Dyn(fn() { render_workspace_app(runtime, runtime.active_app.read()) }),
      ]))
    ]))
  ])
}

fn render_active_app(runtime : Runtime) -> @src.Child {
  runtime.app_actions.clear()
  @src.Node(render_host_app(runtime))
}

fn init_app(runtime : Runtime) -> Unit {
  @src.init_bridge(fn(cmds) { track_batch(runtime, cmds) })
  let _ = try {
    @src.scope(fn() {
      let root = @src.h("div", [], [@src.Dyn(fn() { render_active_app(runtime) })])
      @src.emit(@src.Append(0, root.id))
    })
  } catch {
    _ => fn() {}
  }
  let _ = try { @src.flush() } catch { _ => () }
}

pub fn init_app_for_test(runtime : Runtime) -> Unit {
  init_app(runtime)
}

pub fn ui_history_json(runtime : Runtime) -> Json {
  Json::array(runtime.ui_history)
}

async fn flush_live_batches(runtime : Runtime) -> Unit {
  for ;; {
    let batch = runtime.live_batches.get() catch {
      _ => return
    }
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
  if runtime.stop_requested.val {
    runtime.stop_requested.val = false
    invoke_stop_service(runtime)
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



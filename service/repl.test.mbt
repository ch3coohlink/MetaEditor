async fn with_repl_server(f: async (Runtime, Int) -> Unit raise) -> Unit raise {
  @src.reset_test_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  let server = @http.Server::new(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => flush_live_batches(runtime))
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((request, body, conn) => {
        if request.path == repl_path {
          serve_repl_websocket(runtime, request, conn)
          return
        }
        if request.headers.get("upgrade") is Some("websocket") {
          serve_websocket(runtime, request, conn)
          return
        }
        if request.path == control_path {
          handle(runtime, request, body, conn)
          return
        }
        respond_err(conn, 404, "NotFound", "Not Found")
      })
    })
    f(runtime, server.addr().port())
  })
}

async fn repl_connect(port: Int) -> @websocket.Conn {
  let ws = @websocket.connect("ws://127.0.0.1:\{port}\{repl_path}")
  ws.send_text(Json::object({ "type": "repl:hello" }).stringify())
  let hello = ws.recv().read_all().json()
  assert_eq(json_string(hello, "type"), Some("repl:hello_ack"))
  ws
}

async fn send_repl_ws_request(ws: @websocket.Conn, request_id: Int, cmd: String, arg: String) -> Json {
  ws.send_text(Json::object({
    "type": "repl:request",
    "request_id": request_id.to_json(),
    "cmd": Json::string(cmd),
    "arg": Json::string(arg),
  }).stringify())
  ws.recv().read_all().json()
}

async test "repl websocket hello returns ack" {
  with_repl_server(async fn(_runtime, port) {
    let ws = @websocket.connect("ws://127.0.0.1:\{port}\{repl_path}")
    defer ws.close()
    ws.send_text(Json::object({ "type": "repl:hello" }).stringify())
    let hello = ws.recv().read_all().json()
    assert_eq(json_string(hello, "type"), Some("repl:hello_ack"))
  })
}

async test "repl websocket reuses one connection for multiple commands" {
  with_repl_server(async fn(_runtime, port) {
    let ws = repl_connect(port)
    defer ws.close()

    let first = send_repl_ws_request(ws, 1, "list_projects", "")
    assert_eq(json_bool(first, "ok"), Some(true))
    assert_true(json_string(first, "result").unwrap_or("").contains("projects: 0"))

    let second = send_repl_ws_request(
      ws,
      2,
      "add_project",
      "{\"id\":\"repl-demo\",\"name\":\"Repl Demo\",\"path\":\"demo/repl\"}",
    )
    assert_eq(json_bool(second, "ok"), Some(true))
    assert_true(json_string(second, "result").unwrap_or("").contains("added project repl-demo"))

    let third = send_repl_ws_request(ws, 3, "list_projects", "")
    assert_eq(json_bool(third, "ok"), Some(true))
    assert_true(json_string(third, "result").unwrap_or("").contains("repl-demo"))
  })
}

async test "repl websocket rejects second live client" {
  with_repl_server(async fn(_runtime, port) {
    let first = repl_connect(port)
    defer first.close()

    let second = @websocket.connect("ws://127.0.0.1:\{port}\{repl_path}")
    defer second.close()
    second.send_text(Json::object({ "type": "repl:hello" }).stringify())
    let hello = second.recv().read_all().json()
    assert_eq(json_string(hello, "type"), Some("repl:rejected"))
    assert_eq(json_string(hello, "reason"), Some("repl_busy"))
  })
}

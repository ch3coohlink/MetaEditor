async fn with_repl_server(f: async (Runtime, Int) -> Unit raise) -> Unit raise {
  @src.reset_ui()
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
  @websocket.connect("ws://127.0.0.1:\{port}\{repl_path}")
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

async test "native: repl websocket accepts requests without handshake" {
  with_repl_server(async fn(_runtime, port) {
    let ws = repl_connect(port)
    defer ws.close()
    let response = send_repl_ws_request(ws, 1, "status", "")
    assert_eq(json_bool(response, "ok"), Some(true))
  })
}

async test "native: repl websocket reuses one connection for multiple commands" {
  with_repl_server(async fn(_runtime, port) {
    let ws = repl_connect(port)
    defer ws.close()

    let first = send_repl_ws_request(ws, 1, "status", "")
    assert_eq(json_bool(first, "ok"), Some(true))

    let second = send_repl_ws_request(
      ws,
      2,
      "help",
      "",
    )
    assert_eq(json_bool(second, "ok"), Some(true))
    assert_true(json_string(second, "result").unwrap_or("").contains("Commands:"))

    let third = send_repl_ws_request(ws, 3, "status", "")
    assert_eq(json_bool(third, "ok"), Some(true))
  })
}

async test "native: repl websocket accepts multiple live clients" {
  with_repl_server(async fn(_runtime, port) {
    let first = repl_connect(port)
    defer first.close()
    let second = @websocket.connect("ws://127.0.0.1:\{port}\{repl_path}")
    defer second.close()
    let first_response = send_repl_ws_request(first, 1, "status", "")
    let second_response = send_repl_ws_request(second, 2, "status", "")
    assert_eq(json_bool(first_response, "ok"), Some(true))
    assert_eq(json_bool(second_response, "ok"), Some(true))
  })
}

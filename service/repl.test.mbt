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

async fn browser_connect(port: Int) -> @websocket.Conn {
  @websocket.connect("ws://127.0.0.1:\{port}/")
}

async fn browser_hello(ws: @websocket.Conn, session_id: String) -> Unit {
  let msg : BridgeHelloClientMsg = { role: "browser", user_agent: "test", session_id }
  ws.send_text(msg.to_json().stringify())
}

async fn send_repl_ws_request(ws: @websocket.Conn, request_id: Int, cmd: String, arg: String) -> Json {
  let msg : ReplRequestOutMsg = { request_id, cmd, arg }
  ws.send_text(msg.to_json().stringify())
  recv_ws_json(ws, "repl response: \{cmd} \{arg}".trim().to_string())
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

async test "native: repl websocket exposes instance help and exec" {
  with_repl_server(async fn(_runtime, port) {
    let ws = repl_connect(port)
    defer ws.close()

    let help = send_repl_ws_request(ws, 1, "help", "host-1")
    assert_eq(json_bool(help, "ok"), Some(true))
    assert_true(json_string(help, "result").unwrap_or("").contains("spawn <entry_id:string>"))

    let exec = send_repl_ws_request(ws, 2, "exec", "host-1 spawn demo")
    assert_eq(json_bool(exec, "ok"), Some(true))
    assert_true(json_string(exec, "result").unwrap_or("").contains("spawned demo-1"))
  })
}

async test "native: repl websocket exposes instance help as json" {
  with_repl_server(async fn(_runtime, port) {
    let ws = repl_connect(port)
    defer ws.close()

    let help = send_repl_ws_request(ws, 1, "help", "host-1 --json")
    assert_eq(json_bool(help, "ok"), Some(true))
    let payload = json_field(help, "result").unwrap_or(null)
    match payload {
      Array(items) => {
        let mut found = false
        for item in items {
          if json_string(item, "id") == Some("spawn") {
            found = true
            assert_eq(json_string(item, "desc"), Some("Spawn one child entry under current host."))
          }
        }
        assert_eq(found, true)
      }
      _ => fail("expected action json array")
    }
  })
}

async test "native: browser query request resolves query string in src before asking browser" {
  with_repl_server(async fn(runtime, port) {
    let browser = browser_connect(port)
    defer browser.close()
    browser_hello(browser, "session-1")
    let mut hello = null
    while json_string(hello, "type") != Some("bridge:hello_ack") {
      hello = recv_ws_json(browser, "browser hello_ack")
    }
    @src.runtime_render(editor_runtime(runtime))
      let result_queue : @aqueue.Queue[Json] = @aqueue.Queue::new(kind=Unbounded)
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => {
          let result = request_browser_path(
            runtime,
            "host-1/entries/0/entry",
            ui_path_query("text"),
          ) catch {
            err => fail("\{err}")
          }
          let _ = result_queue.try_put(result) catch { _ => false }
        })
      let mut request = null
      while json_string(request, "type") != Some("bridge:request") {
        request = recv_ws_json(browser, "bridge request: query text")
      }
      assert_eq(json_string(request, "action"), Some("query"))
      assert_eq(request.stringify().contains("host-1/entries/0/entry"), false)
      assert_eq(json_string(request, "kind"), Some("text"))
      let id = json_int(request, "id").unwrap_or(0)
      assert_true(id > 0)
      let response : BridgeResultMsg = {
        type_: "bridge:response",
        request_id: json_int(request, "request_id").unwrap_or(0),
        ok: true,
        result: @src.UiQueryResult::Text(id, "Demo Todo").to_json(),
        error: "",
      }
      browser.send_text(response.to_json().stringify())
      let result = wait_timeout(
        "service query result",
        () => result_queue.try_get() catch { _ => None },
      )
      assert_eq(json_string(result, "text"), Some("Demo Todo"))
    })
  })
}

async test "native: browser trigger request resolves query string in src before asking browser" {
  with_repl_server(async fn(runtime, port) {
    let browser = browser_connect(port)
    defer browser.close()
    browser_hello(browser, "session-1")
    let mut hello = null
    while json_string(hello, "type") != Some("bridge:hello_ack") {
      hello = recv_ws_json(browser, "browser hello_ack")
    }
    @src.runtime_render(editor_runtime(runtime))
      let result_queue : @aqueue.Queue[Json] = @aqueue.Queue::new(kind=Unbounded)
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => {
          let result = request_browser_path(
            runtime,
            "host-1/entries/0/entry",
            ui_path_trigger_click("dblclick"),
          ) catch {
            err => fail("\{err}")
          }
          let _ = result_queue.try_put(result) catch { _ => false }
        })
      let mut request = null
      while json_string(request, "type") != Some("bridge:request") {
        request = recv_ws_json(browser, "bridge request: trigger dblclick")
      }
      assert_eq(json_string(request, "action"), Some("trigger"))
      assert_eq(request.stringify().contains("host-1/entries/0/entry"), false)
      assert_eq(json_string(request, "kind"), Some("dblclick"))
      let id = json_int(request, "id").unwrap_or(0)
      assert_true(id > 0)
      let event_msg : BridgeEventOutMsg = { id, event: "ondblclick", data: None }
      browser.send_text(event_msg.to_json().stringify())
      let response : BridgeResultMsg = {
        type_: "bridge:response",
        request_id: json_int(request, "request_id").unwrap_or(0),
        ok: true,
        result: @src.UiTriggerResult::Pointer(id, "dblclick").to_json(),
        error: "",
      }
      browser.send_text(response.to_json().stringify())
      ignore(wait_timeout(
        "service trigger result",
        () => result_queue.try_get() catch { _ => None },
      ))
    })
    assert_eq(@src.runtime_query(editor_runtime(runtime), "demo-1").entry, "demo")
  })
}

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

async fn recv_ws_json_type(ws: @websocket.Conn, label: String, type_: String) -> Json {
  let mut msg = null
  while json_string(msg, "type") != Some(type_) {
    msg = recv_ws_json(ws, label)
  }
  msg
}

fn[T: @json.FromJson] expect_json(json: Json, message: String) -> T raise {
  try {
    @json.from_json(json)
  } catch {
    _ => fail(message)
  }
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
    ignore(recv_ws_json_type(browser, "browser hello_ack", "bridge:hello_ack"))
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
      let request = recv_ws_json_type(browser, "bridge request: query text", "bridge:request")
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
    ignore(recv_ws_json_type(browser, "browser hello_ack", "bridge:hello_ack"))
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
      let request = recv_ws_json_type(browser, "bridge request: trigger dblclick", "bridge:request")
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

async test "native: control query uses browser responses for attr style and prop while connected" {
  with_repl_server(async fn(_runtime, port) {
    let browser = browser_connect(port)
    defer browser.close()
    browser_hello(browser, "session-1")
    ignore(recv_ws_json_type(browser, "browser hello_ack", "bridge:hello_ack"))
    @async.with_task_group(group => {
      let result_queue : @aqueue.Queue[(@src.UiQueryResult, @src.UiQueryResult, @src.UiQueryResult)] =
        @aqueue.Queue::new(kind=Unbounded)
      group.spawn_bg(no_wait=true, () => {
        let attr_json = call_at(port, "query", "host-1/entries/0/entry attr ui-id --json") catch {
          err => fail("\{err}")
        }
        let style_json = call_at(
          port,
          "query",
          "host-1/entries/0/entry style background-color --json",
        ) catch {
          err => fail("\{err}")
        }
        let prop_json = call_at(
          port,
          "query",
          "host-1/entries/0/name prop textContent --json",
        ) catch {
          err => fail("\{err}")
        }
        let attr : @src.UiQueryResult = expect_json(attr_json, "invalid attr query result")
        let style : @src.UiQueryResult = expect_json(style_json, "invalid style query result")
        let prop : @src.UiQueryResult = expect_json(prop_json, "invalid prop query result")
        let _ = result_queue.try_put((attr, style, prop)) catch { _ => false }
      })
      let attr_request = recv_ws_json_type(browser, "bridge request: control attr", "bridge:request")
      assert_eq(json_string(attr_request, "action"), Some("query"))
      assert_eq(json_string(attr_request, "kind"), Some("attr"))
      assert_eq(json_string(attr_request, "value"), Some("ui-id"))
      let attr_id = json_int(attr_request, "id").unwrap_or(0)
      assert_true(attr_id > 0)
      let attr_response : BridgeResultMsg = {
        type_: "bridge:response",
        request_id: json_int(attr_request, "request_id").unwrap_or(0),
        ok: true,
        result: @src.UiQueryResult::Attr(attr_id, "ui-id", "browser-entry").to_json(),
        error: "",
      }
      browser.send_text(attr_response.to_json().stringify())

      let style_request = recv_ws_json_type(browser, "bridge request: control style", "bridge:request")
      assert_eq(json_string(style_request, "action"), Some("query"))
      assert_eq(json_string(style_request, "kind"), Some("style"))
      assert_eq(json_string(style_request, "value"), Some("background-color"))
      let style_id = json_int(style_request, "id").unwrap_or(0)
      assert_true(style_id > 0)
      let style_response : BridgeResultMsg = {
        type_: "bridge:response",
        request_id: json_int(style_request, "request_id").unwrap_or(0),
        ok: true,
        result: @src.UiQueryResult::Style(style_id, "background-color", "rgb(9, 8, 7)").to_json(),
        error: "",
      }
      browser.send_text(style_response.to_json().stringify())

      let prop_request = recv_ws_json_type(browser, "bridge request: control prop", "bridge:request")
      assert_eq(json_string(prop_request, "action"), Some("query"))
      assert_eq(json_string(prop_request, "kind"), Some("prop"))
      assert_eq(json_string(prop_request, "value"), Some("textContent"))
      let prop_id = json_int(prop_request, "id").unwrap_or(0)
      assert_true(prop_id > 0)
      let prop_response : BridgeResultMsg = {
        type_: "bridge:response",
        request_id: json_int(prop_request, "request_id").unwrap_or(0),
        ok: true,
        result: @src.UiQueryResult::Prop(prop_id, "textContent", "browser-prop").to_json(),
        error: "",
      }
      browser.send_text(prop_response.to_json().stringify())
      let result = wait_timeout(
        "control query browser result",
        () => result_queue.try_get() catch { _ => None },
      )
      let (attr, style, prop) = result
      match attr {
        Attr(_, "ui-id", "browser-entry") => ()
        _ => fail("expected browser attr result")
      }
      match style {
        Style(_, "background-color", "rgb(9, 8, 7)") => ()
        _ => fail("expected browser style result")
      }
      match prop {
        Prop(_, "textContent", "browser-prop") => ()
        _ => fail("expected browser prop result")
      }
    })
  })
}

async test "native: control query falls back to headless path before browser hello" {
  with_repl_server(async fn(_runtime, port) {
    let attr_json = call_at(port, "query", "host-1/entries/0/entry attr ui-id --json") catch {
      err => fail("\{err}")
    }
    let style_json = call_at(
      port,
      "query",
      "host-1/entries/0/entry style background --json",
    ) catch {
      err => fail("\{err}")
    }
    let attr : @src.UiQueryResult = expect_json(attr_json, "invalid headless attr query result")
    let style : @src.UiQueryResult = expect_json(style_json, "invalid headless style query result")
    match attr {
      Attr(_, "ui-id", "entry") => ()
      _ => fail("expected headless attr result")
    }
    match style {
      Style(_, "background", value) => assert_true(value != "")
      _ => fail("expected headless style result")
    }
  })
}

async fn with_host_flow_server(f: async (Runtime, Int) -> Unit raise) -> Unit raise {
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

async fn host_flow_browser_connect(port: Int, session_id: String) -> @websocket.Conn {
  let ws = @websocket.connect("ws://127.0.0.1:\{port}/")
  ws.send_text(Json::object({
    "type": "bridge:hello",
    "role": "browser",
    "session_id": Json::string(session_id),
    "user_agent": Json::string("host-flow-test"),
  }).stringify())
  let hello = ws.recv().read_all().json()
  assert_eq(json_string(hello, "type"), Some("bridge:hello_ack"))
  ws
}

async fn host_flow_repl_connect(port: Int) -> @websocket.Conn {
  let ws = @websocket.connect("ws://127.0.0.1:\{port}\{repl_path}")
  ws.send_text(Json::object({ "type": "repl:hello" }).stringify())
  let hello = ws.recv().read_all().json()
  assert_eq(json_string(hello, "type"), Some("repl:hello_ack"))
  ws
}

async fn host_flow_repl_request(
  ws: @websocket.Conn,
  request_id: Int,
  cmd: String,
  arg: String,
) -> Json {
  ws.send_text(Json::object({
    "type": "repl:request",
    "request_id": request_id.to_json(),
    "cmd": Json::string(cmd),
    "arg": Json::string(arg),
  }).stringify())
  ws.recv().read_all().json()
}

fn expect_flow_batch(json: Json) -> String raise {
  match json {
    Array(_) => json.stringify()
    _ => fail("expected batch")
  }
}

fn expect_flow_request(json: Json, action: String) -> Int raise {
  assert_eq(json_string(json, "type"), Some("bridge:request"))
  assert_eq(json_string(json, "action"), Some(action))
  json_int(json, "request_id").unwrap_or(0)
}

async fn send_flow_browser_ok(ws: @websocket.Conn, request_id: Int, result: Json) -> Unit {
  ws.send_text(Json::object({
    "type": "bridge:response",
    "request_id": request_id.to_json(),
    "ok": true,
    "result": result,
    "error": Json::null(),
  }).stringify())
}

async test "host flow packs browser batch repl query and exec in one process" {
  @stdio.stdout.write("[host-flow] begin\n")
  with_host_flow_server(async fn(_runtime, port) {
    let browser = host_flow_browser_connect(port, "host-flow")
    defer browser.close()
    let repl = host_flow_repl_connect(port)
    defer repl.close()

    @stdio.stdout.write("[host-flow] initial batch\n")
    let initial = expect_flow_batch(browser.recv().read_all().json())
    assert_true(initial.contains("MetaEditor Host"))
    assert_true(initial.contains("Projects"))
    assert_true(initial.contains("Instances"))

    @stdio.stdout.write("[host-flow] add project\n")
    let add_q : @aqueue.Queue[Json] = @aqueue.Queue::new(kind=Unbounded)
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        let response = host_flow_repl_request(
          repl,
          1,
          "add_project",
          "{\"id\":\"host-demo\",\"name\":\"Host Demo\",\"path\":\"demo/host\"}",
        )
        ignore(add_q.try_put(response) catch { _ => false })
      })
      let batch = expect_flow_batch(browser.recv().read_all().json())
      assert_true(batch.contains("project-row-host-demo"))
      assert_true(batch.contains("Host Demo"))
      let sync = browser.recv().read_all().json()
      let sync_id = expect_flow_request(sync, "sync")
      send_flow_browser_ok(browser, sync_id, Json::object({ "ok": true }))
      let add_response = add_q.get()
      assert_eq(json_bool(add_response, "ok"), Some(true))
      assert_true(
        json_string(add_response, "result").unwrap_or("").contains("added project host-demo")
      )
    })

    @stdio.stdout.write("[host-flow] query ui\n")
    let query_q : @aqueue.Queue[Json] = @aqueue.Queue::new(kind=Unbounded)
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        let response = host_flow_repl_request(
          repl,
          2,
          "test_query",
          Json::object({ "kind": Json::string("ui") }).stringify(),
        )
        ignore(query_q.try_put(response) catch { _ => false })
      })
      let request = browser.recv().read_all().json()
      let request_id = expect_flow_request(request, "query")
      send_flow_browser_ok(
        browser,
        request_id,
        Json::object({ "viewport": Json::object({ "width": 100, "height": 50 }) }),
      )
      let query_response = query_q.get()
      assert_eq(json_bool(query_response, "ok"), Some(true))
      let text = json_string(query_response, "result").unwrap_or("")
      assert_true(text.contains("\"width\":100"))
      assert_true(text.contains("\"height\":50"))
    })

    @stdio.stdout.write("[host-flow] exec click\n")
    let exec_q : @aqueue.Queue[Json] = @aqueue.Queue::new(kind=Unbounded)
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        let response = host_flow_repl_request(
          repl,
          3,
          "test_exec",
          Json::object({
            "kind": Json::string("click"),
            "selector": Json::string("[data-testid='project-run-host-ui']"),
          }).stringify(),
        )
        ignore(exec_q.try_put(response) catch { _ => false })
      })
      let request = browser.recv().read_all().json()
      let request_id = expect_flow_request(request, "exec")
      send_flow_browser_ok(browser, request_id, Json::object({ "kind": Json::string("click") }))
      let sync = browser.recv().read_all().json()
      let sync_id = expect_flow_request(sync, "sync")
      send_flow_browser_ok(browser, sync_id, Json::object({ "ok": true }))
      let exec_response = exec_q.get()
      assert_eq(json_bool(exec_response, "ok"), Some(true))
      assert_true(json_string(exec_response, "result").unwrap_or("").contains("\"kind\":\"click\""))
    })
  })
  @stdio.stdout.write("[host-flow] done\n")
}

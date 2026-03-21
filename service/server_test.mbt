test "hello rejects non browser role" {
  let state = new_state()
  assert_eq(accept_hello(state, "cli", "abc", "ua"), Rejected(UnsupportedRole))
}

test "hello rejects missing session id" {
  let state = new_state()
  assert_eq(accept_hello(state, "browser", "", "ua"), Rejected(MissingSessionId))
}

test "hello accepts first connect and same session reconnect" {
  let state = new_state()
  assert_eq(accept_hello(state, "browser", "abc", "ua"), Ack(false))
  let first = session_state(state)
  assert_eq(first.connected, true)
  assert_eq(first.locked, true)
  assert_eq(first.session_id, "abc")
  assert_eq(first.disconnected_at, -1L)
  disconnect_browser(state, 10L)
  let second = session_state(state)
  assert_eq(second.connected, false)
  assert_eq(second.locked, true)
  assert_eq(second.session_id, "abc")
  assert_eq(second.disconnected_at, 10L)
  assert_eq(accept_hello(state, "browser", "abc", "ua"), Ack(true))
}

test "hello rejects second live browser and other session after disconnect" {
  let state = new_state()
  assert_eq(accept_hello(state, "browser", "abc", "ua"), Ack(false))
  assert_eq(accept_hello(state, "browser", "abc", "ua"), Rejected(SessionBusy))
  disconnect_browser(state, 10L)
  assert_eq(accept_hello(state, "browser", "def", "ua"), Rejected(SessionBusy))
}

test "browser init messages send ack before history" {
  let history : Array[Json] = [Json::object({ "kind": Json::string("ui") })]
  let messages = browser_init_messages(history, "abc", false)
  assert_eq(messages.length(), 2)
  let ack = messages[0]
  assert_eq(ack, Json::object({
    "type": Json::string("bridge:hello_ack"),
    "session_id": Json::string("abc"),
    "reconnected": Json::boolean(false),
  }))
  assert_eq(messages[1], Json::array(history))
}

test "start opens browser only when no page is connected" {
  assert_true(should_open_browser(Json::object({ "browsers": Json::number(0) })))
  assert_true(!should_open_browser(Json::object({ "browsers": Json::number(1) })))
}

async test "bind http server retries next port" {
  let addr = @socket.Addr::parse("127.0.0.1:19180")
  let occupied = @socket.TcpServer::new(addr)
  defer occupied.close()
  let server = bind_http_server(addr, 3)
  defer server.close()
  assert_eq(server.addr().port(), 19181)
}

#cfg(platform="windows")
fn service_bin() -> String {
  "_build/native/debug/build/service/service.exe"
}

#cfg(not(platform="windows"))
fn service_bin() -> String {
  "_build/native/debug/build/service/service"
}

fn has_json_flag(output : String, key : String, value : String) -> Bool {
  output.contains("\"\{key}\":\{value}")
}

fn has_json_string(output : String, key : String, value : String) -> Bool {
  output.contains("\"\{key}\":\"\{value}\"")
}

async fn run_meta(args : Array[String]) -> (Int, String) {
  let out_file = "_build/test-service-cli.out"
  let err_file = "_build/test-service-cli.err"
  let code = @process.run(
    service_bin(),
    args,
    cwd=".",
    stdout=@process.redirect_to_file(out_file, create=0o644, truncate=true),
    stderr=@process.redirect_to_file(err_file, create=0o644, truncate=true),
  )
  let stdout = if @fs.exists(out_file) { @fs.read_file(out_file).text() } else { "" }
  let stderr = if @fs.exists(err_file) { @fs.read_file(err_file).text() } else { "" }
  (code, stdout + stderr)
}

async fn start_meta(args : Array[String]) -> (Int, String) {
  let out_file = "_build/test-service-start.out"
  let err_file = "_build/test-service-start.err"
  @async.with_task_group(group => {
    let proc = @process.spawn(
      group,
      service_bin(),
      args,
      cwd=".",
      stdout=@process.redirect_to_file(out_file, create=0o644, truncate=true),
      stderr=@process.redirect_to_file(err_file, create=0o644, truncate=true),
    )
    let mut tries = 0
    while tries < 25 {
      match proc.try_wait() {
        Some(code) => {
          let stdout = if @fs.exists(out_file) { @fs.read_file(out_file).text() } else { "" }
          let stderr = if @fs.exists(err_file) { @fs.read_file(err_file).text() } else { "" }
          return (code, stdout + stderr)
        }
        None => {
          @async.sleep(20)
          tries += 1
        }
      }
    }
    proc.cancel()
    fail("meta start did not exit quickly")
  })
}

async fn wait_status_output() -> (Int, String) {
  let mut tries = 0
  let mut last = (1, "")
  while tries < 25 {
    let result : Result[(Int, String), _] = try? run_meta(["status"])
    match result {
      Ok((code, output)) => {
        last = (code, output)
        if code == 0 && !output.contains("\"ok\"") && output.contains("\"clients\"") {
          return (code, output)
        } else {
          @async.sleep(20)
        }
      }
      Err(_) => @async.sleep(20)
    }
    tries += 1
  }
  last
}

async test "service lifecycle is idempotent" {
  let _ = run_meta(["stop"])
  let (idle_stop_code, idle_stop_output) = run_meta(["stop"])
  assert_eq(idle_stop_code, 0)
  assert_true(has_json_flag(idle_stop_output, "ok", "true"))
  assert_true(has_json_flag(idle_stop_output, "stopped", "false"))
  assert_true(has_json_flag(idle_stop_output, "not_running", "true"))

  let (start_code, start_output) = start_meta(["start", "18120"])
  assert_eq(start_code, 0)
  assert_true(has_json_flag(start_output, "ok", "true"))
  assert_true(has_json_flag(start_output, "started", "true"))
  assert_true(has_json_flag(start_output, "already_running", "false"))
  assert_true(has_json_string(start_output, "url", "http://localhost:18120"))
  let (status_code, status_output) = wait_status_output()
  assert_eq(status_code, 0)
  assert_true(status_output.contains("\"clients\""))

  let (repeat_start_code, repeat_start_output) = start_meta(["start"])
  assert_eq(repeat_start_code, 0)
  assert_true(has_json_flag(repeat_start_output, "ok", "true"))
  assert_true(has_json_flag(repeat_start_output, "started", "false"))
  assert_true(has_json_flag(repeat_start_output, "already_running", "true"))
  assert_true(has_json_string(repeat_start_output, "url", "http://localhost:18120"))

  let (stop_code, stop_output) = run_meta(["stop"])
  assert_eq(stop_code, 0)
  assert_true(has_json_string(stop_output, "kind", "stop"))

  let (final_stop_code, final_stop_output) = run_meta(["stop"])
  assert_eq(final_stop_code, 0)
  assert_true(has_json_flag(final_stop_output, "ok", "true"))
  assert_true(has_json_flag(final_stop_output, "stopped", "false"))
  assert_true(has_json_flag(final_stop_output, "not_running", "true"))
}

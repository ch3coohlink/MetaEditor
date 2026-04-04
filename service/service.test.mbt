test "native: hello rejects non browser role" {
  let state = new_state()
  assert_eq(accept_hello(state, "cli", "abc", "ua"), Rejected(UnsupportedRole))
}

test "native: hello rejects missing session id" {
  let state = new_state()
  assert_eq(accept_hello(state, "browser", "", "ua"), Rejected(MissingSessionId))
}

test "native: hello accepts first connect and same session reconnect" {
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

test "native: hello rejects second live browser and other session after disconnect" {
  let state = new_state()
  assert_eq(accept_hello(state, "browser", "abc", "ua"), Ack(false))
  assert_eq(accept_hello(state, "browser", "abc", "ua"), Rejected(SessionBusy))
  disconnect_browser(state, 10L)
  assert_eq(accept_hello(state, "browser", "def", "ua"), Rejected(SessionBusy))
}

test "native: invalid service pid text is rejected" {
  let parsed: Result[Int, _] = try? parse_service_pid_text("broken")
  match parsed {
    Ok(_) => fail("expected invalid pid text to fail")
    Err(_) => ()
  }
}

test "native: invalid service state text is rejected" {
  let parsed: Result[Int, _] = try? parse_service_port_text("broken")
  match parsed {
    Ok(_) => fail("expected invalid state text to fail")
    Err(_) => ()
  }
}

async test "native: service lock is exclusive" {
  clear_test_service_state()
  let first = acquire_service_lock()
  match (try? try_acquire_service_lock() : Result[ServiceLock?, _]) {
    Ok(None) => ()
    Ok(Some(lock)) => {
      release_service_lock(lock)
      fail("expected service lock to be exclusive")
    }
    Err(_) => ()
  }
  release_service_lock(first)
  match (try? try_acquire_service_lock() : Result[ServiceLock?, _]) {
    Ok(Some(lock)) => release_service_lock(lock)
    _ => fail("expected service lock to be acquirable after release")
  }
  clear_test_service_state()
}

async test "native: bind http server retries next port" {
  let addr = @socket.Addr::parse("127.0.0.1:19180")
  let occupied = @socket.TcpServer::new(addr)
  defer occupied.close()
  let server = bind_http_server(addr, 3)
  defer server.close()
  assert_eq(server.addr().port(), 19181)
}

fn log_lifecycle_output(label: String, output: String) -> Unit {
  if !debug_timing_enabled() { return }
  println("[lifecycle-output] \{label}:")
  println(output)
}

async test "native: roots stay quiet before browser hello" {
  @src.reset_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  ignore(run(runtime, "roots", "host"))
  match runtime.live_batches.try_get() {
    Some(_) => fail("expected no render batch before browser hello")
    None => ()
  }
}

async test "native: browser hello_ack and render share one browser queue" {
  @src.reset_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  assert_eq(accept_hello(runtime.state, "browser", "session-1", "ua"), Ack(false))
  respond_hello_ack(runtime, "session-1", false)
  ignore(run(runtime, "roots", "host"))
  let first = runtime.live_batches.get()
  let second = runtime.live_batches.get()
  assert_eq(first, {
    "type": "bridge:hello_ack",
    "session_id": "session-1",
    "reconnected": false,
  })
  assert_true(second.stringify().contains("MetaEditor"))
}

async test "native: render batch and pong share one browser queue" {
  @src.reset_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  assert_eq(accept_hello(runtime.state, "browser", "session-1", "ua"), Ack(false))
  ignore(run(runtime, "roots", "host"))
  respond_pong(runtime, { "seq": 7 })
  let first = runtime.live_batches.get()
  let second = runtime.live_batches.get()
  assert_true(first.stringify().contains("MetaEditor"))
  assert_eq(second, { "type": "bridge:pong", "seq": 7 })
}

async test "native: init app waits for browser hello before render" {
  @src.reset_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  match runtime.live_batches.try_get() {
    Some(batch) => {
      let _ = batch
      fail("expected no render batch before browser hello")
    }
    None => ()
  }
}

async test "native: disconnected render does not keep stale browser batch" {
  @src.reset_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  assert_eq(accept_hello(runtime.state, "browser", "session-1", "ua"), Ack(false))
  ignore(run(runtime, "roots", "host"))
  let _ = runtime.live_batches.get()
  disconnect_browser(runtime.state, 10L)
  ignore(run(runtime, "roots", "demo"))
  match runtime.live_batches.try_get() {
    Some(_) => fail("expected no stale batch while browser is disconnected")
    None => ()
  }
}

async test "native: reconnect renders latest root snapshot" {
  @src.reset_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  assert_eq(accept_hello(runtime.state, "browser", "session-1", "ua"), Ack(false))
  ignore(run(runtime, "roots", "host"))
  let _ = runtime.live_batches.get()
  disconnect_browser(runtime.state, 10L)
  ignore(run(runtime, "roots", "demo"))
  assert_eq(accept_hello(runtime.state, "browser", "session-1", "ua"), Ack(true))
  respond_hello_ack(runtime, "session-1", true)
  render_app(runtime)
  let first = runtime.live_batches.get()
  let second = runtime.live_batches.get()
  assert_eq(first, {
    "type": "bridge:hello_ack",
    "session_id": "session-1",
    "reconnected": true,
  })
  let text = second.stringify()
  assert_true(text.contains("demo-editor"))
  assert_true(!text.contains("desktop-root"))
}

#cfg(platform="windows")
fn service_bin() -> String {
  "_build/native/debug/build/service/service.exe"
}

#cfg(not(platform="windows"))
fn service_bin() -> String {
  "_build/native/debug/build/service/service"
}

fn test_state_dir() -> String {
  "\{temp_dir()}/metaeditor-service-test"
}

async fn prepare_test_state_dir() -> String {
  let dir = test_state_dir()
  set_state_dir(dir)
  dir
}

async fn clear_test_service_state() -> Unit {
  let _ = prepare_test_state_dir()
  let state = service_state_path()
  if @fs.exists(state) {
    @fs.remove(state)
  }
}

async fn write_test_service_state(pid: String, state: String) -> Unit {
  let _ = prepare_test_state_dir()
  @fs.write_file(
    service_state_path(),
    @utf8.encode("{\"pid\":\{pid},\"port\":\{state}}"),
    create=0o644,
    truncate=true,
  )
}

async fn read_temp_meta_output(stdout_file: String, stderr_file: String) -> String {
  let stdout = if @fs.exists(stdout_file) { @fs.read_file(stdout_file).text() } else { "" }
  let stderr = if @fs.exists(stderr_file) { @fs.read_file(stderr_file).text() } else { "" }
  if @fs.exists(stdout_file) {
    @fs.remove(stdout_file) catch { _ => () }
  }
  if @fs.exists(stderr_file) {
    @fs.remove(stderr_file) catch { _ => () }
  }
  stdout + stderr
}

async fn run_meta_with_timeout(args: Array[String], timeout_ms: Int) -> (Int, String) {
  let state_dir = prepare_test_state_dir()
  let out_file = "\{temp_dir()}/metaeditor-test-cli.out"
  let err_file = "\{temp_dir()}/metaeditor-test-cli.err"
  @async.with_task_group(group => {
    let proc = @process.spawn(
      group,
      service_bin(),
      ["--state-dir", state_dir, ..args],
      cwd=".",
      stdout=@process.redirect_to_file(out_file, create=0o644, truncate=true),
      stderr=@process.redirect_to_file(err_file, create=0o644, truncate=true),
    )
    let mut tries = 0
    let max_tries = (timeout_ms + 19) / 20
    while tries < max_tries {
      match proc.try_wait() {
        Some(code) => return (code, read_temp_meta_output(out_file, err_file))
        None => {
          @async.sleep(20)
          tries += 1
        }
      }
    }
    proc.cancel()
    let _ = read_temp_meta_output(out_file, err_file)
    let command = args.iter().join(" ")
    fail("meta command timed out: \{command}")
  })
}

async fn run_meta(args: Array[String]) -> (Int, String) {
  run_meta_with_timeout(args, 3000)
}

async fn timed_meta(
  label: String,
  args: Array[String],
  timeout_ms: Int,
) -> (Int, String, Int64) {
  let started = @async.now()
  let (code, output) = run_meta_with_timeout(args, timeout_ms)
  let elapsed = @async.now() - started
  ignore(label)
  (code, output, elapsed)
}

async fn assert_page_ready(port: Int) -> Unit {
  let client = @http.Client::new("http://127.0.0.1:\{port}")
  defer client.close()
  let response = client.get("/")
  let body = client.read_all().text()
  assert_eq(response.code, 200)
  assert_true(body.contains("<div id=\"app-info\">Status: Initializing Bridge...</div>"))
  assert_true(body.contains("<script src=\"src/bridge.js\"></script>"))
}

async test "native: service lifecycle is idempotent" {
  let lifecycle_started = @async.now()
  let _ = run_meta(["stop"])
  clear_test_service_state()
  let (idle_stop_code, idle_stop_output, _) = timed_meta("idle stop", ["stop"], 3000)
  assert_eq(idle_stop_code, 0)
  assert_true(idle_stop_output.contains("service is not running"))
  log_timing("lifecycle", "idle stop", @async.now() - lifecycle_started)

  write_test_service_state("999999", "{\"port\":19199}")
  let start_started = @async.now()
  let (start_code, start_output, _) = timed_meta(
    "start --silent",
    ["start", "18120", "--silent"],
    1500,
  )
  assert_eq(start_code, 0)
  log_lifecycle_output("start", start_output)
  assert_true(start_output.contains("started http://localhost:18120"))
  log_timing("lifecycle", "start command", @async.now() - start_started)
  let start_port_started = @async.now()
  let port = read_service_port() catch { _ => fail("expected service port after start") }
  log_timing("lifecycle", "start port", @async.now() - start_port_started)
  let start_ready_started = @async.now()
  assert_page_ready(port)
  log_timing("lifecycle", "start ready", @async.now() - start_ready_started)

  let stop_started = @async.now()
  let (stop_code, stop_output, _) = timed_meta(
    "stop",
    ["stop"],
    1500,
  )
  assert_eq(stop_code, 0)
  assert_true(stop_output.contains("stopped"))
  log_timing("lifecycle", "stop command", @async.now() - stop_started)

  let start_again_started = @async.now()
  let (start_again_code, start_again_output, _) = timed_meta(
    "start again --silent",
    ["start", "18120", "--silent"],
    1500,
  )
  assert_eq(start_again_code, 0)
  log_lifecycle_output("start again", start_again_output)
  assert_true(start_again_output.contains("started http://localhost:18120"))
  log_timing("lifecycle", "start again command", @async.now() - start_again_started)
  let start_again_port_started = @async.now()
  let start_again_port = read_service_port() catch { _ => fail("expected service port after start again") }
  log_timing("lifecycle", "start again port", @async.now() - start_again_port_started)
  let start_again_ready_started = @async.now()
  assert_page_ready(start_again_port)
  log_timing("lifecycle", "start again ready", @async.now() - start_again_ready_started)

  let restart_started = @async.now()
  let (restart_code, restart_output, _) = timed_meta(
    "restart while running",
    ["restart", "18120", "--silent"],
    1500,
  )
  assert_eq(restart_code, 0)
  log_lifecycle_output("restart", restart_output)
  assert_true(restart_output.contains("restarted http://localhost:18120"))
  log_timing("lifecycle", "restart command", @async.now() - restart_started)
  let restart_port_started = @async.now()
  let restart_port = read_service_port() catch { _ => fail("expected service port after restart") }
  log_timing("lifecycle", "restart port", @async.now() - restart_port_started)
  let restart_ready_started = @async.now()
  assert_page_ready(restart_port)
  log_timing("lifecycle", "restart ready", @async.now() - restart_ready_started)

  let stop_started = @async.now()
  let (stop_code, stop_output, _) = timed_meta("stop", ["stop"], 3000)
  assert_eq(stop_code, 0)
  assert_true(stop_output.contains("stopped"))
  log_timing("lifecycle", "stop", @async.now() - stop_started)
  log_timing("lifecycle", "total", @async.now() - lifecycle_started)
  clear_test_service_state()

  // 问题：此函数内的任何assert失败，似乎都会测试脚本导致超时
}

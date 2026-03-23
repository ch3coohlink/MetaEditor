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

test "invalid service pid text is rejected" {
  let parsed: Result[Int, _] = try? parse_service_pid_text("broken")
  match parsed {
    Ok(_) => fail("expected invalid pid text to fail")
    Err(_) => ()
  }
}

test "invalid service state text is rejected" {
  let parsed: Result[Int, _] = try? parse_service_port_text("broken")
  match parsed {
    Ok(_) => fail("expected invalid state text to fail")
    Err(_) => ()
  }
}

async test "service lock is exclusive" {
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

async test "bind http server retries next port" {
  let addr = @socket.Addr::parse("127.0.0.1:19180")
  let occupied = @socket.TcpServer::new(addr)
  defer occupied.close()
  let server = bind_http_server(addr, 3)
  defer server.close()
  assert_eq(server.addr().port(), 19181)
}

async test "render app emits host page batch" {
  @src.reset_test_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  render_app(runtime)
  let batch = runtime.live_batches.get()
  let text = batch.stringify()
  assert_true(text.contains("MetaEditor Host"))
  assert_true(text.contains("Service is running. Use the host action below to stop it."))
  assert_true(text.contains("Stop Service"))
  assert_true(text.contains("host_stop_service"))
}

async test "init app waits for browser hello before render" {
  @src.reset_test_ui()
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
    @fs.remove(stdout_file)
  }
  if @fs.exists(stderr_file) {
    @fs.remove(stderr_file)
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
  @stdio.stdout.write("[timing] \{label} took \{elapsed}ms\n")
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

async test "service lifecycle is idempotent" {
  let _ = run_meta(["stop"])
  clear_test_service_state()
  let (idle_stop_code, idle_stop_output, _) = timed_meta("idle stop", ["stop"], 3000)
  assert_eq(idle_stop_code, 0)
  assert_true(idle_stop_output.contains("service is not running"))

  write_test_service_state("999999", "{\"port\":19199}")
  let (start_code, start_output, _) = timed_meta(
    "start --silent",
    ["start", "18120", "--silent"],
    1500,
  )
  assert_eq(start_code, 0)
  assert_true(start_output.contains("started http://localhost:18120"))
  let port = read_service_port() catch { _ => fail("expected service port after start") }
  assert_page_ready(port)

  let (repeat_start_code, repeat_start_output, _) = timed_meta(
    "repeat start --silent",
    ["start", "--silent"],
    1500,
  )
  assert_eq(repeat_start_code, 0)
  assert_true(repeat_start_output.contains("already running http://localhost:18120"))

  let (host_stop_code, host_stop_output, _) = timed_meta(
    "host stop service",
    ["host_stop_service"],
    1500,
  )
  assert_eq(host_stop_code, 0)
  assert_true(host_stop_output.contains("host_stop_service"))

  let (restart_code, restart_output, _) = timed_meta(
    "restart after host stop",
    ["start", "18120", "--silent"],
    1500,
  )
  assert_eq(restart_code, 0)
  assert_true(restart_output.contains("started http://localhost:18120"))
  let restart_port = read_service_port() catch { _ => fail("expected service port after restart") }
  assert_page_ready(restart_port)

  let (stop_code, stop_output, _) = timed_meta("stop running", ["stop"], 3000)
  assert_eq(stop_code, 0)
  assert_true(stop_output.contains("stopped"))

  let (final_stop_code, final_stop_output, _) = timed_meta("final stop", ["stop"], 3000)
  assert_eq(final_stop_code, 0)
  assert_true(final_stop_output.contains("service is not running"))
  clear_test_service_state()
}

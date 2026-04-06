let service_test_state_lock : @aqueue.Queue[Unit] = @aqueue.Queue::new(kind=Unbounded)

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

fn init {
  if @env.get_env_var("METAEDITOR_DEBUG_TIMING") is Some(_) {
    set_debug_timing(true)
  }
  let _ = service_test_state_lock.try_put(()) catch { _ => false }
}

fn release_service_test_state_lock() -> Unit {
  let _ = service_test_state_lock.try_put(()) catch { _ => false }
}

async fn[T] with_service_state_lock(f: async () -> T) -> T {
  ignore(service_test_state_lock.get() catch { _ => abort("service test lock closed") })
  defer {
    release_service_test_state_lock()
  }
  f()
}

async test "native: service state path and lock path are split" {
  with_service_state_lock(() => {
    let _ = prepare_test_state_dir()
    assert_eq(service_state_path() == service_lock_path(), false)
  })
}

async test "native: service lock is exclusive" {
  with_service_state_lock(() => {
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
  })
}

async test "native: service state stays readable while lock is held" {
  with_service_state_lock(() => {
    clear_test_service_state()
    let lock = acquire_service_lock()
    write_service_state(123, 18180)
    let port = read_service_port() catch { _ => fail("expected readable service state while locked") }
    assert_eq(port, 18180)
    release_service_lock(lock)
    clear_test_service_state()
  })
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
  let status = status_text(runtime)
  assert_true(status.contains("roots: host-1"))
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
  @src.runtime_render(editor_runtime(runtime))
  let first = wait_timeout("live batch: hello_ack", () => runtime.live_batches.try_get() catch { _ => None })
  let second = wait_timeout(
    "live batch: initial render",
    () => runtime.live_batches.try_get() catch { _ => None },
  )
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
  @src.runtime_render(editor_runtime(runtime))
  respond_pong(runtime, { "seq": 7 })
  let first = wait_timeout(
    "live batch: render batch",
    () => runtime.live_batches.try_get() catch { _ => None },
  )
  let second = wait_timeout(
    "live batch: bridge pong",
    () => runtime.live_batches.try_get() catch { _ => None },
  )
  assert_true(first.stringify().contains("MetaEditor"))
  assert_eq(second, { "type": "bridge:pong", "seq": 7 })
}

async test "native: browser ping latency updates host tray" {
  @src.reset_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  assert_eq(accept_hello(runtime.state, "browser", "session-1", "ua"), Ack(false))
  @src.runtime_render(editor_runtime(runtime))
  let _ = wait_timeout(
    "live batch: initial render before tray latency",
    () => runtime.live_batches.try_get() catch { _ => None },
  )
  respond_pong(runtime, { "seq": 8, "latency_ms": 3 })
  let batch = wait_timeout(
    "live batch: tray latency text update",
    () => runtime.live_batches.try_get() catch { _ => None },
  )
  assert_true(batch.stringify().contains("\"3ms\""))
  let pong = wait_timeout(
    "live batch: bridge pong after tray latency",
    () => runtime.live_batches.try_get() catch { _ => None },
  )
  assert_eq(pong, { "type": "bridge:pong", "seq": 8 })
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
  @src.runtime_render(editor_runtime(runtime))
  let _ = wait_timeout(
    "live batch: initial render before disconnect",
    () => runtime.live_batches.try_get() catch { _ => None },
  )
  disconnect_browser(runtime.state, 10L)
  ignore(@src.runtime_set_roots(editor_runtime(runtime), ["demo"]) catch { _ => panic() })
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
  @src.runtime_render(editor_runtime(runtime))
  let _ = wait_timeout(
    "live batch: initial render before reconnect",
    () => runtime.live_batches.try_get() catch { _ => None },
  )
  disconnect_browser(runtime.state, 10L)
  ignore(@src.runtime_set_roots(editor_runtime(runtime), ["demo"]) catch { _ => panic() })
  assert_eq(accept_hello(runtime.state, "browser", "session-1", "ua"), Ack(true))
  respond_hello_ack(runtime, "session-1", true)
  @src.runtime_render(editor_runtime(runtime))
  let first = wait_timeout(
    "live batch: reconnect hello_ack",
    () => runtime.live_batches.try_get() catch { _ => None },
  )
  let second = wait_timeout(
    "live batch: reconnect render",
    () => runtime.live_batches.try_get() catch { _ => None },
  )
  assert_eq(first, {
    "type": "bridge:hello_ack",
    "session_id": "session-1",
    "reconnected": true,
  })
  let text = second.stringify()
  assert_true(text.contains("demo-editor"))
}

#cfg(platform="windows")
fn service_bin() -> String {
  "_build/native/debug/build/service/service.exe"
}

#cfg(not(platform="windows"))
fn service_bin() -> String {
  "_build/native/debug/build/service/service"
}

let test_state_seq : Ref[Int] = Ref::new(1)

async fn prepare_test_state_dir() -> String {
  let seq = test_state_seq.val
  test_state_seq.val = seq + 1
  let dir = "\{temp_dir()}/metaeditor-service-test-\{current_pid()}-\{seq}"
  set_state_dir(dir)
  dir
}

async fn clear_test_service_state() -> Unit {
  let _ = prepare_test_state_dir()
  release_state_file()
  let state = service_state_path()
  let lock = service_lock_path()
  if @fs.exists(state) {
    @fs.remove(state)
  }
  if @fs.exists(lock) {
    @fs.remove(lock)
  }
}

async fn clear_test_service_state_dir(dir: String) -> Unit {
  set_state_dir(dir)
  release_state_file()
  let state = service_state_path()
  let lock = service_lock_path()
  if @fs.exists(state) {
    @fs.remove(state)
  }
  if @fs.exists(lock) {
    @fs.remove(lock)
  }
}

async fn write_test_service_state_in(dir: String, pid: String, state: String) -> Unit {
  set_state_dir(dir)
  @fs.write_file(
    service_state_path(),
    @utf8.encode("{\"pid\":\{pid},\"port\":\{state}}"),
    create=0o644,
    truncate=true,
  )
}

async fn run_meta_result_in(
  state_dir: String,
  args: Array[String],
  timeout_ms: Int,
) -> (Int, String) {
  let command = args.iter().join(" ")
  try {
    let (code, output) = @async.with_timeout(timeout_ms, () =>
      @process.collect_output_merged(
        service_bin(),
        ["--state-dir", state_dir, ..args],
        cwd=".",
      )
    )
    (code, output.text())
  } catch {
    @async.TimeoutError => fail("meta command timed out: \{command}; state_dir=\{state_dir}")
    err => raise err
  }
}

async fn run_meta_with_timeout_in(
  state_dir: String,
  args: Array[String],
  timeout_ms: Int,
) -> (Int, String) {
  run_meta_result_in(state_dir, args, timeout_ms)
}

async fn timed_lifecycle_meta_in(
  state_dir: String,
  label: String,
  args: Array[String],
  timeout_ms: Int,
) -> (Int, String, Int64) {
  let started = @async.now()
  let (code, output) = run_meta_result_in(state_dir, args, timeout_ms)
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

async fn wait_service_port_ready(label: String, timeout_ms: Int) -> Int {
  @async.with_timeout(timeout_ms, () => {
    for ;; {
      match (try? read_service_port() : Result[Int, _]) {
        Ok(port) => return port
        Err(_) => @async.sleep(20)
      }
    }
    abort("unreachable")
  }) catch {
    @async.TimeoutError => fail("timed out waiting for \{label}")
    err => raise err
  }
}

async fn wait_page_ready(label: String, port: Int, timeout_ms: Int) -> Unit {
  @async.with_timeout(timeout_ms, () => {
    for ;; {
      match (try? assert_page_ready(port) : Result[Unit, _]) {
        Ok(_) => return
        Err(_) => @async.sleep(20)
      }
    }
    abort("unreachable")
  }) catch {
    @async.TimeoutError => fail("timed out waiting for \{label}")
    err => raise err
  }
}

async fn stop_with_timeout(state_dir: String, label: String, timeout_ms: Int) -> Unit {
  let (code, _) = run_meta_result_in(state_dir, ["stop"], timeout_ms)
  if code != 0 {
    fail("service lifecycle failed at \{label}: stop exit \{code}")
  }
}

async test "native: service lifecycle is idempotent" {
  with_service_state_lock(() => @async.with_task_group(root => {
    let used_dirs : Array[String] = []
    root.add_defer(() => @async.protect_from_cancel(() => {
      for dir in used_dirs {
        let _ : Result[(Int, String), _] = try? run_meta_result_in(dir, ["stop"], 300)
        clear_test_service_state_dir(dir)
      }
    }))

    let lifecycle_started = @async.now()

    let stop_dir = prepare_test_state_dir()
    used_dirs.push(stop_dir)
    let _ = try? run_meta_with_timeout_in(stop_dir, ["stop"], 500)
    clear_test_service_state_dir(stop_dir)
    let idle_stop_dir = prepare_test_state_dir()
    used_dirs.push(idle_stop_dir)
    let (idle_stop_code, idle_stop_output, _) = timed_lifecycle_meta_in(
      idle_stop_dir,
      "idle stop",
      ["stop"],
      500,
    )
    assert_eq(idle_stop_code, 0)
    assert_true(idle_stop_output.contains("service is not running"))
    log_timing("lifecycle", "idle stop", @async.now() - lifecycle_started)

    let stale_start_dir = prepare_test_state_dir()
    used_dirs.push(stale_start_dir)
    write_test_service_state_in(stale_start_dir, "999999", "{\"port\":19199}")
    let start_dir = prepare_test_state_dir()
    used_dirs.push(start_dir)
    let start_started = @async.now()
    let (start_code, start_output, _) = timed_lifecycle_meta_in(
      start_dir,
      "start --silent",
      ["start", "18120", "--silent"],
      800,
    )
    assert_eq(start_code, 0)
    log_lifecycle_output("start", start_output)
    assert_true(start_output.contains("started http://localhost:18120"))
    log_timing("lifecycle", "start command", @async.now() - start_started)
    set_state_dir(start_dir)
    let start_port_started = @async.now()
    let port = wait_service_port_ready("service lifecycle: start port", 300)
    log_timing("lifecycle", "start port", @async.now() - start_port_started)
    let start_ready_started = @async.now()
    wait_page_ready("service lifecycle: start ready", port, 300)
    log_timing("lifecycle", "start ready", @async.now() - start_ready_started)

    let stop_started = @async.now()
    set_state_dir(start_dir)
    stop_with_timeout(start_dir, "stop after first start", 800)
    log_timing("lifecycle", "stop command", @async.now() - stop_started)

    let start_again_dir = prepare_test_state_dir()
    used_dirs.push(start_again_dir)
    let start_again_started = @async.now()
    let (start_again_code, start_again_output, _) = timed_lifecycle_meta_in(
      start_again_dir,
      "start again --silent",
      ["start", "18120", "--silent"],
      800,
    )
    assert_eq(start_again_code, 0)
    log_lifecycle_output("start again", start_again_output)
    assert_true(start_again_output.contains("started http://localhost:18120"))
    log_timing("lifecycle", "start again command", @async.now() - start_again_started)
    set_state_dir(start_again_dir)
    let start_again_port_started = @async.now()
    let start_again_port = wait_service_port_ready("service lifecycle: start again port", 300)
    log_timing("lifecycle", "start again port", @async.now() - start_again_port_started)
    let start_again_ready_started = @async.now()
    wait_page_ready("service lifecycle: start again ready", start_again_port, 300)
    log_timing("lifecycle", "start again ready", @async.now() - start_again_ready_started)

    let stale_restart_dir = prepare_test_state_dir()
    used_dirs.push(stale_restart_dir)
    let restart_dir = prepare_test_state_dir()
    used_dirs.push(restart_dir)
    let restart_started = @async.now()
    let (restart_code, restart_output, _) = timed_lifecycle_meta_in(
      restart_dir,
      "restart while running",
      ["restart", "18120", "--silent"],
      800,
    )
    assert_eq(restart_code, 0)
    log_lifecycle_output("restart", restart_output)
    log_timing("lifecycle", "restart command", @async.now() - restart_started)
    // 这里故意注释掉正确做法，继续复现“命令和后续等待不在同一个 state_dir”。
    // set_state_dir(restart_dir)
    set_state_dir(stale_restart_dir)
    let restart_port_started = @async.now()
    let restart_port = wait_service_port_ready("service lifecycle: restart port", 300)
    log_timing("lifecycle", "restart port", @async.now() - restart_port_started)
    let restart_ready_started = @async.now()
    wait_page_ready("service lifecycle: restart ready", restart_port, 300)
    log_timing("lifecycle", "restart ready", @async.now() - restart_ready_started)

    let stop_started = @async.now()
    set_state_dir(restart_dir)
    stop_with_timeout(restart_dir, "final stop", 800)
    log_timing("lifecycle", "stop", @async.now() - stop_started)
    log_timing("lifecycle", "total", @async.now() - lifecycle_started)
  })
  )
}

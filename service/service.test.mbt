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
  @async.with_task_group(root => {
    ignore(service_test_state_lock.get() catch { _ => abort("service test lock closed") })
    let _ = prepare_test_state_dir()
    root.add_defer(() => @async.protect_from_cancel(() => {
      cleanup_test_state_dir(test_state_dir())
      release_service_test_state_lock()
    }))
    f()
  })
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

async test "native: roots stay quiet before browser hello" {
  @src.reset_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  let status = status_text(runtime)
  assert_true(status.contains("roots: host-1"))
  assert_eq(@src.query_node("root/entries/0/entry") is Some(_), true)
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

async test "native: init app prepares headless query tree before browser hello" {
  @src.reset_ui()
  let runtime = make_runtime(".")
  init_app(runtime)
  let query = request_browser_path(runtime, "root", {
    "action": "query",
    "kind": "node",
  }) catch { _ => fail("expected headless query to work before browser hello") }
  assert_true(query.stringify().contains("\"id\":"))
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

fn test_state_dir() -> String {
  "\{temp_dir()}/metaeditor-service-test-\{current_pid()}"
}

async fn cleanup_test_state_dir(dir: String) -> Unit {
  release_state_file()
  if @fs.exists(dir) {
    @fs.rmdir(dir, recursive=true) catch { _ => () }
  }
}

async fn prepare_test_state_dir() -> String {
  let dir = test_state_dir()
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

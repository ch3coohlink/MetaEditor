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

test "runtime defaults to host app registry" {
  let apps = default_managed_apps()
  assert_eq(default_active_app_id(), "host")
  assert_eq(default_preview_app_id(), "")
  assert_true(apps.length() >= 1)
  assert_eq(apps[0].id, "host")
}

test "init app emits host ui history" {
  let runtime = make_runtime(".")
  init_app_for_test(runtime)
  let history = ui_history_json(runtime).stringify()
  assert_true(history.length() > 2)
  assert_true(history.contains("MetaEditor Host"))
  assert_true(history.contains("Workspace"))
  assert_true(!history.contains("id: host"))
}

test "invalid service pid text is rejected" {
  let parsed : Result[Int, _] = try? parse_service_pid_text("broken")
  match parsed {
    Ok(_) => fail("expected invalid pid text to fail")
    Err(_) => ()
  }
}

test "invalid service state text is rejected" {
  let parsed : Result[Int, _] = try? parse_service_port_text("broken")
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

async fn clear_test_service_state() -> Unit {
  let lock = service_lock_path()
  let pid = service_pid_path()
  let state = service_state_path()
  if @fs.exists(lock) {
    @fs.remove(lock)
  }
  if @fs.exists(pid) {
    @fs.remove(pid)
  }
  if @fs.exists(state) {
    @fs.remove(state)
  }
}

async fn write_test_service_state(pid : String, state : String) -> Unit {
  @fs.write_file(service_pid_path(), @utf8.encode(pid), create=0o644, truncate=true)
  @fs.write_file(service_state_path(), @utf8.encode(state), create=0o644, truncate=true)
}

async fn read_meta_output(stdout_file : String, stderr_file : String) -> String {
  let stdout = if @fs.exists(stdout_file) { @fs.read_file(stdout_file).text() } else { "" }
  let stderr = if @fs.exists(stderr_file) { @fs.read_file(stderr_file).text() } else { "" }
  stdout + stderr
}

async fn run_meta_with_timeout(args : Array[String], timeout_ms : Int) -> (Int, String) {
  let out_file = "_build/test-service-cli.out"
  let err_file = "_build/test-service-cli.err"
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
    let max_tries = (timeout_ms + 19) / 20
    while tries < max_tries {
      match proc.try_wait() {
        Some(code) => return (code, read_meta_output(out_file, err_file))
        None => {
          @async.sleep(20)
          tries += 1
        }
      }
    }
    proc.cancel()
    let command = args.iter().join(" ")
    fail("meta command timed out: \{command}")
  })
}

async fn run_meta(args : Array[String]) -> (Int, String) {
  run_meta_with_timeout(args, 3000)
}

async fn timed_meta(
  label : String,
  args : Array[String],
  timeout_ms : Int,
) -> (Int, String, Int64) {
  let started = @async.now()
  let (code, output) = run_meta_with_timeout(args, timeout_ms)
  let elapsed = @async.now() - started
  @stdio.stdout.write("[timing] \{label} took \{elapsed}ms\n")
  (code, output, elapsed)
}

async test "service lifecycle is idempotent" {
  let _ = run_meta(["stop"])
  clear_test_service_state()
  let (idle_stop_code, idle_stop_output, _) = timed_meta("idle stop", ["stop"], 3000)
  assert_eq(idle_stop_code, 0)
  assert_true(has_json_flag(idle_stop_output, "ok", "true"))
  assert_true(has_json_flag(idle_stop_output, "stopped", "false"))
  assert_true(has_json_flag(idle_stop_output, "not_running", "true"))

  write_test_service_state("999999", "{\"port\":19199}")
  let (start_code, start_output, _) = timed_meta(
    "start --silent",
    ["start", "18120", "--silent"],
    1500,
  )
  assert_eq(start_code, 0)
  assert_true(has_json_flag(start_output, "ok", "true"))
  assert_true(has_json_flag(start_output, "started", "true"))
  assert_true(has_json_flag(start_output, "already_running", "false"))
  assert_true(has_json_string(start_output, "url", "http://localhost:18120"))
  let (status_code, status_output, _) = timed_meta("status", ["status"], 3000)
  assert_eq(status_code, 0)
  assert_true(status_output.contains("\"clients\""))

  let (repeat_start_code, repeat_start_output, _) = timed_meta(
    "repeat start --silent",
    ["start", "--silent"],
    1500,
  )
  assert_eq(repeat_start_code, 0)
  assert_true(has_json_flag(repeat_start_output, "ok", "true"))
  assert_true(has_json_flag(repeat_start_output, "started", "false"))
  assert_true(has_json_flag(repeat_start_output, "already_running", "true"))
  assert_true(has_json_string(repeat_start_output, "url", "http://localhost:18120"))

  let (stop_code, stop_output, _) = timed_meta("stop running", ["stop"], 3000)
  assert_eq(stop_code, 0)
  assert_true(has_json_string(stop_output, "kind", "stop"))

  let (final_stop_code, final_stop_output, _) = timed_meta("final stop", ["stop"], 3000)
  assert_eq(final_stop_code, 0)
  assert_true(has_json_flag(final_stop_output, "ok", "true"))
  assert_true(has_json_flag(final_stop_output, "stopped", "false"))
  assert_true(has_json_flag(final_stop_output, "not_running", "true"))
  clear_test_service_state()
}

async fn write_error(message : String) -> Unit {
  let payload : Json = { "message": message }
  @stdio.stdout.write("[ERROR] \{payload.stringify()}\n")
}

async fn fail_cli(message : String) -> Unit {
  write_error(message)
  @sys.exit(1)
}

fn help_text(runtime : Runtime) -> String {
  let action_names = runtime.app_actions.keys().iter().join(",")
  "System: start, status, history, test, query <json|kind>, exec <json|action>, stop\n" +
  "Examples:\n" +
  "  meta\n" +
  "  meta start\n" +
  "  meta status\n" +
  "  meta test\n" +
  "  meta test host\n" +
  "  meta test counter\n" +
  "  meta query ui\n" +
  "  meta query {\"kind\":\"selector\",\"selector\":\"button\"}\n" +
  "  meta exec {\"kind\":\"click\",\"selector\":\"button\"}\n" +
  "  meta exec {\"kind\":\"action\",\"name\":\"undo\"}\n" +
  "App Actions: \{action_names}\n"
}

fn local_help_text() -> String {
  let runtime = make_runtime(".")
  init_app(runtime)
  help_text(runtime)
}

fn app_test_package() -> String {
  "ch3coohlink/MetaEditor/app/test"
}

fn app_test_ids() -> Array[String] {
  ["host", "counter"]
}

fn is_known_app_test(app_id : String) -> Bool {
  for id in app_test_ids() {
    if id == app_id {
      return true
    }
  }
  false
}

#cfg(platform="windows")
fn app_test_command(app_id : String) -> (String, Array[String]) {
  (
    "powershell",
    [
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      "scripts\\build-native.ps1",
      "-Package",
      "test",
      "-Test",
      "-TestPackage",
      app_test_package(),
      "-TestFilter",
      "*\{app_id}*",
    ],
  )
}

#cfg(not(platform="windows"))
fn app_test_command(app_id : String) -> (String, Array[String]) {
  (
    "moon",
    [
      "test",
      "--target",
      "native",
      "-p",
      app_test_package(),
      "--filter",
      "*\{app_id}*",
    ],
  )
}

#cfg(platform="windows")
fn all_app_test_command() -> (String, Array[String]) {
  (
    "powershell",
    [
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      "scripts\\build-native.ps1",
      "-Package",
      "test",
      "-Test",
      "-TestPackage",
      app_test_package(),
    ],
  )
}

#cfg(not(platform="windows"))
fn all_app_test_command() -> (String, Array[String]) {
  (
    "moon",
    [
      "test",
      "--target",
      "native",
      "-p",
      app_test_package(),
    ],
  )
}

async fn run_cli_command(runtime : Runtime, cmd : String, rest : String) -> Json raise {
  if runtime.app_actions.contains(cmd) {
    return run_action(runtime, cmd, 50)
  }
  match cmd {
    "status" => status_json(runtime)
    "history" => Json::array(runtime.ui_history)
    "query" => run_query(runtime, rest)
    "exec" => run_exec(runtime, rest)
    _ => raise ServiceError("Unknown command: \{cmd}")
  }
}


async fn handle_control_request(
  runtime : Runtime,
  _request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let payload = body.read_all().json()
  let cmd = json_string(payload, "cmd").unwrap_or("")
  let arg = json_string(payload, "arg").unwrap_or("")
  if cmd == "stop" {
    request_stop_service(runtime)
    respond_ok(conn, stop_ok_result())
    invoke_stop_service(runtime)
    return
  }
  try {
    let result : Json = match cmd {
      "help" => Json::object({ "text": Json::string(help_text(runtime)) })
      _ => run_cli_command(runtime, cmd, arg)
    }
    respond_ok(conn, result)
    if runtime.stop_requested.val {
      runtime.stop_requested.val = false
      invoke_stop_service(runtime)
    }
  } catch {
    ServiceError(message) => respond_err(conn, 400, "BadRequest", message)
    e => respond_err(conn, 500, "InternalError", "\{e}")
  }
}

fn join_args(args : Array[String]) -> String {
  args.iter().join(" ")
}

fn default_addr(port : Int) -> @socket.Addr {
  @socket.Addr::parse("127.0.0.1:\{port}") catch {
    _ => abort("invalid default addr")
  }
}

pub async fn run_service(addr : @socket.Addr) -> Unit {
  let lock = acquire_service_lock()
  let root_dir = "."
  let runtime = make_runtime(root_dir)
  init_app(runtime)
    let cleanup = async fn() {
      runtime.stop_service.val = None
      let _ = try {
        remove_service_pid()
        clear_service_state_file()
      } catch {
        _ => ()
      }
      release_service_lock(lock)
    }
    try {
      let server = bind_http_server(addr, max_port_tries)
      runtime.stop_service.val = Some(fn() { server.close() })
      let listen_addr = server.addr()
      write_service_pid(current_pid())
      write_service_state(listen_addr.port())
      @stdio.stdout.write(
        "\n🚀 MetaEditor Host Active: http://localhost:\{listen_addr.port()}\n\n"
      )
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => flush_live_batches(runtime))
        server.run_forever((request, body, conn) => {
          if request.headers.get("upgrade") is Some("websocket") {
            serve_websocket(runtime, request, conn)
            return
          }
          if request.path == control_path {
            handle_control_request(runtime, request, body, conn)
            return
          }
          let file_path = if request.path == "/" {
            "index.html"
          } else if request.path.has_prefix("/") {
            request.path[1:].to_string()
          } else {
            request.path
          }
          serve_file(runtime, conn, file_path)
        })
      })
      cleanup()
    } catch {
      err => {
        cleanup()
        raise err
      }
    }
}

async fn call_service_at_port(port : Int, cmd : String, arg : String) -> Json raise {
  let client = @http.Client::new("http://127.0.0.1:\{port}")
  defer client.close()
  let response = client.post(
    control_path,
    Json::object({
      "cmd": Json::string(cmd),
      "arg": Json::string(arg),
    }).stringify(),
    extra_headers={ "Content-Type": "application/json" },
  )
  let payload = client.read_all().json()
  if response.code < 200 || response.code >= 300 {
    raise ServiceError(json_string(payload, "error").unwrap_or("service request failed"))
  }
  if json_bool(payload, "ok").unwrap_or(false) {
    match json_field(payload, "result") {
      Some(result) => result
      None => null
    }
  } else {
    raise ServiceError(json_string(payload, "error").unwrap_or("service request failed"))
  }
}

async fn call_service(cmd : String, arg : String) -> Json raise {
  call_service_at_port(require_service_port("service is not ready"), cmd, arg)
}

fn test_temp_path(name : String) -> String {
  let dir = temp_dir()
  let stem = "metaeditor-\{name}-\{current_pid()}-\{@async.now()}"
  match dir {
    [.., .. "/"] => "\{dir}\{stem}"
    [.., .. "\\"] => "\{dir}\{stem}"
    _ => "\{dir}/\{stem}"
  }
}

async fn read_temp_output(path : String) -> String {
  let text = if @fs.exists(path) { @fs.read_file(path).text() } else { "" }
  if @fs.exists(path) {
    @fs.remove(path)
  }
  text
}

async fn run_test_process(
  cmd : String,
  args : Array[String],
  prefix : String,
  ext : Map[String, Json],
) -> Json {
  let stdout_path = test_temp_path("\{prefix}.stdout.log")
  let stderr_path = test_temp_path("\{prefix}.stderr.log")
  @async.with_task_group(group => {
    let proc = @process.spawn(
      group, cmd, args, cwd=".",
      stdout=@process.redirect_to_file(stdout_path, create=0o644, truncate=true),
      stderr=@process.redirect_to_file(stderr_path, create=0o644, truncate=true),
    )
    for tries = 0; tries < 1500; tries = tries + 1 {
      if proc.try_wait() is Some(code) {
        ext["ok"] = Json::boolean(code == 0)
        ext["exit_code"] = code.to_json()
        ext["stdout"] = Json::string(read_temp_output(stdout_path))
        ext["stderr"] = Json::string(read_temp_output(stderr_path))
        return Json::object(ext)
      }
      @async.sleep(20)
    }
    proc.cancel()
    ext["ok"] = Json::boolean(false)
    ext["exit_code"] = (-1).to_json()
    ext["error"] = Json::string("app test timed out")
    ext["stdout"] = Json::string(read_temp_output(stdout_path))
    ext["stderr"] = Json::string(read_temp_output(stderr_path))
    Json::object(ext)
  })
}

async fn run_app_test(app_id : String) -> Json {
  let (cmd, args) = app_test_command(app_id)
  run_test_process(cmd, args, app_id, { "app_id": Json::string(app_id) })
}

async fn run_all_app_tests() -> Json {
  let (cmd, args) = all_app_test_command()
  run_test_process(cmd, args, "apps", {
    "kind": Json::string("all"),
    "apps": app_test_ids().to_json(),
  })
}

async fn write_test_summary(results : Array[Json]) -> Unit {
  let mut ok = true
  let summary : Map[String, Json] = {}
  for result in results {
    if !json_bool(result, "ok").unwrap_or(false) {
      ok = false
    }
    match json_string(result, "app_id") {
      Some(app_id) => summary[app_id] = result
      None => ()
    }
  }
  @stdio.stdout.write(Json::object({
    "ok": Json::boolean(ok),
    "kind": Json::string("app_test"),
    "results": Json::object(summary),
  }).stringify() + "\n")
  if !ok {
    @sys.exit(1)
  }
}

async fn run_meta_test_mode(arg : String) -> Unit {
  if arg.trim() == "" {
    let result = run_all_app_tests()
    let ok = json_bool(result, "ok").unwrap_or(false)
    @stdio.stdout.write(Json::object({
      "ok": Json::boolean(ok),
      "kind": Json::string("app_test"),
      "results": Json::object({
        "all": result,
      }),
    }).stringify() + "\n")
    if !ok {
      @sys.exit(1)
    }
    return
  }
  let app_id = arg.trim().to_string()
  if !is_known_app_test(app_id) {
    fail_cli("unknown app test target: \{arg.trim()}")
    return
  }
  write_test_summary([run_app_test(app_id)])
}

async fn run_client_mode(cmd : String, arg : String) -> Unit {
  match cmd {
    "help" => @stdio.stdout.write(local_help_text())
    "start" => {
      let mut port = default_port
      let mut silent = false
      for token in arg.split(" ") {
        let part = token.trim()
        if part == "" {
          continue
        }
        if part == "--silent" {
          silent = true
        } else {
          port = @strconv.parse_int(part) catch { _ => port }
        }
      }
      run_start_mode(port, silent)
    }
    "test" => run_meta_test_mode(arg)
    "stop" => run_stop_mode()
    _ =>
      try {
        let result = call_service(cmd, arg)
        @stdio.stdout.write("\{result.stringify()}\n")
      } catch {
        ServiceError(message) => fail_cli(message)
        e => fail_cli("\{e}")
      }
  }
}

async fn clear_stale_service_state() -> Unit {
  remove_service_pid() catch { _ => () }
  clear_service_state_file() catch { _ => () }
}

async fn service_lock_held() -> Bool {
  match (try? try_acquire_service_lock() : Result[ServiceLock?, _]) {
    Ok(Some(lock)) => {
      release_service_lock(lock)
      false
    }
    Ok(None) => true
    Err(_) => true
  }
}

async fn wait_for_service_port(error_message : String) -> Int raise {
  for tries = 0; tries < 60; tries = tries + 1 {
    if (try? read_service_port() : Result[Int, _]) is Ok(port) {
      if (try? call_service_at_port(port, "status", "") : Result[Json, _]) is Ok(_) { return port }
    }
    @async.sleep(50)
  }
  raise ServiceError(error_message)
}

async fn detect_service_port() -> Int? raise {
  if !service_lock_held() {
    clear_stale_service_state()
    return None
  }
  Some(wait_for_service_port("service lock is held but service did not become ready"))
}

async fn require_service_port(_error_message : String) -> Int raise {
  match detect_service_port() {
    Some(port) => port
    None => raise ServiceError("service is not running")
  }
}

async fn wait_for_lock_released() -> Bool {
  for tries = 0; tries < 60; tries = tries + 1 {
    if !service_lock_held() { return true }
    @async.sleep(50)
  }
  false
}

fn start_result(port : Int, started : Bool, already_running : Bool) -> Json {
  Json::object({
    "ok": Json::boolean(true),
    "started": Json::boolean(started),
    "already_running": Json::boolean(already_running),
    "port": port.to_json(),
    "url": Json::string("http://localhost:\{port}"),
  })
}

pub fn should_open_browser(status : Json) -> Bool {
  json_int(status, "browsers").unwrap_or(0) == 0
}

#cfg(platform="windows")
async fn open_browser(url : String) -> Unit raise {
  let _ = @process.spawn_orphan("rundll32", ["url.dll,FileProtocolHandler", url])
}

#cfg(target="wasm")
async fn open_browser(_url : String) -> Unit raise {
  ()
}

#cfg(all(not(platform="windows"), not(target="wasm"), not(platform="darwin")))
async fn open_browser(url : String) -> Unit raise {
  let _ = @process.spawn_orphan("xdg-open", [url])
}

#cfg(platform="darwin")
async fn open_browser(url : String) -> Unit raise {
  let _ = @process.spawn_orphan("open", [url])
}

async fn ensure_browser_page(port : Int) -> Unit {
  let status_result : Result[Json, _] = try? call_service_at_port(port, "status", "")
  match status_result {
    Ok(status) =>
      if should_open_browser(status) {
        let _ = try? open_browser("http://localhost:\{port}")
      }
    Err(_) => ()
  }
}

#cfg(platform="windows")
async fn launch_background_service(port : Int) -> Unit raise {
  let exe = @env.args()[0]
  let stdout_log = "\{temp_dir()}/metaeditor-service.stdout.log"
  let stderr_log = "\{temp_dir()}/metaeditor-service.stderr.log"
  let stdout = @process.redirect_to_file(stdout_log, create=0o644, truncate=true)
  let stderr = @process.redirect_to_file(stderr_log, create=0o644, truncate=true)
    let _ = @process.spawn_orphan(
      exe,
      [],
      cwd=".",
      extra_env={
        "METAEDITOR_SERVICE_PORT": "\{port}",
      },
      stdout=stdout,
    stderr=stderr,
  )
}

#cfg(not(platform="windows"))
async fn launch_background_service(port : Int) -> Unit raise {
  let exe = @env.args()[0]
  let stdout = @process.redirect_to_file("/tmp/metaeditor-service.stdout.log", create=0o644, truncate=true)
  let stderr = @process.redirect_to_file("/tmp/metaeditor-service.stderr.log", create=0o644, truncate=true)
    let _ = @process.spawn_orphan(
      exe,
      [],
      cwd=".",
      extra_env={
        "METAEDITOR_SERVICE_PORT": "\{port}",
      },
      stdout=stdout,
    stderr=stderr,
  )
}

fn stop_not_running_result() -> Json {
  Json::object({
    "ok": Json::boolean(true),
    "stopped": Json::boolean(false),
    "not_running": Json::boolean(true),
  })
}

fn stop_ok_result() -> Json {
  Json::object({
    "ok": Json::boolean(true),
    "kind": Json::string("stop"),
  })
}

async fn run_stop_mode() -> Unit {
  if !service_lock_held() {
    clear_stale_service_state()
    @stdio.stdout.write(stop_not_running_result().stringify() + "\n")
    return
  }

  try {
    let _ = call_service("stop", "")
    let released = wait_for_lock_released()
    if !released {
      fail_cli("service did not stop cleanly")
      return
    }
    remove_service_pid() catch { _ => () }
    clear_service_state_file() catch { _ => () }
    @stdio.stdout.write(stop_ok_result().stringify() + "\n")
  } catch {
    ServiceError(message) => fail_cli(message)
    e => fail_cli("\{e}")
  }
}

async fn run_start_mode(port : Int, silent : Bool) -> Unit {
  match detect_service_port() {
    Some(running_port) => {
      if !silent {
        ensure_browser_page(running_port)
      }
      @stdio.stdout.write(start_result(running_port, false, true).stringify() + "\n")
    }
    None =>
      try {
        clear_stale_service_state()
        launch_background_service(port)
        let running_port = wait_for_service_port("service did not start")
        if !silent {
          ensure_browser_page(running_port)
        }
        @stdio.stdout.write(start_result(running_port, true, false).stringify() + "\n")
      } catch {
        ServiceError(message) => fail_cli(message)
        e => fail_cli("\{e}")
      }
  }
}


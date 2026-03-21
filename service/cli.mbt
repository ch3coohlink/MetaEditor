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

async fn run_cli_command(runtime : Runtime, cmd : String, rest : String) -> Json raise {
  if runtime.app_actions.contains(cmd) {
    return run_action(runtime, cmd, 50)
  }
  match cmd {
    "status" => status_json(runtime)
    "history" => Json::array(runtime.ui_history)
    "query" => run_query(runtime, rest)
    "exec" => run_exec(runtime, rest)
    "test" => run_app_test(runtime)
    _ => raise ServiceError("Unknown command: \{cmd}")
  }
}

async fn handle_control_request(
  runtime : Runtime,
  _request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
  stop_service : () -> Unit,
) -> Unit {
  let payload = body.read_all().json()
  let cmd = json_string(payload, "cmd").unwrap_or("")
  let arg = json_string(payload, "arg").unwrap_or("")
  try {
    let result : Json = match cmd {
      "help" => Json::object({ "text": Json::string(help_text(runtime)) })
      "stop" => {
        stop_service()
        Json::object({
          "ok": Json::boolean(true),
          "kind": Json::string("stop"),
        })
      }
      _ => run_cli_command(runtime, cmd, arg)
    }
    conn
    ..send_response(200, "OK", extra_headers={ "Content-Type": "application/json" })
    ..write(Json::object({
      "ok": Json::boolean(true),
      "result": result,
    }).stringify())
    .end_response()
  } catch {
    ServiceError(message) =>
      conn
      ..send_response(400, "BadRequest", extra_headers={ "Content-Type": "application/json" })
      ..write(Json::object({
        "ok": Json::boolean(false),
        "error": Json::string(message),
      }).stringify())
      .end_response()
    e =>
      conn
      ..send_response(500, "InternalError", extra_headers={ "Content-Type": "application/json" })
      ..write(Json::object({
        "ok": Json::boolean(false),
        "error": Json::string("\{e}"),
      }).stringify())
      .end_response()
  }
}

enum Mode {
  Start(Int)
  Serve(Int)
  Command(String, String)
} derive(Show, Eq)

fn join_args(args : Array[String]) -> String {
  args.iter().join(" ")
}

fn parse_mode(args : Array[String]) -> Mode {
  match args {
    [_, "start", port, ..] => Start(@strconv.parse_int(port) catch { _ => default_port })
    [_, "start"] => Start(default_port)
    [_, "serve", port, ..] => Serve(@strconv.parse_int(port) catch { _ => default_port })
    [_, "serve"] => Serve(default_port)
    [_, "help", ..] => Command("help", "")
    [_, "status", ..] => Command("status", "")
    [_, "history", ..] => Command("history", "")
    [_, "test", ..] => Command("test", "")
    [_, "stop", ..] => Command("stop", "")
    [_, "query", rest, ..tail] => Command("query", join_args([rest, ..tail]))
    [_, "exec", rest, ..tail] => Command("exec", join_args([rest, ..tail]))
    [_, cmd, rest, ..tail] => Command(cmd, join_args([rest, ..tail]))
    [_, cmd] => Command(cmd, "")
    _ => Start(default_port)
  }
}

fn default_addr(port : Int) -> @socket.Addr {
  @socket.Addr::parse("127.0.0.1:\{port}") catch {
    _ => abort("invalid default addr")
  }
}

pub async fn serve_daemon(addr : @socket.Addr) -> Unit {
  let lock = acquire_service_lock()
  let root_dir = "."
  let runtime = make_runtime(root_dir)
  init_app(runtime)
  try {
    let server = bind_http_server(addr, max_port_tries)
    let listen_addr = server.addr()
    write_service_pid(current_pid())
    write_service_state(lock, listen_addr.port())
    @stdio.stdout.write("\n🚀 MetaEditor Host Active: http://localhost:\{listen_addr.port()}\n\n")
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => flush_live_batches(runtime))
      server.run_forever((request, body, conn) => {
        if request.headers.get("upgrade") is Some("websocket") {
          serve_websocket(runtime, request, conn)
          return
        }
        if request.path == control_path {
          handle_control_request(runtime, request, body, conn, fn() { server.close() })
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
    remove_service_pid() catch { _ => () }
    remove_service_state(lock) catch { _ => () }
    clear_service_state_file() catch { _ => () }
    release_service_lock(lock)
  } catch {
    err => {
      remove_service_pid() catch { _ => () }
      remove_service_state(lock) catch { _ => () }
      clear_service_state_file() catch { _ => () }
      release_service_lock(lock)
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
  let _ = ensure_service_running()
  let port = read_service_port()
  call_service_at_port(port, cmd, arg)
}

async fn run_client_mode(cmd : String, arg : String) -> Unit {
  if cmd == "help" {
    @stdio.stdout.write(local_help_text())
    return
  }

  if cmd == "stop" {
    run_stop_mode()
    return
  }

  try {
    let result = call_service(cmd, arg)
    @stdio.stdout.write("\{result.stringify()}\n")
  } catch {
    ServiceError(message) => fail_cli(message)
    e =>
      fail_cli("\{e}")
  }
}

async fn clear_stale_service_state() -> Unit {
  remove_service_pid() catch { _ => () }
  clear_service_state_file() catch { _ => () }
}

async fn ensure_service_running() -> Int raise {
  let pid = read_service_pid()
  let _ = read_service_port()
  pid
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
    ["serve", "\{port}"],
    cwd=".",
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
    ["serve", "\{port}"],
    cwd=".",
    stdout=stdout,
    stderr=stderr,
  )
}

async fn wait_for_started_service(_port : Int) -> Int raise {
  let mut tries = 0
  while tries < 60 {
    let pid_result : Result[Int, _] = try? read_service_pid()
    let port_result : Result[Int, _] = try? read_service_port()
    match (pid_result, port_result) {
      (Ok(_), Ok(running_port)) =>
        match (try? call_service_at_port(running_port, "status", "") : Result[Json, _]) {
          Ok(_) => return running_port
          Err(_) => {
            @async.sleep(50)
            tries += 1
          }
        }
      _ => {
        @async.sleep(50)
        tries += 1
      }
    }
  }
  raise ServiceError("service did not start")
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

#cfg(platform="windows")
async fn terminate_service_process(pid : Int) -> Bool {
  let (code, _) = @process.collect_stdout("taskkill", ["/PID", "\{pid}", "/F"])
  code == 0
}

#cfg(not(platform="windows"))
async fn terminate_service_process(pid : Int) -> Bool {
  let (code, _) = @process.collect_stdout("kill", ["-TERM", "\{pid}"])
  code == 0
}

async fn run_stop_mode() -> Unit {
  match (try? read_service_pid() : Result[Int, _]) {
    Ok(pid) => {
      let stopped = (try? terminate_service_process(pid) : Result[Bool, _]).unwrap_or(false)
      remove_service_pid() catch { _ => () }
      clear_service_state_file() catch { _ => () }
      let result = if stopped { stop_ok_result() } else { stop_not_running_result() }
      @stdio.stdout.write(result.stringify() + "\n")
    }
    Err(_) => @stdio.stdout.write(stop_not_running_result().stringify() + "\n")
  }
}

async fn detect_running_port() -> Int? {
  let pid_result : Result[Int, _] = try? read_service_pid()
  let port_result : Result[Int, _] = try? read_service_port()
  match (pid_result, port_result) {
    (Ok(_), Ok(port)) =>
      match (try? call_service_at_port(port, "status", "") : Result[Json, _]) {
        Ok(_) => Some(port)
        Err(_) => {
          clear_stale_service_state()
          None
        }
      }
    _ => None
  }
}

async fn run_start_mode(port : Int) -> Unit {
  match detect_running_port() {
    Some(running_port) => {
      ensure_browser_page(running_port)
      @stdio.stdout.write(start_result(running_port, false, true).stringify() + "\n")
    }
    None =>
      try {
        clear_stale_service_state()
        launch_background_service(port)
        let running_port = wait_for_started_service(port)
        ensure_browser_page(running_port)
        @stdio.stdout.write(start_result(running_port, true, false).stringify() + "\n")
      } catch {
        ServiceError(message) => fail_cli(message)
        e => fail_cli("\{e}")
      }
  }
}


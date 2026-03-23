// ======== 入口和帮助 ========
let boot_service : String = "--internal_boot_as_service"

async fn write_error(message: String) -> Unit {
  @stdio.stdout.write("[ERROR] \{message}\n")
}

async fn main {
  let args = @env.args()
  let mut boot = false
  let mut port = default_port
  let mut state_dir : String? = None
  let cmd_args : Array[String] = []
  let mut i = 1
  while i < args.length() {
    let token = args[i]
    if token == boot_service {
      boot = true
    } else if token == "--state-dir" && i + 1 < args.length() {
      state_dir = Some(args[i + 1])
      i += 1
    } else if boot && token == "--port" && i + 1 < args.length() {
      port = @strconv.parse_int(args[i + 1]) catch { _ => default_port }
      i += 1
    } else {
      cmd_args.push(token)
    }
    i += 1
  }
  match state_dir {
    Some(dir) => set_state_dir(dir)
    None => ()
  }
  if boot {
    run_service(default_addr(port))
  } else {
    match cmd_args {
      [cmd, rest, ..tail] => run_client_mode(cmd, join_args([rest, ..tail]))
      [cmd] => run_client_mode(cmd, "")
      _ => run_client_mode("start", "")
    }
  }
}

async fn fail_cli(message: String) -> Unit {
  write_error(message)
  @sys.exit(1)
}

fn help_text() -> String {
  "Usage:\n" +
  "  meta [--state-dir DIR] [command]\n" +
  "\n" +
  "Flags:\n" +
  "  --state-dir DIR   Use DIR for service state files.\n" +
  "\n" +
  "Commands:\n" +
  "  start    Start the service.\n" +
  "           --silent   Do not open the browser.\n" +
  "           --port N   Start from port N.\n" +
  "  status   Show whether the service is running.\n" +
  "  stop     Stop the service.\n" +
  "\n"
}

fn join_args(args: Array[String]) -> String {
  args.iter().join(" ")
}

fn default_addr(port: Int) -> @socket.Addr {
  @socket.Addr::parse("127.0.0.1:\{port}") catch {
    _ => abort("invalid default addr")
  }
}

// ======== 存活探测和状态清理 ========
async fn clear_stale_service_state() -> Unit {
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

async fn wait_port(error_message: String) -> Int raise {
  for tries = 0; tries < 60; tries = tries + 1 {
    if (try? read_service_port() : Result[Int, _]) is Ok(port) {
      if (try? call_at(port, "status", "") : Result[String, _]) is Ok(_) { return port }
    }
    @async.sleep(50)
  }
  raise ServiceError(error_message)
}

async fn detect_port() -> Int? raise {
  if !service_lock_held() {
    clear_stale_service_state()
    return None
  }
  Some(wait_port("service lock is held but service did not become ready"))
}

async fn require_port() -> Int raise {
  match detect_port() {
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

// ======== 平台相关的后台启动 ========
#cfg(platform="windows")
async fn open_browser(url: String) -> Unit raise {
  let _ = @process.spawn_orphan("rundll32", ["url.dll,FileProtocolHandler", url])
}

#cfg(target="wasm")
async fn open_browser(_url: String) -> Unit raise {
  ()
}

#cfg(all(not(platform="windows"), not(target="wasm"), not(platform="darwin")))
async fn open_browser(url: String) -> Unit raise {
  let _ = @process.spawn_orphan("xdg-open", [url])
}

#cfg(platform="darwin")
async fn open_browser(url: String) -> Unit raise {
  let _ = @process.spawn_orphan("open", [url])
}

#cfg(platform="windows")
async fn launch_background_service(port: Int) -> Unit raise {
  let exe = @env.args()[0]
  let dir = state_dir()
  let _ = @process.spawn_orphan(
    exe,
    [boot_service, "--state-dir", dir, "--port", "\{port}"],
    cwd=".",
  )
}

#cfg(not(platform="windows"))
async fn launch_background_service(port: Int) -> Unit raise {
  let exe = @env.args()[0]
  let dir = state_dir()
  let _ = @process.spawn_orphan(
    exe,
    [boot_service, "--state-dir", dir, "--port", "\{port}"],
    cwd=".",
  )
}

// ======== 生命周期命令 ========
async fn stop() -> Unit {
  if !service_lock_held() {
    clear_stale_service_state()
    @stdio.stdout.write("service is not running\n")
    return
  }
  try {
    let _ = call_service("stop", "")
    let released = wait_for_lock_released()
    if !released {
      fail_cli("service did not stop cleanly")
      return
    }
    clear_service_state_file() catch { _ => () }
    @stdio.stdout.write("stopped\n")
  } catch {
    ServiceError(message) => fail_cli(message)
    e => fail_cli("\{e}")
  }
}

async fn start(port: Int, silent: Bool) -> Unit {
  match detect_port() {
    Some(running_port) => {
      if !silent {
        let _ = try? open_browser("http://localhost:\{running_port}")
      }
      @stdio.stdout.write("already running http://localhost:\{running_port}\n")
    }
    None =>
      try {
        clear_stale_service_state()
        launch_background_service(port)
        let running_port = wait_port("service did not start")
        if !silent {
          let _ = try? open_browser("http://localhost:\{running_port}")
        }
        @stdio.stdout.write("started http://localhost:\{running_port}\n")
      } catch {
        ServiceError(message) => fail_cli(message)
        e => fail_cli("\{e}")
      }
  }
}

// ======== HTTP client：命令执行和控制口调用 ========
async fn status_text(runtime: Runtime) -> String {
  let port = read_service_port() catch { _ => default_port }
  let browser = if runtime.state.browser_connected.val { "connected" } else { "waiting" }
  "running http://localhost:\{port}\nbrowser: \{browser}\n"
}

async fn run(runtime: Runtime, cmd: String, _rest: String) -> String raise {
  match cmd {
    "help" => help_text()
    "host_stop_service" => host_stop_service(runtime, 50)
    "status" => status_text(runtime)
    _ => raise ServiceError("Unknown command: \{cmd}")
  }
}

async fn handle(
  runtime: Runtime,
  _request: @http.Request,
  body: &@io.Reader,
  conn: @http.ServerConnection,
) -> Unit {
  let payload = body.read_all().json()
  let cmd = json_string(payload, "cmd").unwrap_or("")
  let arg = json_string(payload, "arg").unwrap_or("")
  if cmd == "stop" {
    request_stop_service(runtime)
    respond_ok(conn, Json::string("stopped\n"))
    invoke_stop_service(runtime)
    return
  }
  try {
    respond_ok(conn, Json::string(run(runtime, cmd, arg)))
    if runtime.shutting_down.val {
      invoke_stop_service(runtime)
    }
  } catch {
    ServiceError(message) => respond_err(conn, 400, "BadRequest", message)
    e => respond_err(conn, 500, "InternalError", "\{e}")
  }
}

// ======== 本地 CLI 分发 ========
async fn run_client_mode(cmd: String, arg: String) -> Unit {
  match cmd {
    "help" => @stdio.stdout.write(help_text())
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
      start(port, silent)
    }
    "stop" => stop()
    _ =>
      try {
        @stdio.stdout.write(call_service(cmd, arg))
      } catch {
        ServiceError(message) => fail_cli(message)
        e => fail_cli("\{e}")
      }
  }
}

// ======== HTTP server：服务运行态 ========
pub async fn run_service(addr: @socket.Addr) -> Unit {
  let lock = acquire_service_lock()
  let runtime = make_runtime(".")
  init_app(runtime)
  let cleanup = async fn() {
    release_state_file()
    let _ = try {
      clear_service_state_file()
    } catch {
      _ => ()
    }
    release_service_lock(lock)
  }
  try {
    let server = bind_http_server(addr, max_port_tries)
    let listen_addr = server.addr()
    write_service_state(current_pid(), listen_addr.port())
    if !retain_state_file(service_state_path()) {
      raise ServiceError("failed to retain service state file")
    }
    @stdio.stdout.write("\nMetaEditor Host Active: http://localhost:\{listen_addr.port()}\n\n")
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => flush_live_batches(runtime))
      server.run_forever((request, body, conn) => {
        if request.headers.get("upgrade") is Some("websocket") {
          serve_websocket(runtime, request, conn)
          return
        }
        if request.path == control_path {
          handle(runtime, request, body, conn)
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

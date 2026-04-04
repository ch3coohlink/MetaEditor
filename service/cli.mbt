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
  let mut debug_timing = false
  let cmd_args : Array[String] = []
  let mut i = 1
  while i < args.length() {
    let token = args[i]
    if token == boot_service {
      boot = true
    } else if token == "--debug-timing" {
      debug_timing = true
    } else if token == "--state-dir" && i + 1 < args.length() {
      state_dir = Some(args[i + 1])
      i += 1
    } else if boot && token == "--port" && i + 1 < args.length() {
      port = @string.parse_int(args[i + 1]) catch { _ => default_port }
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
  set_debug_timing(debug_timing)
  if boot {
    run_service(default_addr(port))
  } else {
    match cmd_args {
      [cmd, ..rest] => {
        let args : Array[String] = []
        for item in rest {
          args.push(item)
        }
        run_client_mode(cmd, args)
      }
      _ => run_client_mode("start", [])
    }
  }
}

async fn fail_cli(message: String) -> Unit {
  write_error(message)
  @sys.exit(1)
}

fn help_text() -> String {
  "Usage:\n" +
  "  meta [<command>] [<flags>]\n" +
  "\n" +
  "Flags:\n" +
  "  --state-dir DIR  Use DIR for service state files.\n" +
  "  --debug-timing   Print timing logs.\n" +
  "  --port PORT      Try boot from PORT.\n" +
  "\n" +
  "Commands:\n" +
  "  start    Start the service.\n" +
  "           --silent   Do not open the browser.\n" +
  "           --port N   Start from port N.\n" +
  "  restart  Restart the service (share flag with start command).\n" +
  "  status   Show whether the service is running.\n" +
  "  stop     Stop the service.\n" +
  "  roots [ENTRY_ID...]\n" +
  "           Replace top-level instances.\n" +
  "  sync     Wait browser bridge sync.\n" +
  "  help [INSTANCE_ID]\n" +
  "           Show service help or one instance action help.\n" +
  "  exec INSTANCE_ID ACTION [ARGS...]\n" +
  "           Run one instance action.\n" +
  "  repl     Start a long-lived command session.\n" +
  "\n"
}

fn quote_shell_arg(arg : String) -> String {
  let mut need_quote = arg == ""
  for i = 0; i < arg.length(); i = i + 1 {
    let ch = arg[i:i + 1].to_string()
    if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "\"" || ch == "\\" {
      need_quote = true
    }
  }
  if !need_quote { return arg }
  let out = StringBuilder::new()
  out.write_string("\"")
  for i = 0; i < arg.length(); i = i + 1 {
    let ch = arg[i:i + 1].to_string()
    if ch == "\"" || ch == "\\" {
      out.write_string("\\")
    }
    out.write_string(ch)
  }
  out.write_string("\"")
  out.to_string()
}

fn join_shell_args(args : Array[String]) -> String {
  args.map(arg => quote_shell_arg(arg)).iter().join(" ")
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

async fn wait_browser_connected_at(port: Int, timeout_ms: Int) -> Bool {
  let max_tries = (timeout_ms + 49) / 50
  for tries = 0; tries < max_tries; tries = tries + 1 {
    let status = call_at(port, "status", "") catch { _ => "" }
    if status.contains("browser: connected") { return true }
    @async.sleep(50)
  }
  false
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
  let debug_args = if debug_timing_enabled() { ["--debug-timing"] } else { [] }
  let _ = @process.spawn_orphan(
    exe,
    [boot_service, "--state-dir", dir, ..debug_args, "--port", "\{port}"],
    cwd=".",
  )
}

#cfg(not(platform="windows"))
async fn launch_background_service(port: Int) -> Unit raise {
  let exe = @env.args()[0]
  let dir = state_dir()
  let debug_args = if debug_timing_enabled() { ["--debug-timing"] } else { [] }
  let _ = @process.spawn_orphan(
    exe,
    [boot_service, "--state-dir", dir, ..debug_args, "--port", "\{port}"],
    cwd=".",
  )
}

// ======== 生命周期命令 ========
async fn stop() -> Unit {
  stop_running_service("stopped\n", "service is not running\n")
}

async fn stop_running_service(
  stopped_text : String,
  idle_text : String
) -> Unit {
  if !service_lock_held() {
    clear_stale_service_state()
    @stdio.stdout.write(idle_text)
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
    @stdio.stdout.write(stopped_text)
  } catch {
    ServiceError(message) => fail_cli(message)
    e => fail_cli("\{e}")
  }
}

async fn start(port: Int, silent: Bool, verb~: String = "started") -> Unit {
  start_service(port, silent, verb)
}

async fn start_service(port : Int, silent : Bool, verb : String) -> Unit {
  let detect_started = @async.now()
  match detect_port() {
    Some(running_port) => {
      log_timing("boot", "start detect_port", @async.now() - detect_started)
      if !silent {
        if !wait_browser_connected_at(running_port, 800) {
          let _ = try? open_browser("http://localhost:\{running_port}")
        }
      }
      @stdio.stdout.write("already running http://localhost:\{running_port}\n")
    }
    None =>
      try {
        log_timing("boot", "start detect_port", @async.now() - detect_started)
        let clear_started = @async.now()
        clear_stale_service_state()
        log_timing("boot", "start clear_stale", @async.now() - clear_started)
        let launch_started = @async.now()
        launch_background_service(port)
        log_timing("boot", "start launch", @async.now() - launch_started)
        let wait_started = @async.now()
        let running_port = wait_port("service did not start")
        log_timing("boot", "start wait_port", @async.now() - wait_started)
        if !silent {
          if !wait_browser_connected_at(running_port, 800) {
            let _ = try? open_browser("http://localhost:\{running_port}")
          }
        }
        @stdio.stdout.write("\{verb} http://localhost:\{running_port}\n")
      } catch {
        ServiceError(message) => fail_cli(message)
        e => fail_cli("\{e}")
      }
  }
}

async fn restart(port : Int?, silent : Bool) -> Unit {
  let running_port = if service_lock_held() {
    Some(read_service_port() catch { _ => default_port })
  } else {
    clear_stale_service_state()
    None
  }
  let target_port = match port {
    Some(v) => v
    None => match running_port {
      Some(v) => v
      None => default_port
    }
  }
  if running_port is Some(_) {
    stop()
  }
  start(target_port, silent, verb = "restarted")
}

// ======== HTTP client：命令执行和控制口调用 ========
async fn status_text(runtime: Runtime) -> String {
  let port = read_service_port() catch { _ => default_port }
  let browser = if runtime.state.browser_connected.val { "connected" } else { "waiting" }
  let roots = @src.root_instances(app_runtime.val)
  let roots_text = if roots.length() == 0 { "(none)" } else { roots.iter().join(", ") }
  "running http://localhost:\{port}\nbrowser: \{browser}\nroots: \{roots_text}\n"
}

fn default_instance_id() -> @src.InstanceRef raise {
  match @src.root_instances(app_runtime.val) {
    [root] => root
    [] => raise ServiceError("no top-level instance, use `roots ENTRY_ID...` first")
    _ => raise ServiceError("multiple top-level instances, pass INSTANCE_ID explicitly")
  }
}

fn resolve_instance_id(instance : String) -> String raise {
  let instance = instance.trim().to_string()
  if instance == "" { default_instance_id() } else { instance }
}

fn parse_root_entry_ids(text : String) -> Array[String] raise {
  let out : Array[String] = []
  for part in @src.split_shell_args(text) {
    let entry_id = part.trim().to_string()
    if entry_id == "" {
      raise ServiceError("entry id is empty")
    }
    out.push(entry_id)
  }
  out
}

fn replace_root_instances(runtime : Runtime, entry_ids : Array[String]) -> String raise {
  for root in @src.root_instances(app_runtime.val) {
    @src.close_instance(app_runtime.val, root) catch {
      err => raise ServiceError("\{err}")
    }
  }
  for entry_id in entry_ids {
    let _ = @src.boot_instance(app_runtime.val, entry_id) catch {
      err => raise ServiceError("\{err}")
    }
  }
  render_app(runtime)
  let roots = @src.root_instances(app_runtime.val)
  if roots.length() == 0 {
    "roots cleared\n"
  } else {
    let text = roots.iter().join(", ")
    "roots \{text}\n"
  }
}

fn instance_help_text(query : String) -> String raise {
  let instance = resolve_instance_id(query)
  let info = @src.query(app_runtime.val, instance) catch {
    err => raise ServiceError("\{err}")
  }
  let actions = @src.instance_actions(app_runtime.val, instance)
  if actions.length() == 0 {
    return "Instance \{info.id}\nNo actions\n"
  }
  "Instance \{info.id}\n" + @src.action_help_text(actions) + "\n"
}

fn exec_instance_action(text : String) -> String raise {
  let parts = @src.split_shell_args(text)
  if parts.length() < 2 {
    raise ServiceError("Usage: exec INSTANCE_ID ACTION [ARGS...]")
  }
  let instance = resolve_instance_id(parts[0])
  let _ = @src.query(app_runtime.val, instance) catch {
    err => raise ServiceError("\{err}")
  }
  let action = parts[1]
  let infos = @src.instance_actions(app_runtime.val, instance)
  let mut info : @src.ActionInfo? = None
  for item in infos {
    if item.id == action {
      info = Some(item)
      break
    }
  }
  let info = match info {
    Some(info) => info
    None => raise ServiceError("Unknown action: \{action}")
  }
  let tokens : Array[String] = []
  for i = 2; i < parts.length(); i = i + 1 {
    tokens.push(parts[i])
  }
  let args = @src.parse_action_args(info.args, tokens) catch { err => raise ServiceError("\{err}") }
  @src.call_instance(app_runtime.val, instance, action, args) catch {
    err => raise ServiceError("\{err}")
  }
}

async fn run(runtime: Runtime, cmd: String, rest: String) -> String raise {
  ignore(rest)
  match cmd {
    "roots" => replace_root_instances(runtime, parse_root_entry_ids(rest))
    "sync" => {
      sync_browser(runtime)
      "synced\n"
    }
    "help" => if rest.trim() == "" { help_text() } else { instance_help_text(rest) }
    "status" => status_text(runtime)
    "exec" => exec_instance_action(rest)
    _ => raise ServiceError("Unknown command: \{cmd}")
  }
}

fn repl_url(port: Int) -> String {
  "ws://127.0.0.1:\{port}\{repl_path}"
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

fn repl_request(request_id: Int, cmd: String, arg: String) -> Json {
  Json::object({
    "type": "repl:request",
    "request_id": request_id.to_json(),
    "cmd": Json::string(cmd),
    "arg": Json::string(arg),
  })
}

fn split_repl_line(line: String) -> (String, String) {
  let parts = @src.split_shell_args(line) catch { _ => return ("", "") }
  if parts.length() == 0 { return ("", "") }
  if parts.length() == 1 { return (parts[0], "") }
  let rest : Array[String] = []
  for i = 1; i < parts.length(); i = i + 1 {
    rest.push(quote_shell_arg(parts[i]))
  }
  (parts[0], rest.iter().join(" "))
}

async fn repl() -> Unit {
  try {
    let port = require_port()
    let ws = @websocket.connect(repl_url(port))
    defer ws.close()
    @stdio.stdout.write("meta repl connected ws://localhost:\{port}\{repl_path}\n")
    let mut request_id = 1
    for ;; {
      match @stdio.stdin.read_until("\n") {
        Some(line) => {
          let input = line.trim().to_string()
          if input == "" { continue }
          if input == "exit" || input == "quit" { return }
          let (cmd, arg) = split_repl_line(input)
          if cmd == "" { continue }
          ws.send_text(repl_request(request_id, cmd, arg).stringify())
          let payload = ws.recv().read_all().json()
          if !json_bool(payload, "ok").unwrap_or(false) {
            write_error(json_string(payload, "error").unwrap_or("repl request failed"))
          } else {
            match json_field(payload, "result") {
              Some(String(result)) => @stdio.stdout.write(result)
              _ => ()
            }
          }
          request_id = request_id + 1
        }
        None => return
      }
    }
  } catch {
    ServiceError(message) => fail_cli(message)
    e => fail_cli("\{e}")
  }
}

// ======== 本地 CLI 分发 ========
async fn run_client_mode(cmd: String, args: Array[String]) -> Unit {
  match cmd {
    "help" =>
      if args.length() == 0 {
        @stdio.stdout.write(help_text())
      } else {
        try {
          @stdio.stdout.write(call_service("help", join_shell_args(args)))
        } catch {
          ServiceError(message) => fail_cli(message)
          e => fail_cli("\{e}")
        }
      }
    "start" => {
      let mut port = default_port
      let mut silent = false
      for part in args {
        if part == "--silent" {
          silent = true
        } else {
          port = @string.parse_int(part) catch { _ => port }
        }
      }
      start(port, silent)
    }
    "restart" => {
      let mut port : Int? = None
      let mut silent = false
      for part in args {
        if part == "--silent" {
          silent = true
        } else {
          port = Some(@string.parse_int(part) catch { _ => default_port })
        }
      }
      restart(port, silent)
    }
    "stop" => stop()
    "repl" => repl()
    _ =>
      try {
        @stdio.stdout.write(call_service(cmd, join_shell_args(args)))
      } catch {
        ServiceError(message) => fail_cli(message)
        e => fail_cli("\{e}")
      }
  }
}

let app_runtime : Ref[@src.InstanceRuntime] = Ref::new(@src.new_instance_runtime())
let host_dom_state : Ref[@src.DomState] = Ref::new(@src.new_dom_state())
let mounted_roots : Ref[Array[@src.VNode]] = Ref::new([])

fn track_batch(runtime: Runtime, cmds: Array[String]) -> Unit {
  if !runtime.state.browser_connected.val { return }
  let batch: Array[Json] = []
  for cmd in cmds {
    batch.push(@json.parse(cmd) catch { _ => null })
  }
  let _ = runtime.live_batches.try_put(Json::array(batch)) catch { _ => false }
}

pub fn init_app(runtime: Runtime) -> Unit {
  let instance_runtime = @src.new_instance_runtime()
  @src.register_default_entries(instance_runtime, env={
    stop_service: Some(fn() { request_stop_service(runtime) }),
  })
  app_runtime.val = instance_runtime
  host_dom_state.val = @src.new_dom_state()
  mounted_roots.val = []
  @src.init_bridge(host_dom_state.val, fn(cmds) { track_batch(runtime, cmds) })
}

pub fn render_app(runtime: Runtime) -> Unit {
  ignore(runtime)
  let _ = try {
    @src.scope(fn() {
      for root in mounted_roots.val {
        @src.remove(root)
      }
      mounted_roots.val.clear()
      for root in @src.root_instances(app_runtime.val) {
        let node = @src.realize(
          host_dom_state.val,
          @src.h(@src.render_instance(app_runtime.val, root), [], []),
        )
        mounted_roots.val.push(node)
        @src.emit(host_dom_state.val, @src.Append(0, node.id))
      }
    })
  } catch {
    _ => fn() {}
  }
  @src.try_flush()
}

// ======== HTTP server：服务运行态 ========
pub async fn run_service(addr: @socket.Addr) -> Unit {
  let boot_started = @async.now()
  let lock = acquire_service_lock()
  log_timing("boot", "acquire lock", @async.now() - boot_started)
  let runtime_started = @async.now()
  let runtime = make_runtime(".")
  log_timing("boot", "make runtime", @async.now() - runtime_started)
  let init_started = @async.now()
  init_app(runtime)
  log_timing("boot", "init app", @async.now() - init_started)
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
    let bind_started = @async.now()
    let server = bind_http_server(addr, max_port_tries)
    log_timing("boot", "bind server", @async.now() - bind_started)
    let listen_addr = server.addr()
    write_service_state(current_pid(), listen_addr.port())
    if !retain_state_file(service_state_path()) {
      raise ServiceError("failed to retain service state file")
    }
    log_timing("boot", "boot total", @async.now() - boot_started)
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => flush_live_batches(runtime))
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

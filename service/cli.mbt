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
  "  query PATH [node|text] [--json]\n" +
  "           Read one browser node by ui-id path.\n" +
  "  trigger PATH focus|blur|click|dblclick|scrollIntoView [--json]\n" +
  "  trigger PATH input TEXT [--json]\n" +
  "  trigger PATH key KEY [--event press|keydown|keyup] [--code CODE]\n" +
  "           [--ctrl] [--shift] [--alt] [--meta] [--json]\n" +
  "  trigger PATH drag_to TARGET_PATH [--json]\n" +
  "           Trigger one browser DOM action by ui-id path.\n" +
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
  @socket.Addr::parse("0.0.0.0:\{port}") catch {
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
  match poll_until(async fn() {
    if (try? read_service_port() : Result[Int, _]) is Ok(port) {
      if (try? call_at(port, "status", "") : Result[String, _]) is Ok(_) { return Some(port) }
    }
    None
  }, 3000, step_ms=50) {
    Some(port) => port
    None => raise ServiceError(error_message)
  }
}

async fn wait_browser_connected_at(port: Int, timeout_ms: Int) -> Bool {
  poll_until(async fn() {
    let status = call_at(port, "status", "") catch { _ => "" }
    if status.contains("browser: connected") { Some(true) } else { None }
  }, timeout_ms, step_ms=50) is Some(_)
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
  poll_until(async fn() { if !service_lock_held() { Some(true) } else { None } }, 3000, step_ms=50) is Some(_)
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

struct QueryCommand {
  path : String
  kind : BrowserQueryRequest
  as_json : Bool
}

struct TriggerCommand {
  path : String
  kind : String
  text : String?
  key : String?
  key_event : String?
  code : String?
  ctrl_key : Bool
  shift_key : Bool
  alt_key : Bool
  meta_key : Bool
  target_path : String?
  as_json : Bool
}

fn result_json_field(json : Json, key : String) -> Json? { match json { Object(m) => m.get(key); _ => None } }
fn result_json_string(json : Json, key : String) -> String? { match result_json_field(json, key) { Some(String(v)) => Some(v); _ => None } }
fn result_json_int(json : Json, key : String) -> Int? { match result_json_field(json, key) { Some(v) => match (try? @json.from_json(v) : Result[Int, _]) { Ok(n) => Some(n); _ => None }; _ => None } }
fn result_json_bool(json : Json, key : String) -> Bool? { match result_json_field(json, key) { Some(True) => Some(true); Some(False) => Some(false); _ => None } }

fn split_json_flag(tokens : Array[String]) -> (Array[String], Bool) {
  let args : Array[String] = []
  let mut as_json = false
  for token in tokens {
    if token == "--json" {
      as_json = true
    } else {
      args.push(token)
    }
  }
  (args, as_json)
}

fn parse_query_command(rest : String) -> QueryCommand raise {
  let (args, as_json) = split_json_flag(@src.split_shell_args(rest))
  match args {
    [path] => { path, kind: Node, as_json }
    [path, "node"] => { path, kind: Node, as_json }
    [path, "text"] => { path, kind: Text, as_json }
    _ => raise ServiceError("Usage: query PATH [node|text] [--json]")
  }
}

fn parse_trigger_command(rest : String) -> TriggerCommand raise {
  let (args, as_json) = split_json_flag(@src.split_shell_args(rest))
  if args.length() < 2 {
    raise ServiceError("Usage: trigger PATH KIND ... [--json]")
  }
  let path = args[0]
  let kind = args[1]
  let mut text : String? = None
  let mut key : String? = None
  let mut key_event : String? = None
  let mut code : String? = None
  let mut ctrl_key = false
  let mut shift_key = false
  let mut alt_key = false
  let mut meta_key = false
  let mut target_path : String? = None
  match kind {
    "focus" | "blur" | "click" | "dblclick" | "scrollIntoView" => {
      if args.length() != 2 {
        raise ServiceError("Usage: trigger PATH \{kind} [--json]")
      }
    }
    "input" => {
      if args.length() != 3 {
        raise ServiceError("Usage: trigger PATH input TEXT [--json]")
      }
      text = Some(args[2])
    }
    "drag_to" => {
      if args.length() != 3 {
        raise ServiceError("Usage: trigger PATH drag_to TARGET_PATH [--json]")
      }
      target_path = Some(args[2])
    }
    "key" => {
      if args.length() < 3 {
        raise ServiceError("Usage: trigger PATH key KEY [--event press|keydown|keyup] [--code CODE] [--ctrl] [--shift] [--alt] [--meta] [--json]")
      }
      key = Some(args[2])
      key_event = Some("press")
      let mut i = 3
      while i < args.length() {
        match args[i] {
          "--event" => {
            if i + 1 >= args.length() {
              raise ServiceError("missing value for --event")
            }
            key_event = Some(args[i + 1])
            i += 2
          }
          "--code" => {
            if i + 1 >= args.length() {
              raise ServiceError("missing value for --code")
            }
            code = Some(args[i + 1])
            i += 2
          }
          "--ctrl" => { ctrl_key = true; i += 1 }
          "--shift" => { shift_key = true; i += 1 }
          "--alt" => { alt_key = true; i += 1 }
          "--meta" => { meta_key = true; i += 1 }
          _ => raise ServiceError("Unknown trigger key flag: \{args[i]}")
        }
      }
    }
    _ => raise ServiceError("Unknown trigger kind: \{kind}")
  }
  {
    path,
    kind,
    text,
    key,
    key_event,
    code,
    ctrl_key,
    shift_key,
    alt_key,
    meta_key,
    target_path,
    as_json,
  }
}

fn format_query_text(result : Json) -> String {
  match result_json_string(result, "kind") {
    Some(kind) => {
      let lines : Array[String] = []
      lines.push("kind: \{kind}")
      if result_json_int(result, "id") is Some(id) { lines.push("id: \{id}") }
      if result_json_string(result, "tag") is Some(tag) { lines.push("tag: \{tag}") }
      if result_json_string(result, "text") is Some(text) { lines.push("text: \{text}") }
      if result_json_string(result, "value") is Some(value) { lines.push("value: \{value}") }
      if result_json_bool(result, "checked") is Some(checked) { lines.push("checked: \{checked}") }
      if result_json_bool(result, "focused") is Some(focused) { lines.push("focused: \{focused}") }
      if result_json_bool(result, "visible") is Some(visible) { lines.push("visible: \{visible}") }
      lines.iter().join("\n") + "\n"
    }
    None => {
      if result_json_string(result, "text") is Some(text) {
        let id = result_json_int(result, "id").unwrap_or(0)
        "id: \{id}\ntext: \{text}\n"
      } else {
        result.stringify() + "\n"
      }
    }
  }
}

fn format_trigger_text(result : Json) -> String {
  let lines : Array[String] = []
  let ok = result_json_bool(result, "ok").unwrap_or(false)
  lines.push("ok: \{ok}")
  if result_json_string(result, "kind") is Some(kind) { lines.push("kind: \{kind}") }
  let source = result_json_field(result, "source").unwrap_or(result_json_field(result, "target").unwrap_or(null))
  if result_json_int(source, "id") is Some(id) { lines.push("id: \{id}") }
  if result_json_int(result_json_field(result, "target").unwrap_or(null), "id") is Some(target_id) &&
    result_json_string(result, "kind") == Some("drag_to") {
    lines.push("target_id: \{target_id}")
  }
  if result_json_string(result, "name") is Some(name) { lines.push("event: \{name}") }
  lines.iter().join("\n") + "\n"
}

fn format_query_result(result : Json, as_json : Bool) -> String {
  if as_json { result.stringify() + "\n" } else { format_query_text(result) }
}

fn format_trigger_result(result : Json, as_json : Bool) -> String {
  if as_json { result.stringify() + "\n" } else { format_trigger_text(result) }
}

async fn start(port: Int, silent: Bool, verb~: String = "started") -> Unit {
  start_service(port, silent, verb)
}

async fn start_service(port : Int, silent : Bool, verb : String) -> Unit {
  match time_async("start detect_port", async fn() raise { detect_port() }) {
    Some(running_port) => {
      // 这里不能收成 `if !silent && ...`，之前实测过会让 silent 路径也跑等待
      if !silent {
        if !wait_browser_connected_at(running_port, 800) {
          let _ = try? open_browser("http://localhost:\{running_port}")
        }
      }
      @stdio.stdout.write("already running http://localhost:\{running_port}\n")
    }
    None =>
      try {
        time_async("start clear_stale", async fn() { clear_stale_service_state() })
        time_async("start launch", async fn() raise { launch_background_service(port) })
        let running_port = time_async("start wait_port", async fn() raise {
          wait_port("service did not start")
        })
        // 这里不能收成 `if !silent && ...`，之前实测过会让 silent 路径也跑等待
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
fn editor_runtime(runtime : Runtime) -> @src.Runtime {
  match runtime.editor.val {
    Some(editor) => editor
    None => abort("editor runtime not initialized")
  }
}

async fn status_text(runtime: Runtime) -> String {
  let port = read_service_port() catch { _ => default_port }
  let browser = if runtime.state.browser_connected.val { "connected" } else { "waiting" }
  let roots = @src.runtime_roots(editor_runtime(runtime))
  let roots_text = if roots.length() == 0 { "(none)" } else { roots.iter().join(", ") }
  "running http://localhost:\{port}\nbrowser: \{browser}\nroots: \{roots_text}\n"
}

pub async fn run_command(runtime: Runtime, cmd: String, rest: String) -> String raise {
  match cmd {
    "query" => {
      let query = parse_query_command(rest)
      let result = request_browser_query(runtime, query.path, query.kind)
      format_query_result(result, query.as_json)
    }
    "trigger" => {
      let trigger = parse_trigger_command(rest)
      let result = request_browser_trigger(
        runtime,
        trigger.path,
        trigger.kind,
        text=trigger.text,
        key=trigger.key,
        key_event=trigger.key_event,
        code=trigger.code,
        ctrl_key=trigger.ctrl_key,
        shift_key=trigger.shift_key,
        alt_key=trigger.alt_key,
        meta_key=trigger.meta_key,
        target_path=trigger.target_path,
      )
      format_trigger_result(result, trigger.as_json)
    }
    "sync" => {
      sync_browser(runtime)
      "synced\n"
    }
    "status" => status_text(runtime)
    "help" if rest.trim() == "" => help_text()
    "help" | "roots" | "exec" =>
      @src.runtime_run(editor_runtime(runtime), cmd, rest) catch {
        err => raise ServiceError("\{err}")
      }
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
  let c : Command = try { @json.from_json(payload) } catch { _ => { cmd: None, arg: None } }
  let cmd = c.cmd.unwrap_or("")
  let arg = c.arg.unwrap_or("")
  if cmd == "stop" {
    request_stop_service(runtime)
    time_async("handle stop respond_ok", async fn() {
      respond_ok(conn, Json::string("stopped\n"))
    })
    invoke_stop_service(runtime)
    return
  }
  try {
    let result = time_async("handle run_command \{cmd}", async fn() raise {
      run_command(runtime, cmd, arg)
    })
    time_async("handle respond_ok \{cmd}", async fn() {
      respond_ok(conn, Json::string(result))
    })
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
          let payload = recv_ws_json(ws, "repl response #\{request_id}: \{cmd}", timeout_ms=3000)
          let resp : ResponseMsg = try { @json.from_json(payload) } catch { _ => { ok: None, error: None, result: None } }
          if resp.ok != Some(true) {
            write_error(resp.error.unwrap_or("repl request failed"))
          } else {
            match resp.result {
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
    "help" if args.length() == 0 => @stdio.stdout.write(help_text())
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

fn track_batch(runtime: Runtime, cmds: Array[Json]) -> Unit {
  if !runtime.state.browser_connected.val { return }
  let _ = runtime.live_batches.try_put(Json::array(cmds)) catch { _ => false }
}

fn pad2(n : Int64) -> String {
  if n < 10L { "0\{n}" } else { n.to_string() }
}

fn format_tray_time(now : Int64) -> String {
  let total = now / 1000L
  let second = total % 60L
  let minute = (total / 60L) % 60L
  let hour = (total / 3600L) % 24L
  "\{pad2(hour)}:\{pad2(minute)}:\{pad2(second)}"
}

pub fn refresh_host_tray_now(runtime : Runtime) -> Unit {
  let now = @async.now()
  let time_text = format_tray_time(now)
  let tray = @src.get_host_tray()
  let latency_text = if runtime.state.browser_connected.val { tray.latency_text } else { "--ms" }
  @src.set_host_tray(latency_text, time_text)
  @src.try_flush() // service 后台改 reactive 状态不走事件处理器，需要手动 flush 才会把增量 DOM 命令推出去
}

async fn refresh_host_tray(runtime : Runtime) -> Unit {
  for ;; {
    refresh_host_tray_now(runtime)
    @async.sleep(1000)
  }
}

pub fn init_app(runtime: Runtime) -> Unit {
  @src.reset_host_tray()
  runtime.editor.val = Some(@src.new_runtime(
    env={
    stop_service: Some(fn() { request_stop_service(runtime) }),
    },
    on_batch=cmds => track_batch(runtime, cmds),
  ))
}

// ======== HTTP server：服务运行态 ========
pub async fn run_service(addr: @socket.Addr) -> Unit {
  let boot_started = @async.now()
  let lock = time_async("acquire lock", async fn() raise { acquire_service_lock() })
  let runtime = time("make runtime", fn() { make_runtime(".") })
  time("init app", fn() { init_app(runtime) })
  let cleanup = async fn() {
    release_state_file()
    let _ = try? clear_service_state_file()
    release_service_lock(lock)
    let _ = try? clear_service_lock_file()
  }
  try {
    let server = time("bind server", fn() raise { bind_http_server(addr, max_port_tries) })
    let listen_addr = server.addr()
    write_service_state(current_pid(), listen_addr.port())
    if !retain_state_file(service_lock_path()) {
      raise ServiceError("failed to retain service lock file")
    }
    log_timing("boot", "boot total", @async.now() - boot_started)
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => flush_live_batches(runtime))
      group.spawn_bg(no_wait=true, () => refresh_host_tray(runtime))
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

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

enum CmdAction {
  Local(async (@src.CmdContext) -> Unit raise)
  Remote(async (Runtime, @src.CmdContext) -> Json raise)
}

enum OutputFormat {
  StringResult
  Query
  Trigger
  Fixed(String)
}

struct CommandWrap {
  def : @src.CmdDef[CmdAction]
  output : OutputFormat
  client_fallback : (@src.CmdContext) -> String?
}

fn CommandWrap::is_local(self: CommandWrap) -> Bool {
  match self.def.action {
    Local(_) => true
    Remote(_) => false
  }
}

fn command(
  name: String,
  desc: String,
  action: CmdAction,
  usage~ : String = "",
  flags~ : Array[@src.FlagDef] = [],
  allow_unknown~ : Bool = false,
  output~ : OutputFormat = StringResult,
  client_fallback~ : (@src.CmdContext) -> String? = _ => None,
) -> CommandWrap {
  {
    def: {
      name,
      usage,
      desc,
      flags,
      allow_unknown,
      action,
    },
    output,
    client_fallback,
  }
}

let start_flags : Array[@src.FlagDef] = [
  { name: "silent", desc: "Do not open the browser.", has_value: false },
  { name: "port", desc: "Start from port N.", has_value: true },
]

fn get_commands() -> Array[CommandWrap] {
  [
    command(
      "start",
      "Start the service.",
      Local(async fn(ctx) { start(parse_port(ctx).unwrap_or(default_port), ctx.get_bool("silent")) }),
      flags=start_flags,
    ),
    command(
      "restart",
      "Restart the service (share flag with start command).",
      Local(async fn(ctx) { restart(parse_port(ctx), ctx.get_bool("silent")) }),
      flags=start_flags,
    ),
    command(
      "status",
      "Show whether the service is running.",
      Remote(async fn(runtime, _ctx) { Json::string(status_text(runtime)) }),
    ),
    command(
      "stop",
      "Stop the service.",
      Local(async fn(_ctx) { stop() }),
    ),
    command(
      "roots",
      "Replace top-level instances.",
      Remote((runtime, ctx) => { Json::string(@src.runtime_run(editor_runtime(runtime), "roots", ctx) catch { err => raise ServiceError("\{err}") }) }),
      usage="[ENTRY_ID...]",
    ),
    command(
      "sync",
      "Wait browser bridge sync.",
      Remote(async fn(runtime, _ctx) { sync_browser(runtime); Json::string("ok") }),
      output=Fixed("synced\n"),
    ),
    command(
      "query",
      "Read one browser node by ui-id path.",
      Remote(async fn(runtime, ctx) {
        match ctx.args {
          [path, "attr", prop] => query_ui(runtime, path, "attr", value=prop).to_json()
          [path, "prop", prop] => query_ui(runtime, path, "prop", value=prop).to_json()
          [path, "style", prop] => query_ui(runtime, path, "style", value=prop).to_json()
          [path, "text"] => query_ui(runtime, path, "text").to_json()
          [path, "node"] => query_ui(runtime, path, "node").to_json()
          [path] => query_ui(runtime, path, "node").to_json()
          _ => raise ServiceError("Usage: query PATH [node|text|attr PROP|prop PROP|style PROP] [--json]")
        }
      }),
      usage="PATH [node|text|attr PROP|prop PROP|style PROP]",
      flags=[{ name: "json", desc: "Output in JSON format.", has_value: false }],
      output=Query,
    ),
    command(
      "trigger",
      "Trigger one browser DOM action.",
      Remote(async fn(runtime, ctx) {
        if ctx.args.length() < 2 { raise ServiceError("Invalid trigger arguments") }
        match ctx.args {
          [path, ("focus" | "blur" | "click" | "dblclick" | "scrollIntoView" as k)] => {
            for f in ctx.flags { if f.0 != "json" { raise ServiceError("Unknown flag for \{k}: --\{f.0}") } }
            trigger_ui(runtime, path, k).to_json()
          }
          [path, "input", t] => {
            for f in ctx.flags { if f.0 != "json" { raise ServiceError("Unknown flag for input: --\{f.0}") } }
            trigger_ui(runtime, path, "input", text=Some(t)).to_json()
          }
          [path, "drag_to", t] => {
            for f in ctx.flags { if f.0 != "json" { raise ServiceError("Unknown flag for drag_to: --\{f.0}") } }
            trigger_ui(runtime, path, "drag_to", target_path=Some(t)).to_json()
          }
          [path, "key", k] => {
            trigger_ui(
              runtime,
              path,
              "key",
              key=Some(k),
              key_event=Some(ctx.get_string("event").unwrap_or("press")),
              code=ctx.get_string("code"),
              ctrl_key=ctx.get_bool("ctrl"),
              shift_key=ctx.get_bool("shift"),
              alt_key=ctx.get_bool("alt"),
              meta_key=ctx.get_bool("meta"),
            ).to_json()
          }
          _ => raise ServiceError("Invalid trigger arguments")
        }
      }),
      usage="PATH <ACTION> [ARGS...]",
      flags=[
        { name: "event", desc: "Key event type (press|keydown|keyup)", has_value: true },
        { name: "code", desc: "Key code", has_value: true },
        { name: "ctrl", desc: "Ctrl key modifier", has_value: false },
        { name: "shift", desc: "Shift key modifier", has_value: false },
        { name: "alt", desc: "Alt key modifier", has_value: false },
        { name: "meta", desc: "Meta key modifier", has_value: false },
        { name: "json", desc: "Output in JSON format.", has_value: false },
      ],
      output=Trigger,
    ),
    command(
      "help",
      "Show service help or one instance action help.",
      Remote((runtime, ctx) => {
        if ctx.args.length() == 0 {
          Json::string(help_text())
        } else if ctx.get_bool("json") {
          let infos = @src.runtime_instance_actions(editor_runtime(runtime), ctx.args.iter().join(" ")) catch {
            err => raise ServiceError("\{err}")
          }
          Json::array(infos.map(info => @src.action_info_to_json(info)))
        } else {
          Json::string(@src.runtime_run(editor_runtime(runtime), "help", ctx) catch { err => raise ServiceError("\{err}") })
        }
      }),
      usage="[INSTANCE_ID]",
      flags=[{ name: "json", desc: "Output in JSON format.", has_value: false }],
      client_fallback=ctx => if ctx.args.length() == 0 { Some(help_text()) } else { None },
    ),
    command(
      "exec",
      "Run one instance action.",
      Remote((runtime, ctx) => {
        Json::string(@src.runtime_run(editor_runtime(runtime), "exec", ctx) catch { err => raise ServiceError("\{err}") })
      }),
      usage="INSTANCE_ID ACTION [ARGS...]",
      allow_unknown=true,
    ),
    command(
      "repl",
      "Start a long-lived command session.",
      Local(async fn(_ctx) { repl() }),
    ),
  ]
}

fn find_command(cmd: String) -> CommandWrap? {
  for c in get_commands() { if c.def.name == cmd { return Some(c) } }
  None
}

fn pad_right(s: String, len: Int) -> String {
  let mut r = s
  let pad = len - s.length()
  for i = 0; i < pad; i = i + 1 {
    r += " "
  }
  r
}

fn help_text() -> String {
  let out = StringBuilder::new()
  out.write_string("Usage:\n  meta [<command>] [<flags>]\n\nFlags:\n  --state-dir DIR  Use DIR for service state files.\n  --debug-timing   Print timing logs.\n  --port PORT      Try boot from PORT.\n\nCommands:\n")
  for c in get_commands() {
    let cmd = c.def
    let usage = if cmd.usage == "" { cmd.name } else { cmd.name + " " + cmd.usage }
    out.write_string("  " + pad_right(usage, 28) + cmd.desc + "\n")
    for flag in cmd.flags {
      let flag_str = if flag.has_value { "--\{flag.name} VAL" } else { "--\{flag.name}" }
      out.write_string("    " + pad_right(flag_str, 26) + flag.desc + "\n")
    }
  }
  out.write_string("\n")
  out.to_string()
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
      if (try? call_at(port, "status", "") : Result[Json, _]) is Ok(_) { return Some(port) }
    }
    None
  }, 3000, step_ms=50) {
    Some(port) => port
    None => raise ServiceError(error_message)
  }
}

async fn wait_browser_connected_at(port: Int, timeout_ms: Int) -> Bool {
  poll_until(async fn() {
    let status = match (try? call_at(port, "status", "") : Result[Json, _]) {
      Ok(String(text)) => text
      _ => ""
    }
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

async fn open_browser_if_needed(port: Int, silent: Bool) -> Unit {
  // 这里不能收成 `if !silent && ...`，之前实测过会让 silent 路径也跑等待
  if !silent {
    if !wait_browser_connected_at(port, 800) {
      let _ = try? open_browser("http://localhost:\{port}")
    }
  }
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

fn parse_port(ctx: @src.CmdContext) -> Int? {
  if ctx.args.length() > 0 { Some(@string.parse_int(ctx.args[0]) catch { _ => default_port }) }
  else if ctx.get_string("port") is Some(p) { Some(@string.parse_int(p) catch { _ => default_port }) }
  else { None }
}

fn format_query_text(result : Json) -> String {
  let parsed = try {
    Some((@json.from_json(result) : @src.UiQueryResult))
  } catch {
    _ => None
  }
  match parsed {
    Some(@src.UiQueryResult::Node(node)) =>
      [
        "kind: \{node.kind}",
        "id: \{node.id}",
        "tag: \{node.tag}",
        "text: \{node.text}",
        "value: \{node.value}",
        "checked: \{node.checked}",
        "focused: \{node.focused}",
        "visible: \{node.visible}",
      ].iter().join("\n") + "\n"
    Some(@src.UiQueryResult::Text(id, text)) =>
      "id: \{id}\ntext: \{text}\n"
    Some(@src.UiQueryResult::Attr(id, key, value)) =>
      "kind: attr\nid: \{id}\nkey: \{key}\nvalue: \{value}\n"
    Some(@src.UiQueryResult::Prop(id, key, value)) =>
      "kind: prop\nid: \{id}\nkey: \{key}\nvalue: \{value}\n"
    Some(@src.UiQueryResult::Style(id, key, value)) =>
      "kind: style\nid: \{id}\nkey: \{key}\nvalue: \{value}\n"
    None => result.stringify() + "\n"
  }
}

fn format_trigger_text(result : Json) -> String {
  let parsed = try {
    Some((@json.from_json(result) : @src.UiTriggerResult))
  } catch {
    _ => None
  }
  match parsed {
    Some(@src.UiTriggerResult::Pointer(id, name)) =>
      "ok: true\nkind: pointer\nid: \{id}\nevent: \{name}\n"
    Some(@src.UiTriggerResult::Input(id)) =>
      "ok: true\nkind: input\nid: \{id}\n"
    Some(@src.UiTriggerResult::Key(id, name)) =>
      "ok: true\nkind: key\nid: \{id}\nevent: \{name}\n"
    Some(@src.UiTriggerResult::DragTo(id, target_id)) =>
      "ok: true\nkind: drag_to\nid: \{id}\ntarget_id: \{target_id}\n"
    Some(@src.UiTriggerResult::Focus(id)) =>
      "ok: true\nkind: focus\nid: \{id}\n"
    Some(@src.UiTriggerResult::Blur(id)) =>
      "ok: true\nkind: blur\nid: \{id}\n"
    Some(@src.UiTriggerResult::ScrollIntoView(id)) =>
      "ok: true\nkind: scrollIntoView\nid: \{id}\n"
    None => result.stringify() + "\n"
  }
}

fn format_output(format: OutputFormat, result: Json) -> String {
  match format {
    StringResult => match result { String(s) => s; _ => result.stringify() + "\n" }
    Query => format_query_text(result)
    Trigger => format_trigger_text(result)
    Fixed(text) => text
  }
}

async fn start(port : Int, silent : Bool, verb~ : String = "started") -> Unit {
  match time_async("start detect_port", async fn() raise { detect_port() }) {
    Some(running_port) => {
      open_browser_if_needed(running_port, silent)
      @stdio.stdout.write("already running http://localhost:\{running_port}\n")
    }
    None =>
      try {
        time_async("start clear_stale", async fn() { clear_stale_service_state() })
        time_async("start launch", async fn() raise { launch_background_service(port) })
        let running_port = time_async("start wait_port", async fn() raise { wait_port("service did not start") })
        open_browser_if_needed(running_port, silent)
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
  let (c, ctx) = parse_remote_command(cmd, rest)
  let res = eval_remote_command(runtime, c, ctx)
  if ctx.get_bool("json") { res.stringify() + "\n" } else { format_output(c.output, res) }
}

fn parse_remote_command(cmd: String, rest: String) -> (CommandWrap, @src.CmdContext) raise {
  match find_command(cmd) {
    Some(c) => {
      let tokens = @src.split_shell_args(rest)
      let ctx = try { @src.parse_cmd(c.def.flags, tokens, allow_unknown=c.def.allow_unknown) } catch { err => raise ServiceError("\{err}") }
      (c, ctx)
    }
    None => raise ServiceError("Unknown command: \{cmd}")
  }
}

pub async fn eval_remote_command(
  runtime: Runtime,
  c: CommandWrap,
  ctx: @src.CmdContext,
) -> Json raise {
  match c.def.action {
    Remote(f) => f(runtime, ctx)
    Local(_) => raise ServiceError("Command \{c.def.name} is a local command and cannot be run remotely.")
  }
}

pub async fn run_command_result(runtime: Runtime, cmd: String, rest: String) -> Json raise {
  let (c, ctx) = parse_remote_command(cmd, rest)
  eval_remote_command(runtime, c, ctx)
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
      run_command_result(runtime, cmd, arg)
    })
    time_async("handle respond_ok \{cmd}", async fn() {
      respond_ok(conn, result)
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
  ({ request_id, cmd, arg } : ReplRequestOutMsg).to_json()
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
              Some(result) => @stdio.stdout.write(result.stringify() + "\n")
              None => ()
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

async fn run_client_mode(cmd: String, args: Array[String]) -> Unit {
  match find_command(cmd) {
    Some(c) => {
      try {
        if c.is_local() {
          let ctx = try { @src.parse_cmd(c.def.flags, args, allow_unknown=c.def.allow_unknown) } catch { err => raise ServiceError("\{err}") }
          match c.def.action {
            Local(f) => f(ctx)
            Remote(_) => fail_cli("Expected local command")
          }
        } else {
          let ctx = try { @src.parse_cmd(c.def.flags, args, allow_unknown=c.def.allow_unknown) } catch { err => raise ServiceError("\{err}") }
          match (c.client_fallback)(ctx) {
            Some(text) => @stdio.stdout.write(text)
            None => {
              let result = call_service(cmd, join_shell_args(args))
              if ctx.get_bool("json") {
                @stdio.stdout.write(result.stringify() + "\n")
              } else {
                @stdio.stdout.write(format_output(c.output, result))
              }
            }
          }
        }
      } catch {
        ServiceError(message) => fail_cli(message)
        e => fail_cli("\{e}")
      }
    }
    None => fail_cli("Unknown command: \{cmd}")
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
    on_cmds=cmds => @src.apply_mock_cmds(runtime.mock_browser, cmds),
  ))
  @src.runtime_render(editor_runtime(runtime))
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

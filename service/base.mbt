let nil_at: Int64 = -1L
let default_port: Int = 8080
let max_port_tries: Int = 32
let state_file_name: String = ".meta-editor-service.json"
let lock_file_name: String = ".meta-editor-service.lock"
let state_file_size: Int = 1024
let control_path: String = "/_meta/command"
let repl_path: String = "/_meta/repl"
let boot_service: String = "--internal_boot_as_service"
let debug_timing: Ref[Bool] = Ref::new(false)

suberror ServiceError {
  ServiceError(String)
} derive(Show, ToJson)

pub fn set_debug_timing(enabled: Bool) -> Unit {
  debug_timing.val = enabled
}

pub fn debug_timing_enabled() -> Bool {
  debug_timing.val
}

fn log_timing(tag: String, label: String, elapsed: Int64) -> Unit {
  if !debug_timing.val { return }
  println("[\{tag}] \{label}: \{elapsed}ms")
}

pub fn[T] time(label: String, f: () -> T raise) -> T raise {
  let start = @async.now()
  let result = f()
  log_timing("boot", label, @async.now() - start)
  result
}

pub async fn[T] time_async(label: String, f: async () -> T raise) -> T raise {
  let start = @async.now()
  let result = f()
  log_timing("boot", label, @async.now() - start)
  result
}

pub fn json_field(json: Json, key: String) -> Json? {
  match json {
    Object(m) => m.get(key)
    _ => None
  }
}

pub fn json_string(json: Json, key: String) -> String? {
  match json_field(json, key) {
    Some(String(v)) => Some(v)
    _ => None
  }
}

pub fn json_int(json: Json, key: String) -> Int? {
  match json_field(json, key) {
    Some(v) => match (try? @json.from_json(v): Result[Int, _]) {
      Ok(n) => Some(n)
      _ => None
    }
    _ => None
  }
}

pub fn json_bool(json: Json, key: String) -> Bool? {
  match json_field(json, key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

pub async fn[T] poll_until(check: async () -> T?, timeout: Int, step~: Int = 10) -> T raise {
  let max_tries = (timeout + step - 1) / step
  for tries = 0; tries < max_tries; tries = tries + 1 {
    if check() is Some(res) { return res }
    @async.sleep(step)
  }
  raise ServiceError("poll timeout")
}

pub async fn[T] wait_timeout(
  label: String,
  poll: () -> T?,
  timeout_ms~: Int = 400,
) -> T {
  poll_until(fn() { poll() }, timeout_ms, step=20)
    catch { _ => fail("timed out waiting for \{label}") }
}

pub async fn recv_ws_json(
  ws: @websocket.Conn,
  label: String,
  timeout_ms~: Int = 400,
) -> Json {
  let queue: @aqueue.Queue[Json] = @aqueue.Queue::new(kind=Unbounded)
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      let _ = queue.try_put(ws.recv().read_all().json()) catch { _ => false }
    })
    wait_timeout(label, () => queue.try_get() catch { _ => None }, timeout_ms~)
  })
}

async fn read_process_output(reader: @process.ReadFromProcess, output: StringBuilder) -> Unit {
  defer reader.close()
  while reader.read_some() is Some(chunk) {
    output.write_string(@utf8.decode(chunk))
  }
}

pub async fn run_process_collect_output_timeout(
  cmd: String,
  args: Array[String],
  timeout_ms: Int,
  label: String,
  cwd?: StringView,
) -> (Int, String) {
  @async.with_task_group(group => {
    let (reader, writer) = @process.read_from_process()
    let output = StringBuilder::new()
    let output_task = group.spawn(
      () => read_process_output(reader, output),
      no_wait=true)
    let proc = @process.spawn(
      group, cmd, args, cwd?,
      stdout=writer, stderr=writer)
    let max_tries = (timeout_ms + 19) / 20
    for tries = 0; tries < max_tries; tries = tries + 1 {
      match proc.try_wait() {
        Some(code) => {
          output_task.cancel()
          ignore(@async.with_timeout_opt(20, () => output_task.wait()) catch { _ => None })
          return (code, output.to_string())
        }
        None => @async.sleep(20)
      }
    }
    proc.cancel()
    output_task.cancel()
    ignore(@async.with_timeout_opt(20, () => output_task.wait()) catch { _ => None })
    fail("timed out waiting for \{label}")
  })
}

pub fn quote_shell_arg(arg: String) -> String {
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

pub fn join_shell_args(args: Array[String]) -> String {
  args.map(arg => quote_shell_arg(arg)).iter().join(" ")
}

// ======== 常量 ========
let nil_at : Int64 = -1L
let default_port : Int = 8080
let max_port_tries : Int = 32
let state_file_name : String = ".meta-editor-service.json"
let lock_file_name : String = ".meta-editor-service.lock"
let state_file_size : Int = 1024
let control_path : String = "/_meta/command"
let repl_path : String = "/_meta/repl"
let debug_timing : Ref[Bool] = Ref::new(false)
pub fn set_debug_timing(enabled : Bool) -> Unit {
  debug_timing.val = enabled
}
pub fn debug_timing_enabled() -> Bool {
  debug_timing.val
}
fn log_timing(tag : String, label : String, elapsed : Int64) -> Unit {
  if !debug_timing.val { return }
  println("[\{tag}] \{label}: \{elapsed}ms")
}

pub fn[T] time(label : String, f : () -> T raise) -> T raise {
  let start = @async.now()
  let result = f()
  log_timing("boot", label, @async.now() - start)
  result
}

pub async fn[T] time_async(label : String, f : async () -> T raise) -> T raise {
  let start = @async.now()
  let result = f()
  log_timing("boot", label, @async.now() - start)
  result
}

struct Runtime {
  state : ServiceState
  root_dir : String
  browser_conn : BrowserConn
  live_batches : @aqueue.Queue[Json]
  shutting_down : Ref[Bool]
  editor : Ref[@src.Runtime?]
}

struct BrowserConn {
  next_id : Ref[Int]
  next_request_id : Ref[Int]
  active_id : Ref[Int]
  ws : Ref[@websocket.Conn?]
  pending : Ref[Map[Int, @aqueue.Queue[Json]]]
}

suberror ServiceError {
  ServiceError(String)
} derive(Show, ToJson)

// ======== 运行时 ========
pub fn make_runtime(root_dir : String) -> Runtime {
  {
    state: new_state(),
    root_dir,
    browser_conn: {
      next_id: Ref::new(1),
      next_request_id: Ref::new(1),
      active_id: Ref::new(0),
      ws: Ref::new(None),
      pending: Ref::new(Map::new()),
    },
    live_batches: @aqueue.Queue::new(kind=Unbounded),
    shutting_down: Ref::new(false),
    editor: Ref::new(None),
  }
}

pub fn invoke_stop_service(_runtime : Runtime) -> Unit {
  @sys.exit(0)
}

pub fn request_stop_service(runtime : Runtime) -> Unit {
  if runtime.shutting_down.val { return }
  runtime.shutting_down.val = true
  runtime.live_batches.close(clear=true)
}

pub(all) struct Command {
  cmd : String?
  arg : String?
} derive(FromJson)

pub(all) struct ResponseMsg {
  ok : Bool?
  error : String?
  result : Json?
} derive(FromJson)

pub async fn[T] poll_until(
  check : async () -> T?,
  timeout_ms : Int,
  step_ms~ : Int = 50,
) -> T? {
  let max_tries = (timeout_ms + step_ms - 1) / step_ms
  for tries = 0; tries < max_tries; tries = tries + 1 {
    if check() is Some(res) { return Some(res) }
    @async.sleep(step_ms)
  }
  None
}

// service 侧等待统一复用这一条原语，不要再额外造新的等待 API/等待 helper
async fn[T] wait_timeout(
  label : String,
  poll : () -> T?,
  timeout_ms~ : Int = 400,
) -> T {
  match poll_until(fn() { poll() }, timeout_ms, step_ms=20) {
    Some(payload) => payload
    None => fail("timed out waiting for \{label}")
  }
}

async fn recv_ws_json(
  ws : @websocket.Conn,
  label : String,
  timeout_ms~ : Int = 400,
) -> Json {
  let queue : @aqueue.Queue[Json] = @aqueue.Queue::new(kind=Unbounded)
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      let _ = queue.try_put(ws.recv().read_all().json()) catch { _ => false }
    })
    wait_timeout(label, () => queue.try_get() catch { _ => None }, timeout_ms~)
  })
}

async fn read_process_output(reader : @process.ReadFromProcess, output : StringBuilder) -> Unit {
  defer reader.close()
  while reader.read_some() is Some(chunk) {
    output.write_string(@utf8.decode(chunk))
  }
}

async fn run_process_collect_output_timeout(
  cmd : String,
  args : Array[String],
  timeout_ms : Int,
  label : String,
  cwd? : StringView,
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

// ======== 常量 ========
let nil_at : Int64 = -1L
let default_port : Int = 8080
let max_port_tries : Int = 32
let state_file_name : String = ".meta-editor-service.json"
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

// ======== 通用 JSON 辅助 ========
fn json_field(json : Json, key : String) -> Json? {
  match json { Object(m) => m.get(key); _ => None }
}

fn json_string(json : Json, key : String) -> String? {
  match json_field(json, key) { Some(String(v)) => Some(v); _ => None }
}

fn json_int(json : Json, key : String) -> Int? {
  match json_field(json, key) {
    Some(v) =>
      match (try? @json.from_json(v) : Result[Int, _]) { Ok(n) => Some(n); _ => None }
    _ => None
  }
}

fn json_bool(json : Json, key : String) -> Bool? {
  match json_field(json, key) { Some(True) => Some(true); Some(False) => Some(false); _ => None }
}

async fn[T] wait_timeout(
  label : String,
  poll : () -> T?,
  timeout_ms? : Int = 400,
) -> T {
  let max_tries = (timeout_ms + 19) / 20
  for tries = 0; tries < max_tries; tries = tries + 1 {
    match poll() {
      Some(payload) => return payload
      None => @async.sleep(20)
    }
  }
  fail("timed out waiting for \{label}")
}

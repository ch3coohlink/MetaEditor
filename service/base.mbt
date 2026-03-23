// ======== 常量 ========
let nil_at : Int64 = -1L
let default_port : Int = 8080
let max_port_tries : Int = 32
let lock_file_name : String = ".meta-editor-service.lock"
let state_file_name : String = ".meta-editor-service.json"
let pid_file_name : String = ".meta-editor-service.pid"
let state_file_size : Int = 1024
let control_path : String = "/_meta/command"

struct Runtime {
  state : ServiceState
  root_dir : String
  next_conn_id : Ref[Int]
  active_conn_id : Ref[Int]
  browser_ws : Ref[@websocket.Conn?]
  live_batches : @aqueue.Queue[Json]
  shutting_down : Ref[Bool]
}

suberror ServiceError {
  ServiceError(String)
} derive(Show, ToJson)

// ======== 运行时 ========
pub fn make_runtime(root_dir : String) -> Runtime {
  {
    state: new_state(),
    root_dir,
    next_conn_id: Ref::new(1),
    active_conn_id: Ref::new(0),
    browser_ws: Ref::new(None),
    live_batches: @aqueue.Queue::new(kind=Unbounded),
    shutting_down: Ref::new(false),
  }
}

pub fn invoke_stop_service(_runtime : Runtime) -> Unit {
  @sys.exit(0)
}

pub fn request_stop_service(runtime : Runtime) -> Unit {
  if runtime.shutting_down.val {
    return
  }
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

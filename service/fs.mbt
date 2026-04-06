extern "C" fn temp_dir_ffi() -> String? = "metaeditor_service_get_tmp_path"
extern "C" fn current_pid_ffi() -> Int = "metaeditor_service_current_pid"
#borrow(path)
extern "C" fn retain_state_file_ffi(path : String) -> Bool = "metaeditor_service_retain_state_file"
extern "C" fn release_state_file_ffi() -> Unit = "metaeditor_service_release_state_file"

pub(all) struct ServiceLock {
  file : @fs.File
}

struct ServiceStateFile {
  pid : Int
  port : Int
}

let state_dir_ref : Ref[String] = Ref::new(temp_dir())

pub fn temp_dir() -> String {
  match temp_dir_ffi() {
    Some(path) => path
    None => abort("failed to get temp dir")
  }
}

pub fn state_dir() -> String {
  state_dir_ref.val
}

pub async fn set_state_dir(dir : String) -> Unit {
  @fs.mkdir(dir, permission=0o755, recursive=true) catch { _ => () }
  state_dir_ref.val = dir
}

pub fn current_pid() -> Int {
  current_pid_ffi()
}

pub fn retain_state_file(path : String) -> Bool {
  retain_state_file_ffi(path)
}

pub fn release_state_file() -> Unit {
  release_state_file_ffi()
}

pub fn state_path(name : String) -> String {
  let dir = state_dir()
  match dir {
    [.., .. "/"] | [.., .. "\\"] => "\{dir}\{name}"
    _ => "\{dir}/\{name}"
  }
}

pub fn service_state_path() -> String { state_path(state_file_name) }
pub fn service_lock_path() -> String { state_path(lock_file_name) }

pub async fn try_acquire_service_lock() -> ServiceLock? raise {
  let file = @fs.open(service_lock_path(), mode=ReadWrite, create=0o644)
  let locked = file.try_lock(Exclusive)
  if !locked {
    file.close()
    return None
  }
  Some({ file: file })
}

pub async fn acquire_service_lock() -> ServiceLock raise {
  match try_acquire_service_lock() {
    Some(lock) => lock
    None => raise ServiceError("service already running")
  }
}

pub fn release_service_lock(lock : ServiceLock) -> Unit {
  lock.file.unlock()
  lock.file.close()
}

pub async fn write_service_state(pid : Int, port : Int) -> Unit {
  let text = Json::object({
    "pid": pid.to_json(),
    "port": port.to_json(),
  }).stringify()
  let padded = if text.length() < state_file_size {
    text + " ".repeat(state_file_size - text.length())
  } else {
    text
  }
  @fs.write_file(service_state_path(), @utf8.encode(padded), create=0o644, truncate=true)
}

pub async fn clear_service_state_file() -> Unit {
  let path = service_state_path()
  if @fs.exists(path) {
    @fs.remove(path)
  }
}

pub async fn clear_service_lock_file() -> Unit {
  let path = service_lock_path()
  if @fs.exists(path) {
    @fs.remove(path)
  }
}

fn parse_service_state_text(text : String) -> ServiceStateFile raise {
  let state = @json.parse(text.trim())
  match (json_int(state, "pid"), json_int(state, "port")) {
    (Some(pid), Some(port)) => { pid, port }
    _ => raise ServiceError("invalid service state file")
  }
}

pub fn parse_service_port_text(text : String) -> Int raise {
  parse_service_state_text(text).port
}

pub fn parse_service_pid_text(text : String) -> Int raise {
  parse_service_state_text(text).pid
}

pub async fn read_service_port() -> Int raise {
  let path = service_state_path()
  if !@fs.exists(path) {
    raise ServiceError("service is not running")
  }
  parse_service_port_text(@fs.read_file(path).text())
}

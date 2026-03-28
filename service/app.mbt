let projects : @src.Cel[Array[AppProject]] = @src.cel([])
let instances : @src.Cel[Array[AppInstance]] = @src.cel([])
let app_loaded : Ref[Bool] = Ref::new(false)
let next_instance_id : Ref[Int] = Ref::new(1)

pub(all) struct AppProject {
  id : String
  name : String
  path : String?
} derive(Eq, Hash, Show)

pub(all) enum AppStatus {
  Starting
  Running
  Stopped
  Failed
} derive(Eq, Hash, Show)

pub(all) struct AppInstance {
  id : String
  project_id : String
  status : AppStatus
} derive(Eq, Hash, Show)

fn track_batch(runtime: Runtime, cmds: Array[String]) -> Unit {
  let batch: Array[Json] = []
  for cmd in cmds {
    batch.push(@json.parse(cmd) catch { _ => null })
  }
  let _ = runtime.live_batches.try_put(Json::array(batch)) catch { _ => false }
}

fn app_status_text(status : AppStatus) -> String {
  match status {
    Starting => "starting"
    Running => "running"
    Stopped => "stopped"
    Failed => "failed"
  }
}

fn app_json_field(json : Json, key : String) -> Json? {
  match json {
    Object(m) => m.get(key)
    _ => None
  }
}

fn project_from_json(json : Json) -> AppProject? {
  let id = match app_json_field(json, "id") {
    Some(String(v)) => v
    _ => return None
  }
  let name = match app_json_field(json, "name") {
    Some(String(v)) => v
    _ => return None
  }
  let path = match app_json_field(json, "path") {
    Some(String(v)) => Some(v)
    _ => None
  }
  Some({ id, name, path })
}

fn ensure_loaded() -> Unit {
  if app_loaded.val { return }
  app_loaded.val = true
  projects.set([])
}

fn default_path_text(project : AppProject) -> String {
  match project.path {
    Some(path) => path
    None => "(public app path)"
  }
}

fn project_text(project : AppProject) -> String {
  "\{project.id}  \{project.name}  \{default_path_text(project)}"
}

fn instance_text(instance : AppInstance) -> String {
  "\{instance.id}  \{instance.project_id}  \{app_status_text(instance.status)}"
}

fn list_projects_text() -> String {
  let items = projects.peek()
  if items.length() == 0 { return "projects: 0\n" }
  let lines : Array[String] = ["projects: \{items.length()}"]
  for project in items {
    lines.push(project_text(project))
  }
  lines.iter().join("\n") + "\n"
}

fn list_instances_text() -> String {
  let items = instances.peek()
  if items.length() == 0 { return "instances: 0\n" }
  let lines : Array[String] = ["instances: \{items.length()}"]
  for instance in items {
    lines.push(instance_text(instance))
  }
  lines.iter().join("\n") + "\n"
}

fn find_project(id : String) -> AppProject? {
  for project in projects.peek() {
    if project.id == id { return Some(project) }
  }
  None
}

fn[T] find_in(items : Array[T], pred : (T) -> Bool) -> T? {
  for item in items {
    if pred(item) { return Some(item) }
  }
  None
}

fn[T] keyed_items(items : Array[T], key : (T) -> String) -> Array[(String, Int)] {
  let out : Array[(String, Int)] = []
  for i = 0; i < items.length(); i = i + 1 {
    out.push((key(items[i]), i))
  }
  out
}

fn current_project(id : String) -> AppProject? {
  find_in(projects.get(), v => v.id == id)
}

fn current_instance(id : String) -> AppInstance? {
  find_in(instances.get(), v => v.id == id)
}

fn[T] update_items(
  items : Array[T],
  pred : (T) -> Bool,
  f : (Array[T], Int) -> String?
) -> String? {
  let next = items.copy()
  for i = 0; i < next.length(); i = i + 1 {
    if pred(next[i]) { return f(next, i) }
  }
  None
}

fn project_items() -> Array[(String, Int)] {
  keyed_items(projects.get(), v => v.id)
}

fn instance_items() -> Array[(String, Int)] {
  keyed_items(instances.get(), v => v.id)
}

fn add_project(arg : String) -> String raise {
  let payload = @json.parse(arg)
  let project = match project_from_json(payload) {
    Some(project) => project
    None => raise ServiceError("add_project expects JSON with id/name/path?")
  }
  match update_items(projects.peek(), v => v.id == project.id, (next, i) => {
    next[i] = project
    projects.set(next)
    Some("updated project \{project.id}\n")
  }) {
    Some(out) => out
    None => {
      let next = projects.peek().copy()
      next.push(project)
      projects.set(next)
      "added project \{project.id}\n"
    }
  }
}

fn remove_project(arg : String) -> String raise {
  let id = arg.trim().to_string()
  if id == "" { raise ServiceError("remove_project expects project id") }
  let next : Array[AppProject] = []
  let mut removed = false
  for project in projects.peek() {
    if project.id == id {
      removed = true
    } else {
      next.push(project)
    }
  }
  if !removed { raise ServiceError("project not found: \{id}") }
  projects.set(next)
  let kept : Array[AppInstance] = []
  for instance in instances.peek() {
    if instance.project_id != id { kept.push(instance) }
  }
  instances.set(kept)
  "removed project \{id}\n"
}

fn run_project(arg : String) -> String raise {
  let project_id = arg.trim().to_string()
  if project_id == "" { raise ServiceError("run_project expects project id") }
  if find_project(project_id) is None {
    raise ServiceError("project not found: \{project_id}")
  }
  let id = next_instance_id.val.to_string()
  next_instance_id.val = next_instance_id.val + 1
  let next = instances.peek().copy()
  next.push({ id, project_id, status: Running })
  instances.set(next)
  "started instance \{id} for \{project_id}\n"
}

fn stop_instance(arg : String) -> String raise {
  let id = arg.trim().to_string()
  if id == "" { raise ServiceError("stop_instance expects instance id") }
  match update_items(instances.peek(), v => v.id == id, (next, i) => {
      next[i] = {
        id: next[i].id,
        project_id: next[i].project_id,
        status: Stopped,
      }
      instances.set(next)
      Some("stopped instance \{id}\n")
    }) {
    Some(out) => out
    None => raise ServiceError("instance not found: \{id}")
  }
}

fn project_item(id : String) -> @src.Child {
  let run = @src.reg_action("run_project \{id}", fn() {
    ignore(run_project(id) catch { _ => "" })
  })
  let remove = @src.reg_action("remove_project \{id}", fn() {
    ignore(remove_project(id) catch { _ => "" })
  })
  @src.Dyn(fn() {
    match current_project(id) {
      Some(project) =>
        @src.h("div", [
          ("style", @src.S("padding: 12px 0; border-bottom: 1px solid #ddd;")),
          ("data-testid", @src.S("project-row-\{id}"))
        ], [
          @src.h("div", [("style", @src.S("font-weight: 600;"))], [@src.Str(project.name)]),
          @src.h("div", [("style", @src.S("color: #666; font-size: 13px; margin-top: 4px;"))], [
            @src.Str("\{project.id}  \{default_path_text(project)}")
          ]),
          @src.h("div", [("style", @src.S("margin-top: 10px; display: flex; gap: 8px;"))], [
            @src.h("button", [
              ("onclick", run),
              ("data-testid", @src.S("project-run-\{id}")),
              ("style", @src.S("padding: 8px 12px; border: none; border-radius: 8px; background: #0f766e; color: white; cursor: pointer;"))
            ], [@src.Str("Run")]),
            @src.h("button", [
              ("onclick", remove),
              ("data-testid", @src.S("project-remove-\{id}")),
              ("style", @src.S("padding: 8px 12px; border: none; border-radius: 8px; background: #b42318; color: white; cursor: pointer;"))
            ], [@src.Str("Remove")])
          ])
        ])
      None => @src.Null
    }
  })
}

fn instance_item(id : String) -> @src.Child {
  let stop = @src.reg_action("stop_instance \{id}", fn() {
    ignore(stop_instance(id) catch { _ => "" })
  })
  @src.Dyn(fn() {
    match current_instance(id) {
      Some(instance) =>
        @src.h("div", [
          ("style", @src.S("padding: 10px 0; border-bottom: 1px solid #ddd;")),
          ("data-testid", @src.S("instance-row-\{id}"))
        ], [
          @src.h("div", [("style", @src.S("font-weight: 600;"))], [
            @src.Str("Instance \{instance.id}")
          ]),
          @src.h("div", [("style", @src.S("color: #666; font-size: 13px; margin-top: 4px;"))], [
            @src.Str("\{instance.project_id}  \{app_status_text(instance.status)}")
          ]),
          @src.h("div", [("style", @src.S("margin-top: 10px; display: flex; gap: 8px;"))], [
            @src.h("button", [
              ("onclick", stop),
              ("data-testid", @src.S("instance-stop-\{id}")),
              ("style", @src.S("padding: 8px 12px; border: none; border-radius: 8px; background: #7a1c1c; color: white; cursor: pointer;"))
            ], [@src.Str("Stop")])
          ])
        ])
      None => @src.Null
    }
  })
}

fn render_host_app(runtime: Runtime) -> @src.Child {
  let stop_service = @src.reg_action("host_stop_service", fn() { request_stop_service(runtime) })
  @src.h("div", [
    ("style", @src.S("padding: 24px; font-family: sans-serif;")),
    ("data-testid", @src.S("host-root"))
  ], [
    @src.h("h1", [], [@src.Str("MetaEditor Host")]),
    @src.h("div", [("style", @src.S("margin-bottom: 16px; color: #555;"))], [
      @src.Str("Managed app skeleton is running in host app.")
    ]),
    @src.h("button", [
      ("onclick", stop_service),
      ("data-testid", @src.S("host-stop-service")),
      ("style", @src.S("padding: 10px 14px; background: #b42318; color: white; border: none; border-radius: 8px; cursor: pointer;"))
    ], [@src.Str("Stop Service")]),
    @src.h("div", [
      ("style", @src.S("margin-top: 28px;")),
      ("data-testid", @src.S("projects-section"))
    ], [
      @src.h("h2", [], [@src.Str("Projects")]),
      @src.Dyn(fn() {
        if projects.get().length() == 0 {
          @src.h("div", [("style", @src.S("color: #666;"))], [
            @src.Str("No managed app projects yet. Use add_project from CLI first.")
          ])
        } else {
          @src.Null
        }
      }),
      @src.h_map_dyn(project_items, (v, _) => project_item(v))
    ]),
    @src.h("div", [
      ("style", @src.S("margin-top: 28px;")),
      ("data-testid", @src.S("instances-section"))
    ], [
      @src.h("h2", [], [@src.Str("Instances")]),
      @src.Dyn(fn() {
        if instances.get().length() == 0 {
          @src.h("div", [("style", @src.S("color: #666;"))], [
            @src.Str("No running instances.")
          ])
        } else {
          @src.Null
        }
      }),
      @src.h_map_dyn(instance_items, (v, _) => instance_item(v))
    ])
  ])
}

pub fn init_app(runtime: Runtime) -> Unit {
  ensure_loaded()
  @src.init_bridge(fn(cmds) { track_batch(runtime, cmds) })
}

pub fn render_app(runtime: Runtime) -> Unit {
  let _ = try {
    @src.scope(fn() {
      let root = @src.realize(@src.h("div", [], [render_host_app(runtime)]))
      @src.emit(@src.Append(0, root.id))
    })
  } catch {
    _ => fn() {}
  }
  @src.try_flush()
}

pub async fn host_stop_service(runtime: Runtime, settle_ms: Int) -> String {
  request_stop_service(runtime)
  @async.sleep(settle_ms)
  "host_stop_service\n"
}

pub async fn run_app(runtime : Runtime, cmd : String, arg : String) -> String raise {
  ensure_loaded()
  let out = match cmd {
    "host_stop_service" => host_stop_service(runtime, 50)
    "list_projects" => list_projects_text()
    "add_project" => add_project(arg)
    "remove_project" => remove_project(arg)
    "list_instances" => list_instances_text()
    "run_project" => run_project(arg)
    "stop_instance" => stop_instance(arg)
    "test_query" => (query_browser(runtime, @json.parse(arg))).stringify()
    "test_exec" => {
      let result = exec_browser(runtime, @json.parse(arg))
      sync_browser_if_connected(runtime)
      result.stringify()
    }
    _ => raise ServiceError("Unknown command: \{cmd}")
  }
  @src.try_flush()
  match cmd {
    "add_project" | "remove_project" | "run_project" | "stop_instance" =>
      sync_browser_if_connected(runtime)
    _ => ()
  }
  out
}

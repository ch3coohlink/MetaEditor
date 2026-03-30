let entries : @src.Cel[Array[AppEntry]] = @src.cel([])
let instances : @src.Cel[Array[AppInstance]] = @src.cel([])
let next_instance_id : Ref[Int] = Ref::new(1)
let host_dom_state : Ref[@src.DomState] = Ref::new(@src.new_dom_state())

pub(all) struct AppEntry {
  id : String
  name : String
  view : () -> @src.Comp
}

pub(all) enum AppStatus {
  Starting
  Running
  Stopped
  Failed
} derive(Eq, Hash, Show)

pub(all) struct AppInstance {
  id : String
  entry_id : String
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

fn register_app_entry(entry : AppEntry) -> Unit {
  let next = entries.peek().copy()
  for v in next {
    if v.id == entry.id { return }
  }
  next.push(entry)
  entries.set(next)
}

fn register_builtin_app_entries() -> Unit {
  let demo = @src.demo_editor()
  let demo_data = @src.cel(demo.data)
  let demo_session = @src.cel(demo.session)
  register_app_entry({
    id: demo.id,
    name: demo.name.unwrap_or(demo.id),
    view: fn() { (demo.view)(demo_data, demo_session) },
  })
  let demo_host = @src.demo_host_editor()
  let demo_host_data = @src.cel(demo_host.data)
  let demo_host_session = @src.cel(demo_host.session)
  register_app_entry({
    id: demo_host.id,
    name: demo_host.name.unwrap_or(demo_host.id),
    view: fn() { (demo_host.view)(demo_host_data, demo_host_session) },
  })
}

fn init_app_state() -> Unit {
  entries.set([])
  instances.set([])
  next_instance_id.val = 1
}

fn entry_text(entry : AppEntry) -> String {
  "\{entry.id}  \{entry.name}"
}

fn instance_text(instance : AppInstance) -> String {
  "\{instance.id}  \{instance.entry_id}  \{app_status_text(instance.status)}"
}

fn list_entries_text() -> String {
  let items = entries.peek()
  if items.length() == 0 { return "entries: 0\n" }
  let lines : Array[String] = ["entries: \{items.length()}"]
  for entry in items {
    lines.push(entry_text(entry))
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

fn find_entry(id : String) -> AppEntry? {
  for entry in entries.peek() {
    if entry.id == id { return Some(entry) }
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

fn current_entry(id : String) -> AppEntry? {
  find_in(entries.get(), v => v.id == id)
}

fn current_instance(id : String) -> AppInstance? {
  find_in(instances.get(), v => v.id == id)
}

fn active_instance() -> AppInstance? {
  let items = instances.get()
  for i = items.length() - 1; i >= 0; i = i - 1 {
    let item = items[i]
    if item.status == Running { return Some(item) }
  }
  None
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

fn entry_items() -> Array[(String, Int)] {
  keyed_items(entries.get(), v => v.id)
}

fn instance_items() -> Array[(String, Int)] {
  keyed_items(instances.get(), v => v.id)
}

fn start_instance(arg : String) -> String raise {
  let entry_id = arg.trim().to_string()
  if entry_id == "" { raise ServiceError("start_instance expects entry id") }
  if find_entry(entry_id) is None {
    raise ServiceError("entry not found: \{entry_id}")
  }
  let id = next_instance_id.val.to_string()
  next_instance_id.val = next_instance_id.val + 1
  let next = instances.peek().copy()
  next.push({ id, entry_id, status: Running })
  instances.set(next)
  "started instance \{id} for \{entry_id}\n"
}

fn stop_instance(arg : String) -> String raise {
  let id = arg.trim().to_string()
  if id == "" { raise ServiceError("stop_instance expects instance id") }
  match update_items(instances.peek(), v => v.id == id, (next, i) => {
      next[i] = {
        id: next[i].id,
        entry_id: next[i].entry_id,
        status: Stopped,
      }
      instances.set(next)
      Some("stopped instance \{id}\n")
    }) {
    Some(out) => out
    None => raise ServiceError("instance not found: \{id}")
  }
}

fn entry_item(id : String) -> @src.Child {
  let start = @src.reg_action("start_instance \{id}", fn() {
    ignore(start_instance(id) catch { _ => "" })
  })
  @src.Dyn(fn() {
    match current_entry(id) {
      Some(entry) =>
        @src.h("div", [
          ("style", @src.S("padding: 12px 0; border-bottom: 1px solid #ddd;")),
          ("data-testid", @src.S("entry-row-\{id}"))
        ], [
          @src.h("div", [("style", @src.S("font-weight: 600;"))], [@src.Str(entry.name)]),
          @src.h("div", [("style", @src.S("color: #666; font-size: 13px; margin-top: 4px;"))], [
            @src.Str("\{entry.id}")
          ]),
          @src.h("div", [("style", @src.S("margin-top: 10px; display: flex; gap: 8px;"))], [
            @src.h("button", [
              ("onclick", start),
              ("data-testid", @src.S("entry-start-\{id}")),
              ("style", @src.S("padding: 8px 12px; border: none; border-radius: 8px; background: #0f766e; color: white; cursor: pointer;"))
            ], [@src.Str("Start")])
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
            @src.Str("\{instance.entry_id}  \{app_status_text(instance.status)}")
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

fn active_app_panel() -> @src.Child {
  @src.Dyn(fn() {
    match active_instance() {
      Some(instance) =>
        match find_entry(instance.entry_id) {
          Some(entry) =>
            @src.h("div", [
              ("data-testid", @src.S("active-app-panel")),
              ("style", @src.S("margin-top: 16px; border: 1px solid #ddd; border-radius: 12px; background: white; overflow: hidden;"))
            ], [
              @src.h("div", [
                ("style", @src.S("padding: 10px 14px; border-bottom: 1px solid #eee; background: #f8f8f8;"))
              ], [
                @src.h("div", [("style", @src.S("font-weight: 600;"))], [@src.Str(entry.name)]),
                @src.h("div", [("style", @src.S("font-size: 12px; color: #666; margin-top: 2px;"))], [
                  @src.Str("Instance \{instance.id}  \{entry.id}")
                ])
              ]),
              @src.h("div", [("style", @src.S("min-height: 240px;"))], [
                @src.h((entry.view)(), [], [])
              ])
            ])
          None => @src.Null
        }
      None =>
        @src.h("div", [
          ("data-testid", @src.S("active-app-empty")),
          ("style", @src.S("margin-top: 16px; padding: 24px; border: 1px dashed #ccc; border-radius: 12px; color: #666; background: white;"))
        ], [
          @src.Str("Start an entry to show its app UI here.")
        ])
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
      ("data-testid", @src.S("active-app-section"))
    ], [
      @src.h("h2", [], [@src.Str("Current App")]),
      active_app_panel()
    ]),
    @src.h("div", [
      ("style", @src.S("margin-top: 28px;")),
      ("data-testid", @src.S("entries-section"))
    ], [
      @src.h("h2", [], [@src.Str("Entries")]),
      @src.Dyn(fn() {
        if entries.get().length() == 0 {
          @src.h("div", [("style", @src.S("color: #666;"))], [
            @src.Str("No app entries registered.")
          ])
        } else {
          @src.Null
        }
      }),
      @src.h_map_dyn(entry_items, (v, _) => entry_item(v))
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
  init_app_state()
  // register_builtin_app_entries()
  host_dom_state.val = @src.new_dom_state()
  @src.init_bridge(host_dom_state.val, fn(cmds) { track_batch(runtime, cmds) })
}

pub fn render_app(runtime: Runtime) -> Unit {
  let _ = try {
    @src.scope(fn() {
      let root = @src.realize(host_dom_state.val, @src.h("div", [], [render_host_app(runtime)]))
      @src.emit(host_dom_state.val, @src.Append(0, root.id))
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
  let out = match cmd {
    "host_stop_service" => host_stop_service(runtime, 50)
    "list_entries" => list_entries_text()
    "list_instances" => list_instances_text()
    "start_instance" => start_instance(arg)
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
    "start_instance" | "stop_instance" =>
      sync_browser_if_connected(runtime)
    _ => ()
  }
  out
}

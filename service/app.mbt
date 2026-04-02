let entries : @src.Cel[Array[AppEntry]] = @src.cel([])
let windows : @src.Cel[Array[AppWindow]] = @src.cel([])
let z_order : @src.Cel[Array[String]] = @src.cel([])
let selected_entry_id : @src.Cel[String?] = @src.cel(None)
let next_window_id : Ref[Int] = Ref::new(1)
let host_dom_state : Ref[@src.DomState] = Ref::new(@src.new_dom_state())

pub(all) struct WindowSeed {
  title : String
  view : @src.Comp
}

pub(all) struct AppEntry {
  id : String
  name : String
  icon_label : String
  create : () -> WindowSeed
}

pub(all) struct WindowFrame {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Hash, Show)

pub(all) struct AppWindow {
  id : String
  entry_id : String
  title : String
  frame : WindowFrame
  view : @src.Comp
}

fn track_batch(runtime: Runtime, cmds: Array[String]) -> Unit {
  let batch: Array[Json] = []
  for cmd in cmds {
    batch.push(@json.parse(cmd) catch { _ => null })
  }
  let _ = runtime.live_batches.try_put(Json::array(batch)) catch { _ => false }
}

fn[D, S] register_editor_entry(editor : @src.Editor[D, S]) -> Unit {
  let next = entries.peek().copy()
  for item in next {
    if item.id == editor.id { return }
  }
  let name = editor.name.unwrap_or(editor.id)
  next.push({
    id: editor.id,
    name,
    icon_label: editor.icon.unwrap_or(name),
    create: fn() {
      let data = @src.cel((editor.new_data)())
      let session = @src.cel((editor.new_session)())
      {
        title: name,
        view: (editor.view)(data, session),
      }
    },
  })
  entries.set(next)
}

fn register_builtin_app_entries() -> Unit {
  register_editor_entry(@src.demo_editor())
  register_editor_entry(@src.demo_host_editor())
}

fn init_app_state() -> Unit {
  entries.set([])
  windows.set([])
  z_order.set([])
  selected_entry_id.set(None)
  next_window_id.val = 1
}

fn entry_text(entry : AppEntry) -> String {
  "\{entry.id}  \{entry.name}"
}

fn window_text(window : AppWindow) -> String {
  "\{window.id}  \{window.entry_id}  \{window.title}"
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

fn list_windows_text() -> String {
  let order = z_order.peek()
  if order.length() == 0 { return "windows: 0\n" }
  let lines : Array[String] = ["windows: \{order.length()}"]
  for id in order {
    match current_window(id) {
      Some(window) => lines.push(window_text(window))
      None => ()
    }
  }
  lines.iter().join("\n") + "\n"
}

fn find_entry(id : String) -> AppEntry? {
  for entry in entries.get() {
    if entry.id == id { return Some(entry) }
  }
  None
}

fn find_window(id : String) -> AppWindow? {
  for window in windows.get() {
    if window.id == id { return Some(window) }
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
  find_entry(id)
}

fn current_window(id : String) -> AppWindow? {
  find_window(id)
}

fn entry_items() -> Array[(String, Int)] {
  keyed_items(entries.get(), v => v.id)
}

fn window_ids() -> Array[(String, Int)] {
  keyed_items(z_order.get(), v => v)
}

fn bring_to_front(items : Array[String], id : String) -> Array[String] {
  let next : Array[String] = []
  for item in items {
    if item != id {
      next.push(item)
    }
  }
  next.push(id)
  next
}

fn remove_from_order(items : Array[String], id : String) -> Array[String] {
  let next : Array[String] = []
  for item in items {
    if item != id {
      next.push(item)
    }
  }
  next
}

fn current_focus_id() -> String? {
  let order = z_order.get()
  if order.length() == 0 { return None }
  Some(order[order.length() - 1])
}

fn is_selected_entry(id : String) -> Bool {
  match selected_entry_id.get() {
    Some(current) => current == id
    None => false
  }
}

fn is_focused_window(id : String) -> Bool {
  match current_focus_id() {
    Some(current) => current == id
    None => false
  }
}

fn window_z_index(id : String) -> Int {
  let order = z_order.get()
  for i = 0; i < order.length(); i = i + 1 {
    if order[i] == id {
      return 100 + i
    }
  }
  100
}

fn default_window_frame(serial : Int) -> WindowFrame {
  let slot = (serial - 1) % 6
  {
    x: 36 + slot * 28,
    y: 36 + slot * 24,
    width: 420,
    height: 320,
  }
}

fn open_window(arg : String) -> String raise {
  let entry_id = arg.trim().to_string()
  if entry_id == "" { raise ServiceError("open_window expects entry id") }
  let entry = match find_entry(entry_id) {
    Some(entry) => entry
    None => raise ServiceError("entry not found: \{entry_id}")
  }
  let serial = next_window_id.val
  next_window_id.val = serial + 1
  let id = serial.to_string()
  let seed = (entry.create)()
  let next = windows.peek().copy()
  next.push({
    id,
    entry_id,
    title: seed.title,
    frame: default_window_frame(serial),
    view: seed.view,
  })
  windows.set(next)
  z_order.set(bring_to_front(z_order.peek(), id))
  selected_entry_id.set(Some(entry_id))
  "opened window \{id} for \{entry_id}\n"
}

fn focus_window(arg : String) -> String raise {
  let id = arg.trim().to_string()
  if id == "" { raise ServiceError("focus_window expects window id") }
  if current_window(id) is None {
    raise ServiceError("window not found: \{id}")
  }
  z_order.set(bring_to_front(z_order.peek(), id))
  "focused window \{id}\n"
}

fn close_window(arg : String) -> String raise {
  let id = arg.trim().to_string()
  if id == "" { raise ServiceError("close_window expects window id") }
  if current_window(id) is None {
    raise ServiceError("window not found: \{id}")
  }
  let next : Array[AppWindow] = []
  let mut closed_entry : String? = None
  for window in windows.peek() {
    if window.id == id {
      closed_entry = Some(window.entry_id)
    } else {
      next.push(window)
    }
  }
  windows.set(next)
  z_order.set(remove_from_order(z_order.peek(), id))
  match closed_entry {
    Some(entry_id) => selected_entry_id.set(Some(entry_id))
    None => ()
  }
  "closed window \{id}\n"
}

fn select_entry(id : String) -> Unit {
  selected_entry_id.set(Some(id))
}

fn desktop_entry_item(id : String) -> @src.Child {
  let select = @src.reg_action("select_entry \{id}", fn() { select_entry(id) })
  let open = @src.reg_action("open_window \{id}", fn() {
    ignore(open_window(id) catch { _ => "" })
  })
  @src.Dyn(fn() {
    match current_entry(id) {
      Some(entry) => {
        let accent = if is_selected_entry(id) { "#d7ebff" } else { "rgba(255, 255, 255, 0.20)" }
        let border = if is_selected_entry(id) { "#6aa7ff" } else { "rgba(255, 255, 255, 0.18)" }
        @src.h("div", [
          ("ui-id", @src.S("entry:\{id}")),
          ("onclick", select),
          ("ondblclick", open),
          ("style", @src.S(
            "width: 112px; padding: 10px 8px; border-radius: 14px; border: 1px solid \{border}; " +
            "background: \{accent}; color: white; display: flex; flex-direction: column; " +
            "align-items: center; gap: 8px; cursor: default; user-select: none;"
          ))
        ], [
          @src.h("div", [
            ("style", @src.S(
              "width: 52px; height: 52px; border-radius: 16px; background: rgba(255, 255, 255, 0.16); " +
              "display: flex; align-items: center; justify-content: center; font-size: 13px; " +
              "font-weight: 700; letter-spacing: 0.08em;"
            ))
          ], [@src.Str(entry.icon_label)]),
          @src.h("div", [
            ("style", @src.S(
              "font-size: 13px; text-align: center; line-height: 1.35; text-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);"
            ))
          ], [@src.Str(entry.name)])
        ])
      }
      None => @src.Null
    }
  })
}

fn topbar_window_item(id : String) -> @src.Child {
  let focus = @src.reg_action("focus_window \{id}", fn() {
    ignore(focus_window(id) catch { _ => "" })
  })
  @src.Dyn(fn() {
    match current_window(id) {
      Some(window) => {
        let background = if is_focused_window(id) { "#f5f9ff" } else { "rgba(255, 255, 255, 0.72)" }
        let color = if is_focused_window(id) { "#173055" } else { "#384458" }
        @src.h("button", [
          ("ui-id", @src.S("topbar-window:\{id}")),
          ("onclick", focus),
          ("style", @src.S(
            "padding: 7px 12px; border: 1px solid rgba(16, 24, 40, 0.08); border-radius: 999px; " +
            "background: \{background}; color: \{color}; cursor: pointer; font-size: 12px;"
          ))
        ], [@src.Str(window.title)])
      }
      None => @src.Null
    }
  })
}

fn desktop_layer() -> @src.Child {
  @src.h("div", [
    ("ui-id", @src.S("desktop-root")),
    ("style", @src.S(
      "position: absolute; inset: 0; padding: 24px; display: flex; flex-wrap: wrap; " +
      "align-content: flex-start; gap: 18px;"
    ))
  ], [
    @src.h_map_dyn(entry_items, (v, _) => desktop_entry_item(v))
  ])
}

fn window_item(id : String) -> @src.Child {
  let focus = @src.reg_action("focus_window \{id}", fn() {
    ignore(focus_window(id) catch { _ => "" })
  })
  let close = @src.reg_action("close_window \{id}", fn() {
    ignore(close_window(id) catch { _ => "" })
  })
  @src.Dyn(fn() {
    match current_window(id) {
      Some(window) => {
        let border = if is_focused_window(id) { "#5c8dff" } else { "#c8d1e0" }
        let shadow = if is_focused_window(id) {
          "0 18px 40px rgba(11, 18, 30, 0.26)"
        } else {
          "0 14px 28px rgba(11, 18, 30, 0.16)"
        }
        let title_bg = if is_focused_window(id) { "#eff5ff" } else { "#f5f7fb" }
        @src.h("div", [
          ("ui-id", @src.S("window:\{id}")),
          ("onclick", focus),
          ("style", @src.S(
            "position: absolute; left: \{window.frame.x}px; top: \{window.frame.y}px; " +
            "width: \{window.frame.width}px; height: \{window.frame.height}px; z-index: \{window_z_index(id)}; " +
            "display: flex; flex-direction: column; border-radius: 18px; overflow: hidden; " +
            "border: 1px solid \{border}; box-shadow: \{shadow}; background: rgba(255, 255, 255, 0.98); " +
            "pointer-events: auto;"
          ))
        ], [
          @src.h("div", [
            ("ui-id", @src.S("window:\{id}/titlebar")),
            ("style", @src.S(
              "height: 44px; padding: 0 12px; border-bottom: 1px solid rgba(16, 24, 40, 0.08); " +
              "background: \{title_bg}; display: flex; align-items: center; justify-content: space-between; gap: 10px;"
            ))
          ], [
            @src.h("div", [("style", @src.S("font-size: 13px; font-weight: 600; color: #1d2939;"))], [
              @src.Str(window.title)
            ]),
            @src.h("button", [
              ("ui-id", @src.S("window:\{id}/close")),
              ("onclick", close),
              ("style", @src.S(
                "width: 26px; height: 26px; border: none; border-radius: 999px; background: #d92d20; " +
                "color: white; cursor: pointer; font-size: 12px; line-height: 1;"
              ))
            ], [@src.Str("x")])
          ]),
          @src.h("div", [
            ("style", @src.S("flex: 1; min-height: 0; overflow: auto; background: white;"))
          ], [
            @src.h(window.view, [], [])
          ])
        ])
      }
      None => @src.Null
    }
  })
}

fn window_layer() -> @src.Child {
  @src.h("div", [
    ("ui-id", @src.S("window-layer")),
    ("style", @src.S("position: absolute; inset: 0; pointer-events: none;"))
  ], [
    @src.h_map_dyn(window_ids, (v, _) => window_item(v))
  ])
}

fn topbar(runtime: Runtime) -> @src.Child {
  let stop_service = @src.reg_action("host_stop_service", fn() { request_stop_service(runtime) })
  @src.h("div", [
    ("ui-id", @src.S("host-topbar")),
    ("style", @src.S(
      "height: 56px; padding: 10px 14px; box-sizing: border-box; border-bottom: 1px solid rgba(16, 24, 40, 0.08); " +
      "background: rgba(249, 250, 251, 0.92); backdrop-filter: blur(10px); display: flex; " +
      "align-items: center; justify-content: space-between; gap: 12px;"
    ))
  ], [
    @src.h("div", [
      ("style", @src.S("display: flex; align-items: center; gap: 10px; min-width: 0;"))
    ], [
      @src.h("div", [
        ("style", @src.S("padding: 0 8px; font-size: 12px; font-weight: 700; color: #344054;"))
      ], [@src.Str("MetaEditor")]),
      @src.Dyn(fn() {
        if z_order.get().length() == 0 {
          @src.h("div", [("style", @src.S("font-size: 12px; color: #667085;"))], [
            @src.Str("No windows")
          ])
        } else {
          @src.Null
        }
      }),
      @src.h("div", [
        ("ui-id", @src.S("topbar-window-list")),
        ("style", @src.S("display: flex; align-items: center; gap: 8px; overflow: auto;"))
      ], [
        @src.h_map_dyn(window_ids, (v, _) => topbar_window_item(v))
      ])
    ]),
    @src.h("div", [
      ("ui-id", @src.S("system-tray")),
      ("style", @src.S("display: flex; align-items: center; gap: 10px;"))
    ], [
      @src.h("div", [
        ("ui-id", @src.S("host-tray-connection")),
        ("style", @src.S(
          "padding: 6px 10px; border-radius: 999px; background: rgba(255, 255, 255, 0.78); " +
          "border: 1px solid rgba(16, 24, 40, 0.08); font-size: 12px; color: #344054;"
        ))
      ], [@src.Str("NET")]),
      @src.h("div", [
        ("ui-id", @src.S("host-tray-time")),
        ("style", @src.S(
          "padding: 6px 10px; border-radius: 999px; background: rgba(255, 255, 255, 0.78); " +
          "border: 1px solid rgba(16, 24, 40, 0.08); font-size: 12px; color: #344054;"
        ))
      ], [@src.Str("--:--")]),
      @src.h("button", [
        ("onclick", stop_service),
        ("ui-id", @src.S("host-stop-service")),
        ("style", @src.S(
          "padding: 7px 12px; border: none; border-radius: 999px; background: #b42318; color: white; cursor: pointer;"
        ))
      ], [@src.Str("Stop")])
    ])
  ])
}

fn render_host_app(runtime: Runtime) -> @src.Child {
  @src.h("div", [
    ("ui-id", @src.S("host-root")),
    ("style", @src.S(
      "width: 100vw; height: 100vh; overflow: hidden; " +
      "background: linear-gradient(180deg, #9dc0f6 0%, #5d8bdc 42%, #3f67ac 100%); " +
      "font-family: sans-serif; color: #101828;"
    ))
  ], [
    topbar(runtime),
    @src.h("div", [
      ("ui-id", @src.S("workspace-root")),
      ("style", @src.S("position: relative; height: calc(100vh - 56px); overflow: hidden;"))
    ], [
      desktop_layer(),
      window_layer()
    ])
  ])
}

pub fn init_app(runtime: Runtime) -> Unit {
  init_app_state()
  register_builtin_app_entries()
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
    "list_windows" => list_windows_text()
    "open_window" => open_window(arg)
    "focus_window" => focus_window(arg)
    "close_window" => close_window(arg)
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
    "open_window" | "focus_window" | "close_window" =>
      sync_browser_if_connected(runtime)
    _ => ()
  }
  out
}

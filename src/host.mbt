pub(all) struct WindowSeed {
  title : String
  view : Comp
}

pub(all) struct HostEntry {
  id : String
  name : String
  icon_label : String
  create : () -> WindowSeed
}

pub(all) struct HostFrame {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Hash, Show)

pub(all) struct HostWindow {
  id : String
  entry_id : String
  title : String
  frame : HostFrame
  view : Comp
}

pub(all) struct HostEnv {
  stop_service : (() -> Unit raise)?
}

pub(all) struct HostData {
  mut entries : Array[HostEntry]
  mut windows : Array[HostWindow]
  mut z_order : Array[String]
  mut selected_entry_id : String?
  mut next_window_id : Int
  env : HostEnv
}

pub(all) struct HostSession {}

priv suberror HostErr {
  Fail(String)
}

pub fn[D, S] host_entry(editor : Editor[D, S]) -> HostEntry {
  let name = editor.name.unwrap_or(editor.id)
  {
    id: editor.id,
    name,
    icon_label: editor.icon.unwrap_or(name),
    create: fn() {
      let data = cel((editor.new_data)())
      let session = cel((editor.new_session)())
      {
        title: name,
        view: (editor.view)(data, session),
      }
    },
  }
}

fn find_entry(data : HostData, id : String) -> HostEntry? {
  for entry in data.entries {
    if entry.id == id { return Some(entry) }
  }
  None
}

fn find_window(data : HostData, id : String) -> HostWindow? {
  for window in data.windows {
    if window.id == id { return Some(window) }
  }
  None
}

fn keyed_items(items : Array[String]) -> Array[(String, Int)] {
  let out : Array[(String, Int)] = []
  for i = 0; i < items.length(); i = i + 1 {
    out.push((items[i], i))
  }
  out
}

fn entry_items(data : HostData) -> Array[(String, Int)] {
  let out : Array[(String, Int)] = []
  for i = 0; i < data.entries.length(); i = i + 1 {
    out.push((data.entries[i].id, i))
  }
  out
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

fn current_focus_id(data : HostData) -> String? {
  if data.z_order.length() == 0 { return None }
  Some(data.z_order[data.z_order.length() - 1])
}

fn is_selected_entry(data : HostData, id : String) -> Bool {
  match data.selected_entry_id {
    Some(current) => current == id
    None => false
  }
}

fn is_focused_window(data : HostData, id : String) -> Bool {
  match current_focus_id(data) {
    Some(current) => current == id
    None => false
  }
}

fn window_z_index(data : HostData, id : String) -> Int {
  for i = 0; i < data.z_order.length(); i = i + 1 {
    if data.z_order[i] == id {
      return 100 + i
    }
  }
  100
}

fn default_window_frame(serial : Int) -> HostFrame {
  let slot = (serial - 1) % 6
  {
    x: 36 + slot * 28,
    y: 36 + slot * 24,
    width: 420,
    height: 320,
  }
}

fn open_window(data : Cel[HostData], entry_id : String) -> Unit {
  data.mutate(v => {
    let entry = match find_entry(v, entry_id) {
      Some(entry) => entry
      None => return
    }
    let serial = v.next_window_id
    v.next_window_id = serial + 1
    let id = serial.to_string()
    let seed = (entry.create)()
    v.windows.push({
      id,
      entry_id,
      title: seed.title,
      frame: default_window_frame(serial),
      view: seed.view,
    })
    v.z_order = bring_to_front(v.z_order, id)
    v.selected_entry_id = Some(entry_id)
  })
}

pub fn host_open_window(data : Cel[HostData], entry_id : String) -> String raise {
  let entry_id = entry_id.trim().to_string()
  if entry_id == "" { raise Fail("open_window expects entry id") }
  if find_entry(data.peek(), entry_id) is None {
    raise Fail("entry not found: \{entry_id}")
  }
  open_window(data, entry_id)
  "opened window \{data.peek().next_window_id - 1} for \{entry_id}\n"
}

fn focus_window(data : Cel[HostData], id : String) -> Unit {
  data.mutate(v => {
    if find_window(v, id) is None { return }
    v.z_order = bring_to_front(v.z_order, id)
  })
}

pub fn host_focus_window(data : Cel[HostData], id : String) -> String raise {
  let id = id.trim().to_string()
  if id == "" { raise Fail("focus_window expects window id") }
  if find_window(data.peek(), id) is None {
    raise Fail("window not found: \{id}")
  }
  focus_window(data, id)
  "focused window \{id}\n"
}

fn close_window(data : Cel[HostData], id : String) -> Unit {
  data.mutate(v => {
    if find_window(v, id) is None { return }
    let next : Array[HostWindow] = []
    let mut closed_entry : String? = None
    for window in v.windows {
      if window.id == id {
        closed_entry = Some(window.entry_id)
      } else {
        next.push(window)
      }
    }
    v.windows = next
    v.z_order = remove_from_order(v.z_order, id)
    v.selected_entry_id = closed_entry
  })
}

pub fn host_close_window(data : Cel[HostData], id : String) -> String raise {
  let id = id.trim().to_string()
  if id == "" { raise Fail("close_window expects window id") }
  if find_window(data.peek(), id) is None {
    raise Fail("window not found: \{id}")
  }
  close_window(data, id)
  "closed window \{id}\n"
}

fn select_entry(data : Cel[HostData], id : String) -> Unit {
  data.mutate(v => {
    v.selected_entry_id = Some(id)
  })
}

fn require_entry(data : HostData, id : String) -> HostEntry {
  match find_entry(data, id) {
    Some(entry) => entry
    None => abort("entry not found: \{id}")
  }
}

fn require_window(data : HostData, id : String) -> HostWindow {
  match find_window(data, id) {
    Some(window) => window
    None => abort("window not found: \{id}")
  }
}

fn entry_text(entry : HostEntry) -> String {
  "\{entry.id}  \{entry.name}"
}

fn window_text(window : HostWindow) -> String {
  "\{window.id}  \{window.entry_id}  \{window.title}"
}

pub fn host_list_entries(data : HostData) -> String {
  if data.entries.length() == 0 { return "entries: 0\n" }
  let lines : Array[String] = ["entries: \{data.entries.length()}"]
  for entry in data.entries {
    lines.push(entry_text(entry))
  }
  lines.iter().join("\n") + "\n"
}

pub fn host_list_windows(data : HostData) -> String {
  if data.z_order.length() == 0 { return "windows: 0\n" }
  let lines : Array[String] = ["windows: \{data.z_order.length()}"]
  for id in data.z_order {
    match find_window(data, id) {
      Some(window) => lines.push(window_text(window))
      None => ()
    }
  }
  lines.iter().join("\n") + "\n"
}

fn desktop_entry_background(data : HostData, id : String) -> String {
  if is_selected_entry(data, id) { "#d7ebff" } else { "rgba(255, 255, 255, 0.20)" }
}

fn desktop_entry_border(data : HostData, id : String) -> String {
  if is_selected_entry(data, id) { "#6aa7ff" } else { "rgba(255, 255, 255, 0.18)" }
}

fn topbar_window_background(data : HostData, id : String) -> String {
  if is_focused_window(data, id) { "#f5f9ff" } else { "rgba(255, 255, 255, 0.72)" }
}

fn topbar_window_color(data : HostData, id : String) -> String {
  if is_focused_window(data, id) { "#173055" } else { "#384458" }
}

fn window_border(data : HostData, id : String) -> String {
  if is_focused_window(data, id) { "#5c8dff" } else { "#c8d1e0" }
}

fn window_shadow(data : HostData, id : String) -> String {
  if is_focused_window(data, id) {
    "0 18px 40px rgba(11, 18, 30, 0.26)"
  } else {
    "0 14px 28px rgba(11, 18, 30, 0.16)"
  }
}

fn window_titlebar_background(data : HostData, id : String) -> String {
  if is_focused_window(data, id) { "#eff5ff" } else { "#f5f7fb" }
}

fn host_css() -> String {
  (
  #|.host-root {
  #|  width: 100vw;
  #|  height: 100vh;
  #|  overflow: hidden;
  #|  background: linear-gradient(180deg, #9dc0f6 0%, #5d8bdc 42%, #3f67ac 100%);
  #|  font-family: sans-serif;
  #|  color: #101828;
  #|}
  #|.host-topbar {
  #|  height: 56px;
  #|  padding: 10px 14px;
  #|  box-sizing: border-box;
  #|  border-bottom: 1px solid rgba(16, 24, 40, 0.08);
  #|  background: rgba(249, 250, 251, 0.92);
  #|  backdrop-filter: blur(10px);
  #|  display: flex;
  #|  align-items: center;
  #|  justify-content: space-between;
  #|  gap: 12px;
  #|}
  #|.host-topbar-left {
  #|  display: flex;
  #|  align-items: center;
  #|  gap: 10px;
  #|  min-width: 0;
  #|}
  #|.host-brand {
  #|  padding: 0 8px;
  #|  font-size: 12px;
  #|  font-weight: 700;
  #|  color: #344054;
  #|}
  #|.host-empty {
  #|  font-size: 12px;
  #|  color: #667085;
  #|}
  #|.topbar-window-list {
  #|  display: flex;
  #|  align-items: center;
  #|  gap: 8px;
  #|  overflow: auto;
  #|}
  #|.topbar-window {
  #|  padding: 7px 12px;
  #|  border: 1px solid rgba(16, 24, 40, 0.08);
  #|  border-radius: 999px;
  #|  cursor: pointer;
  #|  font-size: 12px;
  #|}
  #|.system-tray {
  #|  display: flex;
  #|  align-items: center;
  #|  gap: 10px;
  #|}
  #|.host-pill {
  #|  padding: 6px 10px;
  #|  border-radius: 999px;
  #|  background: rgba(255, 255, 255, 0.78);
  #|  border: 1px solid rgba(16, 24, 40, 0.08);
  #|  font-size: 12px;
  #|  color: #344054;
  #|}
  #|.host-stop-service {
  #|  padding: 7px 12px;
  #|  border: none;
  #|  border-radius: 999px;
  #|  background: #b42318;
  #|  color: white;
  #|  cursor: pointer;
  #|}
  #|.workspace-root {
  #|  position: relative;
  #|  height: calc(100vh - 56px);
  #|  overflow: hidden;
  #|}
  #|.desktop-root {
  #|  position: absolute;
  #|  inset: 0;
  #|  padding: 24px;
  #|  display: flex;
  #|  flex-wrap: wrap;
  #|  align-content: flex-start;
  #|  gap: 18px;
  #|}
  #|.entry {
  #|  width: 112px;
  #|  padding: 10px 8px;
  #|  border-radius: 14px;
  #|  border: 1px solid transparent;
  #|  color: white;
  #|  display: flex;
  #|  flex-direction: column;
  #|  align-items: center;
  #|  gap: 8px;
  #|  cursor: default;
  #|  user-select: none;
  #|}
  #|.host-entry-icon {
  #|  width: 52px;
  #|  height: 52px;
  #|  border-radius: 16px;
  #|  background: rgba(255, 255, 255, 0.16);
  #|  display: flex;
  #|  align-items: center;
  #|  justify-content: center;
  #|  font-size: 13px;
  #|  font-weight: 700;
  #|  letter-spacing: 0.08em;
  #|}
  #|.host-entry-name {
  #|  font-size: 13px;
  #|  text-align: center;
  #|  line-height: 1.35;
  #|  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);
  #|}
  #|.window-layer {
  #|  position: absolute;
  #|  inset: 0;
  #|  pointer-events: none;
  #|}
  #|.window {
  #|  position: absolute;
  #|  display: flex;
  #|  flex-direction: column;
  #|  border-radius: 18px;
  #|  overflow: hidden;
  #|  border: 1px solid transparent;
  #|  background: rgba(255, 255, 255, 0.98);
  #|  pointer-events: auto;
  #|}
  #|.titlebar {
  #|  height: 44px;
  #|  padding: 0 12px;
  #|  border-bottom: 1px solid rgba(16, 24, 40, 0.08);
  #|  display: flex;
  #|  align-items: center;
  #|  justify-content: space-between;
  #|  gap: 10px;
  #|}
  #|.host-window-title {
  #|  font-size: 13px;
  #|  font-weight: 600;
  #|  color: #1d2939;
  #|}
  #|.close {
  #|  width: 26px;
  #|  height: 26px;
  #|  border: none;
  #|  border-radius: 999px;
  #|  background: #d92d20;
  #|  color: white;
  #|  cursor: pointer;
  #|  font-size: 12px;
  #|  line-height: 1;
  #|}
  #|.host-window-body {
  #|  flex: 1;
  #|  min-height: 0;
  #|  overflow: auto;
  #|  background: white;
  #|}
  )
}

fn desktop_entry_item(data : Cel[HostData], id : String) -> Child {
  let entry = require_entry(data.get(), id)
  h("div", [
    ("ui-id", S("entry:\{id}")),
    ("onclick", E(fn() { select_entry(data, id) })),
    ("ondblclick", E(fn() { open_window(data, id) })),
    ("style:background", D(fn() { desktop_entry_background(data.get(), id) })),
    ("style:border-color", D(fn() { desktop_entry_border(data.get(), id) }))
  ], [
    h("div", [("ui-id", S("host-entry-icon"))], [Str(entry.icon_label)]),
    h("div", [("ui-id", S("host-entry-name"))], [Str(entry.name)])
  ])
}

fn topbar_window_item(data : Cel[HostData], id : String) -> Child {
  let window = require_window(data.get(), id)
  h("button", [
    ("ui-id", S("topbar-window:\{id}")),
    ("onclick", E(fn() { focus_window(data, id) })),
    ("style:background", D(fn() { topbar_window_background(data.get(), id) })),
    ("style:color", D(fn() { topbar_window_color(data.get(), id) }))
  ], [Str(window.title)])
}

fn desktop_layer(data : Cel[HostData]) -> Child {
  h("div", [("ui-id", S("desktop-root"))], [
    h_map_dyn(fn() {
      entry_items(data.get())
    }, (v, _) => desktop_entry_item(data, v))
  ])
}

fn window_item(data : Cel[HostData], id : String) -> Child {
  let window = require_window(data.get(), id)
  h("div", [
    ("ui-id", S("window:\{id}")),
    ("onclick", E(fn() { focus_window(data, id) })),
    ("style:left", S("\{window.frame.x}px")),
    ("style:top", S("\{window.frame.y}px")),
    ("style:width", S("\{window.frame.width}px")),
    ("style:height", S("\{window.frame.height}px")),
    ("style:z-index", D(fn() { window_z_index(data.get(), id).to_string() })),
    ("style:border-color", D(fn() { window_border(data.get(), id) })),
    ("style:box-shadow", D(fn() { window_shadow(data.get(), id) }))
  ], [
    h("div", [
      ("ui-id", S("window:\{id}/titlebar")),
      ("style:background", D(fn() { window_titlebar_background(data.get(), id) }))
    ], [
      h("div", [("ui-id", S("host-window-title"))], [
        Str(window.title)
      ]),
      h("button", [
        ("ui-id", S("window:\{id}/close")),
        ("onclick", E(fn() { close_window(data, id) }))
      ], [Str("x")])
    ]),
    h("div", [("ui-id", S("host-window-body"))], [
      h(window.view, [], [])
    ])
  ])
}

fn window_layer(data : Cel[HostData]) -> Child {
  h("div", [("ui-id", S("window-layer"))], [
    h_map_dyn(fn() {
      keyed_items(data.get().z_order)
    }, (v, _) => window_item(data, v))
  ])
}

fn topbar(data : Cel[HostData]) -> Child {
  h("div", [("ui-id", S("host-topbar"))], [
    h("div", [("ui-id", S("host-topbar-left"))], [
      h("div", [("ui-id", S("host-brand"))], [Str("MetaEditor")]),
      Dyn(fn() {
        if data.get().z_order.length() == 0 {
          h("div", [("ui-id", S("host-empty"))], [
            Str("No windows")
          ])
        } else {
          Null
        }
      }),
      h("div", [
        ("ui-id", S("topbar-window-list")),
        ("style", S("display: flex; align-items: center; gap: 8px; overflow: auto;"))
      ], [
        h_map_dyn(fn() {
          keyed_items(data.get().z_order)
        }, (v, _) => topbar_window_item(data, v))
      ])
    ]),
    h("div", [("ui-id", S("system-tray"))], [
      h("div", [("ui-id", S("host-tray-connection"))], [Str("NET")]),
      h("div", [("ui-id", S("host-tray-latency"))], [Str("--ms")]),
      h("div", [("ui-id", S("host-tray-time"))], [Str("--:--")]),
      Dyn(fn() {
        match data.get().env.stop_service {
          Some(stop) => {
            let action = reg_action("host_stop_service", fn() {
              ignore(stop() catch { _ => () })
            })
            h("button", [
              ("onclick", action),
              ("ui-id", S("host-stop-service"))
            ], [Str("Stop")])
          }
          None => Null
        }
      })
    ])
  ])
}

fn host_view(data : Cel[HostData]) -> Child {
  css("host", S(host_css()))
  h("div", [("ui-id", S("host-root"))], [
    topbar(data),
    h("div", [("ui-id", S("workspace-root"))], [
      desktop_layer(data),
      window_layer(data)
    ])
  ])
}

pub fn host_editor(
  entries : Array[HostEntry],
  env? : HostEnv = { stop_service: None }
) -> Editor[HostData, HostSession] {{
  id: "host",
  name: Some("Host"),
  icon: Some("HOST"),
  new_data: fn() {
    {
      entries: entries.copy(),
      windows: [],
      z_order: [],
      selected_entry_id: None,
      next_window_id: 1,
      env,
    }
  },
  new_session: fn() { HostSession::{} },
  view: fn(data, session) {
    ignore(session)
    comp(fn(attrs, children) {
      ignore(attrs)
      ignore(children)
      host_view(data)
    })
  }
}}

pub fn default_host_editor(env? : HostEnv = { stop_service: None }) -> Editor[HostData, HostSession] {
  host_editor(default_host_entries(), env~)
}

pub fn default_host_entries() -> Array[HostEntry] {
  [
    host_entry(demo_editor()),
    host_entry(demo_host_editor()),
  ]
}

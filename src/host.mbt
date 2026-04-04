pub(all) struct HostFrame {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Hash, Show)

pub(all) struct HostWindow {
  id : String
  instance : InstanceRef
  frame : HostFrame
}

pub(all) struct HostEnv {
  stop_service : (() -> Unit raise)?
}

pub(all) struct HostExtra {
  entries : () -> Array[EntryInfo]
  spawn_child : (String) -> InstanceRef raise
  close_child : (InstanceRef) -> Unit raise
  child_info : (InstanceRef) -> Instance
  render_child : (InstanceRef) -> Comp
}

pub(all) struct HostData {
  children : Set[InstanceRef]
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

fn expect_string_arg(args : Array[ActionArg], name : String) -> String raise {
  match args {
    [ActionArg::String(value)] => value.trim().to_string()
    _ => raise HostErr::Fail("\{name} expects one string argument")
  }
}

fn find_window(data : HostData, id : String) -> HostWindow? {
  for window in data.windows {
    if window.id == id { return Some(window) }
  }
  None
}

fn entry_items(ctx : InstanceCtx[HostData, HostSession, HostExtra]) -> Array[(String, Int)] {
  let items = (ctx.extra.entries)()
  let out : Array[(String, Int)] = []
  for i = 0; i < items.length(); i = i + 1 {
    out.push((items[i].id, i))
  }
  out
}

fn require_entry(ctx : InstanceCtx[HostData, HostSession, HostExtra], id : String) -> EntryInfo {
  for entry in (ctx.extra.entries)() {
    if entry.id == id { return entry }
  }
  abort("entry not found: \{id}")
}

fn require_child(ctx : InstanceCtx[HostData, HostSession, HostExtra], instance : InstanceRef) -> Instance {
  (ctx.extra.child_info)(instance)
}

fn keyed_items(items : Array[String]) -> Array[(String, Int)] {
  let out : Array[(String, Int)] = []
  for i = 0; i < items.length(); i = i + 1 {
    out.push((items[i], i))
  }
  out
}

fn host_children(ctx : InstanceCtx[HostData, HostSession, HostExtra]) -> Array[InstanceRef] {
  ctx.data.get().children.to_array()
}

fn detach_child(data : HostData, child : InstanceRef) -> Unit {
  data.children.remove(child)
  let next : Array[HostWindow] = []
  for window in data.windows {
    if window.instance != child {
      next.push(window)
    }
  }
  data.windows = next
  let next_z : Array[String] = []
  for window_id in data.z_order {
    if find_window(data, window_id) is Some(_) {
      next_z.push(window_id)
    }
  }
  data.z_order = next_z
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

fn desktop_entry_item(
  ctx : InstanceCtx[HostData, HostSession, HostExtra],
  bind : ActionBind,
  id : String,
) -> Child {
  let entry = require_entry(ctx, id)
  h("div", [
    ("ui-id", S("entry:\{id}")),
    ("onclick", bind("select_entry", [ActionArg::String(id)])),
    ("ondblclick", bind("spawn", [ActionArg::String(id)])),
    ("style:background", D(fn() { desktop_entry_background(ctx.data.get(), id) })),
    ("style:border-color", D(fn() { desktop_entry_border(ctx.data.get(), id) }))
  ], [
    h("div", [("ui-id", S("host-entry-icon"))], [Str(entry.icon)]),
    h("div", [("ui-id", S("host-entry-name"))], [Str(entry.name)])
  ])
}

fn topbar_window_item(
  ctx : InstanceCtx[HostData, HostSession, HostExtra],
  bind : ActionBind,
  id : String,
) -> Child {
  let window = match find_window(ctx.data.get(), id) {
    Some(window) => window
    None => abort("window not found: \{id}")
  }
  let info = require_child(ctx, window.instance)
  h("button", [
    ("ui-id", S("topbar-window:\{id}")),
    ("onclick", bind("focus_window", [ActionArg::String(id)])),
    ("style:background", D(fn() { topbar_window_background(ctx.data.get(), id) })),
    ("style:color", D(fn() { topbar_window_color(ctx.data.get(), id) }))
  ], [Str(info.title)])
}

fn desktop_layer(
  ctx : InstanceCtx[HostData, HostSession, HostExtra],
  bind : ActionBind,
) -> Child {
  h("div", [("ui-id", S("desktop-root"))], [
    h_map_dyn(fn() {
      entry_items(ctx)
    }, (v, _) => desktop_entry_item(ctx, bind, v))
  ])
}

fn window_item(
  ctx : InstanceCtx[HostData, HostSession, HostExtra],
  bind : ActionBind,
  id : String,
) -> Child {
  let window = match find_window(ctx.data.get(), id) {
    Some(window) => window
    None => abort("window not found: \{id}")
  }
  let info = require_child(ctx, window.instance)
  h("div", [
    ("ui-id", S("window:\{id}")),
    ("ui-name", S("true")),
    ("onclick", bind("focus_window", [ActionArg::String(id)])),
    ("style:left", S("\{window.frame.x}px")),
    ("style:top", S("\{window.frame.y}px")),
    ("style:width", S("\{window.frame.width}px")),
    ("style:height", S("\{window.frame.height}px")),
    ("style:z-index", D(fn() { window_z_index(ctx.data.get(), id).to_string() })),
    ("style:border-color", D(fn() { window_border(ctx.data.get(), id) })),
    ("style:box-shadow", D(fn() { window_shadow(ctx.data.get(), id) }))
  ], [
    h("div", [
      ("ui-id", S("titlebar")),
      ("style:background", D(fn() { window_titlebar_background(ctx.data.get(), id) }))
    ], [
      h("div", [("ui-id", S("host-window-title"))], [Str(info.title)]),
      h("button", [
        ("ui-id", S("close")),
        ("onclick", bind("close_window", [ActionArg::String(id)]))
      ], [Str("x")])
    ]),
    h("div", [("ui-id", S("host-window-body"))], [
      h((ctx.extra.render_child)(window.instance), [], [])
    ])
  ])
}

fn window_layer(
  ctx : InstanceCtx[HostData, HostSession, HostExtra],
  bind : ActionBind,
) -> Child {
  h("div", [("ui-id", S("window-layer"))], [
    h_map_dyn(fn() {
      keyed_items(ctx.data.get().z_order)
    }, (v, _) => window_item(ctx, bind, v))
  ])
}

fn topbar(
  ctx : InstanceCtx[HostData, HostSession, HostExtra],
  bind : ActionBind,
) -> Child {
  h("div", [("ui-id", S("host-topbar"))], [
    h("div", [("ui-id", S("host-topbar-left"))], [
      h("div", [("ui-id", S("host-brand"))], [Str("MetaEditor")]),
      Dyn(fn() {
        if ctx.data.get().z_order.length() == 0 {
          h("div", [("ui-id", S("host-empty"))], [Str("No windows")])
        } else {
          Null
        }
      }),
      h("div", [
        ("ui-id", S("topbar-window-list")),
        ("style", S("display: flex; align-items: center; gap: 8px; overflow: auto;"))
      ], [
        h_map_dyn(fn() {
          keyed_items(ctx.data.get().z_order)
        }, (v, _) => topbar_window_item(ctx, bind, v))
      ])
    ]),
    h("div", [("ui-id", S("system-tray"))], [
      h("div", [("ui-id", S("host-tray-connection"))], [Str("NET")]),
      h("div", [("ui-id", S("host-tray-latency"))], [Str("--ms")]),
      h("div", [("ui-id", S("host-tray-time"))], [Str("--:--")]),
      Dyn(fn() {
        match ctx.data.get().env.stop_service {
          Some(_) =>
            h("button", [
              ("onclick", bind("stop_service", [])),
              ("ui-id", S("host-stop-service"))
            ], [Str("Stop")])
          None => Null
        }
      })
    ])
  ])
}

fn host_view(
  ctx : InstanceCtx[HostData, HostSession, HostExtra],
  bind : ActionBind,
) -> Child {
  css("host", S(host_css()))
  h("div", [("ui-id", S("host-root"))], [
    topbar(ctx, bind),
    h("div", [("ui-id", S("workspace-root"))], [
      desktop_layer(ctx, bind),
      window_layer(ctx, bind)
    ])
  ])
}

fn host_actions() -> Array[ActionSpec[HostData, HostSession, HostExtra]] {
  [
    {
      id: "select_entry",
      title: Some("Select entry"),
      desc: Some("Select one desktop entry."),
      args: [{
        name: "entry_id",
        kind: ActionArgKind::String,
        desc: Some("Entry id shown on desktop."),
        optional: false,
      }],
      run: (ctx, args) => {
        let entry_id = expect_string_arg(args, "select_entry")
        ctx.data.mutate(v => {
          v.selected_entry_id = Some(entry_id)
        })
        "selected \{entry_id}\n"
      },
    },
    {
      id: "spawn",
      title: Some("Spawn child"),
      desc: Some("Spawn one child entry under current host."),
      args: [{
        name: "entry_id",
        kind: ActionArgKind::String,
        desc: Some("Entry id to spawn."),
        optional: false,
      }],
      run: (ctx, args) => {
        let entry_id = expect_string_arg(args, "spawn")
        if entry_id == "" {
          raise HostErr::Fail("spawn expects entry id")
        }
        let child = (ctx.extra.spawn_child)(entry_id)
        ctx.data.mutate(v => {
          v.children.add(child)
          let serial = v.next_window_id
          v.next_window_id = serial + 1
          v.windows.push({
            id: serial.to_string(),
            instance: child,
            frame: default_window_frame(serial),
          })
          v.z_order = bring_to_front(v.z_order, serial.to_string())
          v.selected_entry_id = Some(entry_id)
        })
        "spawned \{child}\n"
      },
    },
    {
      id: "focus_window",
      title: Some("Focus window"),
      desc: Some("Bring one host window to front."),
      args: [{
        name: "window_id",
        kind: ActionArgKind::String,
        desc: Some("Host window id."),
        optional: false,
      }],
      run: (ctx, args) => {
        let id = expect_string_arg(args, "focus_window")
        if id == "" {
          raise HostErr::Fail("focus_window expects window id")
        }
        ctx.data.mutate(v => {
          if find_window(v, id) is Some(_) {
            v.z_order = bring_to_front(v.z_order, id)
          }
        })
        "focused window \{id}\n"
      },
    },
    {
      id: "close_window",
      title: Some("Close window"),
      desc: Some("Close one host window and its child instance tree."),
      args: [{
        name: "window_id",
        kind: ActionArgKind::String,
        desc: Some("Host window id."),
        optional: false,
      }],
      run: (ctx, args) => {
        let id = expect_string_arg(args, "close_window")
        if id == "" {
          raise HostErr::Fail("close_window expects window id")
        }
        let window = match find_window(ctx.data.peek(), id) {
          Some(window) => window
          None => raise HostErr::Fail("window not found: \{id}")
        }
        (ctx.extra.close_child)(window.instance)
        ctx.data.mutate(v => {
          v.selected_entry_id = None
        })
        "closed window \{id}\n"
      },
    },
    {
      id: "stop_service",
      title: Some("Stop service"),
      desc: Some("Stop native service if current host has that ability."),
      args: [],
      run: (ctx, _) =>
        match ctx.data.get().env.stop_service {
          Some(stop) => {
            ignore(stop() catch { _ => () })
            "stopping service\n"
          }
          None => raise HostErr::Fail("stop_service unavailable")
        },
    },
  ]
}

fn build_host_extra(runtime : InstanceRuntime, host : InstanceRef) -> HostExtra {
  {
    entries: fn() { runtime_entry_infos(runtime) },
    spawn_child: entry_id => boot_instance(runtime, entry_id, parent=Some(host)),
    close_child: child => close_instance(runtime, child),
    child_info: child =>
      query(runtime, child) catch {
        _ => abort("instance not found: \{child}")
      },
    render_child: child => render_instance(runtime, child),
  }
}

fn host_children_extra(
  _runtime : InstanceRuntime,
  _host : InstanceRef,
  ctx : InstanceCtx[HostData, HostSession, HostExtra],
) -> Array[InstanceRef] {
  host_children(ctx)
}

fn host_attach_child(
  _runtime : InstanceRuntime,
  _host : InstanceRef,
  ctx : InstanceCtx[HostData, HostSession, HostExtra],
  child : InstanceRef,
) -> Unit {
  ctx.data.mutate(v => {
    v.children.add(child)
  })
}

fn host_detach_child(
  _runtime : InstanceRuntime,
  _host : InstanceRef,
  ctx : InstanceCtx[HostData, HostSession, HostExtra],
  child : InstanceRef,
) -> Unit {
  ctx.data.mutate(v => {
    detach_child(v, child)
  })
}

pub fn host_entry(
  env? : HostEnv = { stop_service: None }
) -> Entry[HostData, HostSession, HostExtra] {{
  id: "host",
  name: Some("Host"),
  icon: Some("HOST"),
  new_data: fn() {
    {
      children: Set::new(),
      windows: [],
      z_order: [],
      selected_entry_id: None,
      next_window_id: 1,
      env,
    }
  },
  new_session: fn() { HostSession::{} },
  view: fn(ctx, bind) {
    comp(fn(attrs, children) {
      ignore(attrs)
      ignore(children)
      host_view(ctx, bind)
    })
  },
  actions: host_actions(),
}}

pub fn default_host_entry(env? : HostEnv = { stop_service: None }) -> Entry[HostData, HostSession, HostExtra] {
  host_entry(env~)
}

pub fn register_default_entries(
  runtime : InstanceRuntime,
  env? : HostEnv = { stop_service: None }
) -> Unit {
  register_entry(runtime, demo_entry())
  register_entry_with_extra(
    runtime,
    host_entry(env~),
    build_host_extra,
    host_attach_child,
    host_children_extra,
    host_detach_child,
  )
}

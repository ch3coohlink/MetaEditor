pub struct Window { id: String; shared: SharedInstance; title: String } derive(Eq, Hash)
pub struct WindowLayout { x: Int; y: Int; z: Int; w: Int; h: Int }
pub struct HostData { next_window_id: Cel[Int]; windows: Cel[Array[Window]] }
pub struct HostSession {
  latency: Cel[String]
  time: Cel[String]
  layouts: Cel[Map[String, WindowLayout]]
  instances: Cel[Map[String, Instance]]
}
pub struct HostActions { start_entry: (EntryInfo) -> Unit raise; close_window: (Window) -> Unit raise }
let demo_body: UIMeta = ui("demo-body")
pub let demo: Entry[String, Unit, Unit, Unit] = {
  id: "demo", title: "Demo",
  data: () => "Demo app",
  session: _ => (),
  actions: (_, _) => (),
  session_actions: (_, _, _) => (),
  init: (_, _, text, _, _, _) => comp((_, _) => h("div", [Id(demo_body)], [Str(text)])),
}

let desktop: UIMeta = ui("desktop", style=(
  #| & {
  #|   display:flex;
  #|   flex-direction:column;
  #|   width:100%;
  #|   height:100%;
  #|   overflow:hidden;
  #| }
))
let topbar: UIMeta = ui("topbar", style=(
  #| & {
  #|   display:flex;
  #|   align-items:center;
  #|   justify-content:space-between;
  #|   gap:16px;
  #|   padding:10px 14px;
  #|   font:600 14px/1 "Segoe UI",sans-serif;
  #|   color:#e6edf6;
  #|   background:#16324f;
  #|   box-shadow:0 1px 0 #ffffff14;
  #| }
))
let workspace: UIMeta = ui("workspace", style=(
  #| & {
  #|   position:relative;
  #|   flex:1;
  #|   min-height:0;
  #|   overflow:hidden;
  #|   background:
  #|     radial-gradient(circle at top left, #2f6ea6 0, #224f7a 28%, #16324f 65%, #0f2033 100%);
  #| }
))
let entries_wrap: UIMeta = ui("entries-wrap", style=(
  #| & {
  #|   position:relative;
  #|   z-index:1;
  #|   display:grid;
  #|   grid-template-columns:repeat(auto-fill, 84px);
  #|   align-content:start;
  #|   gap:14px;
  #|   padding:18px;
  #| }
))
let entry: UIMeta = ui("entry", style=(
  #| & {
  #|   display:flex;
  #|   flex-direction:column;
  #|   align-items:center;
  #|   gap:8px;
  #|   padding:0;
  #|   border:none;
  #|   background:transparent;
  #|   cursor:pointer;
  #| }
))
let logo: UIMeta = ui("logo", style=(
  #| & {
  #|   display:flex;
  #|   align-items:center;
  #|   justify-content:center;
  #|   width:56px;
  #|   height:56px;
  #|   border-radius:16px;
  #|   background:#f3f7fb;
  #|   box-shadow:0 8px 18px #08111d40;
  #|   font:700 18px/1 "Segoe UI",sans-serif;
  #|   color:#16324f;
  #| }
))
let name: UIMeta = ui("name", style=(
  #| & {
  #|   max-width:84px;
  #|   font:12px/1.3 "Segoe UI",sans-serif;
  #|   color:#f6f8fb;
  #|   text-align:center;
  #|   text-shadow:0 1px 2px #08111d80;
  #|   word-break:break-word;
  #| }
))
let tray: UIMeta = ui("tray", style=(
  #| & {
  #|   display:flex;
  #|   align-items:center;
  #|   gap:8px;
  #|   font:12px/1.2 Consolas,"Courier New",monospace;
  #| }
))
let latency: UIMeta = ui("latency", style=(
  #| & {
  #|   min-width:44px;
  #|   padding:3px 6px;
  #|   border:1px solid #89a8c5;
  #|   border-radius:999px;
  #|   background:#ffffff14;
  #|   text-align:center;
  #| }
))
let time: UIMeta = ui("time", style=(
  #| & {
  #|   min-width:72px;
  #|   padding:3px 8px;
  #|   border:1px solid #89a8c5;
  #|   border-radius:999px;
  #|   background:#ffffff14;
  #|   text-align:center;
  #| }
))
let windows_wrap: UIMeta = ui("windows-wrap", style=(
  #| & {
  #|   position:absolute;
  #|   inset:0;
  #|   z-index:2;
  #|   pointer-events:none;
  #|   padding:24px 32px 32px 132px;
  #|   overflow:hidden;
  #| }
))
let window: UIMeta = ui("window", style=(
  #| & {
  #|   pointer-events:auto;
  #|   display:flex;
  #|   flex-direction:column;
  #|   width:min(720px, 100%);
  #|   max-height:100%;
  #|   min-height:180px;
  #|   margin:0 0 18px;
  #|   border:1px solid #c2d3e4;
  #|   border-radius:18px;
  #|   background:#fff;
  #|   box-shadow:0 18px 40px #08111d3d;
  #|   overflow:hidden;
  #| }
))
let title: UIMeta = ui("title", style=(
  #| & {
  #|   flex:1;
  #|   font:600 14px/1.3 "Segoe UI",sans-serif;
  #|   color:#1f2a37;
  #|   cursor:move;
  #|   user-select:none;
  #| }
))
let header: UIMeta = ui("header", style=(
  #| & {
  #|   display:flex;
  #|   align-items:center;
  #|   gap:8px;
  #|   padding:12px 14px;
  #|   border-bottom:1px solid #e5ebf3;
  #|   background:#f8fbff;
  #| }
))
let close: UIMeta = ui("close", style=(
  #| & {
  #|   margin-left:auto;
  #|   padding:2px 8px;
  #|   border:1px solid #cfd8e3;
  #|   border-radius:999px;
  #|   background:#f7f9fc;
  #|   font:12px/1 "Segoe UI",sans-serif;
  #|   cursor:pointer;
  #| }
))
let resize: UIMeta = ui("resize", style=(
  #| & {
  #|   position:absolute;
  #|   right:0;
  #|   bottom:0;
  #|   width:18px;
  #|   height:18px;
  #|   cursor:nwse-resize;
  #|   background:linear-gradient(135deg, transparent 0 35%, #9cb4cd 35% 55%, #5f7d9c 55% 100%);
  #| }
))
let body: UIMeta = ui("body", style=(
  #| & {
  #|   flex:1;
  #|   min-height:0;
  #|   padding:14px;
  #|   overflow:auto;
  #| }
))
let instance: UIMeta = ui("instance", scope=Scope)
pub let host: Entry[HostData, HostSession, Unit, HostActions] = {
  id: "host", title: "host",
  data: () => {{ next_window_id: cel(0), windows: cel([]) }},
  session: _ => {{
    latency: cel("--ms"),
    time: cel("--:--"),
    layouts: cel(Map::new()),
    instances: cel(Map::new()),
  }},
  actions: (_, _) => (),
  session_actions: (rt, d, s) => {
    let self_inst = rt.current_instance()
    {{
      start_entry: v => {
        let id = "window-\{d.next_window_id.get()}"
        d.next_window_id.set(d.next_window_id.get() + 1)
        let shared = rt.spawn_shared(v.id)
        let index = d.windows.get().length()
        let inst = shared.open(parent=Some(self_inst))
        s.instances.mutate(instances => instances.set(id, inst))
        s.layouts.mutate(layouts => layouts.set(id, {
          x: 24 + index * 24, y: 24 + index * 24, z: index + 1, w: 720, h: 320,
        }))
        d.windows.mutate(ws => ws.push({ id, shared, title: v.title }))
      },
      close_window: w => {
        match s.instances.get().get(w.id) {
          Some(inst) => {
            inst.close()
            s.instances.mutate(instances => ignore(instances.remove(w.id)))
          }
          None => ()
        }
        d.windows.mutate(ws => {
          let mut i = 0
          while i < ws.length() {
            if ws[i].id == w.id {
              ignore(ws.remove(i))
              break
            }
            i = i + 1
          }
        })
        s.layouts.mutate(layouts => ignore(layouts.remove(w.id)))
      },
    }}
  },
  init: (rt, _, d, s, _, actions) => {
    let self_inst = rt.current_instance()
    let entries = Entry::list()
    ignore(effect(() => {
      let windows = d.windows.get()
      let next_ids = []
      for w in windows {
        next_ids.push(w.id)
        if s.instances.get().get(w.id) is None {
          match (try? w.shared.open(parent=Some(self_inst)): Result[Instance, _]) {
            Ok(inst) => s.instances.mutate(instances => instances.set(w.id, inst))
            Err(err) => rt.report(err.to_string())
          }
        }
        if s.layouts.get().get(w.id) is None {
          let i = next_ids.length() - 1
          s.layouts.mutate(layouts => layouts.set(w.id, {
            x: 24 + i * 24, y: 24 + i * 24, z: i + 1, w: 720, h: 320,
          }))
        }
      }
      for id, inst in s.instances.get() {
        if !next_ids.contains(id) {
          ignore((try? inst.close(): Result[Unit, _]))
          s.instances.mutate(instances => ignore(instances.remove(id)))
        }
      }
      for id, _ in s.layouts.get() {
        if !next_ids.contains(id) {
          s.layouts.mutate(layouts => ignore(layouts.remove(id)))
        }
      }
    }))
    let get_layout = (w: Window, i: Int) => {
        match s.layouts.get().get(w.id) {
          Some(layout) => layout
          None => { x: 24 + i * 24, y: 24 + i * 24, z: i + 1, w: 720, h: 320 }
        }
      }
    let set_layout = (w: Window, layout: WindowLayout) => {
        s.layouts.mutate(layouts => layouts.set(w.id, layout))
      }
    let focus_window = (w: Window, i: Int) => {
        let mut top = 0
        let windows = d.windows.get()
        for j = 0; j < windows.length(); j = j + 1 {
          let z = get_layout(windows[j], j).z
          if z > top { top = z }
        }
        let layout = get_layout(w, i)
        if layout.z < top {
          set_layout(w, { ..layout, z: top + 1 })
        }
      }
    comp((_, _) => h("div", [Id(desktop)], [
      h("div", [Id(topbar)], [
        h("div", [], [Str("MetaEditor Desktop")]),
        h("div", [Id(tray)], [
          h("div", [Id(latency)], [DynP(() => Str(s.latency.get()))]),
          h("div", [Id(time)], [DynP(() => Str(s.time.get()))]),
        ]),
      ]),
      h("div", [Id(workspace)], [
        h("div", [Id(entries_wrap)], [h_map_arr(
          entries, (v, _) => h("button", [Id(entry),
            Event(Click, _ => { (actions.start_entry)(v) }, EventCfg::new()),
          ], [
            h("div", [Id(logo)], [Str(v.title[0:1].to_string().to_upper())]),
            h("div", [Id(name)], [Str(v.title)]),
          ]),
          ui_id=Some("entries"),
        )]),
        h("div", [Id(windows_wrap)], [h_map(
          d.windows,
          (v, index) => h("div", [Id(window),
            Event(Click, _ => { focus_window(v, index()) }, EventCfg::new()),
            Event(PointerDown, _ => { focus_window(v, index()) }, EventCfg::new()),
            Style("left", Dynamic(() => String("\{get_layout(v, index()).x}px"))),
            Style("top", Dynamic(() => String("\{get_layout(v, index()).y}px"))),
            Style("width", Dynamic(() => String("\{get_layout(v, index()).w}px"))),
            Style("height", Dynamic(() => String("\{get_layout(v, index()).h}px"))),
            Style("position", Static(String("absolute"))),
            Style("z-index", Dynamic(() => String("\{get_layout(v, index()).z}"))),
          ], [
            h("div", [Id(header)], [
              h("div", [Id(title),
                Event(PointerDown, ev => {
                  focus_window(v, index())
                  match ev.data {
                    Pointer(m) => {
                      let layout = get_layout(v, index())
                      let start_x = layout.x
                      let start_y = layout.y
                      let dx = m.x - start_x
                      let dy = m.y - start_y
                      drag(ev, move_ev => {
                        match move_ev.data {
                          Pointer(mm) => {
                            set_layout(v, {
                              ..get_layout(v, index()),
                              x: mm.x - dx,
                              y: mm.y - dy,
                            })
                          }
                          _ => ()
                        }
                      }, () => ())
                    }
                    _ => ()
                  }
                }, EventCfg::new(stop=true)),
              ], [Str(v.title)]),
              h("button", [Id(close),
                Event(Click, _ => { (actions.close_window)(v) }, EventCfg::new()),
              ], [Str("x")]),
            ]),
            h("div", [Id(body)], [match s.instances.get().get(v.id) {
              Some(i) => h("div", [React, Id(instance)], [h(i.view, [], [])])
              None => Null
            }]),
            h("div", [Id(resize),
              Event(PointerDown, ev => {
                focus_window(v, index())
                match ev.data {
                  Pointer(m) => {
                    let layout = get_layout(v, index())
                    let start_w = layout.w
                    let start_h = layout.h
                    let start_x = m.x
                    let start_y = m.y
                    drag(ev, move_ev => {
                      match move_ev.data {
                        Pointer(mm) => {
                          let next_w = start_w + mm.x - start_x
                          let next_h = start_h + mm.y - start_y
                          set_layout(v, {
                            ..get_layout(v, index()),
                            w: if next_w < 240 { 240 } else { next_w },
                            h: if next_h < 180 { 180 } else { next_h },
                          })
                        }
                        _ => ()
                      }
                    }, () => ())
                  }
                  _ => ()
                }
              }, EventCfg::new(stop=true)),
            ], []),
          ]),
          ui_id=Some("windows"),
        )]),
      ]),
    ]))
  },
}

fn init {
  try { demo.register(); host.register() } catch { e => abort(e.to_string()) }
}

pub fn drag(e: Event, move_fn: (Event) -> Unit raise, up: () -> Unit) -> Unit raise {
  let t = match e.target {
    Some(node) => node;
    _ => fail("pointer drag expects mouse event")
  }
  let pointer_id = e.pointer_id()
  let move_h = t.on(PointerMove, move_fn, EventCfg::new())
  let up_h: Ref[ListenerObj?] = Ref::new(None)
  let cancel_h: Ref[ListenerObj?] = Ref::new(None)
  let end = _ => {
    t.release_pointer(pointer_id)
    move_h.off()
    match up_h.val { Some(h) => h.off(); None => () }
    match cancel_h.val { Some(h) => h.off(); None => () }
    up()
  }
  up_h.val = Some(t.on(PointerUp, end, EventCfg::new()))
  cancel_h.val = Some(t.on(PointerCancel, end, EventCfg::new()))
  t.capture_pointer(pointer_id)
}

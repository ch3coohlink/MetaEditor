pub struct Window { id: String; title: String; inst: Instance?; x: Cel[Int]; y: Cel[Int] } derive(Eq, Hash)
pub struct Drag { id: String; dx: Int; dy: Int }
pub struct HostSession { latency: Cel[String]; time: Cel[String]; windows: Cel[Array[Window]] }
pub struct HostActions { start_entry: (EntryInfo) -> Unit raise; close_window: (Window) -> Unit raise }
pub let demo: Entry[String, Unit, Unit] = {
  id: "demo", title: "Demo",
  data: () => "Demo app",
  session: _ => (),
  actions: (_, _, _) => (),
  init: (_, text, _, _) => {
    let demo_body = ui("demo-body")
    comp((_, _) => h("div", [Id(demo_body)], [Str(text)]))
  },
}

pub let host: Entry[Unit, HostSession, HostActions] = {
  id: "host", title: "host",
  data: () => (),
  session: _ => {{ latency: cel("--ms"), time: cel("--:--"), windows: cel([]) }},
  actions: (rt, _, s) => {
    let wid = gen_id(0)
    {{
      start_entry: v => {
        let id = "window-\{wid()}"
        let inst = Some(rt.spawn(v.id, id="inst-\{id}"))
        s.windows.mutate(ws => ws.push({ id, title: v.title, inst,
          x: cel(24 + ws.length() * 24), y: cel(24 + ws.length() * 24) }))
      },
      close_window: w => {
        match w.inst { Some(inst) => rt.close(inst.id); None => () }
        s.windows.mutate(ws => {
          let mut i = 0
          while i < ws.length() {
            if ws[i].id == w.id {
              ignore(ws.remove(i))
              break
            }
            i = i + 1
          }
        })
      },
    }}
  },
  init: (_, _, s, actions) => {
    let desktop = ui("desktop", style=(
      #| & {
      #|   display:flex;
      #|   flex-direction:column;
      #|   width:100%;
      #|   height:100%;
      #|   overflow:hidden;
      #| }
    ))
    let topbar = ui("topbar", style=(
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
    let workspace = ui("workspace", style=(
      #| & {
      #|   position:relative;
      #|   flex:1;
      #|   min-height:0;
      #|   overflow:hidden;
      #|   background:
      #|     radial-gradient(circle at top left, #2f6ea6 0, #224f7a 28%, #16324f 65%, #0f2033 100%);
      #| }
    ))
    let entries_wrap = ui("entries-wrap", style=(
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
    let entry = ui("entry", style=(
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
    let logo = ui("logo", style=(
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
    let name = ui("name", style=(
      #| & {
      #|   max-width:84px;
      #|   font:12px/1.3 "Segoe UI",sans-serif;
      #|   color:#f6f8fb;
      #|   text-align:center;
      #|   text-shadow:0 1px 2px #08111d80;
      #|   word-break:break-word;
      #| }
    ))
    let tray = ui("tray", style=(
      #| & {
      #|   display:flex;
      #|   align-items:center;
      #|   gap:8px;
      #|   font:12px/1.2 Consolas,"Courier New",monospace;
      #| }
    ))
    let latency = ui("latency", style=(
      #| & {
      #|   min-width:44px;
      #|   padding:3px 6px;
      #|   border:1px solid #89a8c5;
      #|   border-radius:999px;
      #|   background:#ffffff14;
      #|   text-align:center;
      #| }
    ))
    let time = ui("time", style=(
      #| & {
      #|   min-width:72px;
      #|   padding:3px 8px;
      #|   border:1px solid #89a8c5;
      #|   border-radius:999px;
      #|   background:#ffffff14;
      #|   text-align:center;
      #| }
    ))
    let windows_wrap = ui("windows-wrap", style=(
      #| & {
      #|   position:absolute;
      #|   inset:0;
      #|   z-index:2;
      #|   pointer-events:none;
      #|   padding:24px 32px 32px 132px;
      #|   overflow:hidden;
      #| }
    ))
    let window = ui("window", style=(
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
    let title = ui("title", style=(
      #| & {
      #|   flex:1;
      #|   font:600 14px/1.3 "Segoe UI",sans-serif;
      #|   color:#1f2a37;
      #|   cursor:move;
      #|   user-select:none;
      #| }
    ))
    let header = ui("header", style=(
      #| & {
      #|   display:flex;
      #|   align-items:center;
      #|   gap:8px;
      #|   padding:12px 14px;
      #|   border-bottom:1px solid #e5ebf3;
      #|   background:#f8fbff;
      #| }
    ))
    let close = ui("close", style=(
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
    let body = ui("body", style=(
      #| & {
      #|   flex:1;
      #|   min-height:0;
      #|   padding:14px;
      #|   overflow:auto;
      #| }
    ))
    let instance = ui("instance", scope=Scope)
    let entries = Entry::list()

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
          s.windows,
          (v, _) => h("div", [Id(window),
            Style("left", Dynamic(() => String("\{v.x.get()}px"))),
            Style("top", Dynamic(() => String("\{v.y.get()}px"))),
            Style("position", Static(String("absolute"))),
          ], [
            h("div", [Id(header)], [
              h("div", [Id(title)], [Str(v.title)]),
              h("button", [Id(close),
                Event(Click, _ => { (actions.close_window)(v) }, EventCfg::new()),
              ], [Str("x")]),
            ]),
            h("div", [Id(body)], [match v.inst {
              Some(i) => h("div", [React, Id(instance)], [h(i.view, [], [])])
              None => Null
            }]),
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

pub struct Window { id: String; title: String; inst: Instance? } derive(Eq, Hash)
pub struct Icon { id: Cel[String]; title: Cel[String] } derive(Eq, Hash)
pub struct HostData { entries: Cel[Array[Icon]] }
pub struct HostSession { latency: Cel[String]; time: Cel[String]; windows: Cel[Array[Window]] }
pub struct HostActions { start_entry: (Icon) -> Unit raise }
pub let demo_app: Entry[String, Unit, Unit] = {
  id: "demo", title: "Demo",
  data: () => "Demo app",
  session: _ => (),
  actions: (_, _, _) => (),
  init: (_, text, _, _) => {
    let demo_body = ui("demo-body")
    comp((_, _) => h("div", [Id(demo_body)], [Str(text)]))
  },
}

pub let host: Entry[HostData, HostSession, HostActions] = {
  id: "host", title: "host",
  data: () => {{ entries: cel([{ id: cel("demo"), title: cel("Demo") }]) }},
  session: _ => {{ latency: cel("--ms"), time: cel("--:--"), windows: cel([]) }},
  actions: (rt, _, s) => {
    let wid = gen_id(0)
    {{
      start_entry: v => {
        let id = "window-\{wid()}"
        let inst = Some(rt.spawn(v.id.get(), id="inst-\{id}"))
        let win = { id, title: v.title.get(), inst }
        s.windows.mutate(ws => ws.push(win))
      },
    }}
  },
  init: (_, d, s, actions) => {
    let topbar = ui("topbar", style=(
      #| & {
      #|   display:flex;
      #|   align-items:center;
      #|   justify-content:space-between;
      #|   gap:16px;
      #|   padding:10px 14px;
      #|   border-bottom:1px solid #d7dde8;
      #|   background:#f7f9fc;
      #| }
    ))
    let tray = ui("tray", style=(
      #| & {
      #|   display:flex;
      #|   align-items:center;
      #|   gap:8px;
      #|   font:12px/1.2 Consolas,"Courier New",monospace;
      #|   color:#51606f;
      #| }
    ))
    let latency = ui("latency", style=(
      #| & {
      #|   min-width:44px;
      #|   padding:3px 6px;
      #|   border:1px solid #d7dde8;
      #|   border-radius:999px;
      #|   background:#fff;
      #|   text-align:center;
      #| }
    ))
    let time = ui("time", style=(
      #| & {
      #|   min-width:72px;
      #|   padding:3px 8px;
      #|   border:1px solid #d7dde8;
      #|   border-radius:999px;
      #|   background:#fff;
      #|   text-align:center;
      #| }
    ))
    let workspace = ui("workspace", style=(
      #| & {
      #|   display:grid;
      #|   grid-template-columns:220px minmax(0, 1fr);
      #|   min-height:calc(100vh - 45px);
      #|   background:#f7f9fc;
      #| }
    ))
    let entries_wrap = ui("entries-wrap", style=(
      #| & {
      #|   display:flex;
      #|   flex-direction:column;
      #|   gap:8px;
      #|   padding:12px;
      #|   border-right:1px solid #d7dde8;
      #|   background:#f7f9fc;
      #| }
    ))
    let entry = ui("entry", style=(
      #| & {
      #|   padding:8px 10px;
      #|   border:1px solid #d7dde8;
      #|   border-radius:10px;
      #|   background:#fff;
      #|   box-shadow:0 1px 2px #0f172a0f;
      #|   cursor:pointer;
      #| }
    ))
    let name = ui("name", style=(
      #| & {
      #|   font:13px/1.3 "Segoe UI",sans-serif;
      #|   color:#223043;
      #|   white-space:nowrap;
      #|   overflow:hidden;
      #|   text-overflow:ellipsis;
      #| }
    ))
    let window = ui("window", style=(
      #| & {
      #|   margin:12px;
      #|   padding:12px 14px;
      #|   border:1px solid #cfd8e3;
      #|   border-radius:14px;
      #|   background:#fff;
      #|   box-shadow:0 8px 24px #0f172a14;
      #| }
    ))
    let title = ui("title", style=(
      #| & {
      #|   font:600 14px/1.3 "Segoe UI",sans-serif;
      #|   color:#1f2a37;
      #| }
    ))
    let instance = ui("instance", scope=Scope)

    comp((_, _) => h("div", [], [
      h("div", [Id(topbar)], [
        h("div", [], [Str("MetaEditor")]),
        h("div", [Id(tray)], [
          h("div", [Id(latency)], [DynP(() => Str(s.latency.get()))]),
          h("div", [Id(time)], [DynP(() => Str(s.time.get()))]),
        ]),
      ]),
      h("div", [Id(workspace)], [
        h("div", [Id(entries_wrap)], [h_map(
          ui_id=Some("entries"), d.entries,
          (v, _) => h("button", [Id(entry),
            Event(Click, _ => { (actions.start_entry)(v) }, EventCfg::new()),
          ], [h("div", [Id(name)], [DynP(() => Str(v.title.get()))])]),
        )]),
        h_map(
          ui_id=Some("windows"), s.windows,
          (v, _) => h("div", [Id(window)], [
            h("div", [Id(title)], [Str(v.title)]),
            match v.inst {
              Some(i) => h("div", [React, Id(instance)], [h(i.view, [], [])])
              None => Null
            },
          ]),
        ),
      ]),
    ]))
  },
}

fn init {
  try { host.register(); demo_app.register() } catch { e => abort(e.to_string()) }
}

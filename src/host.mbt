pub struct Window { id: String; title: String; body: Instance? } derive(Eq, Hash)
pub struct EntryDef { id: Cel[String]; title: Cel[String] } derive(Eq, Hash)
pub struct HostData { latency: Cel[String]; time: Cel[String]; entries: Cel[Array[EntryDef]] }
pub struct HostSession { windows: Cel[Array[Window]] }

pub let host: Entry[HostData, HostSession] = {
  id: "host", title: "host",
  data: () => {{
    latency: cel("--ms"), time: cel("--:--"),
    entries: cel([{ id: cel("demo"), title: cel("Demo") }]),
  }},
  session: _ => {{ windows: cel([]) }},
  init: (runtime, d, s) => {
    let wid = gen_id(0)
    let demo_body = ui("demo-body") catch { _ => panic() }
    let demo_app: Entry[String, Unit] = {
      id: "demo-app", title: "Demo",
      data: () => "Demo app",
      session: _ => (),
      init: (_, text, _) => comp((_, _) => h("div", [Id(demo_body)], [Str(text)])),
    }
    fn open_entry(v: EntryDef) -> Unit raise {
      let id = "window-\{wid()}"
      let body = match v.id.get() {
        "demo" => Some(runtime.create_instance(demo_app, id="inst-\{id}"))
        _ => None
      }
      s.windows.mutate(ws => ws.push({ id, title: v.title.get(), body }))
    }
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

    comp((_, _) => h("div", [], [
      h("div", [Id(topbar)], [
        h("div", [], [Str("MetaEditor")]),
        h("div", [Id(tray)], [
          h("div", [Id(latency)], [DynP(() => Str(d.latency.get()))]),
          h("div", [Id(time)], [DynP(() => Str(d.time.get()))]),
        ]),
      ]),
      h("div", [Id(workspace)], [
        h("div", [Id(entries_wrap)], [h_map(
          ui_id=Some("entries"), d.entries,
          (v, _) => h("button", [Id(entry),
            Event(Click, _ => open_entry(v), EventCfg::new()),
          ], [h("div", [Id(name)], [DynP(() => Str(v.title.get()))])]),
        )]),
        h_map(
          ui_id=Some("windows"), s.windows,
          (v, _) => h("div", [Id(window)], [
            h("div", [Id(title)], [Str(v.title)]),
            match v.body { Some(body) => body.child(); None => Null },
          ]),
        ),
      ]),
    ]))
  },
}

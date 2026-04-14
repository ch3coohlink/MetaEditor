pub struct HostData {
  latency: Cel[String]
  time: Cel[String]
  entries: Cel[Array[String]]
  windows: Cel[Array[String]]
}

let host: Entry[HostData, Unit] = {
  id: "host",
  title: "host",
  data: () => {{
    latency: cel("--ms"),
    time: cel("--:--"),
    entries: cel(["demo"]),
    windows: cel([]),
  }},
  session: _ => (),
  init: () => {
    let topbar = ui("topbar", style="")
    let tray = ui("tray", style="")
    let latency = ui("latency", style="")
    let time = ui("time", style="")
    let workspace = ui("workspace", style="")
    let entries = ui("entries", style="")
    let entry = ui("entry", style="")
    let name = ui("name", style="")
    let window = ui("window", style="")
    let title = ui("title", style="...")

    let host_entry_item = (n: String) => {
      h("div", [Id(entry)], [h("div", [Id(name)], [Str(n)])])
    }
    (d, _) => comp((_, _) => h("div", [], [
      h("div", [Id(topbar)], [
        h("div", [], [Str("MetaEditor")]),
        h("div", [Id(tray)], [
          h("div", [Id(latency)], [DynP(() => Str(d.latency.get()))]),
          h("div", [Id(time)], [DynP(() => Str(d.time.get()))]),
        ]),
      ]),
      h("div", [Id(workspace)], [
        h("div", [], [h_map(
          ui_id=Some(entries.id),
          d.entries,
          (item, _) => host_entry_item(item),
        )]),
        Dyn(Some("windows"), () => Arr(
          d.windows.get().map(v =>
            h("div", [Id(window)], [h("div", [Id(title)], [Str(v)])]))
        )),
      ]),
    ]))
  },
}

fn init { ignore(Entry::new(host)) }

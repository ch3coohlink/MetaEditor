fn host() -> Comp raise {
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

  let host_tray = cel({ latency_text: "--ms", time_text: "--:--" })
  let host_entries: Cel[Array[String]] = cel(["demo"])
  let host_windows: Cel[Array[String]] = cel([])

  let reset_host_tray = () => { host_tray.set({ latency_text: "--ms", time_text: "--:--" }) }
  let set_host_tray = (a: String, b: String) => { host_tray.set({ latency_text: a, time_text: b }) }

  let get_host_tray = () => host_tray.get()
  let reset_host = (entries?: Array[String] = ["demo"]) => {
    host_entries.set(entries.copy())
    host_windows.set([])
    reset_host_tray()
  }
  let set_host_windows = (windows: Array[String]) => { host_windows.set(windows.copy()) }

  let host_entry_item = (n: String) => {
    h("div", [Id(entry)], [h("div", [Id(name)], [Str(n)])])
  }
  let host_window_item = (name: String) => {
    h("div", [Id(window)], [h("div", [Id(title)], [Str(name)])])
  }
  comp((_, _) => h("div", [], [
    h("div", [Id(topbar)], [
      h("div", [], [Str("MetaEditor")]),
      h("div", [Id(tray)], [
        h("div", [Id(latency)], [Dyn(None, () => Str(host_tray.get().latency_text))]),
        h("div", [Id(time)], [Dyn(None, () => Str(host_tray.get().time_text))]),
      ]),
    ]),
    h("div", [Id(workspace)], [
      h("div", [], [h_map(
        ui_id=Some(entries.id),
        host_entries,
        (item, _) => host_entry_item(item),
      )]),
      Dyn(Some("windows"), () => Arr(
        host_windows.get().map(item => host_window_item(item))
      )),
    ]),
  ]))
}
fn init { ignore(Entry::new("host", host)) }
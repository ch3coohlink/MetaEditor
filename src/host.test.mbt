fn has_entry(id: String) -> Bool {
  for entry in Entry::list() {
    if entry.id == id { return true }
  }
  false
}

fn entry_index(rt: Instance, path: String, title: String) -> Int {
  let mut i = 0
  while i < 32 {
    let v = rt.query("\{path}/\{i}/name", Text) catch { _ => Text("") }
    match v {
      Text(v) => if v == title { return i }
      _ => ()
    }
    i = i + 1
  }
  -1
}

test "host: start entry action opens window" {
  let rt = Runtime::new("host").root()
  let i = entry_index(rt, "entries", "Demo")
  assert_eq(i >= 0, true)
  rt.dispatch("entries/\{i}/entry", Event::pointer(Click))
  match rt.query("windows/0/title", Text) {
    Text("Demo") => ()
    _ => fail("expected host action to open demo window")
  }
}

test "host: desktop lists demo and host entries" {
  assert_eq(has_entry("demo"), true)
  assert_eq(has_entry("host"), true)
}

test "host: host entry opens host window" {
  let rt = Runtime::new("host").root()
  let i = entry_index(rt, "entries", "host")
  assert_eq(i >= 0, true)
  rt.dispatch("entries/\{i}/entry", Event::pointer(Click))
  match rt.query("windows/0/title", Text) {
    Text("host") => ()
    _ => fail("expected host action to open host window")
  }
  let j = entry_index(rt, "windows/0/instance/entries", "Demo")
  assert_eq(j >= 0, true)
  match rt.query("windows/0/instance/entries/\{j}/name", Text) {
    Text("Demo") => ()
    _ => fail("expected nested host desktop")
  }
}

test "host: opening demo twice keeps both windows queryable" {
  let rt = Runtime::new("host").root()
  let i = entry_index(rt, "entries", "Demo")
  assert_eq(i >= 0, true)
  let click = Event::pointer(Click)
  rt.dispatch("entries/\{i}/entry", click)
  rt.dispatch("entries/\{i}/entry", click)
  match rt.query("windows/0/title", Text) {
    Text("Demo") => ()
    _ => fail("expected first demo window")
  }
  match rt.query("windows/1/title", Text) {
    Text("Demo") => ()
    _ => fail("expected second demo window")
  }
}

test "host: dragging window updates its position" {
  let rt = Runtime::new("host").root()
  let i = entry_index(rt, "entries", "Demo")
  assert_eq(i >= 0, true)
  rt.dispatch("entries/\{i}/entry", Event::pointer(Click))
  rt.dispatch("windows/0/title", Event::pointer(PointerDown, x=40, y=40, pointer_id=1))
  rt.dispatch("windows/0/title", Event::pointer(PointerMove, x=160, y=120, pointer_id=1))
  rt.dispatch("windows/0/title", Event::pointer(PointerUp, x=160, y=120, pointer_id=1))
  match rt.query("windows/0/window", Style("left")) {
    Style("left", "144px") => ()
    _ => fail("expected dragged left position")
  }
  match rt.query("windows/0/window", Style("top")) {
    Style("top", "104px") => ()
    _ => fail("expected dragged top position")
  }
}

test "host: clicking window brings it to front" {
  let rt = Runtime::new("host").root()
  let i = entry_index(rt, "entries", "Demo")
  let j = entry_index(rt, "entries", "host")
  assert_eq(i >= 0, true)
  assert_eq(j >= 0, true)
  let click = Event::pointer(Click)
  rt.dispatch("entries/\{i}/entry", click)
  rt.dispatch("entries/\{j}/entry", click)
  match rt.query("windows/0/title", Text) {
    Text("Demo") => ()
    _ => fail("expected demo window first")
  }
  match rt.query("windows/1/title", Text) {
    Text("host") => ()
    _ => fail("expected host window last")
  }
  rt.dispatch("windows/0/title", Event::pointer(PointerDown, x=40, y=40, pointer_id=1))
  match rt.query("windows/0/window", Style("z-index")) {
    Style("z-index", "3") => ()
    _ => fail("expected demo window to move above host")
  }
  match rt.query("windows/1/window", Style("z-index")) {
    Style("z-index", "2") => ()
    _ => fail("expected host window z-index to stay lower")
  }
}

test "host: windows expose stacking z-index" {
  let rt = Runtime::new("host").root()
  let demo_i = entry_index(rt, "entries", "Demo")
  let host_i = entry_index(rt, "entries", "host")
  assert_eq(demo_i >= 0, true)
  assert_eq(host_i >= 0, true)
  let click = Event::pointer(Click)
  rt.dispatch("entries/\{host_i}/entry", click)
  rt.dispatch("entries/\{demo_i}/entry", click)
  match rt.query("windows/0/window", Style("z-index")) {
    Style("z-index", "1") => ()
    _ => fail("expected first window z-index")
  }
  match rt.query("windows/1/window", Style("z-index")) {
    Style("z-index", "2") => ()
    _ => fail("expected second window z-index")
  }
}

test "host: close window removes instance jump" {
  let rt = Runtime::new("host").root()
  let i = entry_index(rt, "entries", "Demo")
  assert_eq(i >= 0, true)
  rt.dispatch("entries/\{i}/entry", Event::pointer(Click))
  rt.dispatch("windows/0/close", Event::pointer(Click))
  assert_fail("window should be removed", () => ignore(rt.query("windows/0/title", Text)))
  assert_fail("window session should be removed", () => ignore(rt.query("windows/0/instance/demo-body", Text)))
}

test "host: window list shares in data and position stays per instance" {
  let left = ui("left", scope=Scope)
  let right = ui("right", scope=Scope)
  let shell: Entry[Unit, Unit, Unit, Unit] = {
    id: "host-shared-shell", title: "shell", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (runtime, _, _, _, _, _) => {
      let main = runtime.spawn_typed(host).0 catch { _ => panic() }
      let other = main.spawn() catch { _ => panic() }
      comp((_, _) => h("div", [], [
        h("div", [Id(left)], [h(main.view, [], [])]),
        h("div", [Id(right)], [h(other.view, [], [])]),
      ]))
    },
  }
  shell.register()
  let rt = Runtime::new("host-shared-shell").root()
  let i = entry_index(rt, "left/entries", "Demo")
  assert_eq(i >= 0, true)
  rt.dispatch("left/entries/\{i}/entry", Event::pointer(Click))
  match rt.query("left/windows/0/title", Text) {
    Text("Demo") => ()
    _ => fail("expected left instance to render shared window")
  }
  match rt.query("right/windows/0/title", Text) {
    Text("Demo") => ()
    _ => fail("expected right instance to render shared window")
  }
  match rt.query("left/windows/0/window", Style("left")) {
    Style("left", "24px") => ()
    _ => fail("expected left default position")
  }
  match rt.query("right/windows/0/window", Style("left")) {
    Style("left", "24px") => ()
    _ => fail("expected right default position")
  }
  rt.dispatch("left/windows/0/title", Event::pointer(PointerDown, x=40, y=40, pointer_id=1))
  rt.dispatch("left/windows/0/title", Event::pointer(PointerMove, x=160, y=120, pointer_id=1))
  rt.dispatch("left/windows/0/title", Event::pointer(PointerUp, x=160, y=120, pointer_id=1))
  match rt.query("left/windows/0/window", Style("left")) {
    Style("left", "144px") => ()
    _ => fail("expected left dragged position")
  }
  match rt.query("right/windows/0/window", Style("left")) {
    Style("left", "24px") => ()
    _ => fail("expected right position to stay local")
  }
}

test "host: window content shares while position stays local" {
  let left = ui("left", scope=Scope)
  let right = ui("right", scope=Scope)
  let shared_btn = ui("shared-btn")
  let shared_value = ui("shared-value")
  let shared_entry: Entry[Cel[String], Unit, Unit, Unit] = {
    id: "host-shared-window-content", title: "Shared Win",
    data: () => cel("A"),
    session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (_, _, d, _, _, _) => comp((_, _) => h("div", [], [
      h("button", [Id(shared_btn),
        Event(Click, _ => d.set(d.get() + "B"), EventCfg::new()),
      ], [Str("go")]),
      h("div", [Id(shared_value)], [DynP(() => Str(d.get()))]),
    ])),
  }
  let shell: Entry[Unit, Unit, Unit, Unit] = {
    id: "host-shared-window-content-shell", title: "shell", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (runtime, _, _, _, _, _) => {
      let main = runtime.spawn_typed(host).0 catch { _ => panic() }
      let other = main.spawn() catch { _ => panic() }
      comp((_, _) => h("div", [], [
        h("div", [Id(left)], [h(main.view, [], [])]),
        h("div", [Id(right)], [h(other.view, [], [])]),
      ]))
    },
  }
  shared_entry.register()
  shell.register()
  let rt = Runtime::new("host-shared-window-content-shell").root()
  let i = entry_index(rt, "left/entries", "Shared Win")
  assert_eq(i >= 0, true)
  rt.dispatch("left/entries/\{i}/entry", Event::pointer(Click))
  match rt.query("left/windows/0/instance/shared-value", Text) {
    Text("A") => ()
    _ => fail("expected left shared window to mount")
  }
  match rt.query("right/windows/0/instance/shared-value", Text) {
    Text("A") => ()
    _ => fail("expected right shared window to mount")
  }
  rt.dispatch("left/windows/0/instance/shared-btn", Event::pointer(Click))
  match rt.query("left/windows/0/instance/shared-value", Text) {
    Text("AB") => ()
    _ => fail("expected left content to update")
  }
  match rt.query("right/windows/0/instance/shared-value", Text) {
    Text("AB") => ()
    _ => fail("expected right content to share data")
  }
  rt.dispatch("left/windows/0/title", Event::pointer(PointerDown, x=40, y=40, pointer_id=1))
  rt.dispatch("left/windows/0/title", Event::pointer(PointerMove, x=160, y=120, pointer_id=1))
  rt.dispatch("left/windows/0/title", Event::pointer(PointerUp, x=160, y=120, pointer_id=1))
  match rt.query("left/windows/0/window", Style("left")) {
    Style("left", "144px") => ()
    _ => fail("expected left dragged position")
  }
  match rt.query("right/windows/0/window", Style("left")) {
    Style("left", "24px") => ()
    _ => fail("expected right position to stay local")
  }
}

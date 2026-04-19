fn has_entry(id: String) -> Bool {
  for entry in Entry::list() {
    if entry.id == id { return true }
  }
  false
}

fn entry_index(rt: Runtime, path: String, title: String) -> Int {
  let mut i = 0
  while i < 8 {
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
  let rt = Runtime::new("host")
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
  let rt = Runtime::new("host")
  let i = entry_index(rt, "entries", "host")
  assert_eq(i >= 0, true)
  rt.dispatch("entries/\{i}/entry", Event::pointer(Click))
  match rt.query("windows/0/title", Text) {
    Text("host") => ()
    _ => fail("expected host action to open host window")
  }
  let j = entry_index(rt, "inst-window-0/entries", "Demo")
  assert_eq(j >= 0, true)
  match rt.query("inst-window-0/entries/\{j}/name", Text) {
    Text("Demo") => ()
    _ => fail("expected nested host desktop")
  }
}

test "host: opening demo twice keeps both windows queryable" {
  let rt = Runtime::new("host")
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
  let rt = Runtime::new("host")
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
  let rt = Runtime::new("host")
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
  let rt = Runtime::new("host")
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
  let rt = Runtime::new("host")
  let i = entry_index(rt, "entries", "Demo")
  assert_eq(i >= 0, true)
  rt.dispatch("entries/\{i}/entry", Event::pointer(Click))
  rt.dispatch("windows/0/close", Event::pointer(Click))
  assert_fail("window should be removed", () => ignore(rt.query("windows/0/title", Text)))
  assert_fail("instance jump should be removed", () => ignore(rt.query("inst-window-0/demo-body", Text)))
}

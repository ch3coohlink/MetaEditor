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
  rt.dispatch("entries/\{i}/entry", Event::new(Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0, pointer_id: 0,
  }))) catch { _ => panic() }
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
  rt.dispatch("entries/\{i}/entry", Event::new(Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0, pointer_id: 0,
  }))) catch { _ => panic() }
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
  let click = Event::new(Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0, pointer_id: 0,
  }))
  rt.dispatch("entries/\{i}/entry", click) catch { _ => panic() }
  rt.dispatch("entries/\{i}/entry", click) catch { _ => panic() }
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
  rt.dispatch("entries/\{i}/entry", Event::new(Click, None, Mouse({
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0, pointer_id: 0,
  }))) catch { _ => panic() }
  rt.dispatch("windows/0/title", Event::new(Mouse({
    kind: PointerDown,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 40, y: 40, button: 0, buttons: 0, pointer_id: 1,
  }))) catch { _ => panic() }
  rt.dispatch("windows/0/title", Event::new(Mouse({
    kind: PointerMove,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 160, y: 120, button: 0, buttons: 0, pointer_id: 1,
  }))) catch { _ => panic() }
  rt.dispatch("windows/0/title", Event::new(Mouse({
    kind: PointerUp,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 160, y: 120, button: 0, buttons: 0, pointer_id: 1,
  }))) catch { _ => panic() }
  match rt.query("windows/0/window", Style("left")) {
    Style("left", "144px") => ()
    _ => fail("expected dragged left position")
  }
  match rt.query("windows/0/window", Style("top")) {
    Style("top", "104px") => ()
    _ => fail("expected dragged top position")
  }
}

test "host: close window removes instance jump" {
  let rt = Runtime::new("host")
  let i = entry_index(rt, "entries", "Demo")
  assert_eq(i >= 0, true)
  rt.dispatch("entries/\{i}/entry", Event::new(Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0, pointer_id: 0,
  }))) catch { _ => panic() }
  rt.dispatch("windows/0/close", Event::new(Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0, pointer_id: 0,
  }))) catch { _ => panic() }
  assert_fail("window should be removed", () => ignore(rt.query("windows/0/title", Text)))
  assert_fail("instance jump should be removed", () => ignore(rt.query("inst-window-0/demo-body", Text)))
}

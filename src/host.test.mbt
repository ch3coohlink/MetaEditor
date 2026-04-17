test "host: start entry action opens window" {
  let rt = Runtime::new("host")
  rt.dispatch("entries/0/entry", Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0,
  })) catch { _ => panic() }
  match rt.query("windows/0/title", Text) {
    Text("Demo") => ()
    _ => fail("expected host action to open demo window")
  }
}

test "host: desktop lists demo and host entries" {
  let rt = Runtime::new("host")
  match rt.query("entries/0/name", Text) {
    Text("Demo") => ()
    _ => fail("expected demo entry")
  }
  match rt.query("entries/1/name", Text) {
    Text("host") => ()
    _ => fail("expected host entry")
  }
}

test "host: host entry opens host window" {
  let rt = Runtime::new("host")
  rt.dispatch("entries/1/entry", Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0,
  })) catch { _ => panic() }
  match rt.query("windows/0/title", Text) {
    Text("host") => ()
    _ => fail("expected host action to open host window")
  }
  match rt.query("inst-window-0/entries/0/name", Text) {
    Text("Demo") => ()
    _ => fail("expected nested host desktop")
  }
}

test "host: opening demo twice keeps both windows queryable" {
  let rt = Runtime::new("host")
  let click = Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0,
  })
  rt.dispatch("entries/0/entry", click) catch { _ => panic() }
  rt.dispatch("entries/0/entry", click) catch { _ => panic() }
  match rt.query("windows/0/title", Text) {
    Text("Demo") => ()
    _ => fail("expected first demo window")
  }
  match rt.query("windows/1/title", Text) {
    Text("Demo") => ()
    _ => fail("expected second demo window")
  }
}

test "host: close window removes instance jump" {
  let rt = Runtime::new("host")
  rt.dispatch("entries/0/entry", Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0,
  })) catch { _ => panic() }
  rt.dispatch("windows/0/close", Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0,
  })) catch { _ => panic() }
  assert_fail("window should be removed", () => ignore(rt.query("windows/0/title", Text)))
  assert_fail("instance jump should be removed", () => ignore(rt.query("inst-window-0/demo-body", Text)))
}

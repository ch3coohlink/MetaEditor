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

fn pointer_event(kind: EventKind, x: Int, y: Int, button?: Int = 0, buttons?: Int = 1, pointer_id?: Int = 1) -> Event {
  Event::new(kind, Pointer({
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x, y, button, buttons, pointer_id,
  }))
}

fn key_event(key: String, shift?: Bool = false, ctrl?: Bool = false) -> Event {
  Event::new(KeyDown, Key({
    mod: { ctrl, shift, alt: false, meta: false }, key, code: key,
  }))
}

test "text editor: input inserts text and enter splits line" {
  let rt = Runtime::new("text-editor")
  rt.dispatch("input", Event::new(Input, Input({ value: "A" }))) catch { _ => panic() }
  match rt.query("lines/0/text", Text) {
    Text("Ahello") => ()
    _ => fail("expected input to insert into first line")
  }
  rt.dispatch("content", key_event("Enter")) catch { _ => panic() }
  match rt.query("lines/0/text", Text) {
    Text("A") => ()
    _ => fail("expected enter to split current line")
  }
  match rt.query("lines/1/text", Text) {
    Text("hello") => ()
    _ => fail("expected tail to move into next line")
  }
}

test "text editor: pointer drag selects text and backspace deletes selection" {
  let rt = Runtime::new("text-editor")
  rt.dispatch("content", pointer_event(PointerDown, 52, 0)) catch { _ => panic() }
  rt.dispatch("content", pointer_event(PointerMove, 76, 0)) catch { _ => panic() }
  rt.dispatch("content", pointer_event(PointerUp, 76, 0, buttons=0)) catch { _ => panic() }
  rt.dispatch("content", key_event("Backspace")) catch { _ => panic() }
  match rt.query("lines/0/text", Text) {
    Text("ho") => ()
    _ => fail("expected selected text to be deleted")
  }
}

test "text editor: ctrl a selects all and tab replaces with spaces" {
  let rt = Runtime::new("text-editor")
  rt.dispatch("content", key_event("a", ctrl=true)) catch { _ => panic() }
  rt.dispatch("content", key_event("Tab")) catch { _ => panic() }
  match rt.query("lines/0/text", Text) {
    Text("  ") => ()
    _ => fail("expected tab to replace whole document after select all")
  }
  assert_fail("expected second line removed after replace all", () => ignore(rt.query("lines/1/text", Text)))
}

test "text editor: data shares text and session keeps cursor state" {
  let rt = Runtime::new("text-editor")
  let data = (text_editor.data)()
  let s1 = (text_editor.session)(data)
  let s2 = (text_editor.session)(data)
  let a1 = (text_editor.actions)(rt, data, s1)
  let a2 = (text_editor.actions)(rt, data, s2)
  (a1.set_text)("abc")
  move_right(data, s1, false)
  assert_eq((a2.get_text)(), "abc")
  assert_eq(s1.cursor_col.get(), 1)
  assert_eq(s2.cursor_col.get(), 0)
}

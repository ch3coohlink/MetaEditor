fn key_event(key: String, shift?: Bool = false, ctrl?: Bool = false) -> Event {
  Event::new(KeyDown, Key({
    mod: { ctrl, shift, alt: false, meta: false }, key, code: key,
  }))
}

test "text editor: input inserts text and enter splits line" {
  let rt = Runtime::new("text-editor").root()
  rt.dispatch("input", Event::new(Input, Input({ value: "A" })))
  match rt.query("lines/0/text", Text) {
    Text("Ahello") => ()
    _ => fail("expected input to insert into first line")
  }
  rt.dispatch("content", key_event("Enter"))
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
  let rt = Runtime::new("text-editor").root()
  rt.dispatch("content", Event::pointer(PointerDown, x=52, y=0, buttons=1, pointer_id=1))
  rt.dispatch("content", Event::pointer(PointerMove, x=76, y=0, buttons=1, pointer_id=1))
  rt.dispatch("content", Event::pointer(PointerUp, x=76, y=0, buttons=0, pointer_id=1))
  rt.dispatch("content", key_event("Backspace"))
  match rt.query("lines/0/text", Text) {
    Text("ho") => ()
    _ => fail("expected selected text to be deleted")
  }
}

test "text editor: ctrl a selects all and tab replaces with spaces" {
  let rt = Runtime::new("text-editor").root()
  rt.dispatch("content", key_event("a", ctrl=true))
  rt.dispatch("content", key_event("Tab"))
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
  let a = (text_editor.actions)(rt, data)
  let a1 = (text_editor.session_actions)(rt, data, s1)
  let _a2 = (text_editor.session_actions)(rt, data, s2)
  (a1.set_text)("abc")
  move_right(data, s1, false)
  assert_eq((a.get_text)(), "abc")
  assert_eq(s1.cursor_col.get(), 1)
  assert_eq(s2.cursor_col.get(), 0)
}

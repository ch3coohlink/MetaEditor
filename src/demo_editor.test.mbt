fn has_insert(cmds : Array[DomCmd]) -> Bool {
  for cmd in cmds {
    match cmd {
      InsertBefore(_, _, _) => return true
      _ => ()
    }
  }
  false
}

fn has_remove(cmds : Array[DomCmd]) -> Bool {
  for cmd in cmds {
    match cmd {
      Remove(_) => return true
      _ => ()
    }
  }
  false
}

test "all: demo editor renders todo list structure" {
  let editor = demo_editor()
  let ui = mount_ui(h((editor.view)(cel(editor.data), cel(editor.session)), [], []))
  defer ui.cleanup()
  assert_true(ui.contains_testid("demo-editor-root"))
  assert_true(ui.contains_testid("demo-summary"))
  assert_true(ui.contains_testid("demo-list"))
  assert_true(ui.contains_testid("demo-item-1"))
  assert_eq(ui.contains_testid("demo-item-2"), false)
  assert_eq(ui.text_at("demo-summary"), Some("Visible 1 / 2 todos"))
  assert_true(ui.text().contains("Demo Todo Editor"))
}

test "all: demo editor add emits insert commands" {
  let editor = demo_editor()
  let ui = mount_ui(h((editor.view)(cel(editor.data), cel(editor.session)), [], []))
  defer ui.cleanup()
  let cmds = ui.click("demo-add")
  assert_true(ui.contains_testid("demo-item-3"))
  assert_eq(ui.text_at("demo-summary"), Some("Visible 2 / 3 todos"))
  assert_true(has_insert(cmds))
}

test "all: demo editor toggle updates text" {
  let editor = demo_editor()
  let ui = mount_ui(h((editor.view)(cel(editor.data), cel(editor.session)), [], []))
  defer ui.cleanup()
  ignore(ui.click("demo-toggle-done"))
  ignore(ui.click("demo-item-toggle-1"))
  assert_eq(ui.text_at("demo-item-text-1"), Some("[x] Write helper"))
}

test "all: demo editor filter reveals hidden todo" {
  let editor = demo_editor()
  let ui = mount_ui(h((editor.view)(cel(editor.data), cel(editor.session)), [], []))
  defer ui.cleanup()
  let cmds = ui.click("demo-toggle-done")
  assert_true(ui.contains_testid("demo-item-2"))
  assert_eq(ui.text_at("demo-summary"), Some("Visible 2 / 2 todos"))
  assert_true(has_insert(cmds))
}

test "all: demo editor remove emits remove commands" {
  let editor = demo_editor()
  let ui = mount_ui(h((editor.view)(cel(editor.data), cel(editor.session)), [], []))
  defer ui.cleanup()
  let cmds = ui.click("demo-item-remove-1")
  assert_eq(ui.contains_testid("demo-item-1"), false)
  assert_eq(ui.text_at("demo-summary"), Some("Visible 0 / 1 todos"))
  assert_true(ui.contains_testid("demo-empty"))
  assert_true(has_remove(cmds))
}

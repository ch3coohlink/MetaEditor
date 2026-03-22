fn expect_action_cb(cmds : Array[@lib.DomCmd], name : String) -> Int {
  for cmd in cmds {
    match cmd {
      @lib.Action(action_name, cb_id) =>
        if action_name == name {
          return cb_id
        }
      _ => ()
    }
  }
  panic()
}

test "counter app registers actions and updates count" {
  @lib.reset_test_ui()
  @lib.get_cmds().clear()
  let root_ref : Ref[@lib.VNode?] = Ref::new(None)
  let _ = @lib.scope(fn() {
    root_ref.val = Some(@app.build_counter_app())
    ()
  }) catch { _ => panic() }
  let cmds = @lib.get_cmds()
  assert_true(cmds.length() > 0)
  match root_ref.val {
    Some(root) => assert_true(root.id > 0)
    None => panic()
  }
  let add_id = expect_action_cb(cmds, "add")
  let undo_id = expect_action_cb(cmds, "undo")
  let redo_id = expect_action_cb(cmds, "redo")
  let rendered = cmds.map(fn(cmd) { cmd.to_json() }).join("\n")
  assert_true(rendered.contains("Counter Test App"))
  assert_true(rendered.contains("Count: 0"))
  assert_true(rendered.contains("Version: 0"))
  assert_true(rendered.contains("Add"))
  assert_true(rendered.contains("Undo"))
  assert_true(rendered.contains("Redo"))

  @lib.trigger_callback(add_id)
  let after_add = @lib.get_cmds().map(fn(cmd) { cmd.to_json() }).join("\n")
  assert_true(after_add.contains("Count: 1"))
  assert_true(after_add.contains("Version: 1"))

  @lib.trigger_callback(undo_id)
  let after_undo = @lib.get_cmds().map(fn(cmd) { cmd.to_json() }).join("\n")
  assert_true(after_undo.contains("Count: 0"))
  assert_true(after_undo.contains("Version: 0"))

  @lib.trigger_callback(redo_id)
  let after_redo = @lib.get_cmds().map(fn(cmd) { cmd.to_json() }).join("\n")
  assert_true(after_redo.contains("Count: 1"))
  assert_true(after_redo.contains("Version: 1"))
}

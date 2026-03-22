test "host app renders shell ui history" {
  @lib.reset_test_ui()
  let runtime = @service.make_runtime(".")
  @service.init_app_for_test(runtime)
  let history = @service.ui_history_json(runtime).stringify()
  assert_true(history.contains("MetaEditor Host"))
  assert_true(history.contains("Switch to Host"))
  assert_true(history.contains("Switch to Counter"))
  assert_true(history.contains("Stop Service"))
  assert_true(history.contains("Workspace"))
}

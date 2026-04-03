test "mock browser renders host editor and opens window" {
  reset_test_state()
  let editor = default_host_editor()
  let data = cel((editor.new_data)())
  let session = cel((editor.new_session)())
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h((editor.view)(data, session), [], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  assert_eq(mock_exists(browser, "entry:demo"), true)
  assert_eq(mock_exists(browser, "window:1"), false)
  assert_eq(browser.css.get("host") is Some(_), true)

  ignore(mock_event(browser, "dblclick", "entry:demo"))
  assert_eq(mock_exists(browser, "window:1"), true)
  assert_eq(mock_text(browser, "window:1/titlebar").contains("Demo Todo"), true)
  assert_eq(mock_exists(browser, "topbar-window:1"), true)
}

test "mock browser closes host window" {
  reset_test_state()
  let editor = default_host_editor()
  let data = cel((editor.new_data)())
  let session = cel((editor.new_session)())
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h((editor.view)(data, session), [], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "dblclick", "entry:demo"))
  assert_eq(mock_exists(browser, "window:1"), true)

  ignore(mock_event(browser, "click", "window:1/close"))
  assert_eq(mock_exists(browser, "window:1"), false)
  assert_eq(mock_exists(browser, "topbar-window:1"), false)
}

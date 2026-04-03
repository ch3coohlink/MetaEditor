test "mock browser renders host editor and opens window" {
  reset_test_state()
  let runtime = new_instance_runtime()
  register_default_entries(runtime)
  let root_query = no_raise(() => boot_instance(runtime, "host"))
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(render_instance(runtime, root_query), [], []))
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
  assert_eq(no_raise(() => query(runtime, "demo-1")).entry, "demo")
}

test "mock browser closes host window" {
  reset_test_state()
  let runtime = new_instance_runtime()
  register_default_entries(runtime)
  let root_query = no_raise(() => boot_instance(runtime, "host"))
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(render_instance(runtime, root_query), [], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "dblclick", "entry:demo"))
  assert_eq(mock_exists(browser, "window:1"), true)

  ignore(mock_event(browser, "click", "window:1/close"))
  assert_eq(mock_exists(browser, "window:1"), false)
  assert_eq(mock_exists(browser, "topbar-window:1"), false)
  assert_eq((try? query(runtime, "demo-1") : Result[Instance, _]) is Err(_), true)
}

test "mock browser host can spawn nested host instance" {
  reset_test_state()
  let runtime = new_instance_runtime()
  register_default_entries(runtime)
  let root_query = no_raise(() => boot_instance(runtime, "host"))
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(render_instance(runtime, root_query), [], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "dblclick", "entry:host"))
  assert_eq(mock_exists(browser, "window:1"), true)
  assert_eq(mock_text(browser, "window:1/titlebar").contains("Host"), true)
  assert_eq(no_raise(() => query(runtime, "host-2")).entry, "host")
}

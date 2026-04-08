let demo_entry_path = "root/workspace/desktop/entries/items/0/entry"
let host_entry_path = "root/workspace/desktop/entries/items/1/entry"
let first_window_path = "root/workspace/windows/items/0/window"
let first_window_titlebar_path = "root/workspace/windows/items/0/window/titlebar"
let first_window_title_path = "root/workspace/windows/items/0/window/titlebar/title"
let first_window_close_path = "root/workspace/windows/items/0/window/titlebar/close"
let second_window_path = "root/workspace/windows/items/1/window"
let second_window_title_path = "root/workspace/windows/items/1/window/titlebar/title"
let first_topbar_window_path = "root/topbar/left/windows/items/0/window"

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

  assert_eq(mock_exists(browser, demo_entry_path), true)
  assert_eq(mock_exists(browser, first_window_path), false)
  let mut has_host_css = false
  let mut root_fills_parent = false
  let mut has_titlebar_css = false
  let mut has_close_css = false
  for _, text in browser.css {
    if text.contains(".host{") {
      has_host_css = true
    }
    if text.contains("width: 100%;") && text.contains("height: 100%;") {
      root_fills_parent = true
    }
    if text.contains(".host .titlebar{") {
      has_titlebar_css = true
    }
    if text.contains(".host .close{") {
      has_close_css = true
    }
  }
  assert_eq(has_host_css, true)
  assert_eq(root_fills_parent, true)
  assert_eq(has_titlebar_css, true)
  assert_eq(has_close_css, true)

  ignore(mock_event(browser, "dblclick", demo_entry_path))
  assert_eq(mock_exists(browser, first_window_path), true)
  assert_eq(mock_text(browser, first_window_titlebar_path).contains("Demo Todo"), true)
  assert_eq(mock_exists(browser, first_topbar_window_path), true)
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

  ignore(mock_event(browser, "dblclick", demo_entry_path))
  assert_eq(mock_exists(browser, first_window_path), true)

  ignore(mock_event(browser, "click", first_window_close_path))
  assert_eq(mock_exists(browser, first_window_path), false)
  assert_eq(mock_exists(browser, first_topbar_window_path), false)
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

  ignore(no_raise(() => call_instance(
    runtime,
    root_query,
    "spawn",
    [ActionArg::String("host")],
  )))
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(mock_exists(browser, first_window_path), true)
  assert_eq(mock_text(browser, first_window_titlebar_path).contains("Host"), true)
  assert_eq(no_raise(() => query(runtime, "host-2")).entry, "host")
}

test "mock browser host tray follows shared tray state" {
  reset_test_state()
  let runtime = new_instance_runtime()
  reset_host_tray()
  register_default_entries(runtime)
  let root_query = no_raise(() => boot_instance(runtime, "host"))
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(render_instance(runtime, root_query), [], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  assert_eq(mock_text(browser, "root/topbar/tray/latency"), "--ms")
  assert_eq(mock_text(browser, "root/topbar/tray/time"), "--:--")

  set_host_tray("12ms", "10:23:45")
  apply_mock_cmds(browser, flush_cmds())

  assert_eq(mock_text(browser, "root/topbar/tray/latency"), "12ms")
  assert_eq(mock_text(browser, "root/topbar/tray/time"), "10:23:45")
}

test "mock browser focus_window updates z-index by z_order" {
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

  ignore(mock_event(browser, "dblclick", demo_entry_path))
  ignore(no_raise(() => call_instance(
    runtime,
    root_query,
    "spawn",
    [ActionArg::String("host")],
  )))
  apply_mock_cmds(browser, flush_cmds())

  assert_eq(mock_text(browser, first_window_title_path).contains("Demo Todo"), true)
  assert_eq(mock_text(browser, second_window_title_path).contains("Host"), true)
  let z1_before = match find_mock_node_by_ui(browser, first_window_path) {
    Some(node) => node.styles.get("z-index")
    None => None
  }
  let z2_before = match find_mock_node_by_ui(browser, second_window_path) {
    Some(node) => node.styles.get("z-index")
    None => None
  }
  assert_eq(z1_before, Some("100"))
  assert_eq(z2_before, Some("101"))

  ignore(no_raise(() => call_instance(
    runtime,
    root_query,
    "focus_window",
    [ActionArg::String("1")],
  )))
  apply_mock_cmds(browser, flush_cmds())

  assert_eq(mock_text(browser, first_window_title_path).contains("Host"), true)
  assert_eq(mock_text(browser, second_window_title_path).contains("Demo Todo"), true)
  let z1_after = match find_mock_node_by_ui(browser, first_window_path) {
    Some(node) => node.styles.get("z-index")
    None => None
  }
  let z2_after = match find_mock_node_by_ui(browser, second_window_path) {
    Some(node) => node.styles.get("z-index")
    None => None
  }
  assert_eq(z1_after, Some("100"))
  assert_eq(z2_after, Some("101"))
}

test "mock browser close_window keeps other windows and instances" {
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

  ignore(mock_event(browser, "dblclick", demo_entry_path))
  ignore(no_raise(() => call_instance(
    runtime,
    root_query,
    "spawn",
    [ActionArg::String("host")],
  )))
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(mock_exists(browser, first_window_path), true)
  assert_eq(mock_exists(browser, second_window_path), true)

  ignore(mock_event(browser, "click", first_window_close_path))

  assert_eq(mock_exists(browser, first_window_path), true)
  assert_eq(mock_exists(browser, second_window_path), false)
  assert_eq(mock_exists(browser, first_topbar_window_path), true)
  assert_eq(mock_exists(browser, "root/topbar/left/windows/items/1/window"), false)
  assert_eq((try? query(runtime, "demo-1") : Result[Instance, _]) is Err(_), true)
  assert_eq(no_raise(() => query(runtime, "host-2")).entry, "host")
}

test "mock browser desktop selection clears on background click" {
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

  ignore(mock_event(browser, "click", demo_entry_path))
  let selected_before = match find_mock_node_by_ui(browser, demo_entry_path) {
    Some(node) => node.styles.get("background")
    None => None
  }
  assert_eq(selected_before, Some("#d7ebff"))

  ignore(mock_event(browser, "click", "root/workspace/desktop/background"))
  let selected_after = match find_mock_node_by_ui(browser, demo_entry_path) {
    Some(node) => node.styles.get("background")
    None => None
  }
  assert_eq(selected_after, Some("rgba(255, 255, 255, 0.20)"))
}

test "mock browser entry selection stays after spawn and close" {
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

  ignore(mock_event(browser, "click", demo_entry_path))
  ignore(no_raise(() => call_instance(
    runtime,
    root_query,
    "spawn",
    [ActionArg::String("demo")],
  )))
  apply_mock_cmds(browser, flush_cmds())
  ignore(no_raise(() => call_instance(
    runtime,
    root_query,
    "close_window",
    [ActionArg::String("1")],
  )))
  apply_mock_cmds(browser, flush_cmds())

  let demo_bg = match find_mock_node_by_ui(browser, demo_entry_path) {
    Some(node) => node.styles.get("background")
    None => None
  }
  let host_bg = match find_mock_node_by_ui(browser, host_entry_path) {
    Some(node) => node.styles.get("background")
    None => None
  }
  assert_eq(demo_bg, Some("#d7ebff"))
  assert_eq(host_bg, Some("rgba(255, 255, 255, 0.20)"))
}

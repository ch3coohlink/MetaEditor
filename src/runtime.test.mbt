test "runtime: new runtime boots default host root" {
  reset_test_state()
  let runtime = new_runtime()
  assert_eq(runtime_roots(runtime), ["host-1"])
  assert_eq(no_raise(() => runtime_query(runtime, "host-1")).entry, "host")
}

test "runtime: set_roots replaces old tree and closes previous root" {
  reset_test_state()
  let runtime = new_runtime()
  let roots = no_raise(() => runtime_set_roots(runtime, ["demo"]))
  assert_eq(roots, ["demo-1"])
  assert_eq((try? runtime_query(runtime, "host-1") : Result[Instance, _]) is Err(_), true)
  assert_eq(no_raise(() => runtime_query(runtime, "demo-1")).entry, "demo")
}

test "runtime: help and exec go through runtime command path" {
  reset_test_state()
  let runtime = new_runtime()
  let help = no_raise(() => runtime_run(runtime, "help", ""))
  assert_true(help.contains("Instance host-1"))
  assert_true(help.contains("spawn <entry_id:string>"))
  let exec = no_raise(() => runtime_run(runtime, "exec", "host-1 spawn demo"))
  assert_true(exec.contains("spawned demo-1"))
  assert_eq(no_raise(() => runtime_query(runtime, "demo-1")).entry, "demo")
}

test "runtime: render follows current roots" {
  reset_test_state()
  let runtime = new_runtime()
  runtime_render(runtime)
  assert_eq(query_node("entry:demo") is Some(_), true)
  assert_eq(query_node("demo-editor") is Some(_), false)
  ignore(no_raise(() => runtime_set_roots(runtime, ["demo"])))
  assert_eq(query_node("entry:demo") is Some(_), false)
  assert_eq(query_node("demo-editor") is Some(_), true)
}

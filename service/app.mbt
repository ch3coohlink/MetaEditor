fn track_batch(runtime: Runtime, cmds: Array[String]) -> Unit {
  let batch: Array[Json] = []
  for cmd in cmds {
    batch.push(@json.parse(cmd) catch { _ => null })
  }
  let _ = runtime.live_batches.try_put(Json::array(batch)) catch { _ => false }
}

fn render_host_app(runtime: Runtime) -> @src.VNode {
  let stop_service = @src.reg_action("host_stop_service", fn() { request_stop_service(runtime) })
  @src.h("div", [
    ("style", @src.S("padding: 24px; font-family: sans-serif;"))
  ], [
    @src.Node(@src.h("h1", [], [@src.Str("MetaEditor Host")])),
    @src.Node(@src.h("div", [("style", @src.S("margin-bottom: 16px; color: #555;"))], [
      @src.Str("Service is running. Use the host action below to stop it.")
    ])),
    @src.Node(@src.h("button", [
      ("onclick", stop_service),
      ("style", @src.S("padding: 10px 14px; background: #b42318; color: white; border: none; border-radius: 8px; cursor: pointer;"))
    ], [@src.Str("Stop Service")]))
  ])
}

fn render_active_app(runtime: Runtime) -> @src.Child {
  @src.Node(render_host_app(runtime))
}

pub fn init_app(runtime: Runtime) -> Unit {
  @src.init_bridge(fn(cmds) { track_batch(runtime, cmds) })
  let _ = try {
    @src.scope(fn() {
      let root = @src.h("div", [], [@src.Dyn(fn() { render_active_app(runtime) })])
      @src.emit(@src.Append(0, root.id))
    })
  } catch {
    _ => fn() {}
  }
  let _ = try { @src.flush() } catch { _ => () }
}

pub fn init_app_for_test(runtime: Runtime) -> Unit {
  init_app(runtime)
}

pub async fn host_stop_service(runtime: Runtime, settle_ms: Int) -> String {
  request_stop_service(runtime)
  @async.sleep(settle_ms)
  "host_stop_service\n"
}

// ======== app ========
fn action_callback_id(runtime: Runtime, name: String) -> Int? {
  runtime.app_actions.get(name)
}

fn track_batch(runtime: Runtime, cmds: Array[String]) -> Unit {
  let batch: Array[Json] = []
  for cmd in cmds {
    let json = @json.parse(cmd) catch { _ => null }
    if json is Array([Number(tag, ..), String(name), Number(callback_id, ..)]) {
      if tag == 8 {
        let parsed: Result[Int, _] = try? @json.from_json(callback_id.to_json())
        match parsed {
          Ok(id) => runtime.app_actions[name] = id
          Err(_) => ()
        }
      }
    }
    batch.push(json)
    runtime.ui_history.push(json)
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
  runtime.app_actions.clear()
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

pub fn ui_history_json(runtime: Runtime) -> Json {
  Json::array(runtime.ui_history)
}

pub async fn run_action(runtime: Runtime, name: String, settle_ms: Int) -> String raise {
  match action_callback_id(runtime, name) {
    Some(callback_id) => {
      @src.trigger_callback(callback_id)
      @async.sleep(settle_ms)
      "\{name}\n"
    }
    None => raise ServiceError("unknown action: \{name}")
  }
}

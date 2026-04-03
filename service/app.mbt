let host_editor : Ref[@src.Editor[@src.HostData, @src.HostSession]] = Ref::new(
  @src.default_host_editor()
)
let host_data : Ref[@src.Cel[@src.HostData]] = Ref::new(@src.cel((host_editor.val.new_data)()))
let host_session : Ref[@src.Cel[@src.HostSession]] = Ref::new(@src.cel((host_editor.val.new_session)()))
let host_dom_state : Ref[@src.DomState] = Ref::new(@src.new_dom_state())

fn track_batch(runtime: Runtime, cmds: Array[String]) -> Unit {
  let batch: Array[Json] = []
  for cmd in cmds {
    batch.push(@json.parse(cmd) catch { _ => null })
  }
  let _ = runtime.live_batches.try_put(Json::array(batch)) catch { _ => false }
}

pub fn init_app(runtime: Runtime) -> Unit {
  let editor = @src.default_host_editor(env={
    stop_service: Some(fn() { request_stop_service(runtime) }),
  })
  host_editor.val = editor
  host_data.val = @src.cel((editor.new_data)())
  host_session.val = @src.cel((editor.new_session)())
  host_dom_state.val = @src.new_dom_state()
  @src.init_bridge(host_dom_state.val, fn(cmds) { track_batch(runtime, cmds) })
}

pub fn render_app(runtime: Runtime) -> Unit {
  ignore(runtime)
  let _ = try {
    @src.scope(fn() {
      let root = @src.realize(
        host_dom_state.val,
        @src.h((host_editor.val.view)(host_data.val, host_session.val), [], []),
      )
      @src.emit(host_dom_state.val, @src.Append(0, root.id))
    })
  } catch {
    _ => fn() {}
  }
  @src.try_flush()
}

pub async fn host_stop_service(runtime: Runtime, settle_ms: Int) -> String {
  request_stop_service(runtime)
  @async.sleep(settle_ms)
  "host_stop_service\n"
}

pub async fn run_app(runtime : Runtime, cmd : String, arg : String) -> String raise {
  let out = match cmd {
    "host_stop_service" => host_stop_service(runtime, 50)
    "list_entries" => @src.host_list_entries(host_data.val.peek())
    "list_windows" => @src.host_list_windows(host_data.val.peek())
    "open_window" => @src.host_open_window(host_data.val, arg)
    "focus_window" => @src.host_focus_window(host_data.val, arg)
    "close_window" => @src.host_close_window(host_data.val, arg)
    "test_query" => (query_browser(runtime, @json.parse(arg))).stringify()
    "test_exec" => {
      let result = exec_browser(runtime, @json.parse(arg))
      sync_browser_if_connected(runtime)
      result.stringify()
    }
    _ => raise ServiceError("Unknown command: \{cmd}")
  }
  @src.try_flush()
  match cmd {
    "open_window" | "focus_window" | "close_window" =>
      sync_browser_if_connected(runtime)
    _ => ()
  }
  out
}

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

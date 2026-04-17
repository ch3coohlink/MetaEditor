pub struct PointerCaptureSession { active: Cel[Bool]; state: Cel[String] }

pub let pointer_capture: Entry[Unit, PointerCaptureSession, Unit] = {
  id: "pointer-capture", title: "Pointer Capture",
  data: () => (),
  session: _ => {{ active: cel(false), state: cel("idle") }},
  actions: (_, _, _) => (),
  init: (_, _, s, _) => {
    let page = ui("capture-page", style=(
      #| & {
      #|   display:flex;
      #|   flex-direction:column;
      #|   gap:12px;
      #|   width:100%;
      #|   height:100%;
      #|   padding:24px;
      #|   background:#eef4fb;
      #| }
    ))
    let box = ui("capture-box", style=(
      #| & {
      #|   width:120px;
      #|   height:120px;
      #|   border:2px solid #16324f;
      #|   border-radius:16px;
      #|   background:#d7e7f8;
      #| }
    ))
    let state = ui("capture-state")
    comp((_, _) => h("div", [Id(page)], [
      h("div", [Id(box),
        Event(PointerDown, _ => {
          s.active.set(true)
          s.state.set("down")
        }, EventCfg::new(capture=true)),
        Event(PointerMove, ev => {
          if s.active.get() {
            match ev {
              Mouse(v) => s.state.set("move:\{v.x},\{v.y}")
              _ => ()
            }
          }
        }, EventCfg::new()),
        Event(PointerUp, _ => {
          s.active.set(false)
          s.state.set("up")
        }, EventCfg::new(capture=true)),
      ], []),
      h("div", [Id(state)], [DynP(() => Str(s.state.get()))]),
    ]))
  },
}

fn init {
  try { pointer_capture.register() } catch { e => abort(e.to_string()) }
}

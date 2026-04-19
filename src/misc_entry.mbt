pub struct PointerCaptureSession { active: Cel[Bool]; state: Cel[String] }
let capture_page: UIMeta = ui("capture-page", style=(
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
let capture_box: UIMeta = ui("capture-box", style=(
  #| & {
  #|   width:120px;
  #|   height:120px;
  #|   border:2px solid #16324f;
  #|   border-radius:16px;
  #|   background:#d7e7f8;
  #| }
))
let capture_state: UIMeta = ui("capture-state")

pub let pointer_capture: Entry[Unit, PointerCaptureSession, Unit, Unit] = {
  id: "pointer-capture", title: "Pointer Capture",
  data: () => (),
  session: _ => {{ active: cel(false), state: cel("idle") }},
  actions: (_, _) => (),
  session_actions: (_, _, _) => (),
  init: (_, _, s, _, _) => {
    comp((_, _) => h("div", [Id(capture_page)], [
      h("div", [Id(capture_box),
        Event(PointerDown, ev => {
          s.active.set(true)
          s.state.set("down")
          drag(ev, move_ev => {
            if s.active.get() {
              match move_ev.data {
                Pointer(v) => s.state.set("move:\{v.x},\{v.y}")
                _ => ()
              }
            }
          }, () => {
            s.active.set(false)
            s.state.set("up")
          })
        }, EventCfg::new()),
      ], []),
      h("div", [Id(capture_state)], [DynP(() => Str(s.state.get()))]),
    ]))
  },
}

fn init {
  try { pointer_capture.register() } catch { e => abort(e.to_string()) }
}

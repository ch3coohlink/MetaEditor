pub struct PointerCaptureSession { active: Cel[Bool]; state: Cel[String] }
pub struct MeasureSession { state: Cel[String] }
pub struct MultiSessionData { count: Cel[Int] }
pub struct MultiSessionSession { measure: Cel[String] }
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
let measure_page: UIMeta = ui("measure-page", style=(
  #| & {
  #|   display:flex;
  #|   flex-direction:column;
  #|   gap:12px;
  #|   width:100%;
  #|   height:100%;
  #|   padding:24px;
  #|   background:#f7fafc;
  #| }
))
let measure_box: UIMeta = ui("measure-box", style=(
  #| & {
  #|   width:120px;
  #|   height:80px;
  #|   border:2px solid #16324f;
  #|   border-radius:12px;
  #|   background:#d7e7f8;
  #|   cursor:pointer;
  #| }
))
let measure_state: UIMeta = ui("measure-state")
let multi_page: UIMeta = ui("multi-page", style=(
  #| & {
  #|   display:flex;
  #|   flex-direction:column;
  #|   gap:12px;
  #|   width:100%;
  #|   height:100%;
  #|   padding:24px;
  #|   background:#f8fafc;
  #| }
))
let multi_bar: UIMeta = ui("multi-bar", style=(
  #| & {
  #|   display:flex;
  #|   gap:12px;
  #| }
))
let multi_add: UIMeta = ui("multi-add")
let multi_measure: UIMeta = ui("multi-measure", style=(
  #| & {
  #|   width:calc(100vw - 180px);
  #|   min-width:160px;
  #|   height:44px;
  #| }
))
let multi_state: UIMeta = ui("multi-state")

pub let pointer_capture: Entry[Unit, PointerCaptureSession, Unit, Unit] = {
  id: "pointer-capture", title: "Pointer Capture",
  data: () => (),
  session: _ => {{ active: cel(false), state: cel("idle") }},
  actions: (_, _) => (),
  session_actions: (_, _, _) => (),
  init: (_, _, _, s, _, _) => {
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
pub let measure_read: Entry[Unit, MeasureSession, Unit, Unit] = {
  id: "measure-read", title: "Measure Read",
  data: () => (),
  session: _ => {{ state: cel("idle") }},
  actions: (_, _) => (),
  session_actions: (_, _, _) => (),
  init: (_, read, _, s, _, _) => {
    comp((_, _) => h("div", [Id(measure_page)], [
      h("div", [Id(measure_box),
        Event(Click, ev => {
          match ev.target {
            Some(node) => read([
              { read: Box(node.id), default: Box(Some({ x: 0, y: 0, w: 0, h: 0 })) },
              { read: View(node.id), default: View(Some({ x: 0, y: 0, w: 0, h: 0 })) },
              { read: Text("14px Segoe UI", ["hello"]), default: Text(Some([0])) },
            ], values => {
              let box = match values[0] {
                Box(Some(v)) => "\{v.w}x\{v.h}"
                _ => "none"
              }
              let view = match values[1] {
                View(Some(v)) => "\{v.w}x\{v.h}"
                _ => "none"
              }
              let text = match values[2] {
                Text(Some([v])) => v.to_string()
                _ => "0"
              }
              s.state.set("box=\{box} view=\{view} text=\{text}")
            })
            None => ()
          }
        }, EventCfg::new()),
      ], []),
      h("div", [Id(measure_state)], [DynP(() => Str(s.state.get()))]),
    ]))
  },
}
pub let multi_session: Entry[MultiSessionData, MultiSessionSession, Unit, Unit] = {
  id: "multi-session", title: "Multi Session",
  data: () => {{ count: cel(0) }},
  session: _ => {{ measure: cel("idle") }},
  actions: (_, _) => (),
  session_actions: (_, _, _) => (),
  init: (_, read, d, s, _, _) => {
    comp((_, _) => h("div", [Id(multi_page)], [
      h("div", [Id(multi_bar)], [
        h("button", [Id(multi_add),
          Event(Click, _ => d.count.set(d.count.get() + 1), EventCfg::new()),
        ], [Str("add")]),
        h("button", [Id(multi_measure),
          Event(Click, ev => {
            match ev.target {
              Some(node) => read([
                { read: View(node.id), default: View(Some({ x: 0, y: 0, w: 0, h: 0 })) },
                { read: Text("14px Segoe UI", ["count=\{d.count.get()}"]), default: Text(Some([0])) },
              ], values => {
                let view = match values[0] {
                  View(Some(v)) => "\{v.w}x\{v.h}"
                  _ => "0x0"
                }
                let text = match values[1] {
                  Text(Some([v])) => v.to_string()
                  _ => "0"
                }
                s.measure.set("view=\{view} text=\{text}")
              })
              None => ()
            }
          }, EventCfg::new()),
        ], [Str("measure")]),
      ]),
      h("div", [Id(multi_state)], [DynP(() => Str("count=\{d.count.get()} \{s.measure.get()}"))]),
    ]))
  },
}

fn init {
  try { pointer_capture.register() } catch { e => abort(e.to_string()) }
  try { measure_read.register() } catch { e => abort(e.to_string()) }
  try { multi_session.register() } catch { e => abort(e.to_string()) }
}

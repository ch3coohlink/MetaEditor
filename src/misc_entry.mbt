pub struct PointerCaptureSession { active: Cel[Bool]; state: Cel[String] }
pub struct MeasureSession { state: Cel[String] }
pub struct MultiSessionData { count: Cel[Int] }
pub struct MultiSessionSession { measure: Cel[String] }
pub struct EventProbeSession {
  wide: Cel[Bool]
  scroll: Cel[String]
  resize: Cel[String]
  composition: Cel[String]
}
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
let multi_measure_box: UIMeta = ui("multi-measure-box", style=(
  #| & {
  #|   width:240px;
  #|   height:44px;
  #|   border:2px solid #16324f;
  #|   border-radius:10px;
  #|   background:#d7e7f8;
  #| }
))
let multi_state: UIMeta = ui("multi-state")
let probe_page: UIMeta = ui("probe-page", style=(
  #| & {
  #|   display:flex;
  #|   flex-direction:column;
  #|   gap:12px;
  #|   width:100%;
  #|   height:100%;
  #|   padding:24px;
  #|   background:#f6f9fc;
  #| }
))
let probe_actions: UIMeta = ui("probe-actions", style=(
  #| & {
  #|   display:flex;
  #|   gap:12px;
  #|   align-items:flex-start;
  #| }
))
let probe_resize_btn: UIMeta = ui("probe-resize-btn")
let probe_resize_box: UIMeta = ui("probe-resize-box", style=(
  #| & {
  #|   height:32px;
  #|   border:2px solid #16324f;
  #|   border-radius:10px;
  #|   background:#d7e7f8;
  #| }
))
let probe_scroll_box: UIMeta = ui("probe-scroll-box", style=(
  #| & {
  #|   width:160px;
  #|   height:56px;
  #|   overflow:auto;
  #|   border:2px solid #16324f;
  #|   border-radius:10px;
  #|   background:#ffffff;
  #| }
))
let probe_scroll_fill: UIMeta = ui("probe-scroll-fill", style=(
  #| & {
  #|   height:140px;
  #| }
))
let probe_input: UIMeta = ui("probe-input")
let probe_scroll_state: UIMeta = ui("probe-scroll-state")
let probe_resize_state: UIMeta = ui("probe-resize-state")
let probe_composition_state: UIMeta = ui("probe-composition-state")

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
        h("div", [Id(multi_measure_box),
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
        ], []),
      ]),
      h("div", [Id(multi_state)], [DynP(() => Str("count=\{d.count.get()} \{s.measure.get()}"))]),
    ]))
  },
}
pub let event_probe: Entry[Unit, EventProbeSession, Unit, Unit] = {
  id: "event-probe", title: "Event Probe",
  data: () => (),
  session: _ => {{
    wide: cel(false),
    scroll: cel("0"),
    resize: cel("idle"),
    composition: cel("idle"),
  }},
  actions: (_, _) => (),
  session_actions: (_, _, _) => (),
  init: (_, read, _, s, _, _) => {
    comp((_, _) => h("div", [Id(probe_page)], [
      h("div", [Id(probe_actions)], [
        h("button", [Id(probe_resize_btn),
          Event(Click, _ => s.wide.set(!s.wide.get()), EventCfg::new()),
        ], [Str("resize")]),
        h("div", [Id(probe_resize_box),
          Style("width", Dynamic(() => String(if s.wide.get() { "140px" } else { "80px" }))),
          Event(Resize, ev => {
            match ev.target {
              Some(node) => read([
                { read: View(node.id), default: View(Some({ x: 0, y: 0, w: 0, h: 0 })) },
              ], values => {
                let size = match values[0] {
                  View(Some(v)) => "\{v.w}x\{v.h}"
                  _ => "0x0"
                }
                s.resize.set(size)
              })
              None => ()
            }
          }, EventCfg::new()),
        ], []),
      ]),
      h("div", [Id(probe_scroll_box),
        Event(Scroll, ev => {
          match ev.target {
            Some(node) => read([
              { read: Scroll(node.id), default: Scroll(Some({ x: 0, y: 0, w: 0, h: 0 })) },
            ], values => {
              let top = match values[0] {
                Scroll(Some(v)) => v.y.to_string()
                _ => "0"
              }
              s.scroll.set(top)
            })
            None => ()
          }
        }, EventCfg::new()),
      ], [
        h("div", [Id(probe_scroll_fill)], [Str("scroll")]),
      ]),
      h("input", [Id(probe_input),
        Event(CompositionStart, _ => s.composition.set("start"), EventCfg::new()),
        Event(CompositionEnd, _ => s.composition.set("end"), EventCfg::new()),
        Event(CompositionCancel, _ => s.composition.set("cancel"), EventCfg::new()),
      ], []),
      h("div", [Id(probe_scroll_state)], [DynP(() => Str("scroll=\{s.scroll.get()}"))]),
      h("div", [Id(probe_resize_state)], [DynP(() => Str("resize=\{s.resize.get()}"))]),
      h("div", [Id(probe_composition_state)], [DynP(() => Str("composition=\{s.composition.get()}"))]),
    ]))
  },
}

fn init {
  try { pointer_capture.register() } catch { e => abort(e.to_string()) }
  try { measure_read.register() } catch { e => abort(e.to_string()) }
  try { multi_session.register() } catch { e => abort(e.to_string()) }
  try { event_probe.register() } catch { e => abort(e.to_string()) }
}

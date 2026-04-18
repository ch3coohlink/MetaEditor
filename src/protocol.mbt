pub enum EventKind { Click; Input; Change; Focus; Blur; KeyDown; KeyUp;
  PointerDown; PointerUp; PointerMove; PointerCancel } derive(Eq, FromJson, ToJson)
pub impl ToString for EventKind with to_string(self) -> String {
  match self.to_json() { String(v) => "on" + to_lower_case(v); _ => "" }
}
pub struct EventCfg { prevent: Bool; stop: Bool; capture: Bool } derive(ToJson)
pub fn EventCfg::new(prevent~: Bool = false, stop~: Bool = false,
  capture~: Bool = false) -> EventCfg {{ prevent, stop, capture }}
pub struct Modify { ctrl: Bool; shift: Bool; alt: Bool; meta: Bool } derive(FromJson, ToJson)
pub fn Modify::new(ctrl~: Bool = false, shift~: Bool = false, alt~: Bool = false,
  meta~: Bool = false) -> Modify {{ ctrl, shift, alt, meta }}
pub struct MouseData { mod: Modify; x: Int; y: Int; button: Int; buttons: Int; pointer_id: Int } derive(FromJson, ToJson)
pub struct KeyData { mod: Modify; key: String; code: String } derive(FromJson, ToJson)
pub struct InputData { value: String } derive(FromJson, ToJson)
pub enum EventData { Mouse(MouseData); Key(KeyData); Input(InputData) } derive(FromJson, ToJson)
pub struct Event { mut target: Node?; kind: EventKind; data: EventData }
pub fn Event::new(kind: EventKind, data: EventData) -> Event {{ kind, target: None, data }}
pub fn Event::pointer_id(self: Event) -> Int { match self.data { Mouse(v) => v.pointer_id; _ => 0 } }

struct ListenerObj { id: Int; nid: Int; kind: EventKind; cfg: EventCfg; f: (Event) -> Unit raise; dom: Dom }
pub impl ToJson for ListenerObj with to_json(l) -> Json { (l.kind, l.cfg, l.nid, l.id).to_json() }
pub fn ListenerObj::off(self: ListenerObj) -> Unit raise { self.dom.unbind_listener(self) }
pub fn Node::on(self: Node, kind: EventKind, f: (Event) -> Unit raise, cfg: EventCfg) -> ListenerObj raise {
  self.dom().bind_listener(self, kind, f, cfg)
}
pub fn Node::off(self: Node, handle: ListenerObj) -> Unit raise {
  self.dom().unbind_listener(handle)
}
pub fn Node::capture_pointer(self: Node, pointer_id: Int) -> Unit raise {
  guard self.data is Element(_) else { fail_non_elm("capture pointer") }
  self.dom().cmd(Pointer({ id: self.id, pointer_id, capture: true }))
}
pub fn Node::release_pointer(self: Node, pointer_id: Int) -> Unit raise {
  guard self.data is Element(_) else { fail_non_elm("release pointer") }
  self.dom().cmd(Pointer({ id: self.id, pointer_id, capture: false }))
}
pub fn Dom::bind_listener(d: Dom, node: Node, kind: EventKind,
  f: (Event) -> Unit raise, cfg: EventCfg) -> ListenerObj raise {
  let listener = { id: (d.nid)(), nid: node.id, kind, cfg, f, dom: d }
  match node.data {
    Element(el) => {
      let ls = if el.listeners is Some(ls) { ls }
      else { let ls = Map::new(); el.listeners = Some(ls); ls }
      ls.set(listener.id, listener)
      d.cmd(Listener({ nid: node.id, id: listener.id, kind, cfg, bind: true }))
      listener
    }
    _ => { fail_non_elm("bind listener"); fail("") }
  }
}
pub fn Dom::unbind_listener(d: Dom, listener: ListenerObj) -> Unit raise {
  match d.node(listener.nid).data {
    Element(el) => match el.listeners {
      Some(ls) => match ls.get(listener.id) {
        Some(l) => {
          ls.remove(l.id)
          d.cmd(Listener({ nid: l.nid, id: l.id, kind: l.kind, cfg: l.cfg, bind: false }))
        }
        None => fail("target listener not found in element")
      }
      None => fail("target listener not found in element")
    }
    _ => fail_non_elm("unbind listener")
  }
}

pub enum NodeQuery { Node; Text; Attr(String); Prop(String); Style(String) } derive(FromJson, ToJson)
pub enum NodeValue { Node(Node); Text(String); Attr(String, String)
  Prop(String, String); Style(String, String) } derive(ToJson)
pub fn Node::query(self: Node, query: NodeQuery) -> NodeValue raise {
  fn str_text(v: StrValue) -> String { match v { Empty => ""; String(v) => v } }
  fn js_text(v: JsValue) -> String {
    match v { String(v) => v; Int(v) => v.to_string(); Float(v) => v.to_string(); _ => "" }
  }
  match query {
    Node => Node(self)
    Text => match self.data {
      Text(t) => Text(t)
      Element(_) => Text(flat_map(self.children(), child => match child.data {
        Text(t) => [t]; _ => []
      }).iter().join(""))
      Anchor(_) => Text("")
    }
    Attr(key) => match self.data {
      Element({ xmls: Some(xmls), .. }) => Attr(key, str_text(xmls.get(key).unwrap_or(Empty)))
      Element(_) => Attr(key, "")
      _ => fail("query attr expects element node")
    }
    Prop(key) => match self.data {
      Element({ props: Some(props), .. }) => Prop(key, js_text(props.get(key).unwrap_or(Empty)))
      Element(_) => Prop(key, "")
      _ => fail("query prop expects element node")
    }
    Style(key) => match self.data {
      Element({ styles: Some(styles), .. }) => Style(key, str_text(styles.get(key).unwrap_or(Empty)))
      Element({ props: Some(props), .. }) => Style(key, js_text(props.get("style").unwrap_or(Empty)))
      Element(_) => Style(key, "")
      _ => fail("query style expects element node")
    }
  }
}
pub fn Node::dispatch(self: Node, dom: Dom, ev: Event) -> Unit raise {
  ev.target = Some(self)
  match self.data {
    Element({ listeners: Some(ls), .. }) => {
      let ids = []
      for entry in ls { if entry.1.kind == ev.kind { ids.push(entry.0) } }
      if ids.is_empty() { fail("listener not found: \{ev.kind.to_string()}") }
      for id in ids {
        match ls.get(id) {
          Some(l) => { try { (l.f)(ev); flush() } catch { e => dom.report("\{e}") } }
          None => ()
        }
      }
    }
    Element(_) => fail("listener not found: \{ev.kind.to_string()}")
    _ => fail("dispatch expects element node")
  }
}

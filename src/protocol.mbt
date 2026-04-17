pub enum EventKind { Click; Input; Change; Focus; Blur; KeyDown; KeyUp;
  PointerDown; PointerUp; PointerMove } derive(FromJson, ToJson)
pub struct EventCfg { prevent: Bool; stop: Bool; capture: Bool } derive(ToJson)
pub fn EventCfg::new(prevent~: Bool = false, stop~: Bool = false,
  capture~: Bool = false) -> EventCfg {{ prevent, stop, capture }}
pub struct Modify { ctrl: Bool; shift: Bool; alt: Bool; meta: Bool } derive(FromJson, ToJson)
pub struct BaseEvent { kind: EventKind; } derive(FromJson, ToJson)
pub struct MouseEvent { kind: EventKind; mod: Modify; x: Int; y: Int; button: Int; buttons: Int } derive(FromJson, ToJson)
pub struct KeyEvent { kind: EventKind; mod: Modify; key: String; code: String } derive(FromJson, ToJson)
pub struct InputEvent { kind: EventKind; value: String } derive(FromJson, ToJson)
pub enum DomEvent { Base(BaseEvent); Mouse(MouseEvent); Key(KeyEvent); Input(InputEvent) }
  derive(FromJson, ToJson)
pub impl ToString for EventKind with to_string(self) -> String {
  match self.to_json() { String(v) => "on" + to_lower_case(v); _ => "" }
}
pub fn DomEvent::kind(self: DomEvent) -> EventKind {
  match self { Base(v) => v.kind; Mouse(v) => v.kind; Key(v) => v.kind; Input(v) => v.kind }
}
struct Listener { kind: EventKind; cfg: EventCfg; id: Int; f: (DomEvent) -> Unit raise }
pub impl ToJson for Listener with to_json(self) -> Json {
  (self.kind, self.cfg, self.id).to_json()
}

pub enum NodeQuery { Node; Text; Attr(String); Prop(String); Style(String) } derive(FromJson, ToJson)
pub enum NodeValue { Node(Node); Text(String); Attr(String, String);
  Prop(String, String); Style(String, String) }
pub impl ToJson for NodeValue with to_json(self) -> Json {
  fn text_of(node: Node) -> String {
    match node.data {
      Text(t) => t; Anchor(_) => ""
      Element(_) => flat_map(node.children(), child =>
        match child.data { Text(t) => [t]; _ => [] }).iter().join("")
    }
  }
  fn attr_map(node: Node) -> Json {
    match node.data {
      Element({ xmls: Some(xmls), .. }) => {
        let a = Map::new()
        for entry in xmls { a.set(entry.0, entry.1.to_json()) }
        Json::object(a)
      }; _ => Json::object({})
    }
  }
  match self {
    Node(node) => match node.data {
      Text(_) => {{ "kind": "text", "id": node.id, "text": text_of(node) }}
      Anchor(_) => {{ "kind": "anchor", "id": node.id, "text": "" }}
      Element(el) => {{ "kind": "element", "id": node.id, "tag": el.tag,
        "text": text_of(node), "attrs": attr_map(node) }}
    }
    Text(text) => { "kind": "text", "text": text }
    Attr(key, value) => { "kind": "attr", "key": key, "value": value }
    Prop(key, value) => { "kind": "prop", "key": key, "value": value }
    Style(key, value) => { "kind": "style", "key": key, "value": value }
  }
}
pub fn Node::query(self: Node, query: NodeQuery) -> NodeValue raise {
  fn str_text(v: StrValue) -> String { match v { Empty => ""; String(v) => v } }
  fn js_text(v: JsValue) -> String {
    match v {
      Empty => ""; String(v) => v; Listener({ kind, .. }) => kind.to_string()
      Int(v) => v.to_string(); Float(v) => v.to_string()
    }
  }
  match query {
    Node => Node(self)
    Text => match self.data {
      Text(t) => Text(t)
      Element(_) => Text(flat_map(self.children(), child => match child.data {
        Text(t) => [t]
        _ => []
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
pub fn Node::dispatch(self: Node, dom: Dom, ev: DomEvent) -> Unit raise {
  let key = ev.kind().to_string()
  match self.data {
    Element({ props: Some(props), .. }) => match props.get(key) {
      Some(Listener(l)) => { try { (l.f)(ev); flush() } catch { e => dom.report("\{e}") } }
      _ => fail("listener not found: \{key}")
    }
    Element(_) => fail("listener not found: \{key}")
    _ => fail("dispatch expects element node")
  }
}

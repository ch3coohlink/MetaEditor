pub enum EventKind { Click; Input; Change; Focus; Blur; KeyDown; KeyUp;
  PointerDown; PointerUp; PointerMove } derive(Eq)
pub struct EventCfg { capture: Bool; passive: Bool; prevent: Bool; stop: Bool } derive(Eq, ToJson)
pub fn EventCfg::new(capture~: Bool = false, passive~: Bool = false, prevent~: Bool = false,
  stop~: Bool = false) -> EventCfg {{ capture, passive, prevent, stop }}
pub struct Modify { ctrl: Bool; shift: Bool; alt: Bool; meta: Bool } derive(Eq)
pub struct BaseEvent { kind: EventKind; } derive(Eq)
pub struct MouseEvent { kind: EventKind; mod: Modify; x: Int; y: Int; button: Int; buttons: Int } derive(Eq)
pub struct KeyEvent { kind: EventKind; mod: Modify; key: String; code: String } derive(Eq)
pub struct InputEvent { kind: EventKind; value: String } derive(Eq)
pub enum DomEvent { Base(BaseEvent); Mouse(MouseEvent); Key(KeyEvent); Input(InputEvent) } derive(Eq)
pub impl ToString for EventKind with to_string(self) -> String {
  match self { Click => "click"; Input => "input"; Change => "change"; Focus => "focus"; 
    Blur => "blur"; KeyDown => "keydown"; KeyUp => "keyup"; PointerDown => "pointerdown";
    PointerUp => "pointerup"; PointerMove => "pointermove" } }
pub fn DomEvent::kind(self: DomEvent) -> EventKind {
  match self { Base(v) => v.kind; Mouse(v) => v.kind; Key(v) => v.kind; Input(v) => v.kind }
}
struct Listener { id: Int; cfg: EventCfg } derive(Eq, ToJson)
struct RegisteredListener { kind: EventKind; f: (DomEvent) -> Unit }

pub enum NodeQuery { Node; Text; Attr(String); Prop(String); Style(String) }
pub enum NodeValue { Node(Node); Text(String); Attr(String, String);
  Prop(String, String); Style(String, String) }
fn[T] badnq(path: @json.JsonPath, msg: String) -> T raise @json.JsonDecodeError {
  raise @json.JsonDecodeError((path, "NodeQuery::from_json: \{msg}")) }
impl @json.FromJson for NodeQuery with from_json(json, path) {
  match json {
    String("node") => Node
    String("text") => Text
    String(kind) => badnq(path, "invalid kind \{kind}")
    Object(fields) => {
      let kind = match fields.get("kind") {
        Some(String(kind)) => kind
        _ => badnq(path, "missing kind")
      }
      match kind {
        "node" => Node
        "text" => Text
        "attr" => match fields.get("value") {
          Some(String(value)) if value != "" => Attr(value)
          Some(_) => badnq(path, "invalid value")
          None => badnq(path, "attr query expects value")
        }
        "prop" => match fields.get("value") {
          Some(String(value)) if value != "" => Prop(value)
          Some(_) => badnq(path, "invalid value")
          None => badnq(path, "prop query expects value")
        }
        "style" => match fields.get("value") {
          Some(String(value)) if value != "" => Style(value)
          Some(_) => badnq(path, "invalid value")
          None => badnq(path, "style query expects value")
        }
        _ => badnq(path, "invalid kind \{kind}")
      }
    }
    _ => badnq(path, "expected string or object")
  }
}
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
pub fn Node::get(self: Node, query: NodeQuery) -> NodeValue raise {
  fn str_text(v: StrValue) -> String { match v { Empty => ""; String(v) => v } }
  fn js_text(v: JsValue) -> String {
    match v {
      Empty => ""; String(v) => v; Listener({ id, .. }) => id.to_string()
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
  let key = "on" + ev.kind().to_string()
  match self.data {
    Element({ props: Some(props), .. }) => match props.get(key) {
      Some(Listener({ id, .. })) => match dom.listeners.get(id) {
        Some(listener) => { (listener.f)(ev); flush() }
        None => fail("listener not found: \{id}")
      }
      _ => fail("listener not found: \{key}")
    }
    Element(_) => fail("listener not found: \{key}")
    _ => fail("dispatch expects element node")
  }
}

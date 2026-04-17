pub enum EventKind { Click; Input; Change; Focus; Blur; KeyDown; KeyUp;
  PointerDown; PointerUp; PointerMove } derive(ToJson)
pub struct EventCfg { capture: Bool; passive: Bool; prevent: Bool; stop: Bool } derive(ToJson)
pub fn EventCfg::new(capture~: Bool = false, passive~: Bool = false, prevent~: Bool = false,
  stop~: Bool = false) -> EventCfg {{ capture, passive, prevent, stop }}
pub struct Modify { ctrl: Bool; shift: Bool; alt: Bool; meta: Bool } derive(ToJson)
pub struct BaseEvent { kind: EventKind; } derive(ToJson)
pub struct MouseEvent { kind: EventKind; mod: Modify; x: Int; y: Int; button: Int; buttons: Int } derive(ToJson)
pub struct KeyEvent { kind: EventKind; mod: Modify; key: String; code: String } derive(ToJson)
pub struct InputEvent { kind: EventKind; value: String } derive(ToJson)
pub enum DomEvent { Base(BaseEvent); Mouse(MouseEvent); Key(KeyEvent); Input(InputEvent) } derive(ToJson)
pub impl ToString for EventKind with to_string(self) -> String {
  match self { Click => "click"; Input => "input"; Change => "change"; Focus => "focus"; 
    Blur => "blur"; KeyDown => "keydown"; KeyUp => "keyup"; PointerDown => "pointerdown";
    PointerUp => "pointerup"; PointerMove => "pointermove" } }
pub fn DomEvent::kind(self: DomEvent) -> EventKind {
  match self { Base(v) => v.kind; Mouse(v) => v.kind; Key(v) => v.kind; Input(v) => v.kind }
}
struct Listener { kind: EventKind; cfg: EventCfg; f: (DomEvent) -> Unit raise }
pub impl ToJson for Listener with to_json(self) -> Json {{
  "kind": self.kind.to_string(), "cfg": self.cfg }}

pub impl FromJson for EventKind with from_json(json, path) {
  match json {
    String("click") => Click
    String("input") => Input
    String("change") => Change
    String("focus") => Focus
    String("blur") => Blur
    String("keydown") => KeyDown
    String("keyup") => KeyUp
    String("pointerdown") => PointerDown
    String("pointerup") => PointerUp
    String("pointermove") => PointerMove
    String(kind) => bad_json(path, "invalid kind \{kind}")
    _ => bad_json(path, "expected string")
  }
}
pub impl FromJson for Modify with from_json(json, path) {
  match json {
    Object(fields) => {
      let ctrl = match fields.get("ctrl") { Some(True) => true; Some(False) => false; _ => false }
      let shift = match fields.get("shift") { Some(True) => true; Some(False) => false; _ => false }
      let alt = match fields.get("alt") { Some(True) => true; Some(False) => false; _ => false }
      let meta = match fields.get("meta") { Some(True) => true; Some(False) => false; _ => false }
      { ctrl, shift, alt, meta }
    }
    _ => bad_json(path, "expected object")
  }
}
pub impl FromJson for DomEvent with from_json(json, path) {
  fn intf(fields: Map[String, Json], key: String) -> Int {
    match fields.get(key) { Some(Number(v, ..)) => v.to_int(); _ => 0 }
  }
  match json {
    Object(fields) => {
      let kind: EventKind = match fields.get("kind") {
        Some(v) => from_json(v, path=path.add_key("kind"))
        None => bad_json(path, "missing kind")
      }
      match kind {
        Click | Change | Focus | Blur => Base({ kind: kind })
        Input => match fields.get("value") {
          Some(String(value)) => Input({ kind, value })
          Some(_) => bad_json(path, "invalid value")
          None => bad_json(path, "missing value")
        }
        KeyDown | KeyUp => {
          let mod = match fields.get("mod") {
            Some(v) => from_json(v, path=path.add_key("mod"))
            None => { ctrl: false, shift: false, alt: false, meta: false }
          }
          let key = match fields.get("key") { Some(String(v)) => v; _ => "" }
          let code = match fields.get("code") { Some(String(v)) => v; _ => "" }
          Key({ kind, mod, key, code })
        }
        PointerDown | PointerUp | PointerMove => {
          let mod = match fields.get("mod") {
            Some(v) => from_json(v, path=path.add_key("mod"))
            None => { ctrl: false, shift: false, alt: false, meta: false }
          }
          Mouse({
            kind,
            mod,
            x: intf(fields, "x"),
            y: intf(fields, "y"),
            button: intf(fields, "button"),
            buttons: intf(fields, "buttons"),
          })
        }
      }
    }
    _ => bad_json(path, "expected object")
  }
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
  let key = "on" + ev.kind().to_string()
  match self.data {
    Element({ props: Some(props), .. }) => match props.get(key) {
      Some(Listener(l)) => { try { (l.f)(ev); flush() } catch { e => dom.report("\{e}") } }
      _ => fail("listener not found: \{key}")
    }
    Element(_) => fail("listener not found: \{key}")
    _ => fail("dispatch expects element node")
  }
}

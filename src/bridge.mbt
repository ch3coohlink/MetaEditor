pub enum NodeQuery { Node; Text; Attr(String); Prop(String); Style(String) }
pub enum NodeValue {
  Node(Node); Text(String); Attr(String, String); Prop(String, String); Style(String, String)
}
fn[T] bad_node_query(path: @json.JsonPath, msg: String) -> T raise @json.JsonDecodeError {
  raise @json.JsonDecodeError((path, "NodeQuery::from_json: \{msg}"))
}
impl @json.FromJson for NodeQuery with from_json(json, path) {
  match json {
    String("node") => Node
    String("text") => Text
    String(kind) => bad_node_query(path, "invalid kind \{kind}")
    Object(fields) => {
      let kind = match fields.get("kind") {
        Some(String(kind)) => kind
        _ => bad_node_query(path, "missing kind")
      }
      match kind {
        "node" => Node
        "text" => Text
        "attr" => match fields.get("value") {
          Some(String(value)) if value != "" => Attr(value)
          Some(_) => bad_node_query(path, "invalid value")
          None => bad_node_query(path, "attr query expects value")
        }
        "prop" => match fields.get("value") {
          Some(String(value)) if value != "" => Prop(value)
          Some(_) => bad_node_query(path, "invalid value")
          None => bad_node_query(path, "prop query expects value")
        }
        "style" => match fields.get("value") {
          Some(String(value)) if value != "" => Style(value)
          Some(_) => bad_node_query(path, "invalid value")
          None => bad_node_query(path, "style query expects value")
        }
        _ => bad_node_query(path, "invalid kind \{kind}")
      }
    }
    _ => bad_node_query(path, "expected string or object")
  }
}
pub impl ToJson for NodeValue with to_json(self) -> Json {
  fn text_of(node: Node) -> String {
    match node.data {
      Text(t) => t
      Element(_) => flat_map(node.children(), child => match child.data {
        Text(t) => [t]
        _ => []
      }).iter().join("")
      Anchor(_) => ""
    }
  }
  fn attr_map(node: Node) -> Json {
    match node.data {
      Element({ xmls: Some(xmls), .. }) => {
        let out : Map[String, Json] = Map::new()
        for entry in xmls {
          out.set(entry.0, match entry.1 {
            Empty => null
            String(v) => Json::string(v)
          })
        }
        Json::object(out)
      }
      _ => Json::object(Map::new())
    }
  }
  match self {
    Node(node) => match node.data {
      Text(_) => {{
          "kind": "text",
          "id": node.id,
          "text": text_of(node),
      }}
      Anchor(_) => {{
          "kind": "anchor",
          "id": node.id,
          "text": "",
      }}
      Element(el) => {{
          "kind": "element",
          "id": node.id,
          "tag": el.tag,
          "text": text_of(node),
          "attrs": attr_map(node),
      }}
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
      Empty => ""; String(v) => v; Listener({ id }) => id.to_string()
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

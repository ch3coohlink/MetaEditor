pub struct MockNode {
  id: Int
  tag: String
  mut text: String
  mut parent: Int?
  children: Array[Int]
  attrs: Map[String, String]
  styles: Map[String, String]
  props: Map[String, String?]
}

pub struct MockBrowser {
  nodes: Map[Int, MockNode]
  roots: Array[Int]
  head: Array[Int]
  mut focused: Int?
}

pub enum UiRequest {
  Query(Int, String, String)
  Trigger(Int, UiTriggerKind)
  Sync
}

pub enum UiTriggerKind {
  Click(String)
  Input(String)
  Key(String, String, String, Bool, Bool, Bool, Bool)
  DragTo(Int)
}

pub(all) struct UiNodeSnapshot {
  id: Int
  kind: String
  tag: String
  text: String
  value: String
  checked: Bool
  focused: Bool
  visible: Bool
}

pub(all) enum UiQueryResult {
  Node(UiNodeSnapshot)
  Text(Int, String)
  Style(Int, String, String)
}

pub(all) enum UiTriggerResult {
  Pointer(Int, String)
  Input(Int)
  Key(Int, String)
  DragTo(Int, Int)
  Focus(Int)
  Blur(Int)
  ScrollIntoView(Int)
}

pub(all) enum UiResponse {
  Query(UiQueryResult)
  Trigger(UiTriggerResult)
  Sync
}

pub fn ui_query_request(id: Int, kind: String, value: String) -> UiRequest {
  Query(id, kind, value)
}

pub fn ui_trigger_click(id: Int, kind: String) -> UiRequest {
  Trigger(id, Click(kind))
}

pub fn ui_trigger_input(id: Int, text: String) -> UiRequest {
  Trigger(id, Input(text))
}

pub fn ui_trigger_key(
  id: Int,
  key: String,
  key_event? : String = "press",
  code? : String = "",
  ctrl_key? : Bool = false,
  shift_key? : Bool = false,
  alt_key? : Bool = false,
  meta_key? : Bool = false,
) -> UiRequest {
  Trigger(id, Key(key, key_event, code, ctrl_key, shift_key, alt_key, meta_key))
}

pub fn ui_trigger_drag_to(id: Int, target_id: Int) -> UiRequest {
  Trigger(id, DragTo(target_id))
}

pub fn ui_sync_request() -> UiRequest {
  Sync
}

suberror MockDomErr {
  Fail(String)
} derive(Show)

fn mock_dom_err(message: String) -> MockDomErr {
  MockDomErr::Fail(message)
}

pub fn new_mock_browser() -> MockBrowser {{
  nodes: Map::new(),
  roots: [],
  head: [],
  focused: None,
}}


fn child_list(browser: MockBrowser, parent: Int) -> Array[Int] {
  if parent == dom_root_body { return browser.roots }
  if parent == dom_root_head { return browser.head }
  match browser.nodes.get(parent) {
    Some(node) => node.children
    None => abort("missing parent: \{parent}")
  }
}

fn detach_mock_node(browser: MockBrowser, id: Int) -> Unit {
  if browser.nodes.get(id) is Some(node) {
    if node.parent is Some(parent) {
      let children = child_list(browser, parent)
      let mut hit = -1
      for i, v in children {
        if hit < 0 && v == id { hit = i }
      }
      if hit >= 0 { ignore(children.remove(hit)) }
      node.parent = None
    }
  }
}

fn append_mock_node(browser: MockBrowser, parent: Int, id: Int) -> Unit {
  detach_mock_node(browser, id)
  child_list(browser, parent).push(id)
  match browser.nodes.get(id) {
    Some(node) => node.parent = Some(parent)
    None => abort("missing child: \{id}")
  }
}

fn insert_before_mock_node(browser: MockBrowser, parent: Int, id: Int, ref_id: Int) -> Unit {
  detach_mock_node(browser, id)
  let xs = child_list(browser, parent)
  let mut pos = xs.length()
  for i = 0; i < xs.length(); i = i + 1 {
    if pos == xs.length() && xs[i] == ref_id {
      pos = i
    }
  }
  if pos == xs.length() { xs.push(id) } else { xs.insert(pos, id) }
  match browser.nodes.get(id) {
    Some(node) => node.parent = Some(parent)
    None => abort("missing child: \{id}")
  }
}

fn remove_mock_subtree(browser: MockBrowser, id: Int) -> Unit {
  let child_ids = match browser.nodes.get(id) {
    Some(node) => node.children.copy()
    None => []
  }
  for child in child_ids {
    remove_mock_subtree(browser, child)
  }
  detach_mock_node(browser, id)
  browser.nodes.remove(id)
  if browser.focused == Some(id) { browser.focused = None }
}

fn apply_mock_cmd(browser: MockBrowser, cmd: DomCmd) -> Unit {
  match cmd {
    Create(id, tag, _) => browser.nodes.set(id, {
      id,
      tag,
      text: "",
      parent: None,
      children: [],
      attrs: Map::new(),
      styles: Map::new(),
      props: Map::new(),
    })
    Text(id, text) =>
      if browser.nodes.get(id) is Some(node) { node.text = text }
    Attr(id, key, value) =>
      if browser.nodes.get(id) is Some(node) {
        match value {
          DomValue::Empty => ignore(node.attrs.remove(key))
          DomValue::String(value) => node.attrs.set(key, value)
        }
      }
    Append(parent, child) => append_mock_node(browser, parent, child)
    Remove(id) => remove_mock_subtree(browser, id)
    Listen(_, _) => ()
    InsertBefore(parent, child, ref_id) => insert_before_mock_node(browser, parent, child, ref_id)
    Style(id, key, value) =>
      if browser.nodes.get(id) is Some(node) {
        match value {
          DomValue::Empty => ignore(node.styles.remove(key))
          DomValue::String(value) => node.styles.set(key, value)
        }
      }
    Prop(id, key, value) =>
      if browser.nodes.get(id) is Some(node) {
        match value {
          DomValue::Empty => node.props.set(key, None)
          DomValue::String(value) => node.props.set(key, Some(value))
        }
      }
  }
}

pub fn apply_mock_cmds(browser: MockBrowser, cmds: Array[DomCmd]) -> Unit {
  for cmd in cmds {
    apply_mock_cmd(browser, cmd)
  }
}

fn find_mock_node_by_ui(browser: MockBrowser, ui_id: String) -> MockNode? {
  match query_node(ui_id) {
    Some(id) => browser.nodes.get(id)
    None => None
  }
}

fn mock_node_text(browser: MockBrowser, id: Int) -> String {
  match browser.nodes.get(id) {
    Some(node) => {
      let out = StringBuilder::new()
      out.write_string(node.text)
      for child in node.children {
        out.write_string(mock_node_text(browser, child))
      }
      out.to_string()
    }
    None => ""
  }
}

fn mock_count(_browser: MockBrowser, target: String) -> Int {
  match query_node(target) {
    Some(_) => 1
    None => 0
  }
}

fn mock_exists(browser: MockBrowser, target: String) -> Bool {
  mock_count(browser, target) > 0
}

fn mock_text(browser: MockBrowser, target: String) -> String {
  match find_mock_node_by_ui(browser, target) {
    Some(node) => mock_node_text(browser, node.id)
    None => ""
  }
}

fn mock_event_name(action: String) -> String {
  match action {
    "click" => "onclick"
    "dblclick" => "ondblclick"
    "keydown" => "onkeydown"
    "keyup" => "onkeyup"
    "input" => "oninput"
    _ => if has_prefix(action, "on") { action } else { "on\{action}" }
  }
}

fn mock_node_visible(node: MockNode) -> Bool {
  node.styles.get("display") != Some("none") &&
  node.styles.get("visibility") != Some("hidden") &&
  node.styles.get("opacity") != Some("0")
}

fn ui_result_object(
  json: Json,
  path: @json.JsonPath,
  owner: String
) -> Map[String, Json] raise @json.JsonDecodeError {
  guard json is Object(fields) else {
    raise @json.JsonDecodeError((path, "\{owner}: expected object"))
  }
  fields
}

fn ui_result_string(json: Json, key: String) -> String? {
  match json {
    Object(fields) => match fields.get(key) { Some(String(v)) => Some(v); _ => None }
    _ => None
  }
}

fn[T : @json.FromJson] decode_field_or(
  fields: Map[String, Json],
  key: String,
  default: T,
  _path: @json.JsonPath,
  _owner: String,
) -> T raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(value) => @json.from_json(value)
    None => default
  }
}

pub impl ToJson for UiTriggerKind with to_json(self : UiTriggerKind) -> Json {
  let fields : Map[String, Json] = Map::new()
  match self {
    Click(kind) => {
      fields.set("kind", Json::string(kind))
    }
    Input(text) => {
      fields.set("kind", Json::string("input"))
      fields.set("text", Json::string(text))
    }
    Key(key, key_event, code, ctrl_key, shift_key, alt_key, meta_key) => {
      fields.set("kind", Json::string("key"))
      fields.set("key", Json::string(key))
      fields.set("key_event", Json::string(key_event))
      if code != "" { fields.set("code", Json::string(code)) }
      if ctrl_key { fields.set("ctrl_key", true.to_json()) }
      if shift_key { fields.set("shift_key", true.to_json()) }
      if alt_key { fields.set("alt_key", true.to_json()) }
      if meta_key { fields.set("meta_key", true.to_json()) }
    }
    DragTo(target_id) => {
      fields.set("kind", Json::string("drag_to"))
      fields.set("target_id", target_id.to_json())
    }
  }
  Json::object(fields)
}

pub impl @json.FromJson for UiTriggerKind with from_json(json, path) {
  let owner = "UiTriggerKind::from_json"
  let fields = ui_result_object(json, path, owner)
  let kind : String = decode_field(fields, "kind", path, owner)
  match kind {
    "input" =>
      Input(decode_field(fields, "text", path, owner))
    "key" =>
      Key(
        decode_field(fields, "key", path, owner),
        decode_field_or(fields, "key_event", "press", path, owner),
        decode_field_or(fields, "code", "", path, owner),
        decode_field_or(fields, "ctrl_key", false, path, owner),
        decode_field_or(fields, "shift_key", false, path, owner),
        decode_field_or(fields, "alt_key", false, path, owner),
        decode_field_or(fields, "meta_key", false, path, owner),
      )
    "drag_to" =>
      DragTo(decode_field(fields, "target_id", path, owner))
    _ => Click(kind)
  }
}

pub impl ToJson for UiRequest with to_json(self : UiRequest) -> Json {
  let fields : Map[String, Json] = Map::new()
  match self {
    Query(id, kind, value) => {
      fields.set("id", id.to_json())
      fields.set("action", Json::string("query"))
      fields.set("kind", Json::string(kind))
      fields.set("value", Json::string(value))
    }
    Trigger(id, trigger) => {
      fields.set("id", id.to_json())
      fields.set("action", Json::string("trigger"))
      match trigger.to_json() {
        Object(trigger_fields) => {
          for field in trigger_fields {
            fields.set(field.0, field.1)
          }
        }
        _ => abort("UiTriggerKind::to_json must return object")
      }
    }
    Sync => {
      fields.set("action", Json::string("sync"))
    }
  }
  Json::object(fields)
}

pub impl @json.FromJson for UiRequest with from_json(json, path) {
  let owner = "UiRequest::from_json"
  let fields = ui_result_object(json, path, owner)
  let action : String = decode_field(fields, "action", path, owner)
  match action {
    "query" =>
      Query(
        decode_field(fields, "id", path, owner),
        decode_field_or(fields, "kind", "node", path, owner),
        decode_field_or(fields, "value", "", path, owner),
      )
    "trigger" =>
      Trigger(
        decode_field(fields, "id", path, owner),
        @json.from_json(json),
      )
    "sync" => Sync
    _ => raise @json.JsonDecodeError((path, "\{owner}: invalid action"))
  }
}

pub impl ToJson for UiNodeSnapshot with to_json(self : UiNodeSnapshot) -> Json {
  Json::object({
    "id": self.id.to_json(),
    "kind": Json::string(self.kind),
    "tag": Json::string(self.tag),
    "text": Json::string(self.text),
    "value": Json::string(self.value),
    "checked": self.checked.to_json(),
    "focused": self.focused.to_json(),
    "visible": self.visible.to_json(),
  })
}

pub impl @json.FromJson for UiNodeSnapshot with from_json(json, path) {
  let owner = "UiNodeSnapshot::from_json"
  let fields = ui_result_object(json, path, owner)
  {
    id: decode_field(fields, "id", path, owner),
    kind: decode_field(fields, "kind", path, owner),
    tag: decode_field(fields, "tag", path, owner),
    text: decode_field(fields, "text", path, owner),
    value: decode_field(fields, "value", path, owner),
    checked: decode_field(fields, "checked", path, owner),
    focused: decode_field(fields, "focused", path, owner),
    visible: decode_field(fields, "visible", path, owner),
  }
}

pub impl ToJson for UiQueryResult with to_json(self : UiQueryResult) -> Json {
  match self {
    Node(node) => node.to_json()
    Text(id, text) => {
      "id": id.to_json(),
      "text": Json::string(text),
    }
    Style(id, key, value) => {
      "id": id.to_json(),
      "kind": Json::string("style"),
      "key": Json::string(key),
      "value": Json::string(value),
    }
  }
}

pub impl @json.FromJson for UiQueryResult with from_json(json, path) {
  match ui_result_string(json, "kind") {
    Some("style") => {
      let owner = "UiQueryResult::from_json"
      let fields = ui_result_object(json, path, owner)
      Style(
        decode_field(fields, "id", path, owner),
        decode_field(fields, "key", path, owner),
        decode_field(fields, "value", path, owner),
      )
    }
    Some(_) => Node(@json.from_json(json))
    None => {
      let owner = "UiQueryResult::from_json"
      let fields = ui_result_object(json, path, owner)
      Text(
        decode_field(fields, "id", path, owner),
        decode_field(fields, "text", path, owner),
      )
    }
  }
}

pub impl ToJson for UiTriggerResult with to_json(self : UiTriggerResult) -> Json {
  match self {
    Pointer(id, name) => {
      "ok": true.to_json(),
      "kind": Json::string("pointer"),
      "id": id.to_json(),
      "name": Json::string(name),
    }
    Input(id) => {
      "ok": true.to_json(),
      "kind": Json::string("input"),
      "id": id.to_json(),
    }
    Key(id, name) => {
      "ok": true.to_json(),
      "kind": Json::string("key"),
      "id": id.to_json(),
      "name": Json::string(name),
    }
    DragTo(id, target_id) => {
      "ok": true.to_json(),
      "kind": Json::string("drag_to"),
      "id": id.to_json(),
      "target_id": target_id.to_json(),
    }
    Focus(id) => {
      "ok": true.to_json(),
      "kind": Json::string("focus"),
      "id": id.to_json(),
    }
    Blur(id) => {
      "ok": true.to_json(),
      "kind": Json::string("blur"),
      "id": id.to_json(),
    }
    ScrollIntoView(id) => {
      "ok": true.to_json(),
      "kind": Json::string("scrollIntoView"),
      "id": id.to_json(),
    }
  }
}

pub impl @json.FromJson for UiTriggerResult with from_json(json, path) {
  let owner = "UiTriggerResult::from_json"
  let fields = ui_result_object(json, path, owner)
  let kind : String = decode_field(fields, "kind", path, owner)
  match kind {
    "pointer" | "click" | "dblclick" | "pointerdown" | "pointermove" | "pointerup" =>
      Pointer(
        decode_field(fields, "id", path, owner),
        decode_field(fields, "name", path, owner),
      )
    "input" =>
      Input(decode_field(fields, "id", path, owner))
    "key" | "press" | "keydown" | "keyup" =>
      Key(
        decode_field(fields, "id", path, owner),
        decode_field(fields, "name", path, owner),
      )
    "drag_to" =>
      DragTo(
        decode_field(fields, "id", path, owner),
        decode_field(fields, "target_id", path, owner),
      )
    "focus" =>
      Focus(decode_field(fields, "id", path, owner))
    "blur" =>
      Blur(decode_field(fields, "id", path, owner))
    "scrollIntoView" =>
      ScrollIntoView(decode_field(fields, "id", path, owner))
    _ => raise @json.JsonDecodeError((path, "\{owner}: invalid kind"))
  }
}

pub impl ToJson for UiResponse with to_json(self : UiResponse) -> Json {
  match self {
    Query(query) => query.to_json()
    Trigger(trigger) => trigger.to_json()
    Sync => { "ok": true.to_json() }
  }
}

pub impl @json.FromJson for UiResponse with from_json(json, path) {
  match ui_result_string(json, "kind") {
    Some("pointer") | Some("click") | Some("dblclick") | Some("pointerdown") |
    Some("pointermove") | Some("pointerup") | Some("input") | Some("key") |
    Some("press") | Some("keydown") | Some("keyup") | Some("drag_to") |
    Some("focus") | Some("blur") | Some("scrollIntoView") =>
      Trigger(@json.from_json(json))
    _ =>
      match json {
        Object(fields) =>
          match fields.get("ok") {
            Some(True) =>
              if fields.get("kind") is None {
                Sync
              } else {
                Query(@json.from_json(json))
              }
            _ => Query(@json.from_json(json))
          }
        _ => raise @json.JsonDecodeError((path, "UiResponse::from_json: expected object"))
      }
  }
}

fn mock_node_snapshot(browser: MockBrowser, id: Int) -> UiNodeSnapshot raise {
  let node = match browser.nodes.get(id) {
    Some(node) => node
    None => raise mock_dom_err("mock node not found")
  }
  {
    id,
    kind: if node.tag == "" { "text" } else { "element" },
    tag: node.tag,
    text: mock_node_text(browser, id),
    value: node.props.get("value").bind(x => x).unwrap_or(node.attrs.get("value").unwrap_or("")),
    checked: node.props.get("checked").bind(x => x).unwrap_or(node.attrs.get("checked").unwrap_or("")) == "true",
    focused: browser.focused == Some(id),
    visible: mock_node_visible(node),
  }
}

fn mock_query(browser: MockBrowser, id: Int, kind: String, value: String) -> UiQueryResult raise {
  let node = mock_node_snapshot(browser, id)
  if kind == "node" { return Node(node) }
  if kind == "text" {
    return Text(id, mock_node_text(browser, id))
  }
  if kind == "style" {
    let current = match browser.nodes.get(id) {
      Some(node) => node
      None => raise mock_dom_err("mock node not found")
    }
    if value == "" { raise mock_dom_err("query style expects property name") }
    return Style(id, value, current.styles.get(value).unwrap_or(""))
  }
  raise mock_dom_err("unsupported query kind: \{kind}")
}

fn mock_key_event(
  _browser: MockBrowser,
  id: Int,
  name: String,
  key: String,
  code: String,
  ctrl: Bool,
  shift: Bool,
  alt: Bool,
  meta: Bool,
) -> Unit {
  trigger_node_ev(id, name, {
    ..EventData::default(),
    key,
    code,
    ctrl,
    shift,
    alt,
    meta,
  })
}

fn mock_trigger(
  browser: MockBrowser,
  id: Int,
  trigger: UiTriggerKind,
) -> UiTriggerResult {
  match trigger {
    Click(kind) => {
      trigger_node(id, mock_event_name(kind))
      Pointer(id, kind)
    }
    Input(text) => {
      match browser.nodes.get(id) {
        Some(node) => node.props.set("value", Some(text))
        None => ()
      }
      trigger_node(id, "oninput")
      trigger_node(id, "onchange")
      Input(id)
    }
    Key(key, key_event, code, ctrl_key, shift_key, alt_key, meta_key) => {
      let name = if key_event == "" { "press" } else { key_event }
      if name == "press" {
        mock_key_event(browser, id, "onkeydown", key, code, ctrl_key, shift_key, alt_key, meta_key)
        mock_key_event(browser, id, "onkeyup", key, code, ctrl_key, shift_key, alt_key, meta_key)
      } else {
        mock_key_event(browser, id, "on\{name}", key, code, ctrl_key, shift_key, alt_key, meta_key)
      }
      Key(id, name)
    }
    DragTo(target_id) => {
      trigger_node(id, "onpointerdown")
      trigger_node(id, "onpointerup")
      DragTo(id, target_id)
    }
  }
}

fn mock_trigger_legacy(browser: MockBrowser, id: Int, kind: String) -> UiTriggerResult raise {
  match kind {
    "click" | "dblclick" | "pointerdown" | "pointermove" | "pointerup" =>
      mock_trigger(browser, id, Click(kind))
    "focus" => {
      browser.focused = Some(id)
      Focus(id)
    }
    "blur" => {
      if browser.focused == Some(id) { browser.focused = None }
      Blur(id)
    }
    "scrollIntoView" => {
      ScrollIntoView(id)
    }
    _ => raise mock_dom_err("unsupported trigger kind: \{kind}")
  }
}

pub fn mock_request(browser: MockBrowser, request: UiRequest) -> UiResponse raise {
  match request {
    Query(id, kind, value) => Query(mock_query(browser, id, kind, value))
    Trigger(id, trigger) =>
      match trigger {
        Click("focus" as kind) | Click("blur" as kind) | Click("scrollIntoView" as kind) =>
          Trigger(mock_trigger_legacy(browser, id, kind))
        _ => Trigger(mock_trigger(browser, id, trigger))
      }
    Sync => Sync
  }
}

fn mock_event(
  browser: MockBrowser,
  action: String,
  target: String,
  ev? : EventData? = None,
) -> Array[DomCmd] {
  let event = mock_event_name(action)
  match query_node(target) {
    Some(id) =>
      match ev {
        Some(data) => trigger_node_ev(id, event, data)
        None => trigger_node(id, event)
      }
    None => ()
  }
  let cmds = flush_cmds()
  apply_mock_cmds(browser, cmds)
  cmds
}

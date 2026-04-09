pub struct MockNode {
  id: Int
  tag: String
  mut text: String
  mut parent: Int?
  children: Array[Int]
  attrs: Map[String, String]
  styles: Map[String, String]
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
    })
    Text(id, text) =>
      if browser.nodes.get(id) is Some(node) { node.text = text }
    Attr(id, key, value) =>
      if browser.nodes.get(id) is Some(node) { node.attrs.set(key, value) }
    Append(parent, child) => append_mock_node(browser, parent, child)
    Remove(id) => remove_mock_subtree(browser, id)
    Listen(_, _) => ()
    InsertBefore(parent, child, ref_id) => insert_before_mock_node(browser, parent, child, ref_id)
    SetStyle(id, key, value) =>
      if browser.nodes.get(id) is Some(node) { node.styles.set(key, value) }
    RemoveStyle(id, key) =>
      if browser.nodes.get(id) is Some(node) { ignore(node.styles.remove(key)) }
    RemoveAttr(id, key) =>
      if browser.nodes.get(id) is Some(node) { ignore(node.attrs.remove(key)) }
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

pub fn ui_query_result_to_json(result: UiQueryResult) -> Json {
  match result {
    Node(node) => {
      "id": node.id.to_json(),
      "kind": Json::string(node.kind),
      "tag": Json::string(node.tag),
      "text": Json::string(node.text),
      "value": Json::string(node.value),
      "checked": node.checked.to_json(),
      "focused": node.focused.to_json(),
      "visible": node.visible.to_json(),
    }
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

pub fn ui_trigger_result_to_json(result: UiTriggerResult) -> Json {
  match result {
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

pub fn ui_response_to_json(result: UiResponse) -> Json {
  match result {
    Query(query) => ui_query_result_to_json(query)
    Trigger(trigger) => ui_trigger_result_to_json(trigger)
    Sync => { "ok": true.to_json() }
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
    value: node.attrs.get("value").unwrap_or(""),
    checked: node.attrs.get("checked") == Some("true"),
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
        Some(node) => node.attrs.set("value", text)
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

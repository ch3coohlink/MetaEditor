priv struct MockNode {
  id: Int
  mut text: String
  mut parent: Int?
  children: Array[Int]
  attrs: Map[String, String]
  styles: Map[String, String]
}

priv struct MockBrowser {
  nodes: Map[Int, MockNode]
  roots: Array[Int]
  css: Map[String, String]
  host_cmds: Array[(Int, String)]
}

fn new_mock_browser() -> MockBrowser {{
  nodes: Map::new(),
  roots: [],
  css: Map::new(),
  host_cmds: [],
}}


fn child_list(browser: MockBrowser, parent: Int) -> Array[Int] {
  if parent == 0 { return browser.roots }
  match browser.nodes.get(parent) {
    Some(node) => node.children
    None => abort("missing parent: \{parent}")
  }
}

fn detach_mock_node(browser: MockBrowser, id: Int) -> Unit {
  if browser.nodes.get(id) is Some(node) {
    if node.parent is Some(parent) {
      let children = child_list(browser, parent)
      for i, v in children { if v == id { ignore(children.remove(i)); break } }
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
}

fn apply_mock_cmd(browser: MockBrowser, cmd: DomCmd) -> Unit {
  match cmd {
    Create(id, _, _) => browser.nodes.set(id, {
      id,
      text: "",
      parent: None,
      children: [],
      attrs: Map::new(),
      styles: Map::new(),
    })
    Text(id, text) =>
      if browser.nodes.get(id) is Some(node) { node.text = text }
    Attr(id, key, value) | UpdateAttr(id, key, value) =>
      if browser.nodes.get(id) is Some(node) { node.attrs.set(key, value) }
    Append(parent, child) => append_mock_node(browser, parent, child)
    UpdateText(id, text) =>
      if browser.nodes.get(id) is Some(node) { node.text = text }
    Remove(id) => remove_mock_subtree(browser, id)
    Listen(_, _, _) => ()
    InsertBefore(parent, child, ref_id) => insert_before_mock_node(browser, parent, child, ref_id)
    SetStyle(id, key, value) =>
      if browser.nodes.get(id) is Some(node) { node.styles.set(key, value) }
    RemoveStyle(id, key) =>
      if browser.nodes.get(id) is Some(node) { ignore(node.styles.remove(key)) }
    RemoveAttr(id, key) =>
      if browser.nodes.get(id) is Some(node) { ignore(node.attrs.remove(key)) }
    HostCmd(id, name) => browser.host_cmds.push((id, name))
    SetCss(id, text) => browser.css.set(id, text)
    RemoveCss(id) => ignore(browser.css.remove(id))
  }
}

fn apply_mock_cmds(browser: MockBrowser, cmds: Array[DomCmd]) -> Unit {
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
    _ => if action.length() >= 2 && action[:2].to_string() == "on" { action } else { "on\{action}" }
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

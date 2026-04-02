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

fn remove_array_item(xs: Array[Int], id: Int) -> Unit {
  let mut hit = -1
  for i = 0; i < xs.length(); i = i + 1 {
    if hit < 0 && xs[i] == id {
      hit = i
    }
  }
  if hit < 0 { return }
  for i = hit; i + 1 < xs.length(); i = i + 1 {
    xs[i] = xs[i + 1]
  }
  ignore(xs.pop())
}

fn insert_array_item(xs: Array[Int], index: Int, id: Int) -> Unit {
  xs.push(id)
  for i = xs.length() - 1; i > index; i = i - 1 {
    xs[i] = xs[i - 1]
  }
  xs[index] = id
}

fn child_list(browser: MockBrowser, parent: Int) -> Array[Int] {
  if parent == 0 { return browser.roots }
  match browser.nodes.get(parent) {
    Some(node) => node.children
    None => abort("missing parent: \{parent}")
  }
}

fn detach_mock_node(browser: MockBrowser, id: Int) -> Unit {
  match browser.nodes.get(id) {
    Some(node) =>
      match node.parent {
        Some(parent) => {
          remove_array_item(child_list(browser, parent), id)
          node.parent = None
        }
        None => ()
      }
    None => ()
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
  if pos == xs.length() {
    xs.push(id)
  } else {
    insert_array_item(xs, pos, id)
  }
  match browser.nodes.get(id) {
    Some(node) => node.parent = Some(parent)
    None => abort("missing child: \{id}")
  }
}

fn insert_after_mock_node(browser: MockBrowser, parent: Int, id: Int, after_id: Int) -> Unit {
  detach_mock_node(browser, id)
  let xs = child_list(browser, parent)
  let mut pos = xs.length()
  for i = 0; i < xs.length(); i = i + 1 {
    if pos == xs.length() && xs[i] == after_id {
      pos = i + 1
    }
  }
  if pos >= xs.length() {
    xs.push(id)
  } else {
    insert_array_item(xs, pos, id)
  }
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
      match browser.nodes.get(id) {
        Some(node) => node.text = text
        None => ()
      }
    Attr(id, key, value) | UpdateAttr(id, key, value) =>
      match browser.nodes.get(id) {
        Some(node) => node.attrs.set(key, value)
        None => ()
      }
    Append(parent, child) => append_mock_node(browser, parent, child)
    UpdateText(id, text) =>
      match browser.nodes.get(id) {
        Some(node) => node.text = text
        None => ()
      }
    Remove(id) => remove_mock_subtree(browser, id)
    Listen(_, _, _) => ()
    Action(_, _) => ()
    InsertBefore(parent, child, ref_id) => insert_before_mock_node(browser, parent, child, ref_id)
    SetStyle(id, key, value) =>
      match browser.nodes.get(id) {
        Some(node) => node.styles.set(key, value)
        None => ()
      }
    RemoveStyle(id, key) =>
      match browser.nodes.get(id) {
        Some(node) => ignore(node.styles.remove(key))
        None => ()
      }
    RemoveAttr(id, key) =>
      match browser.nodes.get(id) {
        Some(node) => ignore(node.attrs.remove(key))
        None => ()
      }
    HostCmd(id, name) => browser.host_cmds.push((id, name))
    SetCss(id, text) => browser.css.set(id, text)
    RemoveCss(id) => ignore(browser.css.remove(id))
    InsertAfter(parent, child, after_id) => insert_after_mock_node(browser, parent, child, after_id)
  }
}

fn apply_mock_cmds(browser: MockBrowser, cmds: Array[DomCmd]) -> Unit {
  for cmd in cmds {
    apply_mock_cmd(browser, cmd)
  }
}

fn find_mock_node_by_ui(browser: MockBrowser, ui_id: String) -> MockNode? {
  for _, node in browser.nodes {
    match node.attrs.get("ui-id") {
      Some(value) => if value == ui_id { return Some(node) }
      None => ()
    }
  }
  None
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

fn mock_count_ui(browser: MockBrowser, ui_id: String) -> Int {
  let mut count = 0
  for _, node in browser.nodes {
    match node.attrs.get("ui-id") {
      Some(value) => if value == ui_id { count = count + 1 }
      None => ()
    }
  }
  count
}

fn mock_text_of_ui(browser: MockBrowser, ui_id: String) -> String {
  match find_mock_node_by_ui(browser, ui_id) {
    Some(node) => mock_node_text(browser, node.id)
    None => ""
  }
}

fn mock_click(browser: MockBrowser, ui_id: String) -> Array[DomCmd] {
  match find_mock_node_by_ui(browser, ui_id) {
    Some(node) => trigger_node(node.id, "onclick")
    None => click(ui_id)
  }
  let cmds = flush_cmds()
  apply_mock_cmds(browser, cmds)
  cmds
}

fn mock_dblclick(browser: MockBrowser, ui_id: String) -> Array[DomCmd] {
  match find_mock_node_by_ui(browser, ui_id) {
    Some(node) => trigger_node(node.id, "ondblclick")
    None => trigger_ui(ui_id, "ondblclick")
  }
  let cmds = flush_cmds()
  apply_mock_cmds(browser, cmds)
  cmds
}
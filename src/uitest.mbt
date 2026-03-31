pub(all) struct TestNode {
  id: Int
  tag: String
  mut text: String
  attrs: Map[String, String]
  styles: Map[String, String]
  mut children: Array[Int]
  mut parent: Int?
}

pub(all) struct UiTest {
  state: DomState
  stop: () -> Unit
  nodes: Ref[Map[Int, Ref[TestNode]]]
  listeners: Ref[Map[String, Int]]
  actions: Ref[Map[String, Int]]
  host_cmds: Ref[Array[(Int, String)]]
}

fn test_node(id: Int, tag: String) -> TestNode {{
  id,
  tag,
  text: "",
  attrs: Map::new(),
  styles: Map::new(),
  children: [],
  parent: None,
}}

fn listener_key(id: Int, event: String) -> String {
  "\{id}:\{event}"
}

fn expect_test_node(ui: UiTest, id: Int) -> Ref[TestNode] {
  match ui.nodes.val.get(id) {
    Some(node) => node
    None => abort("test node not found: \{id}")
  }
}

fn detach_test_child(ui: UiTest, id: Int) -> Unit {
  match ui.nodes.val.get(id) {
    Some(node) =>
      match node.val.parent {
        Some(parent_id) =>
          match ui.nodes.val.get(parent_id) {
            Some(parent) => {
              parent.val.children = parent.val.children.filter(v => v != id)
              node.val.parent = None
            }
            None => node.val.parent = None
          }
        None => ()
      }
    None => ()
  }
}

fn attach_test_child(ui: UiTest, parent_id: Int, child_id: Int, before? : Int? = None) -> Unit {
  let parent = expect_test_node(ui, parent_id)
  let child = expect_test_node(ui, child_id)
  detach_test_child(ui, child_id)
  let next: Array[Int] = []
  let mut inserted = false
  for id in parent.val.children {
    if !inserted {
      match before {
        Some(ref_id) =>
          if id == ref_id {
            next.push(child_id)
            inserted = true
          }
        None => ()
      }
    }
    next.push(id)
  }
  if !inserted { next.push(child_id) }
  parent.val.children = next
  child.val.parent = Some(parent_id)
}

fn remove_test_subtree(ui: UiTest, id: Int) -> Unit {
  let child_ids = match ui.nodes.val.get(id) {
    Some(node) => node.val.children.copy()
    None => []
  }
  for child_id in child_ids {
    remove_test_subtree(ui, child_id)
  }
  detach_test_child(ui, id)
  ui.nodes.val.remove(id)
}

fn apply_test_cmd(ui: UiTest, cmd: DomCmd) -> Unit {
  match cmd {
    Create(id, tag, _) => ui.nodes.val.set(id, Ref::new(test_node(id, tag)))
    Text(id, text) => expect_test_node(ui, id).val.text = text
    Attr(id, key, value) => expect_test_node(ui, id).val.attrs.set(key, value)
    Append(parent_id, child_id) => attach_test_child(ui, parent_id, child_id)
    UpdateText(id, text) => expect_test_node(ui, id).val.text = text
    UpdateAttr(id, key, value) => expect_test_node(ui, id).val.attrs.set(key, value)
    Remove(id) => remove_test_subtree(ui, id)
    Listen(id, event, cb_id) => ui.listeners.val.set(listener_key(id, event), cb_id)
    Action(name, cb_id) => ui.actions.val.set(name, cb_id)
    InsertBefore(parent_id, child_id, ref_id) =>
      attach_test_child(ui, parent_id, child_id, before=Some(ref_id))
    SetStyle(id, key, value) => expect_test_node(ui, id).val.styles.set(key, value)
    RemoveStyle(id, key) => ignore(expect_test_node(ui, id).val.styles.remove(key))
    RemoveAttr(id, key) => ignore(expect_test_node(ui, id).val.attrs.remove(key))
    HostCmd(id, cmd) => ui.host_cmds.val.push((id, cmd))
  }
}

fn collect_test_text(ui: UiTest, id: Int) -> String {
  match ui.nodes.val.get(id) {
    Some(node) => {
      let parts: Array[String] = []
      if node.val.text != "" { parts.push(node.val.text) }
      for child_id in node.val.children {
        let text = collect_test_text(ui, child_id)
        if text != "" { parts.push(text) }
      }
      parts.iter().join("")
    }
    None => ""
  }
}

fn find_testid(ui: UiTest, testid: String) -> Int? {
  for pair in ui.nodes.val {
    let (id, node) = pair
    match node.val.attrs.get("data-testid") {
      Some(value) => if value == testid { return Some(id) }
      None => ()
    }
  }
  None
}

pub fn mount_ui(child: Child) -> UiTest raise {
  reset_test_ui()
  let state = new_dom_state()
  let stop = scope(fn() {
    let root = realize(state, child)
    emit(state, Append(0, root.id))
  })
  let nodes: Map[Int, Ref[TestNode]] = Map::new()
  nodes.set(0, Ref::new(test_node(0, "#root")))
  let ui = {
    state,
    stop,
    nodes: Ref::new(nodes),
    listeners: Ref::new(Map::new()),
    actions: Ref::new(Map::new()),
    host_cmds: Ref::new([]),
  }
  ignore(ui.flush())
  ui
}

pub fn UiTest::flush(self: UiTest) -> Array[DomCmd] {
  try_flush()
  let cmds = get_cmds(self.state)
  for cmd in cmds {
    apply_test_cmd(self, cmd)
  }
  cmds
}

pub fn UiTest::cleanup(self: UiTest) -> Unit {
  (self.stop)()
  ignore(self.flush())
}

pub fn UiTest::contains_testid(self: UiTest, testid: String) -> Bool {
  find_testid(self, testid) is Some(_)
}

pub fn UiTest::text(self: UiTest) -> String {
  collect_test_text(self, 0)
}

pub fn UiTest::text_at(self: UiTest, testid: String) -> String? {
  match find_testid(self, testid) {
    Some(id) => Some(collect_test_text(self, id))
    None => None
  }
}

pub fn UiTest::click(self: UiTest, testid: String) -> Array[DomCmd] {
  let id = match find_testid(self, testid) {
    Some(id) => id
    None => abort("testid not found: \{testid}")
  }
  let cb_id = match self.listeners.val.get(listener_key(id, "onclick")) {
    Some(cb_id) => cb_id
    None => abort("onclick listener not found: \{testid}")
  }
  trigger_callback(cb_id)
  self.flush()
}

pub fn UiTest::run_action(self: UiTest, name: String) -> Array[DomCmd] {
  let cb_id = match self.actions.val.get(name) {
    Some(cb_id) => cb_id
    None => abort("action not found: \{name}")
  }
  trigger_callback(cb_id)
  self.flush()
}

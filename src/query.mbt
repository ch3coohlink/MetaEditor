let class_id: () -> Int = gen_gen_id(0)
type Names = Map[String, UIID]
pub enum UIScopeKind { Normal; Scope }
pub struct UIMeta { id: String; class: String; style: String; scope: UIScopeKind }
pub enum UIID { None; Scope(UIScope); List(UIList); Item(UIItem) }
pub struct UIScope { meta: UIMeta; mut parent: UIID; names: Names?; mut node: Node? }
pub struct UIList { id: String; mut parent: UIID; mut items: Array[UIID]; mut node: Node? }
pub struct UIItem { mut index: Int; mut parent: UIID; names: Names; mut node: Node? }
fn UIID::check(id: String, root~: Bool = false) -> Unit raise {
  if id == "" && !root { fail("ui key cannot be empty") }
  if id.contains("/") { fail("ui key cannot contain '/'") }
  if id.contains(":") { fail("ui key cannot contain ':'") }
  if id.contains(" ") { fail("ui key cannot contain  ' '") }
}
pub fn ui(id: String, scope?: UIScopeKind = Normal, style?: String = "", root?: Bool = false,
) -> UIMeta raise {
  UIID::check(id, root~); { id, class: "u-\{class_id()}", style, scope }
}
pub fn UIID::list(id: String, parent: UIID) -> UIID raise {
  UIID::check(id); List({ id, parent, items: [], node: None })
}
pub fn UIMeta::inst(self: UIMeta, parent: UIID) -> UIID {
  match (self.scope) {
    Scope => Scope({ meta: self, parent, names: Some(Map::new()), node: None })
    Normal => Scope({ meta: self, parent, names: None, node: None })
  }
}
fn UIID::names(self: UIID) -> Names raise {
  match self {
    Scope({ names: Some(names), .. }) => names
    Item(item) => item.names
    _ => fail("uiid is not a namescope")
  }
}
pub fn UIID::len(self: UIID) -> Int {
  match self { List(list) => list.items.length(); _ => 0 }
}
pub fn UIID::get(self: UIID, key: String) -> UIID raise {
  match self {
    Scope({ names: Some(names), .. }) => match names.get(key) {
      Some(node) => node
      None => fail("no id \"\{key}\"")
    }
    Item(item) => match item.names.get(key) {
      Some(node) => node
      None => fail("no id \"\{key}\"")
    }
    List(list) => {
      let i = @string.parse_int(key)
      if i >= 0 && i < list.items.length() { list.items[i] }
      else { fail("no item \"\{key}\"") }
    }
    _ => fail("uiid is not queryable")
  }
}
pub fn UIID::push(self: UIID) -> UIID raise {
  match self {
    List(list) => {
      let item = Item({ parent: self, index: list.items.length(), names: Map::new(), node: None })
      list.items.push(item)
      item
    }
    _ => fail("uiid is not a uilist")
  }
}
pub fn UIID::del(self: UIID, key: String) -> Unit raise {
  match self {
    Scope(scope) => {
      let names = match scope.names { Some(names) => names; None => fail("uiid is not a namescope") }
      ignore(names.remove(key))
    }
    Item(item) => ignore(item.names.remove(key))
    List(list) => {
      let i = @string.parse_int(key)
      if i >= 0 && i < list.items.length() {
        ignore(list.items.remove(i))
        let mut j = i
        while j < list.items.length() {
          if list.items[j] is Item(item) { item.index = j }
          j += 1
        }
      }
    }
    None => fail("uiid is not queryable")
  }
}
pub fn UIID::add(self: UIID, child: UIID) -> Unit raise {
  fn child_id(child: UIID) -> String raise {
    match child {
      Scope(scope) => scope.meta.id
      List(list) => list.id
      Item(_) => fail("cannot add uiitem by name")
      None => fail("cannot add empty uiid")
    }
  }
  fn parent(child: UIID) -> UIID raise {
    match child {
      Scope(scope) => scope.parent
      List(list) => list.parent
      Item(item) => item.parent
      None => fail("empty uiid has no parent")
    }
  }
  if parent(child).path() != self.path() { fail("uiid parent mismatch") }
  let cid = child_id(child)
  let pid = match self { Scope(scope) => scope.meta.id; List(list) => list.id; _ => "" }
  if pid != "" && cid.has_prefix(pid) { fail("ui id cannot start with parent id: \{cid}") }
  let names = self.names()
  if names.get(cid) is Some(_) { fail("duplicate ui id: \{cid}") }
  names.set(cid, child)
}
pub fn UIID::bind(self: UIID, parent: UIID) -> Unit raise {
  match self {
    Scope(scope) => scope.parent = parent
    List(list) => list.parent = parent
    Item(item) => item.parent = parent
    None => fail("empty uiid has no parent")
  }
}
pub fn UIID::bind_node(self: UIID, node: Node?) -> Unit {
  match self {
    Scope(scope) => scope.node = node
    List(list) => list.node = node
    Item(item) => item.node = node
    None => ()
  }
}
pub fn UIID::node(self: UIID) -> Node raise {
  match self {
    Scope({ node: Some(node), .. }) => node
    List({ node: Some(node), .. }) => node
    Item({ node: Some(node), .. }) => node
    _ => fail("uiid is not bound to a node")
  }
}
pub fn UIID::unbind(self: UIID) -> Unit raise {
  match self {
    Scope(scope) => if !(scope.parent is None) { scope.parent.del(scope.meta.id) }
    List(list) => if !(list.parent is None) { list.parent.del(list.id) }
    Item(item) => if !(item.parent is None) { item.parent.del(item.index.to_string()) }
    None => ()
  }
}

pub fn UIID::path(self: UIID) -> String {
  fn join(parent: UIID, seg: String) -> String {
    let base = parent.path()
    if base == "" { seg } else { base + "/" + seg }
  }
  match self {
    Scope(scope) => join(scope.parent, scope.meta.id)
    List(list) => join(list.parent, list.id)
    Item(item) => join(item.parent, item.index.to_string())
    None => ""
  }
}
pub fn UIID::query(self: UIID, path: String) -> UIID raise {
  let mut cur = self
  for p in split_path(path) {
    cur = cur.get(p) catch { _ => fail("no id \"\{p}\" found in path: \"\{path}\"") }
  }
  cur
}

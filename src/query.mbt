let class_id: () -> Int = gen_gen_id(0)
type Names = Map[String, UIID]
pub enum UIScopeKind { Normal; Scope; List }
pub struct UIMeta { id: String; class: String; style: String; scope: UIScopeKind }
pub enum UIID { None; Scope(UIScope); List(UIList); Item(UIItem) }
pub struct UIScope { meta: UIMeta; parent: UIID; names: Names? }
pub struct UIList { meta: UIMeta; parent: UIID; items: Array[UIID] }
pub struct UIItem { mut index: Int; parent: UIID; names: Names }
pub fn ui(id: String, scope?: UIScopeKind = Normal, style?: String = "") -> UIMeta raise {
  if id == "" { fail("ui key cannot be empty") }
  if id.contains("/") { fail("ui key cannot contain /") }
  { id, class: "u-\{class_id()}", style, scope }
}
pub fn UIMeta::inst(self: UIMeta, parent: UIID) -> UIID {
  match (self.scope) {
    List => List({ meta: self, parent, items: [] })
    Scope => Scope({ meta: self, parent, names: Some(Map::new()) })
    Normal => Scope({ meta: self, parent, names: None })
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
      let item = Item({ parent: self, index: list.items.length(), names: Map::new() })
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
      List(list) => list.meta.id
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
  let pid = match self { Scope(scope) => scope.meta.id; List(list) => list.meta.id; _ => "" }
  if pid != "" && cid.has_prefix(pid) { fail("ui id cannot start with parent id: \{cid}") }
  let names = self.names()
  if names.get(cid) is Some(_) { fail("duplicate ui id: \{cid}") }
  names.set(cid, child)
}

pub fn UIID::path(self: UIID) -> String {
  fn join(parent: UIID, seg: String) -> String {
    let base = parent.path()
    if base == "" { seg } else { base + "/" + seg }
  }
  match self {
    Scope(scope) => join(scope.parent, scope.meta.id)
    List(list) => join(list.parent, list.meta.id)
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

let class_id: () -> Int = gen_gen_id(0)
pub struct UIMeta { id: String; class: String; style: String; scope: Bool }
pub struct UIID { meta: UIMeta; parent: UIID?; names: Map[String, UIID]? }
pub fn ui(id: String, scope?: Bool = false, style?: String = "") -> UIMeta raise {
  if id == "" { fail("ui key cannot be empty") }
  if id.contains("/") { fail("ui key cannot contain /") }
  { id, class: "u-\{class_id()}", style, scope }
}
pub fn UIMeta::inst(meta: UIMeta, parent?: UIID? = None) -> UIID {{
  meta, parent, names: if meta.scope { Some(Map::new()) } else { None }
}}
pub fn UIMeta::is_scope(self: UIMeta) -> Bool { self.scope }
pub fn UIID::is_scope(self: UIID) -> Bool { self.meta.scope }
pub fn UIID::names(self: UIID) -> Map[String, UIID] raise {
  match self.names { Some(names) => names; None => fail("uiid is not a namescope") }
}
pub fn UIID::add(self: UIID, child: UIID) -> Unit raise { self.names().set(child.meta.id, child) }
pub fn UIID::del(self: UIID, key: String) -> Unit raise { ignore(self.names().remove(key)) }
pub fn UIID::get(self: UIID, key: String) -> UIID? {
  match self.names { Some(names) => names.get(key); None => None }
}

pub fn UIID::path(self: UIID) -> String {
  match self.parent { Some(parent) => parent.path() + "/" + self.meta.id; None => self.meta.id }
}
pub fn UIID::query(self: UIID, path: String) -> UIID raise {
  let parts = split_path(path)
  let mut cur = self
  for p in parts {
    match cur.get(p) {
      Some(next) => { cur = next }
      None => fail("no id \"\{p}\" found in path: \"\{path}\"")
    }
  }
  cur
}

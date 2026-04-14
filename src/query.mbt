let class_id: () -> Int = gen_gen_id(0)
pub struct UIMeta { id: String; class: String; style: String }
pub struct UIID { meta: UIMeta; parent: UIID? }
pub fn ui(id: String, style?: String = "") -> UIMeta raise {
  if id == "" { fail("ui key cannot be empty") }
  if id.contains("/") { fail("ui key cannot contain /") }
  { id, class: "u-\{class_id()}", style }
}
pub fn UIMeta::inst(self: UIMeta, parent?: UIID? = None) -> UIID {{ meta: self, parent }}

pub fn UIID::path(self: UIID) -> String {
  match self.parent {
    Some(parent) => parent.path() + "/" + self.meta.id
    None => self.meta.id
  }
}
pub fn UIID::query(self: UIID, path: String) -> UIID? {
  if path == "" { return None }
  let parts = []
  for part in path.split("/") {
    let key = part.to_string()
    if key == "" { return None }
    parts.push(key)
  }
  let mut i = parts.length() - 1
  let mut cur = Some(self)
  while cur is Some(uiid) {
    if i < 0 || uiid.meta.id != parts[i] { return None }
    if i == 0 { return Some(self) }
    cur = uiid.parent
    i = i - 1
  }
  None
}

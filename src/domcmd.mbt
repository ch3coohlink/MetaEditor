pub(all) enum DomRoot {
  Head
  Body
}
impl ToInt for DomRoot with to_int(self) {
  match self {
    Head => -1
    Body => 0
  }
}
impl ToInt for DomNs with to_int(self) {
  match self {
    Html => 0
    Svg => 1
    MathML => 2
  }
}
pub(all) enum DomValue {
  Empty
  String(String)
} derive(Eq)
pub impl ToJson for DomValue with to_json(self: DomValue) -> Json { match self {
  Empty => null
  String(value) => Json::string(value)
} }

pub(all) enum DomCmd {
  Create(Int, String, DomNs, DomValue)
  Insert(Int, Int, Int, Bool)
  Remove(Int)
  Attr(Int, String, DomValue)
  Style(Int, String, DomValue)
  Prop(Int, String, DomValue)
} derive(Eq)
pub(all) enum DomCmdTag {
  Create
  Insert
  Remove
  Attr
  Style
  Prop
}
impl ToInt for DomCmdTag with to_int(self) {
  match self {
    Create => 0
    Insert => 1
    Remove => 2
    Attr => 3
    Style => 4
    Prop => 5
  }
}
pub impl ToJson for DomCmd with to_json(self: DomCmd) -> Json {
  match self {
    Create(id, tag, ns, value) => {
      let code = ns.to_int()
      match (value, code) {
        (Empty, 0) => (DomCmdTag::Create.to_int(), id, tag).to_json()
        (Empty, _) => (DomCmdTag::Create.to_int(), id, tag, null, code).to_json()
        (String(text), 0) => (DomCmdTag::Create.to_int(), id, tag, text).to_json()
        (String(text), _) => (DomCmdTag::Create.to_int(), id, tag, text, code).to_json()
      }
    }
    Insert(pid, cid, rid, after) => {
      if rid == 0 && after { (DomCmdTag::Insert.to_int(), pid, cid).to_json() }
      else if after { (DomCmdTag::Insert.to_int(), pid, cid, rid).to_json() }
      else { (DomCmdTag::Insert.to_int(), pid, cid, rid, false).to_json() }
    }
    Remove(id) => (DomCmdTag::Remove.to_int(), id).to_json()
    Attr(id, key, value) => (DomCmdTag::Attr.to_int(), id, key, value).to_json()
    Style(id, key, value) => (DomCmdTag::Style.to_int(), id, key, value).to_json()
    Prop(id, key, value) => (DomCmdTag::Prop.to_int(), id, key, value).to_json()
  }
}

pub(all) enum Value { Empty; String(String) }

pub(all) enum Cmd {
  Create(Int, String, DomNs, Value)
  Insert(Int, Int, Int?)
  Remove(Int)
  Attr(Int, String, Value)
  Style(Int, String, Value)
  Prop(Int, String, Value)
}

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
      let cmd = DomCmdTag::Create.to_int()
      match (value, code) {
        (Empty, 0) => (cmd, id, tag).to_json()
        (Empty, _) => (cmd, id, tag, null, code).to_json()
        (String(text), 0) => (cmd, id, tag, text).to_json()
        (String(text), _) => (cmd, id, tag, text, code).to_json()
      }
    }
    Insert(pid, cid, rid, after) => {
      let cmd = DomCmdTag::Insert.to_int()
      if rid == 0 && after { (cmd, pid, cid).to_json() }
      else if after { (cmd, pid, cid, rid).to_json() }
      else { (cmd, pid, cid, rid, false).to_json() }
    }
    Remove(id) => (DomCmdTag::Remove.to_int(), id).to_json()
    Attr(id, k, v) => (DomCmdTag::Attr.to_int(), id, k, v).to_json()
    Style(id, k, v) => (DomCmdTag::Style.to_int(), id, k, v).to_json()
    Prop(id, k, v) => (DomCmdTag::Prop.to_int(), id, k, v).to_json()
  }
}

pub(all) enum DomNs { Html; Svg; MathML } derive(Eq)
type ClearHooks = Array[() -> Unit]
pub type Frag = Array[Node]
pub struct ElementNode {
  tag: String; ns: DomNs
  mut first_child: Node?
  mut last_child: Node?
  attrs: Map[String, DomValue]
  styles: Map[String, DomValue]
  props: Map[String, DomValue]
  clrs: ClearHooks
}
pub struct Node {
  id: Int
  mut parent: Node?
  mut prev: Node?
  mut next: Node?
  kind: NodeKind
}
pub(all) enum NodeKind {
  Text(String)
  Anchor(ClearHooks)
  Element(ElementNode)
}
fn _clear(clrs: ClearHooks) -> Unit { for clr in clrs { clr() }; clrs.clear() }
fn abort_non_elm(action: String) -> Unit { abort("\{action} on non-element node") }
fn detach(node: Node) -> Unit {
  match node.parent {
    Some(parent) =>
      match parent.kind {
        _ => abort_non_elm("detach")
        Element(el) => {
          match node.prev {
            Some(prev) => prev.next = node.next
            None => el.first_child = node.next
          }
          match node.next {
            Some(next) => next.prev = node.prev
            None => el.last_child = node.prev
          }
          node.parent = None
          node.prev = None
          node.next = None
        }
      }
    None => ()
  }
}
fn _remove(node: Node) -> Unit {
  match node.kind {
    Text(_) => ()
    Anchor(clrs) => _clear(clrs)
    Element(el) => {
      let mut current = el.first_child
      el.first_child = None
      el.last_child = None
      while current is Some(child) {
        let next = child.next
        child.parent = None
        child.prev = None
        child.next = None
        _remove(child)
        current = next
      }
      _clear(el.clrs)
    }
  }
}
pub fn Node::append_child(self: Node, node: Node) -> Unit {
  match self.kind {
    _ => abort_non_elm("append child")
    Element(el) => {
      detach(node)
      node.parent = Some(self)
      node.prev = el.last_child
      node.next = None
      match el.last_child {
        Some(tail) => tail.next = Some(node)
        None => el.first_child = Some(node)
      }
      el.last_child = Some(node)
    }
  }
}
pub fn Node::insert_after(self: Node, node: Node, tail: Node) -> Unit {
  match self.kind {
    _ => abort_non_elm("insert after")
    Element(el) => {
      let same_parent = match node.parent { Some(parent) => parent.id == self.id; None => false }
      if same_parent && node.prev is Some(prev) && prev.id == tail.id { return }
      detach(node)
      let next = tail.next
      node.parent = Some(self)
      node.prev = Some(tail)
      node.next = next
      tail.next = Some(node)
      match next {
        Some(sibling) => sibling.prev = Some(node)
        None => el.last_child = Some(node)
      }
    }
  }
}
pub fn Node::remove(self: Node) -> Unit {
  detach(self)
  _remove(self)
}
pub fn Node::set_attr(self: Node, key: String, value: DomValue) -> Unit {
  match self.kind {
    Element(el) => el.attrs.set(key, value)
    _ => abort_non_elm("set attr")
  }
}
pub fn Node::set_style(self: Node, key: String, value: DomValue) -> Unit {
  match self.kind {
    Element(el) => el.styles.set(key, value)
    _ => abort_non_elm("set style")
  }
}
pub fn Node::set_prop(self: Node, key: String, value: DomValue) -> Unit {
  match self.kind {
    Element(el) => el.props.set(key, value)
    _ => abort_non_elm("set prop")
  }
}
pub fn remove(node: Node) -> Unit { node.remove() }

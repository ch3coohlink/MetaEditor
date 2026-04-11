pub(all) enum DomRoot { Head; Body }
impl ToInt for DomRoot with to_int(self) { match self { Head => -1; Body => 0 } }
impl ToInt for DomNs with to_int(self) { match self { Html => 0; Svg => 1; MathML => 2 } }
struct Listener { id: Int } derive(Eq, ToJson)
pub(all) enum StrValue { Empty; String(String) } derive(Eq)
pub impl ToJson for StrValue with to_json(self) -> Json {
  match self { Empty => null; String(v) => v.to_json() }
}
pub(all) enum JsValue { Empty; String(String); Int(Int); Float(Float); Listener(Listener) } derive(Eq)
pub impl ToJson for JsValue with to_json(self) -> Json {
  match self {
    Empty => null
    String(v) => v.to_json()
    Int(v) => v.to_json()
    Float(v) => v.to_json()
    Listener(v) => v.to_json()
  }
}
enum Prop[T] {
  Static(T)
  Dynamic(() -> T)
}
pub enum UiScope { Name; List }
enum AttrPair {
  React(Bool)
  Id(String, StrValue, UiScope) // 想UiScope这个是可选的
  Xml(String, Prop[StrValue])
  Style(String, Prop[StrValue])
  Prop(String, Prop[JsValue])
}

pub(all) enum DomCmd {
  Create(Int, String, DomNs, StrValue)
  Insert(Int, Int, Int, Bool) // 原本 Int 和 Bool 也是可选的
  Remove(Int)
  Attr(Int, String, StrValue)
  Style(Int, String, StrValue)
  Prop(Int, String, JsValue)
} derive(Eq)
pub(all) enum DomCmdTag { Create; Insert; Remove; Attr; Style; Prop }
impl ToInt for DomCmdTag with to_int(self) {
  match self { Create => 0; Insert => 1; Remove => 2; Attr => 3; Style => 4; Prop => 5 }
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
  tag: String; ns: DomNs; clrs: ClearHooks
  mut first: Node?; mut last: Node?
  xmls: Map[String, StrValue]
  styles: Map[String, StrValue]
  props: Map[String, JsValue]
}
pub struct Node { id: Int; data: NodeKind; mut parent: Node?; mut prev: Node?; mut next: Node? }
pub(all) enum NodeKind { Text(String); Anchor(ClearHooks); Element(ElementNode) }
fn abort_non_elm(action: String) -> Unit { abort("can't \{action} on non-element node") }
fn _detach(n: Node) -> Unit {
  if n.parent is Some(parent) {
    match parent.data {
      _ => abort_non_elm("detach")
      Element(pd) => {
        if n.prev is Some(t) { t.next = n.next } else { pd.first = n.next }
        if n.next is Some(t) { t.prev = n.prev } else { pd.last = n.prev }
      }
    }
  }
}
pub fn Node::insert(self: Node, node: Node, target~: Node? = None, after~: Bool = true) -> Unit {
  match self.data {
    _ => abort_non_elm("insert")
    Element(el) => {
      let same_parent = match node.parent { Some(parent) => parent.id == self.id; None => false }
      if target is Some(tail) {
        if same_parent && after && node.prev is Some(prev) && prev.id == tail.id { return }
        if same_parent && !after && node.next is Some(next) && next.id == tail.id { return }
      } else if same_parent && node.next is None { return }
      let prev: Node? = if target is Some(tail) { if after { Some(tail) } else { tail.prev } } else { el.last }
      let next: Node? = if target is Some(tail) { if after { tail.next } else { Some(tail) } } else { None }
      _detach(node); node.parent = Some(self); node.prev = prev; node.next = next
      if prev is Some(prev) { prev.next = Some(node) } else { el.first = Some(node) }
      if next is Some(next) { next.prev = Some(node) } else { el.last = Some(node) }
    }
  }
}
pub fn Node::remove(self: Node) -> Unit {
  fn _remove(n: Node) -> Unit {
    fn _clear(clrs: ClearHooks) -> Unit { for clr in clrs { clr() }; clrs.clear() }
    match n.data {
      Anchor(clrs) => _clear(clrs)
      Element(el) => {
        let mut i = el.first; el.first = None; el.last = None
        while i is Some(c) { let next = c.next; _remove(c); i = next }
        _clear(el.clrs)
      }
    }
    n.parent = None; n.prev = None; n.next = None
  }
  _detach(self); _remove(self)
}

pub fn Node::set(self : Node, attr : AttrPair) -> Unit {
  if self.data is Element(e) {
    fn bind(next: () -> AttrPair) -> Unit {
      e.clrs.push(try effect(() => self.set(next())) catch { _ => fn() {} })
    }
    match attr {
      Xml(k, Dynamic(f)) => bind(() => Xml(k, Static(f())))
      Style(k, Dynamic(f)) => bind(() => Style(k, Static(f())))
      Prop(k, Dynamic(f)) => bind(() => Prop(k, Static(f())))
      Xml(k, Static(v)) => e.xmls.set(k, v)
      Style("", Static(Empty)) => e.props.set("style", Empty)
      Style("", Static(String(v))) => e.props.set("style", String(v))
      Style(k, Static(v)) => e.styles.set(k, v)
      Prop(k, Static(v)) => e.props.set(k, v)
      React(_) => ()
      Id(k, v, s) => ()
    }
  } else { abort_non_elm("set attr") }
}

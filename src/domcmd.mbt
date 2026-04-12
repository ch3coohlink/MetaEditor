impl ToInt for MountPoint with to_int(self) { match self { Head => -1; Body => 0; Node(n) => n.id } }
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
enum Value[T] { S(T); D(() -> T) }
pub enum UiScope { Name; List }
struct UiId { id: StrValue; scope: UiScope }
pub enum Attr {
  React; Id(UiId); Xml(String, Value[StrValue])
  Style(String, Value[StrValue]); Prop(String, Value[JsValue])
}

pub struct CreateCmd { id: Int; tag: String; ns: DomNs; value: StrValue } derive(Eq)
pub struct InsertCmd { parent: Int; child: Int; target: Int; after: Bool } derive(Eq)
pub(all) enum DomCmd {
  Create(CreateCmd); Insert(InsertCmd); Remove(Int)
  Attr(Int, String, StrValue)
  Style(Int, String, StrValue)
  Prop(Int, String, JsValue)
} derive(Eq)
impl ToInt for DomCmd with to_int(self) -> Int {
  match self { Create(_) => 0; Insert(_) => 1; Remove(_) => 2; Attr(_) => 3; Style(_) => 4; Prop(_) => 5 }
}
pub impl ToJson for DomCmd with to_json(self: DomCmd) -> Json {
  let cmd = self.to_int()
  match self {
    Create({ id, tag, ns, value }) => {
      match (value, ns) {
        (Empty, Html) => (cmd, id, tag).to_json()
        (Empty, _) => (cmd, id, tag, null, ns.to_int()).to_json()
        (String(text), Html) => (cmd, id, tag, text).to_json()
        (String(text), _) => (cmd, id, tag, text, ns.to_int()).to_json()
      }
    }
    Insert({ parent, child, target, after }) => {
      if target == 0 && after { (cmd, parent, child).to_json() }
      else if after { (cmd, parent, child, target).to_json() }
      else { (cmd, parent, child, target, false).to_json() }
    }
    Remove(id) => (cmd, id).to_json()
    Attr(id, k, v) => (cmd, id, k, v).to_json()
    Style(id, k, v) => (cmd, id, k, v).to_json()
    Prop(id, k, v) => (cmd, id, k, v).to_json()
  }
}

pub(all) enum DomNs { Html; Svg; MathML } derive(Eq)
type ClearHooks = Array[() -> Unit]
pub type Frag = Array[Node]
pub struct ElementNode {
  tag: String; ns: DomNs; clrs: ClearHooks
  mut scope: ScopeHandle?
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

pub fn Node::set(self : Node, attr : Attr) -> Unit {
  if self.data is Element(e) {
    fn bind(next : () -> Attr) -> Unit {
      e.clrs.push(effect(() => self.set(next())) catch { _ => fn() {  } })
    }
    match attr {
      Xml(k, D(f)) => bind(() => Xml(k, S(f())))
      Style(k, D(f)) => bind(() => Style(k, S(f())))
      Prop(k, D(f)) => bind(() => Prop(k, S(f())))
      Xml(k, S(v)) => e.xmls.set(k, v)
      Style("", S(Empty)) => e.props.set("style", Empty)
      Style("", S(String(v))) => e.props.set("style", String(v))
      Style(k, S(v)) => e.styles.set(k, v)
      Prop(k, S(v)) => e.props.set(k, v)
      React => {
        let handle = new_scope()
        e.scope = Some(handle)
        e.clrs.push(() => stop_scope(handle))
      }
      Id({ id, scope }) => ()
    }
  } else {
    abort_non_elm("set attr")
  }
}

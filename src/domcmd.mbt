impl ToInt for MountPoint with to_int(self) { match self { Head => -1; Body => 0; Node(n) => n.id } }
impl ToInt for DomNs with to_int(self) { match self { Html => 0; Svg => 1; MathML => 2 } }
struct Listener { id: Int } derive(Eq, ToJson)
pub(all) enum StrValue { Empty; String(String) } derive(Eq)
pub impl ToJson for StrValue with to_json(self) -> Json {
  match self { Empty => null; String(v) => v.to_json() }
}
pub(all) enum JsValue { Empty; String(String); Int(Int); Float(Float); Listener(Listener) } derive(Eq)
pub impl ToJson for JsValue with to_json(self) -> Json { match self {
    Empty => null; String(v) => v.to_json()
    Int(v) => v.to_json(); Float(v) => v.to_json(); Listener(v) => v.to_json()
}}
enum Value[T] { Static(T); Dynamic(() -> T) }
pub enum Attr {
  React; Id(UiPos); Xml(String, Value[StrValue])
  Style(String, Value[StrValue]); Prop(String, Value[JsValue])
}

pub enum UiScope { Name; List }
pub type NameScope = Map[String, Node]
let class_id : Ref[Int] = Ref::new(1)
pub struct UiPos { id: String; scope: UiScope?; class: String; style: String? }
pub fn ui(id: String, scope?: UiScope? = None, style?: String? = None) -> UiPos {
  let i = class_id.val; class_id.val = i + 1
  { id, scope, style, class: "u\{i}" }
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
pub type Frag = Array[Node]
type StrMap = Map[String, StrValue]
pub struct AnchorNode { clrs: ClearHooks }
impl HasClrs for AnchorNode with clrs(self) { self.clrs }
pub struct ElementNode {
  tag: String; ns: DomNs; mut clrs: ClearHooks?; mut scope: Scope?
  mut first: Node?; mut last: Node?; mut ui: UiPos?; mut names: NameScope?
  mut xmls: StrMap?; mut styles: StrMap?; mut props: Map[String, JsValue]?
}
impl HasClrs for ElementNode with clrs(self) {
  if self.clrs is Some(a) { a } else { let a = []; self.clrs = Some(a); a }
}
pub struct Node { id: Int; data: NodeKind; mut parent: Node?; mut prev: Node?; mut next: Node? }
fn Node::new(dom: Dom, data: NodeKind) -> Node {
  let node = { id: dom.id(), parent: None, prev: None, next: None, data }
  match data {
    Text(t) => dom.cmd(Create({ id: node.id, tag: "", ns: Html, value: String(t) }))
    Anchor(_) => dom.cmd(Create({ id: node.id, tag: "", ns: Html, value: Empty }))
    Element({ tag, ns, .. }) => dom.cmd(Create({ id: node.id, tag, ns, value: Empty }))
  }
  node
}
fn text(dom: Dom, t: String) -> Node { Node::new(dom, Text(t)) }
fn anchor(dom: Dom) -> Node { Node::new(dom, Anchor({ clrs: [] })) }
fn element(dom: Dom, tag: String, ns: DomNs) -> Node { Node::new(dom, Element({
  tag, ns, clrs: None, scope: None, first: None, last: None,
  ui: None, names: None, xmls: None, styles: None, props: None,
})) }
pub(all) enum NodeKind { Text(String); Anchor(AnchorNode); Element(ElementNode) }
fn abort_non_elm(action: String) -> Unit { abort("can't \{action} on non-element node") }
fn parent_id(n: Node?) -> Int { match n { Some(n) => n.id; None => 0 } }
fn _detach(n: Node) -> Unit {
  if n.parent is Some(parent) {
    match parent.data {
      Element(pd) => {
        if n.prev is Some(t) { t.next = n.next } else { pd.first = n.next }
        if n.next is Some(t) { t.prev = n.prev } else { pd.last = n.prev }
      }
      _ => abort_non_elm("detach")
    }
  }
}
pub fn Node::insert(self: Node, dom: Dom, node: Node, target~: Node? = None, after~: Bool = true) -> Unit {
  match self.data {
    Element(el) => {
      let sp = match node.parent { Some(parent) => parent.id == self.id; None => false }
      if target is Some(t) {
        if sp && after && node.prev is Some(prev) && prev.id == t.id { return }
        if sp && !after && node.next is Some(next) && next.id == t.id { return }
      } else if sp && node.next is None { return }
      let p: Node? = if target is Some(t) { if after { Some(t) } else { t.prev } } else { el.last }
      let n: Node? = if target is Some(t) { if after { t.next } else { Some(t) } } else { None }
      _detach(node); node.parent = Some(self); node.prev = p; node.next = n
      if p is Some(p) { p.next = Some(node) } else { el.first = Some(node) }
      if n is Some(n) { n.prev = Some(node) } else { el.last = Some(node) }
      dom.update_names(node)
      dom.cmd(Insert({ parent: self.id, child: node.id, target: parent_id(target), after }))
    }; _ => abort_non_elm("insert")
  }
}
pub fn Node::remove(self: Node, dom: Dom) -> Unit {
  fn _remove(n: Node) -> Unit {
    match n.data {
      Anchor(a) => { clean(a) }
      Element(el) => {
        let mut i = el.first; el.first = None; el.last = None
        while i is Some(c) { let next = c.next; _remove(c); i = next }
        if el.clrs is Some(_) { clean(el) }
      }; _ => ()
    }
    n.parent = None; n.prev = None; n.next = None
  }
  dom.update_names(self, bind=false)
  _detach(self); _remove(self)
  dom.cmd(Remove(self.id))
}
pub fn Node::set(self : Node, dom: Dom, attr : Attr) -> Unit {
  if self.data is Element(e) {
    fn xmls(k: String, v: StrValue) {
      (if e.xmls is Some(a) { a } else { let a = Map::new(); e.xmls = Some(a); a }).set(k, v)
      dom.cmd(Attr(self.id, k, v))
    }
    fn stys(k: String, v: StrValue) {
      (if e.styles is Some(a) { a } else { let a = Map::new(); e.styles = Some(a); a }).set(k, v)
      dom.cmd(Style(self.id, k, v))
    }
    fn prps(k: String, v: JsValue) {
      (if e.props is Some(a) { a } else { let a = Map::new(); e.props = Some(a); a }).set(k, v)
      dom.cmd(Prop(self.id, k, v))
    }
    fn bind(next : () -> Attr) { onclr(e, effect(() => self.set(dom, next()))) }
    match attr {
      Xml(k, Dynamic(f)) => bind(() => Xml(k, Static(f())))
      Style(k, Dynamic(f)) => bind(() => Style(k, Static(f())))
      Prop(k, Dynamic(f)) => bind(() => Prop(k, Static(f())))
      Xml(k, Static(v)) => { xmls(k, v) }
      Style("", Static(v)) => { prps("style", match v { Empty => Empty; String(t) => String(t) }) }
      Style(k, Static(v)) => { stys(k, v) }
      Prop(k, Static(v)) => { prps(k, v) }
      React => { let s = Scope::new(); e.scope = Some(s); onclr(e, () => s.stop()) }
      Id(ui) => {
        e.ui = Some(ui); xmls("class", String(ui.class))
        if ui.scope is Some(Name) && e.names is None { e.names = Some(Map::new()) }
      }
    }
  } else { abort_non_elm("set attr") }
}

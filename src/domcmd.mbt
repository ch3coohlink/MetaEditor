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
pub fn ui(id: String, scope?: UiScope? = None, style?: String? = None) -> UiPos raise {
  if id == "" { fail("ui-id is empty") }
  if id.trim() != id { fail("ui-id has leading or trailing whitespace: \{id}") }
  for ch in id {
    if ch == '/' || ch == ':' || ch == '\\' || ch.is_whitespace() {
      fail("ui-id has invalid char: \{id}")
    }
  }
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
pub struct AnchorData { clrs: ClearHooks }
impl HasClrs for AnchorData with clrs(self) { self.clrs }
pub struct ElementData {
  tag: String; ns: DomNs; mut clrs: ClearHooks?; mut scope: Scope?
  mut first: Node?; mut last: Node?; mut ui: UiPos?; mut names: NameScope?
  mut xmls: StrMap?; mut styles: StrMap?; mut props: Map[String, JsValue]?
}
impl HasClrs for ElementData with clrs(self) {
  if self.clrs is Some(a) { a } else { let a = []; self.clrs = Some(a); a }
}
fn text(dom: Dom, t: String) -> Node { Node::new(dom, Text(t)) }
fn anchor(dom: Dom) -> Node { Node::new(dom, Anchor({ clrs: [] })) }
fn empty_elm (tag: String, ns: DomNs, names: NameScope?) -> NodeData { Element({
  tag, ns, clrs: None, scope: None, first: None, last: None,
  ui: None, names, xmls: None, styles: None, props: None,
}) }
fn element(dom: Dom, tag: String, ns: DomNs) -> Node { Node::new(dom, empty_elm(tag, ns, None)) }
fn root(id: Int, tag: String, ns~: DomNs = Html) -> Node {
  { id, parent: None, prev: None, next: None, data: empty_elm(tag, ns, Some(Map::new())) }}
fn fail_non_elm(action: String) -> Unit raise { fail("can't \{action} on non-element node") }
fn name_host(node: Node?) -> Node? {
  let mut i = node; while i is Some(p) {
    match p.data { Element(e) => if e.names is Some(_) { return Some(p) }; _ => () }; i = p.parent
  }; None
}
pub(all) enum NodeData { Text(String); Anchor(AnchorData); Element(ElementData) }
pub struct Node { id: Int; data: NodeData; mut parent: Node?; mut prev: Node?; mut next: Node? }
fn Node::new(dom: Dom, data: NodeData) -> Node {
  let node = { id: dom.id(), parent: None, prev: None, next: None, data }
  let { id, .. } = node; match data {
    Text(t) => dom.cmd(Create({ id, tag: "", ns: Html, value: String(t) }))
    Anchor(_) => dom.cmd(Create({ id, tag: "", ns: Html, value: Empty }))
    Element({ tag, ns, .. }) => dom.cmd(Create({ id, tag, ns, value: Empty }))
  }; node
}
fn Node::names(self: Node) -> NameScope raise {
  match self.data {
    Element(e) => match e.names { Some(n) => n; None => fail("node has no names") }
    _ => fail("node has no names")
  }
}
fn Node::bind_name(self: Node, host: Node, bind~: Bool = true) -> Node raise {
  let names = host.names()
  let scope = match host.data {
    Element(el) => match el.ui { Some(ui) if ui.scope is Some(Name) => Some(ui.id); _ => None }
    _ => None
  }
  match self.data {
    Element(el) => match el.ui {
      Some(ui) => {
        if bind {
          match scope {
            Some(scope) => {
              if ui.id == scope || ui.id.has_prefix(scope + "-") || ui.id.has_prefix(scope + "_") {
                fail("ui-id repeats current scope prefix: \{scope}/\{ui.id}")
              }
            }
            None => ()
          }
          if names.get(ui.id) is Some(old) && old.id != self.id { fail("duplicate ui-id: \{ui.id}") }
          names.set(ui.id, self)
        } else { ignore(names.remove(ui.id)) }
        if ui.scope is Some(Name) { self } else { host }
      }
      None => host
    }
    _ => host
  }
}
fn Node::walk(self: Node, enter: (Node) -> Bool raise, leave: () -> Unit) -> Unit raise {
  if enter(self) { leave(); return }
  match self.data {
    Element(el) => {
      let mut i = el.first
      while i is Some(child) { let next = child.next; child.walk(enter, leave); i = next }
    }
    _ => ()
  }
  leave()
}
fn Node::detach(n: Node) -> Unit raise {
  if n.parent is Some(parent) {
    match parent.data {
      Element(pd) => {
        if n.prev is Some(t) { t.next = n.next } else { pd.first = n.next }
        if n.next is Some(t) { t.prev = n.prev } else { pd.last = n.prev }
      }; _ => fail_non_elm("detach")
    }
  }
}
pub fn Node::insert(self: Node, dom: Dom, node: Node,
  target~: Node? = None, after~: Bool = true, fresh~: Bool = false) -> Unit raise {
  match self.data {
    Element(el) => {
      if !fresh {
        let sp = match node.parent { Some(parent) => parent.id == self.id; None => false }
        if target is Some(t) {
          if sp && after && node.prev is Some(prev) && prev.id == t.id { return }
          if sp && !after && node.next is Some(next) && next.id == t.id { return }
        } else if sp && node.next is None { return }
      }
      let old_host = if fresh { None } else { name_host(node.parent) }
      let p: Node? = if target is Some(t) { if after { Some(t) } else { t.prev } } else { el.last }
      let n: Node? = if target is Some(t) { if after { t.next } else { Some(t) } } else { None }
      if !fresh { node.detach() }
      node.parent = Some(self); node.prev = p; node.next = n
      if p is Some(p) { p.next = Some(node) } else { el.first = Some(node) }
      if n is Some(n) { n.prev = Some(node) } else { el.last = Some(node) }
      if !fresh {
        let new_host = name_host(node.parent)
        let same = match (old_host, new_host) {
          (Some(a), Some(b)) => a.id == b.id
          (None, None) => true
          _ => false
        }
        if !same {
          match old_host { Some(host) => dom.update_names(node, host, bind=false); None => () }
          match new_host { Some(host) => dom.update_names(node, host); None => () }
        }
      }
      dom.cmd(Insert({ parent: self.id, child: node.id, after,
        target: match target { Some(n) => n.id; None => 0 } }))
    }; _ => fail_non_elm("insert")
  }
}
pub fn Node::remove(self: Node, dom: Dom) -> Unit raise {
  fn _remove(n: Node) -> Unit raise {
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
  match name_host(self.parent) { Some(host) => dom.update_names(self, host, bind=false); None => () }
  self.detach(); _remove(self)
  dom.cmd(Remove(self.id))
}
pub fn Node::set(self : Node, dom: Dom, attr : Attr) -> Unit raise {
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
    fn bind(next : () -> Attr raise) -> Unit {
      onclr(e, effect(() => {
        try next() catch { err => dom.report("\{err}") } noraise {
          attr => try self.set(dom, attr) catch { err => dom.report("\{err}") }
        }
      }))
    }
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
  } else { fail_non_elm("set attr") }
}

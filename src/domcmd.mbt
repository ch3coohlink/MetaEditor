impl ToInt for DomNs with to_int(self) { match self { Html => 0; Svg => 1; MathML => 2 } }
pub(all) enum StrValue { Empty; String(String) }
pub impl ToJson for StrValue with to_json(self) -> Json {
  match self { Empty => null; String(v) => v.to_json() }
}
pub(all) enum JsValue { Empty; String(String); Int(Int); Float(Float); Listener(Listener) }
pub impl ToJson for JsValue with to_json(self) -> Json { match self {
    Empty => null; String(v) => v.to_json()
    Int(v) => v.to_json(); Float(v) => v.to_json(); Listener(v) => v.to_json()
}}
enum Value[T] { Static(T); Dynamic(() -> T) }
pub enum Attr {
  React; Id(UIMeta); Xml(String, Value[StrValue])
  Style(String, Value[StrValue]); Prop(String, Value[JsValue])
  Event(EventKind, (DomEvent) -> Unit raise, EventCfg)
}

pub struct CreateCmd { id: Int; tag: String; ns: DomNs; value: StrValue }
pub struct InsertCmd { parent: Int; child: Int; target: Int; after: Bool }
pub(all) enum DomCmd {
  Create(CreateCmd); Insert(InsertCmd); Remove(Int)
  Attr(Int, String, StrValue)
  Style(Int, String, StrValue)
  Prop(Int, String, JsValue)
}
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

pub(all) enum DomNs { Html; Svg; MathML }
pub type Frag = Array[Node]
type StrMap = Map[String, StrValue]
pub struct AnchorData { clrs: ClearHooks }
impl HasClrs for AnchorData with clrs(self) { self.clrs }
pub struct ElementData {
  tag: String; ns: DomNs; mut clrs: ClearHooks?; mut scope: Scope?
  mut first: Node?; mut last: Node?
  mut xmls: StrMap?; mut styles: StrMap?; mut props: Map[String, JsValue]?
}
impl HasClrs for ElementData with clrs(self) {
  if self.clrs is Some(a) { a } else { let a = []; self.clrs = Some(a); a }
}
fn text(dom: Dom, t: String) -> Node { Node::new(dom, Text(t)) }
fn anchor(dom: Dom) -> Node { Node::new(dom, Anchor({ clrs: [] })) }
fn empty_elm (tag: String, ns: DomNs) -> NodeData { Element({
  tag, ns, clrs: None, scope: None, first: None, last: None,
  xmls: None, styles: None, props: None,
}) }
fn element(dom: Dom, tag: String, ns: DomNs) -> Node { Node::new(dom, empty_elm(tag, ns)) }
fn root(id: Int, tag: String, ns~: DomNs = Html) -> Node {
  { id, parent: None, prev: None, next: None, data: empty_elm(tag, ns), ui: None, uictx: None }}
fn fail_non_elm(action: String) -> Unit raise { fail("can't \{action} on non-element node") }
pub(all) enum NodeData { Text(String); Anchor(AnchorData); Element(ElementData) }
pub struct Node {
  id: Int; data: NodeData; mut parent: Node?; mut prev: Node?; mut next: Node?
  mut ui: UIID; mut uictx: UIID
}
fn Node::new(dom: Dom, data: NodeData) -> Node {
  let node = { id: (dom.nid)(), parent: None, prev: None, next: None, data, ui: None, uictx: None }
  let { id, .. } = node; match data {
    Text(t) => dom.cmd(Create({ id, tag: "", ns: Html, value: String(t) }))
    Anchor(_) => dom.cmd(Create({ id, tag: "", ns: Html, value: Empty }))
    Element({ tag, ns, .. }) => dom.cmd(Create({ id, tag, ns, value: Empty }))
  }; node
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
fn Node::walk(self: Node, enter: (Node) -> Bool raise, leave~: () -> Unit raise = () => ()) -> Unit raise {
  if enter(self) { leave(); return }
  if self.data is Element(el) {
    let mut i = el.first
    while i is Some(child) { let next = child.next; child.walk(enter, leave~); i = next }
  }; leave()
}
pub fn Node::first_child(self: Node) -> Node raise {
  match self.data {
    Element({ first: Some(child), .. }) => child
    Element(_) => fail("node has no child")
    _ => fail("can't read child on non-element node")
  }
}
pub fn Node::last_child(self: Node) -> Node raise {
  match self.data {
    Element({ last: Some(child), .. }) => child
    Element(_) => fail("node has no child")
    _ => fail("can't read child on non-element node")
  }
}
pub fn Node::children(self: Node) -> Array[Node] {
  let el = match self.data { Element(el) => el; _ => panic() }
  let mut c = el.first
  let a = []; while c is Some(n) { a.push(n); c = n.next }; a
}
pub fn Node::child_elements(self: Node) -> Array[Node] {
  let a = []; for c in self.children() { if c.data is Element(_) { a.push(c) } }; a
}
pub fn Node::insert(self: Node, dom: Dom, node: Node,
  target~: Node? = None, after~: Bool = true, fresh~: Bool = false) -> Unit raise {
  fn bind_ui(node: Node, scope: UIID, fresh: Bool) -> Unit raise {
    if node.ui is List(_) && !(node.data is Anchor(_)) { fail("list scope only allowed on dyn") }
    node.uictx = scope
    if fresh {
      if !(node.ui is None) && !(scope is None) { scope.add(node.ui) }
    } else {
      let child_scope = match node.ui {
        Scope(s) if s.meta.scope is Scope => {
          node.ui.rebind(scope)
          match scope { None => (); _ => scope.add(node.ui) }
          node.ui
        }
        None => scope
        _ => {
          node.ui.rebind(scope)
          match scope { None => (); _ => scope.add(node.ui) }
          scope
        }
      }
      node.walk(c => if c.id == node.id { false } else { bind_ui(c, child_scope, false); true })
    }
  }
  match self.data {
    Element(el) => {
      if !fresh {
        let sp = match node.parent { Some(parent) => parent.id == self.id; None => false }
        if target is Some(t) {
          if sp && after && node.prev is Some(prev) && prev.id == t.id { return }
          if sp && !after && node.next is Some(next) && next.id == t.id { return }
        } else if sp && node.next is None { return }
      }
      let p: Node? = if target is Some(t) { if after { Some(t) } else { t.prev } } else { el.last }
      let n: Node? = if target is Some(t) { if after { t.next } else { Some(t) } } else { None }
      if !fresh { node.detach() }
      node.parent = Some(self); node.prev = p; node.next = n
      if p is Some(p) { p.next = Some(node) } else { el.first = Some(node) }
      if n is Some(n) { n.prev = Some(node) } else { el.last = Some(node) }
      let scope = if fresh { node.uictx } else {
        match self.ui {
          Scope(s) if s.meta.scope is Scope => self.ui
          _ => self.uictx
        }
      }
      bind_ui(node, scope, fresh)
      dom.cmd(Insert({ parent: self.id, child: node.id, after,
        target: match target { Some(n) => n.id; None => 0 } }))
    }; _ => fail_non_elm("insert")
  }
}
pub fn Node::remove(self: Node, dom: Dom) -> Unit raise {
  fn unbind_ui(n: Node) -> Unit raise {
    if !(n.ui is None) { n.ui.rebind(None) }
    n.walk(c => if c.id == n.id { false } else { unbind_ui(c); true })
  }
  fn _remove(n: Node) -> Unit raise {
    match n.data {
      Anchor(a) => { clean(a) }
      Element(el) => {
        n.walk(c => if c.id == n.id { false } else { _remove(c); true })
        el.first = None; el.last = None
        if el.clrs is Some(_) { clean(el) }
      }; _ => ()
    }
    n.parent = None; n.prev = None; n.next = None
  }
  unbind_ui(self); self.detach(); _remove(self); dom.cmd(Remove(self.id))
}
pub fn Node::set(self: Node, dom: Dom, attr: Attr, scope~: UIID = None) -> Unit raise {
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
        let p = if e.props is Some(a) { a } else { let a = Map::new(); e.props = Some(a); a }
        p.set(k, v); dom.cmd(Prop(self.id, k, v))
      }
      let bind = (next: () -> Attr raise) => onclr(e, effect(() => {
        try next() catch { err => dom.report("\{err}") } noraise {
          attr => try self.set(dom, attr) catch { err => dom.report("\{err}") }
        }
      }))
      match attr {
        Id(meta) => {
          if !(self.ui is None) { fail("node ui is already set") }
          dom.mount_style(meta)
          self.ui = meta.inst(scope)
          self.ui.bind_node(Some(self))
          if meta.class != "" { xmls("class", String(meta.class)) }
        }
        Xml(k, Dynamic(f)) => bind(() => Xml(k, Static(f())))
        Style(k, Dynamic(f)) => bind(() => Style(k, Static(f())))
        Prop(k, Dynamic(f)) => bind(() => Prop(k, Static(f())))
        Event(kind, f, cfg) => prps(kind.to_string(), Listener({ kind, cfg, f }))
        Xml(k, Static(v)) => { xmls(k, v) }
        Style("", Static(v)) => { prps("style", match v { Empty => Empty; String(t) => String(t) }) }
        Style(k, Static(v)) => { stys(k, v) }
        Prop(k, Static(v)) => { prps(k, v) }
        React => { let s = Scope::new(); e.scope = Some(s); onclr(e, () => s.stop()) }
      }
  } else { fail_non_elm("set attr") }
}

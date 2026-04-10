pub struct DomState { mut next_id: Int }
pub fn dom_state() -> DomState {{ next_id: 1 }}
let current_dom: Ref[DomState?] = Ref::new(None)
fn active_dom() -> DomState { match current_dom.val { Some(dom) => dom; None => abort("dom context missing") } }
fn[T] use_dom(dom: DomState, f: () -> T) -> T {
  let prev = current_dom.val
  current_dom.val = Some(dom)
  let out = f()
  current_dom.val = prev
  out
}
fn get_id() -> Int { let dom = active_dom(); let id = dom.next_id; dom.next_id = id + 1; id }

pub(all) enum DomNs { Html; Svg; MathML }
pub struct Node { id: Int; mut parent: Node?; kind: NodeKind }
pub type Frag = Array[Node]
pub(all) enum NodeKind { Text(String); Element(String, DomNs, Frag) }
pub(all) enum Child {
  Null; Lazy((DomNs) -> Frag); Str(String); Int(Int); Arr(Array[Child]); Dyn(() -> Child)
}

trait HTag { render(Self, Array[(String, String)], Array[Child]) -> Child }
pub fn[T: HTag] h(t: T, a: Array[(String, String)], c: Array[Child]) -> Child { t.render(a, c) }
impl HTag for Comp with render(self, attrs, children) { (self.render)(attrs, children) }
impl HTag for String with render(self, _, children) {
  Lazy(fn(ns: DomNs) -> Frag {
    let mut ns = if self == "svg" { Svg } else if self == "math" { MathML } else { ns }
    let node = { id: get_id(), parent: None, kind: Element(self, ns, []) }
    ns = Html
    append(node, children, ns)
    [node]
  })
}
fn append(parent: Node, children: Array[Child], ns: DomNs) -> Unit {
  match parent.kind {
    Text(_) => abort("cannot append to text node")
    Element(_, _, nodes) => {
      for item in children {
        for node in child(item, ns = ns) {
          node.parent = Some(parent)
          nodes.push(node)
        }
      }
    }
  }
}

pub struct Comp { render: (Array[(String, String)], Array[Child]) -> Child }
pub fn comp(f: (Array[(String, String)], Array[Child]) -> Child) -> Comp {{ render: f }}
fn text(t: String) -> Node { { id: get_id(), parent: None, kind: Text(t) } }

fn child(c: Child, ns~: DomNs = Html) -> Frag {
  match c {
    Null => []
    Lazy(f) => f(ns)
    Str(s) => [text(s)]
    Int(i) => [text(i.to_string())]
    Arr(items) => {
      let nodes: Frag = []
      for item in items { for node in child(item, ns~) { nodes.push(node) } }
      nodes
    }
    Dyn(f) => {
      let anchor = text("")
      let old: Ref[Frag] = Ref::new([])
      let next = child(f(), ns = ns)
      old.val = next
      let _ = effect(fn() {
        let next = child(f(), ns = ns)
        match anchor.parent {
          Some(parent) => moddom(parent, next, old.val, anchor)
          None => ()
        }
        old.val = next
      }) catch { _ => fn() {} }
      let out = [anchor]
      for node in old.val { out.push(node) }
      out
    }
  }
}

fn moddom(parent: Node, next: Frag, old: Frag, anchor: Node) -> Unit {
  match parent.kind {
    Text(_) => abort("cannot patch text node")
    Element(_, _, nodes) => {
      let patched: Frag = []
      let mut inserted = false
      for node in next { node.parent = Some(parent) }
      for node in nodes {
        let mut removed = false
        for prev in old { if prev.id == node.id { removed = true } }
        if removed { continue }
        patched.push(node)
        if node.id == anchor.id { inserted = true; for item in next { patched.push(item) } }
      }
      if !inserted { abort("anchor missing in moddom") }
      nodes.clear()
      for node in patched { nodes.push(node) }
    }
  }
}

pub fn[T] run(dom: DomState, f: () -> T) -> T { use_dom(dom, f) }

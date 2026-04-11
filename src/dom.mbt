pub struct DomState { mut next_id: Int }
pub fn dom_state() -> DomState {{ next_id: 1 }}
let current_dom: Ref[DomState?] = Ref::new(None)
fn active_dom() -> DomState { match current_dom.val { Some(dom) => dom; None => abort("dom context missing") } }
fn[T] use_dom(dom: DomState, f: () -> T) -> T {
  let prev = current_dom.val; current_dom.val = Some(dom)
  let out = f(); current_dom.val = prev; out
}
fn get_id() -> Int { let dom = active_dom(); let id = dom.next_id; dom.next_id = id + 1; id }

pub(all) enum DomNs { Html; Svg; MathML } derive(Eq)
pub struct Node { id: Int; mut parent: Node?; kind: NodeKind }
type Frag = Array[Node]
type ClearHooks =Array[() -> Unit]
pub(all) enum NodeKind { Text(String); Anchor(ClearHooks); Element(String, DomNs, Frag, ClearHooks) }
pub(all) enum Child { Null; Lazy((DomNs) -> Frag); Str(String); Int(Int); Arr(Array[Child]); Dyn(() -> Child) }
trait HTag { render(Self, Array[(String, String)], Array[Child]) -> Child }
pub fn[T: HTag] h(t: T, a: Array[(String, String)], c: Array[Child]) -> Child { t.render(a, c) }
impl HTag for Comp with render(self, attrs, children) { (self.render)(attrs, children) }
impl HTag for String with render(self, _, children) {
  Lazy(fn(ns: DomNs) -> Frag {
    let ns = if self == "svg" { Svg } else if self == "math" { MathML } else { ns }
    let node = { id: get_id(), parent: None, kind: Element(self, ns, [], []) }
    append(node, children, if self == "foreignObject" { Html } else { ns })
    [node]
  })
}
fn append(parent: Node, children: Array[Child], ns: DomNs) -> Unit {
  match parent.kind {
    Text(_) => abort("cannot append to text node")
    Anchor(_) => abort("cannot append to anchor node")
    Element(_, _, nodes, _) => {
      for item in children {
        for node in child(item, ns~) { node.parent = Some(parent); nodes.push(node) }
      }
    }
  }
}
pub fn remove(node: Node) -> Unit {
  fn _clear(clrs: ClearHooks) -> Unit { for clr in clrs { clr() }; clrs.clear() }
  fn _remove(node: Node) -> Unit {
    match node.kind {
      Text(_) => ()
      Anchor(clrs) => _clear(clrs)
      Element(_, _, children, clrs) => {
        for child in children { child.parent = None; _remove(child) }
        children.clear()
        _clear(clrs)
      }
    }
  }
  match node.parent {
    Some(parent) =>
      match parent.kind {
        Text(_) => abort("cannot remove from text node")
        Anchor(_) => abort("cannot remove from anchor node")
        Element(_, _, children, _) => {
          for i in 0..<children.length() {
            if children[i].id == node.id { ignore(children.remove(i)); break }
          }
        }
      }
    None => ()
  }
  node.parent = None
  _remove(node)
}

pub struct Comp { render: (Array[(String, String)], Array[Child]) -> Child }
pub fn comp(f: (Array[(String, String)], Array[Child]) -> Child) -> Comp {{ render: f }}
fn text(t: String) -> Node { { id: get_id(), parent: None, kind: Text(t) } }
fn anchor() -> Node { { id: get_id(), parent: None, kind: Anchor([]) } }

fn child(c: Child, ns~: DomNs = Html) -> Frag {
  match c {
    Null => []
    Lazy(f) => f(ns)
    Str(s) => [text(s)]
    Int(i) => [text(i.to_string())]
    Arr(items) => flat_map(items, item => child(item, ns~))
    Dyn(f) => {
      let anchor = anchor()
      let scope = new_scope()
      let old: Ref[Frag] = Ref::new([])
      let next = child(f(), ns~)
      old.val = next
      match anchor.kind {
        Anchor(clrs) => {
          clrs.push(() => stop_scope(scope))
          clrs.push(fn() {
            let current = old.val.copy()
            old.val = []
            for node in current { remove(node) }
          })
        }
        _ => abort("dyn anchor kind mismatch")
      }
      let _ = with_scope(scope, fn() raise {
        effect(fn() {
          let next = child(f(), ns~)
          match anchor.parent {
            Some(parent) => moddom(parent, next, old.val, anchor)
            None => ()
          }
          old.val = next
        })
      }) catch { _ => fn() {} }
      [anchor] + old.val
    }
  }
}

fn moddom(parent: Node, next: Frag, old: Frag, anchor: Node) -> Unit {
  match parent.kind {
    Text(_) => abort("cannot patch text node")
    Anchor(_) => abort("cannot patch anchor node")
    Element(_, _, nodes, _) => {
      let removed: Frag = []
      for prev in old {
        let mut keep = false
        for node in next {
          if !keep && node.id == prev.id { keep = true }
        }
        if !keep { removed.push(prev) }
      }
      for node in removed { remove(node) }
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

priv struct HMapEntry { index: Cel[Int]; nodes: Frag }
pub fn[T: Eq + Hash] h_map(ui_id?: String? = None, items: Array[T], render: (T, () -> Int) -> Child,
) -> Child { h_map_dyn(ui_id~, fn() { items.mapi((i, item) => (item, i)) }, render) }
pub fn[T: Eq + Hash] h_map_dyn(
  ui_id?: String? = None,
  source: () -> Array[(T, Int)],
  render: (T, () -> Int) -> Child,
) -> Child {
  ignore(ui_id)
  let cache: Ref[Map[T, Array[HMapEntry]]] = Ref::new(Map::new())
  Dyn(fn() {
    let items = source()
    Lazy(fn(ns: DomNs) -> Frag {
      let prev = cache.val
      let next: Map[T, Array[HMapEntry]] = Map::new()
      let out: Frag = []
      for item in items {
        let key = item.0
        let index_value = item.1
        let entry = match prev.get(key) {
          Some(bucket) if bucket.length() > 0 => {
            let reused = bucket.remove(0)
            reused.index.set(index_value)
            reused
          }
          None => {
            let index = cel(index_value)
            { index, nodes: child(render(key, fn() { index.get() }), ns~) }
          }
          _ => {
            let index = cel(index_value)
            { index, nodes: child(render(key, fn() { index.get() }), ns~) }
          }
        }
        match next.get(key) {
          Some(bucket) => bucket.push(entry)
          None => next.set(key, [entry])
        }
        for node in entry.nodes { out.push(node) }
      }
      cache.val = next
      out
    })
  })
}

pub fn[T] run(dom: DomState, f: () -> T) -> T { use_dom(dom, f) }

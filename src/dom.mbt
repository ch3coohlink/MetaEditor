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
    _ => abort("cannot append to non-element node")
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
        _ => abort("cannot remove from non-element node")
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
      let mut old: Frag = []
      match anchor.kind {
        Anchor(clrs) => {
          clrs.push(() => stop_scope(scope))
          clrs.push(fn() {
            let current = old.copy(); old = []
            for node in current { remove(node) }
          })
        }
        _ => abort("dyn anchor kind mismatch")
      }
      let _ = with_scope(scope, fn() raise {
        effect(fn() {
          let next = child(f(), ns~)
          if anchor.parent is Some(parent) { mod_dom(parent, next, old, anchor) }
          else { for node in next { node.parent = None } }
          old = next
        })
      }) catch { _ => fn() {} }
      old + [anchor]
    }
  }
}

fn mod_dom(parent: Node, next: Frag, old: Frag, anchor: Node) -> Unit {
  match parent.kind {
    _ => abort("cannot patch non-element node")
    Element(_, _, p, _) => {
      let seen : Set[Int] = Set::new(); for n in next { seen.add(n.id) }
      let mut tail = anchor
      for n in old { if !seen.contains(n.id) { remove(p, n) } }
      for n in next {
        if(n.id != tail.id) { insertBefore(p, n, tail) }
        tail = n
      }
    }
  }
}

priv struct HMapEntry { index: Cel[Int]; frag: Frag }
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
          _ => {
            let index = cel(index_value)
            { index, frag: child(render(key, fn() { index.get() }), ns~) }
          }
        }
        match next.get(key) {
          Some(bucket) => bucket.push(entry)
          None => next.set(key, [entry])
        }
        for node in entry.frag { out.push(node) }
      }
      cache.val = next
      out
    })
  })
}

pub fn[T] run(dom: DomState, f: () -> T) -> T { use_dom(dom, f) }

pub struct DomState { mut next_id: Int }
pub fn dom_state() -> DomState {{ next_id: 1 }}
let current_dom: Ref[DomState?] = Ref::new(None)
fn active_dom() -> DomState { match current_dom.val { Some(dom) => dom; None => abort("dom context missing") } }
fn[T] use_dom(dom: DomState, f: () -> T) -> T {
  let prev = current_dom.val; current_dom.val = Some(dom)
  let out = f(); current_dom.val = prev; out
}
fn get_id() -> Int { let dom = active_dom(); let id = dom.next_id; dom.next_id = id + 1; id }

type Attrs = Array[AttrPair]
type Children = Array[Child]
pub(all) enum Child { Null; Lazy((DomNs) -> Frag); Str(String); Int(Int); Arr(Children); Dyn(() -> Child) }
trait HTag { render(Self, Attrs, Children) -> Child }
pub fn[T: HTag] h(t: T, a: Attrs, c: Children) -> Child { t.render(a, c) }
impl HTag for Comp with render(comp, attrs, cs) { (comp.render)(attrs, cs) }
impl HTag for String with render(tag, attrs, cs) {
  Lazy(fn(ns: DomNs) -> Frag {
    let ns = if tag == "svg" { Svg } else if tag == "math" { MathML } else { ns }
    let node = {
      id: get_id(), parent: None, prev: None, next: None, kind: Element({
        tag: tag, ns, first_child: None, last_child: None,
        attrs: Map::new(), styles: Map::new(), props: Map::new(), clrs: [],
      }),
    }
    for a in attrs { node.set(a) }
    append(node, cs, if tag == "foreignObject" { Html } else { ns })
    [node]
  })
}
fn append(parent: Node, cs: Children, ns: DomNs) -> Unit {
  match parent.kind {
    _ => abort("cannot append to non-element node")
    Element(_) => for item in cs { for node in child(item, ns~) { parent.append_child(node) } }
  }
}

pub struct Comp { render: (Attrs, Children) -> Child }
pub fn comp(f: (Attrs, Children) -> Child) -> Comp {{ render: f }}
fn text(t: String) -> Node { { id: get_id(), parent: None, prev: None, next: None, kind: Text(t) } }
fn anchor() -> Node { { id: get_id(), parent: None, prev: None, next: None, kind: Anchor([]) } }

fn child(c: Child, ns~: DomNs = Html) -> Frag {
  match c {
    Null => []
    Lazy(f) => f(ns)
    Str(s) => [text(s)]
    Int(i) => [text(i.to_string())]
    Arr(items) => flat_map(items, item => child(item, ns~))
    Dyn(f) => {
      let anchor = anchor()
      let mut old: Frag = []
      let stop = effect(fn() {
        let next = child(f(), ns~)
        if anchor.parent is Some(parent) { mod_dom(parent, next, old, anchor) }
        old = next
      }) catch { _ => fn() {} }
      match anchor.kind {
        Anchor(clrs) => {
          clrs.push(stop)
          clrs.push(fn() {
            let current = old.copy(); old = []
            for n in current { n.remove() }
          })
        }
        _ => abort("dyn anchor kind mismatch")
      }
      [anchor] + old
    }
  }
}

fn mod_dom(parent: Node, next: Frag, old: Frag, anchor: Node) -> Unit {
  match parent.kind {
    _ => abort("cannot patch non-element node")
    Element(_) => {
      let seen : Set[Int] = Set::new(); for n in next { seen.add(n.id) }
      for n in old { if !seen.contains(n.id) { n.remove() } }
      let mut tail = anchor
      for n in next {
        if n.id != tail.id { parent.insert_after(n, tail) }
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

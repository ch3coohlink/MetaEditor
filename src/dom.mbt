pub struct Dom { mut next_id: Int; emit: (DomCmd) -> Unit }
pub(all) enum MountPoint { Head; Body; Node(Node) }
pub fn Dom::new(emit?: (DomCmd) -> Unit = fn(_) {}) -> Dom { { next_id: 1, emit } }
pub fn Dom::id(d: Dom) -> Int { let id = d.next_id; d.next_id = id + 1; id }
pub fn Dom::cmd(d: Dom, cmd: DomCmd) -> Unit { (d.emit)(cmd) }
pub fn Dom::mount(d: Dom, t: MountPoint, c: Child) -> Unit {
  match t {
    Node(p) => for node in child(d, c) { p.insert(d, node) }
    Head | Body => for node in child(d, c) {
      d.cmd(Insert({ parent: t.to_int(), child: node.id, target: 0, after: true }))
    }
  }
}

type Attrs = Array[Attr]
type Children = Array[Child]
pub(all) enum Child { Null; Lazy((Dom, DomNs) -> Frag); Str(String); Int(Int); Arr(Children); Dyn(() -> Child) }
trait HTag { render(Self, Attrs, Children) -> Child }
pub fn[T: HTag] h(tag: T, attrs: Attrs, children: Children) -> Child { tag.render(attrs, children) }
impl HTag for Comp with render(comp, attrs, cs) { (comp.render)(attrs, cs) }
impl HTag for String with render(tag, attrs, cs) {
  Lazy(fn(dom: Dom, ns: DomNs) -> Frag {
    let ns = match tag { "svg" => Svg; "math" => MathML; _ => ns }
    let node = element(dom, tag, ns)
    for a in attrs { node.set(dom, a) }
    append(dom, node, cs, match tag { "foreignObject" => Html; _ => ns })
    [node]
  })
}
fn append(dom: Dom, parent: Node, cs: Children, ns: DomNs) -> Unit {
  match parent.data {
    _ => abort("cannot append to non-element node")
    Element(_) => for item in cs { for node in child(dom, item, ns~) { parent.insert(dom, node) } }
  }
}

pub struct Comp { render: (Attrs, Children) -> Child }
pub fn comp(f: (Attrs, Children) -> Child) -> Comp {{ render: f }}

fn child(dom: Dom, c: Child, ns~: DomNs = Html) -> Frag {
  match c {
    Null => []
    Lazy(f) => f(dom, ns)
    Str(s) => [text(dom, s)]
    Int(i) => [text(dom, i.to_string())]
    Arr(items) => flat_map(items, item => child(dom, item, ns~))
    Dyn(f) => {
      let anchor = anchor(dom)
      let mut old: Frag = []
      let stop = effect(fn() {
        let next = child(dom, f(), ns~)
        match anchor.parent { Some(p) => mod_dom(dom, p, next, old, anchor) }
        old = next
      }) catch { _ => fn() {} }
      match anchor.data {
        Anchor(clrs) => {
          clrs.push(stop)
          clrs.push(fn() {
            let current = old.copy(); old = []
            for n in current { n.remove(dom) }
          })
        }
        _ => abort("dyn anchor kind mismatch")
      }
      [anchor] + old
    }
  }
}

fn mod_dom(dom: Dom, parent: Node, next: Frag, old: Frag, anchor: Node) -> Unit {
  match parent.data {
    _ => abort("cannot patch non-element node")
    Element(_) => {
      let seen : Set[Int] = Set::new(); for n in next { seen.add(n.id) }
      for n in old { if !seen.contains(n.id) { n.remove(dom) } }
      let mut tail = anchor
      for n in next {
        if n.id != tail.id { parent.insert(dom, n, target = Some(tail)) }
        tail = n
      }
    }
  }
}

priv struct HMapEntry { index: Cel[Int]; frag: Frag }
pub fn[T: Eq + Hash] h_map(ui_id?: String? = None, items: Array[T], render: (T, () -> Int) -> Child,
) -> Child { h_map_dyn(ui_id~, fn() { items.mapi((i, item) => (item, i)) }, render) }
pub fn[T: Eq + Hash] h_map_dyn(
  ui_id?: String? = None, source: () -> Array[(T, Int)], render: (T, () -> Int) -> Child,
) -> Child {
  ignore(ui_id)
  let cache: Ref[Map[T, Array[HMapEntry]]] = Ref::new(Map::new())
  Dyn(fn() {
    let items = source()
    // TODO: refactor
    Lazy(fn(dom: Dom, ns: DomNs) -> Frag {
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
            { index, frag: child(dom, render(key, fn() { index.get() }), ns~) }
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

pub struct Dom { mut next_id: Int; emit: (DomCmd) -> Unit; head: Node; body: Node }
pub fn Dom::new(emit~: (DomCmd) -> Unit = fn(_) {}) -> Dom {
  { next_id: 3, emit, head: root(1, "head"), body: root(2, "body") } }
pub fn Dom::id(d: Dom) -> Int { let id = d.next_id; d.next_id = id + 1; id }
pub fn Dom::cmd(d: Dom, cmd: DomCmd) -> Unit { (d.emit)(cmd) }
pub fn Dom::mount(d: Dom, parent: Node, c: Child) -> Unit {
  for node in child(d, c, parent.names()) { parent.insert(d, node, fresh=true) }
}
pub fn Dom::resolve(self: Dom, path: String) -> Int raise {
  let path = path.trim().to_string()
  if path == "" { fail("query is empty") }
  let parts = [..path.split("/").map(v => v.to_string())]
  fn resolve_in(root: Node, parts: Array[String], path: String) -> Int raise {
    let mut names = root.names()
    for i = 0; i < parts.length(); i = i + 1 {
      let p = parts[i]; if p == "" { fail("query has empty segment: \{path}") }
      match names.get(p) {
        Some(next) => {
          if i + 1 == parts.length() { return next.id }
          match next.data {
            Element(el) => match el.names {
              Some(s) => names = s
              None => fail("query scope not found: \{path}")
            }; _ => fail("query scope not found: \{path}")
          }
        }; None => fail("query not found: \{path}")
      }
    }
    fail("query is empty")
  }
  let body: Result[Int, _] = try? resolve_in(self.body, parts, path)
  match body { Ok(id) => id; Err(_) => resolve_in(self.head, parts, path) }
}
fn Dom::update_names(_: Dom, node: Node, host: Node, bind~: Bool = true) -> Unit {
  fn walk(node: Node, names: NameScope, bind: Bool) -> Unit {
    let stop = match node.data {
      Element(el) => match el.ui {
        Some(ui) => {
          if bind {
            if names.get(ui.id) is Some(old) && old.id != node.id { abort("duplicate ui-id: \{ui.id}") }
            names.set(ui.id, node)
          } else { ignore(names.remove(ui.id)) }
          ui.scope is Some(Name)
        }
        None => false
      }
      _ => false
    }
    if stop { return }
    match node.data {
      Element(el) => {
        let mut i = el.first
        while i is Some(child) { let next_i = child.next; walk(child, names, bind); i = next_i }
      }
      _ => ()
    }
  }
  walk(node, host.names(), bind)
}

type Attrs = Array[Attr]
type Children = Array[Child]
pub(all) enum Child { Lazy((Dom, NameScope, DomNs) -> Frag)
  Null; Str(String); Int(Int); Arr(Children); Dyn(() -> Child) }
trait HTag { render(Self, Attrs, Children) -> Child }
pub fn[T: HTag] h(tag: T, attrs: Attrs, children: Children) -> Child { tag.render(attrs, children) }
impl HTag for Comp with render(comp, attrs, cs) { (comp.render)(attrs, cs) }
impl HTag for String with render(tag, attrs, cs) {
  fn bind_name(node: Node, names: NameScope) -> NameScope {
    match node.data {
      Element(el) => match el.ui {
        Some(ui) => {
          if names.get(ui.id) is Some(old) && old.id != node.id { abort("duplicate ui-id: \{ui.id}") }
          names.set(ui.id, node)
          if ui.scope is Some(Name) { node.names() } else { names }
        }
        None => names
      }
      _ => names
    }
  }
  fn append(dom: Dom, parent: Node, cs: Children, ns: DomNs, names: NameScope) -> Unit {
    match parent.data {
      Element(_) => for item in cs {
        for node in child(dom, item, ns~, names) { parent.insert(dom, node, fresh=true) }
      }
      _ => abort("cannot append to non-element node")
    }
  }
  Lazy(fn(dom, names, ns) {
    let ns = match tag { "svg" => Svg; "math" => MathML; _ => ns }
    let node = element(dom, tag, ns)
    for a in attrs { node.set(dom, a) }
    append(dom, node, cs, match tag { "foreignObject" => Html; _ => ns }, bind_name(node, names))
    [node]
  })
}

pub struct Comp { render: (Attrs, Children) -> Child }
pub fn comp(f: (Attrs, Children) -> Child) -> Comp {{ render: f }}

fn child(dom: Dom, c: Child, names: NameScope, ns~: DomNs = Html) -> Frag {
  match c {
    Null => []
    Lazy(f) => f(dom, names, ns)
    Str(s) => [text(dom, s)]
    Int(i) => [text(dom, i.to_string())]
    Arr(items) => flat_map(items, item => child(dom, item, names, ns~))
    Dyn(f) => {
      fn mod_dom(dom: Dom, parent: Node, next: Frag, old: Frag, anchor: Node) -> Unit {
        match parent.data {
          Element(_) => {
            let seen : Set[Int] = Set::new(); for n in next { seen.add(n.id) }
            for n in old { if !seen.contains(n.id) { n.remove(dom) } }
            let mut tail = anchor
            for n in next {
              if n.id != tail.id { parent.insert(dom, n, target = Some(tail)) }
              tail = n
            }
          }
          _ => abort("cannot patch non-element node")
        }
      }
      let anchor = anchor(dom)
      let mut old: Frag = []
      match anchor.data {
        Anchor(a) => {
          onclr(a, effect(fn() {
            let next = child(dom, f(), names, ns~)
            match anchor.parent { Some(p) => mod_dom(dom, p, next, old, anchor); _ => () }
            old = next
          }))
          onclr(a, fn() { let c = old.copy(); old = []; for n in c { n.remove(dom) } })
        }
        _ => abort("dyn anchor kind mismatch")
      }
      [anchor] + old
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
    Lazy(fn(dom, names, ns) {
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
            { index, frag: child(dom, render(key, fn() { index.get() }), names, ns~) }
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

pub struct Dom { mut next_id: Int; head: Node; body: Node
  emit: (DomCmd) -> Unit; on_error: (String) -> Unit }
pub fn Dom::new(emit~: (DomCmd) -> Unit = fn(_) {}, on_error~: (String) -> Unit = fn(_) {}) -> Dom {
  { next_id: 3, emit, on_error, head: root(1, "head"), body: root(2, "body") } }
pub fn Dom::id(d: Dom) -> Int { let id = d.next_id; d.next_id = id + 1; id }
pub fn Dom::cmd(d: Dom, cmd: DomCmd) -> Unit { (d.emit)(cmd) }
pub fn Dom::report(d: Dom, err: String) -> Unit { (d.on_error)(err) }
pub fn Dom::mount(d: Dom, parent: Node, c: Child) -> Unit raise {
  for node in child(d, c, parent.ctx()) { parent.insert(d, node, fresh=true) }
}
pub fn Dom::resolve(self: Dom, path: String) -> Int raise {
  let path = path.trim().to_string()
  if path == "" { fail("query is empty") }
  let parts = [..path.split("/").map(v => v.to_string())]
  fn resolve(names: NameScope, parts: Array[String], path: String) raise {
    let mut names = names
    for i = 0; i < parts.length(); i = i + 1 {
      let p = parts[i]; if p == "" { fail("query has empty segment: \{path}") }
      if names.get(p) is Some(next) {
        if i + 1 == parts.length() { return next.id }
        match next.ui() {
          Some(ui) if ui.scope is Some(List) => {
            if i + 2 >= parts.length() { fail("query list item path missing: \{path}") }
            let j = @string.parse_int(parts[i + 1]) catch { _ => fail("query list index invalid: \{path}") }
            let items = if next.data is Anchor(a) && a.items is Some(a){ a
              } else { fail("query list item not found: \{path}") }
            if j < 0 || j >= items.length() { fail("query list item not found: \{path}") }
            let a = []; for k = i + 2; k < parts.length(); k = k + 1 { a.push(parts[k]) }
            return resolve(items[j].names, a, path)
          }
          _ => match next.data {
            Element(el) => match el.names {
              Some(s) => names = s
              None => fail("query scope not found: \{path}")
            }; _ => fail("query scope not found: \{path}")
          }
        }
      } else { fail("query not found: \{path}") }
    }; fail("query is empty")
  }
  try resolve(self.body.names(), parts, path)
  catch { _ => resolve(self.head.names(), parts, path) } noraise { id => id }
}
fn Dom::update_names(_: Dom, node: Node, ctx: NodeCtx, bind~: Bool = true) -> Unit raise {
  let ctxs = [ctx]; node.walk(fn(node) raise {
      ctxs.push(node.bind_name(ctxs[ctxs.length() - 1], bind~))
      if node.data is Element(el) && el.ui is Some(ui) { ui.scope is Some(Name) } else { false }
    }, fn() { ignore(ctxs.pop()) },
  )
}

type Attrs = Array[Attr]
type Children = Array[Child]
pub(all) enum Child { Lazy((Dom, NodeCtx) -> Frag raise)
  Null; Str(String); Int(Int); Arr(Children); Dyn(UiMeta?, () -> Child raise) }
trait HTag { render(Self, Attrs, Children) -> Child }
pub fn[T: HTag] h(tag: T, attrs: Attrs, children: Children) -> Child { tag.render(attrs, children) }
impl HTag for Comp with render(comp, attrs, cs) { (comp.render)(attrs, cs) }
impl HTag for String with render(tag, attrs, cs) {
  fn append(dom: Dom, parent: Node, cs: Children, ctx: NodeCtx) -> Unit raise {
    match parent.data {
      Element(_) => for item in cs {
        for node in child(dom, item, ctx) { parent.insert(dom, node, fresh=true) }
      }; _ => fail("cannot append to non-element node")
    }
  }
  Lazy((dom, ctx) => {
    let ns = match tag { "svg" => Svg; "math" => MathML; _ => ctx.ns }
    let node = element(dom, tag, ns)
    for a in attrs { node.set(dom, a) }
    let child_ctx = node.bind_name({ ..ctx, ns: match tag { "foreignObject" => Html; _ => ns } })
    append(dom, node, cs, child_ctx); [node]
  })
}

pub fn error_child(msg: String) -> Child { Lazy(fn(dom, _) { error_frag(dom, msg) }) }
pub struct Comp { render: (Attrs, Children) -> Child }
pub fn comp(f: (Attrs, Children) -> Child raise) -> Comp {{
  render: (a, c) => try f(a, c) catch { err => error_child("\{err}") } }}
fn error_frag(dom: Dom, msg: String) -> Frag {
  dom.report(msg); try {
    let node = element(dom, "div", Html)
    node.set(dom, Xml("class", Static(String("dom-error"))))
    node.insert(dom, text(dom, msg), fresh=true)
    [node]
  } catch { err => { dom.report("\{err}"); [] } }
}

fn child(dom: Dom, c: Child, ctx: NodeCtx) -> Frag {
  try {
    match c {
      Null => []
      Lazy(f) => f(dom, ctx)
      Str(s) => [text(dom, s)]
      Int(i) => [text(dom, i.to_string())]
      Arr(items) => flat_map(items, v => child(dom, v, ctx))
      Dyn(ui, f) => {
        fn mod_dom(dom: Dom, parent: Node, next: Frag, old: Frag, anchor: Node) -> Unit raise {
          match parent.data {
            Element(_) => {
              let seen : Set[Int] = Set::new(); for n in next { seen.add(n.id) }
              for n in old { if !seen.contains(n.id) { n.remove(dom) } }
              let mut tail = anchor
              for n in next {
                if n.id != tail.id { parent.insert(dom, n, target = Some(tail)) }
                tail = n
              }
            }; _ => fail("cannot modify non-element node")
          }
        }
        let anchor = anchor(dom)
        let mut old: Frag = []
        if anchor.data is Anchor(ac) {
          ac.ui = ui
          match ui { Some(_) => ignore(anchor.bind_name(ctx)); None => () }
          onclr(ac, effect(() => {
            let next = try {
              match ui {
                Some(ui) if ui.scope is Some(List) => {
                  let items = []; let next = []
                  for v in (match f() { Null => []; Arr(a) => a; c => [c] }) {
                    let item_ctx = { ..ctx, name: ui.id, names: Map::new() }
                    let frag = child(dom, v, item_ctx)
                    items.push(item_ctx)
                    for node in frag { next.push(node) }
                  }
                  ac.items = Some(items); next
                }
                _ => { ac.items = None; child(dom, f(), ctx) }
              }
            } catch { err => error_frag(dom, "\{err}") }
            if anchor.parent is Some(p) {
              try mod_dom(dom, p, next, old, anchor) catch { err => dom.report("\{err}") }
            }
            old = next
          }))
          onclr(ac, () => {
            let c = old.copy(); old = []
            for n in c { try n.remove(dom) catch { err => dom.report("\{err}") } }
          })
        } else { fail("dyn anchor kind mismatch") }
        [anchor] + old
      }
    }
  } catch { err => error_frag(dom, "\{err}") }
}

priv struct HMapEntry { index: Cel[Int]; frag: Frag }
pub fn[T: Eq + Hash] h_map(ui_id?: String? = None, items: Array[T], render: (T, () -> Int) -> Child,
) -> Child { h_map_dyn(ui_id~, fn() { items.mapi((i, item) => (item, i)) }, render) }
pub fn[T: Eq + Hash] h_map_dyn(
  ui_id?: String? = None, source: () -> Array[(T, Int)], render: (T, () -> Int) -> Child,
) -> Child {
  let list = match ui_id {
    Some(id) => try Some(ui(id, scope=Some(List))) catch { err => return error_child("\{err}") }
    None => None
  }
  let cache: Ref[Map[T, Array[HMapEntry]]] = Ref::new(Map::new())
  Dyn(list, fn() {
    let items = source()
    // TODO: refactor
    Lazy(fn(dom, ctx) {
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
            { index, frag: child(dom, render(key, fn() { index.get() }), ctx) }
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

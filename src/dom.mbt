pub struct Dom { nid: () -> Int; head: Node; body: Node
  emit: (DomCmd) -> Unit; on_error: (String) -> Unit; registered_class: Set[String] }
pub fn Dom::new(emit~: (DomCmd) -> Unit = fn(_) {}, on_error~: (String) -> Unit = fn(_) {}) -> Dom {
  let head = root(1, "head"); let body = root(2, "body")
  body.uictx = try ui("", scope=Scope, root=true).inst(None) catch { _ => None }
  { nid: gen_id(3), emit, on_error, head, body, registered_class: Set::new(), }
}
pub fn Dom::cmd(d: Dom, cmd: DomCmd) -> Unit { (d.emit)(cmd) }
pub fn Dom::report(d: Dom, err: String) -> Unit { (d.on_error)(err) }
pub fn Dom::mount_style(d: Dom, meta: UIMeta) -> Unit raise {
  if meta.style == "" || d.registered_class.contains(meta.class) { return }
  d.mount(d.head, h("style", [], [Str(meta.css_text())]))
  d.registered_class.add(meta.class)
}
pub fn Dom::mount(d: Dom, parent: Node, c: Child) -> Unit raise {
  let scope = match parent.ui {
    Scope(s) if s.meta.scope is Scope => parent.ui
    _ => parent.uictx
  }
  for node in child(d, c, Html, scope) { parent.insert(d, node, fresh=true) }
}
pub fn Dom::resolve(d: Dom, path: String) -> Node raise {
  let ui = d.body.uictx.query(path)
  ui.node() catch { _ => fail("query does not resolve to a node: \{path}") }
}
pub fn Dom::query(d: Dom, path: String, query: NodeQuery) -> NodeValue raise {
  d.resolve(path).get(query)
}
pub fn Dom::dispatch(d: Dom, path: String, ev: DomEvent) -> Unit raise {
  d.resolve(path).dispatch(d, ev)
}

type Attrs = Array[Attr]
type Children = Array[Child]
pub(all) enum Child { Lazy((Dom, DomNs, UIID) -> Frag raise)
  Null; Str(String); Int(Int); Arr(Children); Dyn(String?, () -> Child raise); DynP(() -> Child raise) }
trait HTag { render(Self, Attrs, Children) -> Child }
pub fn[T: HTag] h(tag: T, attrs: Attrs, children: Children) -> Child { tag.render(attrs, children) }
impl HTag for Comp with render(comp, attrs, cs) { (comp.render)(attrs, cs) }
impl HTag for String with render(tag, attrs, cs) {
  fn append(dom: Dom, parent: Node, cs: Children, ns: DomNs) -> Unit raise {
    match parent.data {
      Element(_) => for item in cs {
        let scope = match parent.ui {
          Scope(s) if s.meta.scope is Scope => parent.ui
          _ => parent.uictx
        }
        for node in child(dom, item, ns, scope) { parent.insert(dom, node, fresh=true) }
      }; _ => fail("cannot append to non-element node")
    }
  }
  Lazy((dom, ns, q) => {
    let ns = match tag { "svg" => Svg; "math" => MathML; _ => ns }
    let node = element(dom, tag, ns); node.uictx = q
    for a in attrs { node.set(dom, a, scope=q) }
    append(dom, node, cs, match tag { "foreignObject" => Html; _ => ns }); [node]
  })
}

pub fn error_child(msg: String) -> Child { Lazy(fn(dom, _, _) { error_frag(dom, msg) }) }
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

fn child(dom: Dom, c: Child, ns: DomNs, q: UIID) -> Frag {
  try {
    match c {
      Null => []
      Lazy(f) => f(dom, ns, q)
      Str(s) => [text(dom, s)]
      Int(i) => [text(dom, i.to_string())]
      Arr(items) => flat_map(items, v => child(dom, v, ns, q))
      DynP(f) => child(dom, Dyn(None, f), ns, q)
      Dyn(id, f) => {
        fn current_scope(node: Node?, q: UIID) -> UIID {
          let mut cur = node
          let mut scope: UIID = None
          while cur is Some(node) {
            if scope is None && !(node.uictx is None) { scope = node.uictx }
            match node.ui {
              Scope(s) if s.meta.scope is Scope => return node.ui
              _ => ()
            }
            cur = node.parent
          }
          if scope is None { q } else { scope }
        }
        fn dyn_list(dom: Dom, c: Child, ns: DomNs, scope: UIID) -> Frag raise {
          match scope {
            List(list) => {
              let items = match c { Arr(items) => items; _ => [c] }
              while list.items.length() < items.length() { ignore(scope.push()) }
              while list.items.length() > items.length() {
                scope.del((list.items.length() - 1).to_string())
              }
              let out = []
              for i = 0; i < items.length(); i = i + 1 {
                for node in child(dom, items[i], ns, list.items[i]) { out.push(node) }
              }
              out
            }
            _ => fail("dyn only accepts list scope")
          }
        }
        fn mod_dom(dom: Dom, parent: Node, next: Frag, old: Frag, anchor: Node) -> Unit raise {
          match parent.data {
            Element(_) => {
              let seen : Set[Int] = Set::new(); for n in next { seen.add(n.id) }
              for n in old { if !seen.contains(n.id) { n.remove(dom) } }
              let mut tail = anchor
              for n in next {
                if n.id != tail.id {
                  parent.insert(dom, n, target=Some(tail), fresh=n.parent is None)
                }
                tail = n
              }
            }; _ => fail("cannot modify non-element node")
          }
        }
        let anchor = anchor(dom); anchor.uictx = q
        match id {
          Some(id) => {
            let scope = UIID::list(id, q)
            anchor.ui = scope; scope.bind_node(Some(anchor))
          }
          None => ()
        }
        let mut old: Frag = []
        if anchor.data is Anchor(ac) {
          onclr(ac, effect(() => {
            let scope = match id {
              Some(_) => anchor.ui
              None => current_scope(Some(anchor), q)
            }
            let next = (match id {
              Some(_) => dyn_list(dom, f(), ns, scope)
              None => child(dom, f(), ns, scope)
            }) catch { err => error_frag(dom, "\{err}") }
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

priv struct HMapEntry { index: Cel[Int]; child: Child; mut frag: Frag? }
pub fn[T: Eq + Hash] h_map(
  items: Cel[Array[T]], render: (T, () -> Int) -> Child, ui_id?: String? = None,
) -> Child { h_map_dyn(fn() { items.get().mapi((i, item) => (item, i)) }, render, ui_id~) }
pub fn[T: Eq + Hash] h_map_dyn(
  source: () -> Array[(T, Int)], render: (T, () -> Int) -> Child, ui_id?: String? = None,
) -> Child {
  let cache: Ref[Map[T, Array[HMapEntry]]] = Ref::new(Map::new())
  Dyn(ui_id, fn() {
    let items = source()
    let prev = cache.val
    let next: Map[T, Array[HMapEntry]] = Map::new()
    let out: Children = []
    for item in items {
      let key = item.0
      let index_value = item.1
      let entry = match prev.get(key) {
        Some(bucket) if bucket.length() > 0 => {
          let reused = bucket.remove(0)
          reused.index.set_eq(index_value)
          reused
        }
        _ => {
          let index = cel(index_value)
          { index, child: render(key, fn() { index.get() }), frag: None }
        }
      }
      match next.get(key) {
        Some(bucket) => bucket.push(entry)
        None => next.set(key, [entry])
      }
      out.push(Lazy(fn(dom, ns, q) {
        match entry.frag {
          Some(frag) => frag
          None => {
            let frag = child(dom, entry.child, ns, q)
            entry.frag = Some(frag)
            frag
          }
        }
      }))
    }
    cache.val = next
    Arr(out)
  })
}

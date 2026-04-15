fn mount_root(c: Child, on_error?: (String) -> Unit = fn(_) {}) -> Dom {
  let dom = Dom::new(on_error~)
  dom.mount(dom.body, c) catch { _ => panic() }
  dom
}

fn first_anchor(node: Node) -> Node {
  for child in node.children() {
    if child.data is Anchor(_) { return child }
  }
  panic()
}

fn node_tag(node: Node) -> String {
  match node.data {
    Element(el) => el.tag
    Text(_) => "#text"
    Anchor(_) => "#anchor"
  }
}

fn node_text(node: Node) -> String {
  match node.data {
    Text(t) => t
    Element(_) => {
      for child in node.children() {
        if child.data is Text(t) { return t }
      }
      ""
    }
    Anchor(_) => ""
  }
}

fn attr_text(node: Node, key: String) -> String {
  match node.data {
    Element(el) => match el.xmls {
      Some(xmls) => match xmls.get(key) { Some(String(v)) => v; _ => "" }
      None => ""
    }
    _ => ""
  }
}

fn key_ids(node: Node) -> Map[String, Int] {
  let ids = Map::new()
  for child in node.child_elements() { ids.set(attr_text(child, "data-key"), child.id) }
  ids
}

fn inc(m: Map[String, Int], k: String) -> Unit {
  m.set(k, match m.get(k) { Some(v) => v + 1; None => 1 })
}

fn count(m: Map[String, Int], k: String) -> Int {
  match m.get(k) { Some(v) => v; None => 0 }
}

priv enum Spec {
  Null
  Str(String)
  Int(Int)
  Arr(Array[Spec])
  Tag(String, Array[Spec])
}

fn render_spec(spec: Spec) -> Child {
  match spec {
    Null => Null
    Str(s) => Str(s)
    Int(i) => Int(i)
    Arr(items) => Arr(items.map(render_spec))
    Tag(tag, children) => h(tag, [], children.map(render_spec))
  }
}

fn spec_texts(spec: Spec) -> Array[String] {
  match spec {
    Null => []
    Str(s) => [s]
    Int(i) => [i.to_string()]
    Arr(items) => flat_map(items, spec_texts)
    Tag(_, children) => flat_map(children, spec_texts)
  }
}

fn tree_texts(node: Node) -> Array[String] {
  match node.data {
    Text(t) => [t]
    Anchor(_) => []
    Element(_) => flat_map(node.children(), tree_texts)
  }
}

fn rand_text(rng: Rng) -> String { "t\{rng.pick(20)}" }
fn rand_tag(rng: Rng) -> String { if rng.pick(2) == 0 { "div" } else { "span" } }
fn rand_spec(rng: Rng, depth: Int) -> Spec {
  if depth <= 0 {
    match rng.pick(3) {
      0 => Str(rand_text(rng))
      1 => Int(rng.pick(50))
      _ => Null
    }
  } else {
    match rng.pick(5) {
      0 => Null
      1 => Str(rand_text(rng))
      2 => Int(rng.pick(50))
      3 => {
        let items = []
        let mut i = 0
        let n = rng.pick(4)
        while i < n {
          items.push(rand_spec(rng, depth - 1))
          i = i + 1
        }
        Arr(items)
      }
      _ => {
        let items = []
        let mut i = 0
        let n = rng.pick(4)
        while i < n {
          items.push(rand_spec(rng, depth - 1))
          i = i + 1
        }
        Tag(rand_tag(rng), items)
      }
    }
  }
}

test "dom: dyn swaps branch and removes old nodes" {
  let show = cel(true)
  let rt = mount_root(
    h("div", [], [Dyn(None, () => {
      if show.get() { h("span", [], [Str("A")]) } else { h("button", [], [Str("B")]) }
    })])
  )
  let host = rt.body.first_child()
  let first = host.child_elements()[0]
  assert_eq(node_tag(first), "span")
  let first_id = first.id
  show.set(false)
  flush()
  let next = host.child_elements()[0]
  assert_eq(node_tag(next), "button")
  assert_eq(node_text(next), "B")
  assert_eq(next.id == first_id, false)
  assert_eq(first.parent is None, true)
}

test "dom: dyn stops after host removal" {
  let text = cel("A")
  let mut runs = 0
  let rt = mount_root(
    h("div", [], [Dyn(None, () => { runs = runs + 1; Str(text.get()) })])
  )
  let host = rt.body.first_child()
  assert_eq(runs, 1)
  host.remove(rt)
  text.set("B")
  flush()
  assert_eq(runs, 1)
  assert_eq(rt.body.children().length(), 0)
}

test "dom: h_map_dyn keeps node ids stable on reorder" {
  let items = cel(["a", "b", "c"])
  let rt = mount_root(
    h("div", [], [h_map_dyn(
      fn() { items.get().mapi((i, item) => (item, i)) },
      (item, _) => h("div", [Xml("data-key", Static(String(item)))], [Str(item)]),
    )])
  )
  let host = rt.body.first_child()
  let before = key_ids(host)
  items.mutate(items => {
    let first = items[0]
    items[0] = items[2]
    items[2] = items[1]
    items[1] = first
  })
  flush()
  let after = host.child_elements()
  assert_eq(after.map(node => attr_text(node, "data-key")), ["c", "a", "b"])
  assert_eq(before.get("a").unwrap(), key_ids(host).get("a").unwrap())
  assert_eq(before.get("b").unwrap(), key_ids(host).get("b").unwrap())
  assert_eq(before.get("c").unwrap(), key_ids(host).get("c").unwrap())
}

test "dom: h_map keeps node ids stable on reactive reorder" {
  let items = cel(["a", "b", "c"])
  let rt = mount_root(
    h("div", [], [h_map(
      items,
      (item, _) => h("div", [Xml("data-key", Static(String(item)))], [Str(item)]),
    )])
  )
  let host = rt.body.first_child()
  let before = key_ids(host)
  items.mutate(items => {
    let moved = items.remove(0)
    items.push(moved)
  })
  flush()
  let after = host.child_elements()
  assert_eq(after.map(node => attr_text(node, "data-key")), ["b", "c", "a"])
  assert_eq(before.get("a").unwrap(), key_ids(host).get("a").unwrap())
  assert_eq(before.get("b").unwrap(), key_ids(host).get("b").unwrap())
  assert_eq(before.get("c").unwrap(), key_ids(host).get("c").unwrap())
}

test "dom: h_map rerenders only changed indexes" {
  let items = cel(["a", "b", "c"])
  let renders : Map[String, Int] = Map::new()
  let dyns : Map[String, Int] = Map::new()
  let _ = mount_root(
    h("div", [], [h_map(
      items,
      (item, index) => {
        inc(renders, item)
        h("div", [Xml("data-key", Static(String(item)))], [
          Dyn(None, () => {
            inc(dyns, item)
            Str(index().to_string())
          })
        ])
      },
    )])
  )
  assert_eq(count(renders, "a"), 1)
  assert_eq(count(renders, "b"), 1)
  assert_eq(count(renders, "c"), 1)
  assert_eq(count(dyns, "a"), 1)
  assert_eq(count(dyns, "b"), 1)
  assert_eq(count(dyns, "c"), 1)
  items.mutate(items => {
    let moved = items.remove(2)
    items.insert(1, moved)
  })
  flush()
  assert_eq(count(renders, "a"), 1)
  assert_eq(count(renders, "b"), 1)
  assert_eq(count(renders, "c"), 1)
  assert_eq(count(dyns, "a"), 1)
  assert_eq(count(dyns, "b"), 2)
  assert_eq(count(dyns, "c"), 2)
}

test "dom: h_map reuses duplicate keys in order" {
  let items = cel(["a", "b", "a"])
  let rt = mount_root(
    h("div", [], [h_map(
      items,
      (item, index) => h("div", [
        Xml("data-key", Static(String(item))),
        Xml("data-index", Dynamic(() => String(index().to_string()))),
      ], [Str(item)]),
    )])
  )
  let host = rt.body.first_child()
  let before = host.child_elements()
  let first_a = before[0].id
  let b = before[1].id
  let second_a = before[2].id
  items.mutate(items => {
    let moved = items.remove(0)
    items.push(moved)
  })
  flush()
  let after = host.child_elements()
  assert_eq(after.map(node => attr_text(node, "data-key")), ["b", "a", "a"])
  assert_eq(after[0].id, b)
  assert_eq(after[1].id, first_a)
  assert_eq(after[2].id, second_a)
  assert_eq(attr_text(after[1], "data-index"), "1")
  assert_eq(attr_text(after[2], "data-index"), "2")
}

test "dom: h_map_dyn rerenders only changed items" {
  let items = cel(["a", "b", "c"])
  let renders : Map[String, Int] = Map::new()
  let dyns : Map[String, Int] = Map::new()
  let _ = mount_root(
    h("div", [], [h_map_dyn(
      fn() { items.get().mapi((i, item) => (item, i)) },
      (item, index) => {
        inc(renders, item)
        h("div", [Xml("data-key", Static(String(item)))], [
          Dyn(None, () => {
            inc(dyns, item)
            Str(index().to_string())
          })
        ])
      },
    )])
  )
  assert_eq(count(renders, "a"), 1)
  assert_eq(count(renders, "b"), 1)
  assert_eq(count(renders, "c"), 1)
  assert_eq(count(dyns, "a"), 1)
  assert_eq(count(dyns, "b"), 1)
  assert_eq(count(dyns, "c"), 1)
  items.mutate(items => {
    let moved = items.remove(2)
    items.insert(1, moved)
  })
  flush()
  assert_eq(count(renders, "a"), 1)
  assert_eq(count(renders, "b"), 1)
  assert_eq(count(renders, "c"), 1)
  assert_eq(count(dyns, "a"), 1)
  assert_eq(count(dyns, "b"), 2)
  assert_eq(count(dyns, "c"), 2)
  items.mutate(items => items.push("d"))
  flush()
  assert_eq(count(renders, "a"), 1)
  assert_eq(count(renders, "b"), 1)
  assert_eq(count(renders, "c"), 1)
  assert_eq(count(renders, "d"), 1)
  assert_eq(count(dyns, "a"), 1)
  assert_eq(count(dyns, "b"), 2)
  assert_eq(count(dyns, "c"), 2)
  assert_eq(count(dyns, "d"), 1)
}

test "dom: h_map_dyn supports sliced source with custom indexes" {
  let items = cel(["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k"])
  let seen : Map[String, Array[Int]] = Map::new()
  fn window(items: Array[String]) -> Array[(String, Int)] {
    let out = []
    let mut i = 5
    while i < 10 {
      out.push((items[i], i))
      i = i + 1
    }
    out
  }
  let rt = mount_root(
    h("div", [], [h_map_dyn(
      fn() { window(items.get()) },
      (item, index) => {
        let logs = match seen.get(item) { Some(v) => v; None => { let v = []; seen.set(item, v); v } }
        h("div", [Xml("data-key", Static(String(item)))], [Dyn(None, () => {
          let i = index()
          logs.push(i)
          Str(i.to_string())
        })])
      },
    )])
  )
  let host = rt.body.first_child()
  let nodes = host.child_elements()
  assert_eq(nodes.map(node => attr_text(node, "data-key")), ["f", "g", "h", "i", "j"])
  assert_eq(nodes.map(node => node_text(node)), ["5", "6", "7", "8", "9"])
  assert_eq(seen.get("f").unwrap(), [5])
  assert_eq(seen.get("j").unwrap(), [9])
  items.mutate(items => {
    let moved = items.remove(7)
    items.insert(5, moved)
  })
  flush()
  let next = host.child_elements()
  assert_eq(next.map(node => attr_text(node, "data-key")), ["h", "f", "g", "i", "j"])
  assert_eq(seen.get("h").unwrap(), [7, 5])
  assert_eq(seen.get("f").unwrap(), [5, 6])
  assert_eq(seen.get("g").unwrap(), [6, 7])
  assert_eq(seen.get("i").unwrap(), [8])
  assert_eq(seen.get("j").unwrap(), [9])
  assert_eq(next.map(node => node_text(node)), ["5", "6", "7", "8", "9"])
}

test "dom: h_map_dyn reuses duplicate keys in source order" {
  let items = cel([("a", 10), ("b", 11), ("a", 12)])
  let rt = mount_root(
    h("div", [], [h_map_dyn(
      fn() { items.get() },
      (item, index) => h("div", [
        Xml("data-key", Static(String(item))),
        Xml("data-index", Dynamic(() => String(index().to_string()))),
      ], [Str(item)]),
    )])
  )
  let host = rt.body.first_child()
  let before = host.child_elements()
  let first_a = before[0].id
  let b = before[1].id
  let second_a = before[2].id
  items.mutate(items => {
    let moved = items.remove(0)
    items.push((moved.0, 13))
    items[0] = ("a", 11)
    items[1] = ("b", 12)
  })
  flush()
  let after = host.child_elements()
  assert_eq(after.map(node => attr_text(node, "data-key")), ["a", "b", "a"])
  assert_eq(after[0].id, first_a)
  assert_eq(after[1].id, b)
  assert_eq(after[2].id, second_a)
  assert_eq(attr_text(after[0], "data-index"), "11")
  assert_eq(attr_text(after[1], "data-index"), "12")
  assert_eq(attr_text(after[2], "data-index"), "13")
}

test "dom: h_map_dyn fuzz keeps ids and indexes stable with duplicate keys" {
  let items = cel(["a", "b", "a", "c"])
  let rt = mount_root(
    h("div", [], [h_map_dyn(
      fn() { items.get().mapi((i, item) => (item, i)) },
      (item, index) => h("div", [
        Xml("data-key", Static(String(item))),
      ], [Dyn(None, () => Str(index().to_string()))]),
    )])
  )
  let host = rt.body.first_child()
  let rng = new_rng()
  let key_pool = ["a", "b", "c", "d"]
  let prev_ids : Map[String, Array[Int]] = Map::new()
  fn record_prev(prev_ids: Map[String, Array[Int]], nodes: Array[Node]) -> Unit {
    prev_ids.clear()
    for node in nodes {
      let key = attr_text(node, "data-key")
      match prev_ids.get(key) {
        Some(ids) => ids.push(node.id)
        None => prev_ids.set(key, [node.id])
      }
    }
  }
  record_prev(prev_ids, host.child_elements())
  let mut step = 0
  while step < 120 {
    items.mutate(items => {
      let op = rng.pick(5)
      match op {
        0 => {
          let from = rng.pick(items.length())
          let item = items.remove(from)
          let to = rng.pick(items.length() + 1)
          items.insert(to, item)
        }
        1 => {
          let i = rng.pick(items.length())
          let j = rng.pick(items.length())
          let a = items[i]
          items[i] = items[j]
          items[j] = a
        }
        2 => {
          if items.length() > 1 {
            ignore(items.remove(rng.pick(items.length())))
          } else {
            let at = rng.pick(items.length() + 1)
            items.insert(at, key_pool[rng.pick(key_pool.length())])
          }
        }
        3 => {
          let at = rng.pick(items.length() + 1)
          items.insert(at, key_pool[rng.pick(key_pool.length())])
        }
        _ => {
          let i = rng.pick(items.length())
          items[i] = key_pool[rng.pick(key_pool.length())]
        }
      }
    })
    flush()
    let nodes = host.child_elements()
    let keys = nodes.map(node => attr_text(node, "data-key"))
    let expected = items.peek()
    assert_eq(keys, expected)
    let mut i = 0
    while i < nodes.length() {
      let node = nodes[i]
      let key = keys[i]
      assert_eq(node_text(node), i.to_string())
      match prev_ids.get(key) {
        Some(ids) if ids.length() > 0 => {
          let expected = ids.remove(0)
          assert_eq(node.id, expected)
        }
        None => ()
        _ => ()
      }
      i = i + 1
    }
    record_prev(prev_ids, nodes)
    step = step + 1
  }
}

test "dom: h_map ui_id keeps list slot instances stable" {
  let items = cel(["a", "b", "c"])
  let rt = mount_root(
    h("div", [], [h_map(
      items,
      (item, _) => h("div", [Xml("data-key", Static(String(item)))], [Str(item)]),
      ui_id=Some("todos"),
    )])
  )
  let host = rt.body.first_child()
  let anchor = first_anchor(host)
  let list = match anchor.ui { List(list) => list; _ => panic() }
  let slot0 = list.items[0]
  let slot1 = list.items[1]
  let slot2 = list.items[2]
  items.mutate(items => {
    let moved = items.remove(0)
    items.push(moved)
  })
  flush()
  let next = match anchor.ui { List(list) => list; _ => panic() }
  match (slot0, next.items[0]) {
    (Item(a), Item(b)) => assert_eq(physical_equal(a, b), true)
    _ => panic()
  }
  match (slot1, next.items[1]) {
    (Item(a), Item(b)) => assert_eq(physical_equal(a, b), true)
    _ => panic()
  }
  match (slot2, next.items[2]) {
    (Item(a), Item(b)) => assert_eq(physical_equal(a, b), true)
    _ => panic()
  }
}

test "dom: plain node rejects list scope" {
  let dom = Dom::new()
  let node = element(dom, "div", Html)
  node.ui = UIID::list("todos", dom.body.uictx)
  assert_fail("plain node should reject list scope", () => dom.body.insert(dom, node, fresh=true))
}

test "dom: node rejects setting ui twice" {
  let dom = Dom::new()
  let node = element(dom, "div", Html)
  node.set(dom, Id(ui("a") catch { _ => panic() }))
  assert_fail("node should reject setting ui twice", () => {
    node.set(dom, Id(ui("b") catch { _ => panic() }))
  })
}

test "dom: ui style mounts head style node once and emits domcmd" {
  let cmds = []
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let title = ui("title", style="& { color:#222; }\n&:hover { color:#000; }") catch { _ => panic() }
  let dom = Dom::new(emit=cmd => cmds.push(cmd))
  dom.mount(dom.body, Arr([
    h("div", [Id(left)], [h("div", [Id(title)], [Str("A")])]),
    h("div", [Id(right)], [h("div", [Id(title)], [Str("B")])]),
  ])) catch { _ => panic() }
  let styles = dom.head.children()
  assert_eq(styles.length(), 1)
  let style = styles[0]
  assert_eq(node_tag(style), "style")
  let style_text = style.first_child()
  assert_eq(node_text(style_text), title.css_text())
  let mut create_style = false
  let mut insert_style = false
  let mut create_text = false
  let mut insert_text = false
  for cmd in cmds {
    match cmd {
      Create({ id, tag, .. }) => {
        if id == style.id && tag == "style" { create_style = true }
        if id == style_text.id && tag == "" { create_text = true }
      }
      Insert({ parent, child, .. }) => {
        if parent == dom.head.id && child == style.id { insert_style = true }
        if parent == style.id && child == style_text.id { insert_text = true }
      }
      _ => ()
    }
  }
  assert_eq(create_style, true)
  assert_eq(insert_style, true)
  assert_eq(create_text, true)
  assert_eq(insert_text, true)
}

test "dom: h fuzz keeps rendered text equal to spec" {
  let rng = new_rng()
  let slots = [
    cel(rand_spec(rng, 3)),
    cel(rand_spec(rng, 3)),
    cel(rand_spec(rng, 3)),
    cel(rand_spec(rng, 3)),
  ]
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let title = ui("title") catch { _ => panic() }
  let outer = cel(true)
  let inner = cel(true)
  let rt = mount_root(
    h("div", [], [
      h("div", [], slots.map(slot => Dyn(None, () => render_spec(slot.get())))),
      h("div", [Id(left)], [h("div", [], [Dyn(None, () => {
        if outer.get() {
          Arr([
            Dyn(None, () => if inner.get() { h("span", [Id(title)], [Str("Q")]) } else { Null }),
            Str("tail"),
          ])
        } else { Null }
      })])]),
      h("div", [Id(right)], []),
    ])
  )
  let host = rt.body.first_child()
  let wrap = rt.resolve("left/title").parent.unwrap()
  let mut side = 0
  fn expected(slots: Array[Cel[Spec]], outer: Bool, inner: Bool) -> Array[String] {
    let texts = flat_map(slots, slot => spec_texts(slot.peek()))
    if outer {
      if inner { texts + ["Q", "tail"] } else { texts + ["tail"] }
    } else { texts }
  }
  fn check_query(dom: Dom, side: Int, outer: Bool, inner: Bool) -> Unit raise {
    if outer && inner {
      let live = if side == 0 { "left/title" } else { "right/title" }
      let dead = if side == 0 { "right/title" } else { "left/title" }
      assert_eq(dom.resolve(live).id > 0, true)
      assert_fail("query should not stay in old scope", () => ignore(dom.resolve(dead)))
    } else {
      assert_fail("query should disappear when dyn is hidden", () => ignore(dom.resolve("left/title")))
      assert_fail("query should disappear when dyn is hidden", () => ignore(dom.resolve("right/title")))
    }
  }
  assert_eq(tree_texts(host), expected(slots, outer.peek(), inner.peek()))
  check_query(rt, side, outer.peek(), inner.peek())
  let mut step = 0
  while step < 120 {
    match rng.pick(5) {
      0 | 1 => {
        let i = rng.pick(slots.length())
        let slot = slots[i]
        slot.set(rand_spec(rng, 3))
      }
      2 => {
        side = 1 - side
        let scope = if side == 0 { rt.resolve("left") } else { rt.resolve("right") }
        scope.insert(rt, wrap)
      }
      3 => outer.set(!outer.peek())
      _ => inner.set(!inner.peek())
    }
    flush()
    assert_eq(tree_texts(host), expected(slots, outer.peek(), inner.peek()))
    check_query(rt, side, outer.peek(), inner.peek())
    flush()
    assert_eq(tree_texts(host), expected(slots, outer.peek(), inner.peek()))
    check_query(rt, side, outer.peek(), inner.peek())
    step = step + 1
  }
}

test "dom: comp renders child" {
  let card = comp((_, cs) => h("section", [], cs))
  let dom = mount_root(h(card, [], [h("div", [], [])]))
  let body = match dom.body.data { Element(el) => el; _ => panic() }
  assert_eq(body.first is Some(_), true)
}

test "dom: swallowed dyn error is reported" {
  let errors = []
  let dom = mount_root(
    h("div", [], [Dyn(None, fn() raise { fail("dyn boom") })])
  , on_error=msg => errors.push(msg))
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].contains("dyn boom"), true)
  let body = match dom.body.data { Element(el) => el; _ => panic() }
  let host = match body.first { Some(node) => node; _ => panic() }
  let host_elm = match host.data { Element(el) => el; _ => panic() }
  let err_node = match host_elm.last {
    Some(node) if node.id != host_elm.first.unwrap().id => node
    _ => fail("expected dyn error node")
  }
  let err_elm = match err_node.data { Element(el) => el; _ => fail("expected element error node") }
  let err_cls = match err_elm.xmls {
    Some(xmls) => match xmls.get("class") { Some(String(v)) => v; _ => "" }; None => ""
  }
  let err_text = match err_elm.first { Some({ data: Text(t), .. }) => t; _ => "" }
  assert_eq(err_cls, "dom-error")
  assert_eq(err_text.contains("dyn boom"), true)
}

test "dom: resolve walks static ui scope" {
  let panel = ui("panel", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let dom = mount_root(
    h("div", [Id(panel)], [h("button", [Id(save)], [Str("Save")])])
  )
  let node = dom.resolve("panel/save")
  assert_eq(node.id > 0, true)
  assert_eq(match node.data { Element(el) => el.tag; _ => "" }, "button")
}

test "dom: fresh mount binds sibling scopes once" {
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let dom = mount_root(
    h("div", [], [
      h("div", [Id(left)], [h("button", [Id(save)], [Str("Save")])]),
      h("div", [Id(right)], []),
    ])
  )
  assert_eq(dom.resolve("left").id > 0, true)
  assert_eq(dom.resolve("right").id > 0, true)
  assert_eq(dom.resolve("left/save").id > 0, true)
}

test "dom: move and remove update query binding" {
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let dom = mount_root(
    h("div", [], [
      h("div", [Id(left)], [h("button", [Id(save)], [Str("Save")])]),
      h("div", [Id(right)], []),
    ])
  )
  let left_host = dom.resolve("left")
  let right_host = dom.resolve("right")
  let save_btn = dom.resolve("left/save")
  right_host.insert(dom, save_btn)
  assert_fail("old path should fail after move", () => ignore(dom.resolve("left/save")))
  assert_eq(dom.resolve("right/save").id, save_btn.id)
  save_btn.remove(dom)
  assert_fail("path should fail after remove", () => ignore(dom.resolve("right/save")))
  assert_eq(match left_host.data { Element(el) => el.first is Some(_); _ => false }, false)
}

test "dom: move subtree updates nested scope paths" {
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let panel = ui("panel", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let dom = mount_root(
    h("div", [], [
      h("div", [Id(left)], [
        h("div", [Id(panel)], [h("button", [Id(save)], [Str("Save")])]),
      ]),
      h("div", [Id(right)], []),
    ])
  )
  let right_host = dom.resolve("right")
  let panel_host = dom.resolve("left/panel")
  let save_btn = dom.resolve("left/panel/save")
  right_host.insert(dom, panel_host)
  assert_fail("old nested path should fail after move", () => ignore(dom.resolve("left/panel/save")))
  assert_eq(dom.resolve("right/panel").id, panel_host.id)
  assert_eq(dom.resolve("right/panel/save").id, save_btn.id)
}

test "dom: nested dyn keeps query in new scope after move" {
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let title = ui("title") catch { _ => panic() }
  let outer = cel(true)
  let inner = cel(true)
  let dom = mount_root(
    h("div", [], [
      h("div", [Id(left)], [Dyn(None, () => {
        if outer.get() {
          h("div", [], [Dyn(None, () => {
            if inner.get() { h("span", [Id(title)], [Str("A")]) } else { Null }
          })])
        } else { Null }
      })]),
      h("div", [Id(right)], []),
    ])
  )
  let right_host = dom.resolve("right")
  let moved = dom.resolve("left/title")
  let wrap = moved.parent.unwrap()
  right_host.insert(dom, wrap)
  assert_fail("old path should fail after move", () => ignore(dom.resolve("left/title")))
  assert_eq(dom.resolve("right/title").id, moved.id)
  inner.set(false)
  flush()
  inner.set(true)
  flush()
  assert_fail("old path should stay invalid after inner dyn rerun", () => ignore(dom.resolve("left/title")))
  assert_eq(dom.resolve("right/title").id > 0, true)
}

test "dom: frag dyn keeps query in new scope after move" {
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let title = ui("title") catch { _ => panic() }
  let outer = cel(true)
  let inner = cel(true)
  let dom = mount_root(
    h("div", [], [
      h("div", [Id(left)], [h("div", [], [Dyn(None, () => {
        if outer.get() {
          Arr([
            Dyn(None, () => if inner.get() { h("span", [Id(title)], [Str("A")]) } else { Null }),
            Str("tail"),
          ])
        } else { Null }
      })])]),
      h("div", [Id(right)], []),
    ])
  )
  let right_host = dom.resolve("right")
  let moved = dom.resolve("left/title")
  let wrap = moved.parent.unwrap()
  right_host.insert(dom, wrap)
  assert_fail("old path should fail after move", () => ignore(dom.resolve("left/title")))
  assert_eq(dom.resolve("right/title").id, moved.id)
  inner.set(false)
  flush()
  inner.set(true)
  flush()
  assert_fail("old path should stay invalid after inner dyn rerun", () => ignore(dom.resolve("left/title")))
  assert_eq(dom.resolve("right/title").id > 0, true)
}

test "dom: list item frag dyn keeps item scope after rerun" {
  let items = cel(["A", "B"])
  let show = cel(true)
  let title = ui("title") catch { _ => panic() }
  let dom = mount_root(
    h("div", [], [Dyn(Some("todos"), () => Arr(items.get().map(item =>
      Arr([
        Dyn(None, () => if show.get() {
          h("span", [Id(title)], [Str(item)])
        } else { Null }),
        Str("tail"),
      ])
    )))])
  )
  assert_eq(dom.resolve("todos/0/title").id > 0, true)
  assert_eq(dom.resolve("todos/1/title").id > 0, true)
  show.set(false)
  flush()
  show.set(true)
  flush()
  assert_eq(dom.resolve("todos/0/title").id > 0, true)
  assert_eq(dom.resolve("todos/1/title").id > 0, true)
}

test "dom: dyn rejects invalid list id" {
  let errors = []
  ignore(mount_root(h("div", [], [Dyn(Some("bad/id"), () => Null)]), on_error=msg => errors.push(msg)))
  assert_eq(errors.length(), 1)
  assert_eq(errors[0] != "", true)
}

test "dom: dyn accepts list scope" {
  let text = ui("text") catch { _ => panic() }
  let dom = mount_root(
    h("div", [], [Dyn(Some("todos"), () => h("span", [Id(text)], [Str("A")]))])
  )
  let node = dom.resolve("todos/0/text")
  assert_eq(match node.data { Element(el) => el.tag; _ => "" }, "span")
}

test "dom: h_map opens list scope from string id" {
  let items = cel(["A", "B"])
  let text = ui("text") catch { _ => panic() }
  let dom = mount_root(
    h("div", [], [h_map(
      items,
      (item, _) => h("span", [Id(text)], [Str(item)]),
      ui_id=Some("todos"),
    )])
  )
  assert_eq(dom.resolve("todos/0/text").id > 0, true)
  assert_eq(dom.resolve("todos/1/text").id > 0, true)
}

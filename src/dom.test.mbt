fn body_nodes(rt: Runtime) -> Array[Node] {
  let out = []
  let body = match rt.dom.body.data { Element(el) => el; _ => panic() }
  let mut node = body.first
  while node is Some(n) { out.push(n); node = n.next }
  out
}

fn child_nodes(node: Node) -> Array[Node] {
  let out = []
  let el = match node.data { Element(el) => el; _ => panic() }
  let mut child = el.first
  while child is Some(n) { out.push(n); child = n.next }
  out
}

fn child_elements(node: Node) -> Array[Node] {
  let out = []
  for child in child_nodes(node) {
    if child.data is Element(_) { out.push(child) }
  }
  out
}

fn first_anchor(node: Node) -> Node {
  for child in child_nodes(node) {
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
      for child in child_nodes(node) {
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
  for child in child_elements(node) { ids.set(attr_text(child, "data-key"), child.id) }
  ids
}

fn inc(m: Map[String, Int], k: String) -> Unit {
  m.set(k, match m.get(k) { Some(v) => v + 1; None => 1 })
}

fn count(m: Map[String, Int], k: String) -> Int {
  match m.get(k) { Some(v) => v; None => 0 }
}

priv struct Rng { mut state: Int }
fn Rng::new(seed: Int) -> Rng {{ state: seed }}
fn Rng::next(self: Rng) -> Int {
  self.state = (self.state * 1664525 + 1013904223) & 0x7fffffff
  self.state
}
fn Rng::pick(self: Rng, n: Int) -> Int {
  if n <= 1 { 0 } else { self.next() % n }
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
    Element(_) => flat_map(child_nodes(node), tree_texts)
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
  let root = Entry::new("root", () => {
    h("div", [], [Dyn(None, () => {
      if show.get() { h("span", [], [Str("A")]) } else { h("button", [], [Str("B")]) }
    })])
  })
  let rt = Runtime::new(root)
  let host = body_nodes(rt)[0]
  let first = child_elements(host)[0]
  assert_eq(node_tag(first), "span")
  let first_id = first.id
  show.set(false)
  flush()
  let next = child_elements(host)[0]
  assert_eq(node_tag(next), "button")
  assert_eq(node_text(next), "B")
  assert_eq(next.id == first_id, false)
  assert_eq(first.parent is None, true)
}

test "dom: dyn stops after host removal" {
  let text = cel("A")
  let mut runs = 0
  let root = Entry::new("root", () => {
    h("div", [], [Dyn(None, () => { runs = runs + 1; Str(text.get()) })])
  })
  let rt = Runtime::new(root)
  let host = body_nodes(rt)[0]
  assert_eq(runs, 1)
  host.remove(rt.dom)
  text.set("B")
  flush()
  assert_eq(runs, 1)
  assert_eq(body_nodes(rt).length(), 0)
}

test "dom: h_map_dyn keeps node ids stable on reorder" {
  let items = cel(["a", "b", "c"])
  let root = Entry::new("root", () => {
    h("div", [], [h_map_dyn(
      fn() { items.get().mapi((i, item) => (item, i)) },
      (item, _) => h("div", [Xml("data-key", Static(String(item)))], [Str(item)]),
    )])
  })
  let rt = Runtime::new(root)
  let host = body_nodes(rt)[0]
  let before = key_ids(host)
  items.mutate(items => {
    let first = items[0]
    items[0] = items[2]
    items[2] = items[1]
    items[1] = first
  })
  flush()
  let after = child_elements(host)
  assert_eq(after.map(node => attr_text(node, "data-key")), ["c", "a", "b"])
  assert_eq(before.get("a").unwrap(), key_ids(host).get("a").unwrap())
  assert_eq(before.get("b").unwrap(), key_ids(host).get("b").unwrap())
  assert_eq(before.get("c").unwrap(), key_ids(host).get("c").unwrap())
}

test "dom: h_map keeps node ids stable on reactive reorder" {
  let items = cel(["a", "b", "c"])
  let root = Entry::new("root", () => {
    h("div", [], [h_map(
      items,
      (item, _) => h("div", [Xml("data-key", Static(String(item)))], [Str(item)]),
    )])
  })
  let rt = Runtime::new(root)
  let host = body_nodes(rt)[0]
  let before = key_ids(host)
  items.mutate(items => {
    let moved = items.remove(0)
    items.push(moved)
  })
  flush()
  let after = child_elements(host)
  assert_eq(after.map(node => attr_text(node, "data-key")), ["b", "c", "a"])
  assert_eq(before.get("a").unwrap(), key_ids(host).get("a").unwrap())
  assert_eq(before.get("b").unwrap(), key_ids(host).get("b").unwrap())
  assert_eq(before.get("c").unwrap(), key_ids(host).get("c").unwrap())
}

test "dom: h_map rerenders only changed indexes" {
  let items = cel(["a", "b", "c"])
  let renders : Map[String, Int] = Map::new()
  let dyns : Map[String, Int] = Map::new()
  let root = Entry::new("root", () => {
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
  })
  let _ = Runtime::new(root)
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
  let root = Entry::new("root", () => {
    h("div", [], [h_map(
      items,
      (item, index) => h("div", [
        Xml("data-key", Static(String(item))),
        Xml("data-index", Dynamic(() => String(index().to_string()))),
      ], [Str(item)]),
    )])
  })
  let rt = Runtime::new(root)
  let host = body_nodes(rt)[0]
  let before = child_elements(host)
  let first_a = before[0].id
  let b = before[1].id
  let second_a = before[2].id
  items.mutate(items => {
    let moved = items.remove(0)
    items.push(moved)
  })
  flush()
  let after = child_elements(host)
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
  let root = Entry::new("root", () => {
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
  })
  let _ = Runtime::new(root)
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
  let root = Entry::new("root", () => {
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
  })
  let rt = Runtime::new(root)
  let host = body_nodes(rt)[0]
  let nodes = child_elements(host)
  assert_eq(nodes.map(node => attr_text(node, "data-key")), ["f", "g", "h", "i", "j"])
  assert_eq(nodes.map(node => node_text(node)), ["5", "6", "7", "8", "9"])
  assert_eq(seen.get("f").unwrap(), [5])
  assert_eq(seen.get("j").unwrap(), [9])
  items.mutate(items => {
    let moved = items.remove(7)
    items.insert(5, moved)
  })
  flush()
  let next = child_elements(host)
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
  let root = Entry::new("root", () => {
    h("div", [], [h_map_dyn(
      fn() { items.get() },
      (item, index) => h("div", [
        Xml("data-key", Static(String(item))),
        Xml("data-index", Dynamic(() => String(index().to_string()))),
      ], [Str(item)]),
    )])
  })
  let rt = Runtime::new(root)
  let host = body_nodes(rt)[0]
  let before = child_elements(host)
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
  let after = child_elements(host)
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
  let root = Entry::new("root", () => {
    h("div", [], [h_map_dyn(
      fn() { items.get().mapi((i, item) => (item, i)) },
      (item, index) => h("div", [
        Xml("data-key", Static(String(item))),
      ], [Dyn(None, () => Str(index().to_string()))]),
    )])
  })
  let rt = Runtime::new(root)
  let host = body_nodes(rt)[0]
  let rng = Rng::new(20260414)
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
  record_prev(prev_ids, child_elements(host))
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
    let nodes = child_elements(host)
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
  let root = Entry::new("root", () => {
    h("div", [], [h_map(
      items,
      (item, _) => h("div", [Xml("data-key", Static(String(item)))], [Str(item)]),
      ui_id=Some("todos"),
    )])
  })
  let rt = Runtime::new(root)
  let host = body_nodes(rt)[0]
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

test "dom: h fuzz keeps rendered text equal to spec" {
  let rng = Rng::new(20260414)
  let slots = [
    cel(rand_spec(rng, 3)),
    cel(rand_spec(rng, 3)),
    cel(rand_spec(rng, 3)),
    cel(rand_spec(rng, 3)),
  ]
  let root = Entry::new("root", () => {
    h("div", [], slots.map(slot => Dyn(None, () => render_spec(slot.get()))))
  })
  let rt = Runtime::new(root)
  let host = body_nodes(rt)[0]
  fn expected(slots: Array[Cel[Spec]]) -> Array[String] {
    flat_map(slots, slot => spec_texts(slot.peek()))
  }
  assert_eq(tree_texts(host), expected(slots))
  let mut step = 0
  while step < 120 {
    let i = rng.pick(slots.length())
    let slot = slots[i]
    slot.set(rand_spec(rng, 3))
    flush()
    assert_eq(tree_texts(host), expected(slots))
    flush()
    assert_eq(tree_texts(host), expected(slots))
    step = step + 1
  }
}

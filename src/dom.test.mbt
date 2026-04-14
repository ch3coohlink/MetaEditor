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

test "dom: dyn swaps branch and removes old nodes" {
  let show = cel(true)
  let root = Entry::new("root", () => {
    h("div", [], [Dyn(() => {
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
    h("div", [], [Dyn(() => { runs = runs + 1; Str(text.get()) })])
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
          Dyn(() => {
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
          Dyn(() => {
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
        h("div", [Xml("data-key", Static(String(item)))], [Dyn(() => {
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

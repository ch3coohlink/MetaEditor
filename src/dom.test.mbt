let test_dom_state : Ref[DomState] = Ref::new(new_dom_state())

fn assert_reset_dom() -> Unit {
  test_dom_state.val = new_dom_state()
}

fn assert_realize(child: Child) -> VNode {
  realize(test_dom_state.val, child)
}

fn assert_take_cmds() -> Array[DomCmd] {
  get_cmds(test_dom_state.val)
}

fn is_remove(cmd: DomCmd, id: Int) -> Bool {
  match cmd {
    Remove(node_id) => node_id == id
    _ => false
  }
}

fn is_create(cmd: DomCmd, id: Int) -> Bool {
  match cmd {
    Create(node_id, _, _) => node_id == id
    _ => false
  }
}

fn is_insert_before(cmd: DomCmd, id: Int) -> Bool {
  match cmd {
    InsertBefore(_, child_id, _) => child_id == id
    _ => false
  }
}

fn find_text_node_id(cmds: Array[DomCmd], text: String) -> Int {
  for i = 0; i < cmds.length(); i = i + 1 {
    match cmds[i] {
      Text(id, value) => if value == text { return id }
      _ => ()
    }
  }
  panic()
}

fn find_parent_id(cmds: Array[DomCmd], child_id: Int) -> Int {
  for cmd in cmds {
    match cmd {
      Append(parent_id, id) => if id == child_id { return parent_id }
      InsertBefore(parent_id, id, _) => if id == child_id { return parent_id }
      _ => ()
    }
  }
  panic()
}

fn assert_no_cmd(cmds: Array[DomCmd], pred: (DomCmd) -> Bool) -> Unit {
  for cmd in cmds {
    if pred(cmd) { panic() }
  }
}

fn assert_text(cmd: DomCmd, text: String) -> Unit {
  match cmd {
    Text(_, value) => if value != text { panic() }
    _ => panic()
  }
}

fn assert_create(cmd: DomCmd, tag: String, ns: String) -> Int {
  match cmd {
    Create(id, t, n) => {
      if t != tag { panic() }
      if ns != "" && n != ns { panic() }
      id
    }
    _ => panic()
  }
}

fn assert_attr(cmd: DomCmd, key: String, value: String) -> Unit {
  match cmd {
    Attr(_, k, v) => {
      if k != key { panic() }
      if v != value { panic() }
    }
    _ => panic()
  }
}

fn assert_append(cmd: DomCmd, parent_id: Int, child_id: Int) -> Unit {
  match cmd {
    Append(p, c) => {
      if p != parent_id { panic() }
      if c != child_id { panic() }
    }
    _ => panic()
  }
}

fn assert_listen(cmd: DomCmd, ev: String, node_id: Int, ui_id: String) -> Unit {
  match cmd {
    Listen(id, name, target) => {
      if id != node_id { panic() }
      if name != ev { panic() }
      if target != ui_id { panic() }
    }
    _ => panic()
  }
}

fn assert_update_attr(cmd: DomCmd, key: String, value: String) -> Unit {
  match cmd {
    UpdateAttr(_, k, v) => {
      if k != key { panic() }
      if v != value { panic() }
    }
    _ => panic()
  }
}

fn find_child(nodes: Array[VNode], id: Int) -> VNode {
  for node in nodes {
    if node.id == id { return node }
  }
  panic()
}

test "h creates elements and attributes" {
  assert_reset_dom()
  let _ = assert_realize(h("div", [("class", S("btn")), ("id", S("main"))], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 3)
  let _ = assert_create(cmds[0], "div", "")
  assert_attr(cmds[1], "class", "btn")
  assert_attr(cmds[2], "id", "main")
}

test "h handles children" {
  assert_reset_dom()
  let parent = assert_realize(h("div", [], [h("span", [], [])]))
  let cmds = assert_take_cmds()
  // parent: Create
  // child: Create
  // Append(parent, child)
  assert_eq(cmds.length(), 3)
  let parent_id = assert_create(cmds[0], "div", "")
  let child_id = assert_create(cmds[1], "span", "")
  assert_append(cmds[2], parent_id, child_id)
  assert_eq(parent.id, parent_id)
}

test "h dispatches comp values" {
  assert_reset_dom()
  let box = comp(fn(attrs, children) { h("section", attrs, children) })
  let node = assert_realize(h(box, [("class", S("panel"))], [Str("ok")]))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 5)
  assert_eq(node.id, assert_create(cmds[0], "section", ""))
  assert_attr(cmds[1], "class", "panel")
  let _ = assert_create(cmds[2], "", "")
  assert_text(cmds[3], "ok")
  assert_append(cmds[4], node.id, match cmds[2] { Create(id, _, _) => id; _ => panic() })
}

test "h nests comp values like regular children" {
  assert_reset_dom()
  let box = comp(fn(attrs, children) { h("section", attrs, children) })
  let _ = assert_realize(h("div", [], [
    h(box, [("class", S("panel"))], [Str("ok")])
  ]))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 7)
  let div_id = assert_create(cmds[0], "div", "")
  let section_id = assert_create(cmds[1], "section", "")
  assert_attr(cmds[2], "class", "panel")
  let text_id = assert_create(cmds[3], "", "")
  assert_text(cmds[4], "ok")
  assert_append(cmds[5], section_id, text_id)
  assert_append(cmds[6], div_id, section_id)
}

test "scoped can name component root" {
  assert_reset_dom()
  let clicked = Ref::new(false)
  let box = scoped(
    comp(fn(attrs, children) {
      h("button", attrs, [
        h("span", [("ui-id", S("label"))], children)
      ])
    }),
    name=Some("scoped:root")
  )
  let node = assert_realize(h(box, [
    ("onclick", E(() => { clicked.val = true }))
  ], [
    Str("ok")
  ]))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 9)
  assert_eq(node.id, assert_create(cmds[0], "button", ""))
  assert_listen(cmds[1], "onclick", node.id, "scoped:root")
  assert_attr(cmds[2], "ui-id", "scoped:root")
  let label_id = assert_create(cmds[3], "span", "")
  assert_attr(cmds[4], "ui-id", "label")
  let text_id = assert_create(cmds[5], "", "")
  assert_text(cmds[6], "ok")
  assert_append(cmds[7], label_id, text_id)
  assert_append(cmds[8], node.id, label_id)
  let names = match node.scope_names {
    Some(v) => v
    None => panic()
  }
  assert_eq(names.get("label"), Some(label_id))
  click("scoped:root/label")
  click("scoped:root")
  assert_eq(clicked.val, true)
}

test "scoped query path reaches nested local node" {
  assert_reset_dom()
  let clicks = Ref::new(0)
  let box = scoped(
    comp(fn(attrs, children) {
      h("div", attrs, [
        h("button", [
          ("ui-id", S("toggle")),
          ("onclick", E(() => { clicks.val = clicks.val + 1 }))
        ], children)
      ])
    }),
    name=Some("panel")
  )
  let _ = assert_realize(h(box, [], [Str("ok")]))
  let _ = assert_take_cmds()
  click("panel/toggle")
  assert_eq(clicks.val, 1)
}

test "scoped reactive component stops inner effects on remove" {
  assert_reset_dom()
  let source = cel("a")
  let seen : Ref[Array[String]] = Ref::new([])
  let box = scoped(
    comp(fn(attrs, children) {
      let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
      h("div", attrs, children)
    }),
    reactive=true
  )
  let parent = assert_realize(h("section", [], [
    h(box, [], [])
  ]))
  let _ = assert_take_cmds()
  assert_eq(seen.val, ["a"])

  source.set("b")
  flush() catch { _ => panic() }
  let _ = assert_take_cmds()
  assert_eq(seen.val, ["a", "b"])

  remove(parent.children[0])
  let _ = assert_take_cmds()
  source.set("c")
  flush() catch { _ => panic() }
  let _ = assert_take_cmds()
  assert_eq(seen.val, ["a", "b"])
}

test "explicit ui-id wins over scoped name" {
  assert_reset_dom()
  let clicked = Ref::new(false)
  let box = scoped(
    comp(fn(attrs, children) { h("button", attrs, children) }),
    name=Some("scoped:root")
  )
  let node = assert_realize(h(box, [
    ("ui-id", S("plain:root")),
    ("onclick", E(() => { clicked.val = true }))
  ], []))
  let cmds = assert_take_cmds()
  assert_eq(node.ui_id, Some("plain:root"))
  assert_true(cmds.any(fn(cmd) {
    match cmd {
      Attr(id, "ui-id", "plain:root") => id == node.id
      _ => false
    }
  }))
  assert_no_cmd(cmds, fn(cmd) {
    match cmd {
      Attr(_, "ui-id", "scoped:root") => true
      _ => false
    }
  })
  click("plain:root")
  assert_eq(clicked.val, true)
}

test "outer scoped reactive remove stops nested scopes too" {
  assert_reset_dom()
  let source = cel("a")
  let outer_seen : Ref[Array[String]] = Ref::new([])
  let inner_seen : Ref[Array[String]] = Ref::new([])
  let inner = scoped(
    comp(fn(attrs, children) {
      let _ = effect(fn() { inner_seen.val.push(source.get()) }) catch { _ => panic() }
      h("span", attrs, children)
    }),
    reactive=true
  )
  let outer = scoped(
    comp(fn(attrs, children) {
      let _ = effect(fn() { outer_seen.val.push(source.get()) }) catch { _ => panic() }
      h("div", attrs, children)
    }),
    reactive=true
  )
  let parent = assert_realize(h("section", [], [
    h(outer, [], [
      h(inner, [], [])
    ])
  ]))
  let _ = assert_take_cmds()
  assert_eq(outer_seen.val, ["a"])
  assert_eq(inner_seen.val, ["a"])

  source.set("b")
  flush() catch { _ => panic() }
  let _ = assert_take_cmds()
  assert_eq(outer_seen.val, ["a", "b"])
  assert_eq(inner_seen.val, ["a", "b"])

  remove(parent.children[0])
  let _ = assert_take_cmds()
  source.set("c")
  flush() catch { _ => panic() }
  let _ = assert_take_cmds()
  assert_eq(outer_seen.val, ["a", "b"])
  assert_eq(inner_seen.val, ["a", "b"])
}

test "outer scope table keeps nested scope root only" {
  assert_reset_dom()
  let inner = scoped(
    comp(fn(attrs, children) {
      h("div", attrs, [
        h("button", [("ui-id", S("inner-btn"))], children)
      ])
    }),
    name=Some("inner-scope")
  )
  let outer = scoped(
    comp(fn(attrs, children) {
      h("section", attrs, [
        h("button", [("ui-id", S("outer-btn"))], []),
        Arr(children),
      ])
    }),
    name=Some("outer-scope")
  )
  let node = assert_realize(h(outer, [], [
    h(inner, [], [])
  ]))
  let _ = assert_take_cmds()
  let outer_names = match node.scope_names {
    Some(v) => v
    None => panic()
  }
  let inner_id = match outer_names.get("inner-scope") {
    Some(v) => v
    None => panic()
  }
  assert_true(outer_names.get("outer-btn") is Some(_))
  assert_eq(outer_names.get("inner-btn"), None)
  let inner_node = find_child(node.children, inner_id)
  let inner_names = match inner_node.scope_names {
    Some(v) => v
    None => panic()
  }
  assert_true(inner_names.get("inner-btn") is Some(_))
}

test "scoped query path stops at nested scope boundary" {
  assert_reset_dom()
  let outer_clicks = Ref::new(0)
  let inner_clicks = Ref::new(0)
  let inner = scoped(
    comp(fn(attrs, children) {
      h("div", attrs, [
        h("button", [
          ("ui-id", S("toggle")),
          ("onclick", E(() => { inner_clicks.val = inner_clicks.val + 1 }))
        ], children)
      ])
    }),
    name=Some("inner")
  )
  let outer = scoped(
    comp(fn(attrs, children) {
      h("section", attrs, [
        h("button", [
          ("ui-id", S("toggle")),
          ("onclick", E(() => { outer_clicks.val = outer_clicks.val + 1 }))
        ], []),
        Arr(children),
      ])
    }),
    name=Some("outer")
  )
  let _ = assert_realize(h(outer, [], [
    h(inner, [], [])
  ]))
  let _ = assert_take_cmds()
  click("outer/toggle")
  click("outer/inner/toggle")
  assert_eq(outer_clicks.val, 1)
  assert_eq(inner_clicks.val, 1)
}

test "scoped reactive null uses empty text host" {
  assert_reset_dom()
  let source = cel("a")
  let seen : Ref[Array[String]] = Ref::new([])
  let box = scoped(
    comp(fn(_attrs, _children) {
      let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
      Null
    }),
    reactive=true
  )
  let node = assert_realize(h(box, [], []))
  let cmds = assert_take_cmds()
  assert_eq(node.id, assert_create(cmds[0], "", ""))
  assert_text(cmds[1], "")
  assert_eq(seen.val, ["a"])

  source.set("b")
  flush() catch { _ => panic() }
  let _ = assert_take_cmds()
  assert_eq(seen.val, ["a", "b"])

  remove(node)
  let _ = assert_take_cmds()
  source.set("c")
  flush() catch { _ => panic() }
  let _ = assert_take_cmds()
  assert_eq(seen.val, ["a", "b"])
}

test "scoped name without reactive does not own inner effects" {
  assert_reset_dom()
  let source = cel("a")
  let seen : Ref[Array[String]] = Ref::new([])
  let box = scoped(
    comp(fn(attrs, children) {
      let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
      h("div", attrs, children)
    }),
    name=Some("named:only")
  )
  let stop = scope(() => {
    let node = assert_realize(h(box, [], []))
    let _ = assert_take_cmds()
    assert_eq(seen.val, ["a"])

    remove(node)
    let _ = assert_take_cmds()
  }) catch { _ => panic() }

  source.set("b")
  flush() catch { _ => panic() }
  let _ = assert_take_cmds()
  assert_eq(seen.val, ["a", "b"])

  stop()
  source.set("c")
  flush() catch { _ => panic() }
  let _ = assert_take_cmds()
  assert_eq(seen.val, ["a", "b"])
}

test "h_map provides index getter and reruns on changes" {
  assert_reset_dom()
  let items = cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 14)
  assert_eq(builds.val, 2)
  assert_text(cmds[6], "0:A")
  assert_text(cmds[11], "1:B")

  items.set([("B", 0), ("C", 1)])
  flush() catch { _ => panic() }
  let cmds2 = assert_take_cmds()
  assert_eq(builds.val, 3)
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      Remove(_) => true
      _ => false
    }
  }))
  assert_eq(cmds2.filter(fn(cmd) {
    match cmd {
      Create(_, "li", _) => true
      _ => false
    }
  }).length(), 1)
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      InsertBefore(_, _, _) => true
      _ => false
    }
  }))
}

test "h_map keeps duplicate items separate" {
  assert_reset_dom()
  let items = ["A", "A", "B"]
  let builds = Ref::new(0)
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map(items, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 19)
  assert_eq(builds.val, 3)
  assert_text(cmds[6], "0:A")
  assert_text(cmds[11], "1:A")
  assert_text(cmds[16], "2:B")
}

test "h_map watches source function dependencies" {
  assert_reset_dom()
  let items = cel([("A", 9)])
  let source_runs = Ref::new(0)
  let builds = Ref::new(0)
  let source = fn() {
    source_runs.val = source_runs.val + 1
    items.get()
  }
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(source, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 9)
  assert_eq(source_runs.val, 1)
  assert_eq(builds.val, 1)
  assert_text(cmds[6], "9:A")

  items.set([("B", 12)])
  flush() catch { _ => panic() }
  let cmds2 = assert_take_cmds()
  assert_eq(source_runs.val, 2)
  assert_eq(builds.val, 2)
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      Remove(_) => true
      _ => false
    }
  }))
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      Text(_, "12:B") => true
      _ => false
    }
  }))
}

test "h_map_dyn keeps explicit indexes" {
  assert_reset_dom()
  let items = cel([("A", 9), ("B", 10)])
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 14)
  assert_text(cmds[6], "9:A")
  assert_text(cmds[11], "10:B")
}

test "h_map removes only missing keyed item" {
  reset_test_ui()
  let items = cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let initial = assert_take_cmds()
  assert_eq(builds.val, 2)
  let a_text_id = find_text_node_id(initial, "0:A")
  let a_li_id = find_parent_id(initial, a_text_id)
  let b_text_id = find_text_node_id(initial, "1:B")
  let b_li_id = find_parent_id(initial, b_text_id)

  items.set([("B", 0)])
  flush() catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(builds.val, 2)
  assert_true(cmds.any(fn(cmd) { is_remove(cmd, a_li_id) }))
  assert_no_cmd(cmds, fn(cmd) { is_remove(cmd, b_li_id) })
  assert_no_cmd(cmds, fn(cmd) { is_create(cmd, b_li_id) })
}

test "h_map reorders kept keyed items without recreating them" {
  reset_test_ui()
  let items = cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let initial = assert_take_cmds()
  assert_eq(builds.val, 2)
  let a_text_id = find_text_node_id(initial, "0:A")
  let a_li_id = find_parent_id(initial, a_text_id)
  let b_text_id = find_text_node_id(initial, "1:B")
  let b_li_id = find_parent_id(initial, b_text_id)

  items.set([("B", 0), ("A", 1)])
  flush() catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(builds.val, 2)
  assert_no_cmd(cmds, fn(cmd) { is_remove(cmd, a_li_id) || is_remove(cmd, b_li_id) })
  assert_no_cmd(cmds, fn(cmd) { is_create(cmd, a_li_id) || is_create(cmd, b_li_id) })
  assert_true(cmds.any(fn(cmd) { is_insert_before(cmd, a_li_id) || is_insert_before(cmd, b_li_id) }))
}

test "h_map adds render only for new keyed item" {
  reset_test_ui()
  let items = cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let _ = assert_take_cmds()
  assert_eq(builds.val, 2)

  items.set([("A", 0), ("B", 1), ("C", 2)])
  flush() catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(builds.val, 3)
  assert_eq(cmds.filter(fn(cmd) {
    match cmd {
      Create(_, "li", _) => true
      _ => false
    }
  }).length(), 1)
}

test "h_map stops removed item effects" {
  reset_test_ui()
  let items = cel([("A", 0), ("B", 1)])
  let source = cel("x")
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        h("li", [], [
          Str("\{i()}:\{x}:"),
          Dyn(fn() { Str(source.get()) })
        ])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let initial = assert_take_cmds()
  let a_text_id = find_text_node_id(initial, "0:A:")
  let a_li_id = find_parent_id(initial, a_text_id)

  items.set([("B", 0)])
  flush() catch { _ => panic() }
  let _ = assert_take_cmds()
  source.set("y")
  flush() catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_no_cmd(cmds, fn(cmd) { is_create(cmd, a_li_id) || is_remove(cmd, a_li_id) })
  assert_no_cmd(cmds, fn(cmd) {
    match cmd {
      UpdateText(id, _) => id == a_text_id
      Text(id, _) => id == a_text_id
      _ => false
    }
  })
}

test "h_map keeps listener registration stable for kept item" {
  reset_test_ui()
  let items = cel([("A", 0), ("B", 1)])
  let clicks = Ref::new(0)
  let seen_indexes: Ref[Array[Int]] = Ref::new([])
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        h("button", [
          ("ui-id", S("item:\{x}")),
          ("onclick", E(() => {
            clicks.val = clicks.val + 1
            seen_indexes.val.push(i())
            ignore(x)
          }))
        ], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let initial = assert_take_cmds()
  let a_text_id = find_text_node_id(initial, "0:A")
  let a_button_id = find_parent_id(initial, a_text_id)

  items.set([("B", 0), ("A", 1), ("C", 2)])
  flush() catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(cmds.filter(fn(cmd) {
    match cmd {
      Listen(id, "onclick", _) => id == a_button_id
      _ => false
    }
  }).length(), 0)

  click("item:A")
  assert_eq(clicks.val, 1)
  assert_eq(seen_indexes.val, [1])
}

test "h_map removes only one duplicate entry" {
  reset_test_ui()
  let items = cel([("A", 0), ("A", 1), ("B", 2)])
  let builds = Ref::new(0)
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let initial = assert_take_cmds()
  assert_eq(builds.val, 3)
  let a0_text_id = find_text_node_id(initial, "0:A")
  let a0_li_id = find_parent_id(initial, a0_text_id)
  let a1_text_id = find_text_node_id(initial, "1:A")
  let a1_li_id = find_parent_id(initial, a1_text_id)
  let b_text_id = find_text_node_id(initial, "2:B")
  let b_li_id = find_parent_id(initial, b_text_id)

  items.set([("A", 0), ("B", 1)])
  flush() catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(builds.val, 3)
  assert_true(cmds.any(fn(cmd) { is_remove(cmd, a1_li_id) }))
  assert_no_cmd(cmds, fn(cmd) { is_remove(cmd, a0_li_id) || is_remove(cmd, b_li_id) })
  assert_no_cmd(cmds, fn(cmd) { is_create(cmd, a0_li_id) || is_create(cmd, b_li_id) })
}

test "svg namespace propagates through foreignObject" {
  assert_reset_dom()
  let _ = assert_realize(h("svg", [], [
    h("foreignObject", [], [
      h("span", [], [])
    ])
  ]))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 5)
  let _ = assert_create(cmds[0], "svg", "http://www.w3.org/2000/svg")
  let _ = assert_create(cmds[1], "foreignObject", "http://www.w3.org/2000/svg")
  let _ = assert_create(cmds[2], "span", "http://www.w3.org/1999/xhtml")
}

test "h handles dynamic attributes" {
  assert_reset_dom()
  let count = cel(0)
  let _ = scope(() => {
    let _ = assert_realize(h("div", [("data-count", D(() => count.get().to_string()))], []))
    ()
  }) catch { _ => panic() }
  
  let cmds1 = assert_take_cmds()
  // Create, UpdateAttr (triggered by first effect run)
  assert_eq(cmds1.length(), 2)
  assert_update_attr(cmds1[1], "data-count", "0")

  count.set(1)
  flush() catch { _ => panic() }
  let cmds2 = assert_take_cmds()
  assert_eq(cmds2.length(), 1)
  assert_update_attr(cmds2[0], "data-count", "1")
}

test "Str and Dyn" {
  assert_reset_dom()
  let val = cel("a")
  let _ = scope(() => {
    let _ = assert_realize(h("div", [], [
      Str("hello"),
      Dyn(fn() { Str(val.get()) })
    ]))
    ()
  }) catch { _ => panic() }
  
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 10)

  val.set("b")
  flush() catch { _ => panic() }
  let cmds2 = assert_take_cmds()
  assert_eq(cmds2.length(), 4)
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      Remove(_) => true
      _ => false
    }
  }))
}

test "events and callback triggering" {
  assert_reset_dom()
  let clicked = Ref::new(false)
  let node = assert_realize(h("button", [
    ("ui-id", S("button:main")),
    ("onclick", E(() => { clicked.val = true }))
  ], []))
  let cmds = assert_take_cmds()
  
  assert_eq(cmds.length(), 3)
  assert_attr(cmds[1], "ui-id", "button:main")
  assert_listen(cmds[2], "onclick", node.id, "button:main")

  click("button:main")
  assert_eq(clicked.val, true)
}

test "remove emits cmd" {
  assert_reset_dom()
  let node = assert_realize(h("div", [], []))
  let _ = assert_take_cmds()
  let _ = scope(() => {
    let _ = assert_realize(h("div", [], [Dyn(fn() {
      remove(node)
      Null
    })]))
    ()
  }) catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_true(cmds.any(fn(cmd) {
    match cmd {
      Remove(id) => id == node.id
      _ => false
    }
  }))
}

test "remove cleans subtree callbacks" {
  assert_reset_dom()
  let child_clicked = Ref::new(0)
  let parent = assert_realize(h("div", [], [
    h("button", [
      ("ui-id", S("child:button")),
      ("onclick", E(() => child_clicked.val = child_clicked.val + 1))
    ], [])
  ]))
  let _ = assert_take_cmds()

  remove(parent)
  let _ = assert_take_cmds()
  click("child:button")
  assert_eq(child_clicked.val, 0)
}

test "same ui-id keeps event handler after dyn rerender" {
  assert_reset_dom()
  let done = cel(false)
  let clicks = Ref::new(0)
  let _ = scope(() => {
    let _ = assert_realize(h("div", [], [
      Dyn(fn() {
        h("button", [
          ("ui-id", S("toggle:item")),
          ("onclick", E(() => {
            clicks.val = clicks.val + 1
            done.set(!done.get())
          }))
        ], [
          Str(if done.get() { "done" } else { "todo" })
        ])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let _ = assert_take_cmds()

  click("toggle:item")
  let first = assert_take_cmds()
  assert_true(first.any(fn(cmd) {
    match cmd {
      Remove(_) => true
      _ => false
    }
  }))

  click("toggle:item")
  let second = assert_take_cmds()
  assert_true(second.any(fn(cmd) {
    match cmd {
      Remove(_) => true
      _ => false
    }
  }))
  assert_eq(clicks.val, 2)
}

test "remove stops dynamic updates for subtree" {
  assert_reset_dom()
  let source = cel("a")
  let stop = scope(() => {
    let parent = assert_realize(h("div", [], [Dyn(fn() { Str(source.get()) })]))
    remove(parent)
  }) catch { _ => panic() }
  let _ = assert_take_cmds()

  source.set("b")
  flush() catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 0)
  stop()
}

test "Dyn handles nested arrays and components" {
  assert_reset_dom()
  let list = cel(["A", "B"])
  let _ = scope(() => {
    let _ = assert_realize(h("ul", [], [
      Dyn(fn() { 
        Arr(list.get().map(fn(x) { h("li", [], [Str(x)]) }))
      })
    ]))
    ()
  }) catch { _ => panic() }
  
  let cmds = assert_take_cmds()
  // Create(ul), Create(anchor), Text(anchor, ""), Append(ul, anchor), 
  // Initial run of Dyn:
  // Create(liA), Create(textA), Text(textA, "A"), Append(liA, textA), InsertBefore(ul, liA, anchor)
  // Create(liB), Create(textB), Text(textB, "B"), Append(liB, textB), InsertBefore(ul, liB, anchor)
  assert_eq(cmds.length(), 14)

  list.set(["C"])
  flush() catch { _ => panic() }
  let cmds2 = assert_take_cmds()
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      Remove(_) => true
      _ => false
    }
  }))
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      Text(_, "C") => true
      _ => false
    }
  }))
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      InsertBefore(_, _, _) => true
      _ => false
    }
  }))
}


test "to_json gives compact array format" {
  let cmd = Text(1, "\"")
  assert_eq(cmd.to_json(), "[1,1,\"\\\"\"]")
}

test "SetStyle emits correct json" {
  let cmd = SetStyle(5, "color", "red")
  assert_eq(cmd.to_json(), "[10,5,\"color\",\"red\"]")
}

test "RemoveStyle emits correct json" {
  let cmd = RemoveStyle(5, "color")
  assert_eq(cmd.to_json(), "[11,5,\"color\"]")
}

test "RemoveAttr emits correct json" {
  let cmd = RemoveAttr(5, "class")
  assert_eq(cmd.to_json(), "[12,5,\"class\"]")
}

test "HostCmd emits correct json" {
  let cmd = HostCmd(3, "focus")
  assert_eq(cmd.to_json(), "[13,3,\"focus\"]")
}

test "EventData from_json parses pipe format" {
  let ev = EventData::from_json("Enter|Enter|1|0|0|0")
  assert_eq(ev.key, "Enter")
  assert_eq(ev.code, "Enter")
  assert_eq(ev.ctrl, true)
  assert_eq(ev.shift, false)
  assert_eq(ev.alt, false)
  assert_eq(ev.meta, false)
}

test "EK callback receives event data" {
  assert_reset_dom()
  let received = Ref::new(EventData::default())
  let node = assert_realize(h("div", [
    ("ui-id", S("key-target")),
    ("onkeydown", EK(fn(ev) { received.val = ev }))
  ], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 3)
  assert_attr(cmds[1], "ui-id", "key-target")
  assert_listen(cmds[2], "onkeydown", node.id, "key-target")
  let ev = EventData::from_json("a|KeyA|0|0|0|0")
  trigger_ui_ev("key-target", "onkeydown", ev)
  assert_eq(received.val.key, "a")
  assert_eq(received.val.code, "KeyA")
}

test "host command helpers emit correct cmds" {
  assert_reset_dom()
  let _ = scope(() => {
    let _ = assert_realize(h("div", [], [Dyn(fn() {
      focus_node(10)
      blur_node(11)
      scroll_into_view(12)
      Null
    })]))
    ()
  }) catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_true(cmds.any(fn(cmd) {
    match cmd {
      HostCmd(10, "focus") => true
      _ => false
    }
  }))
  assert_true(cmds.any(fn(cmd) {
    match cmd {
      HostCmd(11, "blur") => true
      _ => false
    }
  }))
  assert_true(cmds.any(fn(cmd) {
    match cmd {
      HostCmd(12, "scrollIntoView") => true
      _ => false
    }
  }))
}



test "h creates elements and attributes" {
  assert_reset_dom()
  let _ = assert_realize(h("div", [("class", S("btn")), ("id", S("main"))], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 3)
  assert_cmd(cmds[0], Create("div", ""))
  assert_cmd(cmds[1], Attr(1, "class", "btn"))
  assert_cmd(cmds[2], Attr(1, "id", "main"))
}

test "h handles children" {
  assert_reset_dom()
  let parent = assert_realize(h("div", [], [h("span", [], [])]))
  let cmds = assert_take_cmds()
  // parent: Create
  // child: Create
  // Append(parent, child)
  assert_eq(cmds.length(), 3)
  let parent_id = assert_cmd_id(cmds[0], Create("div", ""))
  let child_id = assert_cmd_id(cmds[1], Create("span", ""))
  assert_cmd(cmds[2], Append(parent_id, child_id))
  assert_eq(parent.id, parent_id)
}

test "h dispatches comp values" {
  assert_reset_dom()
  let box = comp(fn(attrs, children) { h("section", attrs, children) })
  let node = assert_realize(h(box, [("class", S("panel"))], [Str("ok")]))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 5)
  let text_id = assert_cmd_id(cmds[2], Create("", ""))
  assert_eq(node.id, assert_cmd_id(cmds[0], Create("section", "")))
  assert_cmd(cmds[1], Attr(node.id, "class", "panel"))
  assert_cmd(cmds[3], Text("ok"))
  assert_cmd(cmds[4], Append(node.id, text_id))
}

test "h nests comp values like regular children" {
  assert_reset_dom()
  let box = comp(fn(attrs, children) { h("section", attrs, children) })
  let _ = assert_realize(h("div", [], [
    h(box, [("class", S("panel"))], [Str("ok")])
  ]))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 7)
  let div_id = assert_cmd_id(cmds[0], Create("div", ""))
  let section_id = assert_cmd_id(cmds[1], Create("section", ""))
  let text_id = assert_cmd_id(cmds[3], Create("", ""))
  assert_cmd(cmds[2], Attr(section_id, "class", "panel"))
  assert_cmd(cmds[4], Text("ok"))
  assert_cmd(cmds[5], Append(section_id, text_id))
  assert_cmd(cmds[6], Append(div_id, section_id))
}

test "ui-name can name component root" {
  assert_reset_dom()
  let clicked = Ref::new(false)
  let box = comp(fn(attrs, children) {
    h("button", attrs, [
      h("span", [("ui-id", S("label"))], children)
    ])
  })
  let node = assert_realize(h(box, [
    ("ui-id", S("scoped:root")),
    ("ui-name", S("true")),
    ("onclick", E(() => { clicked.val = true }))
  ], [
    Str("ok")
  ]))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 11)
  assert_eq(node.id, assert_cmd_id(cmds[0], Create("button", "")))
  assert_cmd(cmds[1], Attr(node.id, "ui-id", "scoped:root"))
  assert_has_cmd(cmds, Attr(node.id, "class", "scoped-root"))
  assert_has_cmd(cmds, Listen(node.id, "onclick", "scoped:root"))
  let label_id = find_create_id(cmds, "span")
  let text_id = find_text_node_id(cmds, "ok")
  assert_has_cmd(cmds, Attr(label_id, "ui-id", "label"))
  assert_has_cmd(cmds, Attr(label_id, "class", "label"))
  assert_has_cmd(cmds, Append(label_id, text_id))
  assert_has_cmd(cmds, Append(node.id, label_id))
  let names = match node.scope_names {
    Some(v) => v
    None => panic()
  }
  assert_eq(names.get("label"), Some(label_id))
  click("scoped:root/label")
  click("scoped:root")
  assert_eq(clicked.val, true)
}

test "ui-name can name element root" {
  assert_reset_dom()
  let clicked = Ref::new(false)
  let node = assert_realize(h("button", [
    ("ui-id", S("scoped:attr")),
    ("ui-name", S("true")),
    ("onclick", E(() => { clicked.val = true }))
  ], [
    h("span", [("ui-id", S("label"))], [Str("ok")])
  ]))
  let cmds = assert_take_cmds()
  assert_eq(node.id, assert_cmd_id(cmds[0], Create("button", "")))
  let names = match node.scope_names {
    Some(v) => v
    None => panic()
  }
  assert_true(names.get("label") is Some(_))
  click("scoped:attr/label")
  click("scoped:attr")
  assert_eq(clicked.val, true)
}

test "ui-name query path reaches nested local node" {
  assert_reset_dom()
  let clicks = Ref::new(0)
  let box = comp(fn(attrs, children) {
    h("div", attrs, [
      h("button", [
        ("ui-id", S("toggle")),
        ("onclick", E(() => { clicks.val = clicks.val + 1 }))
      ], children)
    ])
  })
  let _ = assert_realize(h(box, [
    ("ui-id", S("panel")),
    ("ui-name", S("true"))
  ], [Str("ok")]))
  let _ = assert_take_cmds()
  click("panel/toggle")
  assert_eq(clicks.val, 1)
}

test "ui-react component stops inner effects on remove" {
  assert_reset_dom()
  let source = cel("a")
  let seen : Ref[Array[String]] = Ref::new([])
  let box = comp(fn(attrs, children) {
    let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
    h("div", attrs, children)
  })
  let parent = assert_realize(h("section", [], [
    h(box, [("ui-react", S("true"))], [])
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

test "ui-name keeps explicit ui-id as root id" {
  assert_reset_dom()
  let clicked = Ref::new(false)
  let box = comp(fn(attrs, children) { h("button", attrs, children) })
  let node = assert_realize(h(box, [
    ("ui-id", S("plain:root")),
    ("ui-name", S("true")),
    ("onclick", E(() => { clicked.val = true }))
  ], []))
  let cmds = assert_take_cmds()
  assert_eq(node.ui_id, Some("plain:root"))
  assert_has_cmd(cmds, Attr(node.id, "ui-id", "plain:root"))
  click("plain:root")
  assert_eq(clicked.val, true)
}

test "outer ui-react remove stops nested scopes too" {
  assert_reset_dom()
  let source = cel("a")
  let outer_seen : Ref[Array[String]] = Ref::new([])
  let inner_seen : Ref[Array[String]] = Ref::new([])
  let inner = comp(fn(attrs, children) {
    let _ = effect(fn() { inner_seen.val.push(source.get()) }) catch { _ => panic() }
    h("span", attrs, children)
  })
  let outer = comp(fn(attrs, children) {
    let _ = effect(fn() { outer_seen.val.push(source.get()) }) catch { _ => panic() }
    h("div", attrs, children)
  })
  let parent = assert_realize(h("section", [], [
    h(outer, [("ui-react", S("true"))], [
      h(inner, [("ui-react", S("true"))], [])
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

test "outer ui-name table keeps nested scope root only" {
  assert_reset_dom()
  let inner = comp(fn(attrs, children) {
    h("div", attrs, [
      h("button", [("ui-id", S("inner-btn"))], children)
    ])
  })
  let outer = comp(fn(attrs, children) {
    h("section", attrs, [
      h("button", [("ui-id", S("outer-btn"))], []),
      Arr(children),
    ])
  })
  let node = assert_realize(h(outer, [
    ("ui-id", S("outer-scope")),
    ("ui-name", S("true"))
  ], [
    h(inner, [
      ("ui-id", S("inner-scope")),
      ("ui-name", S("true"))
    ], [])
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

test "ui-name query path stops at nested scope boundary" {
  assert_reset_dom()
  let outer_clicks = Ref::new(0)
  let inner_clicks = Ref::new(0)
  let inner = comp(fn(attrs, children) {
    h("div", attrs, [
      h("button", [
        ("ui-id", S("toggle")),
        ("onclick", E(() => { inner_clicks.val = inner_clicks.val + 1 }))
      ], children)
    ])
  })
  let outer = comp(fn(attrs, children) {
    h("section", attrs, [
      h("button", [
        ("ui-id", S("toggle")),
        ("onclick", E(() => { outer_clicks.val = outer_clicks.val + 1 }))
      ], []),
      Arr(children),
    ])
  })
  let _ = assert_realize(h(outer, [
    ("ui-id", S("outer")),
    ("ui-name", S("true"))
  ], [
    h(inner, [
      ("ui-id", S("inner")),
      ("ui-name", S("true"))
    ], [])
  ]))
  let _ = assert_take_cmds()
  click("outer/toggle")
  click("outer/inner/toggle")
  assert_eq(outer_clicks.val, 1)
  assert_eq(inner_clicks.val, 1)
}

test "ui-list query uses child index" {
  assert_reset_dom()
  let clicks = Ref::new(0)
  let box = comp(fn(attrs, _children) {
    h("div", attrs, [
      h("button", [
        ("ui-id", S("toggle")),
        ("onclick", E(() => { clicks.val = clicks.val + 1 }))
      ], [Str("A")]),
      h("button", [
        ("ui-id", S("toggle")),
        ("onclick", E(() => { clicks.val = clicks.val + 1 }))
      ], [Str("B")]),
    ])
  })
  let node = assert_realize(h(box, [
    ("ui-id", S("todos")),
    ("ui-list", S("true"))
  ], []))
  let _ = assert_take_cmds()
  assert_true(node.list_items is Some(_))
  click("todos/0/toggle")
  click("todos/1/toggle")
  assert_eq(clicks.val, 2)
}

test "h_map items expose local names for list query" {
  assert_reset_dom()
  let clicks = Ref::new(0)
  let list = comp(fn(attrs, _children) {
    h("div", attrs, [
      h_map(["A", "B"], fn(label, _i) {
        Arr([
          h("span", [("ui-id", S("label"))], [Str(label)]),
          h("button", [
            ("ui-id", S("toggle")),
            ("onclick", E(() => { clicks.val = clicks.val + 1 }))
          ], [Str(label)])
        ])
      })
    ])
  })
  let _ = scope(() => {
    let _ = assert_realize(h(list, [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], []))
    ()
  }) catch { _ => panic() }
  let _ = assert_take_cmds()
  click("todos/0/toggle")
  click("todos/1/toggle")
  assert_eq(clicks.val, 2)
}

test "ui-react null uses empty text host" {
  assert_reset_dom()
  let source = cel("a")
  let seen : Ref[Array[String]] = Ref::new([])
  let box = comp(fn(_attrs, _children) {
    let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
    Null
  })
  let node = assert_realize(h(box, [("ui-react", S("true"))], []))
  let cmds = assert_take_cmds()
  assert_eq(node.id, assert_cmd_id(cmds[0], Create("", "")))
  assert_cmd(cmds[1], Text(""))
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

test "ui-name without ui-react does not own inner effects" {
  assert_reset_dom()
  let source = cel("a")
  let seen : Ref[Array[String]] = Ref::new([])
  let box = comp(fn(attrs, children) {
    let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
    h("div", attrs, children)
  })
  let stop = scope(() => {
    let node = assert_realize(h(box, [
      ("ui-id", S("named:only")),
      ("ui-name", S("true"))
    ], []))
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
  assert_cmd(cmds[6], Text("0:A"))
  assert_cmd(cmds[11], Text("1:B"))

  items.set([("B", 0), ("C", 1)])
  flush() catch { _ => panic() }
  let cmds2 = assert_take_cmds()
  assert_eq(builds.val, 3)
  assert_has_cmd(cmds2, AnyRemove)
  assert_eq(cmds2.filter(fn(cmd) {
    match cmd {
      Create(_, "li", _) => true
      _ => false
    }
  }).length(), 1)
  assert_has(cmds2, fn(cmd) {
    match cmd {
      InsertBefore(_, _, _) => true
      _ => false
    }
  })
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
  assert_cmd(cmds[6], Text("0:A"))
  assert_cmd(cmds[11], Text("1:A"))
  assert_cmd(cmds[16], Text("2:B"))
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
  assert_cmd(cmds[6], Text("9:A"))

  items.set([("B", 12)])
  flush() catch { _ => panic() }
  let cmds2 = assert_take_cmds()
  assert_eq(source_runs.val, 2)
  assert_eq(builds.val, 2)
  assert_has_cmd(cmds2, AnyRemove)
  assert_has_cmd(cmds2, Text("12:B"))
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
  assert_cmd(cmds[6], Text("9:A"))
  assert_cmd(cmds[11], Text("10:B"))
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
  assert_has_cmd(cmds, Remove(a_li_id))
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
  assert_has(cmds, fn(cmd) { is_insert_before(cmd, a_li_id) || is_insert_before(cmd, b_li_id) })
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
  assert_has_cmd(cmds, Remove(a1_li_id))
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
  assert_cmd(cmds[0], Create("svg", "http://www.w3.org/2000/svg"))
  assert_cmd(cmds[1], Create("foreignObject", "http://www.w3.org/2000/svg"))
  assert_cmd(cmds[2], Create("span", "http://www.w3.org/1999/xhtml"))
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
  assert_cmd(cmds1[1], UpdateAttr("data-count", "0"))

  count.set(1)
  flush() catch { _ => panic() }
  let cmds2 = assert_take_cmds()
  assert_eq(cmds2.length(), 1)
  assert_cmd(cmds2[0], UpdateAttr("data-count", "1"))
}

test "ui-id also emits derived class" {
  assert_reset_dom()
  let _ = assert_realize(h("div", [("ui-id", S("entry:main/button"))], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 3)
  assert_cmd(cmds[0], Create("div", ""))
  assert_cmd(cmds[1], Attr(1, "ui-id", "entry:main/button"))
  assert_cmd(cmds[2], Attr(1, "class", "button"))
}

test "explicit class keeps derived ui class" {
  assert_reset_dom()
  let _ = assert_realize(h("div", [
    ("ui-id", S("entry:main/button")),
    ("class", S("card"))
  ], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 3)
  assert_cmd(cmds[2], Attr(1, "class", "card button"))
}

test "style property emits style command" {
  assert_reset_dom()
  let _ = assert_realize(h("div", [("style:background-color", S("red"))], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 2)
  assert_cmd(cmds[0], Create("div", ""))
  assert_cmd(cmds[1], SetStyle("background-color", "red"))
}

test "dynamic style property updates and removes" {
  assert_reset_dom()
  let color = cel("red")
  let _ = scope(() => {
    let _ = assert_realize(h("div", [("style:background-color", D(() => color.get()))], []))
    ()
  }) catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 2)
  assert_cmd(cmds[1], SetStyle("background-color", "red"))

  color.set("blue")
  flush() catch { _ => panic() }
  let cmds2 = assert_take_cmds()
  assert_eq(cmds2.length(), 1)
  assert_cmd(cmds2[0], SetStyle("background-color", "blue"))

  color.set("")
  flush() catch { _ => panic() }
  let cmds3 = assert_take_cmds()
  assert_eq(cmds3.length(), 1)
  assert_cmd(cmds3[0], RemoveStyle("background-color"))
}

test "css emits set update and remove" {
  assert_reset_dom()
  let theme = cel("red")
  let stop = scope(() => {
    let style_host = comp(fn(_attrs, _children) {
      css("theme", D(() => ".root { color: \{theme.get()}; }"))
      h("div", [], [])
    })
    let _ = assert_realize(h(style_host, [], []))
    ()
  }) catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_has_cmd(cmds, SetCss("theme", ".theme .root{ color: red; }"))

  theme.set("blue")
  flush() catch { _ => panic() }
  let cmds2 = assert_take_cmds()
  assert_has_cmd(cmds2, SetCss("theme", ".theme .root{ color: blue; }"))

  stop()
  let cmds3 = assert_take_cmds()
  assert_eq(cmds3.length(), 1)
  assert_cmd(cmds3[0], RemoveCss("theme"))
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
  assert_has_cmd(cmds2, AnyRemove)
}

test "events and callback triggering" {
  assert_reset_dom()
  let clicked = Ref::new(false)
  let node = assert_realize(h("button", [
    ("ui-id", S("button:main")),
    ("onclick", E(() => { clicked.val = true }))
  ], []))
  let cmds = assert_take_cmds()
  
  assert_eq(cmds.length(), 4)
  assert_cmd(cmds[1], Attr(node.id, "ui-id", "button:main"))
  assert_cmd(cmds[2], Listen(node.id, "onclick", "button:main"))
  assert_cmd(cmds[3], Attr(node.id, "class", "button-main"))

  click("button:main")
  assert_eq(clicked.val, true)
}

test "css prefixes selectors inside media" {
  assert_reset_dom()
  let stop = scope(() => {
    let style_host = comp(fn(_attrs, _children) {
      css("host", S("@media (max-width: 600px) { .root { color: red; } }"))
      h("div", [], [])
    })
    let _ = assert_realize(h(style_host, [], []))
    ()
  }) catch { _ => panic() }
  let cmds = assert_take_cmds()
  assert_has_cmd(cmds, SetCss("host", "@media (max-width: 600px) {.host .root{ color: red; } }"))
  stop()
  let _ = assert_take_cmds()
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
  assert_has_cmd(cmds, Remove(node.id))
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
  assert_has_cmd(first, AnyRemove)

  click("toggle:item")
  let second = assert_take_cmds()
  assert_has_cmd(second, AnyRemove)
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
  assert_has_cmd(cmds2, AnyRemove)
  assert_has_cmd(cmds2, Text("C"))
  assert_has(cmds2, fn(cmd) {
    match cmd {
      InsertBefore(_, _, _) => true
      _ => false
    }
  })
}


test "to_json gives compact array format" {
  let cmd = DomCmd::Text(1, "\"")
  assert_cmd_json(cmd, "[1,1,\"\\\"\"]")
}

test "SetStyle emits correct json" {
  let cmd = DomCmd::SetStyle(5, "color", "red")
  assert_cmd_json(cmd, "[10,5,\"color\",\"red\"]")
}

test "RemoveStyle emits correct json" {
  let cmd = DomCmd::RemoveStyle(5, "color")
  assert_cmd_json(cmd, "[11,5,\"color\"]")
}

test "RemoveAttr emits correct json" {
  let cmd = DomCmd::RemoveAttr(5, "class")
  assert_cmd_json(cmd, "[12,5,\"class\"]")
}

test "HostCmd emits correct json" {
  let cmd = DomCmd::HostCmd(3, "focus")
  assert_cmd_json(cmd, "[13,3,\"focus\"]")
}

test "SetCss emits correct json" {
  let cmd = DomCmd::SetCss("theme", ".theme .root{ color: red; }")
  assert_cmd_json(cmd, "[14,\"theme\",\".theme .root{ color: red; }\"]")
}

test "RemoveCss emits correct json" {
  let cmd = DomCmd::RemoveCss("theme")
  assert_cmd_json(cmd, "[15,\"theme\"]")
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
  assert_eq(cmds.length(), 4)
  assert_cmd(cmds[1], Attr(node.id, "ui-id", "key-target"))
  assert_cmd(cmds[2], Listen(node.id, "onkeydown", "key-target"))
  assert_cmd(cmds[3], Attr(node.id, "class", "key-target"))
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
  assert_has_cmd(cmds, HostCmd(10, "focus"))
  assert_has_cmd(cmds, HostCmd(11, "blur"))
  assert_has_cmd(cmds, HostCmd(12, "scrollIntoView"))
}

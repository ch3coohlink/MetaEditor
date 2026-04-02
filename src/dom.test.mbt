test "h creates elements and attributes" {
  reset_test_state()
  let _ = assert_realize(h("div", [("class", S("btn")), ("id", S("main"))], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 3)
  let _ = assert_cmds(cmds, [
    Create(id("div"), v("div"), any()),
    Attr(id("div"), v("class"), v("btn")),
    Attr(id("div"), v("id"), v("main"))
  ])
}

test "h handles children" {
  reset_test_state()
  let parent = assert_realize(h("div", [], [h("span", [], [])]))
  let cmds = assert_take_cmds()
  // parent: Create
  // child: Create
  // Append(parent, child)
  assert_eq(cmds.length(), 3)
  let env = assert_cmds(cmds, [
    Create(id("parent"), v("div"), any()),
    Create(id("child"), v("span"), any()),
    Append(id("parent"), id("child"))
  ])
  let parent_id = get_int(env, "parent")
  assert_eq(parent.id, parent_id)
}

test "h dispatches comp values" {
  reset_test_state()
  let box = comp(fn(attrs, children) { h("section", attrs, children) })
  let node = assert_realize(h(box, [("class", S("panel"))], [Str("ok")]))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 5)
  let env = assert_cmds(cmds, [
    Create(id("section"), v("section"), any()),
    Attr(id("section"), v("class"), v("panel")),
    Create(id("text"), v(""), v("")),
    Text(id("text"), v("ok")),
    Append(id("section"), id("text"))
  ])
  assert_eq(node.id, get_int(env, "section"))
}

test "h nests comp values like regular children" {
  reset_test_state()
  let box = comp(fn(attrs, children) { h("section", attrs, children) })
  let _ = assert_realize(h("div", [], [
    h(box, [("class", S("panel"))], [Str("ok")])
  ]))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 7)
  let _ = assert_cmds(cmds, [
    Create(id("div"), v("div"), any()),
    Create(id("section"), v("section"), any()),
    Attr(id("section"), v("class"), v("panel")),
    Create(id("text"), v(""), v("")),
    Text(id("text"), v("ok")),
    Append(id("section"), id("text")),
    Append(id("div"), id("section"))
  ])
}

test "ui-name can name component root" {
  reset_test_state()
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
  let (label_id, text_id) = find_text_mount(cmds, "ok")
  let env = assert_prefix_cmds(cmds, [
    Create(id("root"), v("button"), any()),
    Attr(id("root"), v("ui-id"), v("scoped:root"))
  ])
  assert_eq(node.id, get_int(env, "root"))
  let _ = assert_unordered_cmds(cmds, [
    Attr(v(node.id), v("class"), v("scoped-root")),
    Listen(v(node.id), v("onclick"), v("scoped:root")),
    Attr(v(label_id), v("ui-id"), v("label")),
    Attr(v(label_id), v("class"), v("label")),
    Append(v(label_id), v(text_id)),
    Append(v(node.id), v(label_id))
  ])
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
  reset_test_state()
  let clicked = Ref::new(false)
  let node = assert_realize(h("button", [
    ("ui-id", S("scoped:attr")),
    ("ui-name", S("true")),
    ("onclick", E(() => { clicked.val = true }))
  ], [
    h("span", [("ui-id", S("label"))], [Str("ok")])
  ]))
  let cmds = assert_take_cmds()
  let env = assert_cmd(cmds[0], Create(id("root"), v("button"), any()))
  assert_eq(node.id, get_int(env, "root"))
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
  reset_test_state()
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
  reset_test_state()
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
  let _ = flush_cmds()
  assert_eq(seen.val, ["a", "b"])

  remove(parent.children[0])
  let _ = assert_take_cmds()
  source.set("c")
  let _ = flush_cmds()
  assert_eq(seen.val, ["a", "b"])
}

test "ui-name keeps explicit ui-id as root id" {
  reset_test_state()
  let clicked = Ref::new(false)
  let box = comp(fn(attrs, children) { h("button", attrs, children) })
  let node = assert_realize(h(box, [
    ("ui-id", S("plain:root")),
    ("ui-name", S("true")),
    ("onclick", E(() => { clicked.val = true }))
  ], []))
  let cmds = assert_take_cmds()
  assert_eq(node.ui_id, Some("plain:root"))
  assert_has_cmd(cmds, Attr(v(node.id), v("ui-id"), v("plain:root")))
  click("plain:root")
  assert_eq(clicked.val, true)
}

test "outer ui-react remove stops nested scopes too" {
  reset_test_state()
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
  let _ = flush_cmds()
  assert_eq(outer_seen.val, ["a", "b"])
  assert_eq(inner_seen.val, ["a", "b"])

  remove(parent.children[0])
  let _ = assert_take_cmds()
  source.set("c")
  let _ = flush_cmds()
  assert_eq(outer_seen.val, ["a", "b"])
  assert_eq(inner_seen.val, ["a", "b"])
}

test "outer ui-name table keeps nested scope root only" {
  reset_test_state()
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
  reset_test_state()
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
  reset_test_state()
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
  reset_test_state()
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
  let _ = test_scope(() => {
    let _ = assert_realize(h(list, [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], []))
    ()
  })
  let _ = assert_take_cmds()
  click("todos/0/toggle")
  click("todos/1/toggle")
  assert_eq(clicks.val, 2)
}

test "h_map root Dyn items expose local names for list query" {
  reset_test_state()
  let clicks = Ref::new(0)
  let list = comp(fn(attrs, _children) {
    h("div", attrs, [
      h_map(["A", "B"], fn(label, _i) {
        Dyn(fn() {
          Arr([
            h("span", [("ui-id", S("label"))], [Str(label)]),
            h("button", [
              ("ui-id", S("toggle")),
              ("onclick", E(() => { clicks.val = clicks.val + 1 }))
            ], [Str(label)])
          ])
        })
      })
    ])
  })
  let _ = test_scope(() => {
    let _ = assert_realize(h(list, [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], []))
    ()
  })
  let _ = assert_take_cmds()
  click("todos/0/toggle")
  click("todos/1/toggle")
  assert_eq(clicks.val, 2)
}

test "h_map root Dyn query follows current visible nodes after shape change" {
  reset_test_state()
  let expanded = cel(false)
  let clicks: Ref[Array[String]] = Ref::new([])
  let list = comp(fn(attrs, _children) {
    h("div", attrs, [
      h_map(["A", "B"], fn(label, _i) {
        Dyn(fn() {
          if expanded.get() {
            Arr([
              h("span", [("ui-id", S("label"))], [Str("open:\{label}")]),
              h("button", [
                ("ui-id", S("toggle")),
                ("onclick", E(() => { clicks.val.push("open:\{label}") }))
              ], [Str(label)])
            ])
          } else {
            h("button", [
              ("ui-id", S("toggle")),
              ("onclick", E(() => { clicks.val.push("closed:\{label}") }))
            ], [Str(label)])
          }
        })
      })
    ])
  })
  let _ = test_scope(() => {
    let _ = assert_realize(h(list, [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], []))
    ()
  })
  let _ = assert_take_cmds()

  click("todos/0/toggle")
  click("todos/1/toggle")
  assert_eq(clicks.val, ["closed:A", "closed:B"])

  expanded.set(true)
  let _ = flush_cmds()
  click("todos/0/toggle")
  click("todos/1/toggle")
  assert_eq(clicks.val, ["closed:A", "closed:B", "open:A", "open:B"])
}

test "ui-react null uses empty text host" {
  reset_test_state()
  let source = cel("a")
  let seen : Ref[Array[String]] = Ref::new([])
  let box = comp(fn(_attrs, _children) {
    let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
    Null
  })
  let node = assert_realize(h(box, [("ui-react", S("true"))], []))
  let cmds = assert_take_cmds()
  let env = assert_cmd(cmds[0], Create(id("node"), v(""), v("")))
  assert_eq(node.id, get_int(env, "node"))
  let _ = assert_cmd(cmds[1], Text(id("node"), v("")))
  assert_eq(seen.val, ["a"])

  source.set("b")
  let _ = flush_cmds()
  assert_eq(seen.val, ["a", "b"])

  remove(node)
  let _ = assert_take_cmds()
  source.set("c")
  let _ = flush_cmds()
  assert_eq(seen.val, ["a", "b"])
}

test "ui-name without ui-react does not own inner effects" {
  reset_test_state()
  let source = cel("a")
  let seen : Ref[Array[String]] = Ref::new([])
  let box = comp(fn(attrs, children) {
    let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
    h("div", attrs, children)
  })
  let stop = test_scope(() => {
    let node = assert_realize(h(box, [
      ("ui-id", S("named:only")),
      ("ui-name", S("true"))
    ], []))
    let _ = assert_take_cmds()
    assert_eq(seen.val, ["a"])

    remove(node)
    let _ = assert_take_cmds()
  })

  source.set("b")
  let _ = flush_cmds()
  assert_eq(seen.val, ["a", "b"])

  stop()
  source.set("c")
  let _ = flush_cmds()
  assert_eq(seen.val, ["a", "b"])
}

test "h_map provides index getter and reruns on changes" {
  reset_test_state()
  let items = cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 14)
  assert_eq(builds.val, 2)
  assert_has_cmd(cmds, Text(any(), v("0:A")))
  assert_has_cmd(cmds, Text(any(), v("1:B")))

  items.set([("B", 0), ("C", 1)])
  let cmds2 = flush_cmds()
  assert_eq(builds.val, 3)
  assert_has_cmd(cmds2, Remove(any()))
  assert_eq(count_cmds(cmds2, Create(any(), v("li"), any())), 1)
}

test "h_map keeps duplicate items separate" {
  reset_test_state()
  let items = ["A", "A", "B"]
  let builds = Ref::new(0)
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map(items, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 19)
  assert_eq(builds.val, 3)
  assert_has_cmd(cmds, Text(any(), v("0:A")))
  assert_has_cmd(cmds, Text(any(), v("1:A")))
  assert_has_cmd(cmds, Text(any(), v("2:B")))
}

test "h_map watches source function dependencies" {
  reset_test_state()
  let items = cel([("A", 9)])
  let source_runs = Ref::new(0)
  let builds = Ref::new(0)
  let source = fn() {
    source_runs.val = source_runs.val + 1
    items.get()
  }
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(source, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 9)
  assert_eq(source_runs.val, 1)
  assert_eq(builds.val, 1)
  let _ = assert_cmd(cmds[6], Text(any(), v("9:A")))

  items.set([("B", 12)])
  let cmds2 = flush_cmds()
  assert_eq(source_runs.val, 2)
  assert_eq(builds.val, 2)
  let _ = assert_unordered_cmds(cmds2, [
    Remove(any()),
    Text(any(), v("12:B"))
  ])
}

test "h_map_dyn keeps explicit indexes" {
  reset_test_state()
  let items = cel([("A", 9), ("B", 10)])
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 14)
  assert_has_cmd(cmds, Text(any(), v("9:A")))
  assert_has_cmd(cmds, Text(any(), v("10:B")))
}

test "h_map removes only missing keyed item" {
  reset_ui()
  let items = cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  let initial = assert_take_cmds()
  assert_eq(builds.val, 2)
  let (a_li_id, _) = find_text_mount(initial, "0:A")
  let (b_li_id, _) = find_text_mount(initial, "1:B")

  items.set([("B", 0)])
  let cmds = flush_cmds()
  assert_eq(builds.val, 2)
  assert_has_cmd(cmds, Remove(v(a_li_id)))
  assert_no_cmd(cmds, Remove(v(b_li_id)))
  assert_no_cmd(cmds, Create(v(b_li_id), any(), any()))
}

test "h_map reorders kept keyed items without recreating them" {
  reset_ui()
  let items = cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  let initial = assert_take_cmds()
  assert_eq(builds.val, 2)
  let (a_li_id, _) = find_text_mount(initial, "0:A")
  let (b_li_id, _) = find_text_mount(initial, "1:B")

  items.set([("B", 0), ("A", 1)])
  let cmds = flush_cmds()
  assert_eq(builds.val, 2)
  assert_no_cmd(cmds, Remove(v(a_li_id)))
  assert_no_cmd(cmds, Remove(v(b_li_id)))
  assert_no_cmd(cmds, Create(v(a_li_id), any(), any()))
  assert_no_cmd(cmds, Create(v(b_li_id), any(), any()))
  assert_true(
    count_cmds(cmds, Append(any(), v(a_li_id))) +
    count_cmds(cmds, Append(any(), v(b_li_id))) +
    count_cmds(cmds, InsertBefore(any(), v(a_li_id), any())) +
    count_cmds(cmds, InsertBefore(any(), v(b_li_id), any())) +
    count_cmds(cmds, InsertAfter(any(), v(a_li_id), any())) +
    count_cmds(cmds, InsertAfter(any(), v(b_li_id), any())) > 0
  )
}

test "h_map root Dyn reorders kept keyed items without recreating them" {
  reset_ui()
  let items = cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        Dyn(fn() {
          h("li", [], [Str("\{i()}:\{x}")])
        })
      })
    ]))
    ()
  })
  let initial = assert_take_cmds()
  assert_eq(builds.val, 2)
  let (a_li_id, _) = find_text_mount(initial, "0:A")
  let (b_li_id, _) = find_text_mount(initial, "1:B")

  items.set([("B", 0), ("A", 1)])
  let cmds = flush_cmds()
  assert_eq(builds.val, 2)
  assert_no_cmd(cmds, Remove(v(a_li_id)))
  assert_no_cmd(cmds, Remove(v(b_li_id)))
  assert_no_cmd(cmds, Create(v(a_li_id), any(), any()))
  assert_no_cmd(cmds, Create(v(b_li_id), any(), any()))
}

test "h_map adds render only for new keyed item" {
  reset_ui()
  let items = cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  let _ = assert_take_cmds()
  assert_eq(builds.val, 2)

  items.set([("A", 0), ("B", 1), ("C", 2)])
  let cmds = flush_cmds()
  assert_eq(builds.val, 3)
  assert_eq(count_cmds(cmds, Create(any(), v("li"), any())), 1)
}

test "h_map stops removed item effects" {
  reset_ui()
  let items = cel([("A", 0), ("B", 1)])
  let source = cel("x")
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        h("li", [], [
          Str("\{i()}:\{x}:"),
          Dyn(fn() { Str(source.get()) })
        ])
      })
    ]))
    ()
  })
  let initial = assert_take_cmds()
  let (a_li_id, a_text_id) = find_text_mount(initial, "0:A:")

  items.set([("B", 0)])
  let _ = flush_cmds()
  source.set("y")
  let cmds = flush_cmds()
  assert_no_cmd(cmds, Create(v(a_li_id), any(), any()))
  assert_no_cmd(cmds, Remove(v(a_li_id)))
  assert_no_cmd(cmds, UpdateText(v(a_text_id), any()))
  assert_no_cmd(cmds, Text(v(a_text_id), any()))
}

test "h_map root Dyn stops removed item effects" {
  reset_ui()
  let items = cel([("A", 0), ("B", 1)])
  let source = cel("x")
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        Dyn(fn() {
          h("li", [], [
            Str("\{i()}:\{x}:"),
            Dyn(fn() { Str(source.get()) })
          ])
        })
      })
    ]))
    ()
  })
  let initial = assert_take_cmds()
  let (a_li_id, a_text_id) = find_text_mount(initial, "0:A:")

  items.set([("B", 0)])
  let _ = flush_cmds()
  source.set("y")
  let cmds = flush_cmds()
  assert_no_cmd(cmds, Create(v(a_li_id), any(), any()))
  assert_no_cmd(cmds, Remove(v(a_li_id)))
  assert_no_cmd(cmds, UpdateText(v(a_text_id), any()))
  assert_no_cmd(cmds, Text(v(a_text_id), any()))
}

test "h_map keeps listener registration stable for kept item" {
  reset_ui()
  let items = cel([("A", 0), ("B", 1)])
  let clicks = Ref::new(0)
  let seen_indexes: Ref[Array[Int]] = Ref::new([])
  let _ = test_scope(() => {
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
  })
  let initial = assert_take_cmds()
  let (a_button_id, _) = find_text_mount(initial, "0:A")

  items.set([("B", 0), ("A", 1), ("C", 2)])
  let cmds = flush_cmds()
  assert_eq(count_cmds(cmds, Listen(v(a_button_id), v("onclick"), any())), 0)

  click("item:A")
  assert_eq(clicks.val, 1)
  assert_eq(seen_indexes.val, [1])
}

test "h_map root Dyn keeps listener registration stable for kept item" {
  reset_ui()
  let items = cel([("A", 0), ("B", 1)])
  let clicks = Ref::new(0)
  let seen_indexes : Ref[Array[Int]] = Ref::new([])
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        Dyn(fn() {
          h("button", [
            ("ui-id", S("item:\{x}")),
            ("onclick", E(() => {
              clicks.val = clicks.val + 1
              seen_indexes.val.push(i())
              ignore(x)
            }))
          ], [Str("\{i()}:\{x}")])
        })
      })
    ]))
    ()
  })
  let initial = assert_take_cmds()
  let (a_button_id, _) = find_text_mount(initial, "0:A")

  items.set([("B", 0), ("A", 1), ("C", 2)])
  let cmds = flush_cmds()
  assert_eq(count_cmds(cmds, Listen(v(a_button_id), v("onclick"), any())), 0)

  click("item:A")
  assert_eq(clicks.val, 1)
  assert_eq(seen_indexes.val, [1])
}

test "h_map removes only one duplicate entry" {
  reset_ui()
  let items = cel([("A", 0), ("A", 1), ("B", 2)])
  let builds = Ref::new(0)
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  let initial = assert_take_cmds()
  assert_eq(builds.val, 3)
  let (a0_li_id, _) = find_text_mount(initial, "0:A")
  let (a1_li_id, _) = find_text_mount(initial, "1:A")
  let (b_li_id, _) = find_text_mount(initial, "2:B")

  items.set([("A", 0), ("B", 1)])
  let cmds = flush_cmds()
  assert_eq(builds.val, 3)
  assert_has_cmd(cmds, Remove(v(a1_li_id)))
  assert_no_cmd(cmds, Remove(v(a0_li_id)))
  assert_no_cmd(cmds, Remove(v(b_li_id)))
  assert_no_cmd(cmds, Create(v(a0_li_id), any(), any()))
  assert_no_cmd(cmds, Create(v(b_li_id), any(), any()))
}

test "h_map root Dyn removes only one duplicate entry" {
  reset_ui()
  let items = cel([("A", 0), ("A", 1), ("B", 2)])
  let builds = Ref::new(0)
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        Dyn(fn() {
          h("li", [], [Str("\{i()}:\{x}")])
        })
      })
    ]))
    ()
  })
  let initial = assert_take_cmds()
  assert_eq(builds.val, 3)
  let (a0_li_id, _) = find_text_mount(initial, "0:A")
  let (a1_li_id, _) = find_text_mount(initial, "1:A")
  let (b_li_id, _) = find_text_mount(initial, "2:B")

  items.set([("A", 0), ("B", 1)])
  let cmds = flush_cmds()
  assert_eq(builds.val, 3)
  assert_has_cmd(cmds, Remove(v(a1_li_id)))
  assert_no_cmd(cmds, Remove(v(a0_li_id)))
  assert_no_cmd(cmds, Remove(v(b_li_id)))
  assert_no_cmd(cmds, Create(v(a0_li_id), any(), any()))
  assert_no_cmd(cmds, Create(v(b_li_id), any(), any()))
}

test "svg namespace propagates through foreignObject" {
  reset_test_state()
  let _ = assert_realize(h("svg", [], [
    h("foreignObject", [], [
      h("span", [], [])
    ])
  ]))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 5)
  let _ = assert_cmd(cmds[0], Create(any(), v("svg"), v("http://www.w3.org/2000/svg")))
  let _ = assert_cmd(cmds[1], Create(any(), v("foreignObject"), v("http://www.w3.org/2000/svg")))
  let _ = assert_cmd(cmds[2], Create(any(), v("span"), v("http://www.w3.org/1999/xhtml")))
}

test "h handles dynamic attributes" {
  reset_test_state()
  let count = cel(0)
  let _ = test_scope(() => {
    let _ = assert_realize(h("div", [("data-count", D(() => count.get().to_string()))], []))
    ()
  })
  
  let cmds1 = assert_take_cmds()
  // Create, UpdateAttr (triggered by first effect run)
  assert_eq(cmds1.length(), 2)
  let _ = assert_cmd(cmds1[1], UpdateAttr(any(), v("data-count"), v("0")))

  count.set(1)
  let cmds2 = flush_cmds()
  assert_eq(cmds2.length(), 1)
  let _ = assert_cmd(cmds2[0], UpdateAttr(any(), v("data-count"), v("1")))
}

test "ui-id also emits derived class" {
  reset_test_state()
  let _ = assert_realize(h("div", [("ui-id", S("entry:main/button"))], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 3)
  let _ = assert_cmd(cmds[0], Create(v(1), v("div"), any()))
  let _ = assert_cmd(cmds[1], Attr(v(1), v("ui-id"), v("entry:main/button")))
  let _ = assert_cmd(cmds[2], Attr(v(1), v("class"), v("button")))
}

test "explicit class keeps derived ui class" {
  reset_test_state()
  let _ = assert_realize(h("div", [
    ("ui-id", S("entry:main/button")),
    ("class", S("card"))
  ], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 3)
  let _ = assert_cmd(cmds[2], Attr(v(1), v("class"), v("card button")))
}

test "style property emits style command" {
  reset_test_state()
  let _ = assert_realize(h("div", [("style:background-color", S("red"))], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 2)
  let _ = assert_cmd(cmds[0], Create(any(), v("div"), any()))
  let _ = assert_cmd(cmds[1], SetStyle(any(), v("background-color"), v("red")))
}

test "dynamic style property updates and removes" {
  reset_test_state()
  let color = cel("red")
  let _ = test_scope(() => {
    let _ = assert_realize(h("div", [("style:background-color", D(() => color.get()))], []))
    ()
  })
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 2)
  let _ = assert_cmd(cmds[1], SetStyle(any(), v("background-color"), v("red")))

  color.set("blue")
  let cmds2 = flush_cmds()
  assert_eq(cmds2.length(), 1)
  let _ = assert_cmd(cmds2[0], SetStyle(any(), v("background-color"), v("blue")))

  color.set("")
  let cmds3 = flush_cmds()
  assert_eq(cmds3.length(), 1)
  let _ = assert_cmd(cmds3[0], RemoveStyle(any(), v("background-color")))
}

test "css emits set update and remove" {
  reset_test_state()
  let theme = cel("red")
  let stop = test_scope(() => {
    let style_host = comp(fn(_attrs, _children) {
      css("theme", D(() => ".root { color: \{theme.get()}; }"))
      h("div", [], [])
    })
    let _ = assert_realize(h(style_host, [], []))
    ()
  })
  let cmds = assert_take_cmds()
  assert_has_cmd(cmds, SetCss(v("theme"), v(".theme .root{ color: red; }")))

  theme.set("blue")
  let cmds2 = flush_cmds()
  assert_has_cmd(cmds2, SetCss(v("theme"), v(".theme .root{ color: blue; }")))

  stop()
  let cmds3 = assert_take_cmds()
  assert_eq(cmds3.length(), 1)
  let _ = assert_cmd(cmds3[0], RemoveCss(v("theme")))
}

test "Str and Dyn" {
  reset_test_state()
  let val = cel("a")
  let _ = test_scope(() => {
    let _ = assert_realize(h("div", [], [
      Str("hello"),
      Dyn(fn() { Str(val.get()) })
    ]))
    ()
  })
  
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 10)

  val.set("b")
  let cmds2 = flush_cmds()
  assert_eq(cmds2.length(), 4)
  assert_has_cmd(cmds2, Remove(any()))
}

test "events and callback triggering" {
  reset_test_state()
  let clicked = Ref::new(false)
  let node = assert_realize(h("button", [
    ("ui-id", S("button:main")),
    ("onclick", E(() => { clicked.val = true }))
  ], []))
  let cmds = assert_take_cmds()
  
  assert_eq(cmds.length(), 4)
  let _ = assert_cmd(cmds[1], Attr(v(node.id), v("ui-id"), v("button:main")))
  let _ = assert_cmd(cmds[2], Listen(v(node.id), v("onclick"), v("button:main")))
  let _ = assert_cmd(cmds[3], Attr(v(node.id), v("class"), v("button-main")))

  click("button:main")
  assert_eq(clicked.val, true)
}

test "css prefixes selectors inside media" {
  reset_test_state()
  let stop = test_scope(() => {
    let style_host = comp(fn(_attrs, _children) {
      css("host", S("@media (max-width: 600px) { .root { color: red; } }"))
      h("div", [], [])
    })
    let _ = assert_realize(h(style_host, [], []))
    ()
  })
  let cmds = assert_take_cmds()
  assert_has_cmd(cmds, SetCss(v("host"), v("@media (max-width: 600px) {.host .root{ color: red; } }")))
  stop()
  let _ = assert_take_cmds()
}

test "remove emits cmd" {
  reset_test_state()
  let node = assert_realize(h("div", [], []))
  let _ = assert_take_cmds()
  let _ = test_scope(() => {
    let _ = assert_realize(h("div", [], [Dyn(fn() {
      remove(node)
      Null
    })]))
    ()
  })
  let cmds = assert_take_cmds()
  assert_has_cmd(cmds, Remove(v(node.id)))
}

test "remove cleans subtree callbacks" {
  reset_test_state()
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
  reset_test_state()
  let done = cel(false)
  let clicks = Ref::new(0)
  let _ = test_scope(() => {
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
  })
  let _ = assert_take_cmds()

  click("toggle:item")
  let first = assert_take_cmds()
  assert_has_cmd(first, Remove(any()))

  click("toggle:item")
  let second = assert_take_cmds()
  assert_has_cmd(second, Remove(any()))
  assert_eq(clicks.val, 2)
}

test "remove stops dynamic updates for subtree" {
  reset_test_state()
  let source = cel("a")
  let stop = test_scope(() => {
    let parent = assert_realize(h("div", [], [Dyn(fn() { Str(source.get()) })]))
    remove(parent)
  })
  let _ = assert_take_cmds()

  source.set("b")
  let cmds = flush_cmds()
  assert_eq(cmds.length(), 0)
  stop()
}

test "Dyn handles nested arrays and components" {
  reset_test_state()
  let list = cel(["A", "B"])
  let _ = test_scope(() => {
    let _ = assert_realize(h("ul", [], [
      Dyn(fn() { 
        Arr(list.get().map(fn(x) { h("li", [], [Str(x)]) }))
      })
    ]))
    ()
  })
  
  let cmds = assert_take_cmds()
  // Create(ul), Create(anchor), Text(anchor, ""), Append(ul, anchor), 
  // Initial run of Dyn:
  // Create(liA), Create(textA), Text(textA, "A"), Append(liA, textA), InsertBefore(ul, liA, anchor)
  // Create(liB), Create(textB), Text(textB, "B"), Append(liB, textB), InsertBefore(ul, liB, anchor)
  assert_eq(cmds.length(), 14)

  list.set(["C"])
  let cmds2 = flush_cmds()
  let _ = assert_unordered_cmds(cmds2, [
    Remove(any()),
    Text(any(), v("C"))
  ])
  assert_true(count_cmds(cmds2, InsertBefore(any(), any(), any())) > 0)
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

test "InsertAfter emits correct json" {
  let cmd = DomCmd::InsertAfter(3, 4, 5)
  assert_cmd_json(cmd, "[16,3,4,5]")
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
  reset_test_state()
  let received = Ref::new(EventData::default())
  let node = assert_realize(h("div", [
    ("ui-id", S("key-target")),
    ("onkeydown", EK(fn(ev) { received.val = ev }))
  ], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 4)
  let _ = assert_cmd(cmds[1], Attr(v(node.id), v("ui-id"), v("key-target")))
  let _ = assert_cmd(cmds[2], Listen(v(node.id), v("onkeydown"), v("key-target")))
  let _ = assert_cmd(cmds[3], Attr(v(node.id), v("class"), v("key-target")))
  let ev = EventData::from_json("a|KeyA|0|0|0|0")
  trigger_ui_ev("key-target", "onkeydown", ev)
  assert_eq(received.val.key, "a")
  assert_eq(received.val.code, "KeyA")
}

test "host command helpers emit correct cmds" {
  reset_test_state()
  let _ = test_scope(() => {
    let _ = assert_realize(h("div", [], [Dyn(fn() {
      focus_node(10)
      blur_node(11)
      scroll_into_view(12)
      Null
    })]))
    ()
  })
  let cmds = assert_take_cmds()
  let _ = assert_ordered_cmds(cmds, [
    HostCmd(v(10), v("focus")),
    HostCmd(v(11), v("blur")),
    HostCmd(v(12), v("scrollIntoView"))
  ])
}

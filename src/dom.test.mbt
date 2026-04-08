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

test "react:scope null uses empty text host" {
  reset_test_state()
  let source = cel("a")
  let seen : Ref[Array[String]] = Ref::new([])
  let box = comp(fn(_attrs, _children) {
    let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
    Null
  })
  let node = assert_realize(h(box, [("react:scope", S("true"))], []))
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
    count_cmds(cmds, InsertBefore(any(), v(b_li_id), any())) > 0
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

test "h_map does not move kept keyed items already in place" {
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

  items.set([("A", 0), ("B", 1)])
  let cmds = flush_cmds()
  assert_eq(builds.val, 2)
  assert_eq(count_cmds(cmds, Append(any(), any())), 0)
  assert_eq(count_cmds(cmds, InsertBefore(any(), any(), any())), 0)
}

test "h_map root Dyn does not move kept keyed items already in place" {
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
  let _ = assert_take_cmds()
  assert_eq(builds.val, 2)

  items.set([("A", 0), ("B", 1)])
  let cmds = flush_cmds()
  assert_eq(builds.val, 2)
  assert_eq(count_cmds(cmds, Append(any(), any())), 0)
  assert_eq(count_cmds(cmds, InsertBefore(any(), any(), any())), 0)
}

test "h_map delete only does not move kept keyed items across removed gap" {
  reset_ui()
  let items = cel([("A", 0), ("B", 1), ("C", 2), ("D", 3)])
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
  assert_eq(builds.val, 4)
  let (a_li_id, _) = find_text_mount(initial, "0:A")
  let (d_li_id, _) = find_text_mount(initial, "3:D")

  items.set([("A", 0), ("D", 1)])
  let cmds = flush_cmds()
  assert_eq(builds.val, 4)
  assert_eq(
    count_cmds(cmds, Append(any(), v(a_li_id))) +
    count_cmds(cmds, Append(any(), v(d_li_id))) +
    count_cmds(cmds, InsertBefore(any(), v(a_li_id), any())) +
    count_cmds(cmds, InsertBefore(any(), v(d_li_id), any())),
    0,
  )
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
  assert_no_cmd(cmds, Text(v(a_text_id), any()))
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
  assert_no_cmd(cmds, Text(v(a_text_id), any()))
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
          ("ui-id", S("item-\{x}")),
          ("onclick", E(fn(_) {
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
  assert_eq(count_cmds(cmds, Listen(v(a_button_id), v("onclick"))), 0)

  trigger_node(a_button_id, "onclick")
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
            ("ui-id", S("item-\{x}")),
            ("onclick", E(fn(_) {
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
  assert_eq(count_cmds(cmds, Listen(v(a_button_id), v("onclick"))), 0)

  trigger_node(a_button_id, "onclick")
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
  // Create, Attr (triggered by first effect run)
  assert_eq(cmds1.length(), 2)
  let _ = assert_cmd(cmds1[1], Attr(any(), v("data-count"), v("0")))

  count.set(1)
  let cmds2 = flush_cmds()
  assert_eq(cmds2.length(), 1)
  let _ = assert_cmd(cmds2[0], Attr(any(), v("data-count"), v("1")))
}

test "ui-id also emits derived class" {
  reset_test_state()
  let _ = assert_realize(h("div", [("ui-id", S("entry-main-button"))], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 3)
  let _ = assert_cmd(cmds[0], Create(v(1), v("div"), any()))
  let _ = assert_cmd(cmds[1], Attr(v(1), v("ui-id"), v("entry-main-button")))
  let _ = assert_cmd(cmds[2], Attr(v(1), v("class"), v("entry-main-button")))
}

test "explicit class keeps derived ui class" {
  reset_test_state()
  let _ = assert_realize(h("div", [
    ("ui-id", S("entry-main-button")),
    ("class", S("card"))
  ], []))
  let cmds = assert_take_cmds()
  assert_eq(cmds.length(), 3)
  assert_has_cmd(cmds, Attr(v(1), v("ui-id"), v("entry-main-button")))
  assert_has_cmd(cmds, Attr(v(1), v("class"), v("card entry-main-button")))
}

test "panic ui-id rejects slash" {
  reset_test_state()
  ignore(assert_realize(h("div", [("ui-id", S("bad/id"))], [])))
}

test "panic ui-id rejects colon" {
  reset_test_state()
  ignore(assert_realize(h("div", [("ui-id", S("bad:id"))], [])))
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
  let theme = css("theme", S(".root { color: red; }"))
  let stop = test_scope(() => {
    let _ = mount_test_root(h("div", [], []))
    ()
  })
  let cmds = assert_take_cmds()
  assert_has_cmd(cmds, SetCss(any(), v(".theme .root{ color: red; }\n")))

  theme.reset(".root { color: blue; }")
  let cmds2 = assert_take_cmds()
  assert_has_cmd(cmds2, SetCss(any(), v(".theme .root{ color: blue; }\n")))

  stop()
  let cmds3 = assert_take_cmds()
  assert_no_cmd(cmds3, RemoveCss(any()))
}

test "css prefixes selectors inside media" {
  reset_test_state()
  let theme = css("host-media", S("@media (max-width: 600px) { .root { color: red; } }"))
  ignore(theme)
  let stop = test_scope(() => {
    let _ = mount_test_root(h("div", [], []))
    ()
  })
  let cmds = assert_take_cmds()
  let mut found = false
  for cmd in cmds {
    match cmd {
      SetCss(_, text) => if text.contains(".host-media .root{ color: red; }") { found = true }
      _ => ()
    }
  }
  assert_true(found)
  stop()
  let _ = assert_take_cmds()
}

test "css prefixes multiple selectors inside media" {
  reset_test_state()
  let theme = css(
    "host-media-many",
    S("@media (max-width: 600px) { .root, .item { color: red; } }"),
  )
  ignore(theme)
  let stop = test_scope(() => {
    let _ = mount_test_root(h("div", [], []))
    ()
  })
  let cmds = assert_take_cmds()
  let mut found = false
  for cmd in cmds {
    match cmd {
      SetCss(_, text) =>
        if text.contains(".host-media-many .root, .host-media-many .item{ color: red; }") {
          found = true
        }
      _ => ()
    }
  }
  assert_true(found)
  stop()
  let _ = assert_take_cmds()
}

test "css keeps nested selector commas intact" {
  reset_test_state()
  let theme = css("host-is", S(":is(.a, .b) { color: red; }"))
  ignore(theme)
  let stop = test_scope(() => {
    let _ = mount_test_root(h("div", [], []))
    ()
  })
  let cmds = assert_take_cmds()
  assert_has_cmd(cmds, SetCss(any(), v(".host-is :is(.a, .b){ color: red; }\n")))
  stop()
  let _ = assert_take_cmds()
}

test "css prefixes selector list with nested selector commas" {
  reset_test_state()
  let theme = css("host-is-many", S(":is(.a, .b), .item { color: red; }"))
  ignore(theme)
  let stop = test_scope(() => {
    let _ = mount_test_root(h("div", [], []))
    ()
  })
  let cmds = assert_take_cmds()
  assert_has_cmd(
    cmds,
    SetCss(any(), v(".host-is-many :is(.a, .b), .host-is-many .item{ color: red; }\n")),
  )
  stop()
  let _ = assert_take_cmds()
}

test "css prefixes empty selector inside media to scope root" {
  reset_test_state()
  let theme = css("host-media-root", S("@media (max-width: 600px) { { color: red; } }"))
  ignore(theme)
  let stop = test_scope(() => {
    let _ = mount_test_root(h("div", [], []))
    ()
  })
  let cmds = assert_take_cmds()
  let mut found = false
  for cmd in cmds {
    match cmd {
      SetCss(_, text) => if text.contains(".host-media-root{ color: red; }") { found = true }
      _ => ()
    }
  }
  assert_true(found)
  stop()
  let _ = assert_take_cmds()
}

test "css prefixes selectors inside nested supports under media" {
  reset_test_state()
  let theme = css(
    "host-media-supports",
    S("@media (max-width: 600px) { @supports (display: grid) { .root, .item { color: red; } } }"),
  )
  ignore(theme)
  let stop = test_scope(() => {
    let _ = mount_test_root(h("div", [], []))
    ()
  })
  let cmds = assert_take_cmds()
  let mut found = false
  for cmd in cmds {
    match cmd {
      SetCss(_, text) =>
        if text.contains("@supports (display: grid)") &&
          text.contains(".host-media-supports .root, .host-media-supports .item{ color: red; }") {
          found = true
        }
      _ => ()
    }
  }
  assert_true(found)
  stop()
  let _ = assert_take_cmds()
}

test "css empty selector targets scope root" {
  reset_test_state()
  let theme = css("host-root", S("{ color: red; }"))
  ignore(theme)
  let stop = test_scope(() => {
    let _ = mount_test_root(h("div", [], []))
    ()
  })
  let cmds = assert_take_cmds()
  assert_has_cmd(cmds, SetCss(any(), v(".host-root{ color: red; }\n")))
  stop()
  let _ = assert_take_cmds()
}

test "css creates isolated stylesheet ids" {
  reset_test_state()
  let first_sheet = css("theme-a", S(".root { color: red; }"))
  let second_sheet = css("theme-a", S(".root { color: blue; }"))
  let stop = test_scope(() => {
    ignore(first_sheet)
    ignore(second_sheet)
    let _ = mount_test_root(h("div", [], []))
    ()
  })
  let cmds = assert_take_cmds()
  let first = find_cmd(cmds, SetCss(s("css1"), v(".theme-a .root{ color: red; }\n")))
  let second = find_cmd(cmds, SetCss(s("css2"), v(".theme-a .root{ color: blue; }\n")))
  assert_true(get_str(first, "css1") != get_str(second, "css2"))
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


test "to_json gives compact array format" {
  let cmd = DomCmd::Text(1, "\"")
  assert_cmd_json(cmd, cmd_json(dom_cmd_text, "1,\"\\\"\""))
}

test "SetStyle emits correct json" {
  let cmd = DomCmd::SetStyle(5, "color", "red")
  assert_cmd_json(cmd, cmd_json(dom_cmd_set_style, "5,\"color\",\"red\""))
}

test "RemoveStyle emits correct json" {
  let cmd = DomCmd::RemoveStyle(5, "color")
  assert_cmd_json(cmd, cmd_json(dom_cmd_remove_style, "5,\"color\""))
}

test "RemoveAttr emits correct json" {
  let cmd = DomCmd::RemoveAttr(5, "class")
  assert_cmd_json(cmd, cmd_json(dom_cmd_remove_attr, "5,\"class\""))
}

test "SetCss emits correct json" {
  let cmd = DomCmd::SetCss("theme", ".theme .root{ color: red; }")
  assert_cmd_json(cmd, cmd_json(dom_cmd_set_css, "\"theme\",\".theme .root{ color: red; }\""))
}

test "RemoveCss emits correct json" {
  let cmd = DomCmd::RemoveCss("theme")
  assert_cmd_json(cmd, cmd_json(dom_cmd_remove_css, "\"theme\""))
}

test "EventData from_json parses pipe format" {
  let ev = EventData::from_json("Enter|Enter|1|0|0|0")
  assert_eq(ev.key, "Enter")
  assert_eq(ev.code, "Enter")
  assert_eq(ev.ctrl, true)
  assert_eq(ev.shift, false)
  assert_eq(ev.alt, false)
  assert_eq(ev.meta, false)
  assert_eq(ev.client_x, 0)
  assert_eq(ev.client_y, 0)
  assert_eq(ev.button, 0)
  assert_eq(ev.buttons, 0)
  assert_eq(ev.pointer_id, 0)
}

test "EventData from_json parses pointer payload" {
  let ev = EventData::from_json("||0|0|0|0|120|240|0|1|7")
  assert_eq(ev.client_x, 120)
  assert_eq(ev.client_y, 240)
  assert_eq(ev.button, 0)
  assert_eq(ev.buttons, 1)
  assert_eq(ev.pointer_id, 7)
}

test "init_bridge emits json values without string roundtrip" {
  reset_test_state()
  let state = new_dom_state()
  let seen : Ref[Array[Json]] = Ref::new([])
  init_bridge(state, fn(batch) { seen.val = batch })
  emit(state, Text(1, "ok"))
  flush() catch { _ => panic() }
  assert_eq(seen.val.length(), 1)
  assert_eq(seen.val[0].stringify(), cmd_json(dom_cmd_text, "1,\"ok\""))
}

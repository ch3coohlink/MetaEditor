test "mock dom ui-name query reaches nested local node" {
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
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(box, [
      ("ui-id", S("panel")),
      ("ui-name", S("true"))
    ], [Str("ok")]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "panel/toggle"))
  assert_eq(clicks.val, 1)
}

test "mock dom ui-list query uses child index" {
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
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(box, [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "todos/0/toggle"))
  ignore(mock_event(browser, "click", "todos/1/toggle"))
  assert_eq(clicks.val, 2)
}

test "mock dom h_map root Dyn query follows current visible nodes after shape change" {
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
      }, ui_id=Some("items"))
    ])
  })
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(list, [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "todos/0/toggle"))
  ignore(mock_event(browser, "click", "todos/1/toggle"))
  assert_eq(clicks.val, ["closed:A", "closed:B"])

  expanded.set(true)
  apply_mock_cmds(browser, flush_cmds())
  ignore(mock_event(browser, "click", "todos/0/toggle"))
  ignore(mock_event(browser, "click", "todos/1/toggle"))
  assert_eq(clicks.val, ["closed:A", "closed:B", "open:A", "open:B"])
}

test "mock dom ui-list wrapper Dyn query follows shape change with sibling" {
  reset_test_state()
  let expanded = cel(false)
  let clicks: Ref[Array[String]] = Ref::new([])
  let item = fn(label: String) {
    h("div", [], [
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
    ])
  }
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("div", [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], [
      item("A"),
      item("B"),
      h("div", [("ui-id", S("footer"))], [Str("tail")])
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "todos/0/toggle"))
  ignore(mock_event(browser, "click", "todos/1/toggle"))
  assert_eq(clicks.val, ["closed:A", "closed:B"])

  expanded.set(true)
  apply_mock_cmds(browser, flush_cmds())
  ignore(mock_event(browser, "click", "todos/0/toggle"))
  ignore(mock_event(browser, "click", "todos/1/toggle"))
  assert_eq(clicks.val, ["closed:A", "closed:B", "open:A", "open:B"])
}

test "mock dom ui-list single wrapper keeps live scope after Dyn shape change" {
  reset_test_state()
  let expanded = cel(false)
  let clicks: Ref[Array[String]] = Ref::new([])
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("div", [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], [
      h("div", [], [
        Dyn(fn() {
          if expanded.get() {
            Arr([
              h("span", [("ui-id", S("label"))], [Str("open:A")]),
              h("button", [
                ("ui-id", S("toggle")),
                ("onclick", E(() => { clicks.val.push("open:A") }))
              ], [Str("A")])
            ])
          } else {
            h("button", [
              ("ui-id", S("toggle")),
              ("onclick", E(() => { clicks.val.push("closed:A") }))
            ], [Str("A")])
          }
        })
      ])
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "todos/0/toggle"))
  assert_eq(clicks.val, ["closed:A"])

  expanded.set(true)
  apply_mock_cmds(browser, flush_cmds())
  ignore(mock_event(browser, "click", "todos/0/toggle"))
  assert_eq(clicks.val, ["closed:A", "open:A"])
}

test "mock dom ui-list item root ui-id keeps inner Dyn names live" {
  reset_test_state()
  let expanded = cel(false)
  let clicks: Ref[Array[String]] = Ref::new([])
  let browser = new_mock_browser()
  let item = fn(label: String) {
    h("div", [("ui-id", S("item"))], [
      Dyn(fn() {
        if expanded.get() {
          Arr([
            h("span", [
              ("ui-id", S("label")),
              ("onclick", E(() => { clicks.val.push("label:\{label}") }))
            ], [Str("open:\{label}")]),
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
    ])
  }
  let _ = test_scope(() => {
    let _ = mount_test_root(h("div", [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], [
      item("A"),
      item("B")
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "todos/0/toggle"))
  ignore(mock_event(browser, "click", "todos/1/toggle"))
  assert_eq(clicks.val, ["closed:A", "closed:B"])

  expanded.set(true)
  apply_mock_cmds(browser, flush_cmds())
  ignore(mock_event(browser, "click", "todos/0/label"))
  ignore(mock_event(browser, "click", "todos/1/toggle"))
  assert_eq(clicks.val, ["closed:A", "closed:B", "label:A", "open:B"])
}

test "mock dom ui-name wrapper query stays live after prior lookup and Dyn shape change" {
  reset_test_state()
  let expanded = cel(false)
  let clicks: Ref[Array[String]] = Ref::new([])
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("div", [
      ("ui-id", S("panel")),
      ("ui-name", S("true"))
    ], [
      h("div", [], [
        h("div", [], [
          Dyn(fn() {
            if expanded.get() {
              Arr([
                h("span", [
                  ("ui-id", S("label")),
                  ("onclick", E(() => { clicks.val.push("label") }))
                ], [Str("open")]),
                h("button", [
                  ("ui-id", S("toggle")),
                  ("onclick", E(() => { clicks.val.push("open") }))
                ], [Str("toggle")])
              ])
            } else {
              h("button", [
                ("ui-id", S("toggle")),
                ("onclick", E(() => { clicks.val.push("closed") }))
              ], [Str("toggle")])
            }
          })
        ])
      ])
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "panel/toggle"))
  assert_eq(clicks.val, ["closed"])

  expanded.set(true)
  apply_mock_cmds(browser, flush_cmds())
  ignore(mock_event(browser, "click", "panel/label"))
  ignore(mock_event(browser, "click", "panel/toggle"))
  assert_eq(clicks.val, ["closed", "label", "open"])
}

test "mock dom ui-name can name component root" {
  reset_test_state()
  let root_clicked = Ref::new(0)
  let label_clicked = Ref::new(0)
  let box = comp(fn(attrs, children) {
    h("button", attrs, [
      h("span", [
        ("ui-id", S("label")),
        ("onclick", E(() => { label_clicked.val = label_clicked.val + 1 }))
      ], children)
    ])
  })
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(box, [
      ("ui-id", S("scoped:root")),
      ("ui-name", S("true")),
      ("onclick", E(() => { root_clicked.val = root_clicked.val + 1 }))
    ], [Str("ok")]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "scoped:root/label"))
  ignore(mock_event(browser, "click", "scoped:root"))
  assert_eq(label_clicked.val, 1)
  assert_eq(root_clicked.val, 1)
  assert_eq(mock_text(browser, "scoped:root"), "ok")
}

test "mock dom ui-name can name element root" {
  reset_test_state()
  let root_clicked = Ref::new(0)
  let label_clicked = Ref::new(0)
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("button", [
      ("ui-id", S("scoped:attr")),
      ("ui-name", S("true")),
      ("onclick", E(() => { root_clicked.val = root_clicked.val + 1 }))
    ], [
      h("span", [
        ("ui-id", S("label")),
        ("onclick", E(() => { label_clicked.val = label_clicked.val + 1 }))
      ], [Str("ok")])
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "scoped:attr/label"))
  ignore(mock_event(browser, "click", "scoped:attr"))
  assert_eq(label_clicked.val, 1)
  assert_eq(root_clicked.val, 1)
}

test "mock dom ui-name query stops at nested scope boundary" {
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
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(outer, [
      ("ui-id", S("outer")),
      ("ui-name", S("true"))
    ], [
      h(inner, [
        ("ui-id", S("inner")),
        ("ui-name", S("true"))
      ], [])
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "outer/toggle"))
  ignore(mock_event(browser, "click", "outer/inner/toggle"))
  assert_eq(outer_clicks.val, 1)
  assert_eq(inner_clicks.val, 1)
}

test "mock dom h_map items expose local names for list query" {
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
      }, ui_id=Some("items"))
    ])
  })
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(list, [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "todos/0/toggle"))
  ignore(mock_event(browser, "click", "todos/1/toggle"))
  assert_eq(clicks.val, 2)
}

test "mock dom h_map root Dyn items expose local names for list query" {
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
      }, ui_id=Some("items"))
    ])
  })
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(list, [
      ("ui-id", S("todos")),
      ("ui-list", S("true"))
    ], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "todos/0/toggle"))
  ignore(mock_event(browser, "click", "todos/1/toggle"))
  assert_eq(clicks.val, 2)
}

test "mock dom unnamed h_map does not expose indexed query" {
  reset_test_state()
  let clicks = Ref::new(0)
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("div", [("ui-id", S("root"))], [
      h_map(["A", "B"], fn(label, _i) {
        h("button", [
          ("ui-id", S("toggle")),
          ("onclick", E(() => { clicks.val = clicks.val + 1 }))
        ], [Str(label)])
      })
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "root/0/toggle"))
  assert_eq(clicks.val, 0)
}

test "mock dom named h_map exposes indexed query" {
  reset_test_state()
  let clicks = Ref::new(0)
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("div", [("ui-id", S("root"))], [
      h_map(["A", "B"], fn(label, _i) {
        h("button", [
          ("ui-id", S("toggle")),
          ("onclick", E(() => { clicks.val = clicks.val + 1 }))
        ], [Str(label)])
      }, ui_id=Some("todos"))
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "todos/0/toggle"))
  ignore(mock_event(browser, "click", "todos/1/toggle"))
  assert_eq(clicks.val, 2)
}

test "mock dom events and callback triggering" {
  reset_test_state()
  let clicked = Ref::new(false)
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("button", [
      ("ui-id", S("button:main")),
      ("onclick", E(() => { clicked.val = true }))
    ], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  ignore(mock_event(browser, "click", "button:main"))
  assert_eq(clicked.val, true)
}

test "mock dom remove cleans subtree callbacks" {
  reset_test_state()
  let child_clicked = Ref::new(0)
  let browser = new_mock_browser()
  let parent = mount_test_root(h("div", [], [
    h("button", [
      ("ui-id", S("child:button")),
      ("onclick", E(() => child_clicked.val = child_clicked.val + 1))
    ], [])
  ]))
  apply_mock_cmds(browser, assert_take_cmds())

  remove(parent)
  apply_mock_cmds(browser, assert_take_cmds())
  ignore(mock_event(browser, "click", "child:button"))
  assert_eq(child_clicked.val, 0)
}

test "mock dom same ui-id keeps event handler after dyn rerender" {
  reset_test_state()
  let done = cel(false)
  let clicks = Ref::new(0)
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("div", [], [
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
  apply_mock_cmds(browser, assert_take_cmds())

  assert_eq(mock_text(browser, "toggle:item"), "todo")
  ignore(mock_event(browser, "click", "toggle:item"))
  assert_eq(mock_text(browser, "toggle:item"), "done")
  ignore(mock_event(browser, "click", "toggle:item"))
  assert_eq(mock_text(browser, "toggle:item"), "todo")
  assert_eq(clicks.val, 2)
}

test "mock dom Dyn handles nested arrays and components" {
  reset_test_state()
  let list = cel(["A", "B"])
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("ul", [
      ("ui-id", S("list"))
    ], [
      Dyn(fn() {
        Arr(list.get().map(fn(x) { h("li", [], [Str(x)]) }))
      })
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  assert_eq(mock_text(browser, "list"), "AB")
  list.set(["C"])
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(mock_text(browser, "list"), "C")
}

test "mock dom EK callback receives event data" {
  reset_test_state()
  let received = Ref::new(EventData::default())
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("div", [
      ("ui-id", S("key-target")),
      ("onkeydown", EK(fn(ev) { received.val = ev }))
    ], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  let ev = EventData::from_json("a|KeyA|0|0|0|0")
  ignore(mock_event(browser, "keydown", "key-target", ev=Some(ev)))
  assert_eq(received.val.key, "a")
  assert_eq(received.val.code, "KeyA")
}

test "mock dom EK callback receives pointer data" {
  reset_test_state()
  let received = Ref::new(EventData::default())
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("div", [
      ("ui-id", S("pointer-target")),
      ("onpointermove", EK(fn(ev) { received.val = ev }))
    ], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())

  let ev = EventData::from_json("||0|0|0|0|12|34|0|1|9")
  ignore(mock_event(browser, "onpointermove", "pointer-target", ev=Some(ev)))
  assert_eq(received.val.client_x, 12)
  assert_eq(received.val.client_y, 34)
  assert_eq(received.val.button, 0)
  assert_eq(received.val.buttons, 1)
  assert_eq(received.val.pointer_id, 9)
}

test "mock dom ui-name keeps explicit ui-id as root id" {
  reset_test_state()
  let clicked = Ref::new(false)
  let box = comp(fn(attrs, children) { h("button", attrs, children) })
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h(box, [
      ("ui-id", S("plain:root")),
      ("ui-name", S("true")),
      ("onclick", E(() => { clicked.val = true }))
    ], []))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())
  assert_eq(mock_exists(browser, "plain:root"), true)
  ignore(mock_event(browser, "click", "plain:root"))
  assert_eq(clicked.val, true)
}

test "mock dom ui-react component stops inner effects on remove" {
  reset_test_state()
  let source = cel("a")
  let seen: Ref[Array[String]] = Ref::new([])
  let box = comp(fn(attrs, children) {
    let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
    h("div", attrs, children)
  })
  let browser = new_mock_browser()
  let parent: Ref[VNode?] = Ref::new(None)
  let _ = test_scope(() => {
    parent.val = Some(mount_test_root(h("section", [], [
      h(box, [("ui-react", S("true"))], [])
    ])))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())
  assert_eq(seen.val, ["a"])

  source.set("b")
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(seen.val, ["a", "b"])

  match parent.val {
    Some(node) => remove(node.children[0])
    None => panic()
  }
  apply_mock_cmds(browser, assert_take_cmds())
  source.set("c")
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(seen.val, ["a", "b"])
}

test "mock dom outer ui-react remove stops nested scopes too" {
  reset_test_state()
  let source = cel("a")
  let outer_seen: Ref[Array[String]] = Ref::new([])
  let inner_seen: Ref[Array[String]] = Ref::new([])
  let inner = comp(fn(attrs, children) {
    let _ = effect(fn() { inner_seen.val.push(source.get()) }) catch { _ => panic() }
    h("span", attrs, children)
  })
  let outer = comp(fn(attrs, children) {
    let _ = effect(fn() { outer_seen.val.push(source.get()) }) catch { _ => panic() }
    h("div", attrs, children)
  })
  let browser = new_mock_browser()
  let parent: Ref[VNode?] = Ref::new(None)
  let _ = test_scope(() => {
    parent.val = Some(mount_test_root(h("section", [], [
      h(outer, [("ui-react", S("true"))], [
        h(inner, [("ui-react", S("true"))], [])
      ])
    ])))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())
  assert_eq(outer_seen.val, ["a"])
  assert_eq(inner_seen.val, ["a"])

  source.set("b")
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(outer_seen.val, ["a", "b"])
  assert_eq(inner_seen.val, ["a", "b"])

  match parent.val {
    Some(node) => remove(node.children[0])
    None => panic()
  }
  apply_mock_cmds(browser, assert_take_cmds())
  source.set("c")
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(outer_seen.val, ["a", "b"])
  assert_eq(inner_seen.val, ["a", "b"])
}

test "mock dom ui-name without ui-react does not own inner effects" {
  reset_test_state()
  let source = cel("a")
  let seen: Ref[Array[String]] = Ref::new([])
  let box = comp(fn(attrs, children) {
    let _ = effect(fn() { seen.val.push(source.get()) }) catch { _ => panic() }
    h("div", attrs, children)
  })
  let stop = test_scope(() => {
    let _ = mount_test_root(h(box, [
      ("ui-id", S("named:only")),
      ("ui-name", S("true"))
    ], []))
    ()
  })
  let browser = new_mock_browser()
  apply_mock_cmds(browser, assert_take_cmds())
  assert_eq(seen.val, ["a"])

  source.set("b")
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(seen.val, ["a", "b"])

  stop()
  source.set("c")
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(seen.val, ["a", "b"])
}

test "mock dom Str and Dyn updates text" {
  reset_test_state()
  let val = cel("a")
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("div", [
      ("ui-id", S("sd"))
    ], [
      Str("hello"),
      Dyn(fn() { Str(val.get()) })
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())
  assert_eq(mock_text(browser, "sd"), "helloa")

  val.set("b")
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(mock_text(browser, "sd"), "hellob")
}

test "mock dom remove stops dynamic updates for subtree" {
  reset_test_state()
  let source = cel("a")
  let stop = test_scope(() => {
    let parent = mount_test_root(h("div", [], [Dyn(fn() { Str(source.get()) })]))
    remove(parent)
    ()
  })
  let browser = new_mock_browser()
  apply_mock_cmds(browser, assert_take_cmds())

  source.set("b")
  let cmds = flush_cmds()
  apply_mock_cmds(browser, cmds)
  assert_eq(cmds.length(), 0)
  stop()
}

test "mock dom h_map provides index getter and reruns on changes" {
  reset_test_state()
  let items = cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("ul", [
      ("ui-id", S("list"))
    ], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())
  assert_eq(builds.val, 2)
  assert_eq(mock_text(browser, "list"), "0:A1:B")

  items.set([("B", 0), ("C", 1)])
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(builds.val, 3)
  assert_eq(mock_text(browser, "list"), "1:B1:C")
}

test "mock dom h_map keeps duplicate items separate" {
  reset_test_state()
  let items = ["A", "A", "B"]
  let builds = Ref::new(0)
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("ul", [
      ("ui-id", S("list"))
    ], [
      h_map(items, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())
  assert_eq(builds.val, 3)
  assert_eq(mock_text(browser, "list"), "0:A1:A2:B")
}

test "mock dom h_map watches source function dependencies" {
  reset_test_state()
  let items = cel([("A", 9)])
  let source_runs = Ref::new(0)
  let builds = Ref::new(0)
  let browser = new_mock_browser()
  let source = fn() {
    source_runs.val = source_runs.val + 1
    items.get()
  }
  let _ = test_scope(() => {
    let _ = mount_test_root(h("ul", [
      ("ui-id", S("list"))
    ], [
      h_map_dyn(source, fn(x, i) {
        builds.val = builds.val + 1
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())
  assert_eq(source_runs.val, 1)
  assert_eq(builds.val, 1)
  assert_eq(mock_text(browser, "list"), "9:A")

  items.set([("B", 12)])
  apply_mock_cmds(browser, flush_cmds())
  assert_eq(source_runs.val, 2)
  assert_eq(builds.val, 2)
  assert_eq(mock_text(browser, "list"), "12:B")
}

test "mock dom h_map_dyn keeps explicit indexes" {
  reset_test_state()
  let items = cel([("A", 9), ("B", 10)])
  let browser = new_mock_browser()
  let _ = test_scope(() => {
    let _ = mount_test_root(h("ul", [
      ("ui-id", S("list"))
    ], [
      h_map_dyn(fn() { items.get() }, fn(x, i) {
        h("li", [], [Str("\{i()}:\{x}")])
      })
    ]))
    ()
  })
  apply_mock_cmds(browser, assert_take_cmds())
  assert_eq(mock_text(browser, "list"), "9:A10:B")
}

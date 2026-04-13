test "runtime: resolve name scope path" {
  let app = ui("app", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", fn() raise {
    h("div", [Id(app)], [
      h("div", [Id(title)], [])
    ])
  })
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("app/title") > 0, true)
}

test "runtime: plain id does not open scope" {
  let app = ui("app")
  let title = ui("title")
  let root = Entry::new("root", fn() raise {
    h("div", [Id(app)], [
      h("div", [Id(title)], [])
    ])
  })
  let rt = Runtime::new(root)
  assert_fail("expected scope lookup to fail", fn() raise { rt.resolve("app/title") })
}

test "runtime: nested name scope keeps boundary" {
  let app = ui("app", scope=Some(Name))
  let panel = ui("panel", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", fn() raise {
    h("div", [Id(app)], [
      h("div", [Id(panel)], [
        h("div", [Id(title)], [])
      ])
    ])
  })
  let rt = Runtime::new(root)
  assert_fail("expected nested scope boundary", fn() raise { rt.resolve("app/title") })
  assert_eq(rt.resolve("app/panel/title") > 0, true)
}

test "runtime: named descendant inside anonymous wrapper resolves in parent scope" {
  let app = ui("app", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", fn() raise {
    h("div", [Id(app)], [
      h("div", [], [
        h("div", [Id(title)], [])
      ])
    ])
  })
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("app/title") > 0, true)
  assert_fail("expected descendant name to stay out of root scope", fn() raise { rt.resolve("title") })
}

test "runtime: removing anonymous wrapper clears descendant names" {
  let show = cel(true)
  let app = ui("app", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", fn() raise {
    h("div", [Id(app)], [
      Dyn(fn() raise { if show.get() {
        h("div", [], [h("div", [Id(title)], [])])
      } else { Null } })
    ])
  })
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("app/title") > 0, true)
  show.set(false)
  flush()
  assert_fail("expected removed descendant name to disappear", fn() raise { rt.resolve("app/title") })
}

test "dom: moving dyn subtree across scopes keeps future updates in new scope" {
  let show = cel(true)
  let left_id = ui("left", scope=Some(Name))
  let right_id = ui("right", scope=Some(Name))
  let title_id = ui("title")
  let dom = Dom::new()
  let left = element(dom, "div", Html)
  let right = element(dom, "div", Html)
  left.set(dom, Id(left_id))
  right.set(dom, Id(right_id))
  dom.body.insert(dom, left)
  dom.body.insert(dom, right)
  let box = element(dom, "div", Html)
  for node in child(dom, Dyn(fn() raise { if show.get() {
    h("div", [Id(title_id)], [])
  } else { Null } }), left) {
    box.insert(dom, node, fresh=true)
  }
  left.insert(dom, box)
  assert_eq(dom.resolve("left/title") > 0, true)
  right.insert(dom, box)
  assert_fail("expected moved dyn subtree to leave old scope", fn() raise { dom.resolve("left/title") })
  assert_eq(dom.resolve("right/title") > 0, true)
  show.set(false)
  flush()
  show.set(true)
  flush()
  assert_fail("expected dyn rebuild to stay out of old scope", fn() raise { dom.resolve("left/title") })
  assert_eq(dom.resolve("right/title") > 0, true)
}

test "runtime: resolve empty path fails" {
  let root = Entry::new("root", fn() raise { h("div", [], []) })
  let rt = Runtime::new(root)
  assert_fail("expected empty query to fail", fn() raise { rt.resolve(" ") })
}

test "dom: invalid ui id fails" {
  assert_fail("expected invalid ui-id to fail", fn() raise { ui(" bad ") })
}

test "runtime: duplicate ui id fails" {
  let app = ui("app", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", fn() raise {
    h("div", [Id(app)], [
      h("div", [Id(title)], []),
      h("div", [Id(title)], []),
    ])
  })
  assert_fail("expected duplicate ui-id to fail", fn() raise { Runtime::new(root) })
}

test "runtime: comp renders child" {
  let card = comp((_, cs) => h("section", [], cs))
  let root = Entry::new("root", () => h(card, [], [h("div", [], [])]))
  let rt = Runtime::new(root)
  let body = match rt.dom.body.data { Element(el) => el; _ => panic() }
  assert_eq(body.first is Some(_), true)
}

test "runtime: swallowed dyn error is reported" {
  let errors = []
  let root = Entry::new("root", () => {
    h("div", [], [Dyn(None, fn() raise { fail("dyn boom") })])
  })
  let rt = Runtime::new(root, on_error=msg => errors.push(msg))
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].contains("dyn boom"), true)
  let body = match rt.dom.body.data { Element(el) => el; _ => panic() }
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

test "runtime: resolve walks static ui scope" {
  let panel = ui("panel", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let root = Entry::new("root", () => {
    h("div", [Id(panel)], [h("button", [Id(save)], [Str("Save")])])
  })
  let rt = Runtime::new(root)
  let node = rt.resolve("panel/save")
  assert_eq(node.id > 0, true)
  assert_eq(match node.data { Element(el) => el.tag; _ => "" }, "button")
}

test "runtime: fresh mount binds sibling scopes once" {
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let root = Entry::new("root", () => {
    h("div", [], [
      h("div", [Id(left)], [h("button", [Id(save)], [Str("Save")])]),
      h("div", [Id(right)], []),
    ])
  })
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("left").id > 0, true)
  assert_eq(rt.resolve("right").id > 0, true)
  assert_eq(rt.resolve("left/save").id > 0, true)
}

test "runtime: move and remove update query binding" {
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let root = Entry::new("root", () => {
    h("div", [], [
      h("div", [Id(left)], [h("button", [Id(save)], [Str("Save")])]),
      h("div", [Id(right)], []),
    ])
  })
  let rt = Runtime::new(root)
  let left_host = rt.resolve("left")
  let right_host = rt.resolve("right")
  let save_btn = rt.resolve("left/save")
  right_host.insert(rt.dom, save_btn)
  assert_fail("old path should fail after move", () => ignore(rt.resolve("left/save")))
  assert_eq(rt.resolve("right/save").id, save_btn.id)
  save_btn.remove(rt.dom)
  assert_fail("path should fail after remove", () => ignore(rt.resolve("right/save")))
  assert_eq(match left_host.data { Element(el) => el.first is Some(_); _ => false }, false)
}

test "runtime: move subtree updates nested scope paths" {
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let panel = ui("panel", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let root = Entry::new("root", () => {
    h("div", [], [
      h("div", [Id(left)], [
        h("div", [Id(panel)], [h("button", [Id(save)], [Str("Save")])]),
      ]),
      h("div", [Id(right)], []),
    ])
  })
  let rt = Runtime::new(root)
  let right_host = rt.resolve("right")
  let panel_host = rt.resolve("left/panel")
  let save_btn = rt.resolve("left/panel/save")
  right_host.insert(rt.dom, panel_host)
  assert_fail("old nested path should fail after move", () => ignore(rt.resolve("left/panel/save")))
  assert_eq(rt.resolve("right/panel").id, panel_host.id)
  assert_eq(rt.resolve("right/panel/save").id, save_btn.id)
}

test "runtime: nested dyn keeps query in new scope after move" {
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let title = ui("title") catch { _ => panic() }
  let outer = cel(true)
  let inner = cel(true)
  let root = Entry::new("root", () => {
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
  })
  let rt = Runtime::new(root)
  let right_host = rt.resolve("right")
  let moved = rt.resolve("left/title")
  let wrap = moved.parent.unwrap()
  right_host.insert(rt.dom, wrap)
  assert_fail("old path should fail after move", () => ignore(rt.resolve("left/title")))
  assert_eq(rt.resolve("right/title").id, moved.id)
  inner.set(false)
  flush()
  inner.set(true)
  flush()
  assert_fail("old path should stay invalid after inner dyn rerun", () => ignore(rt.resolve("left/title")))
  assert_eq(rt.resolve("right/title").id > 0, true)
}

test "runtime: frag dyn keeps query in new scope after move" {
  let left = ui("left", scope=Scope) catch { _ => panic() }
  let right = ui("right", scope=Scope) catch { _ => panic() }
  let title = ui("title") catch { _ => panic() }
  let outer = cel(true)
  let inner = cel(true)
  let root = Entry::new("root", () => {
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
  })
  let rt = Runtime::new(root)
  let right_host = rt.resolve("right")
  let moved = rt.resolve("left/title")
  let wrap = moved.parent.unwrap()
  right_host.insert(rt.dom, wrap)
  assert_fail("old path should fail after move", () => ignore(rt.resolve("left/title")))
  assert_eq(rt.resolve("right/title").id, moved.id)
  inner.set(false)
  flush()
  inner.set(true)
  flush()
  assert_fail("old path should stay invalid after inner dyn rerun", () => ignore(rt.resolve("left/title")))
  assert_eq(rt.resolve("right/title").id > 0, true)
}

test "runtime: list item frag dyn keeps item scope after rerun" {
  let items = cel(["A", "B"])
  let show = cel(true)
  let title = ui("title") catch { _ => panic() }
  let root = Entry::new("root", () => {
    h("div", [], [Dyn(Some("todos"), () => Arr(items.get().map(item =>
      Arr([
        Dyn(None, () => if show.get() {
          h("span", [Id(title)], [Str(item)])
        } else { Null }),
        Str("tail"),
      ])
    )))])
  })
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("todos/0/title").id > 0, true)
  assert_eq(rt.resolve("todos/1/title").id > 0, true)
  show.set(false)
  flush()
  show.set(true)
  flush()
  assert_eq(rt.resolve("todos/0/title").id > 0, true)
  assert_eq(rt.resolve("todos/1/title").id > 0, true)
}

test "runtime: dyn rejects invalid list id" {
  let errors = []
  let root = Entry::new("root", () => h("div", [], [Dyn(Some("bad/id"), () => Null)]))
  ignore(Runtime::new(root, on_error=msg => errors.push(msg)))
  assert_eq(errors.length(), 1)
  assert_eq(errors[0] != "", true)
}

test "runtime: dyn accepts list scope" {
  let text = ui("text") catch { _ => panic() }
  let root = Entry::new("root", () => {
    h("div", [], [Dyn(Some("todos"), () => h("span", [Id(text)], [Str("A")]))])
  })
  let rt = Runtime::new(root)
  let node = rt.resolve("todos/0/text")
  assert_eq(match node.data { Element(el) => el.tag; _ => "" }, "span")
}

test "runtime: h_map opens list scope from string id" {
  let items = cel(["A", "B"])
  let text = ui("text") catch { _ => panic() }
  let root = Entry::new("root", () => {
    h("div", [], [h_map(
      items,
      (item, _) => h("span", [Id(text)], [Str(item)]),
      ui_id=Some("todos"),
    )])
  })
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("todos/0/text").id > 0, true)
  assert_eq(rt.resolve("todos/1/text").id > 0, true)
}

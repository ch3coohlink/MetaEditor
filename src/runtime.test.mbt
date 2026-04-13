test "runtime: resolve name scope path" {
  let app = ui("app", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", () => {
    h("div", [Id(app)], [
      h("div", [Id(title)], [])
    ])
  })
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("app/title") > 0, true)
}

test "runtime: comp renders child" {
  let title = ui("title")
  let card = comp((_, cs) => h("section", [], cs))
  let root = Entry::new("root", () => h(card, [], [h("div", [Id(title)], [])]))
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("title") > 0, true)
}

test "runtime: plain id does not open scope" {
  let app = ui("app")
  let title = ui("title")
  let root = Entry::new("root", () => {
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
  let root = Entry::new("root", () => {
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
  let root = Entry::new("root", () => {
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
  let root = Entry::new("root", () => {
    h("div", [Id(app)], [
      Dyn(None, () => if show.get() {
        h("div", [], [h("div", [Id(title)], [])])
      } else { Null })
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
  for node in child(dom, Dyn(None, () => if show.get() {
    h("div", [Id(title_id)], [])
  } else { Null }), left) {
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
  let errors = []
  let root = Entry::new("root", () => h("div", [], []))
  let rt = Runtime::new(root, on_error=msg => errors.push(msg))
  assert_fail("expected empty query to fail", fn() raise { rt.resolve(" ") })
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].contains("query is empty"), true)
}

test "dom: invalid ui id fails" {
  assert_fail("expected invalid ui-id to fail", fn() raise { ui(" bad ") })
}

test "runtime: duplicate ui id is reported" {
  let errors = []
  let app = ui("app", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", () => {
    h("div", [Id(app)], [
      h("div", [Id(title)], []),
      h("div", [Id(title)], []),
    ])
  })
  ignore(Runtime::new(root, on_error=msg => errors.push(msg)))
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].contains("duplicate ui-id"), true)
}

test "runtime: dyn list scope follows list updates" {
  let todos = cel([("a", "A"), ("b", "B")])
  let list = ui("todos", scope=Some(List))
  let text = ui("text")
  let root = Entry::new("root", () => Dyn(Some(list), () => Arr(todos.get()
    .map(v => h("div", [], [h("span", [Id(text)], [Str(v.1)])])))))
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("todos/0/text") > 0, true)
  assert_eq(rt.resolve("todos/1/text") > 0, true)
  todos.set([("b", "B")])
  flush()
  assert_eq(rt.resolve("todos/0/text") > 0, true)
  assert_fail("expected removed list item path to disappear", fn() raise { rt.resolve("todos/1/text") })
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

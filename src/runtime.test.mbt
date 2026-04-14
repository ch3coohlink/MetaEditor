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
    h("div", [], [Dyn(fn() raise { fail("dyn boom") })])
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

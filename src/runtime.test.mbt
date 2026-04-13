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

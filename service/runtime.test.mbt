test "native: node query decodes from shorthand and json" {
  let q1: @src.NodeQuery = from_json("text")
  let q2: @src.NodeQuery = from_json(parse("{\"kind\":\"attr\",\"value\":\"title\"}"))
  match q1 {
    Text => ()
    _ => fail("expected text query")
  }
  match q2 {
    Attr("title") => ()
    _ => fail("expected attr query")
  }
  assert_eq(q1.to_json().stringify(), Json::string("text").stringify())
  assert_eq(q2.to_json().stringify(), parse("{\"kind\":\"attr\",\"value\":\"title\"}").stringify())
}

test "native: dom event roundtrip through json" {
  let ev: @src.DomEvent = from_json(parse("{\"kind\":\"click\"}"))
  assert_eq(ev.kind().to_string(), "click")
  assert_eq(ev.to_json().stringify(), parse("{\"kind\":\"click\"}").stringify())
}

test "native: client read decodes protocol bodies" {
  match Client::read("{\"id\":2,\"body\":[\"Cli\",\"ok\\n\"]}", 2) {
    Array([String("Cli"), String("ok\n")]) => ()
    _ => fail("expected cli body")
  }
  match Client::read("{\"id\":3,\"body\":[\"Query\",{\"kind\":\"text\",\"text\":\"Save\"}]}", 3) {
    Array([String("Query"), Object(_)]) => ()
    _ => fail("expected query body")
  }
  @src.assert_fail("err body should raise", () =>
    ignore(Client::read("{\"id\":4,\"body\":[\"Err\",\"bad\"]}", 4)))
}

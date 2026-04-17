test "native: node query decodes from derive json" {
  let q1: @src.NodeQuery = from_json("Text")
  let q2: @src.NodeQuery = from_json(parse("[\"Attr\",\"title\"]"))
  match q1 {
    Text => ()
    _ => fail("expected text query")
  }
  match q2 {
    Attr("title") => ()
    _ => fail("expected attr query")
  }
}

test "native: dom event decodes from json" {
  let ev: @src.DomEvent = from_json(parse("{\"kind\":\"click\"}"))
  assert_eq(ev.kind().to_string(), "click")
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

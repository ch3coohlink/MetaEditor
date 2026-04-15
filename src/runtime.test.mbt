test "runtime: query forwards to dom query" {
  let panel = ui("panel", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let root : Entry[Unit, Unit] = {
    id: "root",
    title: "root",
    data: () => (),
    session: _ => (),
    init: () => (_, _) => comp((_, _) =>
      h("div", [Id(panel)], [h("button", [Id(save)], [Str("Save")])])
    ),
  }
  let rt = Runtime::new(root)
  match rt.query("panel/save", Text) {
    Text("Save") => ()
    _ => fail("expected runtime query text result")
  }
}

test "runtime: node query decodes from json" {
  let q1 : NodeQuery = @json.from_json("text")
  let q2 : NodeQuery = @json.from_json({ "kind": "prop", "value": "click" })
  match q1 {
    Text => ()
    _ => fail("expected text query")
  }
  match q2 {
    Prop("click") => ()
    _ => fail("expected prop query")
  }
}

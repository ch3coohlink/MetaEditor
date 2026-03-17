pub fn start() -> Unit {
  let _ = try {
    let _ = @src.scope(fn() {
      let count = @src.cel(0)
      let add_action = @src.reg_action("add", fn() { count.set(count.get() + 1) })
      @src.reg_query("count", fn() { count.get().to_string() })
      let root = @src.h("div", [
        ("style", @src.S("padding: 20px; font-family: sans-serif; text-align: center;"))
      ], [
        @src.Node(@src.h("h1", [], [@src.Str("MetaEditor Application")])),
        @src.Node(@src.h("div", [("style", @src.S("font-size: 40px; margin: 20px;"))], [
          @src.Dyn(fn() { @src.Str("Count: \{count.get()}") })
        ])),
        @src.Node(@src.h("button", [
          ("onclick", add_action),
          ("style", @src.S("padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer;"))
        ], [@src.Str("Add")]))
      ])
      @src.emit(@src.Append(0, root.id))

    })
  } catch { _ => () }
  let _ = try { @src.flush() } catch { _ => () }
}

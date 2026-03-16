

pub fn start() -> Unit {
  let _ = try {
    let _ = @src.scope(fn() {
      let count = @src.cel(0)
      
      let root = @src.h("div", [
        ("style", @src.S("padding: 20px; font-family: sans-serif; text-align: center;"))
      ], [
        @src.h("h1", [], [@src.text("MetaEditor Application")]),
        @src.h("div", [("style", @src.S("font-size: 40px; margin: 20px;"))], [
          @src.text_dyn(fn() { "Count: \{count.get()}" })
        ]),
        @src.h("button", [
          ("onclick", @src.E(fn() { count.set(count.get() + 1) })),
          ("style", @src.S("padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer;"))
        ], [@src.text("Add")])
      ])
      
      @src.emit(@src.Append(0, root.id))
    })
    ()
  } catch {
    _ => ()
  }

  let _ = try {
    @src.flush()
  } catch {
    _ => ()
  }
}

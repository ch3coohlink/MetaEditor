pub fn build_counter_app(
  title? : String = "Counter Test App",
  compact? : Bool = false,
) -> @src.VNode {
  let count = @src.new_store(0)
  let add_action = @src.reg_action("add", fn() {
    let _ = @src.apply_local(count, "add", fn(v) { v + 1 })
  })
  let undo_action = @src.reg_action("undo", fn() { let _ = @src.undo(count) })
  let redo_action = @src.reg_action("redo", fn() { let _ = @src.redo(count) })
  let root_style = if compact {
    "padding: 16px; font-family: sans-serif; border: 1px solid #d5d9e0; border-radius: 12px; background: #fff;"
  } else {
    "padding: 24px; font-family: sans-serif; text-align: center;"
  }
  let value_style = if compact {
    "font-size: 28px; margin: 12px 0;"
  } else {
    "font-size: 40px; margin: 20px;"
  }
  let meta_style = if compact {
    "color: #666; margin-bottom: 12px;"
  } else {
    "color: #666; margin-bottom: 16px;"
  }
  let button_row_style = if compact {
    "display: flex; gap: 10px; flex-wrap: wrap;"
  } else {
    "display: flex; gap: 12px; justify-content: center;"
  }
  @src.h("div", [
    ("style", @src.S(root_style))
  ], [
    @src.Node(@src.h("h1", [], [@src.Str(title)])),
    @src.Node(@src.h("div", [("style", @src.S(value_style))], [
      @src.Dyn(fn() { @src.Str("Count: \{count.read()}") })
    ])),
    @src.Node(@src.h("div", [("style", @src.S(meta_style))], [
      @src.Dyn(fn() { @src.Str("Version: \{count.version()}") })
    ])),
    @src.Node(@src.h("div", [("style", @src.S(button_row_style))], [
      @src.Node(@src.h("button", [
        ("onclick", add_action),
        ("style", @src.S("padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer;"))
      ], [@src.Str("Add")])),
      @src.Node(@src.h("button", [
        ("onclick", undo_action),
        ("style", @src.S("padding: 10px 20px; background: #6c757d; color: white; border: none; border-radius: 5px; cursor: pointer;"))
      ], [@src.Str("Undo")])),
      @src.Node(@src.h("button", [
        ("onclick", redo_action),
        ("style", @src.S("padding: 10px 20px; background: #28a745; color: white; border: none; border-radius: 5px; cursor: pointer;"))
      ], [@src.Str("Redo")]))
    ]))
  ])
}

pub fn start() -> Unit {
  let _ = try {
    let _ = @src.scope(fn() {
      let root = build_counter_app()
      @src.emit(@src.Append(0, root.id))
    })
  } catch { _ => () }
  let _ = try { @src.flush() } catch { _ => () }
}

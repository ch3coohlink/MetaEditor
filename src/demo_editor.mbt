pub(all) struct Editor {
  id : String
  name : String
  view : () -> Child
}

pub fn demo_editor() -> Editor {{
  id: "demo",
  name: "Demo Editor",
  view: fn() {
    h("div", [
      ("data-testid", S("demo-editor-root")),
      ("style", S("padding: 16px;"))
    ], [
      h("h2", [], [Str("Demo Editor")]),
      h("div", [("style", S("color: #666;"))], [Str("First src editor placeholder.")])
    ])
  }
}}

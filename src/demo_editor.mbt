pub(all) struct EditorProps[D, S] {
  data : Cel[D]
  session : Cel[S]
}

pub(all) struct Editor[D, S] {
  id : String
  name : String?
  data : D
  session : S
  view : (EditorProps[D, S]) -> Child
}

pub(all) struct AnyEditor {
  id : String
  name : String
  view : () -> Child
}

pub(all) struct DemoData {
  mut title : String
}

pub(all) struct DemoSession {
  mut count : Int
}

pub impl Persist for DemoData with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.title)),
  ])
}

pub impl Persist for DemoData with unpack(
  value : PersistValue,
  old? : DemoData? = None
) -> DemoData {
  ignore(old)
  match value {
    Obj(m) => {
      let title = match m.get("10") {
        Some(v) => unpack(v)
        None => "Demo Editor"
      }
      { title, }
    }
    _ => { title: "Demo Editor" }
  }
}

pub impl Persist for DemoSession with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.count)),
  ])
}

pub impl Persist for DemoSession with unpack(
  value : PersistValue,
  old? : DemoSession? = None
) -> DemoSession {
  ignore(old)
  match value {
    Obj(m) => {
      let count = match m.get("10") {
        Some(v) => unpack(v)
        None => 0
      }
      { count, }
    }
    _ => { count: 0 }
  }
}

pub fn[D, S] erase_editor(editor : Editor[D, S]) -> AnyEditor {
  let props = {
    data: cel(editor.data),
    session: cel(editor.session),
  }
  let name = match editor.name {
    Some(v) => v
    None => editor.id
  }
  {
    id: editor.id,
    name,
    view: fn() { (editor.view)(props) }
  }
}

pub fn demo_editor() -> Editor[DemoData, DemoSession] {{
  id: "demo",
  name: None,
  data: { title: "Demo Editor" },
  session: { count: 0 },
  view: fn(state) {
    h("div", [
      ("data-testid", S("demo-editor-root")),
      ("style", S("padding: 16px;"))
    ], [
      h("h2", [], [
        Dyn(fn() { Str(state.data.get().title) })
      ]),
      h("div", [("style", S("color: #666;"))], [
        Str("First src editor placeholder.")
      ]),
      h("button", [
        ("onclick", E(fn() {
          state.session.mutate(v => {
            v.count = v.count + 1
          })
        })),
        ("style", S("margin-top: 12px; padding: 8px 12px;"))
      ], [
        Dyn(fn() { Str("Session Count: \{state.session.get().count}") })
      ])
    ])
  }
}}

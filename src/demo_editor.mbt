pub(all) struct Editor[D, S] {
  id : String
  name : String?
  data : D
  session : S
  view : (Cel[D], Cel[S]) -> Comp
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

pub fn demo_editor() -> Editor[DemoData, DemoSession] {{
  id: "demo",
  name: None,
  data: { title: "Demo Editor" },
  session: { count: 0 },
  view: fn(data, session) {
    comp(fn(attrs, children) {
      ignore(attrs)
      ignore(children)
      h("div", [
        ("data-testid", S("demo-editor-root")),
        ("style", S("padding: 16px;"))
      ], [
        h("h2", [], [
          Dyn(fn() { Str(data.get().title) })
        ]),
        h("div", [("style", S("color: #666;"))], [
          Str("First src editor placeholder.")
        ]),
        h("button", [
          ("onclick", E(fn() {
            session.mutate(v => {
              v.count = v.count + 1
            })
          })),
          ("style", S("margin-top: 12px; padding: 8px 12px;"))
        ], [
          Dyn(fn() { Str("Session Count: \{session.get().count}") })
        ])
      ])
    })
  }
}}

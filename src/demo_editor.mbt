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

pub(all) struct DemoHostData {
  child : Cel[DemoData]
}

pub(all) struct DemoHostSession {
  child : Cel[DemoSession]
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

pub impl Persist for DemoHostData with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.child)),
  ])
}

pub impl Persist for DemoHostData with unpack(
  value : PersistValue,
  old? : DemoHostData? = None
) -> DemoHostData {
  let child_default = match old {
    Some(prev) => Some(prev.child)
    None => None
  }
  match value {
    Obj(m) => {
      let child : Cel[DemoData] = match m.get("10") {
        Some(v) => unpack(v, old=child_default)
        None => match child_default {
          Some(prev) => prev
          None => unpack(Null)
        }
      }
      { child, }
    }
    _ => {
      child: match child_default {
        Some(prev) => prev
        None => unpack(Null)
      }
    }
  }
}

pub impl Persist for DemoHostSession with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.child)),
  ])
}

pub impl Persist for DemoHostSession with unpack(
  value : PersistValue,
  old? : DemoHostSession? = None
) -> DemoHostSession {
  let child_default = match old {
    Some(prev) => Some(prev.child)
    None => None
  }
  match value {
    Obj(m) => {
      let child : Cel[DemoSession] = match m.get("10") {
        Some(v) => unpack(v, old=child_default)
        None => match child_default {
          Some(prev) => prev
          None => unpack(Null)
        }
      }
      { child, }
    }
    _ => {
      child: match child_default {
        Some(prev) => prev
        None => unpack(Null)
      }
    }
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

pub fn demo_host_editor() -> Editor[DemoHostData, DemoHostSession] {{
  let child = demo_editor()
  {
    id: "demo_host",
    name: Some("Demo Host"),
    data: {
      child: cel(child.data)
    },
    session: {
      child: cel(child.session)
    },
    view: fn(data, session) {
      comp(fn(attrs, children) {
        ignore(attrs)
        ignore(children)
        h("div", [
          ("data-testid", S("demo-host-root")),
          ("style", S("padding: 16px; display: flex; flex-direction: column; gap: 12px;"))
        ], [
          h("h2", [], [Str("Demo Host Editor")]),
          h("div", [("style", S("color: #666;"))], [
            Str("Child editor state is stored in parent data/session.")
          ]),
          h((child.view)(data.get().child, session.get().child), [], [])
        ])
      })
    }
  }
}}

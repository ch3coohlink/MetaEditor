pub(all) struct DemoTodo {
  id : Int
  text : String
  done : Bool
}

pub(all) struct DemoData {
  mut title : String
  mut next_id : Int
  mut todos : Array[DemoTodo]
}

pub(all) struct DemoSession {
  mut show_done : Bool
}

pub(all) struct DemoHostData {
  child : Cel[DemoData]
}

pub(all) struct DemoHostSession {
  child : Cel[DemoSession]
}

priv suberror DemoErr {
  Fail(String)
}

pub impl Persist for DemoTodo with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.id)),
    ("11", pack(self.text)),
    ("12", pack(self.done)),
  ])
}

pub impl Persist for DemoTodo with unpack(
  value : PersistValue,
  old? : DemoTodo? = None
) -> DemoTodo {
  ignore(old)
  match value {
    Obj(m) => {
      let id = match m.get("10") {
        Some(v) => unpack(v)
        None => 0
      }
      let text = match m.get("11") {
        Some(v) => unpack(v)
        None => ""
      }
      let done = match m.get("12") {
        Some(v) => unpack(v)
        None => false
      }
      { id, text, done }
    }
    _ => { id: 0, text: "", done: false }
  }
}

pub impl Persist for DemoData with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.title)),
    ("11", pack(self.next_id)),
    ("12", pack(self.todos)),
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
        None => "Demo Todo Editor"
      }
      let next_id = match m.get("11") {
        Some(v) => unpack(v)
        None => 3
      }
      let todos = match m.get("12") {
        Some(v) => unpack(v)
        None => demo_todos()
      }
      { title, next_id, todos }
    }
    _ => { title: "Demo Todo Editor", next_id: 3, todos: demo_todos() }
  }
}

pub impl Persist for DemoSession with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.show_done)),
  ])
}

pub impl Persist for DemoSession with unpack(
  value : PersistValue,
  old? : DemoSession? = None
) -> DemoSession {
  ignore(old)
  match value {
    Obj(m) => {
      let show_done = match m.get("10") {
        Some(v) => unpack(v)
        None => false
      }
      { show_done, }
    }
    _ => { show_done: false }
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

fn demo_todos() -> Array[DemoTodo] {
  [
    { id: 1, text: "Write helper", done: false },
    { id: 2, text: "Hidden done item", done: true },
  ]
}

fn visible_todos(data : DemoData, session : DemoSession) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let mut n = 0
  for todo in data.todos {
    if session.show_done || !todo.done {
      out.push((todo.id, n))
      n = n + 1
    }
  }
  out
}

fn visible_count(data : DemoData, session : DemoSession) -> Int {
  visible_todos(data, session).length()
}

fn find_todo(data : DemoData, id : Int) -> DemoTodo? {
  for todo in data.todos {
    if todo.id == id { return Some(todo) }
  }
  None
}

fn parse_todo_id(arg : String) -> Int raise {
  let id = @string.parse_int(arg.trim()) catch { _ => -1 }
  if id < 0 { raise DemoErr::Fail("invalid todo id: \{arg}") }
  id
}

fn demo_act(data : Cel[DemoData], session : Cel[DemoSession], name : String, arg : String) -> String raise {
  match name {
    "add" => {
      data.mutate(v => {
        let id = v.next_id
        v.next_id = id + 1
        v.todos.push({ id, text: "Todo \{id}", done: false })
      })
      "added todo\n"
    }
    "toggle_done" => {
      session.mutate(v => {
        v.show_done = !v.show_done
      })
      "toggled done filter\n"
    }
    "toggle_todo" => {
      let id = parse_todo_id(arg)
      data.mutate(v => {
        for i = 0; i < v.todos.length(); i = i + 1 {
          if v.todos[i].id == id {
            v.todos[i] = {
              id,
              text: v.todos[i].text,
              done: !v.todos[i].done,
            }
            return
          }
        }
      })
      "toggled todo \{id}\n"
    }
    "remove_todo" => {
      let id = parse_todo_id(arg)
      data.mutate(v => {
        v.todos = v.todos.filter(todo => todo.id != id)
      })
      "removed todo \{id}\n"
    }
    _ => raise DemoErr::Fail("unknown demo action: \{name}")
  }
}

fn todo_item(
  data : Cel[DemoData],
  bind : (String, String) -> Prop,
  id : Int
) -> Child {
  h("div", [
    ("ui-id", S("demo-item:\{id}")),
    ("style", S("display: flex; gap: 8px; align-items: center; padding: 8px 0; border-bottom: 1px solid #eee;"))
  ], [
    h("span", [("ui-id", S("demo-item:\{id}/text"))], [
      Dyn(fn() {
        match find_todo(data.get(), id) {
          Some(todo) => Str(if todo.done { "[x] \{todo.text}" } else { "[ ] \{todo.text}" })
          None => Str("")
        }
      })
    ]),
    h("button", [
      ("ui-id", S("demo-item:\{id}/toggle")),
      ("onclick", bind("toggle_todo", id.to_string()))
    ], [
      Dyn(fn() {
        match find_todo(data.get(), id) {
          Some(todo) => Str(if todo.done { "Undo" } else { "Done" })
          None => Str("Done")
        }
      })
    ]),
    h("button", [
      ("ui-id", S("demo-item:\{id}/remove")),
      ("onclick", bind("remove_todo", id.to_string()))
    ], [
      Str("Remove")
    ])
  ])
}

fn demo_view(
  data : Cel[DemoData],
  session : Cel[DemoSession],
  bind : (String, String) -> Prop
) -> Child {
  h("div", [
    ("ui-id", S("demo-editor")),
    ("style", S("padding: 16px;"))
  ], [
    h("h2", [], [
      Dyn(fn() { Str(data.get().title) })
    ]),
    h("div", [
      ("ui-id", S("demo-summary")),
      ("style", S("color: #666; margin-bottom: 12px;"))
    ], [
      Dyn(fn() {
        let current = data.get()
        let ui = session.get()
        Str("Visible \{visible_count(current, ui)} / \{current.todos.length()} todos")
      })
    ]),
    h("div", [("style", S("display: flex; gap: 8px; margin-bottom: 12px;"))], [
      h("button", [
        ("ui-id", S("demo-add")),
        ("onclick", bind("add", ""))
      ], [
        Str("Add Todo")
      ]),
      h("button", [
        ("ui-id", S("demo-toggle-done")),
        ("onclick", bind("toggle_done", ""))
      ], [
        Dyn(fn() { Str(if session.get().show_done { "Hide Done" } else { "Show Done" }) })
      ])
    ]),
    h("div", [("ui-id", S("demo-list"))], [
      Dyn(fn() {
        let current = data.get()
        let ui = session.get()
        if visible_count(current, ui) == 0 {
          h("div", [("ui-id", S("demo-empty"))], [Str("No visible todos.")])
        } else {
          Null
        }
      }),
      h_map_dyn(fn() {
        visible_todos(data.get(), session.get())
      }, (v, _) => todo_item(data, bind, v))
    ])
  ])
}

pub fn demo_entry() -> Entry[DemoData, DemoSession] {{
  id: "demo",
  name: Some("Demo Todo"),
  icon: Some("TODO"),
  new_data: fn() {
    {
      title: "Demo Todo Editor",
      next_id: 3,
      todos: demo_todos(),
    }
  },
  new_session: fn() { { show_done: false } },
  view: fn(ctx) {
    comp(fn(attrs, children) {
      ignore(attrs)
      ignore(children)
      demo_view(ctx.data, ctx.session, fn(name, arg) { ctx.action(name, arg=arg) })
    })
  },
  act: (ctx, name, arg) => {
    demo_act(ctx.data, ctx.session, name, arg)
  }
}}

pub fn demo_host_entry() -> Entry[DemoHostData, DemoHostSession] {{
  id: "demo_host",
  name: Some("Demo Host"),
  icon: Some("HOST"),
  new_data: fn() {
    {
      child: cel((demo_entry().new_data)())
    }
  },
  new_session: fn() {
    {
      child: cel((demo_entry().new_session)())
    }
  },
  view: fn(ctx) {
    comp(fn(attrs, children) {
      ignore(attrs)
      ignore(children)
      h("div", [
        ("ui-id", S("demo-host")),
        ("style", S("padding: 16px; display: flex; flex-direction: column; gap: 12px;"))
      ], [
        h("h2", [], [Str("Demo Host Editor")]),
        h("div", [("style", S("color: #666;"))], [
          Str("Child editor state is stored in parent data/session.")
        ]),
        demo_view(ctx.data.get().child, ctx.session.get().child, fn(name, arg) {
          ctx.action(name, arg=arg)
        })
      ])
    })
  },
  act: (ctx, name, arg) => {
    demo_act(ctx.data.get().child, ctx.session.get().child, name, arg)
  }
}}

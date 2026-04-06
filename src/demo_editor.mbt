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

let demo_css =
  #|{
  #|  width: 100%;
  #|  height: 100%;
  #|  box-sizing: border-box;
  #|  padding: 16px;
  #|  display: flex;
  #|  flex-direction: column;
  #|  gap: 12px;
  #|  background: linear-gradient(180deg, #ffffff 0%, #f6f8fc 100%);
  #|  color: #1d2939;
  #|  font-family: inherit;
  #|}
  #|h2 {
  #|  margin: 0;
  #|  font-size: 20px;
  #|  line-height: 1.2;
  #|}
  #|.summary {
  #|  color: #667085;
  #|  font-size: 13px;
  #|}
  #|.demo-actions {
  #|  display: flex;
  #|  gap: 8px;
  #|  flex-wrap: wrap;
  #|}
  #|.demo-actions button,
  #|.demo-item button {
  #|  border: 1px solid #d0d5dd;
  #|  border-radius: 999px;
  #|  background: #fff;
  #|  color: #344054;
  #|  cursor: pointer;
  #|}
  #|.demo-actions button {
  #|  padding: 8px 12px;
  #|  box-shadow: 0 1px 2px rgba(16, 24, 40, 0.04);
  #|}
  #|.list {
  #|  display: flex;
  #|  flex-direction: column;
  #|  gap: 8px;
  #|  min-height: 0;
  #|  overflow: auto;
  #|}
  #|.empty {
  #|  padding: 14px 16px;
  #|  border-radius: 14px;
  #|  background: rgba(255, 255, 255, 0.8);
  #|  border: 1px dashed #d0d5dd;
  #|  color: #98a2b3;
  #|}
  #|.demo-item {
  #|  display: flex;
  #|  align-items: center;
  #|  gap: 8px;
  #|  padding: 12px 14px;
  #|  border-radius: 14px;
  #|  background: rgba(255, 255, 255, 0.9);
  #|  border: 1px solid #eaecf0;
  #|}
  #|.demo-item span {
  #|  flex: 1;
  #|  min-width: 0;
  #|}
  #|.demo-item button {
  #|  padding: 6px 10px;
  #|}
  #|.demo-item button:last-child {
  #|  color: #b42318;
  #|  border-color: #fecdca;
  #|}
let demo_style: StyleSheet = css("demo", S(demo_css))
fn init { ignore(demo_style) }

fn find_todo(data : DemoData, id : Int) -> DemoTodo? {
  for todo in data.todos {
    if todo.id == id { return Some(todo) }
  }
  None
}

fn parse_todo_id(args : Array[ActionArg], name : String) -> Int raise {
  match args {
    [ActionArg::Int(id)] if id >= 0 => id
    _ => raise DemoErr::Fail("invalid todo id for \{name}")
  }
}

fn demo_actions() -> Array[ActionSpec[DemoData, DemoSession, Unit]] {
  [
    {
      id: "add",
      title: Some("Add todo"),
      desc: Some("Append one new todo item."),
      args: [],
      run: (ctx, _) => {
        ctx.data.mutate(v => {
          let id = v.next_id
          v.next_id = id + 1
          v.todos.push({ id, text: "Todo \{id}", done: false })
        })
        "added todo\n"
      },
    },
    {
      id: "toggle",
      title: Some("Toggle"),
      desc: Some("Toggle done filter or one todo done state."),
      args: [{
        name: "id",
        kind: ActionArgKind::Int,
        desc: Some("Todo id. Omit to toggle done filter."),
        optional: true,
      }],
      run: (ctx, args) => {
        match args {
          [] => {
            ctx.session.mutate(v => {
              v.show_done = !v.show_done
            })
            "toggled done filter\n"
          }
          [ActionArg::Int(_)] => {
            let id = parse_todo_id(args, "toggle")
            ctx.data.mutate(v => {
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
          _ => raise DemoErr::Fail("invalid args for toggle")
        }
      },
    },
    {
      id: "remove",
      title: Some("Remove"),
      desc: Some("Remove one todo item."),
      args: [{
        name: "id",
        kind: ActionArgKind::Int,
        desc: Some("Todo id."),
        optional: false,
      }],
      run: (ctx, args) => {
        let id = parse_todo_id(args, "remove")
        ctx.data.mutate(v => {
          v.todos = v.todos.filter(todo => todo.id != id)
        })
        "removed todo \{id}\n"
      },
    },
  ]
}

fn todo_item(
  data : Cel[DemoData],
  bind : ActionBind,
  id : Int
) -> Child {
  h("div", [
    ("class", S("demo-item")), ("ui-id", S("demo-item:\{id}")), ("ui-name", S("true")),
  ], [
    h("span", [("ui-id", S("text"))], [
      Dyn(fn() {
        match find_todo(data.get(), id) {
          Some(todo) => Str(if todo.done { "[x] \{todo.text}" } else { "[ ] \{todo.text}" })
          None => Str("")
        }
      })
    ]),
    h("button", [
      ("ui-id", S("toggle")),
      ("onclick", bind("toggle", [ActionArg::Int(id)]))
    ], [
      Dyn(fn() {
        match find_todo(data.get(), id) {
          Some(todo) => Str(if todo.done { "Undo" } else { "Done" })
          None => Str("Done")
        }
      })
    ]),
    h("button", [
      ("ui-id", S("remove")),
      ("onclick", bind("remove", [ActionArg::Int(id)]))
    ], [
      Str("Remove")
    ])
  ])
}

fn demo_view(
  data : Cel[DemoData],
  session : Cel[DemoSession],
  bind : ActionBind
) -> Child {
  h("div", [
    ("class", S("demo")),
    ("ui-id", S("demo-editor")),
  ], [
    h("h2", [], [
      Dyn(fn() { Str(data.get().title) })
    ]),
    h("div", [
      ("class", S("summary")),
      ("ui-id", S("demo-summary"))
    ], [
      Dyn(fn() {
        let current = data.get()
        let ui = session.get()
        Str("Visible \{visible_count(current, ui)} / \{current.todos.length()} todos")
      })
    ]),
    h("div", [("class", S("demo-actions"))], [
      h("button", [
        ("ui-id", S("demo-add")),
        ("onclick", bind("add", []))
      ], [
        Str("Add Todo")
      ]),
      h("button", [
        ("ui-id", S("demo-toggle-done")),
        ("onclick", bind("toggle", []))
      ], [
        Dyn(fn() { Str(if session.get().show_done { "Hide Done" } else { "Show Done" }) })
      ])
    ]),
    h("div", [("class", S("list")), ("ui-id", S("demo-list"))], [
      Dyn(fn() {
        let current = data.get()
        let ui = session.get()
        if visible_count(current, ui) == 0 {
          h("div", [("class", S("empty")), ("ui-id", S("demo-empty"))], [Str("No visible todos.")])
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

pub fn demo_entry() -> Entry[DemoData, DemoSession, Unit] {{
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
  view: fn(ctx, bind) {
    comp(fn(attrs, children) {
      ignore(attrs)
      ignore(children)
      demo_view(ctx.data, ctx.session, bind)
    })
  },
  actions: demo_actions()
}}

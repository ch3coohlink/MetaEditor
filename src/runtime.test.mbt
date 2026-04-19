test "runtime: query forwards to dom query" {
  let panel = ui("panel", scope=Scope)
  let save = ui("save")
  let root: Entry[Unit, Unit, Unit, Unit] = {
    id: "test-root-query", title: "root", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (_, _, _, _, _, _) => comp((_, _) =>
      h("div", [Id(panel)], [h("button", [Id(save)], [Str("Save")])])),
  }
  root.register()
  let rt = Runtime::new("test-root-query").root()
  match rt.query("panel/save", Text) {
    Text("Save") => ()
    _ => fail("expected runtime query text result")
  }
}

test "runtime: node query decodes from json" {
  let q1: NodeQuery = from_json("Text")
  let q2: NodeQuery = from_json(["Prop", "click"])
  match q1 {
    Text => ()
    _ => fail("expected text query")
  }
  match q2 {
    Prop("click") => ()
    _ => fail("expected prop query")
  }
}

test "runtime: new reports saved ui definition errors" {
  ignore(ui("bad/id"))
  let root: Entry[Unit, Unit, Unit, Unit] = {
    id: "test-root-ui-errors", title: "root", data: () => (), session: _ => (),
    actions: (_, _) => (), session_actions: (_, _, _) => (),
    init: (_, _, _, _, _, _) => comp((_, _) => Null),
  }
  root.register()
  let errors = []
  ignore(Runtime::new("test-root-ui-errors", on_err=msg => errors.push(msg)))
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].contains("ui key cannot contain '/'"), true)
}

test "runtime: child instance keeps static scope" {
  let panel = ui("panel", scope=Scope)
  let slot = ui("slot", scope=Scope)
  let save = ui("save")
  let child: Entry[Unit, Unit, Unit, Unit] = {
    id: "test-child-scope", title: "child", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (_, _, _, _, _, _) => comp((_, _) => h("button", [Id(save)], [Str("Save")])),
  }
  let root: Entry[Unit, Unit, Unit, Unit] = {
    id: "test-root-scope", title: "root", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (runtime, _, _, _, _, _) => {
      let child = runtime.spawn_typed(child).0 catch { _ => panic() }
      comp((_, _) => h("div", [Id(panel)], [h("div", [React, Id(slot)], [h(child.view, [], [])])]))
    },
  }
  child.register()
  root.register()
  let rt = Runtime::new("test-root-scope").root()
  match rt.query("panel/slot/save", Text) {
    Text("Save") => ()
    _ => fail("expected child instance static scope")
  }
}

pub struct RootActions { text: () -> String }
pub struct RootSessionActions { append: (String) -> String raise }
test "runtime: entry actions bind onto instance" {
  let value = ui("value")
  let root: Entry[Cel[String], Cel[Int], RootActions, RootSessionActions] = {
    id: "test-root-actions", title: "root",
    data: () => cel("A"),
    session: _ => cel(0),
    actions: (_, d) => {{
      text: () => d.get(),
    }},
    session_actions: (_, d, s) => {{
      append: tail => {
        d.set(d.get() + tail)
        s.set(s.get() + 1)
        d.get() + ":" + s.get().to_string()
      },
    }},
    init: (_, _, d, s, actions, session_actions) => {
      assert_eq((actions.text)(), "A")
      assert_eq((session_actions.append)("B"), "AB:1")
      comp((_, _) => h("div", [Id(value)], [DynP(() => Str(d.get() + ":" + s.get().to_string()))]))
    },
  }
  root.register()
  let rt = Runtime::new("test-root-actions").root()
  match rt.query("value", Text) {
    Text("AB:1") => ()
    _ => fail("expected bound action result")
  }
}

test "runtime: replay re-emits current dom state after dispatch" {
  let btn = ui("btn")
  let value = ui("value")
  let text = cel("0")
  let root: Entry[Unit, Unit, Unit, Unit] = {
    id: "test-root-replay", title: "root", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (_, _, _, _, _, _) => comp((_, _) => h("div", [], [
      h("button", [Id(btn), Event(Click, _ => text.set("1"), EventCfg::new())], [Str("go")]),
      h("div", [Id(value)], [DynP(() => Str(text.get()))]),
    ])),
  }
  root.register()
  let rt = Runtime::new("test-root-replay").root()
  rt.dispatch("btn", Event::pointer(Click))
  let mut hit = false
  for cmd in rt.replay() {
    match cmd {
      Create({ tag: "", value: String("1"), .. }) => hit = true
      _ => ()
    }
  }
  assert_eq(hit, true)
}

test "runtime: dispatch emits incremental dom cmds" {
  let btn = ui("btn")
  let value = ui("value")
  let text = cel("0")
  let seen = []
  let root: Entry[Unit, Unit, Unit, Unit] = {
    id: "test-root-emit", title: "root", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (_, _, _, _, _, _) => comp((_, _) => h("div", [], [
      h("button", [Id(btn), Event(Click, _ => text.set("1"), EventCfg::new())], [Str("go")]),
      h("div", [Id(value)], [DynP(() => Str(text.get()))]),
    ])),
  }
  root.register()
  let rt = Runtime::new("test-root-emit",
    on_out=out => match out { Cmd(_, cmd) => seen.push([cmd]); Read(_, _, _) => () }).root()
  rt.dispatch("btn", Event::pointer(Click))
  let mut hit = false
  for batch in seen {
    for cmd in batch {
      match cmd {
        Create({ tag: "", value: String("1"), .. }) => hit = true
        _ => ()
      }
    }
  }
  assert_eq(hit, true)
}

test "runtime: trigger by node id emits incremental dom cmds" {
  let btn = ui("btn")
  let value = ui("value")
  let text = cel("0")
  let seen = []
  let root: Entry[Unit, Unit, Unit, Unit] = {
    id: "test-root-trigger", title: "root", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (_, _, _, _, _, _) => comp((_, _) => h("div", [], [
      h("button", [Id(btn), Event(Click, _ => text.set("1"), EventCfg::new())], [Str("go")]),
      h("div", [Id(value)], [DynP(() => Str(text.get()))]),
    ])),
  }
  root.register()
  let rt = Runtime::new("test-root-trigger",
    on_out=out => match out { Cmd(_, cmd) => seen.push([cmd]); Read(_, _, _) => () }).root()
  let node = match rt.query("btn", Node) {
    Node(node) => node
    _ => fail("expected node query result")
  }
  rt.trigger(node.id, Event::pointer(Click))
  let mut hit = false
  for batch in seen {
    for cmd in batch {
      match cmd {
        Create({ tag: "", value: String("1"), .. }) => hit = true
        _ => ()
      }
    }
  }
  assert_eq(hit, true)
}

test "runtime: nested instance keeps static scope when inner instance renders multi root" {
  let outer_slot = ui("outer-slot", scope=Scope)
  let inner_slot = ui("inner-slot", scope=Scope)
  let a = ui("a")
  let b = ui("b")
  let inner: Entry[Unit, Unit, Unit, Unit] = {
    id: "inner", title: "inner", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (_, _, _, _, _, _) => comp((_, _) => Arr([
      h("span", [Id(a)], [Str("A")]),
      h("span", [Id(b)], [Str("B")]),
    ])),
  }
  let outer: Entry[Unit, Unit, Unit, Unit] = {
    id: "outer", title: "outer", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (runtime, _, _, _, _, _) => {
      let inner = runtime.spawn_typed(inner).0 catch { _ => panic() }
      comp((_, _) => h("div", [Id(outer_slot)], [
        h("div", [React, Id(inner_slot)], [h(inner.view, [], [])]),
      ]))
    },
  }
  inner.register()
  outer.register()
  let rt = Runtime::new("outer").root()
  match rt.query("outer-slot/inner-slot/a", Text) {
    Text("A") => ()
    _ => fail("expected static scope to reach first node")
  }
  match rt.query("outer-slot/inner-slot/b", Text) {
    Text("B") => ()
    _ => fail("expected static scope to reach second node")
  }
}

type SharedActions = () -> String
type SharedSessionActions = (String) -> String raise
test "runtime: instance spawn shares data and splits session state" {
  let left = ui("left", scope=Scope)
  let right = ui("right", scope=Scope)
  let value = ui("value")
  let editor: Entry[Cel[String], Cel[Int], SharedActions, SharedSessionActions] = {
    id: "test-shared-instance", title: "editor",
    data: () => cel("A"),
    session: _ => cel(0),
    actions: (_, d) => () => d.get(),
    session_actions: (_, d, s) => tail => {
      d.set(d.get() + tail)
      s.set(s.get() + 1)
      d.get() + ":" + s.get().to_string()
    },
    init: (_, _, d, s, _, _) => comp((_, _) =>
      h("div", [Id(value)], [DynP(() => Str(d.get() + ":" + s.get().to_string()))])),
  }
  let root: Entry[Unit, Unit, Unit, Unit] = {
    id: "test-shared-instance-root", title: "root", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (runtime, _, _, _, _, _) => {
      let (main, actions, main_actions) = runtime.spawn_typed(editor) catch { _ => panic() }
      let other = main.spawn(id="right") catch { _ => panic() }
      assert_eq(actions(), "A")
      assert_eq(main_actions("B"), "AB:1")
      comp((_, _) => h("div", [], [
        h("div", [Id(left)], [h(main.view, [], [])]),
        h("div", [Id(right)], [h(other.view, [], [])]),
      ]))
    },
  }
  root.register()
  let rt = Runtime::new("test-shared-instance-root").root()
  match rt.query("left/value", Text) {
    Text("AB:1") => ()
    _ => fail("expected main instance to keep local state")
  }
  match rt.query("right/value", Text) {
    Text("AB:0") => ()
    _ => fail("expected opened instance to update its local state")
  }
}

test "runtime: closing opener instance closes spawned instance" {
  let left = ui("left", scope=Scope)
  let right = ui("right", scope=Scope)
  let value = ui("value")
  let main_ref: Ref[Instance?] = Ref::new(None)
  let other_ref: Ref[Instance?] = Ref::new(None)
  let editor: Entry[Cel[String], Cel[Int], Unit, Unit] = {
    id: "test-instance-close-parent", title: "editor",
    data: () => cel("A"),
    session: _ => cel(0),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (_, _, d, s, _, _) => comp((_, _) =>
      h("div", [Id(value)], [DynP(() => Str(d.get() + ":" + s.get().to_string()))])),
  }
  let root: Entry[Unit, Unit, Unit, Unit] = {
    id: "test-instance-close-parent-root", title: "root", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (runtime, _, _, _, _, _) => {
      let main = runtime.spawn_typed(editor).0 catch { _ => panic() }
      let other = main.spawn(id="right") catch { _ => panic() }
      main_ref.val = Some(main)
      other_ref.val = Some(other)
      comp((_, _) => h("div", [], [
        h("div", [Id(left)], [h(main.view, [], [])]),
        h("div", [Id(right)], [h(other.view, [], [])]),
      ]))
    },
  }
  editor.register()
  root.register()
  let rt = Runtime::new("test-instance-close-parent-root").root()
  match rt.query("right/value", Text) {
    Text("A:0") => ()
    _ => fail("expected spawned instance to mount")
  }
  match main_ref.val { Some(main) => main.close(); None => fail("missing main instance") }
  match other_ref.val {
    Some(other) => assert_fail("spawned instance should close with opener", () => {
      ignore(other.query("value", Text))
    })
    None => fail("missing spawned instance")
  }
}

test "runtime: closing opener instance closes spawned descendants" {
  let left = ui("left", scope=Scope)
  let mid = ui("mid", scope=Scope)
  let right = ui("right", scope=Scope)
  let value = ui("value")
  let main_ref: Ref[Instance?] = Ref::new(None)
  let other_ref: Ref[Instance?] = Ref::new(None)
  let leaf_ref: Ref[Instance?] = Ref::new(None)
  let editor: Entry[Cel[String], Cel[Int], Unit, Unit] = {
    id: "test-instance-close-desc", title: "editor",
    data: () => cel("A"),
    session: _ => cel(0),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (_, _, d, s, _, _) => comp((_, _) =>
      h("div", [Id(value)], [DynP(() => Str(d.get() + ":" + s.get().to_string()))])),
  }
  let root: Entry[Unit, Unit, Unit, Unit] = {
    id: "test-instance-close-desc-root", title: "root", data: () => (), session: _ => (),
    actions: (_, _) => (),
    session_actions: (_, _, _) => (),
    init: (runtime, _, _, _, _, _) => {
      let main = runtime.spawn_typed(editor).0 catch { _ => panic() }
      let other = main.spawn(id="mid") catch { _ => panic() }
      let leaf = other.spawn(id="leaf") catch { _ => panic() }
      main_ref.val = Some(main)
      other_ref.val = Some(other)
      leaf_ref.val = Some(leaf)
      comp((_, _) => h("div", [], [
        h("div", [Id(left)], [h(main.view, [], [])]),
        h("div", [Id(mid)], [h(other.view, [], [])]),
        h("div", [Id(right)], [h(leaf.view, [], [])]),
      ]))
    },
  }
  editor.register()
  root.register()
  let rt = Runtime::new("test-instance-close-desc-root").root()
  match rt.query("right/value", Text) {
    Text("A:0") => ()
    _ => fail("expected spawned descendant to mount")
  }
  match main_ref.val { Some(main) => main.close(); None => fail("missing main instance") }
  match other_ref.val {
    Some(other) => assert_fail("direct spawned instance should close with opener", () => {
      ignore(other.query("value", Text))
    })
    None => fail("missing spawned instance")
  }
  match leaf_ref.val {
    Some(leaf) => assert_fail("spawned descendant should close with opener", () => {
      ignore(leaf.query("value", Text))
    })
    None => fail("missing spawned descendant")
  }
}

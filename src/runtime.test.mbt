test "runtime: query forwards to dom query" {
  let panel = ui("panel", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let root: Entry[Unit, Unit, Unit] = {
    id: "test-root-query", title: "root", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (_, _, _, _) => comp((_, _) =>
      h("div", [Id(panel)], [h("button", [Id(save)], [Str("Save")])])),
  }
  root.register() catch { _ => () }
  let rt = Runtime::new("test-root-query")
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

test "runtime: child instance keeps static scope and instance jump" {
  let panel = ui("panel", scope=Scope) catch { _ => panic() }
  let slot = ui("slot", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let child: Entry[Unit, Unit, Unit] = {
    id: "test-child-scope", title: "child", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (_, _, _, _) => comp((_, _) => h("button", [Id(save)], [Str("Save")])),
  }
  let root: Entry[Unit, Unit, Unit] = {
    id: "test-root-scope", title: "root", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (runtime, _, _, _) => {
      let child = runtime.instance(child).0 catch { _ => panic() }
      comp((_, _) => h("div", [Id(panel)], [h("div", [React, Id(slot)], [h(child.view, [], [])])]))
    },
  }
  child.register() catch { _ => () }
  root.register() catch { _ => () }
  let rt = Runtime::new("test-root-scope")
  match rt.query("panel/slot/save", Text) {
    Text("Save") => ()
    _ => fail("expected child instance static scope")
  }
  match rt.query("test-child-scope/save", Text) {
    Text("Save") => ()
    _ => fail("expected child instance jump path")
  }
}

pub struct RootActions { append: (String) -> String raise }
test "runtime: entry actions bind onto instance" {
  let value = ui("value") catch { _ => panic() }
  let root: Entry[Cel[String], Cel[Int], RootActions] = {
    id: "test-root-actions", title: "root",
    data: () => cel("A"),
    session: _ => cel(0),
    actions: (_, d, s) => {{
      append: tail => {
        d.set(d.get() + tail)
        s.set(s.get() + 1)
        d.get() + ":" + s.get().to_string()
      },
    }},
    init: (_, d, s, actions) => {
      assert_eq((actions.append)("B"), "AB:1")
      comp((_, _) => h("div", [Id(value)], [DynP(() => Str(d.get() + ":" + s.get().to_string()))]))
    },
  }
  root.register() catch { _ => () }
  let rt = Runtime::new("test-root-actions")
  match rt.query("value", Text) {
    Text("AB:1") => ()
    _ => fail("expected bound action result")
  }
}

test "runtime: replay re-emits current dom state after dispatch" {
  let btn = ui("btn") catch { _ => panic() }
  let value = ui("value") catch { _ => panic() }
  let text = cel("0")
  let root: Entry[Unit, Unit, Unit] = {
    id: "test-root-replay", title: "root", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (_, _, _, _) => comp((_, _) => h("div", [], [
      h("button", [Id(btn), Event(Click, _ => text.set("1"), EventCfg::new())], [Str("go")]),
      h("div", [Id(value)], [DynP(() => Str(text.get()))]),
    ])),
  }
  root.register() catch { _ => () }
  let rt = Runtime::new("test-root-replay")
  rt.dispatch("btn", Event::new(Click, Pointer({
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0, pointer_id: 0,
  }))) catch { _ => panic() }
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
  let btn = ui("btn") catch { _ => panic() }
  let value = ui("value") catch { _ => panic() }
  let text = cel("0")
  let seen = []
  let root: Entry[Unit, Unit, Unit] = {
    id: "test-root-emit", title: "root", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (_, _, _, _) => comp((_, _) => h("div", [], [
      h("button", [Id(btn), Event(Click, _ => text.set("1"), EventCfg::new())], [Str("go")]),
      h("div", [Id(value)], [DynP(() => Str(text.get()))]),
    ])),
  }
  root.register() catch { _ => () }
  let rt = Runtime::new("test-root-emit", on_cmd=cs => seen.push(cs.copy()))
  rt.dispatch("btn", Event::new(Click, Pointer({
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0, pointer_id: 0,
  }))) catch { _ => panic() }
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
  let btn = ui("btn") catch { _ => panic() }
  let value = ui("value") catch { _ => panic() }
  let text = cel("0")
  let seen = []
  let root: Entry[Unit, Unit, Unit] = {
    id: "test-root-trigger", title: "root", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (_, _, _, _) => comp((_, _) => h("div", [], [
      h("button", [Id(btn), Event(Click, _ => text.set("1"), EventCfg::new())], [Str("go")]),
      h("div", [Id(value)], [DynP(() => Str(text.get()))]),
    ])),
  }
  root.register() catch { _ => () }
  let rt = Runtime::new("test-root-trigger", on_cmd=cs => seen.push(cs.copy()))
  let node = match rt.query("btn", Node) {
    Node(node) => node
    _ => fail("expected node query result")
  }
  rt.trigger(node.id, Event::new(Click, Pointer({
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0, pointer_id: 0,
  }))) catch { _ => panic() }
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

test "runtime: nested instance jump works when inner instance renders multi root" {
  let outer_slot = ui("outer-slot", scope=Scope) catch { _ => panic() }
  let inner_slot = ui("inner-slot", scope=Scope) catch { _ => panic() }
  let a = ui("a") catch { _ => panic() }
  let b = ui("b") catch { _ => panic() }
  let inner: Entry[Unit, Unit, Unit] = {
    id: "inner", title: "inner", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (_, _, _, _) => comp((_, _) => Arr([
      h("span", [Id(a)], [Str("A")]),
      h("span", [Id(b)], [Str("B")]),
    ])),
  }
  let outer: Entry[Unit, Unit, Unit] = {
    id: "outer", title: "outer", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (runtime, _, _, _) => {
      let inner = runtime.instance(inner).0 catch { _ => panic() }
      comp((_, _) => h("div", [Id(outer_slot)], [
        h("div", [React, Id(inner_slot)], [h(inner.view, [], [])]),
      ]))
    },
  }
  inner.register() catch { _ => () }
  outer.register() catch { _ => () }
  let rt = Runtime::new("outer")
  match rt.query("outer-slot/inner-slot/a", Text) {
    Text("A") => ()
    _ => fail("expected static scope to reach first node")
  }
  match rt.query("outer-slot/inner-slot/b", Text) {
    Text("B") => ()
    _ => fail("expected static scope to reach second node")
  }
  match rt.query("inner/a", Text) {
    Text("A") => ()
    _ => fail("expected instance jump to reach first node")
  }
  match rt.query("inner/b", Text) {
    Text("B") => ()
    _ => fail("expected instance jump to reach second node")
  }
}

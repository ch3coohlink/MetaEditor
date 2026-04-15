test "runtime: query forwards to dom query" {
  let panel = ui("panel", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let root : Entry[Unit, Unit, Unit] = {
    id: "root", title: "root", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (_, _, _, _) => comp((_, _) =>
      h("div", [Id(panel)], [h("button", [Id(save)], [Str("Save")])])),
  }
  let rt = Runtime::new(root)
  match rt.query("panel/save", Text) {
    Text("Save") => ()
    _ => fail("expected runtime query text result")
  }
}

test "runtime: node query decodes from json" {
  let q1 : NodeQuery = @json.from_json("text")
  let q2 : NodeQuery = @json.from_json({ "kind": "prop", "value": "click" })
  match q1 {
    Text => ()
    _ => fail("expected text query")
  }
  match q2 {
    Prop("click") => ()
    _ => fail("expected prop query")
  }
}

test "runtime: child instance opens name scope" {
  let panel = ui("panel", scope=Scope) catch { _ => panic() }
  let save = ui("save") catch { _ => panic() }
  let child : Entry[Unit, Unit, Unit] = {
    id: "child", title: "child", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (_, _, _, _) => comp((_, _) => h("button", [Id(save)], [Str("Save")])),
  }
  let root : Entry[Unit, Unit, Unit] = {
    id: "root", title: "root", data: () => (), session: _ => (),
    actions: (_, _, _) => (),
    init: (runtime, _, _, _) => {
      let child = runtime.instance(child).0 catch { _ => panic() }
      comp((_, _) => h("div", [Id(panel)], [child.child()]))
    },
  }
  let rt = Runtime::new(root)
  match rt.query("panel/child/save", Text) {
    Text("Save") => ()
    _ => fail("expected child instance name scope")
  }
}

pub struct RootActions { append: (String) -> String raise }
test "runtime: entry actions bind onto instance" {
  let value = ui("value") catch { _ => panic() }
  let root: Entry[Cel[String], Cel[Int], RootActions] = {
    id: "root", title: "root",
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
  let rt = Runtime::new(root)
  match rt.query("value", Text) {
    Text("AB:1") => ()
    _ => fail("expected bound action result")
  }
}

test "runtime: host start entry action opens window" {
  let rt = Runtime::new(host)
  rt.dispatch("entries/0/entry", Mouse({
    kind: Click,
    mod: { ctrl: false, shift: false, alt: false, meta: false },
    x: 0, y: 0, button: 0, buttons: 0,
  })) catch { _ => panic() }
  match rt.query("windows/0/title", Text) {
    Text("Demo") => ()
    _ => fail("expected host action to open demo window")
  }
}

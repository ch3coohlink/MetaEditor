test "native: node query decodes from derive json" {
  let q1: @src.NodeQuery = from_json("Text")
  let q2: @src.NodeQuery = from_json(parse("[\"Attr\",\"title\"]"))
  match q1 {
    Text => ()
    _ => fail("expected text query")
  }
  match q2 {
    Attr("title") => ()
    _ => fail("expected attr query")
  }
}

test "native: dom event decodes from json" {
  let ev: @src.Event = from_json(parse(
    "{\"kind\":\"Click\",\"data\":[\"Pointer\",{\"mod\":{\"ctrl\":false,\"shift\":false,\"alt\":false,\"meta\":false},\"x\":0,\"y\":0,\"vx\":0,\"vy\":0,\"button\":0,\"buttons\":0,\"pointer_id\":0}]}"
  ))
  assert_eq(ev.kind.to_string(), "onclick")
}

test "native: event cfg json carries capture flag" {
  let json = @src.EventCfg::new(capture=true).to_json()
  match json {
    Object(fields) => {
      assert_eq(fields.get("capture"), Some(true.to_json()))
      assert_eq(fields.get("prevent"), Some(false.to_json()))
      assert_eq(fields.get("stop"), Some(false.to_json()))
    }
    _ => fail("expected event cfg object")
  }
}

test "native: client read decodes protocol bodies" {
  match Client::read("{\"id\":2,\"body\":[\"Cli\",\"ok\\n\"]}", 2) {
    Array([String("Cli"), String("ok\n")]) => ()
    _ => fail("expected cli body")
  }
  match Client::read("{\"id\":3,\"body\":[\"Query\",{\"kind\":\"text\",\"text\":\"Save\"}]}", 3) {
    Array([String("Query"), Object(_)]) => ()
    _ => fail("expected query body")
  }
  @src.assert_fail("err body should raise", () =>
    ignore(Client::read("{\"id\":4,\"body\":[\"Err\",\"bad\"]}", 4)))
}

test "native: reset rebuilds runtime root" {
  let rt = Runtime::new(root="host")
  let click: @src.Event = from_json(parse(
    "{\"kind\":\"Click\",\"data\":[\"Pointer\",{\"mod\":{\"ctrl\":false,\"shift\":false,\"alt\":false,\"meta\":false},\"x\":0,\"y\":0,\"vx\":0,\"vy\":0,\"button\":0,\"buttons\":0,\"pointer_id\":0}]}"
  ))
  let q: @src.NodeQuery = from_json("Text")
  rt.rt.dispatch("entries/0/entry", click) catch { _ => panic() }
  ignore(rt.rt.query("windows/0/title", q))
  rt.reset("host")
  @src.assert_fail("window should be cleared after reset", () => ignore(rt.rt.query("windows/0/title", q)))
}

test "native: cmd help" {
  let help = CMD::new(["service", "help"]).help()
  assert_true(help.contains("usage: service [COMMAND] [ARGS...]"))
  assert_true(help.contains("dispatch PATH EVENT_JSON"))
  assert_true(help.contains("--help"))
  assert_true(!help.has_suffix("\n"))
}

test "native: cmd parses --help" {
  let cmd = CMD::new(["service", "--help"])
  assert_true(cmd.args.has("--help"))
}

test "native: cli local output has no trailing newline" {
  let rt = Runtime::new(root="host")
  assert_eq(rt.status_local(), "running http://localhost:8080")
  assert_eq(rt.stop_local(), "stopped")
  assert_eq(CMD::new(["service", "reset"], rt=Some(rt)).reset(), "reset")
}

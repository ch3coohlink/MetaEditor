priv struct EntryTestData {
  mut log : String
}

priv struct EntryTestSession {}

fn action_test_entry() -> Entry[EntryTestData, EntryTestSession, Unit] {
  {
    id: "action_test",
    name: Some("Action Test"),
    icon: Some("ACT"),
    new_data: fn() { { log: "" } },
    new_session: fn() { EntryTestSession::{} },
    view: fn(_, _) {
      comp(fn(attrs, children) {
        ignore(attrs)
        ignore(children)
        Null
      })
    },
    actions: [{
      id: "set",
      title: Some("Set log"),
      desc: Some("Store string/int/bool args in log."),
      args: [
        {
          name: "name",
          kind: ActionArgKind::String,
          desc: Some("User name."),
          optional: false,
        },
        {
          name: "count",
          kind: ActionArgKind::Int,
          desc: Some("Count value."),
          optional: false,
        },
        {
          name: "flag",
          kind: ActionArgKind::Bool,
          desc: Some("Optional bool flag."),
          optional: true,
        },
      ],
      run: (ctx, args) => {
        match args {
          [ActionArg::String(name), ActionArg::Int(count)] => {
            ctx.data.mutate(v => {
              v.log = "\{name}:\{count}:none"
            })
            ctx.data.get().log
          }
          [ActionArg::String(name), ActionArg::Int(count), ActionArg::Bool(flag)] => {
            ctx.data.mutate(v => {
              v.log = "\{name}:\{count}:\{flag}"
            })
            ctx.data.get().log
          }
          _ => fail("unexpected args")
        }
      },
    }],
  }
}

test "entry: action dispatch uses ActionSpec table" {
  let runtime = new_instance_runtime()
  register_entry(runtime, action_test_entry())
  let root = no_raise(() => boot_instance(runtime, "action_test"))
  let result = no_raise(() => call_instance(
    runtime,
    root,
    "set",
    [ActionArg::String("alice"), ActionArg::Int(7), ActionArg::Bool(true)],
  ))
  assert_eq(result, "alice:7:true")
}

test "entry: query parsing walks runtime tree by id and index" {
  let runtime = new_instance_runtime()
  register_default_entries(runtime)
  let host = no_raise(() => boot_instance(runtime, "host"))
  let demo = no_raise(() => boot_instance(runtime, "demo", parent=Some(host)))
  let nested = no_raise(() => boot_instance(runtime, "host", parent=Some(host)))
  assert_eq(instance_query(runtime, host), "host#1")
  assert_eq(instance_query(runtime, demo), "host#1/demo#1")
  assert_eq(instance_query(runtime, nested), "host#1/host#1")
  assert_eq(lookup_instance(runtime, "host#1/demo#1") is Some(_), true)
  assert_eq(lookup_instance(runtime, "host#1/host#1") is Some(_), true)
  assert_eq(lookup_instance(runtime, "host#1/demo") is None, true)
  assert_eq(lookup_instance(runtime, "host#1/demo#2") is None, true)
  assert_eq(lookup_instance(runtime, "host#1/demo#x") is None, true)
}

test "entry: action help text reflects current ActionSpec" {
  let runtime = new_instance_runtime()
  register_entry(runtime, action_test_entry())
  let root = no_raise(() => boot_instance(runtime, "action_test"))
  let help = action_help_text(instance_actions(runtime, root))
  assert_true(help.contains("set <name:string> <count:int> [flag:bool]"))
  assert_true(help.contains("Store string/int/bool args in log."))
  assert_true(help.contains("flag: bool (optional)"))
}

test "entry: shell args parse string int bool optional quotes and escapes" {
  let tokens = no_raise(() => split_shell_args("alpha 12 true \"two words\" a\\ b"))
  assert_eq(tokens, ["alpha", "12", "true", "two words", "a b"])
  let args = no_raise(() => parse_action_args(
    [
      {
        name: "name",
        kind: ActionArgKind::String,
        desc: None,
        optional: false,
      },
      {
        name: "count",
        kind: ActionArgKind::Int,
        desc: None,
        optional: false,
      },
      {
        name: "flag",
        kind: ActionArgKind::Bool,
        desc: None,
        optional: true,
      },
    ],
    ["alpha", "12", "true"],
  ))
  match args {
    [ActionArg::String("alpha"), ActionArg::Int(12), ActionArg::Bool(true)] => ()
    _ => fail("unexpected parsed args")
  }
  let optional = no_raise(() => parse_action_args(
    [
      {
        name: "name",
        kind: ActionArgKind::String,
        desc: None,
        optional: false,
      },
      {
        name: "flag",
        kind: ActionArgKind::Bool,
        desc: None,
        optional: true,
      },
    ],
    ["beta"],
  ))
  match optional {
    [ActionArg::String("beta")] => ()
    _ => fail("optional arg should be omitted")
  }
}

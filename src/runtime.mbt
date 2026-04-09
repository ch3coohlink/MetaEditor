pub struct Runtime {
  instance_runtime : InstanceRuntime
  dom_state : DomState
  mounted_roots : Array[VNode]
  mut mounted_styles : Array[VNode]
  roots : Array[InstanceRef]
}

priv suberror RuntimeErr {
  Fail(String)
}

fn runtime_err(message : String) -> RuntimeErr {
  RuntimeErr::Fail(message)
}

fn default_instance_id(runtime : Runtime) -> InstanceRef raise {
  match runtime.roots {
    [root] => root
    [] => raise runtime_err("no top-level instance")
    _ => raise runtime_err("multiple top-level instances, pass INSTANCE_ID explicitly")
  }
}

fn resolve_instance_id(runtime : Runtime, instance : String) -> InstanceRef raise {
  let instance = instance.trim().to_string()
  if instance == "" { default_instance_id(runtime) } else { instance }
}

fn instance_help_text(runtime : Runtime, instance_id : String) -> String raise {
  let instance = resolve_instance_id(runtime, instance_id)
  let actions = runtime_instance_actions(runtime, instance) catch {
    err => raise runtime_err("\{err}")
  }
  if actions.length() == 0 {
    return "Instance \{instance}\nNo actions\n"
  }
  "Instance \{instance}\n" + action_help_text(actions) + "\n"
}

fn exec_instance_action(runtime : Runtime, ctx : CmdContext) -> String raise {
  let parts = ctx.args
  if parts.length() < 2 {
    raise runtime_err("Usage: exec INSTANCE_ID ACTION [ARGS...]")
  }
  let instance = resolve_instance_id(runtime, parts[0])
  let action = parts[1]
  let infos = runtime_instance_actions(runtime, instance) catch {
    err => raise runtime_err("\{err}")
  }
  let mut info : ActionInfo? = None
  for item in infos {
    if item.id == action {
      info = Some(item)
      break
    }
  }
  let info = match info {
    Some(info) => info
    None => raise runtime_err("Unknown action: \{action}")
  }
  let tokens : Array[String] = []
  for i = 2; i < parts.length(); i = i + 1 {
    tokens.push(parts[i])
  }
  for f in ctx.flags {
    if f.1 == "true" {
      tokens.push("--\{f.0}")
    } else {
      tokens.push("--\{f.0}")
      tokens.push(f.1)
    }
  }
  let action_ctx = parse_cmd(info.flags, tokens) catch { err => raise runtime_err("\{err}") }
  let args = parse_action_args(info.args, action_ctx.args) catch { err => raise runtime_err("\{err}") }
  call_instance(runtime.instance_runtime, instance, action, args, action_ctx) catch {
    err => raise runtime_err("\{err}")
  }
}

pub fn new_runtime(
  env? : HostEnv = new_host_env(),
  on_batch? : (Array[Json]) -> Unit = fn(_) {},
  on_cmds? : (Array[DomCmd]) -> Unit = fn(_) {},
) -> Runtime {
  let instance_runtime = new_instance_runtime()
  register_default_entries(instance_runtime, env~)
  let root = boot_instance(instance_runtime, "host") catch { _ => panic() }
  let runtime : Runtime = {
    instance_runtime,
    dom_state: new_dom_state(),
    mounted_roots: [],
    mounted_styles: [],
    roots: [root],
  }
  init_bridge(runtime.dom_state, on_batch, on_cmds~)
  runtime
}

pub fn runtime_roots(runtime : Runtime) -> Array[InstanceRef] {
  runtime.roots.copy()
}

pub fn runtime_query(runtime : Runtime, instance : InstanceRef) -> Instance raise {
  query(runtime.instance_runtime, instance) catch { err => raise runtime_err("\{err}") }
}

pub fn runtime_resolve_query(runtime : Runtime, query : String) -> Int raise {
  ignore(runtime)
  let query = query.trim().to_string()
  if query == "" {
    raise runtime_err("query is empty")
  }
  match query_node(query) {
    Some(id) => id
    None => raise runtime_err("query not found: \{query}")
  }
}

pub fn runtime_query_tree(runtime : Runtime, instance : InstanceRef, depth? : Int = 1) -> InstanceTree raise {
  query_tree(runtime.instance_runtime, instance, depth~) catch { err => raise runtime_err("\{err}") }
}

pub fn runtime_instance_actions(runtime : Runtime, instance_id : String) -> Array[ActionInfo] raise {
  let instance = resolve_instance_id(runtime, instance_id)
  let _ = query(runtime.instance_runtime, instance) catch {
    err => raise runtime_err("\{err}")
  }
  instance_actions(runtime.instance_runtime, instance)
}

pub fn runtime_render(runtime : Runtime) -> Unit {
  let _ = try {
    scope(fn() {
      for style in runtime.mounted_styles {
        remove(style)
      }
      runtime.mounted_styles = realize_registered_styles(runtime.dom_state)
      for root in runtime.mounted_roots {
        remove(root)
      }
      runtime.mounted_roots.clear()
      for root in runtime.roots {
        let node = realize(
          runtime.dom_state,
          h(render_instance(runtime.instance_runtime, root), [], []),
        )
        runtime.mounted_roots.push(node)
        emit(runtime.dom_state, Append(dom_root_body, node.id))
      }
    })
  } catch {
    _ => fn() {}
  }
  try_flush()
}

pub fn runtime_set_roots(runtime : Runtime, entry_ids : Array[String]) -> Array[InstanceRef] raise {
  let old_roots = runtime.roots.copy()
  for root in old_roots {
    close_instance(runtime.instance_runtime, root) catch {
      err => raise runtime_err("\{err}")
    }
  }
  runtime.roots.clear()
  for entry_id in entry_ids {
    let root = boot_instance(runtime.instance_runtime, entry_id) catch {
      err => raise runtime_err("\{err}")
    }
    runtime.roots.push(root)
  }
  runtime_render(runtime)
  runtime_roots(runtime)
}

pub fn runtime_commands() -> Array[CmdDef[(Runtime, CmdContext) -> String raise]] {
  [
    {
      name: "help",
      usage: "[INSTANCE_ID]",
      desc: "Show service help or one instance action help.",
      flags: [],
      allow_unknown: false,
      action: (runtime, ctx) => instance_help_text(runtime, ctx.args.iter().join(" "))
    },
    {
      name: "exec",
      usage: "INSTANCE_ID ACTION [ARGS...]",
      desc: "Run one instance action.",
      flags: [],
      allow_unknown: true,
      action: (runtime, ctx) => exec_instance_action(runtime, ctx)
    },
    {
      name: "roots",
      usage: "[ENTRY_ID...]",
      desc: "Replace top-level instances.",
      flags: [],
      allow_unknown: false,
      action: (runtime, ctx) => {
        let roots = runtime_set_roots(runtime, ctx.args)
        let txt = roots.iter().join(", ")
        if roots.length() == 0 { "roots cleared\n" } else { "roots \{txt}\n" }
      }
    }
  ]
}

pub fn runtime_run(runtime : Runtime, cmd : String, ctx : CmdContext) -> String raise {
  for c in runtime_commands() {
    if c.name == cmd {
      return (c.action)(runtime, ctx)
    }
  }
  raise runtime_err("Unknown command: \{cmd}")
}

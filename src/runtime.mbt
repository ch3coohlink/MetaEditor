pub struct Runtime {
  instance_runtime : InstanceRuntime
  dom_state : DomState
  mounted_roots : Array[VNode]
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

fn parse_root_entry_ids(text : String) -> Array[String] raise {
  let out : Array[String] = []
  for part in split_shell_args(text) {
    let entry_id = part.trim().to_string()
    if entry_id == "" {
      raise runtime_err("entry id is empty")
    }
    out.push(entry_id)
  }
  out
}

fn instance_help_text(runtime : Runtime, instance_id : String) -> String raise {
  let instance = resolve_instance_id(runtime, instance_id)
  let info = query(runtime.instance_runtime, instance) catch {
    err => raise runtime_err("\{err}")
  }
  let actions = instance_actions(runtime.instance_runtime, instance)
  if actions.length() == 0 {
    return "Instance \{info.id}\nNo actions\n"
  }
  "Instance \{info.id}\n" + action_help_text(actions) + "\n"
}

fn exec_instance_action(runtime : Runtime, text : String) -> String raise {
  let parts = split_shell_args(text)
  if parts.length() < 2 {
    raise runtime_err("Usage: exec INSTANCE_ID ACTION [ARGS...]")
  }
  let instance = resolve_instance_id(runtime, parts[0])
  let _ = query(runtime.instance_runtime, instance) catch {
    err => raise runtime_err("\{err}")
  }
  let action = parts[1]
  let infos = instance_actions(runtime.instance_runtime, instance)
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
  let args = parse_action_args(info.args, tokens) catch { err => raise runtime_err("\{err}") }
  call_instance(runtime.instance_runtime, instance, action, args) catch {
    err => raise runtime_err("\{err}")
  }
}

pub fn new_runtime(
  env? : HostEnv = new_host_env(),
  on_batch? : (Array[Json]) -> Unit = fn(_) {},
) -> Runtime {
  let instance_runtime = new_instance_runtime()
  register_default_entries(instance_runtime, env~)
  let root = boot_instance(instance_runtime, "host") catch { _ => panic() }
  let runtime : Runtime = {
    instance_runtime,
    dom_state: new_dom_state(),
    mounted_roots: [],
    roots: [root],
  }
  init_bridge(runtime.dom_state, on_batch)
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

pub fn runtime_render(runtime : Runtime) -> Unit {
  emit_registered_css(runtime.dom_state)
  let _ = try {
    scope(fn() {
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
        emit(runtime.dom_state, Append(0, node.id))
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

pub fn runtime_run(runtime : Runtime, cmd : String, arg : String) -> String raise {
  match cmd {
    "help" => instance_help_text(runtime, arg)
    "exec" => exec_instance_action(runtime, arg)
    "roots" => {
      let roots = runtime_set_roots(runtime, parse_root_entry_ids(arg))
      if roots.length() == 0 {
        "roots cleared\n"
      } else {
        let text = roots.iter().join(", ")
        "roots \{text}\n"
      }
    }
    _ => raise runtime_err("Unknown command: \{cmd}")
  }
}

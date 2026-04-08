pub(all) enum ActionArgKind {
  String
  Int
  Bool
}

pub(all) enum ActionArg {
  String(String)
  Int(Int)
  Bool(Bool)
}

pub(all) struct ActionArgSpec {
  name : String
  kind : ActionArgKind
  desc : String?
  optional : Bool
}

pub(all) struct ActionInfo {
  id : String
  title : String?
  desc : String?
  args : Array[ActionArgSpec]
}

pub(all) struct InstanceCtx[D, S, X] {
  data : Cel[D]
  session : Cel[S]
  extra : X
}

pub type ActionBind = (String, Array[ActionArg]) -> Prop
pub type InstanceRef = String

pub(all) struct ActionSpec[D, S, X] {
  id : String
  title : String?
  desc : String?
  args : Array[ActionArgSpec]
  run : (InstanceCtx[D, S, X], Array[ActionArg]) -> String raise
}

pub(all) struct Entry[D, S, X] {
  id : String
  name : String?
  icon : String?
  new_data : () -> D
  new_session : () -> S
  view : (InstanceCtx[D, S, X], ActionBind) -> Comp
  actions : Array[ActionSpec[D, S, X]]
}

pub(all) struct EntryInfo {
  id : String
  name : String
  icon : String
}

pub(all) struct Instance {
  id : InstanceRef
  entry : String
  title : String
  icon : String
}

pub(all) struct InstanceTree {
  instance : Instance
  children : Array[InstanceTree]
}

priv struct ActionRunner {
  run : (Array[ActionArg]) -> String raise
}

struct RuntimeNode {
  info : Instance
  parent : InstanceRef?
  attach_child : (InstanceRef) -> Unit
  children : () -> Array[InstanceRef]
  detach_child : (InstanceRef) -> Unit
  render : () -> Comp
  actions : Map[String, ActionRunner]
  action_infos : Array[ActionInfo]
}

struct EntryFactory {
  info : EntryInfo
  create : (InstanceRuntime, InstanceRef, InstanceRef?) -> RuntimeNode
}
pub(all) struct HostHooks[D, S, X] {
  extra : (InstanceRuntime, InstanceRef) -> X
  attach_child : (InstanceRuntime, InstanceRef, InstanceCtx[D, S, X], InstanceRef) -> Unit
  children : (InstanceRuntime, InstanceRef, InstanceCtx[D, S, X]) -> Array[InstanceRef]
  detach_child : (InstanceRuntime, InstanceRef, InstanceCtx[D, S, X], InstanceRef) -> Unit
}

pub struct InstanceRuntime {
  entry_ids : Array[String]
  entries : Map[String, EntryFactory]
  instances : Map[String, RuntimeNode]
  instance_counts : Map[String, Int]
}

priv suberror InstanceErr {
  Fail(String)
}

pub fn new_instance_runtime() -> InstanceRuntime {{
  entry_ids: [],
  entries: Map::new(),
  instances: Map::new(),
  instance_counts: Map::new(),
}}

fn arg_kind_name(kind : ActionArgKind) -> String {
  match kind {
    ActionArgKind::String => "string"
    ActionArgKind::Int => "int"
    ActionArgKind::Bool => "bool"
  }
}

fn arg_usage(spec : ActionArgSpec) -> String {
  let head = "\{spec.name}:\{arg_kind_name(spec.kind)}"
  if spec.optional { "[\{head}]" } else { "<\{head}>" }
}

fn instance_err(message : String) -> InstanceErr {
  InstanceErr::Fail(message)
}

fn node_or_panic(runtime : InstanceRuntime, instance : InstanceRef) -> RuntimeNode {
  match runtime.instances.get(instance) {
    Some(node) => node
    None => panic()
  }
}

fn lookup_node(runtime : InstanceRuntime, instance : InstanceRef) -> RuntimeNode? {
  runtime.instances.get(instance)
}

fn require_node(runtime : InstanceRuntime, instance : InstanceRef) -> RuntimeNode raise {
  match lookup_node(runtime, instance) {
    Some(node) => node
    None => raise instance_err("instance not found: \{instance}")
  }
}

fn next_instance_id(runtime : InstanceRuntime, entry : String) -> InstanceRef {
  let count = match runtime.instance_counts.get(entry) {
    Some(current) => current + 1
    None => 1
  }
  runtime.instance_counts.set(entry, count)
  "\{entry}-\{count}"
}

fn close_tree(runtime : InstanceRuntime, instance : InstanceRef) -> Unit {
  let node = match runtime.instances.get(instance) {
    Some(node) => node
    None => return
  }
  let children = (node.children)()
  for child in children {
    close_tree(runtime, child)
  }
  if node.parent is Some(parent) {
    let parent_node = node_or_panic(runtime, parent)
    (parent_node.detach_child)(instance)
  }
  runtime.instances.remove(instance)
}

fn query_tree_inner(runtime : InstanceRuntime, instance : InstanceRef, depth : Int) -> InstanceTree raise {
  let node = require_node(runtime, instance)
  let children : Array[InstanceTree] = []
  if depth > 0 {
    let child_ids = (node.children)()
    child_ids.sort()
    for child in child_ids {
      children.push(query_tree_inner(runtime, child, depth - 1))
    }
  }
  {
    instance: node.info,
    children,
  }
}

fn[D, S, X] action_info(spec : ActionSpec[D, S, X]) -> ActionInfo {
  {
    id: spec.id,
    title: spec.title,
    desc: spec.desc,
    args: spec.args,
  }
}

fn[D, S, X] entry_info(entry : Entry[D, S, X]) -> EntryInfo {
  let name = entry.name.unwrap_or(entry.id)
  {
    id: entry.id,
    name,
    icon: entry.icon.unwrap_or(name),
  }
}

pub fn action_usage(info : ActionInfo) -> String {
  let out : Array[String] = [info.id]
  for arg in info.args {
    out.push(arg_usage(arg))
  }
  out.iter().join(" ")
}

pub fn action_help(info : ActionInfo) -> String {
  let lines : Array[String] = [action_usage(info)]
  match info.title {
    Some(title) => if title != "" { lines.push("  \{title}") }
    None => ()
  }
  if info.desc is Some(desc) { if desc != "" { lines.push("  \{desc}") } }
  for arg in info.args {
    let optional = if arg.optional { "optional" } else { "required" }
    let desc = arg.desc.unwrap_or("")
    let tail = if desc == "" { "" } else { " - \{desc}" }
    lines.push("  \{arg.name}: \{arg_kind_name(arg.kind)} (\{optional})\{tail}")
  }
  lines.iter().join("\n")
}

pub fn action_help_text(actions : Array[ActionInfo]) -> String {
  if actions.length() == 0 { return "" }
  let out : Array[String] = []
  for i = 0; i < actions.length(); i = i + 1 {
    if i > 0 {
      out.push("")
    }
    out.push(action_help(actions[i]))
  }
  out.iter().join("\n")
}

fn parse_bool_arg(token : String) -> Bool? {
  match token {
    "true" => Some(true)
    "false" => Some(false)
    _ => None
  }
}

fn parse_arg(spec : ActionArgSpec, token : String) -> ActionArg? {
  match spec.kind {
    ActionArgKind::String => Some(ActionArg::String(token))
    ActionArgKind::Int =>
      Some(ActionArg::Int(@string.parse_int(token) catch { _ => return None }))
    ActionArgKind::Bool =>
      match parse_bool_arg(token) {
        Some(value) => Some(ActionArg::Bool(value))
        None => None
      }
  }
}

pub fn parse_action_args(specs : Array[ActionArgSpec], tokens : Array[String]) -> Array[ActionArg] raise {
  let out : Array[ActionArg] = []
  let mut ti = 0
  for spec in specs {
    if ti >= tokens.length() {
      if spec.optional {
        continue
      } else {
        raise instance_err("missing argument: \{spec.name}")
      }
    }
    match parse_arg(spec, tokens[ti]) {
      Some(arg) => {
        out.push(arg)
        ti = ti + 1
      }
      None => raise instance_err("invalid \{arg_kind_name(spec.kind)}: \{tokens[ti]}")
    }
  }
  if ti != tokens.length() {
    raise instance_err("too many arguments")
  }
  out
}

pub fn runtime_entry_infos(runtime : InstanceRuntime) -> Array[EntryInfo] {
  let out : Array[EntryInfo] = []
  for id in runtime.entry_ids {
    match runtime.entries.get(id) {
      Some(factory) => out.push(factory.info)
      None => ()
    }
  }
  out
}

pub fn query(runtime : InstanceRuntime, instance : InstanceRef) -> Instance raise {
  require_node(runtime, instance).info
}

pub fn query_tree(runtime : InstanceRuntime, instance : InstanceRef, depth? : Int = 1) -> InstanceTree raise {
  query_tree_inner(runtime, instance, if depth < 0 { 0 } else { depth })
}

pub fn render_instance(runtime : InstanceRuntime, instance : InstanceRef) -> Comp {
  match lookup_node(runtime, instance) {
    Some(node) => (node.render)()
    None => abort("instance not found")
  }
}

pub fn instance_actions(runtime : InstanceRuntime, instance : InstanceRef) -> Array[ActionInfo] {
  match lookup_node(runtime, instance) {
    Some(node) => node.action_infos
    None => []
  }
}

pub fn call_instance(
  runtime : InstanceRuntime,
  instance : InstanceRef,
  action : String,
  args : Array[ActionArg]
) -> String raise {
  let node = require_node(runtime, instance)
  match node.actions.get(action) {
    Some(runner) => (runner.run)(args)
    None => raise instance_err("unknown action: \{action}")
  }
}

pub fn close_instance(runtime : InstanceRuntime, instance : InstanceRef) -> Unit raise {
  ignore(require_node(runtime, instance))
  close_tree(runtime, instance)
}

pub fn boot_instance(
  runtime : InstanceRuntime,
  entry_id : String,
  parent? : InstanceRef? = None,
) -> InstanceRef raise {
  let entry_id = entry_id.trim().to_string()
  if entry_id == "" {
    raise instance_err("entry id is empty")
  }
  if parent is Some(parent_ref) && lookup_node(runtime, parent_ref) is None {
    raise instance_err("parent instance not found")
  }
  let factory = match runtime.entries.get(entry_id) {
    Some(factory) => factory
    None => raise instance_err("entry not found: \{entry_id}")
  }
  let instance = next_instance_id(runtime, entry_id)
  let node = (factory.create)(runtime, instance, parent)
  runtime.instances.set(instance, node)
  match parent {
    Some(parent_ref) => {
      let parent_node = node_or_panic(runtime, parent_ref)
      (parent_node.attach_child)(instance)
    }
    None => ()
  }
  instance
}

fn[D, S] default_host_hooks() -> HostHooks[D, S, Unit] {
  {
    extra: fn(_, _) { () },
    attach_child: fn(_, _, _, _) { () },
    children: fn(_, _, _) { [] },
    detach_child: fn(_, _, _, _) { () },
  }
}

pub fn[D, S] register_entry(
  runtime : InstanceRuntime,
  entry : Entry[D, S, Unit],
) -> Unit {
  register_entry_with_hooks(runtime, entry, default_host_hooks())
}

pub fn[D, S, X] register_entry_with_hooks(
  runtime : InstanceRuntime,
  entry : Entry[D, S, X],
  hooks : HostHooks[D, S, X],
) -> Unit {
  if runtime.entries.get(entry.id) is Some(_) { return }
  let info = entry_info(entry)
  runtime.entry_ids.push(entry.id)
  runtime.entries.set(entry.id, {
    info,
    create: fn(runtime, instance, parent) {
      let data = cel((entry.new_data)())
      let session = cel((entry.new_session)())
      let ctx : InstanceCtx[D, S, X] = {
        data,
        session,
        extra: (hooks.extra)(runtime, instance),
      }
      let bind_action : ActionBind = (id, args) => E(fn(_) raise {
        ignore(call_instance(runtime, instance, id, args))
      })
      let actions = Map::new()
      let action_infos : Array[ActionInfo] = []
      for action in entry.actions {
        let info = action_info(action)
        action_infos.push(info)
        actions.set(action.id, { run: args => (action.run)(ctx, args) })
      }
      {
        info: {
          id: instance,
          entry: entry.id,
          title: info.name,
          icon: info.icon,
        },
        parent,
        attach_child: child => (hooks.attach_child)(runtime, instance, ctx, child),
        children: fn() { (hooks.children)(runtime, instance, ctx) },
        detach_child: child => (hooks.detach_child)(runtime, instance, ctx, child),
        render: fn() { (entry.view)(ctx, bind_action) },
        actions,
        action_infos,
      }
    },
  })
}

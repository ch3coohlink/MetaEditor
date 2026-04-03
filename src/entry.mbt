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
  id : String
  index : Int
  title : String
  icon : String
}

pub(all) struct InstanceRef {
  key : Int
} derive(Eq, Hash, Show)

priv struct ActionRunner {
  run : (Array[ActionArg]) -> String raise
}

struct RuntimeNode {
  info : Instance
  parent : InstanceRef?
  children : Map[String, Array[InstanceRef]]
  render : () -> Comp
  actions : Map[String, ActionRunner]
  action_infos : Array[ActionInfo]
}

struct EntryFactory {
  info : EntryInfo
  create : (InstanceRuntime, InstanceRef, InstanceRef?, Int) -> RuntimeNode
}

pub struct InstanceRuntime {
  entry_ids : Array[String]
  entries : Map[String, EntryFactory]
  instances : Map[Int, RuntimeNode]
  roots : Map[String, Array[InstanceRef]]
  child_counts : Map[String, Int]
  mut next_instance_key : Int
}

priv suberror InstanceErr {
  Fail(String)
}

pub fn new_instance_runtime() -> InstanceRuntime {{
  entry_ids: [],
  entries: Map::new(),
  instances: Map::new(),
  roots: Map::new(),
  child_counts: Map::new(),
  next_instance_key: 1,
}}

fn counter_key(parent : InstanceRef?, entry_id : String) -> String {
  match parent {
    Some(parent) => "\{parent.key}\n\{entry_id}"
    None => "\n\{entry_id}"
  }
}

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

fn parse_query_part(part : String) -> (String, Int)? {
  let part = part.trim().to_string()
  if part == "" { return None }
  let mut sharp = -1
  for i = 0; i < part.length(); i = i + 1 {
    if part[i:i + 1].to_string() == "#" {
      sharp = i
    }
  }
  if sharp < 1 || sharp + 1 >= part.length() { return None }
  let id = part[:sharp].to_string()
  let index = @string.parse_int(part[sharp + 1:].to_string()) catch { _ => -1 }
  if id == "" || index <= 0 { return None }
  Some((id, index))
}

fn child_refs(node : RuntimeNode, id : String) -> Array[InstanceRef] {
  match node.children.get(id) {
    Some(items) => items
    None => []
  }
}

fn root_refs(runtime : InstanceRuntime, id : String) -> Array[InstanceRef] {
  match runtime.roots.get(id) {
    Some(items) => items
    None => []
  }
}

fn set_child_refs(node : RuntimeNode, id : String, items : Array[InstanceRef]) -> Unit {
  if items.length() == 0 {
    node.children.remove(id)
  } else {
    node.children.set(id, items)
  }
}

fn set_root_refs(runtime : InstanceRuntime, id : String, items : Array[InstanceRef]) -> Unit {
  if items.length() == 0 {
    runtime.roots.remove(id)
  } else {
    runtime.roots.set(id, items)
  }
}

fn remove_ref(items : Array[InstanceRef], target : InstanceRef) -> Array[InstanceRef] {
  let out : Array[InstanceRef] = []
  for item in items {
    if item != target {
      out.push(item)
    }
  }
  out
}

fn node_or_panic(runtime : InstanceRuntime, instance : InstanceRef) -> RuntimeNode {
  match runtime.instances.get(instance.key) {
    Some(node) => node
    None => panic()
  }
}

fn append_child(runtime : InstanceRuntime, parent : InstanceRef?, child : InstanceRef, id : String) -> Unit {
  match parent {
    Some(parent) => {
      let node = node_or_panic(runtime, parent)
      let items = child_refs(node, id)
      items.push(child)
      node.children.set(id, items)
    }
    None => {
      let items = root_refs(runtime, id)
      items.push(child)
      runtime.roots.set(id, items)
    }
  }
}

fn lookup_step(runtime : InstanceRuntime, parent : InstanceRef?, id : String, index : Int) -> InstanceRef? {
  let items = match parent {
    Some(parent) => child_refs(node_or_panic(runtime, parent), id)
    None => root_refs(runtime, id)
  }
  if index <= 0 || index > items.length() { return None }
  Some(items[index - 1])
}

fn lookup_ref(runtime : InstanceRuntime, query : String, start? : InstanceRef? = None) -> InstanceRef? {
  let parts = query
    .split("/")
    .collect()
    .map(part => part.to_string())
    .filter(part => part != "")
  if parts.length() == 0 { return start }
  let mut current = start
  for part in parts {
    let (id, index) = match parse_query_part(part) {
      Some(pair) => pair
      None => return None
    }
    current = lookup_step(runtime, current, id, index)
    if current is None { return None }
  }
  current
}

fn close_tree(runtime : InstanceRuntime, instance : InstanceRef) -> Unit {
  let node = match runtime.instances.get(instance.key) {
    Some(node) => node
    None => return
  }
  let children : Array[InstanceRef] = []
  for _, items in node.children {
    for child in items {
      children.push(child)
    }
  }
  for child in children {
    close_tree(runtime, child)
  }
  match node.parent {
    Some(parent) => {
      let parent_node = node_or_panic(runtime, parent)
      let items = remove_ref(child_refs(parent_node, node.info.id), instance)
      set_child_refs(parent_node, node.info.id, items)
    }
    None => {
      let items = remove_ref(root_refs(runtime, node.info.id), instance)
      set_root_refs(runtime, node.info.id, items)
    }
  }
  runtime.instances.remove(instance.key)
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
  match info.desc {
    Some(desc) => if desc != "" { lines.push("  \{desc}") }
    None => ()
  }
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
        raise InstanceErr::Fail("missing argument: \{spec.name}")
      }
    }
    match parse_arg(spec, tokens[ti]) {
      Some(arg) => {
        out.push(arg)
        ti = ti + 1
      }
      None => raise InstanceErr::Fail("invalid \{arg_kind_name(spec.kind)}: \{tokens[ti]}")
    }
  }
  if ti != tokens.length() {
    raise InstanceErr::Fail("too many arguments")
  }
  out
}

pub fn split_shell_args(text : String) -> Array[String] raise {
  let out : Array[String] = []
  let parts : Array[String] = []
  let mut quote : String? = None
  let mut escaped = false
  let mut i = 0
  while i < text.length() {
    let ch = text[i:i + 1].to_string()
    if escaped {
      parts.push(ch)
      escaped = false
    } else if ch == "\\" {
      escaped = true
    } else {
      match quote {
        Some(q) =>
          if ch == q {
            quote = None
          } else {
            parts.push(ch)
          }
        None =>
          if ch == "'" || ch == "\"" {
            quote = Some(ch)
          } else if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            if parts.length() > 0 {
              out.push(parts.iter().join(""))
              parts.clear()
            }
          } else {
            parts.push(ch)
          }
      }
    }
    i = i + 1
  }
  if escaped {
    raise InstanceErr::Fail("invalid escape at end of input")
  }
  if quote is Some(_) {
    raise InstanceErr::Fail("unterminated quoted string")
  }
  if parts.length() > 0 {
    out.push(parts.iter().join(""))
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

pub fn lookup_instance_ref_info(runtime : InstanceRuntime, instance : InstanceRef) -> Instance? {
  match runtime.instances.get(instance.key) {
    Some(node) => Some(node.info)
    None => None
  }
}

pub fn lookup_instance(runtime : InstanceRuntime, query : String) -> Instance? {
  match lookup_ref(runtime, query) {
    Some(instance) => lookup_instance_ref_info(runtime, instance)
    None => None
  }
}

pub fn resolve_instance_ref(
  runtime : InstanceRuntime,
  query : String,
  start? : InstanceRef? = None,
) -> InstanceRef raise {
  match lookup_ref(runtime, query, start~) {
    Some(instance) => instance
    None => raise InstanceErr::Fail("instance not found: \{query}")
  }
}

pub fn instance_query(runtime : InstanceRuntime, instance : InstanceRef) -> String {
  let parts : Array[String] = []
  let mut current = Some(instance)
  while current is Some(node_ref) {
    let node = node_or_panic(runtime, node_ref)
    parts.push("\{node.info.id}#\{node.info.index}")
    current = node.parent
  }
  let out : Array[String] = []
  for i = parts.length() - 1; i >= 0; i = i - 1 {
    out.push(parts[i])
  }
  out.iter().join("/")
}

pub fn render_instance(runtime : InstanceRuntime, instance : InstanceRef) -> Comp {
  match runtime.instances.get(instance.key) {
    Some(node) => (node.render)()
    None => abort("instance not found")
  }
}

pub fn instance_actions(runtime : InstanceRuntime, instance : InstanceRef) -> Array[ActionInfo] {
  match runtime.instances.get(instance.key) {
    Some(node) => node.action_infos
    None => []
  }
}

pub fn call_instance(runtime : InstanceRuntime, instance : InstanceRef, action : String, args : Array[ActionArg]) -> String raise {
  let node = match runtime.instances.get(instance.key) {
    Some(node) => node
    None => raise InstanceErr::Fail("instance not found")
  }
  match node.actions.get(action) {
    Some(runner) => (runner.run)(args)
    None => raise InstanceErr::Fail("unknown action: \{action}")
  }
}

pub fn close_instance(runtime : InstanceRuntime, instance : InstanceRef) -> Unit raise {
  if runtime.instances.get(instance.key) is None {
    raise InstanceErr::Fail("instance not found")
  }
  close_tree(runtime, instance)
}

pub fn boot_instance(
  runtime : InstanceRuntime,
  entry_id : String,
  parent? : InstanceRef? = None,
) -> InstanceRef raise {
  let entry_id = entry_id.trim().to_string()
  if entry_id == "" {
    raise InstanceErr::Fail("entry id is empty")
  }
  if parent is Some(parent_ref) && runtime.instances.get(parent_ref.key) is None {
    raise InstanceErr::Fail("parent instance not found")
  }
  let factory = match runtime.entries.get(entry_id) {
    Some(factory) => factory
    None => raise InstanceErr::Fail("entry not found: \{entry_id}")
  }
  let key = counter_key(parent, entry_id)
  let index = match runtime.child_counts.get(key) {
    Some(current) => current + 1
    None => 1
  }
  runtime.child_counts.set(key, index)
  let instance = { key: runtime.next_instance_key }
  runtime.next_instance_key += 1
  let node = (factory.create)(runtime, instance, parent, index)
  runtime.instances.set(instance.key, node)
  append_child(runtime, parent, instance, entry_id)
  instance
}

pub fn[D, S] register_entry(runtime : InstanceRuntime, entry : Entry[D, S, Unit]) -> Unit {
  register_entry_with_extra(runtime, entry, fn(_, _) { () })
}

pub fn[D, S, X] register_entry_with_extra(
  runtime : InstanceRuntime,
  entry : Entry[D, S, X],
  extra : (InstanceRuntime, InstanceRef) -> X,
) -> Unit {
  if runtime.entries.get(entry.id) is Some(_) { return }
  let info = entry_info(entry)
  runtime.entry_ids.push(entry.id)
  runtime.entries.set(entry.id, {
    info,
    create: fn(runtime, instance, parent, index) {
      let data = cel((entry.new_data)())
      let session = cel((entry.new_session)())
      let ctx : InstanceCtx[D, S, X] = {
        data,
        session,
        extra: extra(runtime, instance),
      }
      let bind : ActionBind = (id, args) => E(fn() raise {
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
          id: entry.id,
          index,
          title: info.name,
          icon: info.icon,
        },
        parent,
        children: Map::new(),
        render: fn() { (entry.view)(ctx, bind) },
        actions,
        action_infos,
      }
    },
  })
}

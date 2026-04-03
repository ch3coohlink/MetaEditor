pub(all) struct Entry[D, S] {
  id : String
  name : String?
  icon : String?
  new_data : () -> D
  new_session : () -> S
  view : (InstanceCtx[D, S]) -> Comp
  act : (InstanceCtx[D, S], String, String) -> String raise
}

pub(all) struct EntryInfo {
  id : String
  name : String
  icon : String
}

pub(all) struct Instance {
  query : String
  entry_id : String
  title : String
  icon : String
}

pub(all) struct InstanceCtx[D, S] {
  data : Cel[D]
  session : Cel[S]
  self_query : String
  call_impl : (String, String, String) -> String raise
  spawn_impl : (String) -> String raise
  close_impl : (String) -> Unit raise
  lookup_impl : (String) -> Instance?
  entries_impl : () -> Array[EntryInfo]
  render_impl : (String) -> Comp
}

struct RuntimeNode {
  info : Instance
  children : Array[String]
  render : () -> Comp
  act : (String, String) -> String raise
}

struct EntryFactory {
  info : EntryInfo
  create : (InstanceRuntime, String) -> RuntimeNode
}

pub(all) struct InstanceRuntime {
  entry_ids : Array[String]
  entries : Map[String, EntryFactory]
  instances : Map[String, RuntimeNode]
  child_counts : Map[String, Int]
}

priv suberror InstanceErr {
  Fail(String)
}

pub fn new_instance_runtime() -> InstanceRuntime {{
  entry_ids: [],
  entries: Map::new(),
  instances: Map::new(),
  child_counts: Map::new(),
}}

fn counter_key(parent_query : String, entry_id : String) -> String {
  "\{parent_query}\n\{entry_id}"
}

fn resolve_query(base : String, query : String) -> String {
  let query = query.trim().to_string()
  if query == "" { return base }
  if query.contains("/") { return query }
  if query.contains("#") && base == "" { return query }
  if query.contains("#") && query.contains(base) { return query }
  if base == "" { query } else { "\{base}/\{query}" }
}

fn remove_child_query(children : Array[String], query : String) -> Unit {
  for i = 0; i < children.length(); i = i + 1 {
    if children[i] == query {
      ignore(children.remove(i))
      return
    }
  }
}

fn parent_query(query : String) -> String? {
  let parts = query.split("/").collect().map(part => part.to_string())
  if parts.length() <= 1 { return None }
  let out : Array[String] = []
  for i = 0; i + 1 < parts.length(); i = i + 1 {
    out.push(parts[i])
  }
  Some(out.iter().join("/"))
}

fn[D, S] instance_factory_info(entry : Entry[D, S]) -> EntryInfo {
  let name = entry.name.unwrap_or(entry.id)
  {
    id: entry.id,
    name,
    icon: entry.icon.unwrap_or(name),
  }
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

pub fn lookup_instance(runtime : InstanceRuntime, query : String) -> Instance? {
  match runtime.instances.get(query) {
    Some(node) => Some(node.info)
    None => None
  }
}

pub fn render_instance(runtime : InstanceRuntime, query : String) -> Comp {
  match runtime.instances.get(query) {
    Some(node) => (node.render)()
    None => abort("instance not found: \{query}")
  }
}

fn close_instance_tree(runtime : InstanceRuntime, query : String) -> Unit {
  let node = match runtime.instances.get(query) {
    Some(node) => node
    None => return
  }
  let children = node.children.copy()
  for child in children {
    close_instance_tree(runtime, child)
  }
  match parent_query(query) {
    Some(parent) =>
      match runtime.instances.get(parent) {
        Some(parent_node) => remove_child_query(parent_node.children, query)
        None => ()
      }
    None => ()
  }
  runtime.instances.remove(query)
}

pub fn close_instance(runtime : InstanceRuntime, query : String) -> Unit raise {
  if runtime.instances.get(query) is None {
    raise InstanceErr::Fail("instance not found: \{query}")
  }
  close_instance_tree(runtime, query)
}

pub fn call_instance(runtime : InstanceRuntime, query : String, action : String, arg : String) -> String raise {
  match runtime.instances.get(query) {
    Some(node) => (node.act)(action, arg)
    None => raise InstanceErr::Fail("instance not found: \{query}")
  }
}

pub fn boot_instance(runtime : InstanceRuntime, entry_id : String, parent? : String? = None) -> String raise {
  let entry_id = entry_id.trim().to_string()
  if entry_id == "" { raise InstanceErr::Fail("entry id is empty") }
  let factory = match runtime.entries.get(entry_id) {
    Some(factory) => factory
    None => raise InstanceErr::Fail("entry not found: \{entry_id}")
  }
  let parent_query = parent.unwrap_or("")
  if parent_query != "" && runtime.instances.get(parent_query) is None {
    raise InstanceErr::Fail("parent instance not found: \{parent_query}")
  }
  let key = counter_key(parent_query, entry_id)
  let serial = match runtime.child_counts.get(key) {
    Some(current) => current + 1
    None => 1
  }
  runtime.child_counts.set(key, serial)
  let query = if parent_query == "" {
    "\{entry_id}#\{serial}"
  } else {
    "\{parent_query}/\{entry_id}#\{serial}"
  }
  let node = (factory.create)(runtime, query)
  runtime.instances.set(query, node)
  if parent_query != "" {
    match runtime.instances.get(parent_query) {
      Some(parent_node) => parent_node.children.push(query)
      None => ()
    }
  }
  query
}

pub fn[D, S] register_entry(runtime : InstanceRuntime, entry : Entry[D, S]) -> Unit {
  if runtime.entries.get(entry.id) is Some(_) { return }
  let info = instance_factory_info(entry)
  runtime.entry_ids.push(entry.id)
  runtime.entries.set(entry.id, {
    info,
    create: fn(runtime, query) {
      let data = cel((entry.new_data)())
      let session = cel((entry.new_session)())
      let ctx : InstanceCtx[D, S] = {
        data,
        session,
        self_query: query,
        call_impl: (target, action, arg) => call_instance(runtime, target, action, arg),
        spawn_impl: entry_id => boot_instance(runtime, entry_id, parent=Some(query)),
        close_impl: target => close_instance(runtime, target),
        lookup_impl: fn(target) { lookup_instance(runtime, target) },
        entries_impl: fn() { runtime_entry_infos(runtime) },
        render_impl: fn(target) { render_instance(runtime, target) },
      }
      {
        info: {
          query,
          entry_id: entry.id,
          title: info.name,
          icon: info.icon,
        },
        children: [],
        render: fn() { (entry.view)(ctx) },
        act: (name, arg) => (entry.act)(ctx, name, arg),
      }
    },
  })
}

pub fn[D, S] InstanceCtx::call(
  self : InstanceCtx[D, S],
  query : String,
  action : String,
  arg : String,
) -> String raise {
  (self.call_impl)(resolve_query(self.self_query, query), action, arg)
}

pub fn[D, S] InstanceCtx::spawn_child(self : InstanceCtx[D, S], entry_id : String) -> String raise {
  (self.spawn_impl)(entry_id)
}

pub fn[D, S] InstanceCtx::close_instance(self : InstanceCtx[D, S], query : String) -> Unit raise {
  (self.close_impl)(resolve_query(self.self_query, query))
}

pub fn[D, S] InstanceCtx::instance(self : InstanceCtx[D, S], query : String) -> Instance? {
  (self.lookup_impl)(resolve_query(self.self_query, query))
}

pub fn[D, S] InstanceCtx::entries(self : InstanceCtx[D, S]) -> Array[EntryInfo] {
  (self.entries_impl)()
}

pub fn[D, S] InstanceCtx::render(self : InstanceCtx[D, S], query : String) -> Comp {
  (self.render_impl)(resolve_query(self.self_query, query))
}

pub fn[D, S] InstanceCtx::action(
  self : InstanceCtx[D, S],
  name : String,
  arg~ : String = "",
) -> Prop {
  E(fn() raise {
    ignore(self.call("", name, arg))
  })
}

pub fn[D, S] InstanceCtx::action_to(
  self : InstanceCtx[D, S],
  query : String,
  name : String,
  arg~ : String = "",
) -> Prop {
  E(fn() raise {
    ignore(self.call(query, name, arg))
  })
}

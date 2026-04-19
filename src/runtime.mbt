pub struct Entry[D, S, A, SA] {
  id: String
  title: String
  data: () -> D raise
  session: (D) -> S raise
  actions: (Runtime, D) -> A raise
  session_actions: (Runtime, D, S) -> SA raise
  init: (Runtime, InstanceRead, D, S, A, SA) -> Comp raise
}
type InstanceRead = (Array[ReadItem], (Array[ReadValue]) -> Unit raise) -> Unit raise
pub struct EntryInfo { id: String; title: String } derive(Eq, Hash)
pub struct Instance { id: String; title: String; view: Comp; rt: Runtime }
impl Eq for Instance with equal(a, b) { a.id == b.id }
impl Hash for Instance with hash_combine(self, hasher) { hasher.combine_string(self.id) }
let entries: Map[String, (String, (Runtime, String) -> Instance raise)] = Map::new()
pub fn[D, S, A, SA] Entry::register(self: Entry[D, S, A, SA]) -> Unit raise {
  match entries.get(self.id) {
    Some(_) => fail("duplicate entry id: \{self.id}")
    None => entries.set(self.id, (self.title, (rt, id) => rt.spawn_typed(self, id~).0))
  }
}
pub fn Entry::list() -> Array[EntryInfo] { [..entries].map((e) => { id: e.0, title: e.1.0 }) }

struct SharedRt { open: (String) -> Instance raise }
struct InstanceRt { shared: String; title: String; view: Comp }
pub struct ReadItem { read: Read; default: ReadValue }
pub(all) enum RuntimeOut { Cmd(DomCmd); Read(String, Array[Read], (Array[ReadValue]) -> Unit raise) }
pub(all) struct Runtime { dom: Dom; shareds: Map[String, SharedRt]; instances: Map[String, InstanceRt]
  iids: Map[String, () -> Int]; jumps: Map[String, UIID]; root: String
  outs: Ref[Array[RuntimeOut]]; mut on_out: (RuntimeOut) -> Unit raise; on_err: (String) -> Unit }
fn Runtime::emit(self: Runtime) -> Unit {
  let outs = self.outs.val
  if outs.length() == 0 { return }
  self.outs.val = []
  try { for out in outs { (self.on_out)(out) } } catch { e => self.report(e.to_string()) }
}
pub fn Runtime::read(self: Runtime, instance: String, items: Array[ReadItem],
  apply: (Array[ReadValue]) -> Unit raise) -> Unit raise {
  if items.length() == 0 { apply([]); return }
  self.outs.val.push(Read(instance, items.map(i => i.read), res => {
      let values = items.map(i => i.default)
      let n = if res.length() < values.length() { res.length() } else { values.length() }
      for i = 0; i < n; i = i + 1 {
        match res[i] {
          ReadValue::Box(Some(_)) | ReadValue::View(Some(_)) |
          ReadValue::Scroll(Some(_)) | ReadValue::Text(Some(_)) => values[i] = res[i]
          _ => ()
        }
      }
      apply(values)
      flush()
      self.emit()
    }))
  self.emit()
}
fn Runtime::shared_id(self: Runtime, entry_id: String, id: String) -> String raise {
  let id = if id != "" { id } else {
    let i = match self.iids.get(entry_id) {
      Some(n) => n(); None => { let n = gen_id(0); self.iids.set(entry_id, n); n() }
    }; "\{entry_id}-\{i}"
  }; if self.shareds.get(id) is Some(_) { fail("duplicate instance id: \{id}") }; id
}
fn[D, S, A, SA] Runtime::instance_view(self: Runtime, entry: Entry[D, S, A, SA],
  id: String, data: D, session: S, actions: A, session_actions: SA) -> Comp raise {
  let read = (items, apply) => self.read(id, items, apply)
  let raw_view = (entry.init)(self, read, data, session, actions, session_actions)
  comp((attrs, children) => Lazy((dom, ns, q) => {
      self.jumps.set(id, q)
      child(dom, h(raw_view, attrs, children), ns, q)
    }))
}
pub fn Runtime::instance(self: Runtime, id: String) -> Instance raise {
  match self.instances.get(id) {
    Some(v) => { id, title: v.title, view: v.view, rt: self }
    None => fail("unknown instance id: \{id}")
  }
}
fn Runtime::close_instance(self: Runtime, id: String) -> Unit raise {
  let inst = match self.instances.get(id) {
    Some(v) => v
    None => fail("unknown instance id: \{id}")
  }
  self.instances.remove(id)
  self.jumps.remove(id)
  let mut keep = false
  for _, v in self.instances {
    if v.shared == inst.shared {
      keep = true
      break
    }
  }
  if !keep { self.shareds.remove(inst.shared) }
}
///| 类型化的 instance 创建, 使用明确类型的 entry 创建, 可以拿到共享和会话操作集合
pub fn[D, S, A, SA] Runtime::spawn_typed(self: Runtime, entry: Entry[D, S, A, SA],
  id?: String = "") -> (Instance, A, SA) raise {
  let id = self.shared_id(entry.id, id)
  let data = (entry.data)()
  let actions = (entry.actions)(self, data)
  let iid = gen_id(0)
  let open = (id0: String) => {
    let id0 = if id0 != "" { id0 } else {
      "\{id}-\{iid()}"
    }
    if self.instances.get(id0) is Some(_) { fail("duplicate instance id: \{id0}") }
    let session = (entry.session)(data)
    let session_actions = (entry.session_actions)(self, data, session)
    let view = self.instance_view(entry, id0, data, session, actions, session_actions)
    self.instances.set(id0, { shared: id, title: entry.title, view })
    ({ id: id0, title: entry.title, view, rt: self }, session_actions)
  }
  self.shareds.set(id, { open: id0 => open(id0).0 })
  let (inst, session_actions) = open("")
  (inst, actions, session_actions)
}
///| 无类型的 instance 创建, 只要提供 entry id
pub fn Runtime::spawn(self: Runtime, entry_id: String, id?: String = "") -> Instance raise {
  match entries.get(entry_id) {
    Some((_, create)) => create(self, id)
    None => fail("unknown entry: \{entry_id}")
  }
}
pub fn Runtime::new(root: String,
  on_out?: (RuntimeOut) -> Unit raise = _ => (),
  on_err?: (String) -> Unit = (_) => (),
) -> Runtime {
  let outs = Ref::new([])
  let dom = Dom::new(emit=c => outs.val.push(Cmd(c)), on_err=on_err)
  let rt = {
    dom, shareds: Map::new(), instances: Map::new(), iids: Map::new(), jumps: Map::new(),
    root, outs, on_out, on_err,
  }
  for err in ui_errs { on_err(err.to_string()) }
  try {
    let root = rt.spawn(root)
    dom.mount(dom.body, h(root.view, [], []))
  } catch { e => on_err("\{e}") }
  rt.emit(); rt
}
pub fn Runtime::report(self: Runtime, err: String) -> Unit { (self.on_err)(err) }
pub fn Runtime::root(self: Runtime) -> Instance raise { self.instance(self.root) }
pub fn Instance::spawn(self: Instance, id?: String = "") -> Instance raise {
  let shared = match self.rt.instances.get(self.id) {
    Some(v) => v.shared
    None => fail("unknown instance id: \{self.id}")
  }
  match self.rt.shareds.get(shared) {
    Some(v) => (v.open)(id)
    None => fail("unknown instance shared: \{shared}")
  }
}
pub fn Instance::close(self: Instance) -> Unit raise { self.rt.close_instance(self.id) }
fn Instance::resolve(self: Instance, path: String) -> Node raise {
  match self.rt.jumps.get(self.id) {
    Some(q) => if path == "" { q.node() } else { q.query(path).node() }
    None => fail("unknown instance jump: \{self.id}")
  }
}
pub fn Instance::query(self: Instance, path: String, query: NodeQuery) -> NodeValue raise {
  self.resolve(path).query(query)
}
pub fn Instance::dispatch(self: Instance, path: String, ev: Event) -> Unit raise {
  self.resolve(path).dispatch(self.rt.dom, ev)
  self.rt.emit()
}
pub fn Instance::trigger(self: Instance, id: Int, ev: Event) -> Unit raise {
  self.rt.dom.trigger(id, ev)
  self.rt.emit()
}
pub fn Instance::replay(self: Instance) -> Array[DomCmd] { self.rt.dom.replay() }

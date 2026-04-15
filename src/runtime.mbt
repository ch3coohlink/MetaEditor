pub struct Entry[D, S, A] { id: String; title: String; data: () -> D raise; session: (D) -> S raise
  actions: (Runtime, D, S) -> A raise; init: (Runtime, D, S, A) -> Comp raise }
pub struct Instance { id: String; title: String; view: Comp; root: UIMeta? }
let entries: Map[String, (Runtime, String) -> Instance raise] = Map::new()
impl Eq for Instance with equal(a, b) { a.id == b.id }
impl Hash for Instance with hash_combine(self, hasher) { hasher.combine_string(self.id) }
// 多余包装
pub fn Instance::child(self: Instance) -> Child {
  match self.root {
    Some(root) => h("div", [React, Id(root)], [h(self.view, [], [])])
    None => h(self.view, [], [])
  }
}
pub fn[D, S, A] Entry::register(self: Entry[D, S, A]) -> Unit raise {
  match entries.get(self.id) {
    Some(_) => fail("duplicate entry id: \{self.id}")
    None => entries.set(self.id, (rt, id) => rt.instance(self, id~).0)
  }
}

pub struct Runtime { dom: Dom; instances: Map[String, Instance]; iids: Map[String, () -> Int]
  on_batch: (Array[DomCmd]) -> Unit; on_error: (String) -> Unit }
fn Runtime::instance_id(self: Runtime, entry_id: String, id: String) -> String raise {
  let id = if id != "" { id } else {
    let i = match self.iids.get(entry_id) {
      Some(n) => n(); None => { let n = gen_id(0); self.iids.set(entry_id, n); n() }
    }; if i == 0 { entry_id } else { "\{entry_id}-\{i}" }
  }; if self.instances.get(id) is Some(_) { fail("duplicate instance id: \{id}") }; id
}
///| 类型化的 instance 创建, 使用明确类型的 entry 创建, 可以拿到 actions 具体操作集合
pub fn[D, S, A] Runtime::instance(self: Runtime, entry: Entry[D, S, A],
  id?: String = "", scoped?: Bool = true) -> (Instance, A) raise {
  let id = self.instance_id(entry.id, id)
  let data = (entry.data)()
  let session = (entry.session)(data)
  let actions = (entry.actions)(self, data, session)
  let root = if scoped { Some(ui(id, scope=Scope)) } else { None }
  let raw = { id, title: entry.title, view: (entry.init)(self, data, session, actions), root }
  self.instances.set(raw.id, raw)
  (raw, actions)
}
///| 无类型的 instance 创建, 只要提供 entry id
pub fn Runtime::spawn(self: Runtime, entry_id: String, id?: String = "") -> Instance raise {
  let id = self.instance_id(entry_id, id)
  match entries.get(entry_id) {
    Some(create) => create(self, id)
    None => fail("unknown entry: \{entry_id}")
  }
}
pub fn[D, S, A] Runtime::new(root: Entry[D, S, A],
  on_cmd?: (Array[DomCmd]) -> Unit = fn(_) {},
  on_error?: (String) -> Unit = fn(_) {},
) -> Runtime {
  let cmds = []; let dom = Dom::new(emit=c => cmds.push(c), on_error~)
  let rt = { dom, instances: Map::new(), iids: Map::new(), on_batch: on_cmd, on_error }
  try { dom.mount(dom.body, rt.instance(root, scoped=false).0.child()) }
  catch { e => on_error("\{e}") }
  on_cmd(cmds); rt
}
pub fn Runtime::report(self: Runtime, err: String) -> Unit { (self.on_error)(err) }
pub fn Runtime::resolve(self: Runtime, path: String) -> Node raise { self.dom.resolve(path) }
pub fn Runtime::query(self: Runtime, path: String, query: NodeQuery
  ) -> NodeValue raise { self.dom.query(path, query) }
pub fn Runtime::dispatch(self: Runtime, path: String, ev: DomEvent
  ) -> Unit raise { self.dom.dispatch(path, ev) }

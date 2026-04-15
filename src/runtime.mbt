pub struct Entry[D, S, A] { id: String; title: String;
  data: () -> D raise; session: (D) -> S raise
  actions: (Runtime, D, S) -> A raise; init: (Runtime, D, S, A) -> Comp raise }
pub struct RegisteredEntry { id: String; title: String; create: (Runtime, String) -> Instance raise }
pub struct Instance { id: String; title: String; view: Comp; root: UIMeta? }
let entries: Map[String, RegisteredEntry] = Map::new()
impl Eq for Instance with equal(a, b) { a.id == b.id }
impl Hash for Instance with hash_combine(self, hasher) { hasher.combine_string(self.id) }
pub fn Instance::child(self: Instance) -> Child {
  match self.root {
    Some(root) => h("div", [React, Id(root)], [h(self.view, [], [])])
    None => h(self.view, [], [])
  }
}
pub fn[D, S, A] Entry::register(self: Entry[D, S, A]) -> Unit raise {
  match entries.get(self.id) {
    Some(_) => fail("duplicate entry id: \{self.id}")
    None => entries.set(self.id, {
      id: self.id, title: self.title,
      create: (rt, id) => rt.instance(self, id~).0,
    })
  }
}
pub fn Entry::get(id: String) -> RegisteredEntry raise {
  match entries.get(id) { Some(v) => v; None => fail("unknown entry: \{id}") } }
pub fn Entry::list() -> Iter[(String, RegisteredEntry)] { [..entries.iter()]}

pub struct Runtime { dom: Dom; instances: Map[String, Instance]
  on_batch: (Array[DomCmd]) -> Unit; on_error: (String) -> Unit }
pub fn[D, S, A] Runtime::instance(self: Runtime, entry: Entry[D, S, A],
  id?: String = "", scoped?: Bool = true,
) -> (Instance, A) raise {
  let id = if id == "" { entry.id } else { id }
  if self.instances.get(id) is Some(_) { fail("duplicate instance id: \{id}") }
  let data = (entry.data)()
  let session = (entry.session)(data)
  let actions = (entry.actions)(self, data, session)
  let root = if scoped { Some(ui(id, scope=Scope)) } else { None }
  let raw = { id, title: entry.title, view: (entry.init)(self, data, session, actions), root }
  self.instances.set(raw.id, raw)
  (raw, actions)
}
pub fn[D, S, A] Runtime::new(root: Entry[D, S, A],
  on_batch?: (Array[DomCmd]) -> Unit = fn(_) {},
  on_error?: (String) -> Unit = fn(_) {},
) -> Runtime {
  let cmds = []; let dom = Dom::new(emit=c => cmds.push(c), on_error~)
  let rt = { dom, instances: Map::new(), on_batch, on_error }
  try {
    let root = rt.instance(root, scoped=false).0
    dom.mount(dom.body, root.child())
  } catch { err => { on_error("\{err}") } }
  on_batch(cmds); rt
}
pub fn Runtime::report(self: Runtime, err: String) -> Unit { (self.on_error)(err) }
pub fn Runtime::resolve(self: Runtime, path: String) -> Node raise { self.dom.resolve(path) }
pub fn Runtime::query(self: Runtime, path: String, query: NodeQuery
  ) -> NodeValue raise { self.dom.query(path, query) }
pub fn Runtime::dispatch(self: Runtime, path: String, ev: DomEvent
  ) -> Unit raise { self.dom.dispatch(path, ev) }

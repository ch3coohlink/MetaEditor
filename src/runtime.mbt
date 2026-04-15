pub struct Entry[D, S] { id: String; title: String; data: () -> D raise;
  session: (D) -> S raise; init: (Runtime, D, S) -> Comp raise }
pub struct Instance { id: String; title: String; view: Comp; root: UIMeta? }
impl Eq for Instance with equal(a, b) { a.id == b.id }
impl Hash for Instance with hash_combine(self, hasher) { hasher.combine_string(self.id) }
pub fn Instance::child(self: Instance) -> Child {
  match self.root {
    Some(root) => h("div", [React, Id(root)], [h(self.view, [], [])])
    None => h(self.view, [], [])
  }
}

pub struct Runtime { dom: Dom; instances: Map[String, Instance]
  on_batch: (Array[DomCmd]) -> Unit; on_error: (String) -> Unit }
pub fn[D, S] Runtime::create_instance(
  self: Runtime, entry: Entry[D, S], id?: String = "", scoped?: Bool = true,
) -> Instance raise {
  let id = if id == "" { entry.id } else { id }
  if self.instances.get(id) is Some(_) { fail("duplicate instance id: \{id}") }
  let data = (entry.data)()
  let session = (entry.session)(data)
  let root = if scoped { Some(ui(id, scope=Scope)) } else { None }
  let out = { id, title: entry.title, view: (entry.init)(self, data, session), root }
  self.instances.set(out.id, out)
  out
}
pub fn[D, S] Runtime::new(root: Entry[D, S],
  on_batch?: (Array[DomCmd]) -> Unit = fn(_) {},
  on_error?: (String) -> Unit = fn(_) {},
) -> Runtime {
  let cmds = []; let dom = Dom::new(emit=c => cmds.push(c), on_error~)
  let rt = { dom, instances: Map::new(), on_batch, on_error }
  try {
    let root = rt.create_instance(root, scoped=false)
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

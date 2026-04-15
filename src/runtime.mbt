pub struct Entry[D, S] {
  id: String; title: String; init: () -> ((D, S) -> Comp) raise
  data: () -> D raise; session: (D) -> S raise
}
pub fn[D, S] Entry::new(entry: Entry[D, S]) -> Entry[D, S] { entry }

pub struct Instance[D, S] { id: String; entry: Entry[D, S]; data: D; session: S }
pub fn[D, S] Instance::new(entry: Entry[D, S], id?: String = "") -> Instance[D, S] raise {
  let data = (entry.data)()
  let session = (entry.session)(data)
  { entry, data, session, id: if id == "" { entry.id } else { id } }
}

pub struct Runtime { dom: Dom; on_batch: (Array[DomCmd]) -> Unit; on_error: (String) -> Unit }
pub fn[D, S] Runtime::new(root: Entry[D, S],
  on_batch?: (Array[DomCmd]) -> Unit = fn(_) {},
  on_error?: (String) -> Unit = fn(_) {},
) -> Runtime {
  let cmds : Ref[Array[DomCmd]] = Ref::new([])
  let dom = Dom::new(emit=c => cmds.val.push(c), on_error=on_error)
  try {
    let inst = Instance::new(root)
    let view = (root.init)()
    dom.mount(dom.body, h(view(inst.data, inst.session), [], []))
  } catch { err => { on_error("\{err}") } }
  on_batch(cmds.val)
  { dom, on_batch, on_error }
}
pub fn Runtime::report(self: Runtime, err: String) -> Unit { (self.on_error)(err) }
pub fn Runtime::resolve(self: Runtime, path: String) -> Node raise { self.dom.resolve(path) }
pub fn Runtime::query(self: Runtime, path: String, query: NodeQuery) -> NodeValue raise {
  self.dom.query(path, query)
}

pub struct Entry { id: String; title: String; view: () -> Child }
pub fn Entry::new(id: String,
  view: () -> Comp raise,
  title?: String = "",
) -> Entry {
  { id, title: if title == "" { id } else { title },
    view: () => try h(view(), [], []) catch { err => error_child("\{err}") } }
}

pub struct Instance { id: String; entry: Entry }
pub fn Instance::new(entry: Entry, id?: String = "",
) -> Instance {{ entry, id: if id == "" { entry.id } else { id } }}

pub struct Runtime { dom: Dom; on_batch: (Array[DomCmd]) -> Unit; on_error: (String) -> Unit }
pub fn Runtime::new(root: Entry,
  on_batch?: (Array[DomCmd]) -> Unit = fn(_) {},
  on_error?: (String) -> Unit = fn(_) {},
) -> Runtime {
  let cmds : Ref[Array[DomCmd]] = Ref::new([])
  let dom = Dom::new(emit=c => cmds.val.push(c), on_error=on_error)
  try dom.mount(dom.body, (root.view)()) catch { err => { on_error("\{err}") } }
  on_batch(cmds.val)
  { dom, on_batch, on_error }
}
pub fn Runtime::report(self: Runtime, err: String) -> Unit { (self.on_error)(err) }
pub fn Runtime::resolve(self: Runtime, path: String) -> Node raise { self.dom.resolve(path) }

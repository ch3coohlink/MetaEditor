pub struct Entry { id: String; title: String; view: () -> Child raise }
pub fn Entry::new(id: String, view: () -> Child raise, title?: String = "",
) -> Entry {{ id, view, title: if title == "" { id } else { title } }}

pub struct Instance { id: String; entry: Entry }
pub fn Instance::new(entry: Entry, id?: String = "",
) -> Instance {{ entry, id: if id == "" { entry.id } else { id } }}

pub struct Runtime { dom: Dom; on_batch: (Array[DomCmd]) -> Unit; errors: Ref[Array[String]] }
pub fn Runtime::new(root: Entry, on_batch?: (Array[DomCmd]) -> Unit = fn(_) {}) -> Runtime raise {
  let cmds : Ref[Array[DomCmd]] = Ref::new([])
  let errors: Ref[Array[String]] = Ref::new([])
  let dom = Dom::new(emit=c => cmds.val.push(c), on_error=msg => errors.val.push(msg))
  dom.mount(dom.body, (root.view)())
  on_batch(cmds.val)
  { dom, on_batch, errors }
}
pub fn Runtime::resolve(self: Runtime, path: String) -> Int raise { self.dom.resolve(path) }

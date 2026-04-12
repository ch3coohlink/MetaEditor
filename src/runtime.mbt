pub struct Entry { id: String; title: String; view: () -> Child }
pub fn Entry::new(id: String, view: () -> Child, title?: String = "",
) -> Entry {{ id, view, title: if title == "" { id } else { title } }}

pub struct Instance { id: String; entry: Entry }
pub fn Instance::new(entry: Entry, id?: String = "",
) -> Instance {{ entry, id: if id == "" { entry.id } else { id } }}

pub struct Runtime { root: Instance; dom: DomState; on_batch: (Array[DomCmd]) -> Unit }
pub fn Runtime::new(root: Instance, on_batch?: (Array[DomCmd]) -> Unit = fn(_) {},
) -> Runtime {{ root, dom: dom_state(), on_batch }}
pub fn Runtime::resolve(self: Runtime, path: String) -> Int raise {
  let path = path.trim().to_string()
  if path == "" { fail("query is empty") }
  fail("query is pending runtime/dom redesign")
}

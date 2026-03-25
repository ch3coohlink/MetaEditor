pub(all) enum PersistValue {
  Obj(Map[String, PersistValue])
  Arr(Array[PersistValue])
  Str(String)
  Int(Int)
  Bool(Bool)
  Null
  Ref(String)
  Cel(Cel[PersistValue])
}

pub(all) struct RefNode {
  id: String
  value: PersistValue
}

priv struct BoundRefNode {
  id: String
  mut value: PersistValue
  mut outs: Array[String]
  mut refs: Int
}

priv struct RefBindState {
  kv: Kv
  key: String
  mut next_id: Int
  nodes: Array[BoundRefNode]
}

priv struct ScopedRefBind {
  key: String
  source: Cel[PersistValue]
  mut refs: Int
  stop: () -> Unit
}

pub(open) trait Persist {
  pack(Self) -> PersistValue
  unpack(PersistValue, old? : Self?) -> Self
}

pub(all) struct Kv {
  data: Ref[Map[String, PersistValue]]
}

pub fn open_kv() -> Kv {
  { data: Ref::new(Map::new()) }
}

pub fn Kv::get(self: Kv, key: String) -> Option[PersistValue] {
  self.data.val.get(key)
}

pub fn Kv::set(self: Kv, key: String, value: PersistValue) -> Unit {
  self.data.val.set(key, value)
}

pub fn Kv::delete(self: Kv, key: String) -> Unit {
  self.data.val.remove(key)
}

pub fn[T: Persist] pack(value: T) -> PersistValue {
  T::pack(value)
}

pub fn[T: Persist] unpack(value: PersistValue, old? : T? = None) -> T {
  T::unpack(value, old~)
}

pub fn obj(items: Array[(String, PersistValue)]) -> PersistValue {
  let m: Map[String, PersistValue] = Map::new()
  for item in items {
    let (k, v) = item
    m.set(k, v)
  }
  PersistValue::Obj(m)
}

pub fn arr(items: Array[PersistValue]) -> PersistValue {
  PersistValue::Arr(items)
}

fn node_key(key: String, id: String) -> String {
  key + "/" + id
}

fn same_node_value(a: PersistValue, b: PersistValue) -> Bool {
  match (a, b) {
    (Obj(m1), Obj(m2)) => physical_equal(m1, m2)
    (Arr(a1), Arr(a2)) => physical_equal(a1, a2)
    _ => false
  }
}

fn find_node_id(nodes: Array[BoundRefNode], value: PersistValue) -> Option[String] {
  for node in nodes {
    if same_node_value(node.value, value) { return Some(node.id) }
  }
  None
}

fn find_node_index(nodes: Array[BoundRefNode], id: String) -> Int? {
  for i = 0; i < nodes.length(); i = i + 1 {
    if nodes[i].id == id { return Some(i) }
  }
  None
}

fn alloc_node_id(st: RefBindState) -> String {
  let mut id = st.next_id.to_string()
  st.next_id = st.next_id + 1
  while find_node_index(st.nodes, id) is Some(_) {
    id = st.next_id.to_string()
    st.next_id = st.next_id + 1
  }
  id
}

fn bind_node(st: RefBindState, value: PersistValue, id? : String? = None) -> String {
  match find_node_id(st.nodes, value) {
    Some(found) => found
    None => {
      let next = match id {
        Some(v) => v
        None => alloc_node_id(st)
      }
      st.nodes.push({ id: next, value, outs: [], refs: 0 })
      next
    }
  }
}

fn inc_node_ref(st: RefBindState, id: String) -> Unit {
  match find_node_index(st.nodes, id) {
    Some(i) => st.nodes[i].refs = st.nodes[i].refs + 1
    None => ()
  }
}

fn dec_node_ref(st: RefBindState, id: String) -> Unit {
  if id == "0" { return }
  match find_node_index(st.nodes, id) {
    Some(i) => {
      st.nodes[i].refs = st.nodes[i].refs - 1
      if st.nodes[i].refs <= 0 { drop_node(st, id) }
    }
    None => ()
  }
}

fn drop_node(st: RefBindState, id: String) -> Unit {
  if id == "0" { return }
  match find_node_index(st.nodes, id) {
    Some(i) => {
      let outs = st.nodes[i].outs.copy()
      let _ = st.nodes.remove(i)
      st.kv.delete(node_key(st.key, id))
      outs.each(fn(child) { dec_node_ref(st, child) })
    }
    None => ()
  }
}

fn remove_one(ids: Array[String], target: String) -> Bool {
  for i = 0; i < ids.length(); i = i + 1 {
    if ids[i] == target {
      let _ = ids.remove(i)
      return true
    }
  }
  false
}

fn update_node_refs(st: RefBindState, id: String, next: Array[String]) -> Unit {
  match find_node_index(st.nodes, id) {
    Some(i) => {
      let prev = st.nodes[i].outs.copy()
      let rest = next.copy()
      prev.each(fn(old_id) {
        if not(remove_one(rest, old_id)) {
          dec_node_ref(st, old_id)
        }
      })
      rest.each(fn(new_id) { inc_node_ref(st, new_id) })
      st.nodes[i].outs = next
    }
    None => ()
  }
}

fn dehydrate_leaf(value: PersistValue, get_id: (PersistValue) -> String) -> PersistValue {
  match value {
    Obj(_) => Ref(get_id(value))
    Arr(_) => Ref(get_id(value))
    Cel(c) => dehydrate_leaf(c.peek(), get_id)
    _ => value
  }
}

pub fn dehydrate(value: PersistValue, get_id: (PersistValue) -> String) -> PersistValue {
  match value {
    Obj(m) => {
      let out: Map[String, PersistValue] = Map::new()
      m.each(fn(k, v) { out.set(k, dehydrate_leaf(v, get_id)) })
      PersistValue::Obj(out)
    }
    Arr(items) => {
      let out: Array[PersistValue] = []
      items.each(fn(v) { out.push(dehydrate_leaf(v, get_id)) })
      PersistValue::Arr(out)
    }
    Cel(c) => dehydrate(c.peek(), get_id)
    _ => value
  }
}

fn hydrate_value(
  cur: PersistValue,
  raw: PersistValue,
  resolve: (PersistValue, String) -> PersistValue
) -> PersistValue {
  match cur {
    Cel(prev) => {
      prev.set(hydrate_value(prev.peek(), raw, resolve))
      PersistValue::Cel(prev)
    }
    _ => match raw {
      Ref(id) => resolve(cur, id)
      Obj(next) => {
        let target = match cur {
          Obj(prev) => prev
          _ => Map::new()
        }
        let stale: Array[String] = []
        target.each(fn(k, _) {
          match next.get(k) {
            Some(_) => ()
            None => stale.push(k)
          }
        })
        stale.each(fn(k) { target.remove(k) })
        next.each(fn(k, v) {
          let cur_v = match target.get(k) {
            Some(x) => x
            None => PersistValue::Null
          }
          target.set(k, hydrate_value(cur_v, v, resolve))
        })
        PersistValue::Obj(target)
      }
      Arr(next) => {
        let target = match cur {
          Arr(prev) => prev
          _ => []
        }
        let prev = target.copy()
        target.clear()
        for i = 0; i < next.length(); i = i + 1 {
          let cur_v = if i < prev.length() { prev[i] } else { PersistValue::Null }
          target.push(hydrate_value(cur_v, next[i], resolve))
        }
        PersistValue::Arr(target)
      }
      _ => raw
    }
  }
}

pub fn hydrate(
  st: PersistValue,
  raw: PersistValue,
  resolve: (PersistValue, String) -> PersistValue
) -> PersistValue {
  hydrate_value(st, raw, resolve)
}

fn save_node(st: RefBindState, id: String, seen: Array[String]) -> Unit {
  if seen.contains(id) { return }
  seen.push(id)
  match find_node_index(st.nodes, id) {
    Some(i) => {
      let value = st.nodes[i].value
      let outs: Array[String] = []
      let raw = dehydrate(value, fn(child) {
        let child_id = bind_node(st, child)
        outs.push(child_id)
        child_id
      })
      update_node_refs(st, id, outs)
      st.kv.set(node_key(st.key, id), raw)
      outs.each(fn(child_id) { save_node(st, child_id, seen) })
    }
    None => ()
  }
}

fn collect_saved_ids(value: PersistValue, out: Array[String]) -> Unit {
  match value {
    Ref(id) => if not(out.contains(id)) { out.push(id) }
    Obj(m) => m.each(fn(_, v) { collect_saved_ids(v, out) })
    Arr(items) => items.each(fn(v) { collect_saved_ids(v, out) })
    Cel(c) => collect_saved_ids(c.peek(), out)
    _ => ()
  }
}

fn collect_kv_ids(kv: Kv, key: String, id: String, out: Array[String]) -> Unit {
  if out.contains(id) { return }
  out.push(id)
  match kv.get(node_key(key, id)) {
    Some(value) => collect_saved_ids(value, out)
    None => ()
  }
  let ids = out.copy()
  ids.each(fn(next) {
    if next != id { collect_kv_ids(kv, key, next, out) }
  })
}

pub fn clone(root: PersistValue) -> Array[RefNode] {
  let st = { kv: open_kv(), key: "", next_id: 1, nodes: [] }
  ignore(bind_node(st, root, id=Some("0")))
  let seen: Array[String] = []
  save_node(st, "0", seen)
  let out: Array[RefNode] = []
  seen.each(fn(id) {
    match st.kv.get(node_key("", id)) {
      Some(value) => out.push({ id, value })
      None => ()
    }
  })
  out
}

fn patch_from(
  cur: PersistValue,
  load: (String) -> Option[PersistValue],
  id: String,
  cache: Map[String, PersistValue]
) -> PersistValue {
  match cache.get(id) {
    Some(value) => value
    None => {
      let raw = match load(id) {
        Some(value) => value
        None => PersistValue::Null
      }
      match raw {
        Obj(_) => {
          let target = match cur {
            Obj(prev) => prev
            _ => Map::new()
          }
          let node = PersistValue::Obj(target)
          cache.set(id, node)
          hydrate(node, raw, fn(prev, next_id) { patch_from(prev, load, next_id, cache) })
        }
        Arr(_) => {
          let target = match cur {
            Arr(prev) => prev
            _ => []
          }
          let node = PersistValue::Arr(target)
          cache.set(id, node)
          hydrate(node, raw, fn(prev, next_id) { patch_from(prev, load, next_id, cache) })
        }
        _ => hydrate(cur, raw, fn(prev, next_id) { patch_from(prev, load, next_id, cache) })
      }
    }
  }
}

pub fn patch_refs(root: PersistValue, data: Array[RefNode]) -> PersistValue {
  let nodes: Map[String, PersistValue] = Map::new()
  data.each(fn(node) { nodes.set(node.id, node.value) })
  let cache: Map[String, PersistValue] = Map::new()
  patch_from(root, fn(id) { nodes.get(id) }, "0", cache)
}

pub fn save_to_kv(kv: Kv, key: String, root: PersistValue) -> Unit {
  let prev_ids: Array[String] = []
  collect_kv_ids(kv, key, "0", prev_ids)
  let nodes = clone(root)
  let next_ids: Array[String] = []
  nodes.each(fn(node) {
    next_ids.push(node.id)
    kv.set(node_key(key, node.id), node.value)
  })
  prev_ids.each(fn(id) {
    if not(next_ids.contains(id)) { kv.delete(node_key(key, id)) }
  })
}

pub fn load_from_kv(root: PersistValue, kv: Kv, key: String) -> Option[PersistValue] {
  match kv.get(node_key(key, "0")) {
    Some(_) => {
      let cache: Map[String, PersistValue] = Map::new()
      Some(patch_from(root, fn(id) { kv.get(node_key(key, id)) }, "0", cache))
    }
    None => None
  }
}

pub impl Persist for PersistValue with pack(self) -> PersistValue {
  self
}

pub impl Persist for PersistValue with unpack(
  value: PersistValue,
  old? : PersistValue? = None
) -> PersistValue {
  ignore(old)
  value
}

pub impl Persist for String with pack(self) -> PersistValue {
  PersistValue::Str(self)
}

pub impl Persist for String with unpack(
  value: PersistValue,
  old? : String? = None
) -> String {
  ignore(old)
  match value {
    Str(s) => s
    _ => ""
  }
}

pub impl Persist for Int with pack(self) -> PersistValue {
  PersistValue::Int(self)
}

pub impl Persist for Int with unpack(
  value: PersistValue,
  old? : Int? = None
) -> Int {
  ignore(old)
  match value {
    Int(n) => n
    _ => 0
  }
}

pub impl Persist for Bool with pack(self) -> PersistValue {
  PersistValue::Bool(self)
}

pub impl Persist for Bool with unpack(
  value: PersistValue,
  old? : Bool? = None
) -> Bool {
  ignore(old)
  match value {
    Bool(b) => b
    _ => false
  }
}

pub impl[T: Persist] Persist for Array[T] with pack(self) -> PersistValue {
  let out: Array[PersistValue] = []
  for item in self {
    out.push(item.pack())
  }
  PersistValue::Arr(out)
}

pub impl[T: Persist] Persist for Array[T] with unpack(
  value: PersistValue,
  old? : Array[T]? = None
) -> Array[T] {
  match value {
    Arr(items) => {
      let out: Array[T] = []
      match old {
        Some(prev) => {
          for i = 0; i < items.length(); i = i + 1 {
            let item = items[i]
            if i < prev.length() {
              out.push(T::unpack(item, old=Some(prev[i])))
            } else {
              out.push(T::unpack(item))
            }
          }
        }
        None => {
          for item in items {
            out.push(T::unpack(item))
          }
        }
      }
      out
    }
    _ => []
  }
}

pub impl[T: Persist] Persist for Cel[T] with pack(self) -> PersistValue {
  self.get().pack()
}

pub impl[T: Persist] Persist for Cel[T] with unpack(
  value: PersistValue,
  old? : Cel[T]? = None
) -> Cel[T] {
  match old {
    Some(prev) => {
      prev.set(T::unpack(value, old=Some(prev.peek())))
      prev
    }
    None => cel(T::unpack(value))
  }
}

pub fn[T: Persist] bind_with_kv(kv: Kv) -> (String, Cel[T]) -> (() -> Unit) raise {
  fn(key: String, source: Cel[T]) raise {
    match kv.get(key) {
      Some(value) => source.set(T::unpack(value, old=Some(source.peek())))
      None => kv.set(key, source.peek().pack())
    }
    scope(fn() raise {
      let _ = effect(() => kv.set(key, source.get().pack()))
      ()
    })
  }
}

fn sync_bound_root(st: RefBindState, source: Cel[PersistValue]) -> Unit {
  match find_node_index(st.nodes, "0") {
    Some(i) => st.nodes[i].value = source.peek()
    None => st.nodes.push({ id: "0", value: source.peek(), outs: [], refs: 0 })
  }
  let seen: Array[String] = []
  save_node(st, "0", seen)
}

pub fn bind_refs_with_kv(kv: Kv) -> (String, Cel[PersistValue]) -> (() -> Unit) raise {
  fn(key: String, source: Cel[PersistValue]) raise {
    match load_from_kv(source.peek(), kv, key) {
      Some(value) => source.set(value)
      None => ()
    }
    let st = { kv, key, next_id: 1, nodes: [] }
    sync_bound_root(st, source)
    scope(fn() raise {
      let _ = on_post_flush(fn() { sync_bound_root(st, source) })
      ()
    })
  }
}

fn same_ref_source(a: Cel[PersistValue], b: Cel[PersistValue]) -> Bool {
  physical_equal(a.cell, b.cell)
}

fn find_scoped_ref_bind(
  binds: Array[ScopedRefBind],
  key: String,
  source: Cel[PersistValue]
) -> Int? {
  for i = 0; i < binds.length(); i = i + 1 {
    let entry = binds[i]
    if entry.key == key && same_ref_source(entry.source, source) { return Some(i) }
  }
  None
}

pub fn bind_refs_scoped_with_kv(kv: Kv) -> (String, Cel[PersistValue]) -> Unit raise {
  let binds: Ref[Array[ScopedRefBind]] = Ref::new([])
  let bind = bind_refs_with_kv(kv)
  fn(key: String, source: Cel[PersistValue]) raise {
    let entries = binds.val
    match find_scoped_ref_bind(entries, key, source) {
      Some(i) => {
        entries[i].refs = entries[i].refs + 1
      }
      None => {
        let stop = bind(key, source) catch { e => raise e }
        entries.push({ key, source, refs: 1, stop })
      }
    }
    onclr(fn() {
      match find_scoped_ref_bind(binds.val, key, source) {
        Some(i) => {
          let entry = binds.val[i]
          entry.refs = entry.refs - 1
          if entry.refs <= 0 {
            (entry.stop)()
            let _ = binds.val.remove(i)
          }
        }
        None => ()
      }
    })
  }
}

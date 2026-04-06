// ======== 持久化值和基础存储 ========
pub(all) enum PersistValue {
  Obj(Map[String, PersistValue])
  Arr(Array[PersistValue])
  Str(String)
  Int(Int)
  Bool(Bool)
  Null
  Ref(String)
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

pub fn Kv::keys_with_prefix(self: Kv, prefix: String) -> Array[String] {
  let out: Array[String] = []
  let head = prefix + "/"
  for key, _ in self.data.val {
    if has_prefix(key, head) { out.push(key) }
  }
  out
}

// ======== Persist 协议和基础实现 ========
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
    let stop = scope(() => {
      let _ = effect(() => { kv.set(key, source.get().pack()) })
      ()
    })
    stop
  }
}

// ======== 节点级存储状态 ========

priv struct BoundNode {
  mut value: PersistValue
  mut kids: Array[String]
  mut refs: Int
  mut stop: () -> Unit
}

priv struct StorageState {
  kv: Kv
  prefix: String
  node_to_id: Array[(PersistValue, String)]
  nodes: Map[String, Ref[BoundNode]]
  id_counter: Ref[Int]
}

// ======== 节点状态初始化 ========
fn StorageState::new(kv: Kv, prefix: String) -> StorageState {
  {
    kv,
    prefix,
    node_to_id: [],
    nodes: Map::new(),
    id_counter: Ref::new(0),
  }
}

fn StorageState::alloc_id(self: StorageState) -> String {
  let mut id = self.id_counter.val.to_string()
  self.id_counter.val = self.id_counter.val + 1
  while self.nodes.contains(id) {
    id = self.id_counter.val.to_string()
    self.id_counter.val = self.id_counter.val + 1
  }
  id
}

// ======== 节点身份索引和容器改写 ========
fn remove_node_id(items: Array[(PersistValue, String)], id: String) -> Unit {
  for i = 0; i < items.length(); i = i + 1 {
    if items[i].1 == id {
      let _ = items.remove(i)
      return
    }
  }
}

fn push_unique(ids: Array[String], id: String) -> Unit {
  if !ids.contains(id) { ids.push(id) }
}

fn has_prefix(s: String, p: String) -> Bool {
  s.length() >= p.length() && s[:p.length()].to_string() == p
}

fn StorageState::find_node_id(self: StorageState, v: PersistValue) -> Option[String] {
  for item in self.node_to_id {
    match (item.0, v) {
      (Obj(a), Obj(b)) => if physical_equal(a, b) { return Some(item.1) }
      (Arr(a), Arr(b)) => if physical_equal(a, b) { return Some(item.1) }
      _ => ()
    }
  }
  None
}

fn map_container(
  v: PersistValue,
  f: (PersistValue) -> PersistValue
) -> PersistValue {
  match v {
    Obj(m) => {
      let out: Map[String, PersistValue] = Map::new()
      for k, field in m {
        out.set(k, f(field))
      }
      PersistValue::Obj(out)
    }
    Arr(a) => {
      let out: Array[PersistValue] = []
      for field in a {
        out.push(f(field))
      }
      PersistValue::Arr(out)
    }
    _ => v
  }
}

fn walk_container(v: PersistValue, f: (PersistValue) -> Unit) -> Unit {
  match v {
    Obj(m) => for _, field in m { f(field) }
    Arr(a) => for field in a { f(field) }
    _ => ()
  }
}

fn reuse_container(saved: PersistValue, old: Option[PersistValue]) -> PersistValue {
  match saved {
    Obj(_) => match old {
      Some(Obj(_) as prev) => prev
      _ => Obj(Map::new())
    }
    Arr(_) => match old {
      Some(Arr(_) as prev) => prev
      _ => Arr([])
    }
    _ => Null
  }
}

fn StorageState::field_value(self: StorageState, v: PersistValue) -> PersistValue {
  match self.find_node_id(v) {
    Some(id) => PersistValue::Ref(id)
    None => v
  }
}

fn StorageState::encode_node(self: StorageState, v: PersistValue) -> PersistValue {
  map_container(v, fn(field) { self.field_value(field) })
}

// ======== 节点绑定和同步 ========
fn StorageState::attach_node(self: StorageState, id: String, v: PersistValue) -> Unit raise {
  if self.nodes.contains(id) { return }
  let entry = Ref::new({ value: v, kids: [], refs: if id == "0" { 1 } else { 0 }, stop: fn() {} })
  match v {
    Obj(_) | Arr(_) => self.node_to_id.push((v, id))
    _ => ()
  }
  self.nodes.set(id, entry)
  let stop = scope(fn() {
    let _ = on_post_flush(fn() { self.sync_node_now(id) })
    ()
  })
  entry.val.stop = stop
}

fn StorageState::ensure_node(self: StorageState, v: PersistValue) -> String raise {
  match self.find_node_id(v) {
    Some(id) => id
    None => match v {
      Obj(_) | Arr(_) => {
        let id = self.alloc_id()
        self.attach_node(id, v)
        self.sync_node(id)
        id
      }
      _ => abort("node value required")
    }
  }
}

fn StorageState::collect_kids(self: StorageState, v: PersistValue) -> Array[String] {
  let out: Array[String] = []
  walk_container(v, fn(field) {
    match self.find_node_id(field) {
      Some(id) => push_unique(out, id)
      None => match field {
        Obj(_) | Arr(_) => push_unique(out, self.ensure_node(field) catch { _ => abort("collect kids failed") })
        _ => ()
      }
    }
  })
  out
}

fn StorageState::with_node(self: StorageState, id: String, f: (BoundNode) -> Unit) -> Unit {
  if self.nodes.get(id) is Some(entry) { f(entry.val) }
}

fn StorageState::drop_node(self: StorageState, id: String) -> Unit {
  self.with_node(id, fn(node) {
    let kids = node.kids.copy()
    (node.stop)()
    match node.value {
      Obj(_) | Arr(_) => remove_node_id(self.node_to_id, id)
      _ => ()
    }
    let _ = self.nodes.remove(id)
    kids.each(fn(child) { self.dec_ref(child) })
  })
}

fn StorageState::inc_ref(self: StorageState, id: String) -> Unit {
  if id == "0" { return }
  self.with_node(id, fn(node) { node.refs = node.refs + 1 })
}

fn StorageState::dec_ref(self: StorageState, id: String) -> Unit {
  if id == "0" { return }
  self.with_node(id, fn(node) {
    node.refs = node.refs - 1
    if node.refs <= 0 { self.drop_node(id) }
  })
}

fn StorageState::update_kids(self: StorageState, id: String, next: Array[String]) -> Unit {
  self.with_node(id, fn(node) {
    let prev = node.kids.copy()
    prev.each(fn(old_id) { if !next.contains(old_id) { self.dec_ref(old_id) } })
    next.each(fn(new_id) { if !prev.contains(new_id) { self.inc_ref(new_id) } })
    node.kids = next
  })
}

fn StorageState::sync_node(self: StorageState, id: String) -> Unit {
  if self.nodes.get(id) is Some(entry) {
    let next_kids = self.collect_kids(entry.val.value)
    let dehydrated = self.encode_node(entry.val.value)
    self.update_kids(id, next_kids)
    self.kv.set(self.prefix + "/" + id, dehydrated)
  }
}

fn StorageState::sync_node_now(self: StorageState, id: String) -> Unit {
  self.sync_node(id)
}

// ======== 节点回填和根绑定 ========
fn StorageState::rehydrate_value(self: StorageState, v: PersistValue, old: Option[PersistValue]) -> PersistValue raise {
  match v {
    Ref(id) => {
      match self.nodes.get(id) {
        Some(entry) => entry.val.value
        None => {
          match self.kv.get(self.prefix + "/" + id) {
            Some(saved) => {
              let node = reuse_container(saved, old)
              match node {
                Obj(_) | Arr(_) => {
                  self.attach_node(id, node)
                  self.hydrate_node(id, node)
                  node
                }
                _ => PersistValue::Null
              }
            }
            None => PersistValue::Null
          }
        }
      }
    }
    Obj(m) => {
      let out: Map[String, PersistValue] = match old {
        Some(Obj(prev)) => prev
        _ => Map::new()
      }
      for k, v in m {
        out.set(k, self.rehydrate_value(v, out.get(k)))
      }
      PersistValue::Obj(out)
    }
    Arr(m) => {
      let out: Array[PersistValue] = match old {
        Some(Arr(prev)) => prev
        _ => []
      }
      out.clear()
      for v in m { out.push(self.rehydrate_value(v, None)) }
      PersistValue::Arr(out)
    }
    _ => v
  }
}

fn StorageState::hydrate_node(self: StorageState, id: String, v: PersistValue) -> Unit raise {
  match self.kv.get(self.prefix + "/" + id) {
    Some(saved) => {
      match (v, saved) {
        (Obj(m), Obj(s)) => {
          for k, sv in s {
            let val = self.rehydrate_value(sv, m.get(k))
            m.set(k, val)
          }
          let keys: Array[String] = []
          for k, _ in m { if !s.contains(k) { keys.push(k) } }
          for k in keys { m.remove(k) }
        }
        (Arr(m), Arr(s)) => {
          m.clear()
          for sv in s { m.push(self.rehydrate_value(sv, None)) }
        }
        _ => ()
      }
    }
    None => ()
  }
}

fn StorageState::sync_root(self: StorageState, v: PersistValue) -> Unit raise {
  match self.nodes.get("0") {
    Some(entry) => entry.val.value = v
    None => self.attach_node("0", v)
  }
  self.sync_node("0")
}

fn StorageState::attach_existing_root(self: StorageState, v: PersistValue) -> Unit raise {
  self.attach_node("0", v)
}

// ======== 节点级公开绑定入口 ========
pub fn[T: Persist] bind_refs_with_kv(kv: Kv) -> (String, Cel[T]) -> (() -> Unit) raise {
  fn(prefix: String, root_cel: Cel[T]) raise {
    let state = StorageState::new(kv, prefix)
    let root_val = root_cel.peek().pack()
    let root_id = "0"
    
    match kv.get(prefix + "/0") {
      Some(_) => {
        state.attach_existing_root(root_val)
        state.hydrate_node(root_id, root_val)
        root_cel.set(T::unpack(root_val, old=Some(root_cel.peek())))
        match state.nodes.get("0") {
          Some(entry) => entry.val.value = root_cel.peek().pack()
          None => ()
        }
      }
      None => state.sync_root(root_val)
    }

    let stop_root = scope(() => {
      let _ = effect(() => {
        let val = root_cel.get().pack()
        match state.nodes.get("0") {
          Some(entry) => entry.val.value = val
          None => ()
        }
      })
      let _ = on_post_flush(fn() {
        state.sync_root(root_cel.peek().pack()) catch { _ => abort("storage root sync failed") }
      })
      ()
    })

    fn() {
      stop_root()
      let ids: Array[String] = []
      for id, _ in state.nodes { ids.push(id) }
      ids.each(fn(id) { state.drop_node(id) })
    }
  }
}

priv struct ScopedRefBind[T] {
  key: String
  source: Cel[T]
  mut refs: Int
  stop: () -> Unit
}

// ======== scoped 绑定复用 ========
fn[T] same_ref_source(a: Cel[T], b: Cel[T]) -> Bool {
  physical_equal(a.cell, b.cell)
}

fn[T] find_scoped_ref_bind(
  binds: Array[ScopedRefBind[T]],
  key: String,
  source: Cel[T]
) -> Int? {
  for i = 0; i < binds.length(); i = i + 1 {
    let entry = binds[i]
    if entry.key == key && same_ref_source(entry.source, source) { return Some(i) }
  }
  None
}

pub fn[T: Persist] bind_refs_scoped_with_kv(kv: Kv) -> (String, Cel[T]) -> Unit raise {
  let binds: Ref[Array[ScopedRefBind[T]]] = Ref::new([])
  let bind = bind_refs_with_kv(kv)
  fn(key: String, source: Cel[T]) raise {
    let entries = binds.val
    match find_scoped_ref_bind(entries, key, source) {
      Some(i) => entries[i].refs = entries[i].refs + 1
      None => {
        let stop = bind(key, source) catch { e => raise e }
        entries.push({ key, source, refs: 1, stop })
      }
    }
    onclr(fn() {
      if find_scoped_ref_bind(binds.val, key, source) is Some(i) {
        let entry = binds.val[i]
        entry.refs = entry.refs - 1
        if entry.refs <= 0 {
          (entry.stop)()
          let _ = binds.val.remove(i)
        }
      }
    })
  }
}

// ======== 节点键和显式 gc ========
fn node_key_id(prefix: String, key: String) -> String? {
  let head = prefix + "/"
  if key.length() <= head.length() { return None }
  if key[:head.length()].to_string() != head { return None }
  let id = key[head.length():].to_string()
  if id.split("/").collect().length() != 1 { return None }
  Some(id)
}

fn collect_ref_ids(v: PersistValue, out: Array[String]) -> Unit {
  match v {
    Ref(id) => push_unique(out, id)
    _ => walk_container(v, fn(field) { collect_ref_ids(field, out) })
  }
}

pub fn gc_refs(kv: Kv, prefix: String) -> Unit {
  let live: Array[String] = []
  let queue: Array[String] = []
  if kv.get(prefix + "/0") is Some(_) {
    live.push("0")
    queue.push("0")
  }
  for i = 0; i < queue.length(); i = i + 1 {
    let id = queue[i]
    match kv.get(prefix + "/" + id) {
      Some(v) => {
        let refs: Array[String] = []
        collect_ref_ids(v, refs)
        for child in refs {
          if !live.contains(child) {
            live.push(child)
            queue.push(child)
          }
        }
      }
      None => ()
    }
  }
  let stale: Array[String] = []
  for key in kv.keys_with_prefix(prefix) {
    match node_key_id(prefix, key) {
      Some(id) => if !live.contains(id) { stale.push(key) }
      None => ()
    }
  }
  for key in stale {
    kv.delete(key)
  }
}

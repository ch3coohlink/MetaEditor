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
    let stop = scope(fn() raise {
      let _ = effect(fn() raise { kv.set(key, source.get().pack()) })
      ()
    })
    stop
  }
}

// --- Decentralized Node-level Storage ---

priv struct StorageState {
  kv: Kv
  prefix: String
  obj_to_id: Array[(Map[String, PersistValue], String)]
  arr_to_id: Array[(Array[PersistValue], String)]
  id_to_obj: Map[String, Map[String, PersistValue]]
  id_to_arr: Map[String, Array[PersistValue]]
  id_counter: Ref[Int]
  bound_ids: Map[String, () -> Unit]
}

fn StorageState::new(kv: Kv, prefix: String) -> StorageState {
  {
    kv,
    prefix,
    obj_to_id: [],
    arr_to_id: [],
    id_to_obj: Map::new(),
    id_to_arr: Map::new(),
    id_counter: Ref::new(0),
    bound_ids: Map::new(),
  }
}

fn StorageState::alloc_id(self: StorageState) -> String {
  let mut id = self.id_counter.val.to_string()
  self.id_counter.val = self.id_counter.val + 1
  while self.id_to_obj.contains(id) || self.id_to_arr.contains(id) || self.bound_ids.contains(id) {
    id = self.id_counter.val.to_string()
    self.id_counter.val = self.id_counter.val + 1
  }
  id
}

fn StorageState::find_obj_id(self: StorageState, m: Map[String, PersistValue]) -> Option[String] {
  for item in self.obj_to_id {
    if physical_equal(item.0, m) { return Some(item.1) }
  }
  None
}

fn StorageState::find_arr_id(self: StorageState, a: Array[PersistValue]) -> Option[String] {
  for item in self.arr_to_id {
    if physical_equal(item.0, a) { return Some(item.1) }
  }
  None
}

fn StorageState::dehydrate_shallow(self: StorageState, v: PersistValue) -> PersistValue {
  match v {
    Obj(m) => {
      let id_opt = self.find_obj_id(m)
      match id_opt {
        Some(id) => PersistValue::Ref(id)
        None => {
          let out: Map[String, PersistValue] = Map::new()
          for k, v in m {
            out.set(k, self.dehydrate_shallow(v))
          }
          PersistValue::Obj(out)
        }
      }
    }
    Arr(m) => {
      let id_opt = self.find_arr_id(m)
      match id_opt {
        Some(id) => PersistValue::Ref(id)
        None => {
          let out: Array[PersistValue] = []
          for v in m {
            out.push(self.dehydrate_shallow(v))
          }
          PersistValue::Arr(out)
        }
      }
    }
    _ => v
  }
}

fn StorageState::dehydrate_node_content(self: StorageState, v: PersistValue) -> PersistValue {
  match v {
    Obj(m) => {
      let out: Map[String, PersistValue] = Map::new()
      for k, v in m {
        out.set(k, self.dehydrate_shallow(v))
      }
      PersistValue::Obj(out)
    }
    Arr(m) => {
      let out: Array[PersistValue] = []
      for v in m {
        out.push(self.dehydrate_shallow(v))
      }
      PersistValue::Arr(out)
    }
    _ => v
  }
}

fn StorageState::ensure_bound(self: StorageState, v: PersistValue) -> Unit raise {
  match v {
    Obj(m) => {
      let id_opt = self.find_obj_id(m)
      if id_opt is None {
        self.bind_node(v, self.alloc_id())
      }
    }
    Arr(m) => {
      let id_opt = self.find_arr_id(m)
      if id_opt is None {
        self.bind_node(v, self.alloc_id())
      }
    }
    _ => ()
  }
}

fn StorageState::discover_children(self: StorageState, v: PersistValue) -> Unit raise {
  match v {
    Obj(m) => {
      for _, v in m {
        self.ensure_bound(v)
      }
    }
    Arr(m) => {
      for v in m {
        self.ensure_bound(v)
      }
    }
    _ => ()
  }
}

fn StorageState::bind_node(
  self: StorageState,
  v: PersistValue,
  id: String,
  save_now?: Bool = true
) -> Unit raise {
  if self.bound_ids.contains(id) { return }
  match v {
    Obj(m) => {
      self.obj_to_id.push((m, id))
      self.id_to_obj.set(id, m)
      let stop = scope(fn() raise {
        let _ = effect(fn() raise {
          ignore(self.dehydrate_node_content(PersistValue::Obj(m)))
        })
        let _ = on_post_flush(fn() {
          self.discover_children(PersistValue::Obj(m)) catch { _ => () }
          let dehydrated = self.dehydrate_node_content(PersistValue::Obj(m))
          self.kv.set(self.prefix + "/" + id, dehydrated)
        })
        ()
      })
      self.bound_ids.set(id, stop)
      self.discover_children(v)
      if save_now {
        let dehydrated = self.dehydrate_node_content(PersistValue::Obj(m))
        self.kv.set(self.prefix + "/" + id, dehydrated)
      }
    }
    Arr(m) => {
      self.arr_to_id.push((m, id))
      self.id_to_arr.set(id, m)
      let stop = scope(fn() raise {
        let _ = effect(fn() raise {
          ignore(self.dehydrate_node_content(PersistValue::Arr(m)))
        })
        let _ = on_post_flush(fn() {
          self.discover_children(PersistValue::Arr(m)) catch { _ => () }
          let dehydrated = self.dehydrate_node_content(PersistValue::Arr(m))
          self.kv.set(self.prefix + "/" + id, dehydrated)
        })
        ()
      })
      self.bound_ids.set(id, stop)
      self.discover_children(v)
      if save_now {
        let dehydrated = self.dehydrate_node_content(PersistValue::Arr(m))
        self.kv.set(self.prefix + "/" + id, dehydrated)
      }
    }
    _ => ()
  }
}

fn StorageState::rehydrate_value(self: StorageState, v: PersistValue, old: Option[PersistValue]) -> PersistValue raise {
  match v {
    Ref(id) => {
      match self.id_to_obj.get(id) {
        Some(m) => PersistValue::Obj(m)
        None => {
          match self.id_to_arr.get(id) {
            Some(a) => PersistValue::Arr(a)
            None => {
              match self.kv.get(self.prefix + "/" + id) {
                Some(Obj(_)) => {
                  let m: Map[String, PersistValue] = Map::new()
                  self.bind_node(Obj(m), id, save_now=false)
                  self.hydrate_node(id, Obj(m))
                  PersistValue::Obj(m)
                }
                Some(Arr(_)) => {
                  let a: Array[PersistValue] = []
                  self.bind_node(Arr(a), id, save_now=false)
                  self.hydrate_node(id, Arr(a))
                  PersistValue::Arr(a)
                }
                _ => PersistValue::Null
              }
            }
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
  match v {
    Obj(m) => {
      self.id_to_obj.set("0", m)
      if self.find_obj_id(m) is None { self.obj_to_id.push((m, "0")) }
      self.discover_children(v)
      let dehydrated = self.dehydrate_node_content(v)
      self.kv.set(self.prefix + "/0", dehydrated)
    }
    Arr(m) => {
      self.id_to_arr.set("0", m)
      if self.find_arr_id(m) is None { self.arr_to_id.push((m, "0")) }
      self.discover_children(v)
      let dehydrated = self.dehydrate_node_content(v)
      self.kv.set(self.prefix + "/0", dehydrated)
    }
    _ => {
      self.kv.set(self.prefix + "/0", v)
    }
  }
}

fn StorageState::mount_root(self: StorageState, v: PersistValue) -> Unit {
  match v {
    Obj(m) => {
      self.id_to_obj.set("0", m)
      if self.find_obj_id(m) is None { self.obj_to_id.push((m, "0")) }
    }
    Arr(m) => {
      self.id_to_arr.set("0", m)
      if self.find_arr_id(m) is None { self.arr_to_id.push((m, "0")) }
    }
    _ => ()
  }
}

pub fn[T: Persist] bind_refs_with_kv(kv: Kv) -> (String, Cel[T]) -> (() -> Unit) raise {
  fn(prefix: String, root_cel: Cel[T]) raise {
    let state = StorageState::new(kv, prefix)
    let root_val = root_cel.peek().pack()
    let root_id = "0"
    
    match kv.get(prefix + "/0") {
      Some(_) => {
        state.mount_root(root_val)
        state.hydrate_node(root_id, root_val)
        root_cel.set(T::unpack(root_val, old=Some(root_cel.peek())))
      }
      None => state.sync_root(root_val)
    }

    let stop_root = scope(fn() raise {
      let _ = effect(fn() raise {
        let val = root_cel.get().pack()
        state.sync_root(val)
      })
      let _ = on_post_flush(fn() {
        state.sync_root(root_cel.peek().pack()) catch { _ => () }
      })
      ()
    })

    fn() {
      stop_root()
      for stop in state.bound_ids.values() { stop() }
    }
  }
}

priv struct ScopedRefBind[T] {
  key: String
  source: Cel[T]
  mut refs: Int
  stop: () -> Unit
}

fn same_ref_source[T](a: Cel[T], b: Cel[T]) -> Bool {
  physical_equal(a.cell, b.cell)
}

fn find_scoped_ref_bind[T](
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

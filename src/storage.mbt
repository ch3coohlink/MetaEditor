pub(all) enum PersistValue {
  Obj(Map[String, PersistValue])
  Arr(Array[PersistValue])
  Str(String)
  Int(Int)
  Bool(Bool)
  Null
  Ref(String)
} derive(Show)

pub(all) struct GraphNode {
  id: String
  value: PersistValue
}

priv enum SeenNode {
  Obj(Map[String, PersistValue])
  Arr(Array[PersistValue])
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

fn find_seen_id(seen: Array[(SeenNode, String)], node: SeenNode) -> Option[String] {
  for entry in seen {
    let (cur, id) = entry
    match (cur, node) {
      (Obj(a), Obj(b)) => if physical_equal(a, b) { return Some(id) }
      (Arr(a), Arr(b)) => if physical_equal(a, b) { return Some(id) }
      _ => ()
    }
  }
  None
}

fn clone_graph_value(
  value: PersistValue,
  seen: Array[(SeenNode, String)],
  out: Map[String, PersistValue]
) -> PersistValue {
  match value {
    Obj(m) => {
      match find_seen_id(seen, Obj(m)) {
        Some(id) => Ref(id)
        None => {
          let id = out.length().to_string()
          seen.push((Obj(m), id))
          let node: Map[String, PersistValue] = Map::new()
          out.set(id, PersistValue::Obj(node))
          m.each(fn(k, v) { node.set(k, clone_graph_value(v, seen, out)) })
          Ref(id)
        }
      }
    }
    Arr(items) => {
      match find_seen_id(seen, Arr(items)) {
        Some(id) => Ref(id)
        None => {
          let id = out.length().to_string()
          seen.push((Arr(items), id))
          let node: Array[PersistValue] = []
          out.set(id, PersistValue::Arr(node))
          items.each(fn(v) { node.push(clone_graph_value(v, seen, out)) })
          Ref(id)
        }
      }
    }
    _ => value
  }
}

pub fn graph_clone(root: PersistValue) -> Array[GraphNode] {
  let seen: Array[(SeenNode, String)] = []
  let nodes: Map[String, PersistValue] = Map::new()
  let root_ref = clone_graph_value(root, seen, nodes)
  let root_id = match root_ref {
    Ref(id) => id
    _ => {
      nodes.set("0", root)
      "0"
    }
  }
  let out: Array[GraphNode] = []
  out.push({ id: "0", value: match nodes.get(root_id) { Some(v) => v; None => root } })
  nodes.each(fn(id, value) {
    if id != root_id { out.push({ id, value }) }
  })
  out
}

fn hydrate_graph_value(
  value: PersistValue,
  nodes: Map[String, PersistValue],
  cache: Map[String, PersistValue]
) -> PersistValue {
  match value {
    Ref(id) => hydrate_graph_node(id, nodes, cache)
    _ => value
  }
}

fn hydrate_graph_node(
  id: String,
  nodes: Map[String, PersistValue],
  cache: Map[String, PersistValue]
) -> PersistValue {
  match cache.get(id) {
    Some(value) => value
    None => {
      let value = match nodes.get(id) {
        Some(v) => v
        None => Null
      }
      match value {
        Obj(m) => {
          let out: Map[String, PersistValue] = Map::new()
          let node = PersistValue::Obj(out)
          cache.set(id, node)
          m.each(fn(k, v) { out.set(k, hydrate_graph_value(v, nodes, cache)) })
          node
        }
        Arr(items) => {
          let out: Array[PersistValue] = []
          let node = PersistValue::Arr(out)
          cache.set(id, node)
          items.each(fn(v) { out.push(hydrate_graph_value(v, nodes, cache)) })
          node
        }
        _ => {
          cache.set(id, value)
          value
        }
      }
    }
  }
}

pub fn graph_hydrate(data: Array[GraphNode]) -> PersistValue {
  let nodes: Map[String, PersistValue] = Map::new()
  data.each(fn(node) { nodes.set(node.id, node.value) })
  let cache: Map[String, PersistValue] = Map::new()
  hydrate_graph_node("0", nodes, cache)
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

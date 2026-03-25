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

priv struct GraphSaveState {
  mut seen: Array[(SeenNode, String)]
  mut next_id: Int
  mut ids: Array[String]
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

fn graph_index_key(key: String) -> String {
  key + "/@graph"
}

fn graph_node_key(key: String, id: String) -> String {
  key + "/" + id
}

fn graph_ids_from_value(value: PersistValue) -> Array[String] {
  match value {
    Arr(items) => {
      let out: Array[String] = []
      items.each(fn(item) {
        match item {
          Str(id) => out.push(id)
          _ => ()
        }
      })
      out
    }
    _ => []
  }
}

fn graph_ids_value(nodes: Array[GraphNode]) -> PersistValue {
  let ids: Array[PersistValue] = []
  nodes.each(fn(node) { ids.push(Str(node.id)) })
  Arr(ids)
}

fn graph_ids_only_value(ids: Array[String]) -> PersistValue {
  let out: Array[PersistValue] = []
  ids.each(fn(id) { out.push(Str(id)) })
  Arr(out)
}

pub fn graph_save_to_kv(
  kv: Kv,
  key: String,
  root: PersistValue
) -> Unit {
  let nodes = graph_clone(root)
  let prev_ids = match kv.get(graph_index_key(key)) {
    Some(index) => graph_ids_from_value(index)
    None => []
  }
  let next_ids: Array[String] = []
  nodes.each(fn(node) {
    next_ids.push(node.id)
    kv.set(graph_node_key(key, node.id), node.value)
  })
  for id in prev_ids {
    if not(next_ids.contains(id)) { kv.delete(graph_node_key(key, id)) }
  }
  kv.set(graph_index_key(key), graph_ids_value(nodes))
}

fn render_value(value: PersistValue) -> String {
  value.to_string()
}

fn collect_graph_value(
  value: PersistValue,
  old_seen: Array[(SeenNode, String)],
  new_seen: Array[(SeenNode, String)],
  st: GraphSaveState,
  nodes: Map[String, PersistValue]
) -> PersistValue {
  match value {
    Obj(m) => {
      match find_seen_id(new_seen, Obj(m)) {
        Some(id) => Ref(id)
        None => {
          let id = match find_seen_id(old_seen, Obj(m)) {
            Some(id) => id
            None => {
              let id = st.next_id.to_string()
              st.next_id = st.next_id + 1
              id
            }
          }
          new_seen.push((Obj(m), id))
          let out: Map[String, PersistValue] = Map::new()
          nodes.set(id, PersistValue::Obj(out))
          m.each(fn(k, v) { out.set(k, collect_graph_value(v, old_seen, new_seen, st, nodes)) })
          Ref(id)
        }
      }
    }
    Arr(items) => {
      match find_seen_id(new_seen, Arr(items)) {
        Some(id) => Ref(id)
        None => {
          let id = match find_seen_id(old_seen, Arr(items)) {
            Some(id) => id
            None => {
              let id = st.next_id.to_string()
              st.next_id = st.next_id + 1
              id
            }
          }
          new_seen.push((Arr(items), id))
          let out: Array[PersistValue] = []
          nodes.set(id, PersistValue::Arr(out))
          items.each(fn(v) { out.push(collect_graph_value(v, old_seen, new_seen, st, nodes)) })
          Ref(id)
        }
      }
    }
    _ => value
  }
}

fn graph_sync_with_state(
  kv: Kv,
  key: String,
  root: PersistValue,
  st: GraphSaveState
) -> Unit {
  let old_seen = st.seen
  let new_seen: Array[(SeenNode, String)] = []
  let nodes: Map[String, PersistValue] = Map::new()
  let root_value = match root {
    Obj(m) => {
      new_seen.push((Obj(m), "0"))
      let out: Map[String, PersistValue] = Map::new()
      m.each(fn(k, v) { out.set(k, collect_graph_value(v, old_seen, new_seen, st, nodes)) })
      PersistValue::Obj(out)
    }
    Arr(items) => {
      new_seen.push((Arr(items), "0"))
      let out: Array[PersistValue] = []
      items.each(fn(v) { out.push(collect_graph_value(v, old_seen, new_seen, st, nodes)) })
      PersistValue::Arr(out)
    }
    _ => root
  }
  nodes.set("0", root_value)
  let next_ids: Array[String] = ["0"]
  nodes.each(fn(id, value) {
    if id != "0" { next_ids.push(id) }
    match kv.get(graph_node_key(key, id)) {
      Some(prev) => if render_value(prev) != render_value(value) { kv.set(graph_node_key(key, id), value) }
      None => kv.set(graph_node_key(key, id), value)
    }
  })
  for id in st.ids {
    if not(next_ids.contains(id)) { kv.delete(graph_node_key(key, id)) }
  }
  let index_value = graph_ids_only_value(next_ids)
  match kv.get(graph_index_key(key)) {
    Some(prev) => if render_value(prev) != render_value(index_value) { kv.set(graph_index_key(key), index_value) }
    None => kv.set(graph_index_key(key), index_value)
  }
  st.seen = new_seen
  st.ids = next_ids
}

fn patch_graph_value(
  value: PersistValue,
  cur: PersistValue,
  load: (String) -> Option[PersistValue],
  cache: Map[String, PersistValue]
) -> PersistValue {
  match value {
    Ref(id) => patch_graph_node(id, cur=Some(cur), load, cache)
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
          Some(v) => v
          None => Null
        }
        target.set(k, patch_graph_value(v, cur_v, load, cache))
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
        let cur_v = if i < prev.length() { prev[i] } else { Null }
        target.push(patch_graph_value(next[i], cur_v, load, cache))
      }
      PersistValue::Arr(target)
    }
    _ => value
  }
}

fn patch_graph_node(
  id: String,
  cur? : PersistValue? = None,
  load: (String) -> Option[PersistValue],
  cache: Map[String, PersistValue]
) -> PersistValue {
  match cache.get(id) {
    Some(value) => value
    None => {
      let value = match load(id) {
        Some(v) => v
        None => Null
      }
      match value {
        Obj(next) => {
          let target = match cur {
            Some(Obj(prev)) => prev
            _ => Map::new()
          }
          let node = PersistValue::Obj(target)
          cache.set(id, node)
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
              Some(v) => v
              None => Null
            }
            target.set(k, patch_graph_value(v, cur_v, load, cache))
          })
          node
        }
        Arr(next) => {
          let target = match cur {
            Some(Arr(prev)) => prev
            _ => []
          }
          let node = PersistValue::Arr(target)
          cache.set(id, node)
          let prev = target.copy()
          target.clear()
          for i = 0; i < next.length(); i = i + 1 {
            let cur_v = if i < prev.length() { prev[i] } else { Null }
            target.push(patch_graph_value(next[i], cur_v, load, cache))
          }
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

pub fn graph_patch_with(
  root: PersistValue,
  load: (String) -> Option[PersistValue]
) -> PersistValue {
  let cache: Map[String, PersistValue] = Map::new()
  patch_graph_node("0", cur=Some(root), load, cache)
}

pub fn graph_patch(root: PersistValue, data: Array[GraphNode]) -> PersistValue {
  let nodes: Map[String, PersistValue] = Map::new()
  data.each(fn(node) { nodes.set(node.id, node.value) })
  graph_patch_with(root, fn(id) { nodes.get(id) })
}

pub fn graph_load_from_kv(root: PersistValue, kv: Kv, key: String) -> Option[PersistValue] {
  match kv.get(graph_index_key(key)) {
    Some(_) => Some(graph_patch_with(root, fn(id) { kv.get(graph_node_key(key, id)) }))
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

pub fn bind_graph_with_kv(kv: Kv) -> (String, Cel[PersistValue]) -> (() -> Unit) raise {
  fn(key: String, source: Cel[PersistValue]) raise {
    match graph_load_from_kv(source.peek(), kv, key) {
      Some(value) => source.set(value)
      None => ()
    }
    let st = {
      seen: [],
      next_id: 1,
      ids: match kv.get(graph_index_key(key)) {
        Some(index) => graph_ids_from_value(index)
        None => []
      },
    }
    graph_sync_with_state(kv, key, source.peek(), st)
    scope(fn() raise {
      let _ = effect(() => graph_sync_with_state(kv, key, source.get(), st))
      let _ = on_post_flush(fn() { graph_sync_with_state(kv, key, source.peek(), st) })
      ()
    })
  }
}

fn assert_obj(value: PersistValue, label: String) -> Map[String, PersistValue] {
  match value {
    Obj(m) => m
    _ => abort(label)
  }
}

fn assert_arr(value: PersistValue, label: String) -> Array[PersistValue] {
  match value {
    Arr(items) => items
    _ => abort(label)
  }
}

fn assert_kv_obj(
  kv: Kv,
  key: String,
  label: String
) -> Map[String, PersistValue] {
  match kv.get(key) {
    Some(v) => assert_obj(v, label)
    None => abort(label)
  }
}

fn assert_obj_str(
  m: Map[String, PersistValue],
  key: String,
  expected: String,
  label: String
) -> Unit raise {
  match m.get(key) {
    Some(Str(v)) => assert_eq(v, expected)
    _ => abort(label)
  }
}

fn assert_obj_int(
  m: Map[String, PersistValue],
  key: String,
  expected: Int,
  label: String
) -> Unit raise {
  match m.get(key) {
    Some(Int(v)) => assert_eq(v, expected)
    _ => abort(label)
  }
}

fn assert_item_str(
  items: Array[PersistValue],
  index: Int,
  expected: String,
  label: String
) -> Unit raise {
  match items[index] {
    Str(v) => assert_eq(v, expected)
    _ => abort(label)
  }
}

fn assert_prefs_item(
  items: Array[PersistValue],
  index: Int,
  name: String,
  age: Int,
  label: String
) -> Unit raise {
  let m = assert_obj(items[index], label)
  assert_obj_str(m, "10", name, label + "-name")
  assert_obj_int(m, "20", age, label + "-age")
}

struct Prefs {
  mut name: String
  mut age: Int
}

struct Doc {
  title: String
  tags: Array[String]
}

struct Group {
  members: Array[Prefs]
}

struct CellPrefs {
  title: Cel[String]
  age: Cel[Int]
}

pub impl Persist for Prefs with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.name)),
    ("20", pack(self.age)),
  ])
}

pub impl Persist for Prefs with unpack(
  value: PersistValue,
  old? : Prefs? = None
) -> Prefs {
  ignore(old)
  match value {
    Obj(m) => {
      let name: String = match m.get("10") {
        Some(v) => unpack(v)
        None => "anon"
      }
      let age: Int = match m.get("20") {
        Some(v) => unpack(v)
        None => 18
      }
      { name, age }
    }
    _ => { name: "anon", age: 18 }
  }
}

pub impl Persist for Doc with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.title)),
    ("20", pack(self.tags)),
  ])
}

pub impl Persist for Doc with unpack(
  value: PersistValue,
  old? : Doc? = None
) -> Doc {
  ignore(old)
  match value {
    Obj(m) => {
      let title: String = match m.get("10") {
        Some(v) => unpack(v)
        None => ""
      }
      let tags: Array[String] = match m.get("20") {
        Some(v) => unpack(v)
        None => []
      }
      { title, tags }
    }
    _ => { title: "", tags: [] }
  }
}

pub impl Persist for Group with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.members)),
  ])
}

pub impl Persist for Group with unpack(
  value: PersistValue,
  old? : Group? = None
) -> Group {
  ignore(old)
  match value {
    Obj(m) => {
      let members: Array[Prefs] = match m.get("10") {
        Some(v) => unpack(v)
        None => []
      }
      { members, }
    }
    _ => { members: [] }
  }
}

pub impl Persist for CellPrefs with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.title)),
    ("20", pack(self.age)),
  ])
}

pub impl Persist for CellPrefs with unpack(
  value: PersistValue,
  old? : CellPrefs? = None
) -> CellPrefs {
  let title_default = match old {
    Some(prev) => Some(prev.title)
    None => None
  }
  let age_default = match old {
    Some(prev) => Some(prev.age)
    None => None
  }
  match value {
    Obj(m) => {
      let title = match m.get("10") {
        Some(v) => unpack(v, old=title_default)
        None => match title_default {
          Some(prev) => prev
          None => cel("")
        }
      }
      let age = match m.get("20") {
        Some(v) => unpack(v, old=age_default)
        None => match age_default {
          Some(prev) => prev
          None => cel(18)
        }
      }
      { title, age }
    }
    _ => {
      title: match title_default {
        Some(prev) => prev
        None => cel("")
      },
      age: match age_default {
        Some(prev) => prev
        None => cel(18)
      },
    }
  }
}

test "persist packs typed records and fills defaults" {
  let prefs = { name: "Ada", age: 18 }
  let packed = prefs.pack()
  let m = assert_obj(packed, "obj")
  assert_obj_str(m, "10", "Ada", "name")
  assert_obj_int(m, "20", 18, "age")
  let upgraded = Prefs::unpack(obj([]))
  assert_eq(upgraded.name, "anon")
  assert_eq(upgraded.age, 18)
}

test "bind_with_kv serializes cel mutate" {
  let kv = open_kv()
  let bind = bind_with_kv(kv)
  let state = cel({ name: "Ada", age: 18 })
  let stop = bind("prefs", state) catch { _ => abort("bind") }

  let first = assert_kv_obj(kv, "prefs", "missing first save")
  assert_obj_str(first, "10", "Ada", "first-name")
  assert_obj_int(first, "20", 18, "first-age")

  state.mutate(p => {
    p.name = "Cora"
    p.age = 21
  })
  flush() catch { _ => abort("flush") }

  let second = assert_kv_obj(kv, "prefs", "missing second save")
  assert_obj_str(second, "10", "Cora", "second-name")
  assert_obj_int(second, "20", 21, "second-age")
  stop()
}

test "bind_with_kv supports arrays and nested objects" {
  let kv = open_kv()
  let bind = bind_with_kv(kv)
  let state = cel({
    title: "Notes",
    tags: ["moonbit"],
  })
  let stop = bind("doc", state) catch { _ => abort("bind") }

  state.mutate(d => {
    d.tags.push("storage")
  })
  flush() catch { _ => abort("flush") }

  let saved = assert_kv_obj(kv, "doc", "missing doc")
  let tags = match saved.get("20") {
    Some(v) => assert_arr(v, "tags")
    None => abort("tags")
  }
  assert_eq(tags.length(), 2)
  assert_item_str(tags, 0, "moonbit", "tag-0")
  assert_item_str(tags, 1, "storage", "tag-1")
  stop()
}

test "bind_with_kv supports array of objects" {
  let kv = open_kv()
  let bind = bind_with_kv(kv)
  let state = cel({
    members: [
      { name: "Ada", age: 18 },
      { name: "Bea", age: 20 },
    ],
  })
  let stop = bind("group", state) catch { _ => abort("bind") }

  state.mutate(g => {
    g.members[0].age = 19
    g.members.push({ name: "Cora", age: 21 })
  })
  flush() catch { _ => abort("flush") }

  let saved = assert_kv_obj(kv, "group", "missing group")
  let items = match saved.get("10") {
    Some(v) => assert_arr(v, "members")
    None => abort("members")
  }
  assert_eq(items.length(), 3)
  assert_prefs_item(items, 0, "Ada", 19, "member-0")
  assert_prefs_item(items, 1, "Bea", 20, "member-1")
  assert_prefs_item(items, 2, "Cora", 21, "member-2")
  stop()
}

test "bind_with_kv tracks nested cel fields recursively" {
  let kv = open_kv()
  let bind = bind_with_kv(kv)
  let state = cel({
    title: cel("Ada"),
    age: cel(18),
  })
  let stop = bind("cell-prefs", state) catch { _ => abort("bind") }

  state.peek().title.set("Bea")
  flush() catch { _ => abort("flush-title") }

  let first = assert_kv_obj(kv, "cell-prefs", "missing cell-prefs-1")
  assert_obj_str(first, "10", "Bea", "title")
  assert_obj_int(first, "20", 18, "age-1")

  state.peek().age.set(19)
  flush() catch { _ => abort("flush-age") }

  let second = assert_kv_obj(kv, "cell-prefs", "missing cell-prefs-2")
  assert_obj_str(second, "10", "Bea", "title-2")
  assert_obj_int(second, "20", 19, "age-2")
  stop()
}

test "bind_with_kv keeps nested cel identity when loading existing value" {
  let kv = open_kv()
  kv.set("cell-prefs", obj([
    ("10", pack("Bea")),
    ("20", pack(19)),
  ]))
  let bind = bind_with_kv(kv)
  let state = cel({
    title: cel("Ada"),
    age: cel(18),
  })
  let title = state.peek().title
  let age = state.peek().age
  let stop = bind("cell-prefs", state) catch { _ => abort("bind") }

  assert_eq(physical_equal(title, state.peek().title), true)
  assert_eq(physical_equal(age, state.peek().age), true)
  assert_eq(title.peek(), "Bea")
  assert_eq(age.peek(), 19)

  title.set("Cora")
  flush() catch { _ => abort("flush-title") }

  let saved = assert_kv_obj(kv, "cell-prefs", "missing cell-prefs")
  assert_obj_str(saved, "10", "Cora", "title")
  assert_obj_int(saved, "20", 19, "age")
  stop()
}

test "bind_with_kv keeps old cel when persisted object misses field" {
  let kv = open_kv()
  kv.set("cell-prefs", obj([
    ("10", pack("Bea")),
  ]))
  let bind = bind_with_kv(kv)
  let state = cel({
    title: cel("Ada"),
    age: cel(18),
  })
  let title = state.peek().title
  let age = state.peek().age
  let stop = bind("cell-prefs", state) catch { _ => abort("bind") }

  assert_eq(physical_equal(title, state.peek().title), true)
  assert_eq(physical_equal(age, state.peek().age), true)
  assert_eq(title.peek(), "Bea")
  assert_eq(age.peek(), 18)

  age.set(20)
  flush() catch { _ => abort("flush-age") }

  let saved = assert_kv_obj(kv, "cell-prefs", "missing cell-prefs")
  assert_obj_str(saved, "10", "Bea", "title")
  assert_obj_int(saved, "20", 20, "age")
  stop()
}

test "bind_with_kv keeps array cel identity when loading existing value" {
  let kv = open_kv()
  kv.set("cell-list", arr([
    pack("Bea"),
    pack("Cora"),
  ]))
  let bind = bind_with_kv(kv)
  let state = cel([
    cel("Ada"),
    cel("Dana"),
  ])
  let first = state.peek()[0]
  let second = state.peek()[1]
  let stop = bind("cell-list", state) catch { _ => abort("bind") }

  assert_eq(physical_equal(first, state.peek()[0]), true)
  assert_eq(physical_equal(second, state.peek()[1]), true)
  assert_eq(first.peek(), "Bea")
  assert_eq(second.peek(), "Cora")

  second.set("Eve")
  flush() catch { _ => abort("flush-second") }

  let items = match kv.get("cell-list") {
    Some(v) => assert_arr(v, "missing cell-list")
    None => abort("missing cell-list")
  }
  assert_eq(items.length(), 2)
  assert_item_str(items, 0, "Bea", "item-0")
  assert_item_str(items, 1, "Eve", "item-1")
  stop()
}

test "bind_with_kv stops syncing after stop" {
  let kv = open_kv()
  let bind = bind_with_kv(kv)
  let state = cel({ name: "Ada", age: 18 })
  let stop = bind("prefs", state) catch { _ => abort("bind") }

  stop()
  state.mutate(p => {
    p.name = "Bea"
    p.age = 19
  })
  flush() catch { _ => abort("flush") }

  let saved = assert_kv_obj(kv, "prefs", "missing prefs")
  assert_obj_str(saved, "10", "Ada", "name")
  assert_obj_int(saved, "20", 18, "age")
}

test "bind_refs_with_kv stores child nodes by ref" {
  let child = obj([("name", PersistValue::Str("Ada"))])
  let root = obj([
    ("left", child),
    ("right", child),
  ])
  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind") }

  let root_node = assert_kv_obj(kv, "refs/0", "root")
  match root_node.get("left") {
    Some(Ref(id)) => {
      assert_eq(id, "1")
      match root_node.get("right") {
        Some(Ref(id2)) => assert_eq(id, id2)
        _ => abort("right")
      }
    }
    _ => abort("left")
  }
  let child_node = assert_kv_obj(kv, "refs/1", "child")
  assert_obj_str(child_node, "name", "Ada", "child-name")
  stop()
}

test "bind_refs_with_kv loads shared child identity" {
  let kv = open_kv()
  kv.set("refs/0", obj([("left", Ref("1")), ("right", Ref("1"))]))
  kv.set("refs/1", obj([("name", PersistValue::Str("Bea"))]))
  
  let bind = bind_refs_with_kv(kv)
  let root = obj([
    ("left", obj([("name", PersistValue::Str("Ada"))])),
    ("right", obj([("name", PersistValue::Str("Ada"))])),
  ])
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind") }

  match state.peek() {
    Obj(m) => {
      let left = match m.get("left") { Some(Obj(v)) => v; _ => abort("left") }
      let right = match m.get("right") { Some(Obj(v)) => v; _ => abort("right") }
      assert_eq(physical_equal(left, right), true)
      match left.get("name") { Some(Str(v)) => assert_eq(v, "Bea"); _ => abort("name") }
    }
    _ => abort("state")
  }
  stop()
}

test "bind_refs_with_kv saves nested mutate" {
  let child = obj([("name", PersistValue::Str("Ada"))])
  let root = obj([("left", child)])
  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind") }

  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(c)) => c.set("name", PersistValue::Str("Bea"))
        _ => abort("child")
      }
    }
    _ => abort("root")
  }
  flush() catch { _ => abort("flush") }

  let child_node = assert_kv_obj(kv, "refs/1", "child")
  assert_obj_str(child_node, "name", "Bea", "child-name")
  stop()
}

test "bind_refs_with_kv handles self cycle" {
  let root_map: Map[String, PersistValue] = Map::new()
  let root = PersistValue::Obj(root_map)
  root_map.set("self", root)
  
  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("cycle", state) catch { _ => abort("bind") }

  let saved = assert_kv_obj(kv, "cycle/0", "missing cycle")
  match saved.get("self") {
    Some(Ref(id)) => assert_eq(id, "0")
    _ => abort("self-ref")
  }
  stop()
}

test "bind_refs_with_kv keeps stale child snapshot in kv" {
  let child = obj([("name", PersistValue::Str("Ada"))])
  let root = obj([("left", child)])
  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind") }

  let next = obj([("title", PersistValue::Str("Bea"))])
  state.set(next)
  flush() catch { _ => abort("flush") }

  let root_node = assert_kv_obj(kv, "refs/0", "root")
  assert_obj_str(root_node, "title", "Bea", "title")
  let child_node = assert_kv_obj(kv, "refs/1", "stale-child")
  assert_obj_str(child_node, "name", "Ada", "stale-child-name")
  stop()
}

test "bind_refs_with_kv keeps shared child alive after single-side detach" {
  let child = obj([("name", PersistValue::Str("Ada"))])
  let root = obj([
    ("left", child),
    ("right", child),
  ])
  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind") }

  match state.peek() {
    Obj(m) => m.remove("left")
    _ => abort("root-1")
  }
  flush() catch { _ => abort("flush-1") }

  let root_node = assert_kv_obj(kv, "refs/0", "root")
  match root_node.get("right") {
    Some(Ref(id)) => assert_eq(id, "1")
    _ => abort("right-ref")
  }
  let child1 = assert_kv_obj(kv, "refs/1", "child-1")
  assert_obj_str(child1, "name", "Ada", "name-1")

  match state.peek() {
    Obj(m) => {
      match m.get("right") {
        Some(Obj(c)) => c.set("name", PersistValue::Str("Bea"))
        _ => abort("right")
      }
    }
    _ => abort("root-2")
  }
  flush() catch { _ => abort("flush-2") }

  let child2 = assert_kv_obj(kv, "refs/1", "child-2")
  assert_obj_str(child2, "name", "Bea", "name-2")
  stop()
}

test "bind_refs_with_kv keeps nested orphan snapshots after root shrink" {
  let leaf = obj([("name", PersistValue::Str("Ada"))])
  let mid = obj([("child", leaf)])
  let root = obj([("branch", mid)])
  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind") }

  state.set(obj([("title", PersistValue::Str("Bea"))]))
  flush() catch { _ => abort("flush") }

  let root_node = assert_kv_obj(kv, "refs/0", "root")
  assert_obj_str(root_node, "title", "Bea", "title")
  let mid_node = assert_kv_obj(kv, "refs/1", "mid")
  match mid_node.get("child") {
    Some(Ref(id)) => assert_eq(id, "2")
    _ => abort("mid-child")
  }
  let leaf_node = assert_kv_obj(kv, "refs/2", "leaf")
  assert_obj_str(leaf_node, "name", "Ada", "leaf-name")
  stop()
}

test "bind_refs_with_kv keeps shared child in array after single-side detach" {
  let child = obj([("name", PersistValue::Str("Ada"))])
  let root = arr([child, child])
  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind") }

  match state.peek() {
    Arr(items) => {
      let _ = items.remove(0)
    }
    _ => abort("root-1")
  }
  flush() catch { _ => abort("flush-1") }

  let root_items = assert_arr(match kv.get("refs/0") {
    Some(v) => v
    None => abort("root")
  }, "root")
  match root_items[0] {
    Ref(id) => assert_eq(id, "1")
    _ => abort("item-ref")
  }

  match state.peek() {
    Arr(items) => {
      match items[0] {
        Obj(c) => c.set("name", PersistValue::Str("Bea"))
        _ => abort("child")
      }
    }
    _ => abort("root-2")
  }
  flush() catch { _ => abort("flush-2") }

  let child_node = assert_kv_obj(kv, "refs/1", "child")
  assert_obj_str(child_node, "name", "Bea", "child-name")
  stop()
}

test "bind_refs_scoped_with_kv stops after last scope clears" {
  let child = obj([("name", PersistValue::Str("Ada"))])
  let root = obj([("left", child)])
  let kv = open_kv()
  let bind = bind_refs_scoped_with_kv(kv)
  let state = cel(root)

  let stop1 = scope(fn() raise {
    bind("refs", state)
    ()
  }) catch { _ => abort("scope-1") }
  let stop2 = scope(fn() raise {
    bind("refs", state)
    ()
  }) catch { _ => abort("scope-2") }

  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(c)) => c.set("name", PersistValue::Str("Bea"))
        _ => abort("child-1")
      }
    }
    _ => abort("root-1")
  }
  flush() catch { _ => abort("flush-1") }
  let child1 = assert_kv_obj(kv, "refs/1", "child-1")
  assert_obj_str(child1, "name", "Bea", "name-1")

  stop1()
  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(c)) => c.set("name", PersistValue::Str("Cora"))
        _ => abort("child-2")
      }
    }
    _ => abort("root-2")
  }
  flush() catch { _ => abort("flush-2") }
  let child2 = assert_kv_obj(kv, "refs/1", "child-2")
  assert_obj_str(child2, "name", "Cora", "name-2")

  stop2()
  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(c)) => c.set("name", PersistValue::Str("Dana"))
        _ => abort("child-3")
      }
    }
    _ => abort("root-3")
  }
  flush() catch { _ => abort("flush-3") }
  let child3 = assert_kv_obj(kv, "refs/1", "child-3")
  assert_obj_str(child3, "name", "Cora", "name-3")
}

test "bind_refs_with_kv stop drops child watchers with root" {
  let child = obj([("name", PersistValue::Str("Ada"))])
  let root = obj([("left", child)])
  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind") }

  flush() catch { _ => abort("flush-1") }
  stop()

  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(c)) => c.set("name", PersistValue::Str("Bea"))
        _ => abort("child")
      }
    }
    _ => abort("root")
  }
  flush() catch { _ => abort("flush-2") }

  let child_node = assert_kv_obj(kv, "refs/1", "child")
  assert_obj_str(child_node, "name", "Ada", "child-name")
}

test "bind_refs_with_kv reloads from kv after stop" {
  let child = obj([("name", PersistValue::Str("Ada"))])
  let root = obj([("left", child)])
  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind-1") }

  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(c)) => c.set("name", PersistValue::Str("Bea"))
        _ => abort("child-1")
      }
    }
    _ => abort("root-1")
  }
  flush() catch { _ => abort("flush-1") }
  stop()

  let next = cel(obj([
    ("left", obj([("name", PersistValue::Str("Cora"))])),
  ]))
  let stop2 = bind("refs", next) catch { _ => abort("bind-2") }

  match next.peek() {
    Obj(m) => {
      let left = match m.get("left") { Some(Obj(v)) => v; _ => abort("left") }
      match left.get("name") {
        Some(Str(v)) => assert_eq(v, "Bea")
        _ => abort("name")
      }
    }
    _ => abort("root-2")
  }
  stop2()
}

test "gc_refs removes stale orphan snapshots" {
  let child = obj([("name", PersistValue::Str("Ada"))])
  let root = obj([("left", child)])
  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind") }

  state.set(obj([("title", PersistValue::Str("Bea"))]))
  flush() catch { _ => abort("flush") }
  stop()

  gc_refs(kv, "refs")

  let root_node = assert_kv_obj(kv, "refs/0", "root")
  assert_obj_str(root_node, "title", "Bea", "title")
  match kv.get("refs/1") {
    None => ()
    Some(_) => abort("stale-child")
  }
}

test "gc_refs keeps reachable shared nodes and self cycle" {
  let shared = obj([("name", PersistValue::Str("Ada"))])
  let root_map: Map[String, PersistValue] = Map::new()
  let root = PersistValue::Obj(root_map)
  root_map.set("left", shared)
  root_map.set("right", shared)
  root_map.set("self", root)

  let kv = open_kv()
  let bind = bind_refs_with_kv(kv)
  let state = cel(root)
  let stop = bind("refs", state) catch { _ => abort("bind") }
  stop()

  gc_refs(kv, "refs")

  let root_node = assert_kv_obj(kv, "refs/0", "root")
  match root_node.get("left") {
    Some(Ref(id)) => assert_eq(id, "1")
    _ => abort("left")
  }
  match root_node.get("right") {
    Some(Ref(id)) => assert_eq(id, "1")
    _ => abort("right")
  }
  match root_node.get("self") {
    Some(Ref(id)) => assert_eq(id, "0")
    _ => abort("self")
  }
  let child = assert_kv_obj(kv, "refs/1", "child")
  assert_obj_str(child, "name", "Ada", "name")
}

test "gc_refs clears prefix when root is missing" {
  let kv = open_kv()
  kv.set("refs/0", obj([("left", Ref("1"))]))
  kv.set("refs/1", obj([("name", PersistValue::Str("Ada"))]))
  kv.delete("refs/0")

  gc_refs(kv, "refs")

  match kv.get("refs/0") {
    None => ()
    Some(_) => abort("root")
  }
  match kv.get("refs/1") {
    None => ()
    Some(_) => abort("child")
  }
}


fn assert_obj(value: @lib.PersistValue, label: String) -> Map[String, @lib.PersistValue] {
  match value {
    Obj(m) => m
    _ => abort(label)
  }
}

fn assert_arr(value: @lib.PersistValue, label: String) -> Array[@lib.PersistValue] {
  match value {
    Arr(items) => items
    _ => abort(label)
  }
}

fn assert_kv_obj(
  kv: @lib.Kv,
  key: String,
  label: String
) -> Map[String, @lib.PersistValue] {
  match kv.get(key) {
    Some(v) => assert_obj(v, label)
    None => abort(label)
  }
}

fn assert_obj_str(
  m: Map[String, @lib.PersistValue],
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
  m: Map[String, @lib.PersistValue],
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
  items: Array[@lib.PersistValue],
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
  items: Array[@lib.PersistValue],
  index: Int,
  name: String,
  age: Int,
  label: String
) -> Unit raise {
  let m = assert_obj(items[index], label)
  assert_obj_str(m, "10", name, label + "-name")
  assert_obj_int(m, "20", age, label + "-age")
}

fn find_graph_node(
  nodes: Array[@lib.GraphNode],
  id: String,
  label: String
) -> @lib.PersistValue {
  for node in nodes {
    if node.id == id { return node.value }
  }
  abort(label)
}

fn assert_missing(v: Option[@lib.PersistValue], label: String) -> Unit {
  match v {
    None => ()
    Some(_) => abort(label)
  }
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
  title: @lib.Cel[String]
  age: @lib.Cel[Int]
}

pub impl @lib.Persist for Prefs with pack(self) -> @lib.PersistValue {
  @lib.obj([
    ("10", @lib.pack(self.name)),
    ("20", @lib.pack(self.age)),
  ])
}

pub impl @lib.Persist for Prefs with unpack(
  value: @lib.PersistValue,
  old? : Prefs? = None
) -> Prefs {
  ignore(old)
  match value {
    Obj(m) => {
      let name: String = match m.get("10") {
        Some(v) => @lib.unpack(v)
        None => "anon"
      }
      let age: Int = match m.get("20") {
        Some(v) => @lib.unpack(v)
        None => 18
      }
      { name, age }
    }
    _ => { name: "anon", age: 18 }
  }
}

pub impl @lib.Persist for Doc with pack(self) -> @lib.PersistValue {
  @lib.obj([
    ("10", @lib.pack(self.title)),
    ("20", @lib.pack(self.tags)),
  ])
}

pub impl @lib.Persist for Doc with unpack(
  value: @lib.PersistValue,
  old? : Doc? = None
) -> Doc {
  ignore(old)
  match value {
    Obj(m) => {
      let title: String = match m.get("10") {
        Some(v) => @lib.unpack(v)
        None => ""
      }
      let tags: Array[String] = match m.get("20") {
        Some(v) => @lib.unpack(v)
        None => []
      }
      { title, tags }
    }
    _ => { title: "", tags: [] }
  }
}

pub impl @lib.Persist for Group with pack(self) -> @lib.PersistValue {
  @lib.obj([
    ("10", @lib.pack(self.members)),
  ])
}

pub impl @lib.Persist for Group with unpack(
  value: @lib.PersistValue,
  old? : Group? = None
) -> Group {
  ignore(old)
  match value {
    Obj(m) => {
      let members: Array[Prefs] = match m.get("10") {
        Some(v) => @lib.unpack(v)
        None => []
      }
      { members, }
    }
    _ => { members: [] }
  }
}

pub impl @lib.Persist for CellPrefs with pack(self) -> @lib.PersistValue {
  @lib.obj([
    ("10", @lib.pack(self.title)),
    ("20", @lib.pack(self.age)),
  ])
}

pub impl @lib.Persist for CellPrefs with unpack(
  value: @lib.PersistValue,
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
        Some(v) => @lib.unpack(v, old=title_default)
        None => match title_default {
          Some(prev) => prev
          None => @lib.cel("")
        }
      }
      let age = match m.get("20") {
        Some(v) => @lib.unpack(v, old=age_default)
        None => match age_default {
          Some(prev) => prev
          None => @lib.cel(18)
        }
      }
      { title, age }
    }
    _ => {
      title: match title_default {
        Some(prev) => prev
        None => @lib.cel("")
      },
      age: match age_default {
        Some(prev) => prev
        None => @lib.cel(18)
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
  let upgraded = Prefs::unpack(@lib.obj([]))
  assert_eq(upgraded.name, "anon")
  assert_eq(upgraded.age, 18)
}

test "bind_with_kv serializes cel mutate" {
  let kv = @lib.open_kv()
  let bind = @lib.bind_with_kv(kv)
  let state = @lib.cel({ name: "Ada", age: 18 })
  let stop = bind("prefs", state) catch { _ => abort("bind") }

  let first = assert_kv_obj(kv, "prefs", "missing first save")
  assert_obj_str(first, "10", "Ada", "first-name")
  assert_obj_int(first, "20", 18, "first-age")

  state.mutate(p => {
    p.name = "Cora"
    p.age = 21
  })
  @lib.flush() catch { _ => abort("flush") }

  let second = assert_kv_obj(kv, "prefs", "missing second save")
  assert_obj_str(second, "10", "Cora", "second-name")
  assert_obj_int(second, "20", 21, "second-age")
  stop()
}

test "bind_with_kv supports arrays and nested objects" {
  let kv = @lib.open_kv()
  let bind = @lib.bind_with_kv(kv)
  let state = @lib.cel({
    title: "Notes",
    tags: ["moonbit"],
  })
  let stop = bind("doc", state) catch { _ => abort("bind") }

  state.mutate(d => {
    d.tags.push("storage")
  })
  @lib.flush() catch { _ => abort("flush") }

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
  let kv = @lib.open_kv()
  let bind = @lib.bind_with_kv(kv)
  let state = @lib.cel({
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
  @lib.flush() catch { _ => abort("flush") }

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
  let kv = @lib.open_kv()
  let bind = @lib.bind_with_kv(kv)
  let state = @lib.cel({
    title: @lib.cel("Ada"),
    age: @lib.cel(18),
  })
  let stop = bind("cell-prefs", state) catch { _ => abort("bind") }

  state.peek().title.set("Bea")
  @lib.flush() catch { _ => abort("flush-title") }

  let first = assert_kv_obj(kv, "cell-prefs", "missing cell-prefs-1")
  assert_obj_str(first, "10", "Bea", "title")
  assert_obj_int(first, "20", 18, "age-1")

  state.peek().age.set(19)
  @lib.flush() catch { _ => abort("flush-age") }

  let second = assert_kv_obj(kv, "cell-prefs", "missing cell-prefs-2")
  assert_obj_str(second, "10", "Bea", "title-2")
  assert_obj_int(second, "20", 19, "age-2")
  stop()
}

test "bind_with_kv keeps nested cel identity when loading existing value" {
  let kv = @lib.open_kv()
  kv.set("cell-prefs", @lib.obj([
    ("10", @lib.pack("Bea")),
    ("20", @lib.pack(19)),
  ]))
  let bind = @lib.bind_with_kv(kv)
  let state = @lib.cel({
    title: @lib.cel("Ada"),
    age: @lib.cel(18),
  })
  let title = state.peek().title
  let age = state.peek().age
  let stop = bind("cell-prefs", state) catch { _ => abort("bind") }

  assert_eq(physical_equal(title, state.peek().title), true)
  assert_eq(physical_equal(age, state.peek().age), true)
  assert_eq(title.peek(), "Bea")
  assert_eq(age.peek(), 19)

  title.set("Cora")
  @lib.flush() catch { _ => abort("flush-title") }

  let saved = assert_kv_obj(kv, "cell-prefs", "missing cell-prefs")
  assert_obj_str(saved, "10", "Cora", "title")
  assert_obj_int(saved, "20", 19, "age")
  stop()
}

test "bind_with_kv keeps old cel when persisted object misses field" {
  let kv = @lib.open_kv()
  kv.set("cell-prefs", @lib.obj([
    ("10", @lib.pack("Bea")),
  ]))
  let bind = @lib.bind_with_kv(kv)
  let state = @lib.cel({
    title: @lib.cel("Ada"),
    age: @lib.cel(18),
  })
  let title = state.peek().title
  let age = state.peek().age
  let stop = bind("cell-prefs", state) catch { _ => abort("bind") }

  assert_eq(physical_equal(title, state.peek().title), true)
  assert_eq(physical_equal(age, state.peek().age), true)
  assert_eq(title.peek(), "Bea")
  assert_eq(age.peek(), 18)

  age.set(20)
  @lib.flush() catch { _ => abort("flush-age") }

  let saved = assert_kv_obj(kv, "cell-prefs", "missing cell-prefs")
  assert_obj_str(saved, "10", "Bea", "title")
  assert_obj_int(saved, "20", 20, "age")
  stop()
}

test "bind_with_kv keeps array cel identity when loading existing value" {
  let kv = @lib.open_kv()
  kv.set("cell-list", @lib.arr([
    @lib.pack("Bea"),
    @lib.pack("Cora"),
  ]))
  let bind = @lib.bind_with_kv(kv)
  let state = @lib.cel([
    @lib.cel("Ada"),
    @lib.cel("Dana"),
  ])
  let first = state.peek()[0]
  let second = state.peek()[1]
  let stop = bind("cell-list", state) catch { _ => abort("bind") }

  assert_eq(physical_equal(first, state.peek()[0]), true)
  assert_eq(physical_equal(second, state.peek()[1]), true)
  assert_eq(first.peek(), "Bea")
  assert_eq(second.peek(), "Cora")

  second.set("Eve")
  @lib.flush() catch { _ => abort("flush-second") }

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
  let kv = @lib.open_kv()
  let bind = @lib.bind_with_kv(kv)
  let state = @lib.cel({ name: "Ada", age: 18 })
  let stop = bind("prefs", state) catch { _ => abort("bind") }

  stop()
  state.mutate(p => {
    p.name = "Bea"
    p.age = 19
  })
  @lib.flush() catch { _ => abort("flush") }

  let saved = assert_kv_obj(kv, "prefs", "missing prefs")
  assert_obj_str(saved, "10", "Ada", "name")
  assert_obj_int(saved, "20", 18, "age")
}

test "graph_clone stores shared child once" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", Obj(child))
  root.set("right", Obj(child))

  let nodes = @lib.graph_clone(Obj(root))
  assert_eq(nodes.length(), 2)

  let root_node = find_graph_node(nodes, "0", "root")
  match root_node {
    Obj(m) => {
      let left = match m.get("left") {
        Some(Ref(id)) => id
        _ => abort("left")
      }
      let right = match m.get("right") {
        Some(Ref(id)) => id
        _ => abort("right")
      }
      assert_eq(left, right)
      let child_node = find_graph_node(nodes, left, "child")
      let child_map = assert_obj(child_node, "child-obj")
      assert_obj_str(child_map, "name", "Ada", "child-name")
    }
    _ => abort("root-node")
  }
}

test "graph_hydrate restores shared identity" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let nodes: Array[@lib.GraphNode] = [
    { id: "0", value: @lib.obj([("left", Ref("1")), ("right", Ref("1"))]) },
    { id: "1", value: @lib.PersistValue::Obj(child) },
  ]

  let restored = @lib.graph_hydrate(nodes)
  match restored {
    Obj(m) => {
      let left = match m.get("left") {
        Some(Obj(v)) => v
        _ => abort("left")
      }
      let right = match m.get("right") {
        Some(Obj(v)) => v
        _ => abort("right")
      }
      assert_eq(physical_equal(left, right), true)
    }
    _ => abort("restored")
  }
}

test "graph_hydrate restores self cycle" {
  let nodes: Array[@lib.GraphNode] = [
    { id: "0", value: @lib.obj([("self", Ref("0"))]) },
  ]
  let restored = @lib.graph_hydrate(nodes)

  match restored {
    Obj(m) => {
      let self = match m.get("self") {
        Some(Obj(v)) => v
        _ => abort("self")
      }
      assert_eq(physical_equal(m, self), true)
    }
    _ => abort("cycle-root")
  }
}

test "graph_patch keeps shared child identity" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", @lib.PersistValue::Obj(child))
  root.set("right", @lib.PersistValue::Obj(child))
  let left = match root.get("left") {
    Some(Obj(v)) => v
    _ => abort("left")
  }
  let right = match root.get("right") {
    Some(Obj(v)) => v
    _ => abort("right")
  }
  let nodes: Array[@lib.GraphNode] = [
    { id: "0", value: @lib.obj([("left", Ref("1")), ("right", Ref("1"))]) },
    { id: "1", value: @lib.obj([("name", Str("Bea"))]) },
  ]

  let patched = @lib.graph_patch(@lib.PersistValue::Obj(root), nodes)
  match patched {
    Obj(m) => {
      let next_left = match m.get("left") {
        Some(Obj(v)) => v
        _ => abort("next-left")
      }
      let next_right = match m.get("right") {
        Some(Obj(v)) => v
        _ => abort("next-right")
      }
      assert_eq(physical_equal(left, next_left), true)
      assert_eq(physical_equal(right, next_right), true)
      assert_eq(physical_equal(next_left, next_right), true)
      match next_left.get("name") {
        Some(Str(v)) => assert_eq(v, "Bea")
        _ => abort("name")
      }
    }
    _ => abort("patched")
  }
}

test "graph_patch_with shares the same patch core" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", @lib.PersistValue::Obj(child))
  root.set("right", @lib.PersistValue::Obj(child))
  let cached = child
  let nodes: Map[String, @lib.PersistValue] = Map::new()
  nodes.set("0", @lib.obj([("left", Ref("1")), ("right", Ref("1"))]))
  nodes.set("1", @lib.obj([("name", Str("Bea"))]))

  let patched = @lib.graph_patch_with(@lib.PersistValue::Obj(root), id => nodes.get(id))
  match patched {
    Obj(m) => {
      let left = match m.get("left") {
        Some(Obj(v)) => v
        _ => abort("left")
      }
      let right = match m.get("right") {
        Some(Obj(v)) => v
        _ => abort("right")
      }
      assert_eq(physical_equal(cached, left), true)
      assert_eq(physical_equal(left, right), true)
    }
    _ => abort("patched")
  }
}

test "graph_patch keeps array child identity by slot" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Array[@lib.PersistValue] = [@lib.PersistValue::Obj(child)]
  let cached = child
  let nodes: Array[@lib.GraphNode] = [
    { id: "0", value: @lib.arr([Ref("1")]) },
    { id: "1", value: @lib.obj([("name", Str("Bea"))]) },
  ]

  let patched = @lib.graph_patch(@lib.PersistValue::Arr(root), nodes)
  match patched {
    Arr(items) => {
      let first = match items[0] {
        Obj(v) => v
        _ => abort("item")
      }
      assert_eq(physical_equal(cached, first), true)
      match first.get("name") {
        Some(Str(v)) => assert_eq(v, "Bea")
        _ => abort("name")
      }
    }
    _ => abort("patched")
  }
}

test "bind_graph_with_kv stores graph nodes by ref" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", @lib.PersistValue::Obj(child))
  root.set("right", @lib.PersistValue::Obj(child))
  let kv = @lib.open_kv()
  let bind = @lib.bind_graph_with_kv(kv)
  let state = @lib.cel(@lib.PersistValue::Obj(root))
  let stop = bind("graph", state) catch { _ => abort("bind") }

  let ids = match kv.get("graph/@graph") {
    Some(v) => assert_arr(v, "graph-index")
    None => abort("graph-index")
  }
  assert_eq(ids.length(), 2)
  let root_node = assert_kv_obj(kv, "graph/0", "graph-root")
  match root_node.get("left") {
    Some(Ref(id)) => assert_eq(id, "1")
    _ => abort("left")
  }
  match root_node.get("right") {
    Some(Ref(id)) => assert_eq(id, "1")
    _ => abort("right")
  }
  let child_node = assert_kv_obj(kv, "graph/1", "graph-child")
  assert_obj_str(child_node, "name", "Ada", "child-name")
  stop()
}

test "graph_save_to_kv and graph_load_from_kv share graph format" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", @lib.PersistValue::Obj(child))
  root.set("right", @lib.PersistValue::Obj(child))
  let kv = @lib.open_kv()

  @lib.graph_save_to_kv(kv, "graph", @lib.PersistValue::Obj(root))
  let base = @lib.obj([])
  let loaded = match @lib.graph_load_from_kv(base, kv, "graph") {
    Some(v) => v
    None => abort("load")
  }

  match loaded {
    Obj(m) => {
      let left = match m.get("left") {
        Some(Obj(v)) => v
        _ => abort("left")
      }
      let right = match m.get("right") {
        Some(Obj(v)) => v
        _ => abort("right")
      }
      assert_eq(physical_equal(left, right), true)
      match left.get("name") {
        Some(Str(v)) => assert_eq(v, "Ada")
        _ => abort("name")
      }
    }
    _ => abort("loaded")
  }
}

test "bind_graph_with_kv loads shared graph identity" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let kv = @lib.open_kv()
  kv.set("graph/@graph", @lib.arr([Str("0"), Str("1")]))
  kv.set("graph/0", @lib.obj([("left", Ref("1")), ("right", Ref("1"))]))
  kv.set("graph/1", @lib.PersistValue::Obj(child))
  let bind = @lib.bind_graph_with_kv(kv)
  let state = @lib.cel(@lib.obj([]))
  let stop = bind("graph", state) catch { _ => abort("bind") }

  match state.peek() {
    Obj(m) => {
      let left = match m.get("left") {
        Some(Obj(v)) => v
        _ => abort("left")
      }
      let right = match m.get("right") {
        Some(Obj(v)) => v
        _ => abort("right")
      }
      assert_eq(physical_equal(left, right), true)
    }
    _ => abort("state")
  }
  stop()
}

test "bind_graph_with_kv keeps cached child identity when loading" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", @lib.PersistValue::Obj(child))
  root.set("right", @lib.PersistValue::Obj(child))
  let kv = @lib.open_kv()
  kv.set("graph/@graph", @lib.arr([Str("0"), Str("1")]))
  kv.set("graph/0", @lib.obj([("left", Ref("1")), ("right", Ref("1"))]))
  kv.set("graph/1", @lib.obj([("name", Str("Bea"))]))
  let bind = @lib.bind_graph_with_kv(kv)
  let state = @lib.cel(@lib.PersistValue::Obj(root))
  let cached = match root.get("left") {
    Some(Obj(v)) => v
    _ => abort("cached")
  }
  let stop = bind("graph", state) catch { _ => abort("bind") }

  match state.peek() {
    Obj(m) => {
      let left = match m.get("left") {
        Some(Obj(v)) => v
        _ => abort("left")
      }
      let right = match m.get("right") {
        Some(Obj(v)) => v
        _ => abort("right")
      }
      assert_eq(physical_equal(cached, left), true)
      assert_eq(physical_equal(left, right), true)
      match left.get("name") {
        Some(Str(v)) => assert_eq(v, "Bea")
        _ => abort("name")
      }
    }
    _ => abort("state")
  }
  stop()
}

test "bind_graph_with_kv keeps cached array child identity when loading" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Array[@lib.PersistValue] = [@lib.PersistValue::Obj(child)]
  let kv = @lib.open_kv()
  kv.set("graph/@graph", @lib.arr([Str("0"), Str("1")]))
  kv.set("graph/0", @lib.arr([Ref("1")]))
  kv.set("graph/1", @lib.obj([("name", Str("Bea"))]))
  let bind = @lib.bind_graph_with_kv(kv)
  let state = @lib.cel(@lib.PersistValue::Arr(root))
  let cached = child
  let stop = bind("graph", state) catch { _ => abort("bind") }

  match state.peek() {
    Arr(items) => {
      let first = match items[0] {
        Obj(v) => v
        _ => abort("item")
      }
      assert_eq(physical_equal(cached, first), true)
      match first.get("name") {
        Some(Str(v)) => assert_eq(v, "Bea")
        _ => abort("name")
      }
    }
    _ => abort("state")
  }
  stop()
}

test "bind_graph_with_kv removes stale graph nodes after update" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", @lib.PersistValue::Obj(child))
  let kv = @lib.open_kv()
  let bind = @lib.bind_graph_with_kv(kv)
  let state = @lib.cel(@lib.PersistValue::Obj(root))
  let stop = bind("graph", state) catch { _ => abort("bind") }

  state.set(@lib.obj([("title", Str("Bea"))]))
  @lib.flush() catch { _ => abort("flush") }

  let ids = match kv.get("graph/@graph") {
    Some(v) => assert_arr(v, "graph-index")
    None => abort("graph-index")
  }
  assert_eq(ids.length(), 1)
  let root_node = assert_kv_obj(kv, "graph/0", "graph-root")
  assert_obj_str(root_node, "title", "Bea", "title")
  assert_missing(kv.get("graph/1"), "stale-child")
  stop()
}

test "bind_graph_with_kv saves nested graph mutate through root cel" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", @lib.PersistValue::Obj(child))
  root.set("right", @lib.PersistValue::Obj(child))
  let kv = @lib.open_kv()
  let bind = @lib.bind_graph_with_kv(kv)
  let state = @lib.cel(@lib.PersistValue::Obj(root))
  let stop = bind("graph", state) catch { _ => abort("bind") }

  state.mutate(v => {
    match v {
      Obj(m) => {
        match m.get("left") {
          Some(Obj(node)) => node.set("name", Str("Bea"))
          _ => abort("left")
        }
      }
      _ => abort("root")
    }
  })
  @lib.flush() catch { _ => abort("flush") }

  let child_node = assert_kv_obj(kv, "graph/1", "graph-child")
  assert_obj_str(child_node, "name", "Bea", "child-name")
  stop()
}

test "bind_graph_with_kv saves direct nested graph mutation on flush" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", @lib.PersistValue::Obj(child))
  root.set("right", @lib.PersistValue::Obj(child))
  let kv = @lib.open_kv()
  let bind = @lib.bind_graph_with_kv(kv)
  let state = @lib.cel(@lib.PersistValue::Obj(root))
  let stop = bind("graph", state) catch { _ => abort("bind") }

  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(node)) => node.set("name", Str("Cora"))
        _ => abort("left")
      }
    }
    _ => abort("root")
  }
  @lib.flush() catch { _ => abort("flush") }

  let child_node = assert_kv_obj(kv, "graph/1", "graph-child")
  assert_obj_str(child_node, "name", "Cora", "child-name")
  stop()
}

test "bind_graph_with_kv stops direct nested graph flush sync after stop" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", @lib.PersistValue::Obj(child))
  root.set("right", @lib.PersistValue::Obj(child))
  let kv = @lib.open_kv()
  let bind = @lib.bind_graph_with_kv(kv)
  let state = @lib.cel(@lib.PersistValue::Obj(root))
  let stop = bind("graph", state) catch { _ => abort("bind") }

  stop()
  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(node)) => node.set("name", Str("Dana"))
        _ => abort("left")
      }
    }
    _ => abort("root")
  }
  @lib.flush() catch { _ => abort("flush") }

  let child_node = assert_kv_obj(kv, "graph/1", "graph-child")
  assert_obj_str(child_node, "name", "Ada", "child-name")
}

test "bind_graph_scoped_with_kv stops after last scope clears" {
  let child: Map[String, @lib.PersistValue] = Map::new()
  child.set("name", Str("Ada"))
  let root: Map[String, @lib.PersistValue] = Map::new()
  root.set("left", @lib.PersistValue::Obj(child))
  root.set("right", @lib.PersistValue::Obj(child))
  let kv = @lib.open_kv()
  let bind = @lib.bind_graph_scoped_with_kv(kv)
  let state = @lib.cel(@lib.PersistValue::Obj(root))

  let stop1 = @lib.scope(fn() raise {
    bind("graph", state)
    ()
  }) catch { _ => abort("scope-1") }
  let stop2 = @lib.scope(fn() raise {
    bind("graph", state)
    ()
  }) catch { _ => abort("scope-2") }

  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(node)) => node.set("name", Str("Bea"))
        _ => abort("left-1")
      }
    }
    _ => abort("root-1")
  }
  @lib.flush() catch { _ => abort("flush-1") }
  let child1 = assert_kv_obj(kv, "graph/1", "graph-child-1")
  assert_obj_str(child1, "name", "Bea", "child-name-1")

  stop1()
  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(node)) => node.set("name", Str("Cora"))
        _ => abort("left-2")
      }
    }
    _ => abort("root-2")
  }
  @lib.flush() catch { _ => abort("flush-2") }
  let child2 = assert_kv_obj(kv, "graph/1", "graph-child-2")
  assert_obj_str(child2, "name", "Cora", "child-name-2")

  stop2()
  match state.peek() {
    Obj(m) => {
      match m.get("left") {
        Some(Obj(node)) => node.set("name", Str("Dana"))
        _ => abort("left-3")
      }
    }
    _ => abort("root-3")
  }
  @lib.flush() catch { _ => abort("flush-3") }
  let child3 = assert_kv_obj(kv, "graph/1", "graph-child-3")
  assert_obj_str(child3, "name", "Cora", "child-name-3")
}

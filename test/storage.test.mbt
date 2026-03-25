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
  match packed {
    Obj(m) => {
      match m.get("10") {
        Some(Str(name)) => assert_eq(name, "Ada")
        _ => abort("name")
      }
      match m.get("20") {
        Some(Int(age)) => assert_eq(age, 18)
        _ => abort("age")
      }
    }
    _ => abort("obj")
  }
  let upgraded = Prefs::unpack(@lib.obj([]))
  assert_eq(upgraded.name, "anon")
  assert_eq(upgraded.age, 18)
}

test "bind_with_kv serializes cel mutate" {
  let kv = @lib.open_kv()
  let bind = @lib.bind_with_kv(kv)
  let state = @lib.cel({ name: "Ada", age: 18 })
  let stop = bind("prefs", state) catch { _ => abort("bind") }

  match kv.get("prefs") {
    Some(Obj(m)) => {
      match m.get("10") {
        Some(Str(name)) => assert_eq(name, "Ada")
        _ => abort("first-name")
      }
      match m.get("20") {
        Some(Int(age)) => assert_eq(age, 18)
        _ => abort("first-age")
      }
    }
    _ => abort("missing first save")
  }

  state.mutate(p => {
    p.name = "Cora"
    p.age = 21
  })
  @lib.flush() catch { _ => abort("flush") }

  match kv.get("prefs") {
    Some(Obj(m)) => {
      match m.get("10") {
        Some(Str(name)) => assert_eq(name, "Cora")
        _ => abort("second-name")
      }
      match m.get("20") {
        Some(Int(age)) => assert_eq(age, 21)
        _ => abort("second-age")
      }
    }
    _ => abort("missing second save")
  }
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

  match kv.get("doc") {
    Some(Obj(m)) => {
      match m.get("20") {
        Some(Arr(tags)) => {
          assert_eq(tags.length(), 2)
          match tags[0] {
            Str(v) => assert_eq(v, "moonbit")
            _ => abort("tag-0")
          }
          match tags[1] {
            Str(v) => assert_eq(v, "storage")
            _ => abort("tag-1")
          }
        }
        _ => abort("tags")
      }
    }
    _ => abort("missing doc")
  }
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

  match kv.get("group") {
    Some(Obj(m)) => {
      match m.get("10") {
        Some(Arr(items)) => {
          assert_eq(items.length(), 3)
        }
        _ => abort("members")
      }
    }
    _ => abort("missing group")
  }
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

  match kv.get("cell-prefs") {
    Some(Obj(m)) => {
      match m.get("10") {
        Some(Str(v)) => assert_eq(v, "Bea")
        _ => abort("title")
      }
      match m.get("20") {
        Some(Int(v)) => assert_eq(v, 18)
        _ => abort("age-1")
      }
    }
    _ => abort("missing cell-prefs-1")
  }

  state.peek().age.set(19)
  @lib.flush() catch { _ => abort("flush-age") }

  match kv.get("cell-prefs") {
    Some(Obj(m)) => {
      match m.get("10") {
        Some(Str(v)) => assert_eq(v, "Bea")
        _ => abort("title-2")
      }
      match m.get("20") {
        Some(Int(v)) => assert_eq(v, 19)
        _ => abort("age-2")
      }
    }
    _ => abort("missing cell-prefs-2")
  }
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

  match kv.get("cell-prefs") {
    Some(Obj(m)) => {
      match m.get("10") {
        Some(Str(v)) => assert_eq(v, "Cora")
        _ => abort("title")
      }
      match m.get("20") {
        Some(Int(v)) => assert_eq(v, 19)
        _ => abort("age")
      }
    }
    _ => abort("missing cell-prefs")
  }
  stop()
}

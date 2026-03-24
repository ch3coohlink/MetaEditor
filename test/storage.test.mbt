fn prefs_schema() -> @lib.Schema {
  @lib.schema("prefs", [
    @lib.field(10, "name", @lib.string("anon")),
    @lib.field(20, "age", @lib.int(18)),
  ])
}

fn doc_schema() -> @lib.Schema {
  @lib.schema("doc", [
    @lib.field(10, "title", @lib.string("")),
    @lib.field(20, "tags", @lib.array(@lib.string(""))),
  ])
}

fn obj(items: Array[(String, Json)]) -> Json {
  let m: Map[String, Json] = Map::new()
  for item in items {
    let (k, v) = item
    m.set(k, v)
  }
  Json::object(m)
}

test "storage fills defaults and drops extra fields" {
  let s = prefs_schema()
  let raw = obj([
    ("10", Json::string("Ada")),
    ("99", Json::string("drop")),
  ])
  let prefs = @lib.load_text(s, raw.stringify()) catch { _ => abort("load") }
  assert_eq(
    prefs,
    obj([
      ("name", Json::string("Ada")),
      ("age", Json::number(18.0)),
    ]),
  )

  let text = @lib.encode_text(s, prefs)
  let round = @lib.load_text(s, text) catch { _ => abort("round") }
  assert_eq(round, prefs)
}

test "storage rename keeps store tag stable" {
  let s = @lib.schema("prefs", [
    @lib.field(10, "title", @lib.string("anon")),
    @lib.field(20, "age", @lib.int(18)),
  ])
  let raw = obj([
    ("10", Json::string("Bea")),
    ("20", Json::number(19.0)),
  ])
  let prefs = @lib.load_text(s, raw.stringify()) catch { _ => abort("load") }
  assert_eq(
    prefs,
    obj([
      ("title", Json::string("Bea")),
      ("age", Json::number(19.0)),
    ]),
  )
}

test "storage handles arrays recursively" {
  let s = doc_schema()
  let raw = obj([
    ("10", Json::string("Notes")),
    ("20", Json::array([Json::string("moonbit"), Json::string("storage")])),
  ])
  let doc = @lib.load_text(s, raw.stringify()) catch { _ => abort("load") }
  assert_eq(
    doc,
    obj([
      ("title", Json::string("Notes")),
      ("tags", Json::array([Json::string("moonbit"), Json::string("storage")])),
    ]),
  )
}

test "bind_with_kv serializes cel mutate" {
  let kv = @lib.open_kv()
  let bind = @lib.bind_with_kv(kv)
  let s = prefs_schema()
  let state = @lib.cell(obj([
    ("name", Json::string("Ada")),
    ("age", Json::number(18.0)),
  ]))
  let stop = bind("prefs", s, state) catch { _ => abort("bind") }

  let first = match kv.get("prefs") {
    Some(text) => text
    None => abort("missing first save")
  }
  let first_value = @lib.load_text(s, first) catch { _ => abort("first") }
  assert_eq(
    first_value,
    obj([
      ("name", Json::string("Ada")),
      ("age", Json::number(18.0)),
    ]),
  )

  state.mutate(v => {
    match v {
      Object(m) => {
        m.set("name", Json::string("Cora"))
        m.set("age", Json::number(21.0))
      }
      _ => abort("state")
    }
  })
  @lib.flush() catch { _ => abort("flush") }

  let second = match kv.get("prefs") {
    Some(text) => text
    None => abort("missing second save")
  }
  let second_value = @lib.load_text(s, second) catch { _ => abort("second") }
  assert_eq(
    second_value,
    obj([
      ("name", Json::string("Cora")),
      ("age", Json::number(21.0)),
    ]),
  )
  stop()
}

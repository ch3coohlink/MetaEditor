suberror StorageError {
  InvalidBlob(String)
  MissingMigration(String, Int)
} derive(Show)

pub(all) struct Migration {
  from: Int
  apply: (Json) -> Json
}

pub(all) struct Schema[T] {
  id: String
  version: Int
  encode: (T) -> Json
  decode: (Json) -> T raise
  migrations: Array[Migration]
}

pub(all) struct Field[T] {
  key: String
  schema: Schema[T]
  default: T
}

pub fn[T] make_schema(
  id: String,
  version: Int,
  encode: (T) -> Json,
  decode: (Json) -> T raise,
) -> Schema[T] {
  { id, version, encode, decode, migrations: [] }
}

pub fn[T] with_migration(schema: Schema[T], from: Int, apply: (Json) -> Json) -> Schema[T] {
  let migrations = schema.migrations.copy()
  migrations.push({ from, apply })
  { id: schema.id, version: schema.version, encode: schema.encode,
    decode: schema.decode, migrations }
}

pub fn[T] make_field(key: String, schema: Schema[T], default: T) -> Field[T] {
  { key, schema, default }
}

fn object_from(items: Array[(String, Json)]) -> Json {
  let m: Map[String, Json] = Map::new()
  for item in items {
    let (k, v) = item
    m.set(k, v)
  }
  Json::object(m)
}

fn object_of(json: Json) -> Map[String, Json] raise {
  match json {
    Object(m) => m
    _ => raise InvalidBlob("expected object")
  }
}

fn array_of(json: Json) -> Array[Json] raise {
  match json {
    Array(xs) => xs
    _ => raise InvalidBlob("expected array")
  }
}

fn[T] read_field(obj: Map[String, Json], field: Field[T]) -> T raise {
  match obj.get(field.key) {
    Some(raw) => (field.schema.decode)(raw)
    None => field.default
  }
}

fn[T] migrate(schema: Schema[T], version: Int, data: Json) -> Json raise {
  if version >= schema.version {
    return data
  }
  let mut cur = data
  let mut v = version
  while v < schema.version {
    let mut found = false
    for m in schema.migrations {
      if m.from == v {
        cur = (m.apply)(cur)
        found = true
        break
      }
    }
    if !found {
      raise MissingMigration(schema.id, v)
    }
    v += 1
  }
  cur
}

pub fn[T] encode_doc(schema: Schema[T], value: T) -> Json {
  object_from([
    ("schema", schema.id.to_json()),
    ("version", schema.version.to_json()),
    ("data", (schema.encode)(value)),
  ])
}

pub fn[T] decode_doc(schema: Schema[T], blob: Json) -> T raise {
  match blob {
    Object(m) =>
      match m.get("schema") {
        Some(String(id)) =>
          if id == schema.id {
            match m.get("version") {
              Some(version_json) => match @json.from_json(version_json) {
                Ok(version) =>
                  match m.get("data") {
                    Some(data) => (schema.decode)(migrate(schema, version, data))
                    None => (schema.decode)(blob)
                  }
                _ => (schema.decode)(blob)
              }
              _ => (schema.decode)(blob)
            }
          } else {
            (schema.decode)(blob)
          }
        _ => (schema.decode)(blob)
      }
    _ => (schema.decode)(blob)
  }
}

pub fn load_text[T](schema: Schema[T], text: String) -> T raise {
  decode_doc(schema, @json.parse(text))
}

pub fn encode_text[T](schema: Schema[T], value: T) -> String {
  encode_doc(schema, value).stringify()
}

pub fn bind_text[T](
  source: Cel[T],
  schema: Schema[T],
  save: (String) -> Unit,
) -> (() -> Unit) raise {
  scope(() => {
    let _ = effect(() => save(encode_text(schema, source.get())))
    ()
  })
}

pub fn string_schema() -> Schema[String] {
  make_schema("string", 1, fn(v) { v.to_json() }, fn(raw) {
    match raw {
      String(v) => v
      _ => raise InvalidBlob("expected string")
    }
  })
}

pub fn int_schema() -> Schema[Int] {
  make_schema("int", 1, fn(v) { v.to_json() }, fn(raw) {
    match @json.from_json(raw) {
      Ok(v) => v
      _ => raise InvalidBlob("expected int")
    }
  })
}

pub fn bool_schema() -> Schema[Bool] {
  make_schema("bool", 1, fn(v) { v.to_json() }, fn(raw) {
    match raw {
      True => true
      False => false
      _ => raise InvalidBlob("expected bool")
    }
  })
}

pub fn[T] array_schema(item: Schema[T]) -> Schema[Array[T]] {
  make_schema("\{item.id}[]", item.version, fn(xs) {
    let out: Array[Json] = []
    for x in xs {
      out.push((item.encode)(x))
    }
    Json::array(out)
  }, fn(raw) {
    let xs = array_of(raw)
    let out: Array[T] = []
    for x in xs {
      out.push((item.decode)(x))
    }
    out
  })
}

pub fn record2[A, B, T](
  id: String,
  version: Int,
  a: Field[A],
  b: Field[B],
  build: (A, B) -> T,
  split: (T) -> (A, B),
) -> Schema[T] {
  make_schema(id, version, fn(v) {
    let (va, vb) = split(v)
    object_from([
      (a.key, (a.schema.encode)(va)),
      (b.key, (b.schema.encode)(vb)),
    ])
  }, fn(raw) {
    let obj = object_of(raw)
    build(read_field(obj, a), read_field(obj, b))
  })
}

pub fn record3[A, B, C, T](
  id: String,
  version: Int,
  a: Field[A],
  b: Field[B],
  c: Field[C],
  build: (A, B, C) -> T,
  split: (T) -> (A, B, C),
) -> Schema[T] {
  make_schema(id, version, fn(v) {
    let (va, vb, vc) = split(v)
    object_from([
      (a.key, (a.schema.encode)(va)),
      (b.key, (b.schema.encode)(vb)),
      (c.key, (c.schema.encode)(vc)),
    ])
  }, fn(raw) {
    let obj = object_of(raw)
    build(read_field(obj, a), read_field(obj, b), read_field(obj, c))
  })
}

pub fn record4[A, B, C, D, T](
  id: String,
  version: Int,
  a: Field[A],
  b: Field[B],
  c: Field[C],
  d: Field[D],
  build: (A, B, C, D) -> T,
  split: (T) -> (A, B, C, D),
) -> Schema[T] {
  make_schema(id, version, fn(v) {
    let (va, vb, vc, vd) = split(v)
    object_from([
      (a.key, (a.schema.encode)(va)),
      (b.key, (b.schema.encode)(vb)),
      (c.key, (c.schema.encode)(vc)),
      (d.key, (d.schema.encode)(vd)),
    ])
  }, fn(raw) {
    let obj = object_of(raw)
    build(
      read_field(obj, a),
      read_field(obj, b),
      read_field(obj, c),
      read_field(obj, d),
    )
  })
}

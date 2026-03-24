suberror StorageError {
  InvalidBlob(String)
} derive(Show)

pub(all) struct Kv {
  data: Ref[Map[String, String]]
}

pub fn open_kv() -> Kv {
  { data: Ref::new(Map::new()) }
}

pub fn Kv::get(self: Kv, key: String) -> Option[String] {
  self.data.val.get(key)
}

pub fn Kv::set(self: Kv, key: String, value: String) -> Unit {
  self.data.val.set(key, value)
}

pub(all) struct Schema {
  id: String
  default: Json
  encode: (Json) -> Json
  decode: (Json) -> Json
}

pub(all) struct Field {
  tag: Int
  name: String
  schema: Schema
}

fn object_from(items: Array[(String, Json)]) -> Json {
  let m: Map[String, Json] = Map::new()
  for item in items {
    let (k, v) = item
    m.set(k, v)
  }
  Json::object(m)
}

fn object_of(json: Json) -> Map[String, Json] {
  match json {
    Object(m) => m
    _ => Map::new()
  }
}

fn array_of(json: Json) -> Array[Json] {
  match json {
    Array(xs) => xs
    _ => []
  }
}

fn read_object_field(obj: Map[String, Json], field: Field) -> Json {
  match obj.get("\{field.tag}") {
    Some(raw) => raw
    None =>
      match obj.get(field.name) {
        Some(raw) => raw
        None => field.schema.default
      }
  }
}

fn field_default(field: Field) -> Json {
  field.schema.default
}

pub fn field(tag: Int, name: String, schema: Schema) -> Field {
  { tag, name, schema }
}

pub fn schema(id: String, fields: Array[Field]) -> Schema {
  let defaults = object_from(fields.map(fn(field) {
    (field.name, field_default(field))
  }))
  {
    id,
    default: defaults,
    encode: fn(raw) {
      let obj = object_of(raw)
      let out: Array[(String, Json)] = []
      for field in fields {
        let value = read_object_field(obj, field)
        out.push(("\{field.tag}", (field.schema.encode)(value)))
      }
      object_from(out)
    },
    decode: fn(raw) {
      let obj = object_of(raw)
      let out: Array[(String, Json)] = []
      for field in fields {
        let value = read_object_field(obj, field)
        out.push((field.name, (field.schema.decode)(value)))
      }
      object_from(out)
    },
  }
}

pub fn string(default: String) -> Schema {
  {
    id: "string",
    default: default.to_json(),
    encode: fn(raw) {
      match raw {
        String(_) => raw
        _ => default.to_json()
      }
    },
    decode: fn(raw) {
      match raw {
        String(_) => raw
        _ => default.to_json()
      }
    },
  }
}

pub fn int(default: Int) -> Schema {
  {
    id: "int",
    default: default.to_json(),
    encode: fn(raw) {
      match raw {
        Number(_) => raw
        _ => default.to_json()
      }
    },
    decode: fn(raw) {
      match raw {
        Number(_) => raw
        _ => default.to_json()
      }
    },
  }
}

pub fn bool(default: Bool) -> Schema {
  {
    id: "bool",
    default: default.to_json(),
    encode: fn(raw) {
      match raw {
        True => raw
        False => raw
        _ => default.to_json()
      }
    },
    decode: fn(raw) {
      match raw {
        True => raw
        False => raw
        _ => default.to_json()
      }
    },
  }
}

pub fn array(item: Schema) -> Schema {
  {
    id: "\{item.id}[]",
    default: Json::array([]),
    encode: fn(raw) {
      let xs = array_of(raw)
      let out: Array[Json] = []
      for x in xs {
        out.push((item.encode)(x))
      }
      Json::array(out)
    },
    decode: fn(raw) {
      let xs = array_of(raw)
      let out: Array[Json] = []
      for x in xs {
        out.push((item.decode)(x))
      }
      Json::array(out)
    },
  }
}

pub fn load_text(schema: Schema, text: String) -> Json raise {
  (schema.decode)(@json.parse(text))
}

pub fn encode_text(schema: Schema, value: Json) -> String {
  (schema.encode)(value).stringify()
}

pub fn bind_with_kv(kv: Kv) -> (String, Schema, Cel[Json]) -> (() -> Unit) raise {
  fn(key: String, schema: Schema, source: Cel[Json]) raise {
    match kv.get(key) {
      Some(text) => source.set(load_text(schema, text) catch { _ => schema.default })
      None => kv.set(key, encode_text(schema, source.peek()))
    }
    scope(fn() raise {
      let _ = effect(() => kv.set(key, encode_text(schema, source.get())))
      ()
    })
  }
}

pub fn[T] cell(x: T) -> Cel[T] { cel(x) }

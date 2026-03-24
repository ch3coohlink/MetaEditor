struct Prefs {
  mut name: String
  mut age: Int
}

fn prefs_schema() -> @lib.Schema[Prefs] {
  @lib.with_migration(
    @lib.record2(
      "prefs",
      2,
      @lib.make_field("name", @lib.string_schema(), "anon"),
      @lib.make_field("age", @lib.int_schema(), 18),
      fn(name, age) { { name, age } },
      fn(v) { (v.name, v.age) },
    ),
    1,
    fn(raw) {
      match raw {
        Object(m) => match m.get("title") {
          Some(title) => Json::object({ "name": title })
          None => raw
        }
        _ => raw
      }
    }
  )
}

test "storage schema fills defaults and drops extra fields" {
  let s = prefs_schema()
  let doc = Json::object({
    "schema": "prefs".to_json(),
    "version": (2).to_json(),
    "data": Json::object({
      "name": "Ada".to_json(),
      "extra": "drop".to_json(),
    }),
  })
  let prefs = @lib.decode_doc(s, doc) catch { e =>
    println(e)
    panic()
  }
  assert_eq(prefs.name, "Ada")
  assert_eq(prefs.age, 18)

  let text = @lib.encode_text(s, prefs)
  let round = @lib.load_text(s, text) catch { e =>
    println(e)
    panic()
  }
  assert_eq(round.name, "Ada")
  assert_eq(round.age, 18)
}

test "storage schema migrates old document" {
  let s = prefs_schema()
  let doc = Json::object({
    "schema": "prefs".to_json(),
    "version": (1).to_json(),
    "data": Json::object({
      "title": "Bea".to_json(),
      "old": (99).to_json(),
    }),
  })
  let prefs = @lib.decode_doc(s, doc) catch { e =>
    println(e)
    panic()
  }
  assert_eq(prefs.name, "Bea")
  assert_eq(prefs.age, 18)
}

test "bind_text serializes cel mutate" {
  let s = prefs_schema()
  let state = @lib.cel({ name: "Ada", age: 18 })
  let seen: Ref[Array[String]] = Ref::new([])
  let stop = @lib.bind_text(state, s, fn(text) { seen.val.push(text) }) catch {
    _ => panic()
  }

  assert_eq(seen.val.length(), 1)
  let first = @lib.load_text(s, seen.val[0]) catch { e =>
    println(e)
    panic()
  }
  assert_eq(first.name, "Ada")
  assert_eq(first.age, 18)

  state.mutate(p => {
    p.name = "Cora"
    p.age = 21
  })
  @lib.flush() catch { _ => panic() }

  assert_eq(seen.val.length(), 2)
  let second = @lib.load_text(s, seen.val[1]) catch { e =>
    println(e)
    panic()
  }
  assert_eq(second.name, "Cora")
  assert_eq(second.age, 21)
  stop()
}

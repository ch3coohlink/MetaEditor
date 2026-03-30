fn open_sqlite_conn() -> @sqlite3.Connection {
  let db : Result[@sqlite3.Connection, _] = try? @sqlite3.Connection::open(":memory:")
  match db {
    Ok(db) => db
    Err(_) => abort("open sqlite")
  }
}

fn create_test_table(db : @sqlite3.Connection, label : String) -> Unit {
  let ok : Result[Unit, _] = try? {
    let stmt = db.prepare("CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)")
    stmt.step_once()
    stmt.finalize()
  }
  match ok {
    Ok(_) => ()
    Err(_) => abort(label)
  }
}

fn insert_test_value(
  db : @sqlite3.Connection,
  value : String,
  label : String
) -> Unit {
  let ok : Result[Unit, _] = try? {
    let stmt = db.prepare("INSERT INTO test (value) VALUES (?)")
    stmt.bind(index=1, value)
    stmt.step_once()
    stmt.finalize()
  }
  match ok {
    Ok(_) => ()
    Err(_) => abort(label)
  }
}

test "native: sqlite kv roundtrip" {
  let kv = match open_sqlite_kv(":memory:") {
    Some(db) => db
    None => fail("open sqlite")
  }
  defer kv.close()

  assert_eq(kv.set("prefs/name", "Ada"), true)
  assert_eq(kv.get("prefs/name"), Some("Ada"))
  assert_eq(kv.set("prefs/name", "Bea"), true)
  assert_eq(kv.get("prefs/name"), Some("Bea"))
}

test "native: sqlite kv delete removes key" {
  let kv = match open_sqlite_kv(":memory:") {
    Some(db) => db
    None => fail("open sqlite")
  }
  defer kv.close()

  assert_eq(kv.set("prefs/name", "Ada"), true)
  assert_eq(kv.delete("prefs/name"), true)
  assert_eq(kv.get("prefs/name"), None)
}

test "native: sqlite kv keys_with_prefix scans current prefix" {
  let kv = match open_sqlite_kv(":memory:") {
    Some(db) => db
    None => fail("open sqlite")
  }
  defer kv.close()

  ignore(kv.set("refs/0", "root"))
  ignore(kv.set("refs/1", "child"))
  ignore(kv.set("other/0", "other"))

  let keys = kv.keys_with_prefix("refs")
  assert_eq(keys, ["refs/0", "refs/1"])
}

test "native: sqlite database open close" {
  let db = open_sqlite_conn()
  let _ : Result[Unit, _] = try? db.close()
}

test "native: sqlite database exec create table" {
  let db = open_sqlite_conn()
  defer {
    let _ : Result[Unit, _] = try? db.close()
  }
  create_test_table(db, "create table")
}

test "native: sqlite statement bind and execute" {
  let db = open_sqlite_conn()
  defer {
    let _ : Result[Unit, _] = try? db.close()
  }
  create_test_table(db, "create table")
  insert_test_value(db, "Ada", "insert")
}

test "native: sqlite statement column text" {
  let db = open_sqlite_conn()
  defer {
    let _ : Result[Unit, _] = try? db.close()
  }
  create_test_table(db, "setup-table")
  insert_test_value(db, "Ada", "setup-insert")

  let select : Result[String, _] = try? {
    let stmt = db.prepare("SELECT value FROM test")
    if !stmt.step() {
      stmt.finalize()
      fail("step")
    }
    let value : String = stmt.column(index=0)
    stmt.finalize()
    value
  }
  match select {
    Ok(value) => assert_eq(value, "Ada")
    Err(_) => fail("select")
  }
}

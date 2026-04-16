pub(all) struct SqliteKv {
  conn: @sqlite3.Connection
}

pub fn open_sqlite_kv(path: String) -> SqliteKv? {
  let conn: Result[@sqlite3.Connection, _] = try? @sqlite3.Connection::open(path)
  match conn {
    Ok(conn) => {
      let init: Result[Unit, _] = try? {
        let stmt = conn.prepare("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        stmt.step_once()
        stmt.finalize()
      }
      match init {
        Ok(_) => Some({ conn: conn })
        Err(_) => {
          let _: Result[Unit, _] = try? conn.close()
          None
        }
      }
    }
    Err(_) => None
  }
}

pub fn SqliteKv::close(self: SqliteKv) -> Unit {
  let _: Result[Unit, _] = try? self.conn.close()
}

pub fn SqliteKv::get(self: SqliteKv, key: String) -> String? {
  let out: Result[String?, _] = try? {
    let stmt = self.conn.prepare("SELECT value FROM kv WHERE key = ?")
    stmt.bind(index=1, key)
    let value = if stmt.step() {
      Some(stmt.column(index=0))
    } else {
      None
    }
    stmt.finalize()
    value
  }
  match out {
    Ok(value) => value
    Err(_) => None
  }
}

pub fn SqliteKv::set(self: SqliteKv, key: String, value: String) -> Bool {
  let out: Result[Unit, _] = try? {
    let stmt = self.conn.prepare(
      "INSERT INTO kv(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
    )
    stmt.bind(index=1, key)
    stmt.bind(index=2, value)
    stmt.step_once()
    stmt.finalize()
  }
  match out {
    Ok(_) => true
    Err(_) => false
  }
}

pub fn SqliteKv::delete(self: SqliteKv, key: String) -> Bool {
  let out: Result[Unit, _] = try? {
    let stmt = self.conn.prepare("DELETE FROM kv WHERE key = ?")
    stmt.bind(index=1, key)
    stmt.step_once()
    stmt.finalize()
  }
  match out {
    Ok(_) => true
    Err(_) => false
  }
}

pub fn SqliteKv::keys_with_prefix(self: SqliteKv, prefix: String) -> Array[String] {
  let out: Result[Array[String], _] = try? {
    let stmt = self.conn.prepare("SELECT key FROM kv WHERE key LIKE ? ORDER BY key")
    stmt.bind(index=1, prefix + "/%")
    let keys: Array[String] = []
    while stmt.step() {
      keys.push(stmt.column(index=0))
    }
    stmt.finalize()
    keys
  }
  match out {
    Ok(keys) => keys
    Err(_) => []
  }
}

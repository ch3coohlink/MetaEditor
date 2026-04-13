test "runtime: resolve name scope path" {
  let app = ui("app", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", () =>
    h("div", [Id(app)], [
      h("div", [Id(title)], [])
    ])
  )
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("app/title") > 0, true)
}

test "runtime: plain id does not open scope" {
  let app = ui("app")
  let title = ui("title")
  let root = Entry::new("root", () =>
    h("div", [Id(app)], [
      h("div", [Id(title)], [])
    ])
  )
  let rt = Runtime::new(root)
  let result : Result[Int, _] = try? rt.resolve("app/title")
  match result {
    Ok(_) => fail("expected scope lookup to fail")
    Err(_) => ()
  }
}

test "runtime: nested name scope keeps boundary" {
  let app = ui("app", scope=Some(Name))
  let panel = ui("panel", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", () =>
    h("div", [Id(app)], [
      h("div", [Id(panel)], [
        h("div", [Id(title)], [])
      ])
    ])
  )
  let rt = Runtime::new(root)
  let miss : Result[Int, _] = try? rt.resolve("app/title")
  match miss {
    Ok(_) => fail("expected nested scope boundary")
    Err(_) => ()
  }
  assert_eq(rt.resolve("app/panel/title") > 0, true)
}

test "runtime: named descendant inside anonymous wrapper resolves in parent scope" {
  let app = ui("app", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", () =>
    h("div", [Id(app)], [
      h("div", [], [
        h("div", [Id(title)], [])
      ])
    ])
  )
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("app/title") > 0, true)
  let leaked : Result[Int, _] = try? rt.resolve("title")
  match leaked {
    Ok(_) => fail("expected descendant name to stay out of root scope")
    Err(_) => ()
  }
}

test "runtime: removing anonymous wrapper clears descendant names" {
  let show = cel(true)
  let app = ui("app", scope=Some(Name))
  let title = ui("title")
  let root = Entry::new("root", () =>
    h("div", [Id(app)], [
      Dyn(() => if show.get() {
        h("div", [], [h("div", [Id(title)], [])])
      } else { Null })
    ])
  )
  let rt = Runtime::new(root)
  assert_eq(rt.resolve("app/title") > 0, true)
  show.set(false)
  flush()
  let result : Result[Int, _] = try? rt.resolve("app/title")
  match result {
    Ok(_) => fail("expected removed descendant name to disappear")
    Err(_) => ()
  }
}

test "runtime: resolve empty path fails" {
  let root = Entry::new("root", () => h("div", [], []))
  let rt = Runtime::new(root)
  let result : Result[Int, _] = try? rt.resolve(" ")
  match result {
    Ok(_) => fail("expected empty query to fail")
    Err(_) => ()
  }
}

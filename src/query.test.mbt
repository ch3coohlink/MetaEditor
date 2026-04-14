test "query: scope keeps names map" {
  let root = ui("root", scope=true).inst()
  let child = ui("child").inst(parent=Some(root))
  root.add(child)
  assert_eq(root.is_scope(), true)
  assert_eq(root.get("child") is Some(_), true)
}

test "query: non scope has no names" {
  let root = ui("root").inst()
  assert_eq(root.is_scope(), false)
  assert_eq(root.get("child") is Some(_), false)
  assert_fail("non scope should not allow add", () => root.add(ui("child").inst(parent=Some(root))))
}

test "query: query walks downward through nested scopes" {
  let root = ui("root", scope=true).inst()
  let toolbar = ui("toolbar", scope=true).inst(parent=Some(root))
  let save = ui("save").inst(parent=Some(toolbar))
  root.add(toolbar)
  toolbar.add(save)
  let hit = root.query("toolbar/save")
  assert_eq(hit.path(), "root/toolbar/save")
}

test "query: query missing id fails" {
  let root = ui("root", scope=true).inst()
  assert_fail("missing path should fail", () => ignore(root.query("toolbar/save")))
}

test "query: del removes name from scope" {
  let root = ui("root", scope=true).inst()
  let child = ui("child").inst(parent=Some(root))
  root.add(child)
  assert_eq(root.get("child") is Some(_), true)
  root.del("child")
  assert_eq(root.get("child") is Some(_), false)
}

test "query: add rejects duplicate name" {
  let root = ui("root", scope=true).inst()
  let a = ui("item").inst(parent=Some(root))
  let b = ui("item").inst(parent=Some(root))
  root.add(a)
  assert_fail("duplicate ui id should fail", () => root.add(b))
}

test "query: add rejects wrong parent" {
  let root = ui("root", scope=true).inst()
  let other = ui("other", scope=true).inst()
  let child = ui("item").inst(parent=Some(other))
  assert_fail("wrong parent should fail", () => root.add(child))
}

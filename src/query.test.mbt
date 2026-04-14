test "query: scope keeps names map" {
  let root = ui("root", scope=Scope).inst()
  let child = ui("child").inst(parent=Some(root))
  root.add(child)
  assert_eq(root.is_scope(), true)
  assert_eq(root.get("child").path(), "root/child")
}

test "query: non scope has no names" {
  let root = ui("root").inst()
  assert_eq(root.is_scope(), false)
  assert_fail("non scope get should fail", () => ignore(root.get("child")))
  assert_fail("non scope should not allow add", () => root.add(ui("child").inst(parent=Some(root))))
}

test "query: query walks downward through nested scope and list" {
  let root = ui("root", scope=Scope).inst()
  let todos = ui("todos", scope=List).inst(parent=Some(root))
  let item = todos.push()
  let title = ui("title").inst(parent=Some(item))
  root.add(todos)
  item.add(title)
  let hit = root.query("todos/0/title")
  assert_eq(hit.path(), "root/todos/0/title")
}

test "query: query missing id fails" {
  let root = ui("root", scope=Scope).inst()
  assert_fail("missing path should fail", () => ignore(root.query("toolbar/save")))
}

test "query: del removes name from scope" {
  let root = ui("root", scope=Scope).inst()
  let child = ui("child").inst(parent=Some(root))
  root.add(child)
  assert_eq(root.get("child").path(), "root/child")
  root.del("child")
  assert_fail("deleted id should fail", () => ignore(root.get("child")))
}

test "query: add rejects duplicate name" {
  let root = ui("root", scope=Scope).inst()
  let a = ui("item").inst(parent=Some(root))
  let b = ui("item").inst(parent=Some(root))
  root.add(a)
  assert_fail("duplicate ui id should fail", () => root.add(b))
}

test "query: add rejects wrong parent" {
  let root = ui("root", scope=Scope).inst()
  let other = ui("other", scope=Scope).inst()
  let child = ui("item").inst(parent=Some(other))
  assert_fail("wrong parent should fail", () => root.add(child))
}

test "query: list starts empty and push creates indexed item" {
  let root = ui("root", scope=Scope).inst()
  let list = ui("todos", scope=List).inst(parent=Some(root))
  root.add(list)
  assert_eq(list.len(), 0)
  let item = list.push()
  let title = ui("title").inst(parent=Some(item))
  item.add(title)
  assert_eq(list.len(), 1)
  assert_eq(list.get("0").path(), "root/todos/0")
  assert_eq(item.path(), "root/todos/0")
}

test "query: list del removes item slot and compacts index" {
  let root = ui("root", scope=Scope).inst()
  let list = ui("todos", scope=List).inst(parent=Some(root))
  root.add(list)
  ignore(list.push())
  let item = list.push()
  assert_eq(item.path(), "root/todos/1")
  list.del("0")
  assert_eq(list.len(), 1)
  let next = list.get("0")
  assert_eq(next.path(), "root/todos/0")
  assert_fail("removed item should fail", () => ignore(list.get("1")))
}

test "query: list can nest list" {
  let root = ui("root", scope=Scope).inst()
  let todos = ui("todos", scope=List).inst(parent=Some(root))
  root.add(todos)
  let todo = todos.push()
  let subtasks = ui("subtasks", scope=List).inst(parent=Some(todo))
  todo.add(subtasks)
  let sub = subtasks.push()
  let title = ui("title").inst(parent=Some(sub))
  sub.add(title)
  let hit = root.query("todos/0/subtasks/0/title")
  assert_eq(hit.path(), "root/todos/0/subtasks/0/title")
}

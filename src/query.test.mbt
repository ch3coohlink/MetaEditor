test "query: scope keeps names map" {
  let host = ui("root", scope=Scope).inst(None)
  let scope = ui("scope", scope=Scope).inst(host)
  let child = ui("child").inst(scope)
  host.add(scope)
  scope.add(child)
  assert_eq(scope.get("child").path(), "root/scope/child")
}

test "query: non scope has no names" {
  let host = ui("root", scope=Scope).inst(None)
  let node = ui("node").inst(host)
  assert_fail("non scope get should fail", () => ignore(node.get("child")))
  assert_fail("non scope should not allow add", () => node.add(ui("child").inst(node)))
}

test "query: query walks downward through nested scope and list" {
  let root = ui("app", scope=Scope).inst(None)
  let todos = ui("todos", scope=List).inst(root)
  let item = todos.push()
  let title = ui("title").inst(item)
  root.add(todos)
  item.add(title)
  let hit = root.query("todos/0/title")
  assert_eq(hit.path(), "app/todos/0/title")
}

test "query: query missing id fails" {
  let root = ui("app", scope=Scope).inst(None)
  assert_fail("missing path should fail", () => ignore(root.query("toolbar/save")))
}

test "query: del removes name from scope" {
  let host = ui("root", scope=Scope).inst(None)
  let scope = ui("scope", scope=Scope).inst(host)
  let child = ui("child").inst(scope)
  scope.add(child)
  assert_eq(scope.get("child").path(), "root/scope/child")
  scope.del("child")
  assert_fail("deleted id should fail", () => ignore(scope.get("child")))
}

test "query: add rejects duplicate name" {
  let host = ui("root", scope=Scope).inst(None)
  let scope = ui("scope", scope=Scope).inst(host)
  let a = ui("item").inst(scope)
  let b = ui("item").inst(scope)
  scope.add(a)
  assert_fail("duplicate ui id should fail", () => scope.add(b))
}

test "query: add rejects id prefixed by parent id" {
  let root = ui("root", scope=Scope).inst(None)
  let child = ui("root-title").inst(root)
  assert_fail("prefixed ui id should fail", () => root.add(child))
}

test "query: add rejects wrong parent" {
  let host = ui("root", scope=Scope).inst(None)
  let root = ui("app", scope=Scope).inst(host)
  let other = ui("other", scope=Scope).inst(host)
  let child = ui("item").inst(other)
  assert_fail("wrong parent should fail", () => root.add(child))
}

test "query: list starts empty and push creates indexed item" {
  let root = ui("app", scope=Scope).inst(None)
  let list = ui("todos", scope=List).inst(root)
  root.add(list)
  assert_eq(list.len(), 0)
  let item = list.push()
  let title = ui("title").inst(item)
  item.add(title)
  assert_eq(list.len(), 1)
  assert_eq(list.get("0").path(), "app/todos/0")
  assert_eq(item.path(), "app/todos/0")
}

test "query: list del removes item slot and compacts index" {
  let root = ui("app", scope=Scope).inst(None)
  let list = ui("todos", scope=List).inst(root)
  root.add(list)
  ignore(list.push())
  let item = list.push()
  assert_eq(item.path(), "app/todos/1")
  list.del("0")
  assert_eq(list.len(), 1)
  let next = list.get("0")
  assert_eq(next.path(), "app/todos/0")
  assert_fail("removed item should fail", () => ignore(list.get("1")))
}

test "query: list can nest list" {
  let root = ui("app", scope=Scope).inst(None)
  let todos = ui("todos", scope=List).inst(root)
  root.add(todos)
  let todo = todos.push()
  let subtasks = ui("subtasks", scope=List).inst(todo)
  todo.add(subtasks)
  let sub = subtasks.push()
  let title = ui("title").inst(sub)
  sub.add(title)
  let hit = root.query("todos/0/subtasks/0/title")
  assert_eq(hit.path(), "app/todos/0/subtasks/0/title")
}

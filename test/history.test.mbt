test "apply_local updates value and version" {
  let store = @lib.new_store(1)
  let snap = @lib.apply_local(store, "inc", fn(v) { v + 1 })
  assert_eq(snap.value, 2)
  assert_eq(snap.version, 1)
  assert_eq(store.peek(), 2)
  assert_eq(store.peek_version(), 1)
}

test "apply_patch enforces cas" {
  let store = @lib.new_store(3)
  let ok = @lib.apply_patch(store, @lib.patch("replace", 0, 3, 8))
  assert_eq(ok, true)
  let conflict = @lib.apply_patch(store, @lib.patch("stale", 0, 8, 9))
  assert_eq(conflict, false)
  assert_eq(store.peek(), 8)
  assert_eq(store.peek_version(), 1)
}

test "undo and redo restore snapshots" {
  let store = @lib.new_store(0)
  let _ = @lib.apply_local(store, "add", fn(v) { v + 1 })
  let _ = @lib.apply_local(store, "add", fn(v) { v + 1 })
  assert_eq(store.peek(), 2)
  assert_eq(@lib.undo(store), true)
  assert_eq(store.peek(), 1)
  assert_eq(@lib.undo(store), true)
  assert_eq(store.peek(), 0)
  assert_eq(@lib.redo(store), true)
  assert_eq(store.peek(), 1)
  assert_eq(@lib.redo(store), true)
  assert_eq(store.peek(), 2)
}

pub(all) struct Snapshot[T] {
  version: Int
  value: T
}

pub(all) struct Patch[T] {
  label: String
  version: Int
  expect: T
  next: T
}

pub(all) struct Store[T] {
  state: Cel[T]
  rev: Cel[Int]
  undo_stack: Ref[Array[Snapshot[T]]]
  redo_stack: Ref[Array[Snapshot[T]]]
}

pub fn[T] new_store(initial: T) -> Store[T] {
  {
    state: cel(initial),
    rev: cel(0),
    undo_stack: Ref::new([]),
    redo_stack: Ref::new([]),
  }
}

fn[T] current_snapshot(store: Store[T]) -> Snapshot[T] {
  { version: store.rev.peek(), value: store.state.peek() }
}

fn[T] restore_snapshot(store: Store[T], snapshot: Snapshot[T]) -> Unit {
  store.state.set(snapshot.value)
  store.rev.set(snapshot.version)
}

pub fn[T] Store::read(self: Store[T]) -> T { self.state.get() }
pub fn[T] Store::peek(self: Store[T]) -> T { self.state.peek() }
pub fn[T] Store::version(self: Store[T]) -> Int { self.rev.get() }
pub fn[T] Store::peek_version(self: Store[T]) -> Int { self.rev.peek() }
pub fn[T] Store::snapshot(self: Store[T]) -> Snapshot[T] { current_snapshot(self) }
pub fn[T] Store::can_undo(self: Store[T]) -> Bool { self.undo_stack.val.length() > 0 }
pub fn[T] Store::can_redo(self: Store[T]) -> Bool { self.redo_stack.val.length() > 0 }

pub fn[T] patch(label: String, version: Int, expect: T, next: T) -> Patch[T] {
  { label, version, expect, next }
}

pub fn[T: Eq] apply_local(store: Store[T], _label: String, update: (T) -> T) -> Snapshot[T] {
  let before = current_snapshot(store)
  let after = update(before.value)
  if after != before.value {
    store.undo_stack.val.push(before)
    store.redo_stack.val.clear()
    store.state.set(after)
    store.rev.set(before.version + 1)
  }
  current_snapshot(store)
}

pub fn[T: Eq] apply_patch(store: Store[T], op: Patch[T]) -> Bool {
  let before = current_snapshot(store)
  if before.version != op.version || before.value != op.expect {
    return false
  }
  if before.value == op.next {
    return true
  }
  store.undo_stack.val.push(before)
  store.redo_stack.val.clear()
  store.state.set(op.next)
  store.rev.set(before.version + 1)
  true
}

pub fn[T] undo(store: Store[T]) -> Bool {
  match store.undo_stack.val.pop() {
    Some(snapshot) => {
      store.redo_stack.val.push(current_snapshot(store))
      restore_snapshot(store, snapshot)
      true
    }
    None => false
  }
}

pub fn[T] redo(store: Store[T]) -> Bool {
  match store.redo_stack.val.pop() {
    Some(snapshot) => {
      store.undo_stack.val.push(current_snapshot(store))
      restore_snapshot(store, snapshot)
      true
    }
    None => false
  }
}

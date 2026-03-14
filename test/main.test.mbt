test "signal get/set and effect rerun" {
  let count = @lib.signal(0)
  let seen : Ref[Array[Int]] = Ref::new([])
  let dispose = @lib.effect(fn() {
    seen.val.push(count.get())
  })

  assert_eq(seen.val, [0])
  count.set(1)
  assert_eq(seen.val, [0, 1])

  dispose()
  count.set(2)
  assert_eq(seen.val, [0, 1])
}

test "batch coalesces repeated updates" {
  let count = @lib.signal(0)
  let runs = Ref::new(0)
  let _dispose = @lib.effect(fn() {
    let _ = count.get()
    runs.val = runs.val + 1
  })

  assert_eq(runs.val, 1)
  @lib.batch(fn() {
    count.set(1)
    count.set(2)
    count.set(3)
  })
  assert_eq(runs.val, 2)
}

test "cleanup runs before rerun and on dispose" {
  let source = @lib.signal(1)
  let cleanup_log : Ref[Array[Int]] = Ref::new([])
  let _dispose = @lib.effect(fn() {
    let current = source.get()
    @lib.on_cleanup(fn() {
      cleanup_log.val.push(current)
    })
  })

  assert_eq(cleanup_log.val, [])
  source.set(2)
  assert_eq(cleanup_log.val, [1])
}

test "untracked read does not subscribe" {
  let source = @lib.signal(10)
  let runs = Ref::new(0)
  let _dispose = @lib.effect(fn() {
    runs.val = runs.val + 1
    let _ = @lib.untracked(fn() { source.get() })
  })

  assert_eq(runs.val, 1)
  source.set(11)
  assert_eq(runs.val, 1)
}

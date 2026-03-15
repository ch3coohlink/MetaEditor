test "signal get/set and effect rerun" {
  let count = @lib.cel(0)
  let seen : Ref[Array[Int]] = Ref::new([])
  let (_, stop) = @lib.scope(fn() {
    @lib.effect(fn() { seen.val.push(count.get()) })
  })

  assert_eq(seen.val, [0])
  count.set(1)
  assert_eq(seen.val, [0, 1])

  stop()
  count.set(2)
  assert_eq(seen.val, [0, 1])
}

test "batch coalesces repeated updates" {
  let count = @lib.cel(0)
  let runs = Ref::new(0)
  let _ = @lib.scope(fn() {
    @lib.effect(fn() {
      let _ = count.get()
      runs.val = runs.val + 1
    })
  })

  assert_eq(runs.val, 1)
  @lib.batch(fn() {
    count.set(1)
    count.set(2)
    count.set(3)
  })
  assert_eq(runs.val, 2)
}

test "cleanup runs before rerun and on scope stop" {
  let source = @lib.cel(1)
  let log : Ref[Array[Int]] = Ref::new([])
  let (_, stop) = @lib.scope(fn() {
    @lib.effect(fn() {
      let cur = source.get()
      @lib.onclr(fn() { log.val.push(cur) })
    })
  })

  assert_eq(log.val, [])
  source.set(2)
  assert_eq(log.val, [1])
  stop()
  assert_eq(log.val, [1, 2])
}

test "untracked read does not subscribe" {
  let source = @lib.cel(10)
  let runs = Ref::new(0)
  let _ = @lib.scope(fn() {
    @lib.effect(fn() {
      runs.val = runs.val + 1
      let _ = @lib.untracked(fn() { source.get() })
    })
  })

  assert_eq(runs.val, 1)
  source.set(11)
  assert_eq(runs.val, 1)
}

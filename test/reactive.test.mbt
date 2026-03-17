priv suberror TestErr {
  Boom(String)
}

test "signal get/set and effect rerun" {
  let count = @lib.cel(0)
  let seen: Ref[Array[Int]] = Ref::new([])
  let stop = @lib.scope(() => { let _ = @lib.effect(() => seen.val.push(count.get())); () }) catch { _ => panic() }

  assert_eq(seen.val, [0])
  count.set(1)
  @lib.flush() catch { _ => panic() }
  assert_eq(seen.val, [0, 1])

  stop()
  count.set(2)
  assert_eq(seen.val, [0, 1])
}

test "cleanup runs before rerun and on scope stop" {
  let source = @lib.cel(1)
  let log: Ref[Array[Int]] = Ref::new([])
  let stop = @lib.scope(() => {
    let _ = @lib.effect(() => {
      let cur = source.get()
      @lib.onclr(() => log.val.push(cur))
    })
  }) catch { _ => panic() }

  assert_eq(log.val, [])
  source.set(2)
  @lib.flush() catch { _ => panic() }
  assert_eq(log.val, [1])
  stop()
  assert_eq(log.val, [1, 2])
}

test "untracked read does not subscribe" {
  let source = @lib.cel(10)
  let runs = Ref::new(0)
  let _ = @lib.scope(() => {
    let _ = @lib.effect(() => {
      runs.val = runs.val + 1
      let _ = @lib.untracked(() => source.get()) catch { _ => panic() }
    })
  }) catch { _ => panic() }

  assert_eq(runs.val, 1)
  source.set(11)
  @lib.flush() catch { _ => panic() }
  assert_eq(runs.val, 1)
}

test "effect raise does not poison later scopes" {
  fn boom() -> Unit raise {
    raise Boom("boom")
  }

  let threw = try {
    let _ = @lib.scope(() => { let _ = @lib.effect(boom); () })
    false
  } catch { _ => true }
  assert_eq(threw, true)

  let count = @lib.cel(0)
  let seen: Ref[Array[Int]] = Ref::new([])
  let stop = @lib.scope(() => { let _ = @lib.effect(() => seen.val.push(count.get())); () }) catch { _ => panic() }

  assert_eq(seen.val, [0])
  count.set(1)
  @lib.flush() catch { _ => panic() }
  assert_eq(seen.val, [0, 1])
  stop()
}

test "computed derives and caches" {
  let a = @lib.cel(2)
  let b = @lib.cel(3)
  let stop = @lib.scope(() => {
    let sum = @lib.computed(fn() { a.get() + b.get() })
    assert_eq(sum.get(), 5)
    a.set(10)
    @lib.flush()
    assert_eq(sum.get(), 13)
    b.set(7)
    @lib.flush()
    assert_eq(sum.get(), 17)
  }) catch { _ => panic() }
  stop()
}

test "watch receives old and new values" {
  let source = @lib.cel(1)
  let log: Ref[Array[(Int, Int)]] = Ref::new([])
  let stop = @lib.scope(() => {
    let _ = @lib.watch(source, fn(old, cur) { log.val.push((old, cur)) })
  }) catch { _ => panic() }
  source.set(2)
  @lib.flush() catch { _ => panic() }
  source.set(5)
  @lib.flush() catch { _ => panic() }
  assert_eq(log.val, [(1, 2), (2, 5)])
  stop()
}

test "watch does not fire when value unchanged" {
  let source = @lib.cel(1)
  let runs = Ref::new(0)
  let stop = @lib.scope(() => {
    let _ = @lib.watch(source, fn(_old, _cur) { runs.val = runs.val + 1 })
  }) catch { _ => panic() }
  source.set(1) // 相同值
  @lib.flush() catch { _ => panic() }
  assert_eq(runs.val, 0)
  stop()
}

test "watch_raw fires every time" {
  let source = @lib.cel(1)
  let seen: Ref[Array[Int]] = Ref::new([])
  let stop = @lib.scope(() => {
    let _ = @lib.watch_raw(source, fn(v) { seen.val.push(v) })
  }) catch { _ => panic() }
  assert_eq(seen.val, [1]) // 初始执行
  source.set(1) // 相同值也触发
  @lib.flush() catch { _ => panic() }
  assert_eq(seen.val, [1, 1])
  stop()
}

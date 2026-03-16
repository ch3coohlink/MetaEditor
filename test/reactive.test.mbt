priv suberror TestErr {
  Boom(String)
}

test "signal get/set and effect rerun" {
  let count = @lib.cel(0)
  let seen: Ref[Array[Int]] = Ref::new([])
  let stop = @lib.scope(() => @lib.effect(() => seen.val.push(count.get()))) catch { _ => panic() }

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
    @lib.effect(() => {
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
    @lib.effect(() => {
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
    let _ = @lib.scope(() => @lib.effect(boom))
    false
  } catch { _ => true }
  assert_eq(threw, true)

  let count = @lib.cel(0)
  let seen: Ref[Array[Int]] = Ref::new([])
  let stop = @lib.scope(() => @lib.effect(() => seen.val.push(count.get()))) catch { _ => panic() }

  assert_eq(seen.val, [0])
  count.set(1)
  @lib.flush() catch { _ => panic() }
  assert_eq(seen.val, [0, 1])
  stop()
}


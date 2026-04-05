priv suberror TestErr {
  Boom(String)
}

test "signal get/set and effect rerun" {
  let count = cel(0)
  let seen: Ref[Array[Int]] = Ref::new([])
  let stop = scope(() => { let _ = effect(() => seen.val.push(count.get())); () }) catch { _ => panic() }

  assert_eq(seen.val, [0])
  count.set(1)
  flush() catch { _ => panic() }
  assert_eq(seen.val, [0, 1])

  stop()
  count.set(2)
  assert_eq(seen.val, [0, 1])
}

test "cleanup runs before rerun and on scope stop" {
  let source = cel(1)
  let log: Ref[Array[Int]] = Ref::new([])
  let stop = scope(() => {
    let _ = effect(() => {
      let cur = source.get()
      onclr(() => log.val.push(cur))
    })
  }) catch { _ => panic() }

  assert_eq(log.val, [])
  source.set(2)
  flush() catch { _ => panic() }
  assert_eq(log.val, [1])
  stop()
  assert_eq(log.val, [1, 2])
}

test "untracked read does not subscribe" {
  let source = cel(10)
  let runs = Ref::new(0)
  let _ = scope(() => {
    let _ = effect(() => {
      runs.val = runs.val + 1
      let _ = untracked(() => source.get()) catch { _ => panic() }
    })
  }) catch { _ => panic() }

  assert_eq(runs.val, 1)
  source.set(11)
  flush() catch { _ => panic() }
  assert_eq(runs.val, 1)
}

test "effect raise does not poison later scopes" {
  fn boom() -> Unit raise {
    raise Boom("boom")
  }

  let threw = try {
    let _ = scope(() => { let _ = effect(boom); () })
    false
  } catch { _ => true }
  assert_eq(threw, true)

  let count = cel(0)
  let seen: Ref[Array[Int]] = Ref::new([])
  let stop = scope(() => { let _ = effect(() => seen.val.push(count.get())); () }) catch { _ => panic() }

  assert_eq(seen.val, [0])
  count.set(1)
  flush() catch { _ => panic() }
  assert_eq(seen.val, [0, 1])
  stop()
}

test "cel mutate reruns effects" {
  let list = cel(["A"])
  let seen: Ref[Array[Int]] = Ref::new([])
  let stop = scope(() => {
    let _ = effect(() => seen.val.push(list.get().length()))
    ()
  }) catch { _ => panic() }

  assert_eq(seen.val, [1])
  list.mutate(xs => { xs.push("B") })
  flush() catch { _ => panic() }
  assert_eq(seen.val, [1, 2])
  stop()
}

test "cel mutate can edit array in place" {
  let list = cel([1, 2])
  let seen: Ref[Array[Int]] = Ref::new([])
  let stop = scope(() => {
    let _ = effect(() => seen.val.push(list.get().length()))
    ()
  }) catch { _ => panic() }

  assert_eq(seen.val, [2])
  list.mutate(xs => {
    xs.push(3)
    xs.push(4)
  })
  flush() catch { _ => panic() }
  assert_eq(seen.val, [2, 4])
  stop()
}

test "track dedups repeated reads in one effect" {
  let source = cel(1)
  let stop = scope(() => {
    let _ = effect(() => {
      ignore(source.get())
      ignore(source.get())
      ignore(source.get())
    })
    ()
  }) catch { _ => panic() }

  assert_eq(source.subs.val.length(), 1)
  source.set(2)
  flush() catch { _ => panic() }
  assert_eq(source.subs.val.length(), 1)
  stop()
  assert_eq(source.subs.val.length(), 0)
}

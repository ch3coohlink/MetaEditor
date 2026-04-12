test "reactive: effect runs immediately on create" {
  let s = Scope::new()
  let c = cel(1)
  let mut seen = 0
  s.run(() => {
    ignore(effect(() => { seen = c.get() }))
  })
  assert_eq(seen, 1)
}

test "reactive: updates wait for flush" {
  let s = Scope::new()
  let c = cel(0)
  let mut seen = -1
  s.run(() => {
    ignore(effect(() => { seen = c.get() }))
  })
  assert_eq(seen, 0)
  c.set(1)
  assert_eq(seen, 0)
  flush()
  assert_eq(seen, 1)
}

test "reactive: effect dedups before flush" {
  let s = Scope::new()
  let c = cel(0)
  let mut runs = 0
  let mut seen = -1
  s.run(() => {
    ignore(effect(() => { runs = runs + 1; seen = c.get() }))
  })
  assert_eq(runs, 1)
  c.set(1)
  c.set(2)
  c.set(3)
  flush()
  assert_eq(runs, 2)
  assert_eq(seen, 3)
}

test "reactive: repeated get in one effect does not duplicate deps" {
  let s = Scope::new()
  let c = cel(1)
  let mut runs = 0
  let mut seen = 0
  s.run(() => {
    ignore(effect(() => {
      runs = runs + 1
      seen = if c.get() > 0 { c.get() } else { 0 }
    }))
  })
  assert_eq(runs, 1)
  assert_eq(seen, 1)
  c.set(2)
  flush()
  assert_eq(runs, 2)
  assert_eq(seen, 2)
}

test "reactive: ternary tracks only active branch" {
  let s = Scope::new()
  let cond = cel(true)
  let a = cel(10)
  let b = cel(20)
  let mut runs = 0
  let mut seen = 0
  s.run(() => {
    ignore(effect(() => {
      runs = runs + 1
      seen = if cond.get() { a.get() } else { b.get() }
    }))
  })
  assert_eq(runs, 1)
  assert_eq(seen, 10)
  b.set(30)
  flush()
  assert_eq(runs, 1)
  assert_eq(seen, 10)
  a.set(11)
  flush()
  assert_eq(runs, 2)
  assert_eq(seen, 11)
}

test "reactive: ternary switches deps after branch change" {
  let s = Scope::new()
  let cond = cel(true)
  let a = cel(10)
  let b = cel(20)
  let mut runs = 0
  let mut seen = 0
  s.run(() => {
    ignore(effect(() => {
      runs = runs + 1
      seen = if cond.get() { a.get() } else { b.get() }
    }))
  })
  cond.set(false)
  flush()
  assert_eq(runs, 2)
  assert_eq(seen, 20)
  a.set(99)
  flush()
  assert_eq(runs, 2)
  assert_eq(seen, 20)
  b.set(21)
  flush()
  assert_eq(runs, 3)
  assert_eq(seen, 21)
}

test "reactive: stop cancels queued effect" {
  let s = Scope::new()
  let c = cel(0)
  let mut runs = 0
  s.run(() => {
    ignore(effect(() => { runs = runs + 1; ignore(c.get()) }))
  })
  assert_eq(runs, 1)
  c.set(1)
  s.stop()
  flush()
  assert_eq(runs, 1)
}

test "reactive: stop detaches deps" {
  let s = Scope::new()
  let c = cel(0)
  let mut runs = 0
  let stop = s.run(() => effect(() => { runs = runs + 1; ignore(c.get()) }))
  assert_eq(runs, 1)
  stop()
  c.set(1)
  flush()
  assert_eq(runs, 1)
}

test "reactive: one flush drains chained effects" {
  let s = Scope::new()
  let a = cel(0)
  let b = cel(0)
  let mut seen = 0
  s.run(() => {
    ignore(effect(() => {
      let v = a.get()
      if v > 0 { b.set(v + 1) }
    }))
    ignore(effect(() => { seen = b.get() }))
  })
  assert_eq(seen, 0)
  a.set(1)
  flush()
  assert_eq(seen, 2)
}

test "reactive: flush recovers after error" {
  let bad_scope = Scope::new()
  let bad = cel(0)
  bad_scope.run(() => {
    ignore(effect(() => {
      let v = bad.get()
      if v >= 0 { bad.set(v + 1) }
    }))
  })
  let failed : Result[Unit, _] = try? flush()
  match failed {
    Ok(_) => fail("expected flush to fail")
    Err(_) => ()
  }
  bad_scope.stop()
  let good_scope = Scope::new()
  let good = cel(0)
  let mut seen = -1
  good_scope.run(() => {
    ignore(effect(() => { seen = good.get() }))
  })
  assert_eq(seen, 0)
  good.set(1)
  flush()
  assert_eq(seen, 1)
}

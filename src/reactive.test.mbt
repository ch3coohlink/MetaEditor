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

test "reactive: fuzz matches queued dependency model" {
  let rng = new_rng()
  let a = cel(1)
  let b = cel(10)
  let c = cel(100)
  let cond = cel(true)
  let s1 = Scope::new()
  let s2 = Scope::new()
  let mut runs1 = 0
  let mut runs2 = 0
  let mut seen1 = 0
  let mut seen2 = 0
  s1.run(() => {
    ignore(effect(() => {
      runs1 = runs1 + 1
      seen1 = if cond.get() { a.get() } else { b.get() }
    }))
  })
  s2.run(() => {
    ignore(effect(() => {
      runs2 = runs2 + 1
      seen2 = a.get() + c.get()
    }))
  })
  let ma = Ref::new(1)
  let mb = Ref::new(10)
  let mc = Ref::new(100)
  let mcond = Ref::new(true)
  let mactive1 = Ref::new(true)
  let mactive2 = Ref::new(true)
  let mqueued1 = Ref::new(false)
  let mqueued2 = Ref::new(false)
  let mruns1 = Ref::new(1)
  let mruns2 = Ref::new(1)
  let mseen1 = Ref::new(1)
  let mseen2 = Ref::new(101)
  fn queue1(
    active: Ref[Bool],
    queued: Ref[Bool],
  ) -> Unit {
    if active.val { queued.val = true }
  }
  fn queue2(
    active: Ref[Bool],
    queued: Ref[Bool],
  ) -> Unit {
    if active.val { queued.val = true }
  }
  fn model_flush(
    active1: Ref[Bool],
    active2: Ref[Bool],
    queued1: Ref[Bool],
    queued2: Ref[Bool],
    runs1: Ref[Int],
    runs2: Ref[Int],
    seen1: Ref[Int],
    seen2: Ref[Int],
    cond: Ref[Bool],
    a: Ref[Int],
    b: Ref[Int],
    c: Ref[Int],
  ) -> Unit {
    if queued1.val && active1.val {
      queued1.val = false
      runs1.val = runs1.val + 1
      seen1.val = if cond.val { a.val } else { b.val }
    } else {
      queued1.val = false
    }
    if queued2.val && active2.val {
      queued2.val = false
      runs2.val = runs2.val + 1
      seen2.val = a.val + c.val
    } else {
      queued2.val = false
    }
  }
  let mut step = 0
  while step < 200 {
    match rng.pick(8) {
      0 => {
        let next = rng.pick(20)
        a.set(next)
        ma.val = next
        if mcond.val { queue1(mactive1, mqueued1) }
        queue2(mactive2, mqueued2)
      }
      1 => {
        let next = rng.pick(20) + 100
        b.set(next)
        mb.val = next
        if !mcond.val { queue1(mactive1, mqueued1) }
      }
      2 => {
        let next = rng.pick(20) + 200
        c.set(next)
        mc.val = next
        queue2(mactive2, mqueued2)
      }
      3 => {
        cond.set(!cond.peek())
        mcond.val = !mcond.val
        queue1(mactive1, mqueued1)
      }
      4 => {
        a.set(a.peek() + 1)
        ma.val = ma.val + 1
        if mcond.val { queue1(mactive1, mqueued1) }
        queue2(mactive2, mqueued2)
      }
      5 => {
        c.set(c.peek() + 1)
        mc.val = mc.val + 1
        queue2(mactive2, mqueued2)
      }
      6 => {
        s1.stop()
        mactive1.val = false
        mqueued1.val = false
      }
      _ => {
        s2.stop()
        mactive2.val = false
        mqueued2.val = false
      }
    }
    if rng.pick(3) == 0 {
      flush()
      model_flush(
        mactive1, mactive2, mqueued1, mqueued2,
        mruns1, mruns2, mseen1, mseen2, mcond, ma, mb, mc,
      )
      assert_eq(runs1, mruns1.val)
      assert_eq(runs2, mruns2.val)
      assert_eq(seen1, mseen1.val)
      assert_eq(seen2, mseen2.val)
    }
    step = step + 1
  }
  flush()
  model_flush(
    mactive1, mactive2, mqueued1, mqueued2,
    mruns1, mruns2, mseen1, mseen2, mcond, ma, mb, mc,
  )
  assert_eq(runs1, mruns1.val)
  assert_eq(runs2, mruns2.val)
  assert_eq(seen1, mseen1.val)
  assert_eq(seen2, mseen2.val)
}

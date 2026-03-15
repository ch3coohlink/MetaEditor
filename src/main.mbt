let sid: Ref[Int] = Ref::new(0)
let eid: Ref[Int] = Ref::new(-1)
let oid: Ref[Int] = Ref::new(-1)
let on: Ref[Bool] = Ref::new(true)
let depth: Ref[Int] = Ref::new(0)
let pending: Ref[Array[Int]] = Ref::new([])
let effs: Array[Effect] = []
let scps: Array[Scope] = []

fn clear(i: Int) -> Unit {
  effs[i].deps = []
  for f in effs[i].cleanups { f() }
  effs[i].cleanups = []
}
fn flush() -> Unit {
  while pending.val.length() > 0 {
    let cur = pending.val
    pending.val = []
    for i in cur {
      effs[i].queued = false
      if effs[i].active { (effs[i].run)() }
    }
  }
}
fn queue(i: Int) -> Unit {
  if not(effs[i].active) || effs[i].queued { return }
  effs[i].queued = true
  pending.val.push(i)
  if depth.val == 0 { flush() }
}
pub fn onclr(f: () -> Unit) -> Unit {
  let i = eid.val
  if i >= 0 { return effs[i].cleanups.push(f) }
  let s = oid.val
  if s >= 0 { scps[s].clrs.push(f) }
}
fn[T] track(sig: Cel[T]) -> Unit {
  if not(on.val) { return }
  let i = eid.val
  if i < 0 || effs[i].deps.contains(sig.id) { return }
  effs[i].deps.push(sig.id)
  sig.subs.val.push(i)
  onclr(fn() { sig.subs.val = sig.subs.val.filter(fn(x) { x != i }) })
}
fn[T] within(i: Int, f: () -> T) -> T {
  let pe = eid.val
  let po = on.val
  eid.val = i
  on.val = true
  let r = f()
  eid.val = pe
  on.val = po
  r
}
pub fn[T] untracked(f: () -> T) -> T {
  let prev = on.val
  on.val = false
  let r = f()
  on.val = prev
  r
}
pub fn[T] batch(f: () -> T) -> T {
  depth.val = depth.val + 1
  let r = f()
  depth.val = depth.val - 1
  if depth.val == 0 { flush() }
  r
}

pub struct Cel[T] { id: Int; cell: Ref[T]; subs: Ref[Array[Int]] }
pub fn[T] cel(x: T) -> Cel[T] {
  let i = sid.val
  sid.val = i + 1
  { id: i, cell: Ref::new(x), subs: Ref::new([]) }
}
pub fn[T] Cel::peek(self: Cel[T]) -> T { self.cell.val }
pub fn[T] Cel::get(self: Cel[T]) -> T { track(self); self.cell.val }
pub fn[T] Cel::set(self: Cel[T], x: T) -> Unit {
  self.cell.val = x
  for i in self.subs.val { queue(i) }
}
pub fn[T] Cel::update(self: Cel[T], f: (T) -> T) -> Unit { self.set(f(self.cell.val)) }

priv struct Effect {
  run: () -> Unit; mut active: Bool; mut queued: Bool
  mut deps: Array[Int]; mut cleanups: Array[() -> Unit]
}
fn Effect::new(run: () -> Unit) -> Effect {{
  run, active: true, queued: false, deps: [], cleanups: []
}}
pub fn effect(f: () -> Unit) -> Unit {
  let i = effs.length()
  fn run() {
    if not(effs[i].active) { return }
    clear(i)
    within(i, f) |> ignore
  }
  fn stop() {
    if not(effs[i].active) { return }
    effs[i].active = false
    effs[i].queued = false
    clear(i)
  }
  effs.push(Effect::new(run))
  let s = oid.val
  if s >= 0 { scps[s].clrs.push(stop) }
  run()
}

priv struct Scope { mut active: Bool; mut clrs: Array[() -> Unit] }
fn Scope::new() -> Scope {{ active: true, clrs: [] }}
pub fn[T] scope(f: () -> T) -> (T, () -> Unit) {
  let i = scps.length()
  scps.push(Scope::new())
  let ps = oid.val
  oid.val = i
  let r = f()
  oid.val = ps
  fn stop() {
    if not(scps[i].active) { return }
    scps[i].active = false
    for g in scps[i].clrs { g() }
    scps[i].clrs = []
  }
  (r, stop)
}

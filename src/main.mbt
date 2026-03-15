let sid: Ref[Int] = Ref::new(0)
let eid: Ref[Int] = Ref::new(-1)
let oid: Ref[Int] = Ref::new(-1)
let on: Ref[Bool] = Ref::new(true)
let depth: Ref[Int] = Ref::new(0)
let pending: Ref[Array[Int]] = Ref::new([])
let scheduled: Ref[Bool] = Ref::new(false)
let effcts: Array[Effect] = []
let scopes: Array[Scope] = []

fn clear(i: Int) -> Unit {
  effcts[i].deps = []
  for f in effcts[i].cleanups { f() }
  effcts[i].cleanups = []
}
pub fn flush() -> Unit {
  scheduled.val = false
  while pending.val.length() > 0 {
    let cur = pending.val
    pending.val = []
    for i in cur {
      effcts[i].queued = false
      if effcts[i].active { (effcts[i].run)() }
    }
  }
}
fn queue(i: Int) -> Unit {
  if not(effcts[i].active) || effcts[i].queued { return }
  effcts[i].queued = true
  pending.val.push(i)
  scheduled.val = true
}
pub fn onclr(f: () -> Unit) -> Unit {
  let i = eid.val
  if i >= 0 { return effcts[i].cleanups.push(f) }
  let s = oid.val
  if s >= 0 { scopes[s].clrs.push(f) }
}
fn[T] track(sig: Cel[T]) -> Unit {
  if not(on.val) { return }
  let i = eid.val
  if i < 0 || effcts[i].deps.contains(sig.id) { return }
  effcts[i].deps.push(sig.id)
  sig.subs.val.push(i)
  onclr(fn() { sig.subs.val = sig.subs.val.filter(fn(x) { x != i }) })
}
pub fn[T] untracked(f: () -> T) -> T {
  let prev = on.val
  on.val = false
  let r = f()
  on.val = prev
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
  let i = effcts.length()
  fn run() {
    if not(effcts[i].active) { return }
    let pe = eid.val
    let po = on.val
    depth.val = depth.val + 1
    eid.val = i
    on.val = true
    clear(i)
    f() |> ignore
    eid.val = pe
    on.val = po
    depth.val = depth.val - 1
  }
  fn stop() {
    if not(effcts[i].active) { return }
    effcts[i].active = false
    effcts[i].queued = false
    clear(i)
  }
  effcts.push(Effect::new(run))
  let s = oid.val
  if s >= 0 { scopes[s].clrs.push(stop) }
  run()
}

priv struct Scope { mut active: Bool; mut clrs: Array[() -> Unit] }
fn Scope::new() -> Scope {{ active: true, clrs: [] }}
pub fn[T] scope(f: () -> T) -> (T, () -> Unit) {
  let i = scopes.length()
  scopes.push(Scope::new())
  let ps = oid.val
  oid.val = i
  let r = f()
  oid.val = ps
  fn stop() {
    if not(scopes[i].active) { return }
    scopes[i].active = false
    for g in scopes[i].clrs { g() }
    scopes[i].clrs = []
  }
  (r, stop)
}

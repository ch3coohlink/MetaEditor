let sid: Ref[Int] = Ref::new(0)
let eid: Ref[Int] = Ref::new(-1)
let oid: Ref[Int] = Ref::new(-1)
let on: Ref[Bool] = Ref::new(true)
let pending: Ref[Array[Int]] = Ref::new([])
let effcts: Array[Effect] = []
let scopes: Array[Scope] = []

fn clear(i: Int) -> Unit {
  effcts[i].deps = []
  let e = effcts[i]
  for f in scopes[e.owner].clrs[e.slot] { f() }
  scopes[e.owner].clrs[e.slot] = []
}
pub fn flush() -> Unit {
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
}
pub fn onclr(f: () -> Unit) -> Unit {
  let i = eid.val
  if i >= 0 {
    let e = effcts[i]
    scopes[e.owner].clrs[e.slot].push(f)
    return
  }
  let s = oid.val
  if s >= 0 { scopes[s].clrs[0].push(f) }
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
  run: () -> Unit; owner: Int; slot: Int; mut active: Bool; mut queued: Bool
  mut deps: Array[Int]
}
fn Effect::new(run: () -> Unit, owner: Int, slot: Int) -> Effect {{
  run, owner, slot, active: true, queued: false, deps: []
}}
pub fn effect(f: () -> Unit) -> Unit {
  let s = oid.val
  if s < 0 { abort("effect must be created inside scope") }
  let i = effcts.length()
  let k = scopes[s].clrs.length()
  scopes[s].clrs.push([])
  fn run() {
    if not(effcts[i].active) { return }
    let pe = eid.val
    let po = on.val
    let ps = oid.val
    eid.val = i
    oid.val = s
    on.val = true
    clear(i)
    f() |> ignore
    eid.val = pe
    oid.val = ps
    on.val = po
  }
  fn stop() {
    if not(effcts[i].active) { return }
    effcts[i].active = false
    effcts[i].queued = false
    clear(i)
  }
  effcts.push(Effect::new(run, s, k))
  scopes[s].clrs[0].push(stop)
  run()
}

priv struct Scope { mut active: Bool; mut clrs: Array[Array[() -> Unit]] }
fn Scope::new() -> Scope {{ active: true, clrs: [[]] }}
pub fn scope(f: () -> Unit) -> () -> Unit {
  let i = scopes.length()
  let scp = Scope::new()
  scopes.push(scp)
  let ps = oid.val
  oid.val = i
  f()
  oid.val = ps
  fn stop() {
    if not(scp.active) { return }
    scp.active = false
    for cs in scp.clrs { for g in cs { g() } }
    scp.clrs = [[]]
  }
  stop
}

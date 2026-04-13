let fscp: Scope = Scope::new()
let feff: Eff = Eff::new(fscp, fn() {})
let cscp: Ref[Scope] = Ref::new(fscp)
let ceff: Ref[Eff] = Ref::new(feff)
let eid: Ref[Int] = Ref::new(0)
fn eff_id () -> Int { let id = eid.val; eid.val = id + 1; id }

type Dep = Set[Eff]
pub struct Cel[T] { mut v: T; dep: Dep }
pub fn[T] cel(x: T) -> Cel[T] {{ v: x, dep: Set::new() }}
pub fn[T] Cel::peek(s: Cel[T]) -> T { s.v }
pub fn[T] Cel::get(s: Cel[T]) -> T {
  let e = ceff.val; if e.id == feff.id { return s.v }
  if s.dep.contains(e) { return s.v }
  s.dep.add(e); e.deps.push(s.dep); s.v
}
fn[T] Cel::notify(s: Cel[T]) -> Unit { for e in s.dep { eq.add(e) } }
pub fn[T] Cel::set(s: Cel[T], x: T) -> Unit { s.v = x; s.notify() }
pub fn[T] Cel::mutate(s: Cel[T], f: (T) -> Unit) -> Unit { f(s.v); s.notify() }

pub struct Scope { mut active: Bool; clrs: ClearHooks }
impl HasClrs for Scope with clrs(s) { s.clrs }
pub fn Scope::new() -> Scope {{ active: true, clrs: [] }}
pub fn[T] Scope::run(s: Scope, f: () -> T) -> T { cscp.protect(s, f) }
pub fn Scope::stop(s: Scope) -> Unit { if s.active { s.active = false; clean(s) } }

pub struct Eff { id: Int; f: () -> Unit; scope: Scope; deps: Array[Dep]; mut queued: Bool }
impl Eq for Eff with equal(a, b) { a.id == b.id }
impl Hash for Eff with hash_combine(self, hasher) { hasher.combine_int(self.id) }
pub fn Eff::new(s: Scope, f: () -> Unit) -> Eff {{ id: eff_id(), f, scope: s, deps: [], queued: false }}
fn Eff::clean(s: Eff) -> Unit { for d in s.deps { d.remove(s) }; s.deps.clear() }
pub fn[T] Eff::run(s: Eff, f: () -> T) -> T { ceff.protect(s, f) }

priv struct EffQueue { mut items: Array[Eff]; mut lock: Bool }
fn EffQueue::new() -> EffQueue {{ items: [], lock: false }}
fn EffQueue::add(s: EffQueue, e: Eff) -> Unit { if !e.queued { e.queued = true; s.items.push(e) } }
fn EffQueue::take(s: EffQueue) -> Array[Eff] { let out = s.items; s.items = []; out }
fn EffQueue::flush(s: EffQueue) -> Unit raise {
  if s.lock { return }; s.lock = true; defer { s.lock = false }; try {
    let mut n = 0; while s.items.length() > 0 {
      for e in s.take() {
        e.queued = false; if e.scope.active { (e.f)() }; n += 1
        if n > 1000 { fail("infinite reactive triggering detected") }
      }
    }
  } catch { e => { for e in s.take() { e.queued = false }; raise e } }
}
let eq: EffQueue = EffQueue::new()
pub fn flush() -> Unit raise { eq.flush() }

pub fn effect(f: () -> Unit) -> () -> Unit {
  let s = cscp.val; let mut eff = feff; let clr = () => eff.clean()
  eff = Eff::new(s, () => { if s.active { clr(); s.run(() => eff.run(f)) } })
  onclr(s, clr); (eff.f)(); clr
}

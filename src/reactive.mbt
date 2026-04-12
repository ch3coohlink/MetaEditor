let fscp: Scope = Scope::new()
let feff: Eff = Eff::new(fscp, fn() {})
let cscp: Ref[Scope] = Ref::new(fscp)
let ceff: Ref[Eff] = Ref::new(feff)
let eid: Ref[Int] = Ref::new(0)
fn eff_id () -> Int { let id = eid.val; eid.val = id + 1; id }

pub struct Cel[T] { mut v: T; effs: Set[Eff] }
pub fn[T] cel(x: T) -> Cel[T] {{ v: x, effs: Set::new() }}
pub fn[T] Cel::peek(s: Cel[T]) -> T { s.v }
pub fn[T] Cel::get(s: Cel[T]) -> T {
  let e = ceff.val; if e.id == feff.id { return s.v }
  if s.effs.contains(e) { return s.v }
  s.effs.add(e); onclr(e, () => { s.effs.remove(e) }); s.v
}
fn[T] Cel::notify(s: Cel[T]) -> Unit { for e in s.effs { (e.f)() } }
pub fn[T] Cel::set(s: Cel[T], x: T) -> Unit { s.v = x; s.notify() }
pub fn[T] Cel::mutate(s: Cel[T], f: (T) -> Unit) -> Unit { f(s.v); s.notify() }

pub struct Scope { mut active: Bool; clrs: ClearHooks }
impl HasClrs for Scope with clrs(s) { s.clrs }
pub fn Scope::new() -> Scope {{ active: true, clrs: [] }}
pub fn[T] Scope::run(s: Scope, f: () -> T) -> T { cscp.protect(s, f) }
pub fn Scope::stop(s: Scope) -> Unit { if s.active { s.active = false; clean(s) } }

pub struct Eff { id: Int; f: () -> Unit; scope: Scope; clrs: ClearHooks }
impl Eq for Eff with equal(a, b) { a.id == b.id }
impl Hash for Eff with hash_combine(self, hasher) { hasher.combine_int(self.id) }
pub fn Eff::new(s: Scope, f: () -> Unit) -> Eff {{ id: eff_id(), f, scope: s, clrs:[] }}
pub fn[T] Eff::run(s: Eff, f: () -> T) -> T { ceff.protect(s, f) }
impl HasClrs for Eff with clrs(s) { s.clrs }

pub fn effect(f: () -> Unit) -> () -> Unit {
  let s = cscp.val; let mut eff = feff; let clr = () => clean(eff); onclr(s, clr)
  eff = Eff::new(s, () => { if s.active { clr(); s.run(() => eff.run(f)) } })
  (eff.f)(); clr
}

let ceff: Ref[Eff?] = Ref::new(None)
let cscp: Ref[Scope?] = Ref::new(None)

pub struct Cel[T] { mut v: T }
pub fn[T] cel(x: T) -> Cel[T] {{ v: x }}
pub fn[T] Cel::peek(s: Cel[T]) -> T { s.v }
pub fn[T] Cel::get(s: Cel[T]) -> T { s.v }
pub fn[T] Cel::set(s: Cel[T], x: T) -> Unit { s.v = x }
pub fn[T] Cel::mutate(s: Cel[T], f: (T) -> Unit) -> Unit { f(s.v) }

pub struct Scope { mut active: Bool; clrs: ClearHooks }
impl HasClrs for Scope with clrs(s) { s.clrs }
pub fn Scope::new() -> Scope {{ active: true, clrs: [] }}
pub fn[T] Scope::run(s: Scope, f: () -> T raise) -> T raise { cscp.protect(Some(s), f) }
pub fn Scope::stop(s: Scope) -> Unit { if s.active { s.active = false; clean(s) } }

pub struct Eff { run: () -> Result[Unit, Error]; scope: Scope; clrs: ClearHooks }
impl HasClrs for Eff with clrs(s) { s.clrs }

pub fn effect(f: () -> Unit raise) -> Result[() -> Unit, Error] {
  let s = match cscp.val { Some(s) => s; _ => return try? fail("effect must be created inside scope") }
  let clrs = []; let run = () => { if !s.active { Ok(()) } else { clean({ clrs, }); try? s.run(f) } }
  let eff = { run, scope: s, clrs }
  let clr = () => clean(eff); onclr(s, clr)
  match run() { Ok(_) => Ok(clr); Err(e) => Err(e) }
}

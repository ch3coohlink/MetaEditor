pub struct Cel[T] { mut v: T }
pub fn[T] cel(x: T) -> Cel[T] {{ v: x }}
pub fn[T] Cel::peek(self: Cel[T]) -> T { self.v }
pub fn[T] Cel::get(self: Cel[T]) -> T { self.v }
pub fn[T] Cel::set(self: Cel[T], x: T) -> Unit { self.v = x }
pub fn[T] Cel::mutate(self: Cel[T], f: (T) -> Unit) -> Unit { f(self.v) }

pub struct Scope { mut active: Bool; clrs: ClearHooks }
impl HasClrs for Scope with clrs(self) { self.clrs }
pub fn Scope::new() -> Scope {{ active: true, clrs: [] }}
fn Scope::use() -> Unit {}
pub fn Scope::stop(s: Scope) -> Unit {
  if s.active { s.active = false; clean(s) }
}

pub struct Eff { run: () -> Result[Unit, Error]; scope: Scope; clrs: ClearHooks }
impl HasClrs for Eff with clrs(self) { self.clrs }

pub fn effect(f: () -> Unit raise) -> Result[() -> Unit, Error] {
  let scope = Scope::new()
  let clrs : ClearHooks = []
  let run = () => { if !scope.active { Ok(()) } else { clean({ clrs, }); try? f() } }
  let eff = { run, scope, clrs }
  match run() { Ok(_) => Ok(() => clean(eff)); Err(e) => Err(e) }
}

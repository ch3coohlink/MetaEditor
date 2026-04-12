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

pub trait ToInt { to_int(Self) -> Int }

pub fn[T, U] flat_map(a : Array[T], f : (T) -> Array[U]) -> Array[U] {
  let r = []; for i in a { for value in f(i) { r.push(value) } }; r
}

pub fn[T] assert_fail(msg: String, f: () -> T raise) -> Unit raise {
  try f() catch { _ => () } noraise { _ => fail(msg) }
}

pub type ClearHooks = Array[() -> Unit]
pub trait HasClrs { clrs(Self) -> ClearHooks }
pub fn[T: HasClrs] onclr(t: T, f: () -> Unit) -> Unit { t.clrs().push(f) }
pub fn[T: HasClrs] clean(t: T) -> Unit { let c = t.clrs(); for f in c { f() }; c.clear() }

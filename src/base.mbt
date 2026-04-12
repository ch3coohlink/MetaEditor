pub trait ToInt { to_int(Self) -> Int }
pub fn[T, U] flat_map(a : Array[T], f : (T) -> Array[U]) -> Array[U] {
  let r = []; for i in a { for value in f(i) { r.push(value) } }; r
}

pub type ClearHooks = Array[() -> Unit]
pub trait HasClrs { clrs(Self) -> ClearHooks }
pub fn[T: HasClrs] onclr(t: T, f: () -> Unit) -> Unit { t.clrs().push(f) }
pub fn[T: HasClrs] clean(t: T) -> Unit { let c = t.clrs(); for f in c { f() }; c.clear() }

pub struct Queue[T] { mut items: Array[T] }
pub fn[T] Queue::new() -> Queue[T] {{ items: [] }}
pub fn[T] Queue::push(self: Queue[T], item: T) -> Unit { self.items.push(item) }
pub fn[T] Queue::take(self: Queue[T]) -> Array[T] { let out = self.items; self.items = []; out }
pub fn[T] Queue::clear(self: Queue[T]) -> Unit { self.items.clear() }
pub fn[T] Queue::length(self: Queue[T]) -> Int { self.items.length() }

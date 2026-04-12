pub trait ToInt { to_int(Self) -> Int }
pub fn[T, U] flat_map(items : Array[T], f : (T) -> Array[U]) -> Array[U] {
  let out : Array[U] = []
  for item in items {
    for value in f(item) { out.push(value) }
  }
  out
}

pub type ClearHooks = Array[() -> Unit]
pub fn clean(clrs: ClearHooks) -> Unit { for f in clrs { f() }; clrs.clear() }

pub struct Queue[T] { mut items: Array[T] }
pub fn[T] Queue::new() -> Queue[T] {{ items: [] }}
pub fn[T] Queue::push(self: Queue[T], item: T) -> Unit { self.items.push(item) }
pub fn[T] Queue::take(self: Queue[T]) -> Array[T] { let out = self.items; self.items = []; out }
pub fn[T] Queue::clear(self: Queue[T]) -> Unit { self.items.clear() }
pub fn[T] Queue::length(self: Queue[T]) -> Int { self.items.length() }

struct PostTask { mut active: Bool; run: () -> Unit }
pub struct PostQueue { mut items: Array[Ref[PostTask]] }
pub fn PostQueue::new() -> PostQueue {{ items: [] }}
pub fn PostQueue::add(self: PostQueue, f: () -> Unit) -> (() -> Unit) {
  let entry = Ref::new({ active: true, run: f })
  self.items.push(entry)
  fn() {
    if entry.val.active {
      entry.val.active = false
      self.items = self.items.filter(x => !physical_equal(x, entry))
    }
  }
}
pub fn PostQueue::run(self: PostQueue) -> Unit {
  self.items.each(entry => if entry.val.active { (entry.val.run)() })
}
pub fn PostQueue::clear(self: PostQueue) -> Unit { self.items.clear() }

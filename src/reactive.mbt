let ceff: Ref[Option[Ref[Eff]]] = Ref::new(None)
let cscp: Ref[Option[Ref[Scope]]] = Ref::new(None)
let pending: Ref[Array[Ref[Eff]]] = Ref::new([])

pub fn reset_test_reactive() -> Unit {
  ceff.val = None
  cscp.val = None
  pending.val.clear()
  pool.val.clear()
}

fn clear(e: Ref[Eff]) -> Unit { e.val.clrs.each(f => f()); e.val.clrs.clear() }
let pool : Ref[Array[() -> Unit]] = Ref::new([])
pub fn on_post_flush(f : () -> Unit) -> Unit { pool.val.push(f) }
pub fn flush() -> Unit raise {
  while pending.val.length() > 0 {
    let cur = pending.val; pending.val = []
    cur.each(e => { e.val.queued = false; if e.val.active { (e.val.run)() } })
  }
  pool.val.each(fn(f) { f() })
}

fn queue(e: Ref[Eff]) -> Unit {
  if e.val.active && not(e.val.queued) { e.val.queued = true; pending.val.push(e) }
}
pub fn onclr(f: () -> Unit) -> Unit {
  match ceff.val {
    Some(e) => e.val.clrs.push(f)
    None => match cscp.val { Some(s) => s.val.clrs.push(f); None => () }
  }
}
fn[T] track(sig: Cel[T]) -> Unit {
  match ceff.val {
    Some(e) => {
      sig.subs.val.push(e)
      onclr(() => sig.subs.val = sig.subs.val.filter(x => not(physical_equal(x, e))))
    }
    None => ()
  }
}
pub fn[T] untracked(f: () -> T raise) -> T raise { ceff.protect(None, f) }

pub struct Cel[T] { cell : Ref[T]; subs : Ref[Array[Ref[Eff]]] }
pub fn[T] cel(x : T) -> Cel[T] { { cell: Ref::new(x), subs: Ref::new([]), } }
pub fn[T] Cel::peek(self : Cel[T]) -> T { self.cell.val }
pub fn[T] Cel::get(self : Cel[T]) -> T { track(self); self.cell.val }
pub fn[T] Cel::set(self : Cel[T], x : T) -> Unit { self.cell.val = x; self.subs.val.each(queue) }
pub fn[T] Cel::mutate(self : Cel[T], f : (T) -> Unit) -> Unit {
  f(self.cell.val)
  self.subs.val.each(queue)
}

// 只读派生信号，带缓存。依赖变化时自动重算。
pub fn[T] computed(f: () -> T raise) -> Cel[T] raise {
  let c = cel(f())
  let _ = effect(() => { c.set(f()) })
  c
}

// 监听信号变化，回调接收 (旧值, 新值)
pub fn[T: Eq] watch(source: Cel[T], callback: (T, T) -> Unit raise) -> (() -> Unit) raise {
  let prev: Ref[T] = Ref::new(source.peek())
  effect(() => {
    let cur = source.get()
    let old = prev.val
    if old != cur { prev.val = cur; callback(old, cur) }
  })
}

// 无需 Eq 约束版本，每次依赖触发都执行回调
pub fn[T] watch_raw(source: Cel[T], callback: (T) -> Unit raise) -> (() -> Unit) raise {
  effect(() => { callback(source.get()) })
}

pub struct Eff {
  mut run : () -> Unit raise; clrs : Array[() -> Unit]; mut active : Bool; mut queued : Bool
}
pub fn effect(f : () -> Unit raise) -> (() -> Unit) raise {
  let s = match cscp.val { Some(s) => s; None => abort("effect must be created inside scope") }
  let e = { run: fn () {}, active: true, queued: false, clrs: [], }; let r = Ref::new(e)
  let stop = fn() { if e.active { e.active = false; e.queued = false; clear(r) } }
  s.val.clrs.push(stop)
  e.run = () => {
    if e.active { ceff.protect(Some(r), () => cscp.protect(Some(s), () => { clear(r); f() })) }
  }; (e.run)()
  stop
}

priv struct Scope { mut active : Bool; clrs : Array[() -> Unit] }
pub fn scope(f : () -> Unit raise) -> (() -> Unit) raise {
  let s = Ref::new({ active: true, clrs: [], }); cscp.protect(Some(s), f)
  () => if s.val.active { s.val.active = false; s.val.clrs.each(g => g()); s.val.clrs.clear() }
}

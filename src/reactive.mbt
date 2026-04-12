let ceff: Ref[Option[Ref[Eff]]] = Ref::new(None)
let cscp: Ref[Option[Ref[Scope]]] = Ref::new(None)
let pending: Ref[Array[Ref[Eff]]] = Ref::new([])
let pfi: Ref[Int] = Ref::new(1)

pub fn reset_reactive() -> Unit {
  ceff.val = None
  cscp.val = None
  pending.val.clear()
  pfi.val = 1
  pool.val.clear()
}

fn clear(e: Ref[Eff]) -> Unit {
  e.val.subs.each(subs => {
    subs.val = subs.val.filter(x => !physical_equal(x, e))
  })
  e.val.subs.clear()
  e.val.clrs.each(f => f())
  e.val.clrs.clear()
}
priv struct PostFlush { mut active: Bool; run: () -> Unit }
let pool : Ref[Array[Ref[PostFlush]]] = Ref::new([])
pub fn on_post_flush(f : () -> Unit) -> (() -> Unit) {
  let id = pfi.val
  pfi.val = id + 1
  ignore(id)
  let entry = Ref::new({ active: true, run: f })
  pool.val.push(entry)
  let stop = fn() {
    if entry.val.active {
      entry.val.active = false
      pool.val = pool.val.filter(x => !physical_equal(x, entry))
    }
  }
  onclr(stop)
  stop
}
pub fn flush() -> Unit raise {
  while pending.val.length() > 0 {
    let cur = pending.val; pending.val = []
    cur.each(e => { e.val.queued = false; if e.val.active { (e.val.run)() } })
  }
  pool.val.each(fn(entry) { if entry.val.active { (entry.val.run)() } })
}

pub fn try_flush() -> Unit {
  let _ = try { flush() } catch { e => println("Flush Error: \{e}") }
}

fn queue(e: Ref[Eff]) -> Unit {
  if e.val.active && !e.val.queued { e.val.queued = true; pending.val.push(e) }
}
pub fn onclr(f: () -> Unit) -> Unit {
  match ceff.val {
    Some(e) => e.val.clrs.push(f)
    None => if cscp.val is Some(s) { s.val.clrs.push(f) }
  }
}
fn[T] track(sig: Cel[T]) -> Unit {
  if ceff.val is Some(e) {
    for subs in e.val.subs {
      if physical_equal(subs, sig.subs) { return }
    }
    e.val.subs.push(sig.subs)
    sig.subs.val.push(e)
  }
}
pub fn[T] untracked(f: () -> T raise) -> T raise { ceff.protect(None, f) }

pub struct Cel[T] { cell : Ref[T]; subs : Ref[Array[Ref[Eff]]] }
pub fn[T] cel(x : T) -> Cel[T] { { cell: Ref::new(x), subs: Ref::new([]), } }
pub fn[T] Cel::peek(self : Cel[T]) -> T { self.cell.val }
pub fn[T] Cel::get(self : Cel[T]) -> T { track(self); self.cell.val }
/// 改进：以后可能要有一个比较缓存值是否不相等才触发的版本
fn[T] Cel::notify(self : Cel[T]) -> Unit { self.subs.val.each(queue) }
pub fn[T] Cel::set(self : Cel[T], x : T) -> Unit { self.cell.val = x; self.notify() }
pub fn[T] Cel::mutate(self : Cel[T], f : (T) -> Unit) -> Unit {
  f(self.cell.val); self.notify()
}

pub struct Eff {
  mut run : () -> Unit raise // raise? 不支持
  clrs : Array[() -> Unit]
  subs : Array[Ref[Array[Ref[Eff]]]]
  mut active : Bool
  mut queued : Bool
}
pub fn effect(f: () -> Unit raise) -> (() -> Unit) raise {
  let s = match cscp.val { Some(s) => s; None => abort("effect must be created inside scope") }
  let e = { run: fn () {}, active: true, queued: false, clrs: [], subs: [], }; let r = Ref::new(e)
  let stop = fn() { if e.active { e.active = false; e.queued = false; clear(r) } }
  s.val.clrs.push(stop)
  e.run = () => {
    if e.active { ceff.protect(Some(r), () => cscp.protect(Some(s), () => { clear(r); f() })) }
  }; (e.run)()
  stop
}

struct Scope { mut active : Bool; clrs : ClearHooks }
fn Scope::new() -> Scope {{ active: true, clrs: [], }}
fn Scope::use() -> Unit {}
fn Scope::stop(s: Scope) -> Unit { if s.active { s.active = false; clean(s.clrs) } }
fn clean(clrs: ClearHooks) -> Unit { for f in clrs { f() }; clrs.clear() }
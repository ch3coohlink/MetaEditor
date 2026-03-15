let ceff: Ref[Option[Ref[Eff]]] = Ref::new(None)
let cscp: Ref[Option[Ref[Scope]]] = Ref::new(None)
let pending: Ref[Array[Ref[Eff]]] = Ref::new([])

fn clear(e: Ref[Eff]) -> Unit { e.val.clrs.each(f => f()); e.val.clrs.clear() }
let post_flush_hooks : Ref[Array[() -> Unit]] = Ref::new([])
pub fn on_post_flush(f : () -> Unit) -> Unit { post_flush_hooks.val.push(f) }

pub fn flush() -> Unit raise {
  while pending.val.length() > 0 {
    let cur = pending.val; pending.val = []
    cur.each(e => { e.val.queued = false; if e.val.active { (e.val.run)() } })
  }
  post_flush_hooks.val.each(fn(f) { f() })
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
pub fn[T] Cel::update(self : Cel[T], f : (T) -> T) -> Unit { self.set(f(self.cell.val)) }


pub struct Eff {
  mut run : () -> Unit raise; clrs : Array[() -> Unit]; mut active : Bool; mut queued : Bool
}
pub fn effect(f : () -> Unit raise) -> Unit raise {
  let s = match cscp.val { Some(s) => s; None => abort("effect must be created inside scope") }
  let e = { run: fn () {}, active: true, queued: false, clrs: [], }; let r = Ref::new(e)
  s.val.clrs.push(() => if e.active { e.active = false; e.queued = false; clear(r) })
  e.run = () => {
    if e.active { ceff.protect(Some(r), () => cscp.protect(Some(s), () => { clear(r); f() })) }
  }; (e.run)()
}

priv struct Scope { mut active : Bool; clrs : Array[() -> Unit] }
pub fn scope(f : () -> Unit raise) -> (() -> Unit) raise {
  let s = Ref::new({ active: true, clrs: [], }); cscp.protect(Some(s), f)
  () => if s.val.active { s.val.active = false; s.val.clrs.each(g => g()); s.val.clrs.clear() }
}


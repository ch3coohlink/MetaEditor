let ceff: Ref[Option[Ref[Eff]]] = Ref::new(None)
let cscp: Ref[Option[Ref[Scope]]] = Ref::new(None)
let pending: Ref[Array[Ref[Eff]]] = Ref::new([])

fn clear(e: Ref[Eff]) -> Unit {
  e.val.clrs.each(f => f())
  e.val.clrs.clear()
}
pub fn flush() -> Unit raise {
  while pending.val.length() > 0 {
    let cur = pending.val
    pending.val = []
    cur.each(e => {
      e.val.queued = false
      if e.val.active { (e.val.run)() }
    })
  }
}
fn queue(e: Ref[Eff]) -> Unit {
  if not(e.val.active) || e.val.queued { return }
  e.val.queued = true
  pending.val.push(e)
}
pub fn onclr(f: () -> Unit) -> Unit {
  match ceff.val {
    Some(e) => e.val.clrs.push(f)
    None => match cscp.val {
      Some(s) => s.val.clrs.push(f)
      None => ()
    }
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
pub fn[T] untracked(f: () -> T raise) -> T raise {
  let prev = ceff.val; ceff.val = None
  try f() catch { e => { ceff.val = prev; raise e } } noraise { r => { ceff.val = prev; r } }
}

pub struct Cel[T] { cell: Ref[T]; subs: Ref[Array[Ref[Eff]]] }
pub fn[T] cel(x: T) -> Cel[T] { { cell: Ref::new(x), subs: Ref::new([]) } }
pub fn[T] Cel::peek(s: Cel[T]) -> T { s.cell.val }
pub fn[T] Cel::get(s: Cel[T]) -> T { track(s); s.cell.val }
pub fn[T] Cel::set(s: Cel[T], x: T) -> Unit { s.cell.val = x; s.subs.val.each(queue) }
pub fn[T] Cel::update(s: Cel[T], f: (T) -> T) -> Unit { s.set(f(s.cell.val)) }

pub struct Eff {
  mut run: () -> Unit raise
  mut active: Bool; mut queued: Bool; clrs: Array[() -> Unit]
}
fn Eff::new() -> Eff {{
  run: fn () {}, active: true, queued: false, clrs: []
}}
pub fn effect(f: () -> Unit raise) -> Unit raise {
  let s = match cscp.val {
    Some(s) => s
    None => abort("effect must be created inside scope")
  }
  let e = Ref::new(Eff::new())
  e.val.run = fn() -> Unit raise {
    if not(e.val.active) { return }
    let pe = ceff.val
    let ps = cscp.val
    ceff.val = Some(e); cscp.val = Some(s)
    clear(e)
    try f() catch { e => { ceff.val = pe; cscp.val = ps; raise e } }
    noraise { _ => { ceff.val = pe; cscp.val = ps } }
  }
n  s.val.clrs.push(() => {
    if not(e.val.active) { return }
    e.val.active = false; e.val.queued = false; clear(e)
  })
  (e.val.run)()
}

priv struct Scope { mut active: Bool; clrs: Array[() -> Unit] }
fn Scope::new() -> Scope {{ active: true, clrs: [] }}
pub fn scope(f: () -> Unit raise) -> (() -> Unit) raise {
  let s = Ref::new(Scope::new())
  let ps = cscp.val
  cscp.val = Some(s)
  try f() catch { err => { cscp.val = ps; raise err } } noraise { _ => cscp.val = ps }
  () => {
    if not(s.val.active) { return }
    s.val.active = false
    s.val.clrs.each(g => g())
    s.val.clrs.clear()
  }
}

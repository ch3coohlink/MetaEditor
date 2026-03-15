let eid: Ref[Int] = Ref::new(0)
let eff: Ref[Option[Ref[Eff]]] = Ref::new(None)
let scp: Ref[Option[Ref[Scope]]] = Ref::new(None)
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
  match eff.val {
    Some(e) => e.val.clrs.push(f)
    None => match scp.val {
      Some(s) => s.val.clrs.push(f)
      None => ()
    }
  }
}
fn[T] track(sig: Cel[T]) -> Unit {
  match eff.val {
    Some(e) => {
      sig.subs.val.push(e)
      let id = e.val.id
      onclr(() => sig.subs.val = sig.subs.val.filter(x => x.val.id != id))
    }
    None => ()
  }
}
pub fn[T] untracked(f: () -> T raise) -> T raise {
  let prev = eff.val; eff.val = None
  try f() catch { err => { eff.val = prev; raise err } } noraise { r => { eff.val = prev; r } }
}

pub struct Cel[T] { cell: Ref[T]; subs: Ref[Array[Ref[Eff]]] }
pub fn[T] cel(x: T) -> Cel[T] { { cell: Ref::new(x), subs: Ref::new([]) } }
pub fn[T] Cel::peek(self: Cel[T]) -> T { self.cell.val }
pub fn[T] Cel::get(self: Cel[T]) -> T { track(self); self.cell.val }
pub fn[T] Cel::set(self: Cel[T], x: T) -> Unit {
  self.cell.val = x
  self.subs.val.each(queue)
}
pub fn[T] Cel::update(self: Cel[T], f: (T) -> T) -> Unit { self.set(f(self.cell.val)) }

pub struct Eff {
  id: Int; mut run: () -> Unit raise
  mut active: Bool; mut queued: Bool; clrs: Array[() -> Unit]
}
fn Eff::new(id: Int) -> Eff {{
  id, run: fn () {}, active: true, queued: false, clrs: []
}}
pub fn effect(f: () -> Unit raise) -> Unit raise {
  let s = match scp.val {
    Some(s) => s
    None => abort("effect must be created inside scope")
  }
  let id = eid.val
  eid.val = id + 1
  let e = Ref::new(Eff::new(id))
  e.val.run = fn() -> Unit raise {
    if not(e.val.active) { return }
    let pe = eff.val
    let ps = scp.val
    eff.val = Some(e); scp.val = Some(s)
    clear(e)
    try f() catch { err => { eff.val = pe; scp.val = ps; raise err } }
    noraise { _ => { eff.val = pe; scp.val = ps } }
  }
  s.val.clrs.push(() => {
    if not(e.val.active) { return }
    e.val.active = false; e.val.queued = false; clear(e)
  })
  (e.val.run)()
}

priv struct Scope { mut active: Bool; clrs: Array[() -> Unit] }
fn Scope::new() -> Scope {{ active: true, clrs: [] }}
pub fn scope(f: () -> Unit raise) -> (() -> Unit) raise {
  let s = Ref::new(Scope::new())
  let ps = scp.val
  scp.val = Some(s)
  try f() catch { err => { scp.val = ps; raise err } } noraise { _ => scp.val = ps }
  () => {
    if not(s.val.active) { return }
    s.val.active = false
    s.val.clrs.each(g => g())
    s.val.clrs.clear()
  }
}

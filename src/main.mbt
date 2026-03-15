let next_signal_id: Ref[Int] = Ref::new(0)
let current_effect_id: Ref[Int] = Ref::new(-1)
let tracking_enabled: Ref[Bool] = Ref::new(true)
let batch_depth: Ref[Int] = Ref::new(0)
let pending_effects: Ref[Array[Int]] = Ref::new([])
let effects: Array[EffectState] = []

fn contains_int(items: Array[Int], target: Int) -> Bool {
  for item in items { if item == target { return true } }
  false
}
fn remove_int(items: Array[Int], target: Int) -> Array[Int] {
  let next: Array[Int] = []
  for item in items { if item != target { next.push(item) } }
  next
}
fn clear_effect_state(effect_id: Int) -> Unit {
  effects[effect_id].deps = []
  for cleanup in effects[effect_id].cleanups { cleanup() }
  effects[effect_id].cleanups = []
}
fn flush_pending() -> Unit {
  while pending_effects.val.length() > 0 {
    let current = pending_effects.val
    pending_effects.val = []
    for effect_id in current {
      effects[effect_id].queued = false
      if effects[effect_id].active { (effects[effect_id].run)() }
    }
  }
}
fn enqueue_effect(effect_id: Int) -> Unit {
  if not(effects[effect_id].active) { return }
  if effects[effect_id].queued { return }
  effects[effect_id].queued = true
  pending_effects.val.push(effect_id)
  if batch_depth.val == 0 { flush_pending() }
}
fn[T] track_signal(sig: Signal[T]) -> Unit {
  if not(tracking_enabled.val) { return }
  let effect_id = current_effect_id.val
  if effect_id < 0 { return }
  if contains_int(effects[effect_id].deps, sig.id) { return }
  effects[effect_id].deps.push(sig.id)
  sig.subscribers.val.push(effect_id)
  effects[effect_id].cleanups.push(fn() {
    sig.subscribers.val = remove_int(sig.subscribers.val, effect_id)
  })
}

pub struct Signal[T] { id: Int; cell: Ref[T]; subscribers: Ref[Array[Int]] }
pub fn[T] signal(initial: T) -> Signal[T] {
  let id = next_signal_id.val
  next_signal_id.val = id + 1
  { id, cell: Ref::new(initial), subscribers: Ref::new([]) }
}
pub fn[T] Signal::peek(self: Signal[T]) -> T { self.cell.val }
pub fn[T] Signal::get(self: Signal[T]) -> T { track_signal(self); self.cell.val }
pub fn[T] Signal::set(self: Signal[T], next: T) -> Unit {
  self.cell.val = next
  for effect_id in self.subscribers.val { enqueue_effect(effect_id) }
}
pub fn[T] Signal::update(self: Signal[T], f: (T) -> T) -> Unit {
  self.set(f(self.cell.val))
}

pub fn onclr(f: () -> Unit) -> Unit {
  let effect_id = current_effect_id.val
  if effect_id >= 0 { effects[effect_id].cleanups.push(f) }
}
pub fn[T] untracked(f: () -> T) -> T {
  let prev = tracking_enabled.val
  tracking_enabled.val = false
  let result = f()
  tracking_enabled.val = prev
  result
}
pub fn[T] batch(f: () -> T) -> T {
  batch_depth.val = batch_depth.val + 1
  let result = f()
  batch_depth.val = batch_depth.val - 1
  if batch_depth.val == 0 { flush_pending() }
  result
}

priv struct EffectState {
  run: () -> Unit; mut active: Bool; mut queued: Bool
  mut deps: Array[Int]; mut cleanups: Array[() -> Unit]
}
fn EffectState::new(run: () -> Unit) -> EffectState {
  { run, active: true, queued: false, deps: [], cleanups: [] }
}
pub fn effect(f: () -> Unit) -> () -> Unit {
  let effect_id = effects.length()
  fn run() {
    if not(effects[effect_id].active) { return }
    clear_effect_state(effect_id)
    let prev_effect = current_effect_id.val
    let prev_tracking = tracking_enabled.val
    current_effect_id.val = effect_id
    tracking_enabled.val = true
    f()
    current_effect_id.val = prev_effect
    tracking_enabled.val = prev_tracking
  }
  fn dispose() {
    if not(effects[effect_id].active) { return }
    effects[effect_id].active = false
    effects[effect_id].queued = false
    clear_effect_state(effect_id)
  }
  effects.push(EffectState::new(run))
  run()
  dispose
}

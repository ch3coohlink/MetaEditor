let nid: Ref[Int] = Ref::new(1)
let ns_html = "http://www.w3.org/1999/xhtml"
let ns_svg = "http://www.w3.org/2000/svg"
let ns_math = "http://www.w3.org/1998/Math/MathML"
pub(all) enum DomCmd {
  Create(Int, String, String)
  Text(Int, String)
  Attr(Int, String, String)
  Append(Int, Int)
  UpdateText(Int, String)
  UpdateAttr(Int, String, String)
  Remove(Int)
  Listen(Int, String, String)
  Action(String, String)
  InsertBefore(Int, Int, Int)
  SetStyle(Int, String, String)    // 设置单个 style 属性
  RemoveStyle(Int, String)         // 移除单个 style 属性
  RemoveAttr(Int, String)          // 移除属性
  HostCmd(Int, String)             // 宿主命令(focus/blur/scrollIntoView)
}
fn[T: ToJson] jarr(items: T) -> String { items.to_json().stringify() }
pub fn DomCmd::to_json(self: DomCmd) -> String {
  match self {
    Create(id, tag, ns) => jarr((0, id, tag, ns))
    Text(id, text) => jarr((1, id, text))
    Attr(id, k, v) => jarr((2, id, k, v))
    Append(pid, cid) => jarr((3, pid, cid))
    UpdateText(id, text) => jarr((4, id, text))
    UpdateAttr(id, k, v) => jarr((5, id, k, v))
    Remove(id) => jarr((6, id))
    Listen(id, ev, ui_id) => jarr((7, id, ev, ui_id))
    Action(name, ui_id) => jarr((8, name, ui_id))
    InsertBefore(pid, cid, rid) => jarr((9, pid, cid, rid))
    SetStyle(id, k, v) => jarr((10, id, k, v))
    RemoveStyle(id, k) => jarr((11, id, k))
    RemoveAttr(id, k) => jarr((12, id, k))
    HostCmd(id, cmd) => jarr((13, id, cmd))
  }
}
pub(all) enum Child {
  Null
  Lazy((String) -> VNode)
  Str(String)
  Int(Int)
  Arr(Array[Child])
  Dyn(() -> Child)
}
pub struct DomState {
  next: Ref[Int]
  cmds: Array[DomCmd]
}
pub(all) struct VNode {
  id: Int
  ui_id: String?
  listener_keys: Array[String]
  action_names: Array[String]
  clrs: Array[() -> Unit]
  children: Array[VNode]
}
pub(all) enum Prop { S(String); D(() -> String); E(() -> Unit raise); EK((EventData) -> Unit raise); ActionRef(String) }

// 键盘/输入事件数据，由 bridge 回传
pub(all) struct EventData {
  key: String          // 按键名（如 "a", "Enter", "ArrowUp"）
  code: String         // 物理键码（如 "KeyA", "Enter"）
  ctrl: Bool           // Ctrl 键
  shift: Bool          // Shift 键
  alt: Bool            // Alt 键
  meta: Bool           // Meta 键（Cmd/Win）
  prevent: Bool        // 是否已 preventDefault
}
pub fn EventData::default() -> EventData {
  { key: "", code: "", ctrl: false, shift: false, alt: false, meta: false, prevent: false }
}
pub fn EventData::from_json(s: String) -> EventData {
  // 简易解析: "key|code|ctrl|shift|alt|meta"
  let parts = s.split("|").collect().map(fn(sv) { sv.to_string() })
  let get = fn(i: Int) -> String { if i < parts.length() { parts[i] } else { "" } }
  let b = fn(s: String) -> Bool { s == "1" }
  { key: get(0), code: get(1), ctrl: b(get(2)), shift: b(get(3)), alt: b(get(4)), meta: b(get(5)), prevent: false }
}

fn realize_current(c: Child) -> VNode {
  match c {
    Lazy(f) => f(ns_html)
    _ => abort("not a child")
  }
}

pub fn realize(state: DomState, c: Child) -> VNode {
  use_dom_state_inner(state, fn() { realize_current(c) })
}

priv enum EventHandler {
  Plain(() -> Unit raise)
  WithData((EventData) -> Unit raise)
}

priv struct EventSlot {
  owner_id: Int
  handler: EventHandler
}

fn listener_key(ui_id: String, event: String) -> String {
  "\{ui_id}\n\{event}"
}

fn find_static_ui_id(attrs: Array[(String, Prop)]) -> String? {
  for pair in attrs {
    let (key, value) = pair
    if key == "ui-id" {
      match value {
        S(raw) => return Some(raw)
        _ => abort("ui-id must be static")
      }
    }
  }
  None
}

let event_handlers: Map[String, EventSlot] = Map::new()
let action_handlers: Map[String, () -> Unit raise] = Map::new()
let action_targets: Map[String, String] = Map::new()
let ui_nodes: Map[String, Int] = Map::new()

pub fn reg_action(name: String, f: () -> Unit raise) -> Prop {
  action_handlers.set(name, f)
  ActionRef(name)
}

let cq: Array[DomCmd] = []
let current_dom_state: Ref[Option[DomState]] = Ref::new(None)

fn active_dom_state() -> DomState {
  match current_dom_state.val {
    Some(state) => state
    None => { next: nid, cmds: cq }
  }
}

fn next_active_id() -> Int {
  let state = active_dom_state()
  let id = state.next.val
  state.next.val = id + 1
  id
}

pub fn new_dom_state() -> DomState {{ next: Ref::new(1), cmds: [] }}

fn[T] use_dom_state_inner(state: DomState, f: () -> T) -> T {
  let prev = current_dom_state.val
  current_dom_state.val = Some(state)
  let out = f()
  current_dom_state.val = prev
  out
}

fn[T] use_dom_state_raise(state: DomState, f: () -> T raise) -> T raise {
  let prev = current_dom_state.val
  current_dom_state.val = Some(state)
  let out = try {
    f()
  } catch {
    e => {
      current_dom_state.val = prev
      raise e
    }
  }
  current_dom_state.val = prev
  out
}

fn emit_current(c: DomCmd) -> Unit { active_dom_state().cmds.push(c) }
pub fn emit(state: DomState, c: DomCmd) -> Unit { state.cmds.push(c) }
pub fn get_cmds(state: DomState) -> Array[DomCmd] {
  let r = state.cmds.copy()
  state.cmds.clear()
  r
}
pub fn reset_test_ui() -> Unit {
  nid.val = 1
  cq.clear()
  event_handlers.clear()
  action_handlers.clear()
  action_targets.clear()
  ui_nodes.clear()
  reset_test_reactive()
}

fn trigger_event(key: String, ev: EventData) -> Unit {
  match event_handlers.get(key) {
    Some({ handler: Plain(f), .. }) => {
      let _ = f() catch { e => println("Event Error (\{key}): \{e}") }
      let _ = flush() catch { e => println("Flush Error: \{e}") }
    }
    Some({ handler: WithData(f), .. }) => {
      let _ = f(ev) catch { e => println("Event Error (\{key}): \{e}") }
      let _ = flush() catch { e => println("Flush Error: \{e}") }
    }
    None => ()
  }
}

pub fn trigger_ui(ui_id: String, event: String) -> Unit {
  trigger_event(listener_key(ui_id, event), EventData::default())
}

pub fn trigger_ui_ev(ui_id: String, event: String, ev: EventData) -> Unit {
  trigger_event(listener_key(ui_id, event), ev)
}

pub fn click(ui_id: String) -> Unit {
  trigger_ui(ui_id, "onclick")
}

pub fn trigger_action(name: String) -> Unit {
  match action_targets.get(name) {
    Some(ui_id) => click(ui_id)
    None =>
      match action_handlers.get(name) {
        Some(f) => {
          let _ = f() catch { e => println("Action Error (\{name}): \{e}") }
          let _ = flush() catch { e => println("Flush Error: \{e}") }
        }
        None => ()
      }
  }
}
fn create_text_node(v: String) -> VNode { 
  let id = next_active_id(); emit_current(Create(id, "", "")); emit_current(Text(id, v))
  { id, ui_id: None, listener_keys: [], action_names: [], clrs: [], children: [] } 
}

fn freeze_child(c: Child) -> Child {
  match c {
    Null => Null
    Lazy(f) => {
      let cached: Ref[Option[VNode]] = Ref::new(None)
      Lazy(fn(ns: String) -> VNode {
        match cached.val {
          Some(node) => node
          None => {
            let node = f(ns)
            cached.val = Some(node)
            node
          }
        }
      })
    }
    Str(s) => {
      let cached: Ref[Option[VNode]] = Ref::new(None)
      Lazy(fn(_ns: String) -> VNode {
        match cached.val {
          Some(node) => node
          None => {
            let node = create_text_node(s)
            cached.val = Some(node)
            node
          }
        }
      })
    }
    Int(i) => freeze_child(Str(i.to_string()))
    Arr(a) => Arr(a.map(freeze_child))
    Dyn(f) => Dyn(fn() { freeze_child(f()) })
  }
}

fn contains_node(nodes: Array[VNode], id: Int) -> Bool {
  for node in nodes {
    if node.id == id { return true }
  }
  false
}
fn children(id: Int, c_in: Child, target_array: Array[VNode], ns: String, anchor_opt: Option[Int]) -> Unit {
  match c_in {
    Null => ()
    Lazy(f) => {
      let n = f(ns)
      match anchor_opt {
        Some(ref_id) => emit_current(InsertBefore(id, n.id, ref_id))
        None => emit_current(Append(id, n.id))
      }
      target_array.push(n)
    }
    Str(s) => {
      let n = create_text_node(s)
      match anchor_opt {
        Some(ref_id) => emit_current(InsertBefore(id, n.id, ref_id))
        None => emit_current(Append(id, n.id))
      }
      target_array.push(n)
    }
    Int(i) => children(id, Str(i.to_string()), target_array, ns, anchor_opt)
    Arr(a) => {
      for child in a { children(id, child, target_array, ns, anchor_opt) }
    }
    Dyn(f) => {
      let dom_state = active_dom_state()
      let anchor = create_text_node("")
      match anchor_opt {
        Some(ref_id) => emit_current(InsertBefore(id, anchor.id, ref_id))
        None => emit_current(Append(id, anchor.id))
      }
      target_array.push(anchor)
      
      let old_nodes: Ref[Array[VNode]] = Ref::new([])
      
      let stop_effect = effect(fn() {
        use_dom_state_inner(dom_state, fn() {
          let new_child = f()
          let new_vnodes = []
          children(id, new_child, new_vnodes, ns, Some(anchor.id))
          for old in old_nodes.val {
            if !contains_node(new_vnodes, old.id) {
              emit_current(Remove(old.id))
              recursive_cleanup(old)
            }
          }
          old_nodes.val = new_vnodes
        })
      }) catch { _ => fn() {} }
      
      anchor.clrs.push(fn() { 
        ignore(use_dom_state_inner(dom_state, fn() {
          let _ = stop_effect()
          for old in old_nodes.val {
            emit_current(Remove(old.id))
            recursive_cleanup(old)
          }
        }))
      })
    }
  }
}

pub(open) trait HTag {
  render(Self, Array[(String, Prop)], Array[Child]) -> Child
}

fn render_element(tag: String, attrs: Array[(String, Prop)], children_prop: Array[Child]) -> Child {
  Lazy(fn(ns: String) -> VNode {
    let dom_state = active_dom_state()
    let cur_ns = if ns == "" { ns_html } else { ns }
    let create_ns = if tag == "svg" { ns_svg } else if tag == "math" { ns_math } else { cur_ns }
    let child_ns = if tag == "foreignObject" { ns_html } else if tag == "svg" { ns_svg } else if tag == "math" { ns_math } else { cur_ns }
    let id = next_active_id(); emit_current(Create(id, tag, create_ns))
    let ui_id = find_static_ui_id(attrs)
    let listener_keys: Array[String] = []
    let action_names: Array[String] = []
    let my_clrs: Array[() -> Unit] = []
    match ui_id {
      Some(value) => ui_nodes.set(value, id)
      None => ()
    }
    attrs.each(fn(p) {
      let (k, v) = p
      match v {
        S(s) => emit_current(Attr(id, k, s))
        D(f) => {
          if k == "ui-id" { abort("ui-id must be static") }
          let stop = effect(fn() {
            use_dom_state_inner(dom_state, fn() { emit_current(UpdateAttr(id, k, f())) })
          }) catch { _ => fn() {} }
          my_clrs.push(stop)
        }
        E(f) => {
          let uid = match ui_id {
            Some(value) => value
            None => abort("interactive node requires ui-id")
          }
          let key = listener_key(uid, k)
          event_handlers.set(key, {
            owner_id: id,
            handler: Plain(fn() raise {
              ignore(use_dom_state_raise(dom_state, fn() raise { f() }))
            })
          })
          listener_keys.push(key)
          emit_current(Listen(id, k, uid))
        }
        EK(f) => {
          let uid = match ui_id {
            Some(value) => value
            None => abort("interactive node requires ui-id")
          }
          let key = listener_key(uid, k)
          event_handlers.set(key, {
            owner_id: id,
            handler: WithData(fn(ev) raise {
              ignore(use_dom_state_raise(dom_state, fn() raise { f(ev) }))
            })
          })
          listener_keys.push(key)
          emit_current(Listen(id, k, uid))
        }
        ActionRef(name) => {
          let uid = match ui_id {
            Some(value) => value
            None => abort("interactive node requires ui-id")
          }
          let action = match action_handlers.get(name) {
            Some(handler) => handler
            None => abort("action not found: \{name}")
          }
          let key = listener_key(uid, k)
          event_handlers.set(key, {
            owner_id: id,
            handler: Plain(fn() raise {
              ignore(use_dom_state_raise(dom_state, fn() raise { action() }))
            })
          })
          listener_keys.push(key)
          action_names.push(name)
          action_targets.set(name, uid)
          emit_current(Action(name, uid))
          emit_current(Listen(id, k, uid))
        }
      }
    })
    let current_children: Array[VNode] = []
    for c in children_prop { children(id, c, current_children, child_ns, None) }
    { id, ui_id, listener_keys, action_names, clrs: my_clrs, children: current_children }
  })
}

pub impl HTag for String with render(self, attrs, children_prop) {
  render_element(self, attrs, children_prop)
}

pub struct Comp {
  priv render : (Array[(String, Prop)], Array[Child]) -> Child
}

pub fn comp(f: (Array[(String, Prop)], Array[Child]) -> Child) -> Comp { { render: f } }
fn scoped_attrs(attrs: Array[(String, Prop)], name: String?) -> Array[(String, Prop)] {
  if name is Some(value) && find_static_ui_id(attrs) is None {
    let out = attrs.copy()
    out.push(("ui-id", S(value)))
    return out
  }
  attrs
}
fn attach_scope_stop(node: VNode, stop: () -> Unit, attach: Bool) -> VNode {
  if attach { node.clrs.push(stop) }
  node
}
fn wrap_scoped_child(child: Child, handle: ScopeHandle, attach_stop: Bool) -> Child {
  let stop = fn() { stop_scope(handle) }
  match child {
    Null => Lazy(fn(_ns: String) -> VNode { attach_scope_stop(create_text_node(""), stop, attach_stop) })
    Lazy(f) => Lazy(fn(ns: String) -> VNode {
      attach_scope_stop(
        with_scope(handle, fn() { f(ns) }) catch { _ => panic() },
        stop,
        attach_stop,
      )
    })
    Str(s) => Lazy(fn(_ns: String) -> VNode { attach_scope_stop(create_text_node(s), stop, attach_stop) })
    Int(i) => wrap_scoped_child(Str(i.to_string()), handle, attach_stop)
    Arr(items) => {
      if items.length() == 0 { return wrap_scoped_child(Null, handle, attach_stop) }
      let out: Array[Child] = []
      let mut first = attach_stop
      for item in items {
        out.push(wrap_scoped_child(item, handle, first))
        first = false
      }
      Arr(out)
    }
    Dyn(f) =>
      if attach_stop {
        Arr([
          Lazy(fn(_ns: String) -> VNode {
            attach_scope_stop(create_text_node(""), stop, true)
          }),
          Dyn(fn() {
            with_scope(handle, fn() { wrap_scoped_child(f(), handle, false) }) catch { _ => panic() }
          })
        ])
      } else {
        Dyn(fn() {
          with_scope(handle, fn() { wrap_scoped_child(f(), handle, false) }) catch { _ => panic() }
        })
      }
  }
}
pub fn scoped(inner: Comp, name? : String? = None, reactive? : Bool = false) -> Comp {
  comp(fn(attrs, children_prop) {
    let next_attrs = scoped_attrs(attrs, name)
    if !reactive { return (inner.render)(next_attrs, children_prop) }
    let handle = new_scope()
    let child = with_scope(handle, fn() { (inner.render)(next_attrs, children_prop) }) catch { _ => panic() }
    wrap_scoped_child(child, handle, true)
  })
}

pub impl HTag for Comp with render(self, attrs, children_prop) {
  (self.render)(attrs, children_prop)
}

pub fn[T: HTag] h(tag: T, attrs: Array[(String, Prop)], children_prop: Array[Child]) -> Child {
  tag.render(attrs, children_prop)
}

priv struct HMapEntry {
  child : Child
  idx : Ref[Int]
}

pub fn[T: Eq + Hash] h_map(items: Array[T], f: (T, () -> Int) -> Child) -> Child {
  h_map_dyn(fn() {
    let out: Array[(T, Int)] = []
    let i: Ref[Int] = Ref::new(0)
    for x in items {
      let n = i.val
      i.val = n + 1
      out.push((x, n))
    }
    out
  }, f)
}

pub fn[T: Eq + Hash] h_map_dyn(items: () -> Array[(T, Int)], f: (T, () -> Int) -> Child) -> Child {
  let cache: Ref[Map[T, Array[HMapEntry]]] = Ref::new(Map::new())
  Dyn(fn() {
    let xs = items()
    let prev = cache.val
    let next: Map[T, Array[HMapEntry]] = Map::new()
    let current: Array[Child] = []
    let used: Map[T, Int] = Map::new()
    for pair in xs {
      let (x, n) = pair
      let pos = match used.get(x) { Some(k) => k; None => 0 }
      match prev.get(x) {
        Some(entries) => {
          if pos < entries.length() {
            let entry = entries[pos]
            entry.idx.val = n
            match next.get(x) {
              Some(vs) => vs.push(entry)
              None => next.set(x, [entry])
            }
            used.set(x, pos + 1)
            current.push(entry.child)
          } else {
            let idx = Ref::new(n)
            let child = freeze_child(f(x, fn() { idx.val }))
            let entry = { child, idx }
            match next.get(x) {
              Some(vs) => vs.push(entry)
              None => next.set(x, [entry])
            }
            used.set(x, pos + 1)
            current.push(child)
          }
        }
        None => {
          let idx = Ref::new(n)
          let child = freeze_child(f(x, fn() { idx.val }))
          let entry = { child, idx }
          match next.get(x) {
            Some(vs) => vs.push(entry)
            None => next.set(x, [entry])
          }
          used.set(x, pos + 1)
          current.push(child)
        }
      }
    }
    cache.val = next
    Arr(current)
  })
}

fn recursive_cleanup(node: VNode) -> Unit {
  node.listener_keys.each(fn(key) {
    match event_handlers.get(key) {
      Some(slot) => if slot.owner_id == node.id { event_handlers.remove(key) }
      None => ()
    }
  })
  node.action_names.each(fn(name) {
    match action_targets.get(name) {
      Some(ui_id) =>
        match node.ui_id {
          Some(current) => if ui_id == current { action_targets.remove(name) }
          None => ()
        }
      None => ()
    }
  })
  match node.ui_id {
    Some(value) =>
      match ui_nodes.get(value) {
        Some(current_id) => if current_id == node.id { ui_nodes.remove(value) }
        None => ()
      }
    None => ()
  }
  node.clrs.each(fn(f) { f() })
  node.children.each(recursive_cleanup)
}

// 宿主命令辅助函数
pub fn focus_node(id: Int) -> Unit { emit_current(HostCmd(id, "focus")) }
pub fn blur_node(id: Int) -> Unit { emit_current(HostCmd(id, "blur")) }
pub fn scroll_into_view(id: Int) -> Unit { emit_current(HostCmd(id, "scrollIntoView")) }
pub fn remove(node: VNode) -> Unit { 
  emit_current(Remove(node.id))
  recursive_cleanup(node)
}
pub fn init_bridge(state: DomState, sender: (Array[String]) -> Unit) -> Unit {
  let _ = on_post_flush(fn() { 
    let cs = get_cmds(state)
    if cs.length() > 0 { sender(cs.map(fn(c) { c.to_json() }))  } 
  })
}

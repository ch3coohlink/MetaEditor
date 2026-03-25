let nid: Ref[Int] = Ref::new(1)
fn next_id() -> Int { let id = nid.val; nid.val = id + 1; id }
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
  Listen(Int, String, Int)
  Action(String, Int)
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
    Listen(id, ev, cb) => jarr((7, id, ev, cb))
    Action(name, cb) => jarr((8, name, cb))
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
pub(all) struct VNode { id: Int; cb_ids: Array[Int]; clrs: Array[() -> Unit]; children: Array[VNode] }
pub(all) enum Prop { S(String); D(() -> String); E(() -> Unit raise); EK((EventData) -> Unit raise); ActionRef(Int) }

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

pub fn realize(c: Child) -> VNode {
  match c {
    Lazy(f) => f(ns_html)
    _ => abort("not a child")
  }
}

pub fn reg_action(name: String, f: () -> Unit raise) -> Prop {
  let i = ci.val; ci.val = i + 1; cbs.set(i, f)
  emit(Action(name, i))
  ActionRef(i)
}

let cq: Array[DomCmd] = []
pub fn emit(c: DomCmd) -> Unit { cq.push(c) }
pub fn get_cmds() -> Array[DomCmd] { let r = cq.copy(); cq.clear(); r }
let cbs: Map[Int, () -> Unit raise] = Map::new()
let cbs_ev: Map[Int, (EventData) -> Unit raise] = Map::new()
let ci: Ref[Int] = Ref::new(1)
pub fn reset_test_ui() -> Unit {
  nid.val = 1
  cq.clear()
  cbs.clear()
  cbs_ev.clear()
  ci.val = 1
  reset_test_reactive()
}
pub fn trigger_callback(id: Int) -> Unit {
  match cbs.get(id) {
    Some(f) => {
      let _ = f() catch { e => println("Callback Error (ID \{id}): \{e}") }
      let _ = flush() catch { e => println("Flush Error: \{e}") }
    }
    None => match cbs_ev.get(id) {
      Some(_) => trigger_callback_ev(id, EventData::default())
      None => ()
    }
  }
}
// 带事件数据的回调触发
pub fn trigger_callback_ev(id: Int, ev: EventData) -> Unit {
  match cbs_ev.get(id) {
    Some(f) => {
      let _ = f(ev) catch { e => println("Callback Error (ID \{id}): \{e}") }
      let _ = flush() catch { e => println("Flush Error: \{e}") }
    }
    None => ()
  }
}
fn create_text_node(v: String) -> VNode { 
  let id = next_id(); emit(Create(id, "", "")); emit(Text(id, v))
  { id, cb_ids: [], clrs: [], children: [] } 
}
fn children(id: Int, c_in: Child, target_array: Array[VNode], ns: String, anchor_opt: Option[Int]) -> Unit {
  match c_in {
    Null => ()
    Lazy(f) => {
      let n = f(ns)
      match anchor_opt {
        Some(ref_id) => emit(InsertBefore(id, n.id, ref_id))
        None => emit(Append(id, n.id))
      }
      target_array.push(n)
    }
    Str(s) => {
      let n = create_text_node(s)
      match anchor_opt {
        Some(ref_id) => emit(InsertBefore(id, n.id, ref_id))
        None => emit(Append(id, n.id))
      }
      target_array.push(n)
    }
    Int(i) => children(id, Str(i.to_string()), target_array, ns, anchor_opt)
    Arr(a) => {
      for child in a { children(id, child, target_array, ns, anchor_opt) }
    }
    Dyn(f) => {
      let anchor = create_text_node("")
      match anchor_opt {
        Some(ref_id) => emit(InsertBefore(id, anchor.id, ref_id))
        None => emit(Append(id, anchor.id))
      }
      target_array.push(anchor)
      
      let old_nodes: Ref[Array[VNode]] = Ref::new([])
      
      let stop_effect = effect(fn() {
        for old in old_nodes.val {
          emit(Remove(old.id))
          recursive_cleanup(old)
        }
        let new_child = f()
        let new_vnodes = []
        children(id, new_child, new_vnodes, ns, Some(anchor.id))
        old_nodes.val = new_vnodes
      }) catch { _ => fn() {} }
      
      anchor.clrs.push(fn() { 
        let _ = stop_effect()
        for old in old_nodes.val { recursive_cleanup(old) }
      })
    }
  }
}

pub(open) trait HTag {
  render(Self, Array[(String, Prop)], Array[Child]) -> Child
}

fn render_element(tag: String, attrs: Array[(String, Prop)], children_prop: Array[Child]) -> Child {
  Lazy(fn(ns: String) -> VNode {
    let cur_ns = if ns == "" { ns_html } else { ns }
    let create_ns = if tag == "svg" { ns_svg } else if tag == "math" { ns_math } else { cur_ns }
    let child_ns = if tag == "foreignObject" { ns_html } else if tag == "svg" { ns_svg } else if tag == "math" { ns_math } else { cur_ns }
    let id = next_id(); emit(Create(id, tag, create_ns))
    let my_cbs = []
    let my_clrs: Array[() -> Unit] = []
    attrs.each(fn(p) {
      let (k, v) = p
      match v {
        S(s) => emit(Attr(id, k, s))
        D(f) => {
          let stop = effect(fn() { emit(UpdateAttr(id, k, f())) }) catch { _ => fn() {} }
          my_clrs.push(stop)
        }
        E(f) => {
          let i = ci.val; ci.val = i + 1; cbs.set(i, f)
          my_cbs.push(i)
          emit(Listen(id, k, i))
        }
        EK(f) => {
          let i = ci.val; ci.val = i + 1; cbs_ev.set(i, f)
          my_cbs.push(i)
          emit(Listen(id, k, i))
        }
        ActionRef(i) => {
          my_cbs.push(i)
          emit(Listen(id, k, i))
        }
      }
    })
    let current_children: Array[VNode] = []
    for c in children_prop { children(id, c, current_children, child_ns, None) }
    { id, cb_ids: my_cbs, clrs: my_clrs, children: current_children }
  })
}

pub impl HTag for String with render(self, attrs, children_prop) {
  render_element(self, attrs, children_prop)
}

pub struct Comp {
  priv render : (Array[(String, Prop)], Array[Child]) -> Child
}

pub fn comp(f: (Array[(String, Prop)], Array[Child]) -> Child) -> Comp { { render: f } }

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
            let child = f(x, fn() { idx.val })
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
          let child = f(x, fn() { idx.val })
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
  node.cb_ids.each(fn(id) { cbs.remove(id); cbs_ev.remove(id) })
  node.clrs.each(fn(f) { f() })
  node.children.each(recursive_cleanup)
}

// 宿主命令辅助函数
pub fn focus_node(id: Int) -> Unit { emit(HostCmd(id, "focus")) }
pub fn blur_node(id: Int) -> Unit { emit(HostCmd(id, "blur")) }
pub fn scroll_into_view(id: Int) -> Unit { emit(HostCmd(id, "scrollIntoView")) }
pub fn remove(node: VNode) -> Unit { 
  emit(Remove(node.id))
  recursive_cleanup(node)
}
pub fn init_bridge(sender: (Array[String]) -> Unit) -> Unit {
  let _ = on_post_flush(fn() { 
    let cs = get_cmds()
    if cs.length() > 0 { sender(cs.map(fn(c) { c.to_json() }))  } 
  })
}

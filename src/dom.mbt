let nid: Ref[Int] = Ref::new(1)
let ns_html = "http://www.w3.org/1999/xhtml"
let ns_svg = "http://www.w3.org/2000/svg"
let ns_math = "http://www.w3.org/1998/Math/MathML"

// ====== 命令与基础类型 ======
pub(all) enum Cmd[I, S] {
  Create(I, S, S)
  Text(I, S)
  Attr(I, S, S)
  Append(I, I)
  UpdateText(I, S)
  UpdateAttr(I, S, S)
  Remove(I)
  Listen(I, S, S)
  InsertBefore(I, I, I)
  SetStyle(I, S, S)    // 设置单个 style 属性
  RemoveStyle(I, S)    // 移除单个 style 属性
  RemoveAttr(I, S)     // 移除属性
  HostCmd(I, S)        // 宿主命令(focus/blur/scrollIntoView)
  SetCss(S, S)         // 设置全局样式表
  RemoveCss(S)         // 移除全局样式表
}
pub type DomCmd = Cmd[Int, String]
fn[T: ToJson] jarr(items: T) -> String { items.to_json().stringify() }
pub fn dom_cmd_to_json(cmd: DomCmd) -> String {
  match cmd {
    Create(id, tag, ns) => jarr((0, id, tag, ns))
    Text(id, text) => jarr((1, id, text))
    Attr(id, k, v) => jarr((2, id, k, v))
    Append(pid, cid) => jarr((3, pid, cid))
    UpdateText(id, text) => jarr((4, id, text))
    UpdateAttr(id, k, v) => jarr((5, id, k, v))
    Remove(id) => jarr((6, id))
    Listen(id, ev, ui_id) => jarr((7, id, ev, ui_id))
    InsertBefore(pid, cid, rid) => jarr((8, pid, cid, rid))
    SetStyle(id, k, v) => jarr((9, id, k, v))
    RemoveStyle(id, k) => jarr((10, id, k))
    RemoveAttr(id, k) => jarr((11, id, k))
    HostCmd(id, cmd) => jarr((12, id, cmd))
    SetCss(id, text) => jarr((13, id, text))
    RemoveCss(id) => jarr((14, id))
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
  parent_id: Int?
  ui_id: String?
  listener_keys: Array[String]
  action_names: Array[String]
  clrs: Array[() -> Unit]
  children: Array[VNode]
  scope_names: Map[String, Int]?
  list_items: Array[Map[String, Int]]?
}
pub(all) enum Prop {
  S(String)
  D(() -> String)
  E(() -> Unit raise)
  EK((EventData) -> Unit raise)
}
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

// ====== 事件与属性辅助 ======
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
fn listener_key(id: Int, event: String) -> String {
  "\{id}\n\{event}"
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
fn parse_static_flag(value: Prop) -> Bool {
  match value {
    S("false") => false
    _ => true
  }
}
priv struct UiHostAttrs {
  name: Bool
  react: Bool
  list: Bool
}
fn take_ui_host_attrs(attrs: Array[(String, Prop)]) -> (Array[(String, Prop)], UiHostAttrs) {
  let plain: Array[(String, Prop)] = []
  let mut name = false
  let mut react = false
  let mut list = false
  for pair in attrs {
    let (key, value) = pair
    match key {
      "ui-name" => name = parse_static_flag(value)
      "ui-react" => react = parse_static_flag(value)
      "ui-list" => list = parse_static_flag(value)
      _ => plain.push(pair)
    }
  }
  (plain, { name, react, list })
}

// ====== 全局状态 ======
let event_handlers: Map[String, EventSlot] = Map::new()
let ui_nodes: Map[String, Int] = Map::new()
let nodes_by_id: Map[Int, VNode] = Map::new()
let pending_mounts: Map[Int, (Int) -> Unit] = Map::new()
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
fn drain_global_cmds(state: DomState) -> Unit {
  if cq.length() == 0 { return }
  for cmd in cq { state.cmds.push(cmd) }
  cq.clear()
}
pub fn get_cmds(state: DomState) -> Array[DomCmd] {
  drain_global_cmds(state)
  let r = state.cmds.copy()
  state.cmds.clear()
  r
}
pub fn reset_ui() -> Unit {
  nid.val = 1
  cq.clear()
  event_handlers.clear()
  ui_nodes.clear()
  nodes_by_id.clear()
  pending_mounts.clear()
  reset_reactive()
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
fn remember_node(node: VNode) -> VNode {
  nodes_by_id.set(node.id, node)
  node
}

// ====== scope 与 query ======
fn mount_node_before(parent_id: Int, node_id: Int, before_id: Int?) -> Int {
  match before_id {
    Some(id) => emit_current(InsertBefore(parent_id, node_id, id))
    None => emit_current(Append(parent_id, node_id))
  }
  node_id
}
fn parse_query_index(part: String) -> Int? {
  Some(@string.parse_int(part)) catch { _ => None }
}
fn collect_scope_names_into(node: VNode, names: Map[String, Int]) -> Unit {
  match node.ui_id {
    Some(name) => names.set(name, node.id)
    None =>
      match node.list_items {
        Some(_) => {
          for child in node.children { collect_scope_names_into(child, names) }
          return
        }
        None =>
          match node.scope_names {
            Some(inner) => {
              for key, value in inner { names.set(key, value) }
              return
            }
            None => ()
          }
      }
  }
  if node.scope_names is Some(_) || node.list_items is Some(_) { return }
  for child in node.children { collect_scope_names_into(child, names) }
}
fn scope_names_of_node(node: VNode) -> Map[String, Int] {
  match node.scope_names {
    Some(names) => names
    None => {
      let names: Map[String, Int] = Map::new()
      collect_scope_names_into(node, names)
      names
    }
  }
}
fn refresh_names_map(names: Map[String, Int], nodes: Array[VNode]) -> Unit {
  names.clear()
  for node in nodes { collect_scope_names_into(node, names) }
}
fn list_item_scopes(nodes: Array[VNode]) -> Array[Map[String, Int]] {
  let items: Array[Map[String, Int]] = []
  for child in nodes {
    let current = match nodes_by_id.get(child.id) {
      Some(value) => value
      None => child
    }
    match current.list_items {
      Some(scopes) => for scope in scopes { items.push(scope) }
      None => items.push(scope_names_of_node(current))
    }
  }
  items
}
fn refresh_list_items(scopes: Array[Map[String, Int]], nodes: Array[VNode]) -> Unit {
  scopes.clear()
  for scope in list_item_scopes(nodes) { scopes.push(scope) }
}
fn remember_parent(node: VNode, parent_id: Int?) -> VNode {
  remember_node({ ..node, parent_id: parent_id })
}
fn current_node(node: VNode) -> VNode {
  match nodes_by_id.get(node.id) {
    Some(value) => value
    None => node
  }
}
fn refresh_scope_owner(node: VNode) -> Unit {
  match node.scope_names {
    Some(names) => refresh_names_map(names, node.children)
    None => ()
  }
  match node.list_items {
    Some(scopes) => refresh_list_items(scopes, node.children)
    None => ()
  }
  ignore(remember_node(node))
}
fn refresh_scope_chain(parent_id: Int?) -> Unit {
  let mut current = parent_id
  while true {
    match current {
      Some(id) =>
        match nodes_by_id.get(id) {
          Some(node) => {
            refresh_scope_owner(node)
            current = node.parent_id
          }
          None => return
        }
      None => return
    }
  }
}
priv enum QueryCursor {
  Node(Int)
  Scope(Map[String, Int])
}
fn resolve_local_name(node: VNode, part: String) -> Int? {
  match node.scope_names {
    Some(names) =>
      match names.get(part) {
        Some(value) => Some(value)
        None =>
          match node.ui_id {
            Some(name) => if name == part { Some(node.id) } else { None }
            None => None
          }
      }
    None =>
      match node.ui_id {
        Some(name) => if name == part { Some(node.id) } else { None }
        None => None
      }
  }
}
fn resolve_ui_query(query: String) -> Int? {
  let parts = query.split("/").collect().map(fn(part) { part.to_string() }).filter(part => part != "")
  if parts.length() == 0 { return None }
  let current = match ui_nodes.get(parts[0]) {
    Some(id) => id
    None => return None
  }
  let cursor: Ref[QueryCursor] = Ref::new(Node(current))
  for i = 1; i < parts.length(); i = i + 1 {
    let part = parts[i]
    match cursor.val {
      Node(node_id) => {
        let node = match nodes_by_id.get(node_id) {
          Some(value) => value
          None => return None
        }
        match resolve_local_name(node, part) {
          Some(value) => {
            cursor.val = Node(value)
            continue
          }
          None => ()
        }
        match node.list_items {
          Some(scopes) =>
            match parse_query_index(part) {
              Some(index) => {
                if index < 0 || index >= scopes.length() { return None }
                cursor.val = Scope(scopes[index])
              }
              None => return None
            }
          None => return None
        }
      }
      Scope(scope) =>
        match scope.get(part) {
          Some(value) => cursor.val = Node(value)
          None => return None
        }
    }
  }
  match cursor.val {
    Node(id) => Some(id)
    Scope(_) => None
  }
}
pub fn trigger_node(id: Int, event: String) -> Unit {
  trigger_event(listener_key(id, event), EventData::default())
}
pub fn trigger_node_ev(id: Int, event: String, ev: EventData) -> Unit {
  trigger_event(listener_key(id, event), ev)
}
pub fn trigger_ui(ui_id: String, event: String) -> Unit {
  match resolve_ui_query(ui_id) {
    Some(id) => trigger_node(id, event)
    None => ()
  }
}
pub fn trigger_ui_ev(ui_id: String, event: String, ev: EventData) -> Unit {
  match resolve_ui_query(ui_id) {
    Some(id) => trigger_node_ev(id, event, ev)
    None => ()
  }
}
pub fn css(id: String, value: Prop) -> Unit {
  let dom_state = active_dom_state()
  let live = Ref::new(true)
  let clear = fn() {
    if live.val {
      live.val = false
      ignore(use_dom_state_inner(dom_state, fn() { emit_current(RemoveCss(id)) }))
    }
  }
  match value {
    S(text) => {
      emit_current(SetCss(id, css_scope_block(id, text)))
      onclr(clear)
    }
    D(f) => {
      let stop = effect(fn() {
        use_dom_state_inner(dom_state, fn() {
          emit_current(SetCss(id, css_scope_block(id, f())))
        })
      }) catch { _ => fn() {} }
      onclr(fn() {
        let _ = stop()
        clear()
      })
    }
    _ => abort("css only accepts string")
  }
}

// ====== 基础节点与子树更新 ======
fn create_text_node(v: String) -> VNode { 
  let id = next_active_id(); emit_current(Create(id, "", "")); emit_current(Text(id, v))
  remember_node({
    id,
    parent_id: None,
    ui_id: None,
    listener_keys: [],
    action_names: [],
    clrs: [],
    children: [],
    scope_names: None,
    list_items: None,
  }) 
}
fn create_list_anchor() -> VNode {
  let anchor = create_text_node("")
  remember_node({ ..anchor, list_items: Some([]) })
}
fn contains_node(nodes: Array[VNode], id: Int) -> Bool {
  for node in nodes {
    if node.id == id { return true }
  }
  false
}
fn mount_owner_item(
  mount_id: Int,
  owner: VNode,
  ns: String,
  item: Child,
  nodes: Array[VNode],
  scopes: Array[Map[String, Int]],
) -> Unit {
  let item_nodes: Array[VNode] = []
  children(mount_id, owner.id, item, item_nodes, ns, Some(owner.id))
  match owner.list_items {
    Some(_) => {
      let item_scope = Map::new()
      refresh_names_map(item_scope, item_nodes)
      scopes.push(item_scope)
    }
    None => ()
  }
  for node in item_nodes { nodes.push(node) }
}
fn replace_owner_children(
  mount_id: Int,
  owner: VNode,
  ns: String,
  child: Child,
) -> Array[VNode] {
  let nodes: Array[VNode] = []
  let scopes: Array[Map[String, Int]] = []
  owner.children.clear()
  match child {
    Arr(items) => for item in items { mount_owner_item(mount_id, owner, ns, item, nodes, scopes) }
    _ => mount_owner_item(mount_id, owner, ns, child, nodes, scopes)
  }
  for node in nodes { owner.children.push(node) }
  match owner.list_items {
    Some(items) => {
      items.clear()
      for scope in scopes { items.push(scope) }
    }
    None => ()
  }
  refresh_scope_owner(owner)
  refresh_scope_chain(owner.parent_id)
  nodes
}
fn cleanup_removed_nodes(old_nodes: Array[VNode], new_nodes: Array[VNode]) -> Unit {
  for old in old_nodes {
    if !contains_node(new_nodes, old.id) {
      emit_current(Remove(old.id))
      recursive_cleanup(old)
    }
  }
}
fn cleanup_nodes(nodes: Array[VNode]) -> Unit {
  for node in nodes {
    emit_current(Remove(node.id))
    recursive_cleanup(node)
  }
}
fn children(
  mount_id: Int,
  owner_id: Int,
  c_in: Child,
  target_array: Array[VNode],
  ns: String,
  anchor_opt: Option[Int],
) -> Unit {
  match c_in {
    Null => ()
    Lazy(f) => {
      let n = remember_parent(f(ns), Some(owner_id))
      match anchor_opt {
        Some(ref_id) => emit_current(InsertBefore(mount_id, n.id, ref_id))
        None => emit_current(Append(mount_id, n.id))
      }
      match pending_mounts.get(n.id) {
        Some(start) => {
          pending_mounts.remove(n.id)
          start(mount_id)
        }
        None => ()
      }
      target_array.push(n)
    }
    Str(s) => {
      let n = remember_parent(create_text_node(s), Some(owner_id))
      match anchor_opt {
        Some(ref_id) => emit_current(InsertBefore(mount_id, n.id, ref_id))
        None => emit_current(Append(mount_id, n.id))
      }
      target_array.push(n)
    }
    Int(i) => children(mount_id, owner_id, Str(i.to_string()), target_array, ns, anchor_opt)
    Arr(a) => {
      for child in a { children(mount_id, owner_id, child, target_array, ns, anchor_opt) }
    }
    Dyn(f) => {
      let dom_state = active_dom_state()
      let anchor = remember_parent({ ..create_list_anchor(), scope_names: Some(Map::new()) }, Some(owner_id))
      match anchor_opt {
        Some(ref_id) => emit_current(InsertBefore(mount_id, anchor.id, ref_id))
        None => emit_current(Append(mount_id, anchor.id))
      }
      target_array.push(anchor)
      
      let old_nodes: Ref[Array[VNode]] = Ref::new([])
      
      let stop_effect = effect(fn() {
        use_dom_state_inner(dom_state, fn() {
          let new_vnodes = replace_owner_children(mount_id, anchor, ns, f())
          cleanup_removed_nodes(old_nodes.val, new_vnodes)
          old_nodes.val = new_vnodes
        })
      }) catch { _ => fn() {} }
      
      anchor.clrs.push(fn() { 
        ignore(use_dom_state_inner(dom_state, fn() {
          let _ = stop_effect()
          cleanup_nodes(old_nodes.val)
          refresh_scope_chain(anchor.parent_id)
        }))
      })
    }
  }
}

// ====== 元素渲染 ======
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
    let ui_class = match ui_id {
      Some(value) => Some(derived_ui_class(value))
      None => None
    }
    let listener_keys: Array[String] = []
    let action_names: Array[String] = []
    let my_clrs: Array[() -> Unit] = []
    let saw_class = Ref::new(false)
    match ui_id {
      Some(value) => ui_nodes.set(value, id)
      None => ()
    }
    attrs.each(fn(p) {
      let (k, v) = p
      match style_prop_name(k) {
        Some(style_key) =>
          match v {
            S(s) => emit_style_attr(id, style_key, s)
            D(f) => {
              let stop = effect(fn() {
                use_dom_state_inner(dom_state, fn() { emit_style_attr(id, style_key, f()) })
              }) catch { _ => fn() {} }
              my_clrs.push(stop)
            }
            _ => abort("style property only accepts string")
          }
        None =>
          match v {
            S(s) => {
              if k == "class" { saw_class.val = true }
              emit_current(Attr(id, k, if k == "class" { merge_class_name(s, ui_class) } else { s }))
            }
            D(f) => {
              if k == "ui-id" { abort("ui-id must be static") }
              if k == "class" { saw_class.val = true }
              let stop = effect(fn() {
                use_dom_state_inner(dom_state, fn() {
                  emit_current(UpdateAttr(
                    id,
                    k,
                    if k == "class" { merge_class_name(f(), ui_class) } else { f() },
                  ))
                })
              }) catch { _ => fn() {} }
              my_clrs.push(stop)
            }
            E(f) => {
              let uid = match ui_id {
                Some(value) => value
                None => abort("interactive node requires ui-id")
              }
              let key = listener_key(id, k)
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
              let key = listener_key(id, k)
              event_handlers.set(key, {
                owner_id: id,
                handler: WithData(fn(ev) raise {
                  ignore(use_dom_state_raise(dom_state, fn() raise { f(ev) }))
                })
              })
              listener_keys.push(key)
              emit_current(Listen(id, k, uid))
            }
          }
      }
    })
    if !saw_class.val {
      match ui_class {
        Some(name) => emit_current(Attr(id, "class", name))
        None => ()
      }
    }
    let current_children: Array[VNode] = []
    for c in children_prop { children(id, id, c, current_children, child_ns, None) }
    remember_node({
      id,
      parent_id: None,
      ui_id,
      listener_keys,
      action_names,
      clrs: my_clrs,
      children: current_children,
      scope_names: None,
      list_items: None,
    })
  })
}
pub impl HTag for String with render(self, attrs, children_prop) {
  render_element(self, attrs, children_prop)
}
pub struct Comp {
  priv render : (Array[(String, Prop)], Array[Child]) -> Child
}
pub fn comp(f: (Array[(String, Prop)], Array[Child]) -> Child) -> Comp { { render: f } }

// ====== 作用域宿主与 h ======
fn attach_scope_host(
  node: VNode,
  stop: (() -> Unit)?,
  flags: (Bool, Bool, Bool),
) -> VNode {
  let (attach_stop, attach_names, attach_list) = flags
  if (attach_names || attach_list) && node.ui_id is None {
    abort("ui-name/ui-list requires ui-id")
  }
  if attach_stop {
    match stop {
      Some(f) => node.clrs.push(f)
      None => ()
    }
  }
  let host = remember_node({
    ..node,
    scope_names: if attach_names { Some(Map::new()) } else { None },
    list_items: if attach_list { Some([]) } else { None },
  })
  refresh_scope_owner(host)
  host
}
fn attach(
  child: Child,
  handle: ScopeHandle?,
  flags: (Bool, Bool, Bool),
) -> Child {
  let (f_stop, f_name, f_list) = flags
  let stop = match handle {
    Some(scope) => Some(fn() { stop_scope(scope) })
    None => None
  }
  match child {
    Null => Lazy(fn(_ns: String) -> VNode {
      attach_scope_host(create_text_node(""), stop, flags)
    })
    Lazy(f) => Lazy(fn(ns: String) -> VNode {
      let node = match handle {
        Some(scope) => with_scope(scope, fn() { f(ns) }) catch { _ => panic() }
        None => f(ns)
      }
      attach_scope_host(node, stop, flags)
    })
    Str(s) => Lazy(fn(_ns: String) -> VNode {
      attach_scope_host(create_text_node(s), stop, flags)
    })
    Int(i) => attach(Str(i.to_string()), handle, flags)
    Arr(items) => {
      if items.length() == 0 { return attach(Null, handle, flags) }
      let out: Array[Child] = []
      let mut current = flags
      for item in items {
        out.push(attach(item, handle, current))
        current = (false, false, false)
      }
      Arr(out)
    }
    Dyn(f) =>
      if f_stop || f_name || f_list {
        Arr([
          Lazy(fn(_ns: String) -> VNode {
            attach_scope_host(create_text_node(""), stop, flags)
          }),
          Dyn(fn() {
            match handle {
              Some(scope) =>
                with_scope(scope, fn() { attach(f(), handle, (false, false, false)) }) catch { _ => panic() }
              None => attach(f(), handle, (false, false, false))
            }
          })
        ])
      } else {
        Dyn(fn() {
          match handle {
            Some(scope) =>
              with_scope(scope, fn() { attach(f(), handle, (false, false, false)) }) catch { _ => panic() }
            None => attach(f(), handle, (false, false, false))
          }
        })
      }
  }
}
pub impl HTag for Comp with render(self, attrs, children_prop) {
  (self.render)(attrs, children_prop)
}
pub fn[T: HTag] h(tag: T, attrs: Array[(String, Prop)], children_prop: Array[Child]) -> Child {
  let (plain_attrs, ui_host) = take_ui_host_attrs(attrs)
  let handle = if ui_host.react { Some(new_scope()) } else { None }
  let child = match handle {
    Some(scope) =>
      with_scope(scope, fn() { tag.render(plain_attrs, children_prop) }) catch { _ => panic() }
    None => tag.render(plain_attrs, children_prop)
  }
  if ui_host.name || ui_host.react || ui_host.list {
    attach(child, handle, (ui_host.react, ui_host.name, ui_host.list))
  } else {
    child
  }
}

// ====== h_map 列表复用 ======
priv struct HMapEntry {
  anchor: VNode
  idx: Ref[Int]
}
fn item_first_mounted_id(anchor: VNode) -> Int {
  if anchor.children.length() == 0 { return anchor.id }
  anchor.children[0].id
}
fn move_item_before(parent_id: Int, anchor: VNode, before_id: Int?) -> Unit {
  for node in anchor.children {
    match before_id {
      Some(id) => emit_current(InsertBefore(parent_id, node.id, id))
      None => emit_current(Append(parent_id, node.id))
    }
  }
  match before_id {
    Some(id) => emit_current(InsertBefore(parent_id, anchor.id, id))
    None => emit_current(Append(parent_id, anchor.id))
  }
}
fn cleanup_item(anchor: VNode) -> Unit {
  for node in anchor.children {
    emit_current(Remove(node.id))
    recursive_cleanup(node)
  }
  anchor.children.clear()
  emit_current(Remove(anchor.id))
  recursive_cleanup(anchor)
}
fn realize_item(parent_id: Int, ns: String, before_id: Int?, child: Child) -> VNode {
  let anchor = remember_parent({ ..create_text_node(""), scope_names: Some(Map::new()) }, Some(parent_id))
  ignore(mount_node_before(parent_id, anchor.id, before_id))
  ignore(replace_owner_children(parent_id, anchor, ns, child))
  anchor
}
fn item_scope_names(anchor: VNode) -> Map[String, Int] {
  match current_node(anchor).scope_names {
    Some(names) => names
    None => abort("h_map item missing scope_names")
  }
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
  Lazy(fn(ns: String) -> VNode {
    let dom_state = active_dom_state()
    let anchor = create_list_anchor()
    let entries: Ref[Array[HMapEntry]] = Ref::new([])
    let started = Ref::new(false)
    let stop_effect: Ref[(() -> Unit)?] = Ref::new(None)
    let start = fn(parent_id: Int) {
      if started.val { return }
      started.val = true
      stop_effect.val = Some(effect(fn() {
        use_dom_state_inner(dom_state, fn() {
          let anchor = current_node(anchor)
          let xs = items()
          let prev = cache.val
          let next_cache: Map[T, Array[HMapEntry]] = Map::new()
          let used: Map[T, Int] = Map::new()
          let reused: Map[T, Int] = Map::new()
          let plans: Array[(T, Int, HMapEntry?)] = []
          let keep_ids: Map[Int, Bool] = Map::new()
          for pair in xs {
            let (x, n) = pair
            let pos = match used.get(x) { Some(k) => k; None => 0 }
            let reused_entry = match prev.get(x) {
              Some(entries) =>
                if pos < entries.length() {
                  let entry = entries[pos]
                  entry.idx.val = n
                  reused.set(x, pos + 1)
                  keep_ids.set(entry.anchor.id, true)
                  Some(entry)
                } else {
                  None
                }
              None => None
            }
            plans.push((x, n, reused_entry))
            used.set(x, pos + 1)
          }
          let kept_order: Array[HMapEntry] = []
          for entry in entries.val {
            if keep_ids.get(entry.anchor.id) == Some(true) { kept_order.push(entry) }
          }
          let current_entries: Array[HMapEntry] = []
          let cursor = Ref::new(0)
          let before_id = fn() -> Int {
            if cursor.val < kept_order.length() {
              item_first_mounted_id(kept_order[cursor.val].anchor)
            } else {
              anchor.id
            }
          }
          for plan in plans {
            let (x, n, planned) = plan
            let entry = match planned {
              Some(entry) => {
                if cursor.val < kept_order.length() &&
                  kept_order[cursor.val].anchor.id == entry.anchor.id {
                  cursor.val = cursor.val + 1
                } else {
                  move_item_before(parent_id, entry.anchor, Some(before_id()))
                }
                entry
              }
              None => {
                let idx = Ref::new(n)
                { anchor: realize_item(parent_id, ns, Some(before_id()), f(x, fn() { idx.val })), idx }
              }
            }
            current_entries.push(entry)
            match next_cache.get(x) {
              Some(vs) => vs.push(entry)
              None => next_cache.set(x, [entry])
            }
          }
          for key, entries in prev {
            let keep = match reused.get(key) { Some(n) => n; None => 0 }
            for i in keep..<entries.length() {
              cleanup_item(entries[i].anchor)
            }
          }
          cache.val = next_cache
          entries.val = current_entries
          anchor.children.clear()
          for entry in current_entries { anchor.children.push(entry.anchor) }
          match anchor.list_items {
            Some(items) => {
              items.clear()
              for entry in current_entries { items.push(item_scope_names(entry.anchor)) }
            }
            None => ()
          }
          ignore(remember_node(anchor))
          refresh_scope_chain(anchor.parent_id)
        })
      }) catch { _ => fn() {} })
    }
    pending_mounts.set(anchor.id, start)
    anchor.clrs.push(fn() {
      ignore(use_dom_state_inner(dom_state, fn() {
        let anchor = current_node(anchor)
        pending_mounts.remove(anchor.id)
        match stop_effect.val {
          Some(stop) => {
            let _ = stop()
            stop_effect.val = None
          }
          None => ()
        }
        for entry in entries.val {
          cleanup_item(entry.anchor)
        }
        entries.val = []
        anchor.children.clear()
        match anchor.list_items {
          Some(ids) => ids.clear()
          None => ()
        }
        ignore(remember_node(anchor))
      }))
    })
    remember_node(anchor)
  })
}

// ====== 清理与对外辅助 ======
fn recursive_cleanup(node: VNode) -> Unit {
  node.listener_keys.each(fn(key) {
    match event_handlers.get(key) {
      Some(slot) => if slot.owner_id == node.id { event_handlers.remove(key) }
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
  nodes_by_id.remove(node.id)
  node.clrs.each(fn(f) { f() })
  node.children.each(recursive_cleanup)
}
// 宿主命令辅助函数
pub fn click(ui_id: String) -> Unit { trigger_ui(ui_id, "onclick") }
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
    if cs.length() > 0 { sender(cs.map(fn(c) { dom_cmd_to_json(c) }))  }
  })
}

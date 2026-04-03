let nid: Ref[Int] = Ref::new(1)
let ns_html = "http://www.w3.org/1999/xhtml"
let ns_svg = "http://www.w3.org/2000/svg"
let ns_math = "http://www.w3.org/1998/Math/MathML"
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
fn scope_names_of_node(node: VNode) -> Map[String, Int] {
  match node.scope_names {
    Some(names) => names
    None => {
      let names: Map[String, Int] = Map::new()
      collect_item_scope_names(node, names)
      ignore(remember_node({ ..node, scope_names: Some(names) }))
      names
    }
  }
}
fn scope_names_ref_of_nodes(nodes: Array[VNode]) -> Map[String, Int]? {
  if nodes.length() == 0 { return None }
  match nodes[0].scope_names {
    Some(names) => Some(names)
    None => None
  }
}
fn build_scope_names_of_nodes(nodes: Array[VNode]) -> Map[String, Int] {
  let names: Map[String, Int] = Map::new()
  for node in nodes { collect_item_scope_names(node, names) }
  names
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
fn list_items_for_host(nodes: Array[VNode]) -> Array[Map[String, Int]] {
  list_item_scopes(nodes)
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
fn create_text_node(v: String) -> VNode { 
  let id = next_active_id(); emit_current(Create(id, "", "")); emit_current(Text(id, v))
  remember_node({
    id,
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
fn children(id: Int, c_in: Child, target_array: Array[VNode], ns: String, anchor_opt: Option[Int]) -> Unit {
  match c_in {
    Null => ()
    Lazy(f) => {
      let n = f(ns)
      match anchor_opt {
        Some(ref_id) => emit_current(InsertBefore(id, n.id, ref_id))
        None => emit_current(Append(id, n.id))
      }
      match pending_mounts.get(n.id) {
        Some(start) => {
          pending_mounts.remove(n.id)
          start(id)
        }
        None => ()
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
      let anchor = remember_node({ ..create_list_anchor(), scope_names: Some(Map::new()) })
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
          let new_scopes = []
          anchor.children.clear()
          let add_item = fn(item: Child) {
            let item_nodes: Array[VNode] = []
            children(id, item, item_nodes, ns, Some(anchor.id))
            let item_nodes = attach_item_scope_names(item_nodes)
            new_scopes.push(build_scope_names_of_nodes(item_nodes))
            for node in item_nodes {
              new_vnodes.push(node)
            }
          }
          match new_child {
            Arr(items) => for item in items { add_item(item) }
            _ => add_item(new_child)
          }
          for node in new_vnodes { anchor.children.push(node) }
          match anchor.list_items {
            Some(scopes) => {
              scopes.clear()
              for scope in new_scopes { scopes.push(scope) }
            }
            None => ()
          }
          let current_scope = match anchor.scope_names {
            Some(names) => names
            None => Map::new()
          }
          current_scope.clear()
          let next_scope = build_scope_names_of_nodes(new_vnodes)
          for key, value in next_scope { current_scope.set(key, value) }
          ignore(remember_node({
            ..anchor,
            scope_names: Some(current_scope),
          }))
          match nodes_by_id.get(id) {
            Some(parent) =>
              if parent.ui_id is None && parent.scope_names is Some(_) {
                let parent_scope = match parent.scope_names {
                  Some(names) => names
                  None => Map::new()
                }
                parent_scope.clear()
                for key, value in current_scope { parent_scope.set(key, value) }
                ignore(remember_node({ ..parent, scope_names: Some(parent_scope) }))
              }
            None => ()
          }
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
    for c in children_prop { children(id, c, current_children, child_ns, None) }
    remember_node({
      id,
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
fn collect_scope_names(node: VNode, names: Map[String, Int]) -> Unit {
  match node.ui_id {
    Some(name) => names.set(name, node.id)
    None => ()
  }
  if node.scope_names is Some(_) || node.list_items is Some(_) { return }
  for child in node.children { collect_scope_names(child, names) }
}
fn collect_item_scope_names(node: VNode, names: Map[String, Int]) -> Unit {
  match node.ui_id {
    Some(name) => names.set(name, node.id)
    None =>
      match node.list_items {
        Some(_) => {
          for child in node.children { collect_item_scope_names(child, names) }
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
  for child in node.children { collect_item_scope_names(child, names) }
}
fn attach_item_scope_names(nodes: Array[VNode]) -> Array[VNode] {
  if nodes.length() == 0 { return nodes }
  let names = match nodes[0].scope_names {
    Some(names) => names
    None => Map::new()
  }
  names.clear()
  for node in nodes { collect_item_scope_names(node, names) }
  let first = remember_node({ ..nodes[0], scope_names: Some(names) })
  nodes[0] = first
  nodes
}
fn scoped_item(child: Child) -> Child {
  match child {
    Null => Null
    Str(_) | Int(_) | Lazy(_) =>
      Lazy(fn(ns: String) -> VNode {
        ignore(ns)
        let node = realize_current(match child { Int(i) => Str(i.to_string()); _ => child })
        let items = [node]
        attach_item_scope_names(items)[0]
      })
    Arr(items) => {
      if items.length() == 0 { return Arr([]) }
      let out = items.copy()
      out[0] = scoped_item(out[0])
      Arr(out)
    }
    Dyn(f) => Dyn(fn() { scoped_item(f()) })
  }
}
fn scope_names_for(node: VNode, attach: Bool) -> Map[String, Int]? {
  if !attach { return None }
  let names: Map[String, Int] = Map::new()
  for child in node.children { collect_scope_names(child, names) }
  Some(names)
}
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
  remember_node({
    ..node,
    scope_names: scope_names_for(node, attach_names),
    list_items: if attach_list { Some(list_items_for_host(node.children)) } else { None },
  })
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
  let anchor = create_text_node("")
  ignore(mount_node_before(parent_id, anchor.id, before_id))
  let roots: Array[VNode] = []
  children(parent_id, child, roots, ns, Some(anchor.id))
  let roots = attach_item_scope_names(roots)
  for node in roots { anchor.children.push(node) }
  remember_node({
    ..anchor,
    scope_names: match scope_names_ref_of_nodes(roots) {
      Some(names) => Some(names)
      None => if roots.length() > 0 { Some(build_scope_names_of_nodes(roots)) } else { None }
    },
  })
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
          let xs = items()
          let prev = cache.val
          let next: Map[T, Array[HMapEntry]] = Map::new()
          let used: Map[T, Int] = Map::new()
          let reused: Map[T, Int] = Map::new()
          let plans: Array[(T, Int, HMapEntry?)] = []
          for pair in xs {
            let (x, n) = pair
            let pos = match used.get(x) { Some(k) => k; None => 0 }
            let reused_entry = match prev.get(x) {
              Some(entries) =>
                if pos < entries.length() {
                  let entry = entries[pos]
                  entry.idx.val = n
                  reused.set(x, pos + 1)
                  Some(entry)
                } else {
                  None
                }
              None => None
            }
            plans.push((x, n, reused_entry))
            used.set(x, pos + 1)
          }
          let current_entries_rev: Array[HMapEntry] = []
          let mut before_id: Int? = Some(anchor.id)
          for i = plans.length() - 1; i >= 0; i = i - 1 {
            let plan = plans[i]
            let (x, n, planned) = plan
            let entry = match planned {
              Some(entry) => {
                move_item_before(parent_id, entry.anchor, before_id)
                entry
              }
              None => {
                let idx = Ref::new(n)
                let item_anchor = realize_item(parent_id, ns, before_id, scoped_item(f(x, fn() { idx.val })))
                { anchor: item_anchor, idx }
              }
            }
            current_entries_rev.push(entry)
            before_id = Some(item_first_mounted_id(entry.anchor))
            match next.get(x) {
              Some(vs) => vs.push(entry)
              None => next.set(x, [entry])
            }
          }
          let current_entries: Array[HMapEntry] = []
          for i = current_entries_rev.length() - 1; i >= 0; i = i - 1 {
            current_entries.push(current_entries_rev[i])
          }
          for _, entries in next {
            let reversed = entries.copy()
            entries.clear()
            for i = reversed.length() - 1; i >= 0; i = i - 1 {
              entries.push(reversed[i])
            }
          }
          for key, entries in prev {
            let keep = match reused.get(key) { Some(n) => n; None => 0 }
            for i in keep..<entries.length() {
              cleanup_item(entries[i].anchor)
            }
          }
          cache.val = next
          entries.val = current_entries
          anchor.children.clear()
          for entry in current_entries { anchor.children.push(entry.anchor) }
          match anchor.list_items {
            Some(scopes) => {
              scopes.clear()
              for entry in current_entries {
                scopes.push(scope_names_of_node(entry.anchor))
              }
            }
            None => ()
          }
          ignore(remember_node(anchor))
        })
      }) catch { _ => fn() {} })
    }
    pending_mounts.set(anchor.id, start)
    anchor.clrs.push(fn() {
      ignore(use_dom_state_inner(dom_state, fn() {
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

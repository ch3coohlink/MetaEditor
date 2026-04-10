let nid: Ref[Int] = Ref::new(1)
let css_nid: Ref[Int] = Ref::new(1)
let ns_html = "http://www.w3.org/1999/xhtml"
let ns_svg = "http://www.w3.org/2000/svg"
let ns_math = "http://www.w3.org/1998/Math/MathML"
let ns_code_html = 0
let ns_code_svg = 1
let ns_code_math = 2

// ====== 命令与基础类型 ======
pub let dom_cmd_create = 0
pub let dom_cmd_insert = 1
pub let dom_cmd_remove = 2
pub let dom_cmd_attr = 3
pub let dom_cmd_style = 4
pub let dom_cmd_prop = 5
pub let dom_cmd_listen = 6
pub let dom_root_body = 0
pub let dom_root_head = -1
pub(all) struct ListenPolicy {
  key: String?
  code: String?
  ctrl: Bool?
  shift: Bool?
  alt: Bool?
  meta: Bool?
  prevent: Bool
  stop: Bool
} derive(Eq, ToJson)
pub(all) struct ListenSpec {
  event: String
  capture: Bool
  passive: Bool
  prevent: Bool
  stop: Bool
  policies: Array[ListenPolicy]
} derive(Eq, ToJson)
pub(all) enum Cmd[I, S, V, B] {
  Create(I, S, S, V)
  Insert(I, I, I, B)
  Attr(I, S, V)
  Style(I, S, V)
  Prop(I, S, V)
  Remove(I)
  Listen(I, ListenSpec)
}
pub(all) enum DomValue {
  Empty
  String(String)
} derive(Eq)
pub impl ToJson for DomValue with to_json(self: DomValue) -> Json {
  match self {
    DomValue::Empty => null
    DomValue::String(value) => Json::string(value)
  }
}
pub type DomCmd = Cmd[Int, String, DomValue, Bool]
fn nullable_dom_string(value: String) -> DomValue {
  if value == "" { DomValue::Empty } else { DomValue::String(value) }
}
fn ns_code(ns: String) -> Int {
  if ns == ns_svg { ns_code_svg } else if ns == ns_math { ns_code_math } else { ns_code_html }
}
pub impl ToJson for DomCmd with to_json(self: DomCmd) -> Json {
  match self {
    Create(id, tag, ns, value) => {
      let items : Array[Json] = [dom_cmd_create.to_json(), id.to_json(), tag.to_json()]
      match value {
        DomValue::Empty => ()
        DomValue::String(text) => items.push(Json::string(text))
      }
      let code = ns_code(ns)
      if code != ns_code_html {
        if value == DomValue::Empty { items.push(null) }
        items.push(code.to_json())
      }
      Json::array(items)
    }
    Insert(pid, cid, rid, after) => {
      let items : Array[Json] = [dom_cmd_insert.to_json(), pid.to_json(), cid.to_json()]
      if rid != 0 || !after {
        items.push(rid.to_json())
      }
      if !after {
        items.push(false.to_json())
      }
      Json::array(items)
    }
    Attr(id, k, v) => (dom_cmd_attr, id, k, v).to_json()
    Style(id, k, v) => (dom_cmd_style, id, k, v).to_json()
    Prop(id, k, v) => (dom_cmd_prop, id, k, v).to_json()
    Remove(id) => (dom_cmd_remove, id).to_json()
    Listen(id, spec) => (dom_cmd_listen, id, spec).to_json()
  }
}
pub(all) struct VFrag {
  nodes: Array[VNode]
  mount: ((Int) -> Unit)?
}
pub(all) enum Child {
  Null
  Lazy((String) -> VFrag)
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
pub(all) struct Listener {
  spec: ListenSpec
  run: (EventData) -> Unit raise
}
pub(all) enum Prop {
  Empty
  S(String)
  D(() -> Prop)
  E(Listener)
}
pub fn on(
  run: (EventData) -> Unit raise,
  spec?: ListenSpec = { event: "", capture: false, passive: false, prevent: false, stop: false, policies: [] },
) -> Prop {
  E({ spec, run })
}
pub struct StyleSheet {
  id: String
  scope: String
  text: Cel[String]
}
// 键盘/输入事件数据，由 bridge 回传
pub(all) struct EventData {
  key: String          // 按键名（如 "a", "Enter", "ArrowUp"）
  code: String         // 物理键码（如 "KeyA", "Enter"）
  ctrl: Bool           // Ctrl 键
  shift: Bool          // Shift 键
  alt: Bool            // Alt 键
  meta: Bool           // Meta 键（Cmd/Win）
  client_x: Int        // 指针/鼠标事件的 clientX
  client_y: Int        // 指针/鼠标事件的 clientY
  button: Int          // 指针/鼠标事件的 button
  buttons: Int         // 指针/鼠标事件的 buttons
  pointer_id: Int      // PointerEvent 的 pointerId
  prevent: Bool        // 是否已 preventDefault
} derive(ToJson, FromJson)
pub fn EventData::default() -> EventData {
  {
    key: "",
    code: "",
    ctrl: false,
    shift: false,
    alt: false,
    meta: false,
    client_x: 0,
    client_y: 0,
    button: 0,
    buttons: 0,
    pointer_id: 0,
    prevent: false,
  }
}

// ====== 事件与属性辅助 ======
fn vnode_frag(node: VNode) -> VFrag {
  { nodes: [node], mount: None }
}
fn realize_frag_current(c: Child, ns~: String = ns_html) -> VFrag {
  match c {
    Lazy(f) => f(ns)
    _ => abort("not a child")
  }
}
fn activate_frag(frag: VFrag, mount_id: Int) -> VFrag {
  match frag.mount {
    Some(start) => {
      start(mount_id)
      { ..frag, mount: None }
    }
    None => frag
  }
}
fn realize_current(c: Child, ns~: String = ns_html) -> VNode {
  let frag = realize_frag_current(c, ns~)
  match frag.nodes {
    [node] => node
    _ => abort("root child must realize to exactly one node")
  }
}
pub fn realize_frag(state: DomState, c: Child) -> VFrag {
  use_dom_state_inner(state, fn() { realize_frag_current(c) })
}
pub fn realize(state: DomState, c: Child) -> VNode {
  let frag = realize_frag(state, c)
  match frag.nodes {
    [node] => node
    _ => abort("root child must realize to exactly one node")
  }
}
priv struct EventSlot {
  owner_id: Int
  handler: (EventData) -> Unit raise
}
fn listener_key(id: Int, event: String) -> String {
  "\{id}\n\{event}"
}
fn listener_base_event_name(key: String) -> String {
  match key.split(":").collect() {
    [base, .._] => base.to_string()
    _ => key
  }
}
fn listen_override_bool(base: Bool, flags: Array[String], key: String, disabled: String) -> Bool {
  let mut out = base
  for flag in flags {
    if flag == key {
      out = true
    } else if flag == disabled {
      out = false
    }
  }
  out
}
fn default_listen_spec(event: String) -> ListenSpec {
  match event {
    "onclick" | "ondblclick" | "onpointerdown" | "onpointerup" | "onpointermove" | "onkeydown" | "onkeyup" => {
      event,
      capture: false,
      passive: false,
      prevent: true,
      stop: false,
      policies: [],
    }
    _ => {
      event,
      capture: false,
      passive: false,
      prevent: false,
      stop: false,
      policies: [],
    }
  }
}
fn parse_listener_spec(key: String) -> ListenSpec {
  let parts = key.split(":").collect().map(fn(seg) { seg.to_string() })
  let event = listener_base_event_name(key)
  let flags: Array[String] = []
  for i = 1; i < parts.length(); i = i + 1 {
    flags.push(parts[i])
  }
  let spec = default_listen_spec(event)
  {
    ..spec,
    capture: listen_override_bool(spec.capture, flags, "capture", "no-capture"),
    passive: listen_override_bool(spec.passive, flags, "passive", "no-passive"),
    prevent: listen_override_bool(spec.prevent, flags, "prevent", "no-prevent"),
    stop: listen_override_bool(spec.stop, flags, "stop", "no-stop"),
  }
}
fn emit_listener_value(
  id: Int,
  key: String,
  listener: Listener,
  ui_id: String?,
  dom_state: DomState,
  listener_keys: Array[String],
) -> Unit {
  if ui_id is None { abort("interactive node requires ui-id") }
  let base = parse_listener_spec(key)
  let spec = if listener.spec.event == "" { { ..listener.spec, event: base.event } } else { listener.spec }
  if spec.event != base.event { abort("dynamic listener event cannot change") }
  let event_key = listener_key(id, spec.event)
  let mut seen = false
  for existing in listener_keys {
    if existing == event_key { seen = true }
  }
  if !seen { listener_keys.push(event_key) }
  event_handlers.set(event_key, {
    owner_id: id,
    handler: fn(ev) raise {
      ignore(use_dom_state_raise(dom_state, fn() raise { (listener.run)(ev) }))
    }
  })
  emit_current(Listen(id, spec))
}
fn validate_ui_id(raw: String) -> String {
  if raw.contains("/") || raw.contains(":") {
    panic()
  }
  raw
}
fn find_static_ui_id(attrs: Array[(String, Prop)]) -> String? {
  for pair in attrs {
    let (key, value) = pair
    if key == "ui-id" {
      match value {
        S(raw) => return Some(validate_ui_id(raw))
        _ => abort("ui-id must be static")
      }
    }
  }
  None
}
fn set_host_ui_id(target: Ref[String?], value: Prop, key: String) -> Unit {
  match value {
    S(raw) =>
      match target.val {
        Some(_) => abort("duplicate ui-id host attrs")
        None => target.val = Some(validate_ui_id(raw))
      }
    _ => abort("\{key} must be static")
  }
}
fn parse_static_flag(value: Prop) -> Bool {
  match value {
    S("false") => false
    _ => true
  }
}
priv struct UiHostAttrs {
  scope: Bool
  react: Bool
  list: Bool
}
fn take_ui_host_attrs(attrs: Array[(String, Prop)]) -> (Array[(String, Prop)], UiHostAttrs) {
  let plain: Array[(String, Prop)] = []
  let ui_id: Ref[String?] = Ref::new(None)
  let mut scope = false
  let mut react = false
  let mut list = false
  for pair in attrs {
    let (key, value) = pair
    match key {
      "ui-id" => set_host_ui_id(ui_id, value, key)
      "ui-id:scope" => {
        set_host_ui_id(ui_id, value, key)
        scope = true
      }
      "ui-id:list" => {
        set_host_ui_id(ui_id, value, key)
        list = true
      }
      "react:scope" => react = parse_static_flag(value)
      _ => plain.push(pair)
    }
  }
  match ui_id.val {
    Some(name) => plain.push(("ui-id", S(name)))
    None => ()
  }
  (plain, { scope, react, list })
}

// ====== 全局状态 ======
let event_handlers: Map[String, EventSlot] = Map::new()
let nodes_by_id: Map[Int, VNode] = Map::new()
let instance_mounts: Map[String, Int] = Map::new()
let registered_styles: Array[StyleSheet] = []
let cq: Array[DomCmd] = []
let current_dom_state: Ref[Option[DomState]] = Ref::new(None)
fn active_dom_state() -> DomState {
  match current_dom_state.val {
    Some(state) => state
    None => { next: nid, cmds: cq }
  }
}
fn dom_effect(dom_state: DomState, f: () -> Unit) -> (() -> Unit) {
  effect(fn() { use_dom_state_inner(dom_state, f) }) catch { _ => fn() {} }
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
  current_dom_state.val = None
  event_handlers.clear()
  nodes_by_id.clear()
  instance_mounts.clear()
  reset_reactive()
}
fn trigger_event(key: String, ev: EventData) -> Unit {
  match event_handlers.get(key) {
    Some({ handler: f, .. }) => {
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
    Some(id) => emit_current(Insert(parent_id, node_id, id, false))
    None => emit_current(Insert(parent_id, node_id, 0, true))
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
  if node.scope_names is Some(names) { refresh_names_map(names, node.children) }
  if node.list_items is Some(scopes) { refresh_list_items(scopes, node.children) }
  ignore(remember_node(node))
}
fn refresh_scope_chain(parent_id: Int?) -> Unit {
  let mut current = parent_id
  while true {
    if current is Some(id) {
      if nodes_by_id.get(id) is Some(node) {
        refresh_scope_owner(node)
        current = node.parent_id
        continue
      }
    }
    return
  }
}
priv enum QueryCursor {
  Node(Int)
  Scope(Map[String, Int])
}
fn resolve_local_name(node: VNode, part: String) -> Int? {
  match node.scope_names {
    Some(names) => {
      match names.get(part) {
        Some(value) => Some(value)
        None =>
          match node.ui_id {
            Some(name) => if name == part { Some(node.id) } else { None }
            None => None
          }
      }
    }
    None => {
      match node.ui_id {
        Some(name) => if name == part { Some(node.id) } else { None }
        None => None
      }
    }
  }
}
fn insert_root_by_id(roots: Array[VNode], node: VNode) -> Unit {
  let mut pos = roots.length()
  for i = 0; i < roots.length(); i = i + 1 {
    if roots[i].id > node.id {
      pos = i
      break
    }
  }
  roots.insert(pos, node)
}
fn query_roots() -> Array[VNode] {
  let roots: Array[VNode] = []
  for _, node in nodes_by_id {
    if node.parent_id is None {
      insert_root_by_id(roots, node)
    }
  }
  roots
}
fn resolve_query_root(part: String) -> Int? {
  for root in query_roots() {
    match resolve_local_name(root, part) {
      Some(id) => return Some(id)
      None =>
        match scope_names_of_node(root).get(part) {
          Some(id) => return Some(id)
          None => ()
        }
    }
  }
  None
}
fn resolve_query_parts_from(root_id: Int, parts: Array[String], start: Int) -> Int? {
  let cursor: Ref[QueryCursor] = Ref::new(Node(root_id))
  for i = start; i < parts.length(); i = i + 1 {
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
fn resolve_ui_query(query: String) -> Int? {
  let parts = query.split("/").collect().map(fn(part) { part.to_string() }).filter(part => part != "")
  if parts.length() == 0 { return None }
  match instance_mounts.get(parts[0]) {
    Some(id) =>
      if parts.length() == 1 { Some(id) } else { resolve_query_parts_from(id, parts, 1) }
    None => {
      let current = match resolve_query_root(parts[0]) {
        Some(id) => id
        None => return None
      }
      resolve_query_parts_from(current, parts, 1)
    }
  }
}
pub fn query_node(query: String) -> Int? { resolve_ui_query(query) }
pub fn trigger_node(id: Int, event: String) -> Unit {
  trigger_event(listener_key(id, event), EventData::default())
}
pub fn trigger_node_ev(id: Int, event: String, ev: EventData) -> Unit {
  trigger_event(listener_key(id, event), ev)
}
fn next_css_id(scope: String) -> String {
  let id = css_nid.val
  css_nid.val = id + 1
  "\{scope}-\{id}"
}
pub fn css(id: String, value: Prop) -> StyleSheet {
  let sheet = {
    id: next_css_id(id),
    scope: id,
    text: cel(""),
  }
  match value {
    S(text) => {
      sheet.text.set(css_scope_block(id, text))
      registered_styles.push(sheet)
      sheet
    }
    _ => abort("module css only accepts static string")
  }
}
pub fn StyleSheet::reset(self: StyleSheet, text: String) -> Unit {
  self.text.set(css_scope_block(self.scope, text))
}
pub fn realize_registered_styles(state: DomState) -> Array[VNode] {
  use_dom_state_inner(state, fn() {
    let nodes: Array[VNode] = []
    for sheet in registered_styles {
      let node = realize_current(h("style", [
        ("data-mbt-css", S(sheet.id)),
        ("react:scope", S("true"))
      ], [
        Dyn(fn() { Str(sheet.text.get()) })
      ]))
      nodes.push(node)
      emit_current(Insert(dom_root_head, node.id, 0, true))
    }
    nodes
  })
}

// ====== 基础节点与子树更新 ======
fn create_text_node(v: String) -> VNode { 
  let id = next_active_id(); emit_current(Create(id, "", "", DomValue::String(v)))
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
fn create_list_anchor(ui_id? : String? = None, expose_list? : Bool = true) -> VNode {
  let anchor = create_text_node("")
  let ui_id = ui_id.map(validate_ui_id)
  remember_node({ ..anchor, ui_id, list_items: if expose_list { Some([]) } else { None } })
}
fn create_list_host(
  ns: String,
  ui_id? : String? = None,
  expose_list? : Bool = true,
  wrap? : Bool = false,
  tag? : String = "div",
) -> VNode {
  if wrap {
    let attrs: Array[(String, Prop)] = []
    match ui_id {
      Some(name) => attrs.push(("ui-id", S(name)))
      None => ()
    }
    let node = realize_current(h(tag, attrs, []), ns = ns)
    remember_node({ ..node, list_items: if expose_list { Some([]) } else { None } })
  } else {
    create_list_anchor(ui_id~, expose_list~)
  }
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
  let keep_ids: Set[Int] = Set::new()
  for node in new_nodes { keep_ids.add(node.id) }
  for old in old_nodes {
    if !keep_ids.contains(old.id) {
      remove(old)
    }
  }
}
fn cleanup_nodes(nodes: Array[VNode]) -> Unit {
  for node in nodes {
    remove(node)
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
      let frag = f(ns)
      let mounted: Array[VNode] = []
      for node in frag.nodes {
        let n = remember_parent(node, Some(owner_id))
        ignore(mount_node_before(mount_id, n.id, anchor_opt))
        mounted.push(n)
        target_array.push(n)
      }
      ignore(activate_frag({ ..frag, nodes: mounted }, mount_id))
    }
    Str(s) => {
      let n = remember_parent(create_text_node(s), Some(owner_id))
      ignore(mount_node_before(mount_id, n.id, anchor_opt))
      target_array.push(n)
    }
    Int(i) => children(mount_id, owner_id, Str(i.to_string()), target_array, ns, anchor_opt)
    Arr(a) => {
      for child in a { children(mount_id, owner_id, child, target_array, ns, anchor_opt) }
    }
    Dyn(f) => {
      let dom_state = active_dom_state()
      let anchor = remember_parent({ ..create_list_anchor(), scope_names: Some(Map::new()) }, Some(owner_id))
      ignore(mount_node_before(mount_id, anchor.id, anchor_opt))
      target_array.push(anchor)
      
      let old_nodes: Ref[Array[VNode]] = Ref::new([])
      
      let stop_effect = dom_effect(dom_state, fn() {
        let new_vnodes = replace_owner_children(mount_id, anchor, ns, f())
        cleanup_removed_nodes(old_nodes.val, new_vnodes)
        old_nodes.val = new_vnodes
      })
      
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
  Lazy(fn(ns: String) -> VFrag {
    let dom_state = active_dom_state()
    let cur_ns = if ns == "" { ns_html } else { ns }
    let create_ns = if tag == "svg" { ns_svg } else if tag == "math" { ns_math } else { cur_ns }
    let child_ns = if tag == "foreignObject" { ns_html } else if tag == "svg" { ns_svg } else if tag == "math" { ns_math } else { cur_ns }
    let id = next_active_id(); emit_current(Create(id, tag, create_ns, DomValue::Empty))
    let ui_id = find_static_ui_id(attrs)
    let ui_class = ui_id.map(derived_ui_class)
    let listener_keys: Array[String] = []
    let action_names: Array[String] = []
    let my_clrs: Array[() -> Unit] = []
    let saw_class = Ref::new(false)
    attrs.each(fn(p) {
      let (k, v) = p
      match style_prop_name(k) {
        Some(style_key) =>
          match v {
            Empty => emit_current(Style(id, style_key, DomValue::Empty))
            S(s) => emit_current(Style(id, style_key, DomValue::String(s)))
            D(f) => {
              let stop = dom_effect(dom_state, fn() {
                match f() {
                  Empty => emit_current(Style(id, style_key, DomValue::Empty))
                  S(s) => emit_current(Style(id, style_key, DomValue::String(s)))
                  _ => abort("style property only accepts empty/string")
                }
              })
              my_clrs.push(stop)
            }
            _ => abort("style property only accepts empty/string")
          }
        None =>
          match prop_prop_name(k) {
            Some(prop_key) =>
              match v {
                Empty => emit_current(Prop(id, prop_key, DomValue::Empty))
                S(s) => emit_current(Prop(id, prop_key, nullable_dom_string(s)))
                D(f) => {
                  let stop = dom_effect(dom_state, fn() {
                    match f() {
                      Empty => emit_current(Prop(id, prop_key, DomValue::Empty))
                      S(s) => emit_current(Prop(id, prop_key, nullable_dom_string(s)))
                      _ => abort("property only accepts empty/string")
                    }
                  })
                  my_clrs.push(stop)
                }
                _ => abort("property only accepts empty/string")
              }
            None =>
              match v {
                Empty => {
                  if k == "class" { saw_class.val = true }
                  match ui_class {
                    Some(name) => emit_current(Attr(id, k, DomValue::String(name)))
                    None => emit_current(Attr(id, k, DomValue::Empty))
                  }
                }
                S(s) => {
                  if k == "class" { saw_class.val = true }
                  emit_current(Attr(
                    id,
                    k,
                    nullable_dom_string(if k == "class" { merge_class_name(s, ui_class) } else { s }),
                  ))
                }
                D(f) => {
                  if k == "ui-id" { abort("ui-id must be static") }
                  if k == "class" { saw_class.val = true }
                  let stop = effect(fn() {
                    use_dom_state_inner(dom_state, fn() {
                      match f() {
                        Empty =>
                          match ui_class {
                            Some(name) => emit_current(Attr(id, k, DomValue::String(name)))
                            None => emit_current(Attr(id, k, DomValue::Empty))
                          }
                        S(s) =>
                          emit_current(Attr(
                            id,
                            k,
                            nullable_dom_string(
                              if k == "class" { merge_class_name(s, ui_class) } else { s },
                            ),
                          ))
                        E(l) => emit_listener_value(id, k, l, ui_id, dom_state, listener_keys)
                        _ => abort("attribute only accepts empty/string/listener")
                      }
                    })
                  }) catch { _ => fn() {} }
                  my_clrs.push(stop)
                }
                E(l) => emit_listener_value(id, k, l, ui_id, dom_state, listener_keys)
              }
          }
      }
    })
    if !saw_class.val {
      match ui_class {
        Some(name) => emit_current(Attr(id, "class", DomValue::String(name)))
        None => ()
      }
    }
    let current_children: Array[VNode] = []
    for c in children_prop { children(id, id, c, current_children, child_ns, None) }
    vnode_frag(remember_node({
      id,
      parent_id: None,
      ui_id,
      listener_keys,
      action_names,
      clrs: my_clrs,
      children: current_children,
      scope_names: None,
      list_items: None,
    }))
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
  let (attach_stop, attach_scope, attach_list) = flags
  if (attach_scope || attach_list) && node.ui_id is None {
    abort("ui-id:scope/ui-id:list requires ui-id")
  }
  if attach_stop {
    match stop {
      Some(f) => node.clrs.push(f)
      None => ()
    }
  }
  let host = remember_node({
    ..node,
    scope_names: if attach_scope { Some(Map::new()) } else { None },
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
  let (f_stop, f_scope, f_list) = flags
  let stop = match handle {
    Some(scope) => Some(fn() { stop_scope(scope) })
    None => None
  }
  match child {
    Null => Lazy(fn(_ns: String) -> VFrag {
      vnode_frag(attach_scope_host(create_text_node(""), stop, flags))
    })
    Lazy(f) => Lazy(fn(ns: String) -> VFrag {
      let frag = match handle {
        Some(scope) => with_scope(scope, fn() { f(ns) }) catch { _ => panic() }
        None => f(ns)
      }
      match frag.nodes {
        [] => vnode_frag(attach_scope_host(create_text_node(""), stop, flags))
        [node, ..rest] => {
          let out: Array[VNode] = [attach_scope_host(node, stop, flags)]
          for item in rest { out.push(item) }
          { ..frag, nodes: out }
        }
      }
    })
    Str(s) => Lazy(fn(_ns: String) -> VFrag {
      vnode_frag(attach_scope_host(create_text_node(s), stop, flags))
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
      if f_stop || f_scope || f_list {
        Arr([
          Lazy(fn(_ns: String) -> VFrag {
            vnode_frag(attach_scope_host(create_text_node(""), stop, flags))
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
  if ui_host.scope || ui_host.react || ui_host.list {
    attach(child, handle, (ui_host.react, ui_host.scope, ui_host.list))
  } else {
    child
  }
}

pub fn mount_instance(instance: String, child: Child) -> Child {
  let instance = instance.trim().to_string()
  if instance == "" { abort("instance mount requires instance id") }
  Lazy(fn(ns: String) -> VFrag {
    let dom_state = active_dom_state()
    let anchor = remember_node({ ..create_text_node(""), scope_names: Some(Map::new()) })
    let start = fn(parent_id: Int) {
      ignore(use_dom_state_inner(dom_state, fn() {
        let anchor = current_node(anchor)
        instance_mounts.set(instance, anchor.id)
        ignore(replace_owner_children(parent_id, anchor, ns, child))
        ignore(remember_node(anchor))
      }))
    }
    anchor.clrs.push(fn() {
      match instance_mounts.get(instance) {
        Some(id) => if id == anchor.id { instance_mounts.remove(instance) }
        None => ()
      }
    })
    { nodes: [anchor], mount: Some(start) }
  })
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
    ignore(mount_node_before(parent_id, node.id, before_id))
  }
  ignore(mount_node_before(parent_id, anchor.id, before_id))
}
fn cleanup_item(anchor: VNode) -> Unit {
  for node in anchor.children {
    remove(node)
  }
  anchor.children.clear()
  remove(anchor)
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
pub fn[T: Eq + Hash] h_map(
  items: Array[T],
  f: (T, () -> Int) -> Child,
  ui_id? : String? = None,
  wrap? : Bool = false,
  tag? : String = "div"
) -> Child {
  h_map_dyn(fn() {
    let out: Array[(T, Int)] = []
    let i: Ref[Int] = Ref::new(0)
    for x in items {
      let n = i.val
      i.val = n + 1
      out.push((x, n))
    }
    out
  }, f, ui_id~, wrap~, tag~)
}
pub fn[T: Eq + Hash] h_map_dyn(
  items: () -> Array[(T, Int)],
  f: (T, () -> Int) -> Child,
  ui_id? : String? = None,
  wrap? : Bool = false,
  tag? : String = "div"
) -> Child {
  let cache: Ref[Map[T, Array[HMapEntry]]] = Ref::new(Map::new())
  Lazy(fn(ns: String) -> VFrag {
    let dom_state = active_dom_state()
    let wrapped = wrap || ui_id is Some(_) || tag != "div"
    let anchor = create_list_host(ns, ui_id~, expose_list=(ui_id is Some(_)), wrap=wrapped, tag=tag)
    let entries: Ref[Array[HMapEntry]] = Ref::new([])
    let stop_effect: Ref[(() -> Unit)?] = Ref::new(None)
    let start = fn(mount_id: Int) {
      stop_effect.val = Some(dom_effect(dom_state, fn() {
        let anchor = current_node(anchor)
        let item_parent_id = if wrapped { anchor.id } else { mount_id }
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
        let before_id = fn() -> Int? {
          if cursor.val < kept_order.length() {
            Some(item_first_mounted_id(kept_order[cursor.val].anchor))
          } else {
            if wrapped { None } else { Some(anchor.id) }
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
                move_item_before(item_parent_id, entry.anchor, before_id())
              }
              entry
            }
            None => {
              let idx = Ref::new(n)
              { anchor: realize_item(item_parent_id, ns, before_id(), f(x, fn() { idx.val })), idx }
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
      }))
    }
    anchor.clrs.push(fn() {
      ignore(use_dom_state_inner(dom_state, fn() {
        let anchor = current_node(anchor)
        if stop_effect.val is Some(stop) {
          let _ = stop()
          stop_effect.val = None
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
    { nodes: [anchor], mount: Some(start) }
  })
}

// ====== 清理与对外辅助 ======
fn recursive_cleanup(node: VNode) -> Unit {
  node.listener_keys.each(fn(key) {
    if event_handlers.get(key) is Some(slot) {
      if slot.owner_id == node.id { event_handlers.remove(key) }
    }
  })
  nodes_by_id.remove(node.id)
  node.clrs.each(fn(f) { f() })
  node.children.each(recursive_cleanup)
}
pub fn remove(node: VNode) -> Unit { 
  emit_current(Remove(node.id))
  recursive_cleanup(node)
}
pub fn init_bridge(
  state: DomState,
  sender: (Array[Json]) -> Unit,
  on_cmds? : (Array[DomCmd]) -> Unit = fn(_) {},
) -> Unit {
  let _ = on_post_flush(fn() { 
    let cs = get_cmds(state)
    if cs.length() > 0 {
      on_cmds(cs)
      sender(cs.map(fn(c) { c.to_json() }))
    }
  })
}

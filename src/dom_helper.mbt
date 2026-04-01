// ===== 测试状态 =====
let test_state : Ref[DomState] = Ref::new(new_dom_state())

fn reset_test_state() -> Unit {
  test_state.val = new_dom_state()
}

fn assert_realize(child: Child) -> VNode {
  realize(test_state.val, child)
}

fn assert_take_cmds() -> Array[DomCmd] {
  get_cmds(test_state.val)
}

// ===== 命令匹配 =====
fn is_remove(cmd: DomCmd, id: Int) -> Bool {
  match cmd {
    Remove(node_id) => node_id == id
    _ => false
  }
}

fn is_create(cmd: DomCmd, id: Int) -> Bool {
  match cmd {
    Create(node_id, _, _) => node_id == id
    _ => false
  }
}

fn is_insert_before(cmd: DomCmd, id: Int) -> Bool {
  match cmd {
    InsertBefore(_, child_id, _) => child_id == id
    _ => false
  }
}

fn find_text_node_id(cmds: Array[DomCmd], text: String) -> Int {
  for i = 0; i < cmds.length(); i = i + 1 {
    match cmds[i] {
      Text(id, value) => if value == text { return id }
      _ => ()
    }
  }
  panic()
}

fn find_parent_id(cmds: Array[DomCmd], child_id: Int) -> Int {
  for cmd in cmds {
    match cmd {
      Append(parent_id, id) => if id == child_id { return parent_id }
      InsertBefore(parent_id, id, _) => if id == child_id { return parent_id }
      _ => ()
    }
  }
  panic()
}

fn find_create_id(cmds: Array[DomCmd], tag: String) -> Int {
  for cmd in cmds {
    match cmd {
      Create(id, current, _) => if current == tag { return id }
      _ => ()
    }
  }
  panic()
}

// ===== 通用断言 =====
fn assert_no_cmd(cmds: Array[DomCmd], pred: (DomCmd) -> Bool) -> Unit {
  for cmd in cmds {
    if pred(cmd) { panic() }
  }
}

fn assert_has(cmds: Array[DomCmd], pred: (DomCmd) -> Bool) -> Unit {
  for cmd in cmds {
    if pred(cmd) { return }
  }
  panic()
}

fn find_child(nodes: Array[VNode], id: Int) -> VNode {
  for node in nodes {
    if node.id == id { return node }
  }
  panic()
}

// ===== 命令断言 =====
priv enum Pat[T] {
  Eq(T)
  Any
  Var(String)
}

type CmdPat = Cmd[Pat[Int], Pat[String]]

priv struct MatchEnv {
  ints: Map[String, Int]
  strs: Map[String, String]
}

fn[T] v(x: T) -> Pat[T] { Eq(x) }
fn[T] any() -> Pat[T] { Any }
fn id(name: String) -> Pat[Int] { Var(name) }
fn new_match_env() -> MatchEnv {
  { ints: Map::new(), strs: Map::new() }
}
fn get_int(env: MatchEnv, name: String) -> Int {
  match env.ints.get(name) {
    Some(value) => value
    None => panic()
  }
}
fn match_int(env: MatchEnv, pat: Pat[Int], value: Int) -> Bool {
  match pat {
    Eq(expect) => expect == value
    Any => true
    Var(name) =>
      match env.ints.get(name) {
        Some(expect) => expect == value
        None => {
          env.ints.set(name, value)
          true
        }
      }
  }
}

fn match_str(env: MatchEnv, pat: Pat[String], value: String) -> Bool {
  match pat {
    Eq(expect) => expect == value
    Any => true
    Var(name) =>
      match env.strs.get(name) {
        Some(expect) => expect == value
        None => {
          env.strs.set(name, value)
          true
        }
      }
  }
}

fn cmd_matches(env: MatchEnv, pat: CmdPat, cmd: DomCmd) -> Bool {
  match (pat, cmd) {
    (Create(idp, tagp, nsp), Create(id, tag, ns)) =>
      match_int(env, idp, id) &&
      match_str(env, tagp, tag) &&
      match_str(env, nsp, ns)
    (Text(idp, textp), Text(id, text)) =>
      match_int(env, idp, id) &&
      match_str(env, textp, text)
    (Attr(idp, kp, vp), Attr(id, k, v)) =>
      match_int(env, idp, id) &&
      match_str(env, kp, k) &&
      match_str(env, vp, v)
    (Append(pp, cp), Append(parent, child)) =>
      match_int(env, pp, parent) &&
      match_int(env, cp, child)
    (UpdateText(idp, textp), UpdateText(id, text)) =>
      match_int(env, idp, id) &&
      match_str(env, textp, text)
    (UpdateAttr(idp, kp, vp), UpdateAttr(id, k, v)) =>
      match_int(env, idp, id) &&
      match_str(env, kp, k) &&
      match_str(env, vp, v)
    (Remove(idp), Remove(id)) =>
      match_int(env, idp, id)
    (Listen(idp, evp, targetp), Listen(id, ev, target)) =>
      match_int(env, idp, id) &&
      match_str(env, evp, ev) &&
      match_str(env, targetp, target)
    (Action(namep, uidp), Action(name, uid)) =>
      match_str(env, namep, name) &&
      match_str(env, uidp, uid)
    (InsertBefore(pp, cp, rp), InsertBefore(parent, child, ref_id)) =>
      match_int(env, pp, parent) &&
      match_int(env, cp, child) &&
      match_int(env, rp, ref_id)
    (SetStyle(idp, kp, vp), SetStyle(id, k, v)) =>
      match_int(env, idp, id) &&
      match_str(env, kp, k) &&
      match_str(env, vp, v)
    (RemoveStyle(idp, kp), RemoveStyle(id, k)) =>
      match_int(env, idp, id) &&
      match_str(env, kp, k)
    (RemoveAttr(idp, kp), RemoveAttr(id, k)) =>
      match_int(env, idp, id) &&
      match_str(env, kp, k)
    (HostCmd(idp, cmdp), HostCmd(id, name)) =>
      match_int(env, idp, id) &&
      match_str(env, cmdp, name)
    (SetCss(idp, textp), SetCss(id, text)) =>
      match_str(env, idp, id) &&
      match_str(env, textp, text)
    (RemoveCss(idp), RemoveCss(id)) =>
      match_str(env, idp, id)
    _ => false
  }
}

fn assert_has_cmd(cmds: Array[DomCmd], pat: CmdPat) -> Unit {
  for cmd in cmds {
    let env = new_match_env()
    if cmd_matches(env, pat, cmd) { return }
  }
  panic()
}

fn assert_cmd(cmd: DomCmd, pat: CmdPat) -> MatchEnv {
  let env = new_match_env()
  if !cmd_matches(env, pat, cmd) { panic() }
  env
}

fn assert_cmds(cmds: Array[DomCmd], pats: Array[CmdPat]) -> MatchEnv {
  if cmds.length() != pats.length() { panic() }
  let env = new_match_env()
  for i = 0; i < cmds.length(); i = i + 1 {
    if !cmd_matches(env, pats[i], cmds[i]) { panic() }
  }
  env
}

fn assert_cmd_json(cmd: DomCmd, json: String) -> Unit {
  if dom_cmd_to_json(cmd) != json { panic() }
}

// ===== DOM 外围样式工具 =====
fn style_prop_name(key: String) -> String? {
  if key.length() <= 6 { return None }
  if key[:6].to_string() != "style:" { return None }
  Some(key[6:].to_string())
}

fn has_prefix(text: String, prefix: String) -> Bool {
  text.length() >= prefix.length() && text[:prefix.length()].to_string() == prefix
}

fn normalize_css_name(text: String) -> String {
  text.split(":").collect().map(seg => seg.to_string()).iter().join("-")
}

fn derived_ui_class(ui_id: String) -> String {
  let parts = ui_id.split("/").collect().map(seg => seg.to_string()).filter(seg => seg != "")
  if parts.length() == 0 { return "" }
  normalize_css_name(parts[parts.length() - 1])
}

fn merge_class_name(raw: String, derived: String?) -> String {
  match derived {
    Some(name) => if name == "" { raw } else if raw == "" { name } else { raw + " " + name }
    None => raw
  }
}

fn prefixed_css_selector(scope: String, selector: String) -> String {
  let selector = selector.trim().to_string()
  if selector == "" { return selector }
  if has_prefix(selector, "&") {
    "." + scope + selector[1:].to_string()
  } else {
    "." + scope + " " + selector
  }
}

fn prefix_css_selectors(scope: String, selector_text: String) -> String {
  selector_text
    .split(",")
    .collect()
    .map(seg => prefixed_css_selector(scope, seg.to_string()))
    .iter()
    .join(", ")
}

fn write_css_rule(out: StringBuilder, header: String, body: String) -> Unit {
  out.write_string(header)
  out.write_string("{")
  out.write_string(body)
  out.write_string("}")
}

fn scoped_css_header(scope: String, header: String) -> String {
  let trimmed = header.trim().to_string()
  if trimmed == "" { return header }
  if has_prefix(trimmed, "@media") || has_prefix(trimmed, "@supports") ||
    has_prefix(trimmed, "@container") || has_prefix(trimmed, "@layer") {
    return header
  }
  if has_prefix(trimmed, "@") { return header }
  prefix_css_selectors(scope, header)
}

fn css_scope_block(scope: String, text: String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  let len = text.length()
  while i < len {
    let mut open_idx = -1
    let mut scan = i
    while scan < len {
      let ch = text[scan:scan + 1].to_string()
      if ch == "{" {
        open_idx = scan
        scan = len
      } else {
        scan = scan + 1
      }
    }
    if open_idx < 0 {
      out.write_string(text[i:].to_string())
      i = len
    } else {
      let header = text[i:open_idx].to_string()
      let mut depth = 1
      let mut j = open_idx + 1
      while j < len && depth > 0 {
        let ch = text[j:j + 1].to_string()
        if ch == "{" {
          depth = depth + 1
        } else if ch == "}" {
          depth = depth - 1
        }
        j = j + 1
      }
      if depth > 0 {
        out.write_string(text[i:].to_string())
        i = len
      } else {
        let body = text[open_idx + 1:j - 1].to_string()
        let trimmed = header.trim().to_string()
        if trimmed == "" {
          write_css_rule(out, header, body)
        } else if has_prefix(trimmed, "@media") || has_prefix(trimmed, "@supports") ||
          has_prefix(trimmed, "@container") || has_prefix(trimmed, "@layer") {
          write_css_rule(out, header, css_scope_block(scope, body))
        } else if has_prefix(trimmed, "@") {
          write_css_rule(out, header, body)
        } else {
          write_css_rule(out, scoped_css_header(scope, header), body)
        }
        i = j
      }
    }
  }
  out.to_string()
}

fn emit_style_attr(id: Int, key: String, value: String) -> Unit {
  if value == "" {
    emit_current(RemoveStyle(id, key))
  } else {
    emit_current(SetStyle(id, key, value))
  }
}

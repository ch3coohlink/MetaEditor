// ===== 测试状态 =====
let test_state : Ref[DomState] = Ref::new(new_dom_state())

fn reset_test_state() -> Unit {
  reset_ui()
  reset_host_tray()
  test_state.val = new_dom_state()
}

fn assert_realize(child: Child) -> VNode {
  realize(test_state.val, child)
}

fn assert_take_cmds() -> Array[DomCmd] {
  get_cmds(test_state.val)
}

fn test_scope(f: () -> Unit raise) -> (() -> Unit) {
  no_raise(() => scope(f))
}

fn flush_cmds() -> Array[DomCmd] {
  no_raise(flush)
  assert_take_cmds()
}

fn mount_test_root(child: Child) -> VNode {
  ignore(realize_registered_styles(test_state.val))
  let node = assert_realize(child)
  emit(test_state.val, Append(dom_root_body, node.id))
  node
}

// ===== 通用断言 =====
priv enum Pat[T] {
  Eq(T)
  Any
  Var(String)
}

type CmdPat = Cmd[Pat[Int], Pat[String], Pat[DomValue]]

priv struct MatchEnv {
  ints: Map[String, Int]
  strs: Map[String, String]
}

fn[T] v(x: T) -> Pat[T] { Eq(x) }
fn[T] any() -> Pat[T] { Any }
fn id(name: String) -> Pat[Int] { Var(name) }
fn listen_spec(
  event: String,
  capture?: Bool = false,
  passive?: Bool = false,
  prevent?: Bool = false,
  stop?: Bool = false,
) -> ListenSpec {
  { event, capture, passive, prevent, stop, policies: [] }
}
fn new_match_env() -> MatchEnv {
  { ints: Map::new(), strs: Map::new() }
}
fn[T: Eq] match_val(m: Map[String, T], pat: Pat[T], value: T) -> Bool {
  match pat {
    Eq(expect) => expect == value
    Any => true
    Var(name) =>
      match m.get(name) {
        Some(expect) => expect == value
        None => {
          m.set(name, value)
          true
        }
      }
  }
}
fn[T] get_val(m: Map[String, T], name: String) -> T {
  match m.get(name) {
    Some(value) => value
    None => panic()
  }
}
fn get_int(env: MatchEnv, name: String) -> Int { get_val(env.ints, name) }

fn match_int(env: MatchEnv, pat: Pat[Int], value: Int) -> Bool {
  match_val(env.ints, pat, value)
}
fn match_str(env: MatchEnv, pat: Pat[String], value: String) -> Bool {
  match_val(env.strs, pat, value)
}
fn match_dom_value(pat: Pat[DomValue], value: DomValue) -> Bool {
  match pat {
    Eq(expect) => expect == value
    Any => true
    Var(_) => panic()
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
      match_dom_value(vp, v)
    (Style(idp, kp, vp), Style(id, k, v)) =>
      match_int(env, idp, id) &&
      match_str(env, kp, k) &&
      match_dom_value(vp, v)
    (Prop(idp, kp, vp), Prop(id, k, v)) =>
      match_int(env, idp, id) &&
      match_str(env, kp, k) &&
      match_dom_value(vp, v)
    (Append(pp, cp), Append(parent, child)) =>
      match_int(env, pp, parent) &&
      match_int(env, cp, child)
    (Remove(idp), Remove(id)) =>
      match_int(env, idp, id)
    (Listen(idp, evp), Listen(id, ev)) =>
      match_int(env, idp, id) &&
      evp == ev
    (InsertBefore(pp, cp, rp), InsertBefore(parent, child, ref_id)) =>
      match_int(env, pp, parent) &&
      match_int(env, cp, child) &&
      match_int(env, rp, ref_id)
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

fn assert_no_cmd(cmds: Array[DomCmd], pat: CmdPat) -> Unit {
  for cmd in cmds {
    let env = new_match_env()
    if cmd_matches(env, pat, cmd) { panic() }
  }
}

fn find_cmd(cmds: Array[DomCmd], pat: CmdPat) -> MatchEnv {
  for cmd in cmds {
    let env = new_match_env()
    if cmd_matches(env, pat, cmd) { return env }
  }
  panic()
}

fn find_text_mount(cmds: Array[DomCmd], text: String) -> (Int, Int) {
  let env = find_cmd(cmds, Text(id("text"), v(text)))
  let text_id = get_int(env, "text")
  let parent_id = get_int(find_cmd(cmds, Append(id("parent"), v(text_id))), "parent")
  (parent_id, text_id)
}

fn find_style_mount(cmds: Array[DomCmd], css_id: String, text: String) -> (Int, Int) {
  let env = find_cmd(cmds, Attr(id("style"), v("data-mbt-css"), v(DomValue::String(css_id))))
  let style_id = get_int(env, "style")
  let text_id = get_int(find_cmd(cmds, Text(id("text"), v(text))), "text")
  ignore(find_cmd(cmds, Append(v(dom_root_head), v(style_id))))
  (style_id, text_id)
}

fn count_cmds(cmds: Array[DomCmd], pat: CmdPat) -> Int {
  let mut n = 0
  for cmd in cmds {
    let env = new_match_env()
    if cmd_matches(env, pat, cmd) { n = n + 1 }
  }
  n
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
  if cmd.to_json().stringify() != json { panic() }
}

fn cmd_json(tag: Int, body: String) -> String {
  "[\{tag},\{body}]"
}

// ===== DOM 外围样式工具 =====
fn style_prop_name(key: String) -> String? {
  if !has_prefix(key, "style:") { return None }
  Some(key[6:].to_string())
}
fn prop_prop_name(key: String) -> String? {
  if !has_prefix(key, "prop:") { return None }
  Some(key[5:].to_string())
}

fn normalize_css_name(text: String) -> String {
  text.split(":").collect().map(seg => seg.to_string()).iter().join("-")
}

fn derived_ui_class(ui_id: String) -> String {
  normalize_css_name(ui_id)
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

fn split_css_selector_list(text: String) -> Array[String] {
  let out : Array[String] = []
  let mut start = 0
  let mut i = 0
  let len = text.length()
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut quote = ""
  while i < len {
    let ch = text[i:i + 1].to_string()
    if quote != "" {
      if ch == "\\" && i + 1 < len {
        i = i + 2
      } else {
        if ch == quote {
          quote = ""
        }
        i = i + 1
      }
    } else if ch == "\"" || ch == "'" {
      quote = ch
      i = i + 1
    } else if ch == "(" {
      paren_depth = paren_depth + 1
      i = i + 1
    } else if ch == ")" {
      if paren_depth > 0 { paren_depth = paren_depth - 1 }
      i = i + 1
    } else if ch == "[" {
      bracket_depth = bracket_depth + 1
      i = i + 1
    } else if ch == "]" {
      if bracket_depth > 0 { bracket_depth = bracket_depth - 1 }
      i = i + 1
    } else if ch == "," && paren_depth == 0 && bracket_depth == 0 {
      out.push(text[start:i].to_string())
      start = i + 1
      i = i + 1
    } else {
      i = i + 1
    }
  }
  out.push(text[start:].to_string())
  out
}

fn prefix_css_selectors(scope: String, selector_text: String) -> String {
  let selectors : Array[String] = []
  for seg in split_css_selector_list(selector_text) {
    selectors.push(prefixed_css_selector(scope, seg))
  }
  selectors.iter().join(", ")
}

fn write_css_rule(out: StringBuilder, header: String, body: String) -> Unit {
  out.write_string(header)
  out.write_string("{")
  out.write_string(body)
  out.write_string("}")
  out.write_string("\n")
}

fn is_recursive_css_at_rule(header: String) -> Bool {
  let trimmed = header.trim().to_string()
  has_prefix(trimmed, "@media") || has_prefix(trimmed, "@supports") ||
  has_prefix(trimmed, "@container") || has_prefix(trimmed, "@layer")
}

fn scoped_css_header(scope: String, header: String) -> String {
  let trimmed = header.trim().to_string()
  if trimmed == "" { return header }
  if is_recursive_css_at_rule(trimmed) {
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
          write_css_rule(out, "." + scope, body)
        } else if is_recursive_css_at_rule(trimmed) {
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

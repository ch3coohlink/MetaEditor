// ===== 测试状态 =====
let test_dom_state : Ref[DomState] = Ref::new(new_dom_state())

fn assert_reset_dom() -> Unit {
  test_dom_state.val = new_dom_state()
}

fn assert_realize(child: Child) -> VNode {
  realize(test_dom_state.val, child)
}

fn assert_take_cmds() -> Array[DomCmd] {
  get_cmds(test_dom_state.val)
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

fn assert_text(cmd: DomCmd, text: String) -> Unit {
  match cmd {
    Text(_, value) => if value != text { panic() }
    _ => panic()
  }
}

fn assert_create(cmd: DomCmd, tag: String, ns: String) -> Int {
  match cmd {
    Create(id, t, n) => {
      if t != tag { panic() }
      if ns != "" && n != ns { panic() }
      id
    }
    _ => panic()
  }
}

fn assert_attr(cmd: DomCmd, key: String, value: String) -> Unit {
  match cmd {
    Attr(_, k, v) => {
      if k != key { panic() }
      if v != value { panic() }
    }
    _ => panic()
  }
}

fn assert_append(cmd: DomCmd, parent_id: Int, child_id: Int) -> Unit {
  match cmd {
    Append(p, c) => {
      if p != parent_id { panic() }
      if c != child_id { panic() }
    }
    _ => panic()
  }
}

fn assert_listen(cmd: DomCmd, ev: String, node_id: Int, ui_id: String) -> Unit {
  match cmd {
    Listen(id, name, target) => {
      if id != node_id { panic() }
      if name != ev { panic() }
      if target != ui_id { panic() }
    }
    _ => panic()
  }
}

fn assert_update_attr(cmd: DomCmd, key: String, value: String) -> Unit {
  match cmd {
    UpdateAttr(_, k, v) => {
      if k != key { panic() }
      if v != value { panic() }
    }
    _ => panic()
  }
}

fn find_child(nodes: Array[VNode], id: Int) -> VNode {
  for node in nodes {
    if node.id == id { return node }
  }
  panic()
}

// ===== 常见命令断言 =====
priv enum CmdPattern {
  Attr(Int, String, String)
  Append(Int, Int)
  Listen(Int, String, String)
  AnyRemove
  Remove(Int)
  Text(String)
  SetStyle(String, String)
  RemoveStyle(String)
  SetCss(String, String)
  RemoveCss(String)
  HostCmd(Int, String)
}

fn cmd_matches(cmd: DomCmd, pattern: CmdPattern) -> Bool {
  match pattern {
    Attr(expect_id, expect_key, expect_value) =>
      match cmd {
        Attr(id, key, value) => id == expect_id && key == expect_key && value == expect_value
        _ => false
      }
    Append(expect_parent, expect_child) =>
      match cmd {
        Append(parent, child) => parent == expect_parent && child == expect_child
        _ => false
      }
    Listen(expect_id, expect_name, expect_target) =>
      match cmd {
        Listen(id, name, target) =>
          id == expect_id && name == expect_name && target == expect_target
        _ => false
      }
    AnyRemove =>
      match cmd {
        Remove(_) => true
        _ => false
      }
    Remove(expect_id) =>
      match cmd {
        Remove(id) => id == expect_id
        _ => false
      }
    Text(expect_text) =>
      match cmd {
        Text(_, value) => value == expect_text
        _ => false
      }
    SetStyle(expect_key, expect_value) =>
      match cmd {
        SetStyle(_, key, value) => key == expect_key && value == expect_value
        _ => false
      }
    RemoveStyle(expect_key) =>
      match cmd {
        RemoveStyle(_, key) => key == expect_key
        _ => false
      }
    SetCss(expect_id, expect_text) =>
      match cmd {
        SetCss(id, text) => id == expect_id && text == expect_text
        _ => false
      }
    RemoveCss(expect_id) =>
      match cmd {
        RemoveCss(id) => id == expect_id
        _ => false
      }
    HostCmd(expect_id, expect_name) =>
      match cmd {
        HostCmd(id, name) => id == expect_id && name == expect_name
        _ => false
      }
  }
}

fn assert_has_remove(cmds: Array[DomCmd], id: Int) -> Unit {
  assert_has(cmds, cmd => cmd_matches(cmd, Remove(id)))
}

fn assert_has_any_remove(cmds: Array[DomCmd]) -> Unit {
  assert_has(cmds, cmd => cmd_matches(cmd, AnyRemove))
}

fn assert_has_text_cmd(cmds: Array[DomCmd], text: String) -> Unit {
  assert_has(cmds, cmd => cmd_matches(cmd, Text(text)))
}

fn assert_has_cmd(cmds: Array[DomCmd], pattern: CmdPattern) -> Unit {
  assert_has(cmds, cmd => cmd_matches(cmd, pattern))
}

fn assert_cmd(cmd: DomCmd, pattern: CmdPattern) -> Unit {
  if !cmd_matches(cmd, pattern) { panic() }
}

fn assert_cmd_json(cmd: DomCmd, json: String) -> Unit {
  if cmd.to_json() != json { panic() }
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

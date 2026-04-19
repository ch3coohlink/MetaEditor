enum Expr {
  Ref(String)
  Tok(String)
  Lit(String)
  Range(UInt16, UInt16)
  NoneCharOf(Array[UInt16])
  Lex(Expr)
  Chain(Array[Expr])
  OneOf(Array[Expr])
  Repeat(Expr)
  Repeat1(Expr)
  Maybe(Expr)
  Omit(Expr)
}

struct TokenInfo {
  expr: Expr
  emit_node: Bool
}

struct Grammar {
  tokens: Map[String, TokenInfo]
  rules: Map[String, Expr]
  start: String
}

struct ParserSpec {
  prefix: String
  file_stem: String
  parser_fn: String
  grammar: Grammar
  valid_input: String
  invalid_input: String
  root_invalid_input: String
}

struct Emitter {
  grammar: Grammar
  parser_type: String
  match_type: String
  mut next_id: Int
  methods: Array[String]
  token_methods: Map[String, String]
}

fn q(s: String) -> String {
  s.to_json().stringify()
}

fn nums(xs: Array[UInt16]) -> String {
  let body = xs.iter().map(x => x.to_string()).join(", ")
  "[\{body}]"
}

fn tok(expr: Expr, emit_node~: Bool = false) -> TokenInfo {
  { expr, emit_node }
}

fn expect_expr(expr: Expr) -> String {
  match expr {
    Ref(name) => name
    Tok(name) => name
    Lit(text) => text
    Range(lo, hi) => "char \{lo}-\{hi}"
    NoneCharOf(_) => "char"
    Lex(inner) => expect_expr(inner)
    Chain(items) => if items.length() == 0 { "sequence" } else { expect_expr(items[0]) }
    OneOf(items) => items.iter().map(expect_expr).join(" | ")
    Repeat(inner) => expect_expr(inner)
    Repeat1(inner) => expect_expr(inner)
    Maybe(inner) => expect_expr(inner)
    Omit(inner) => expect_expr(inner)
  }
}

pub fn parser_specs() -> Array[ParserSpec] {
  [
    {
      prefix: "Json",
      file_stem: "json",
      parser_fn: "json_parser",
      grammar: json_grammar(),
      valid_input: "{\"a\": [1, true]}",
      invalid_input: "{\"a\": [1, 2, }",
      root_invalid_input: "?",
    },
    {
      prefix: "Kv",
      file_stem: "kv",
      parser_fn: "kv_parser",
      grammar: kv_grammar(),
      valid_input: "theme=dark,features=[spell,lint]",
      invalid_input: "theme=dark,features=[spell,]",
      root_invalid_input: "?",
    },
  ]
}

fn Emitter::fresh(self: Emitter) -> String {
  let id = self.next_id
  self.next_id = id + 1
  "p\{id}"
}

fn Emitter::push(self: Emitter, body: String) -> Unit {
  self.methods.push(body)
}

fn match_fail() -> String {
  "{ ok: false, nodes: [] }"
}

fn match_ok(nodes~: String = "[]") -> String {
  "{ ok: true, nodes: \{nodes} }"
}

fn call_method(parser_type: String, match_type: String, name: String, body: String) -> String {
  "fn \{parser_type}::\{name}(self: \{parser_type}) -> \{match_type} {\n\{body}\n}"
}

fn chain_method(
  parser_type: String,
  match_type: String,
  name: String,
  parts: Array[String],
  expects: Array[String],
) -> String {
  let ret = match_ok(nodes="nodes")
  let lines: Array[String] = [
    "fn \{parser_type}::\{name}(self: \{parser_type}) -> \{match_type} {",
    "  let start = self.i",
    "  let nodes: Array[GenAst] = []",
  ]
  for i in 0..<parts.length() {
    let part = parts[i]
    let expect = expects[i]
    let msg = q("expected " + expect)
    lines.push("  let m = self.\{part}()")
    lines.push("  if !m.ok {")
    lines.push("    if self.i > start || nodes.length() > 0 {")
    lines.push("      nodes.push(self.gen_recover(\{msg}))")
    lines.push("    } else {")
    lines.push("      self.i = start")
    lines.push("      return \{match_fail()}")
    lines.push("    }")
    lines.push("  } else {")
    lines.push("    for node in m.nodes { nodes.push(node) }")
    lines.push("  }")
  }
  lines.push("  \{ret}")
  lines.push("}")
  lines.iter().join("\n")
}

fn oneof_method(parser_type: String, match_type: String, name: String, parts: Array[String]) -> String {
  let lines: Array[String] =
    ["fn \{parser_type}::\{name}(self: \{parser_type}) -> \{match_type} {", "  let start = self.i"]
  for part in parts {
    lines.push("  let m = self.\{part}()")
    lines.push("  if m.ok { return m }")
    lines.push("  self.i = start")
  }
  lines.push("  \{match_fail()}")
  lines.push("}")
  lines.iter().join("\n")
}

fn repeat_method(parser_type: String, match_type: String, name: String, part: String) -> String {
  let ret = match_ok(nodes="nodes")
  [
    "fn \{parser_type}::\{name}(self: \{parser_type}) -> \{match_type} {",
    "  let nodes: Array[GenAst] = []",
    "  while true {",
    "    let start = self.i",
    "    let m = self.\{part}()",
    "    if !m.ok { self.i = start; break }",
    "    for node in m.nodes { nodes.push(node) }",
    "    if self.i == start { break }",
    "  }",
    "  \{ret}",
    "}",
  ].iter().join("\n")
}

fn repeat1_method(parser_type: String, match_type: String, name: String, part: String) -> String {
  let ret = match_ok(nodes="nodes")
  [
    "fn \{parser_type}::\{name}(self: \{parser_type}) -> \{match_type} {",
    "  let start = self.i",
    "  let first = self.\{part}()",
    "  if !first.ok { self.i = start; return \{match_fail()} }",
    "  let nodes = first.nodes",
    "  while true {",
    "    let again = self.i",
    "    let m = self.\{part}()",
    "    if !m.ok { self.i = again; break }",
    "    for node in m.nodes { nodes.push(node) }",
    "    if self.i == again { break }",
    "  }",
    "  \{ret}",
    "}",
  ].iter().join("\n")
}

fn maybe_method(parser_type: String, match_type: String, name: String, part: String) -> String {
  [
    "fn \{parser_type}::\{name}(self: \{parser_type}) -> \{match_type} {",
    "  let start = self.i",
    "  let m = self.\{part}()",
    "  if !m.ok { self.i = start; return \{match_ok()} }",
    "  m",
    "}",
  ].iter().join("\n")
}

fn omit_method(parser_type: String, match_type: String, name: String, part: String) -> String {
  [
    "fn \{parser_type}::\{name}(self: \{parser_type}) -> \{match_type} {",
    "  let m = self.\{part}()",
    "  if !m.ok { return \{match_fail()} }",
    "  \{match_ok()}",
    "}",
  ].iter().join("\n")
}

fn node_method(parser_type: String, match_type: String, name: String, label: String, part: String) -> String {
  let node = "[{ type_: \{q(label)}, c: m.nodes, s: start, e: self.i }]"
  let ret = match_ok(nodes=node)
  [
    "fn \{parser_type}::\{name}(self: \{parser_type}) -> \{match_type} {",
    "  let start = self.i",
    "  let m = self.\{part}()",
    "  if !m.ok { self.i = start; return \{match_fail()} }",
    "  \{ret}",
    "}",
  ].iter().join("\n")
}

fn Emitter::emit_expr(self: Emitter, expr: Expr) -> String {
  match expr {
    Ref(name) => "gen_parse_\{name}"
    Tok(name) => self.emit_token(name)
    Lit(text) => {
      let id = self.fresh()
      let ok = match_ok()
      let fail = match_fail()
      self.push(call_method(
        self.parser_type,
        self.match_type,
        id,
        "  if self.gen_eat(\{q(text)}) { \{ok} } else { \{fail} }",
      ))
      id
    }
    Range(lo, hi) => {
      let id = self.fresh()
      let ok = match_ok()
      let fail = match_fail()
      self.push(call_method(
        self.parser_type,
        self.match_type,
        id,
        "  if self.gen_take_range(\{lo}, \{hi}) { \{ok} } else { \{fail} }",
      ))
      id
    }
    NoneCharOf(chars) => {
      let id = self.fresh()
      let ok = match_ok()
      let fail = match_fail()
      self.push(call_method(
        self.parser_type,
        self.match_type,
        id,
        "  if self.gen_take_none_of(\{nums(chars)}) { \{ok} } else { \{fail} }",
      ))
      id
    }
    Lex(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(call_method(self.parser_type, self.match_type, id, [
        "  let start = self.i",
        "  self.gen_skip_ws()",
        "  let m = self.\{part}()",
        "  if m.ok { return m }",
        "  self.i = start",
        "  \{match_fail()}",
      ].iter().join("\n")))
      id
    }
    Omit(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(omit_method(self.parser_type, self.match_type, id, part))
      id
    }
    Chain(items) => {
      let id = self.fresh()
      let parts: Array[String] = []
      let expects: Array[String] = []
      for item in items {
        parts.push(self.emit_expr(item))
        expects.push(expect_expr(item))
      }
      self.push(chain_method(self.parser_type, self.match_type, id, parts, expects))
      id
    }
    OneOf(items) => {
      let id = self.fresh()
      let parts: Array[String] = []
      for item in items {
        parts.push(self.emit_expr(item))
      }
      self.push(oneof_method(self.parser_type, self.match_type, id, parts))
      id
    }
    Repeat(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(repeat_method(self.parser_type, self.match_type, id, part))
      id
    }
    Repeat1(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(repeat1_method(self.parser_type, self.match_type, id, part))
      id
    }
    Maybe(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(maybe_method(self.parser_type, self.match_type, id, part))
      id
    }
  }
}

fn Emitter::emit_token(self: Emitter, name: String) -> String {
  match self.token_methods.get(name) {
    Some(id) => id
    None => {
      let id = self.fresh()
      self.token_methods[name] = id
      let info = self.grammar.tokens[name]
      let part = self.emit_expr(info.expr)
      self.push(if info.emit_node {
        node_method(self.parser_type, self.match_type, id, name, part)
      } else {
        call_method(self.parser_type, self.match_type, id, "  self.\{part}()")
      })
      id
    }
  }
}

fn rule_method(parser_type: String, match_type: String, name: String, part: String) -> String {
  let node = "[{ type_: \{q(name)}, c: m.nodes, s: start, e: self.i }]"
  let ret = match_ok(nodes=node)
  [
    "fn \{parser_type}::gen_parse_\{name}(self: \{parser_type}) -> \{match_type} {",
    "  let start = self.i",
    "  let m = self.\{part}()",
    "  if !m.ok { self.i = start; return \{match_fail()} }",
    "  \{ret}",
    "}",
  ].iter().join("\n")
}

pub fn generate_parser_source(spec: ParserSpec) -> String {
  let grammar = spec.grammar
  let parser_type = spec.prefix + "Parser"
  let match_type = spec.prefix + "Match"
  let ws_prefix = spec.file_stem + "_gen"
  let emitter = {
    grammar,
    parser_type,
    match_type,
    next_id: 0,
    methods: [],
    token_methods: {},
  }
  for name, expr in grammar.rules {
    let part = emitter.emit_expr(expr)
    emitter.push(rule_method(parser_type, match_type, name, part))
  }
  let methods = emitter.methods.iter().join("\n\n")
  [
    "priv struct \{match_type} { ok: Bool; nodes: Array[GenAst] }",
    "",
    "let \{ws_prefix}_ch_ws: UInt16 = 32",
    "let \{ws_prefix}_ch_nl: UInt16 = 10",
    "let \{ws_prefix}_ch_cr: UInt16 = 13",
    "let \{ws_prefix}_ch_tab: UInt16 = 9",
    "",
    "priv struct \{parser_type} { input: String; len: Int; mut i: Int; diagnostics: Array[GenDiag] }",
    "",
    "fn \{parser_type}::gen_skip_ws(self: \{parser_type}) -> Unit {",
    "  while self.i < self.len {",
    "    let ch = self.input[self.i]",
    "    if ch == \{ws_prefix}_ch_ws || ch == \{ws_prefix}_ch_nl || ch == \{ws_prefix}_ch_cr || ch == \{ws_prefix}_ch_tab {",
    "      self.i = self.i + 1",
    "    } else {",
    "      break",
    "    }",
    "  }",
    "}",
    "",
    "fn \{parser_type}::gen_eat(self: \{parser_type}, text: String) -> Bool {",
    "  let n = text.length()",
    "  if self.i + n > self.len { return false }",
    "  for j in 0..<n {",
    "    if self.input[self.i + j] != text[j] { return false }",
    "  }",
    "  self.i = self.i + n",
    "  true",
    "}",
    "",
    "fn \{parser_type}::gen_take_range(self: \{parser_type}, lo: UInt16, hi: UInt16) -> Bool {",
    "  if self.i >= self.len { return false }",
    "  let ch = self.input[self.i]",
    "  if lo <= ch && ch <= hi {",
    "    self.i = self.i + 1",
    "    true",
    "  } else {",
    "    false",
    "  }",
    "}",
    "",
    "fn \{parser_type}::gen_take_none_of(self: \{parser_type}, chars: Array[UInt16]) -> Bool {",
    "  if self.i >= self.len { return false }",
    "  let ch = self.input[self.i]",
    "  for bad in chars {",
    "    if ch == bad { return false }",
    "  }",
    "  self.i = self.i + 1",
    "  true",
    "}",
    "",
    "fn \{parser_type}::gen_diag(self: \{parser_type}, msg: String, s: Int, e: Int) -> Unit {",
    "  self.diagnostics.push({ msg, s, e })",
    "}",
    "",
    "fn \{parser_type}::gen_missing(self: \{parser_type}, msg: String, at: Int) -> GenAst {",
    "  self.gen_diag(msg, at, at)",
    "  { type_: \"missing\", c: [], s: at, e: at }",
    "}",
    "",
    "fn \{parser_type}::gen_error(self: \{parser_type}, msg: String, s: Int, e: Int) -> GenAst {",
    "  self.gen_diag(msg, s, e)",
    "  { type_: \"error\", c: [], s, e }",
    "}",
    "",
    "fn \{parser_type}::gen_should_insert_missing(self: \{parser_type}) -> Bool {",
    "  if self.i >= self.len { return true }",
    "  let ch = self.input[self.i]",
    "  ch == 44 || ch == 58 || ch == 93 || ch == 125",
    "}",
    "",
    "fn \{parser_type}::gen_recover(self: \{parser_type}, msg: String) -> GenAst {",
    "  if self.gen_should_insert_missing() {",
    "    return self.gen_missing(msg, self.i)",
    "  }",
    "  let s = self.i",
    "  self.i = self.i + 1",
    "  self.gen_error(msg, s, self.i)",
    "}",
    "",
    methods,
    "",
    "fn \{spec.parser_fn}_tolerant(input: String) -> GenParseResult {",
    "  let p: \{parser_type} = { input, len: input.length(), i: 0, diagnostics: [] }",
    "  let m = p.gen_parse_\{grammar.start}()",
    "  let nodes = m.nodes",
    "  if !m.ok {",
    "    nodes.push(p.gen_recover(\"expected \{grammar.start}\"))",
    "  }",
    "  p.gen_skip_ws()",
    "  if p.i < p.len {",
    "    let s = p.i",
    "    p.i = p.len",
    "    nodes.push(p.gen_error(\"unexpected trailing input\", s, p.len))",
    "  }",
    "  let ast = if nodes.length() == 0 {",
    "    None",
    "  } else if nodes.length() == 1 {",
    "    Some(nodes[0])",
    "  } else {",
    "    Some({ type_: \"\{grammar.start}\", c: nodes, s: 0, e: p.i })",
    "  }",
    "  let ok = m.ok && p.diagnostics.length() == 0 && p.i == p.len && nodes.length() == 1",
    "  { ok, end: p.i, ast, diagnostics: p.diagnostics }",
    "}",
    "",
    "pub fn \{spec.parser_fn}(input: String, mode: ParseMode) -> GenParseResult {",
    "  let res = \{spec.parser_fn}_tolerant(input)",
    "  match mode {",
    "    Tolerant => res",
    "    Strict => if res.ok { res } else {",
    "      { ok: false, end: res.end, ast: None, diagnostics: res.diagnostics }",
    "    }",
    "  }",
    "}",
    "",
    "pub fn \{spec.parser_fn}_ok(input: String) -> Bool { \{spec.parser_fn}(input, Strict).ok }",
    "",
    "test \"\{spec.parser_fn} parse ok\" {",
    "  let sample = \{q(spec.valid_input)}",
    "  inspect(\{spec.parser_fn}_ok(sample), content=\"true\")",
    "  inspect(\{spec.parser_fn}(sample, Strict).end, content=sample.length().to_string())",
    "}",
    "",
    "test \"\{spec.parser_fn} has ast\" {",
    "  let ast = \{spec.parser_fn}(\{q(spec.valid_input)}, Strict).ast",
    "  inspect((ast is Some(_)).to_string(), content=\"true\")",
    "}",
    "",
    "test \"\{spec.parser_fn} parse fail\" {",
    "  inspect(\{spec.parser_fn}_ok(\{q(spec.invalid_input)}), content=\"false\")",
    "}",
    "",
    "test \"\{spec.parser_fn} tolerant keeps ast\" {",
    "  let res = \{spec.parser_fn}(\{q(spec.invalid_input)}, Tolerant)",
    "  inspect((res.ast is Some(_)).to_string(), content=\"true\")",
    "  inspect((res.diagnostics.length() > 0).to_string(), content=\"true\")",
    "}",
    "",
    "test \"\{spec.parser_fn} tolerant recovers root\" {",
    "  let res = \{spec.parser_fn}(\{q(spec.root_invalid_input)}, Tolerant)",
    "  inspect((res.ast is Some(_)).to_string(), content=\"true\")",
    "  inspect((res.diagnostics.length() > 0).to_string(), content=\"true\")",
    "}",
    "",
  ].iter().join("\n")
}

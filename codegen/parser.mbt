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

struct Emitter {
  grammar: Grammar
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

fn json_grammar() -> Grammar {
  let tokens: Map[String, TokenInfo] = {
    "string": tok(Lex(Tok("string_raw")), emit_node=true),
    "number": tok(Lex(Tok("number_raw")), emit_node=true),
    "{": tok(Lex(Lit("{"))),
    "}": tok(Lex(Lit("}"))),
    "[": tok(Lex(Lit("["))),
    "]": tok(Lex(Lit("]"))),
    ":": tok(Lex(Lit(":"))),
    ",": tok(Lex(Lit(","))),
    "true": tok(Lex(Lit("true")), emit_node=true),
    "false": tok(Lex(Lit("false")), emit_node=true),
    "null": tok(Lex(Lit("null")), emit_node=true),
    "digit": tok(Range(48, 57)),
    "onenine": tok(Range(49, 57)),
    "sign": tok(OneOf([Lit("+"), Lit("-")])),
    "hex": tok(OneOf([Range(48, 57), Range(65, 70), Range(97, 102)])),
    "int": tok(OneOf([
      Lit("0"),
      Chain([Tok("onenine"), Repeat(Tok("digit"))]),
    ])),
    "frac": tok(Chain([Lit("."), Repeat1(Tok("digit"))])),
    "exp": tok(Chain([
      OneOf([Lit("e"), Lit("E")]),
      Maybe(Tok("sign")),
      Repeat1(Tok("digit")),
    ])),
    "unicode_escape": tok(Chain([
      Lit("u"),
      Tok("hex"),
      Tok("hex"),
      Tok("hex"),
      Tok("hex"),
    ])),
    "escape_char": tok(OneOf([
      Lit("\""),
      Lit("\\"),
      Lit("/"),
      Lit("b"),
      Lit("f"),
      Lit("n"),
      Lit("r"),
      Lit("t"),
    ])),
    "escape": tok(Chain([
      Lit("\\"),
      OneOf([Tok("escape_char"), Tok("unicode_escape")]),
    ])),
    "unescaped": tok(NoneCharOf([34, 92, 10, 13])),
    "string_char": tok(OneOf([Tok("unescaped"), Tok("escape")])),
    "string_raw": tok(Chain([
      Lit("\""),
      Repeat(Tok("string_char")),
      Lit("\""),
    ])),
    "number_raw": tok(Chain([
      Maybe(Lit("-")),
      Tok("int"),
      Maybe(Tok("frac")),
      Maybe(Tok("exp")),
    ])),
  }
  let rules: Map[String, Expr] = {
    "pair": Chain([Tok("string"), Omit(Tok(":")), Ref("value")]),
    "object": Chain([
      Omit(Tok("{")),
      Maybe(Chain([Ref("pair"), Repeat(Chain([Omit(Tok(",")), Ref("pair")]))])),
      Omit(Tok("}")),
    ]),
    "array": Chain([
      Omit(Tok("[")),
      Maybe(Chain([Ref("value"), Repeat(Chain([Omit(Tok(",")), Ref("value")]))])),
      Omit(Tok("]")),
    ]),
    "value": OneOf([
      Tok("string"),
      Tok("number"),
      Ref("object"),
      Ref("array"),
      Tok("true"),
      Tok("false"),
      Tok("null"),
    ]),
  }
  { tokens, rules, start: "value" }
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

fn call_method(name: String, body: String) -> String {
  "fn GenParser::\{name}(self: GenParser) -> GenMatch {\n\{body}\n}"
}

fn chain_method(name: String, parts: Array[String]) -> String {
  let ret = match_ok(nodes="nodes")
  let lines: Array[String] = [
    "fn GenParser::\{name}(self: GenParser) -> GenMatch {",
    "  let start = self.i",
    "  let nodes: Array[GenAst] = []",
  ]
  for part in parts {
    lines.push("  let m = self.\{part}()")
    lines.push("  if !m.ok { self.i = start; return \{match_fail()} }")
    lines.push("  for node in m.nodes { nodes.push(node) }")
  }
  lines.push("  \{ret}")
  lines.push("}")
  lines.iter().join("\n")
}

fn oneof_method(name: String, parts: Array[String]) -> String {
  let lines: Array[String] =
    ["fn GenParser::\{name}(self: GenParser) -> GenMatch {", "  let start = self.i"]
  for part in parts {
    lines.push("  let m = self.\{part}()")
    lines.push("  if m.ok { return m }")
    lines.push("  self.i = start")
  }
  lines.push("  \{match_fail()}")
  lines.push("}")
  lines.iter().join("\n")
}

fn repeat_method(name: String, part: String) -> String {
  let ret = match_ok(nodes="nodes")
  [
    "fn GenParser::\{name}(self: GenParser) -> GenMatch {",
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

fn repeat1_method(name: String, part: String) -> String {
  let ret = match_ok(nodes="nodes")
  [
    "fn GenParser::\{name}(self: GenParser) -> GenMatch {",
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

fn maybe_method(name: String, part: String) -> String {
  [
    "fn GenParser::\{name}(self: GenParser) -> GenMatch {",
    "  let start = self.i",
    "  let m = self.\{part}()",
    "  if !m.ok { self.i = start; return \{match_ok()} }",
    "  m",
    "}",
  ].iter().join("\n")
}

fn omit_method(name: String, part: String) -> String {
  [
    "fn GenParser::\{name}(self: GenParser) -> GenMatch {",
    "  let m = self.\{part}()",
    "  if !m.ok { return \{match_fail()} }",
    "  \{match_ok()}",
    "}",
  ].iter().join("\n")
}

fn node_method(name: String, label: String, part: String) -> String {
  let node = "[{ type_: \{q(label)}, c: m.nodes, s: start, e: self.i }]"
  let ret = match_ok(nodes=node)
  [
    "fn GenParser::\{name}(self: GenParser) -> GenMatch {",
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
      self.push(call_method(id, "  if self.gen_eat(\{q(text)}) { \{ok} } else { \{fail} }"))
      id
    }
    Range(lo, hi) => {
      let id = self.fresh()
      let ok = match_ok()
      let fail = match_fail()
      self.push(call_method(id, "  if self.gen_take_range(\{lo}, \{hi}) { \{ok} } else { \{fail} }"))
      id
    }
    NoneCharOf(chars) => {
      let id = self.fresh()
      let ok = match_ok()
      let fail = match_fail()
      self.push(call_method(id, "  if self.gen_take_none_of(\{nums(chars)}) { \{ok} } else { \{fail} }"))
      id
    }
    Lex(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(call_method(id, "  self.gen_skip_ws()\n  self.\{part}()"))
      id
    }
    Omit(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(omit_method(id, part))
      id
    }
    Chain(items) => {
      let id = self.fresh()
      let parts: Array[String] = []
      for item in items {
        parts.push(self.emit_expr(item))
      }
      self.push(chain_method(id, parts))
      id
    }
    OneOf(items) => {
      let id = self.fresh()
      let parts: Array[String] = []
      for item in items {
        parts.push(self.emit_expr(item))
      }
      self.push(oneof_method(id, parts))
      id
    }
    Repeat(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(repeat_method(id, part))
      id
    }
    Repeat1(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(repeat1_method(id, part))
      id
    }
    Maybe(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(maybe_method(id, part))
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
      self.push(if info.emit_node { node_method(id, name, part) } else { call_method(id, "  self.\{part}()") })
      id
    }
  }
}

fn rule_method(name: String, part: String) -> String {
  let node = "[{ type_: \{q(name)}, c: m.nodes, s: start, e: self.i }]"
  let ret = match_ok(nodes=node)
  [
    "fn GenParser::gen_parse_\{name}(self: GenParser) -> GenMatch {",
    "  let start = self.i",
    "  let m = self.\{part}()",
    "  if !m.ok { self.i = start; return \{match_fail()} }",
    "  \{ret}",
    "}",
  ].iter().join("\n")
}

pub fn generate_parser_source() -> String {
  let grammar = json_grammar()
  let emitter = { grammar, next_id: 0, methods: [], token_methods: {} }
  for name, expr in grammar.rules {
    let part = emitter.emit_expr(expr)
    emitter.push(rule_method(name, part))
  }
  let methods = emitter.methods.iter().join("\n\n")
  [
    "pub struct GenAst { type_: String; c: Array[GenAst]; s: Int; e: Int }",
    "pub struct GenParseResult { ok: Bool; end: Int; ast: GenAst? }",
    "priv struct GenMatch { ok: Bool; nodes: Array[GenAst] }",
    "",
    "let gen_ch_ws: UInt16 = 32",
    "let gen_ch_nl: UInt16 = 10",
    "let gen_ch_cr: UInt16 = 13",
    "let gen_ch_tab: UInt16 = 9",
    "",
    "priv struct GenParser { input: String; len: Int; mut i: Int }",
    "",
    "fn GenParser::gen_skip_ws(self: GenParser) -> Unit {",
    "  while self.i < self.len {",
    "    let ch = self.input[self.i]",
    "    if ch == gen_ch_ws || ch == gen_ch_nl || ch == gen_ch_cr || ch == gen_ch_tab {",
    "      self.i = self.i + 1",
    "    } else {",
    "      break",
    "    }",
    "  }",
    "}",
    "",
    "fn GenParser::gen_eat(self: GenParser, text: String) -> Bool {",
    "  let n = text.length()",
    "  if self.i + n > self.len { return false }",
    "  for j in 0..<n {",
    "    if self.input[self.i + j] != text[j] { return false }",
    "  }",
    "  self.i = self.i + n",
    "  true",
    "}",
    "",
    "fn GenParser::gen_take_range(self: GenParser, lo: UInt16, hi: UInt16) -> Bool {",
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
    "fn GenParser::gen_take_none_of(self: GenParser, chars: Array[UInt16]) -> Bool {",
    "  if self.i >= self.len { return false }",
    "  let ch = self.input[self.i]",
    "  for bad in chars {",
    "    if ch == bad { return false }",
    "  }",
    "  self.i = self.i + 1",
    "  true",
    "}",
    "",
    methods,
    "",
    "pub fn generated_parse(input: String) -> GenParseResult {",
    "  let p: GenParser = { input, len: input.length(), i: 0 }",
    "  let m = p.gen_parse_\{grammar.start}()",
    "  p.gen_skip_ws()",
    "  let ok = m.ok && p.i == p.len && m.nodes.length() == 1",
    "  { ok, end: p.i, ast: if ok { Some(m.nodes[0]) } else { None } }",
    "}",
    "",
    "pub fn generated_parse_ok(input: String) -> Bool { generated_parse(input).ok }",
    "",
    "fn generated_read_sample() -> String raise {",
    "  @fs.read_file_to_string(\"parsergen/sample_json.json\")",
    "}",
    "",
    "test \"generated parser parse ok\" {",
    "  let sample = generated_read_sample()",
    "  inspect(generated_parse_ok(sample), content=\"true\")",
    "  inspect(generated_parse(sample).end, content=sample.length().to_string())",
    "}",
    "",
    "test \"generated parser has ast\" {",
    "  let ast = generated_parse(\"{\\\"a\\\": [1, true]}\").ast",
    "  inspect((ast is Some(_)).to_string(), content=\"true\")",
    "}",
    "",
    "test \"generated parser parse fail\" {",
    "  inspect(generated_parse_ok(\"{\\\"a\\\": [1, 2, }\"), content=\"false\")",
    "}",
    "",
  ].iter().join("\n")
}

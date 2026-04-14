enum TokenDef {
  Lit(String)
  Builtin(String)
}

enum Expr {
  Ref(String)
  Tok(String)
  Chain(Array[Expr])
  OneOf(Array[Expr])
  Repeat(Expr)
  Maybe(Expr)
  Omit(Expr)
}

struct Grammar {
  tokens : Map[String, TokenDef]
  rules : Map[String, Expr]
  start : String
}

struct Emitter {
  grammar : Grammar
  mut next_id : Int
  methods : Array[String]
}

fn q(s : String) -> String {
  s.to_json().stringify()
}

fn json_grammar() -> Grammar {
  let tokens : Map[String, TokenDef] = {
    "string": Builtin("string"),
    "number": Builtin("number"),
    "{": Lit("{"),
    "}": Lit("}"),
    "[": Lit("["),
    "]": Lit("]"),
    ":": Lit(":"),
    ",": Lit(","),
    "true": Lit("true"),
    "false": Lit("false"),
    "null": Lit("null"),
  }
  let rules : Map[String, Expr] = {
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

fn Emitter::fresh(self : Emitter) -> String {
  let id = self.next_id
  self.next_id = id + 1
  "p\{id}"
}

fn Emitter::push(self : Emitter, body : String) -> Unit {
  self.methods.push(body)
}

fn tok_method(name : String, tok : TokenDef) -> String {
  let body = match tok {
    Lit(text) =>
      "  self.skip_ws()\n  self.eat(\{q(text)})"
    Builtin(kind) =>
      "  self.skip_ws()\n  self.parse_\{kind}()"
  }
  "fn Parser::\{name}(self : Parser) -> Bool {\n\{body}\n}"
}

fn chain_method(name : String, parts : Array[String]) -> String {
  let lines : Array[String] = ["fn Parser::\{name}(self : Parser) -> Bool {", "  let start = self.i"]
  for part in parts {
    lines.push("  if !self.\{part}() { self.i = start; return false }")
  }
  lines.push("  true")
  lines.push("}")
  lines.iter().join("\n")
}

fn oneof_method(name : String, parts : Array[String]) -> String {
  let lines : Array[String] = ["fn Parser::\{name}(self : Parser) -> Bool {", "  let start = self.i"]
  for part in parts {
    lines.push("  if self.\{part}() { return true }")
    lines.push("  self.i = start")
  }
  lines.push("  false")
  lines.push("}")
  lines.iter().join("\n")
}

fn repeat_method(name : String, part : String) -> String {
  [
    "fn Parser::\{name}(self : Parser) -> Bool {",
    "  while true {",
    "    let start = self.i",
    "    if !self.\{part}() { self.i = start; break }",
    "    if self.i == start { break }",
    "  }",
    "  true",
    "}",
  ].iter().join("\n")
}

fn maybe_method(name : String, part : String) -> String {
  [
    "fn Parser::\{name}(self : Parser) -> Bool {",
    "  let start = self.i",
    "  if !self.\{part}() { self.i = start }",
    "  true",
    "}",
  ].iter().join("\n")
}

fn Emitter::emit_expr(self : Emitter, expr : Expr) -> String {
  match expr {
    Ref(name) => "parse_\{name}"
    Tok(name) => {
      let id = self.fresh()
      let tok = self.grammar.tokens[name]
      self.push(tok_method(id, tok))
      id
    }
    Omit(inner) => self.emit_expr(inner)
    Chain(items) => {
      let id = self.fresh()
      let parts : Array[String] = []
      for item in items {
        parts.push(self.emit_expr(item))
      }
      self.push(chain_method(id, parts))
      id
    }
    OneOf(items) => {
      let id = self.fresh()
      let parts : Array[String] = []
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
    Maybe(inner) => {
      let id = self.fresh()
      let part = self.emit_expr(inner)
      self.push(maybe_method(id, part))
      id
    }
  }
}

fn rule_method(name : String, part : String) -> String {
  [
    "fn Parser::parse_\{name}(self : Parser) -> Bool {",
    "  self.\{part}()",
    "}",
  ].iter().join("\n")
}

pub fn generate_parser_source() -> String {
  let grammar = json_grammar()
  let emitter = { grammar, next_id: 0, methods: [] }
  for name, expr in grammar.rules {
    let part = emitter.emit_expr(expr)
    emitter.push(rule_method(name, part))
  }
  let methods = emitter.methods.iter().join("\n\n")
  [
    "pub struct ParseResult { ok : Bool; end : Int }",
    "",
    "let ch_ws : UInt16 = 32",
    "let ch_nl : UInt16 = 10",
    "let ch_cr : UInt16 = 13",
    "let ch_tab : UInt16 = 9",
    "let ch_quote : UInt16 = 34",
    "let ch_minus : UInt16 = 45",
    "let ch_plus : UInt16 = 43",
    "let ch_dot : UInt16 = 46",
    "let ch_zero : UInt16 = 48",
    "let ch_one : UInt16 = 49",
    "let ch_nine : UInt16 = 57",
    "",
    "priv struct Parser { input : String; len : Int; mut i : Int }",
    "",
    "fn Parser::peek(self : Parser) -> UInt16 {",
    "  if self.i < self.len { self.input[self.i] } else { 0 }",
    "}",
    "",
    "fn Parser::skip_ws(self : Parser) -> Unit {",
    "  while self.i < self.len {",
    "    let ch = self.input[self.i]",
    "    if ch == ch_ws || ch == ch_nl || ch == ch_cr || ch == ch_tab {",
    "      self.i = self.i + 1",
    "    } else {",
    "      break",
    "    }",
    "  }",
    "}",
    "",
    "fn Parser::eat(self : Parser, text : String) -> Bool {",
    "  let n = text.length()",
    "  if self.i + n > self.len { return false }",
    "  for j in 0..<n {",
    "    if self.input[self.i + j] != text[j] { return false }",
    "  }",
    "  self.i = self.i + n",
    "  true",
    "}",
    "",
    "fn Parser::parse_string(self : Parser) -> Bool {",
    "  if self.peek() != ch_quote { return false }",
    "  self.i = self.i + 1",
    "  while self.i < self.len {",
    "    let ch = self.input[self.i]",
    "    if ch == ch_quote {",
    "      self.i = self.i + 1",
    "      return true",
    "    }",
    "    if ch == 92 {",
    "      if self.i + 1 >= self.len { return false }",
    "      self.i = self.i + 2",
    "    } else {",
    "      self.i = self.i + 1",
    "    }",
    "  }",
    "  false",
    "}",
    "",
    "fn Parser::parse_digits(self : Parser) -> Bool {",
    "  let mut ok = false",
    "  while self.i < self.len {",
    "    let ch = self.input[self.i]",
    "    if ch_zero <= ch && ch <= ch_nine {",
    "      ok = true",
    "      self.i = self.i + 1",
    "    } else {",
    "      break",
    "    }",
    "  }",
    "  ok",
    "}",
    "",
    "fn Parser::parse_number(self : Parser) -> Bool {",
    "  let start = self.i",
    "  if self.peek() == ch_minus { self.i = self.i + 1 }",
    "  if self.i >= self.len { self.i = start; return false }",
    "  if self.input[self.i] == ch_zero {",
    "    self.i = self.i + 1",
    "  } else {",
    "    let ch = self.input[self.i]",
    "    if !(ch_one <= ch && ch <= ch_nine) { self.i = start; return false }",
    "    self.i = self.i + 1",
    "    ignore(self.parse_digits())",
    "  }",
    "  if self.i < self.len && self.input[self.i] == ch_dot {",
    "    self.i = self.i + 1",
    "    if !self.parse_digits() { self.i = start; return false }",
    "  }",
    "  if self.i < self.len {",
    "    let ch = self.input[self.i]",
    "    if ch == 69 || ch == 101 {",
    "      self.i = self.i + 1",
    "      if self.i < self.len {",
    "        let sign = self.input[self.i]",
    "        if sign == ch_plus || sign == ch_minus { self.i = self.i + 1 }",
    "      }",
    "      if !self.parse_digits() { self.i = start; return false }",
    "    }",
    "  }",
    "  true",
    "}",
    "",
    methods,
    "",
    "pub fn parse(input : String) -> ParseResult {",
    "  let p = { input, len : input.length(), i : 0 }",
    "  let ok = p.parse_\{grammar.start}()",
    "  p.skip_ws()",
    "  { ok : ok && p.i == p.len, end : p.i }",
    "}",
    "",
    "pub fn parse_ok(input : String) -> Bool { parse(input).ok }",
    "",
  ].iter().join("\n")
}

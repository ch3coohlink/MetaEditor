priv struct KvMatch { ok: Bool; nodes: Array[GenAst] }

let kv_gen_ch_ws: UInt16 = 32
let kv_gen_ch_nl: UInt16 = 10
let kv_gen_ch_cr: UInt16 = 13
let kv_gen_ch_tab: UInt16 = 9

priv struct KvParser { input: String; len: Int; mut i: Int; diagnostics: Array[GenDiag] }

fn KvParser::gen_skip_ws(self: KvParser) -> Unit {
  while self.i < self.len {
    let ch = self.input[self.i]
    if ch == kv_gen_ch_ws || ch == kv_gen_ch_nl || ch == kv_gen_ch_cr || ch == kv_gen_ch_tab {
      self.i = self.i + 1
    } else {
      break
    }
  }
}

fn KvParser::gen_eat(self: KvParser, text: String) -> Bool {
  let n = text.length()
  if self.i + n > self.len { return false }
  for j in 0..<n {
    if self.input[self.i + j] != text[j] { return false }
  }
  self.i = self.i + n
  true
}

fn KvParser::gen_take_range(self: KvParser, lo: UInt16, hi: UInt16) -> Bool {
  if self.i >= self.len { return false }
  let ch = self.input[self.i]
  if lo <= ch && ch <= hi {
    self.i = self.i + 1
    true
  } else {
    false
  }
}

fn KvParser::gen_take_none_of(self: KvParser, chars: Array[UInt16]) -> Bool {
  if self.i >= self.len { return false }
  let ch = self.input[self.i]
  for bad in chars {
    if ch == bad { return false }
  }
  self.i = self.i + 1
  true
}

fn KvParser::gen_diag(self: KvParser, msg: String, s: Int, e: Int) -> Unit {
  self.diagnostics.push({ msg, s, e })
}

fn KvParser::gen_missing(self: KvParser, msg: String, at: Int) -> GenAst {
  self.gen_diag(msg, at, at)
  { type_: "missing", c: [], s: at, e: at }
}

fn KvParser::gen_error(self: KvParser, msg: String, s: Int, e: Int) -> GenAst {
  self.gen_diag(msg, s, e)
  { type_: "error", c: [], s, e }
}

fn KvParser::gen_should_insert_missing(self: KvParser) -> Bool {
  if self.i >= self.len { return true }
  let ch = self.input[self.i]
  ch == 44 || ch == 58 || ch == 93 || ch == 125
}

fn KvParser::gen_recover(self: KvParser, msg: String) -> GenAst {
  if self.gen_should_insert_missing() {
    return self.gen_missing(msg, self.i)
  }
  let s = self.i
  self.i = self.i + 1
  self.gen_error(msg, s, self.i)
}

fn KvParser::p4(self: KvParser) -> KvMatch {
  if self.gen_eat("[") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn KvParser::p3(self: KvParser) -> KvMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p4()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn KvParser::p2(self: KvParser) -> KvMatch {
  self.p3()
}

fn KvParser::p1(self: KvParser) -> KvMatch {
  let m = self.p2()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn KvParser::p13(self: KvParser) -> KvMatch {
  if self.gen_take_range(97, 122) { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn KvParser::p14(self: KvParser) -> KvMatch {
  if self.gen_take_range(65, 90) { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn KvParser::p12(self: KvParser) -> KvMatch {
  let start = self.i
  let m = self.p13()
  if m.ok { return m }
  self.i = start
  let m = self.p14()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn KvParser::p11(self: KvParser) -> KvMatch {
  self.p12()
}

fn KvParser::p15(self: KvParser) -> KvMatch {
  let nodes: Array[GenAst] = []
  while true {
    let start = self.i
    let m = self.p11()
    if !m.ok { self.i = start; break }
    for node in m.nodes { nodes.push(node) }
    if self.i == start { break }
  }
  { ok: true, nodes: nodes }
}

fn KvParser::p10(self: KvParser) -> KvMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p11()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected alpha"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p15()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected alpha"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn KvParser::p9(self: KvParser) -> KvMatch {
  self.p10()
}

fn KvParser::p8(self: KvParser) -> KvMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p9()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn KvParser::p7(self: KvParser) -> KvMatch {
  let start = self.i
  let m = self.p8()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "ident", c: m.nodes, s: start, e: self.i }] }
}

fn KvParser::p21(self: KvParser) -> KvMatch {
  if self.gen_eat(",") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn KvParser::p20(self: KvParser) -> KvMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p21()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn KvParser::p19(self: KvParser) -> KvMatch {
  self.p20()
}

fn KvParser::p18(self: KvParser) -> KvMatch {
  let m = self.p19()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn KvParser::p17(self: KvParser) -> KvMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p18()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ,"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p7()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ident"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn KvParser::p16(self: KvParser) -> KvMatch {
  let nodes: Array[GenAst] = []
  while true {
    let start = self.i
    let m = self.p17()
    if !m.ok { self.i = start; break }
    for node in m.nodes { nodes.push(node) }
    if self.i == start { break }
  }
  { ok: true, nodes: nodes }
}

fn KvParser::p6(self: KvParser) -> KvMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p7()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ident"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p16()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ,"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn KvParser::p5(self: KvParser) -> KvMatch {
  let start = self.i
  let m = self.p6()
  if !m.ok { self.i = start; return { ok: true, nodes: [] } }
  m
}

fn KvParser::p25(self: KvParser) -> KvMatch {
  if self.gen_eat("]") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn KvParser::p24(self: KvParser) -> KvMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p25()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn KvParser::p23(self: KvParser) -> KvMatch {
  self.p24()
}

fn KvParser::p22(self: KvParser) -> KvMatch {
  let m = self.p23()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn KvParser::p0(self: KvParser) -> KvMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p1()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ["))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p5()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ident"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p22()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ]"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn KvParser::gen_parse_list(self: KvParser) -> KvMatch {
  let start = self.i
  let m = self.p0()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "list", c: m.nodes, s: start, e: self.i }] }
}

fn KvParser::p26(self: KvParser) -> KvMatch {
  let start = self.i
  let m = self.p7()
  if m.ok { return m }
  self.i = start
  let m = self.gen_parse_list()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn KvParser::gen_parse_value(self: KvParser) -> KvMatch {
  let start = self.i
  let m = self.p26()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "value", c: m.nodes, s: start, e: self.i }] }
}

fn KvParser::p31(self: KvParser) -> KvMatch {
  if self.gen_eat("=") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn KvParser::p30(self: KvParser) -> KvMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p31()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn KvParser::p29(self: KvParser) -> KvMatch {
  self.p30()
}

fn KvParser::p28(self: KvParser) -> KvMatch {
  let m = self.p29()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn KvParser::p27(self: KvParser) -> KvMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p7()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ident"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p28()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ="))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.gen_parse_value()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected value"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn KvParser::gen_parse_pair(self: KvParser) -> KvMatch {
  let start = self.i
  let m = self.p27()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "pair", c: m.nodes, s: start, e: self.i }] }
}

fn KvParser::p35(self: KvParser) -> KvMatch {
  let m = self.p19()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn KvParser::p34(self: KvParser) -> KvMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p35()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ,"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.gen_parse_pair()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected pair"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn KvParser::p33(self: KvParser) -> KvMatch {
  let nodes: Array[GenAst] = []
  while true {
    let start = self.i
    let m = self.p34()
    if !m.ok { self.i = start; break }
    for node in m.nodes { nodes.push(node) }
    if self.i == start { break }
  }
  { ok: true, nodes: nodes }
}

fn KvParser::p32(self: KvParser) -> KvMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.gen_parse_pair()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected pair"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p33()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ,"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn KvParser::gen_parse_doc(self: KvParser) -> KvMatch {
  let start = self.i
  let m = self.p32()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "doc", c: m.nodes, s: start, e: self.i }] }
}

fn kv_parser_tolerant(input: String) -> GenParseResult {
  let p: KvParser = { input, len: input.length(), i: 0, diagnostics: [] }
  let m = p.gen_parse_doc()
  let nodes = m.nodes
  if !m.ok {
    nodes.push(p.gen_recover("expected doc"))
  }
  p.gen_skip_ws()
  if p.i < p.len {
    let s = p.i
    p.i = p.len
    nodes.push(p.gen_error("unexpected trailing input", s, p.len))
  }
  let ast = if nodes.length() == 0 {
    None
  } else if nodes.length() == 1 {
    Some(nodes[0])
  } else {
    Some({ type_: "doc", c: nodes, s: 0, e: p.i })
  }
  let ok = m.ok && p.diagnostics.length() == 0 && p.i == p.len && nodes.length() == 1
  { ok, end: p.i, ast, diagnostics: p.diagnostics }
}

pub fn kv_parser(input: String, mode: ParseMode) -> GenParseResult {
  let res = kv_parser_tolerant(input)
  match mode {
    Tolerant => res
    Strict => if res.ok { res } else {
      { ok: false, end: res.end, ast: None, diagnostics: res.diagnostics }
    }
  }
}

pub fn kv_parser_ok(input: String) -> Bool { kv_parser(input, Strict).ok }

test "kv_parser parse ok" {
  let sample = "theme=dark,features=[spell,lint]"
  inspect(kv_parser_ok(sample), content="true")
  inspect(kv_parser(sample, Strict).end, content=sample.length().to_string())
}

test "kv_parser has ast" {
  let ast = kv_parser("theme=dark,features=[spell,lint]", Strict).ast
  inspect((ast is Some(_)).to_string(), content="true")
}

test "kv_parser parse fail" {
  inspect(kv_parser_ok("theme=dark,features=[spell,]"), content="false")
}

test "kv_parser tolerant keeps ast" {
  let res = kv_parser("theme=dark,features=[spell,]", Tolerant)
  inspect((res.ast is Some(_)).to_string(), content="true")
  inspect((res.diagnostics.length() > 0).to_string(), content="true")
}

test "kv_parser tolerant recovers root" {
  let res = kv_parser("?", Tolerant)
  inspect((res.ast is Some(_)).to_string(), content="true")
  inspect((res.diagnostics.length() > 0).to_string(), content="true")
}

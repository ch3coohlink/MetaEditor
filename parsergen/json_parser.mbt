priv struct JsonMatch { ok: Bool; nodes: Array[GenAst] }

let json_gen_ch_ws: UInt16 = 32
let json_gen_ch_nl: UInt16 = 10
let json_gen_ch_cr: UInt16 = 13
let json_gen_ch_tab: UInt16 = 9

priv struct JsonParser { input: String; len: Int; mut i: Int; diagnostics: Array[GenDiag] }

fn JsonParser::gen_skip_ws(self: JsonParser) -> Unit {
  while self.i < self.len {
    let ch = self.input[self.i]
    if ch == json_gen_ch_ws || ch == json_gen_ch_nl || ch == json_gen_ch_cr || ch == json_gen_ch_tab {
      self.i = self.i + 1
    } else {
      break
    }
  }
}

fn JsonParser::gen_eat(self: JsonParser, text: String) -> Bool {
  let n = text.length()
  if self.i + n > self.len { return false }
  for j in 0..<n {
    if self.input[self.i + j] != text[j] { return false }
  }
  self.i = self.i + n
  true
}

fn JsonParser::gen_take_range(self: JsonParser, lo: UInt16, hi: UInt16) -> Bool {
  if self.i >= self.len { return false }
  let ch = self.input[self.i]
  if lo <= ch && ch <= hi {
    self.i = self.i + 1
    true
  } else {
    false
  }
}

fn JsonParser::gen_take_none_of(self: JsonParser, chars: Array[UInt16]) -> Bool {
  if self.i >= self.len { return false }
  let ch = self.input[self.i]
  for bad in chars {
    if ch == bad { return false }
  }
  self.i = self.i + 1
  true
}

fn JsonParser::gen_diag(self: JsonParser, msg: String, s: Int, e: Int) -> Unit {
  self.diagnostics.push({ msg, s, e })
}

fn JsonParser::gen_missing(self: JsonParser, msg: String, at: Int) -> GenAst {
  self.gen_diag(msg, at, at)
  { type_: "missing", c: [], s: at, e: at }
}

fn JsonParser::gen_error(self: JsonParser, msg: String, s: Int, e: Int) -> GenAst {
  self.gen_diag(msg, s, e)
  { type_: "error", c: [], s, e }
}

fn JsonParser::gen_should_insert_missing(self: JsonParser) -> Bool {
  if self.i >= self.len { return true }
  let ch = self.input[self.i]
  ch == 44 || ch == 58 || ch == 93 || ch == 125
}

fn JsonParser::gen_recover(self: JsonParser, msg: String) -> GenAst {
  if self.gen_should_insert_missing() {
    return self.gen_missing(msg, self.i)
  }
  let s = self.i
  self.i = self.i + 1
  self.gen_error(msg, s, self.i)
}

fn JsonParser::p5(self: JsonParser) -> JsonMatch {
  if self.gen_eat("\"") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p10(self: JsonParser) -> JsonMatch {
  if self.gen_take_none_of([34, 92, 10, 13]) { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p9(self: JsonParser) -> JsonMatch {
  self.p10()
}

fn JsonParser::p13(self: JsonParser) -> JsonMatch {
  if self.gen_eat("\\") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p17(self: JsonParser) -> JsonMatch {
  if self.gen_eat("\"") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p18(self: JsonParser) -> JsonMatch {
  if self.gen_eat("\\") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p19(self: JsonParser) -> JsonMatch {
  if self.gen_eat("/") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p20(self: JsonParser) -> JsonMatch {
  if self.gen_eat("b") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p21(self: JsonParser) -> JsonMatch {
  if self.gen_eat("f") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p22(self: JsonParser) -> JsonMatch {
  if self.gen_eat("n") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p23(self: JsonParser) -> JsonMatch {
  if self.gen_eat("r") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p24(self: JsonParser) -> JsonMatch {
  if self.gen_eat("t") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p16(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p17()
  if m.ok { return m }
  self.i = start
  let m = self.p18()
  if m.ok { return m }
  self.i = start
  let m = self.p19()
  if m.ok { return m }
  self.i = start
  let m = self.p20()
  if m.ok { return m }
  self.i = start
  let m = self.p21()
  if m.ok { return m }
  self.i = start
  let m = self.p22()
  if m.ok { return m }
  self.i = start
  let m = self.p23()
  if m.ok { return m }
  self.i = start
  let m = self.p24()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p15(self: JsonParser) -> JsonMatch {
  self.p16()
}

fn JsonParser::p27(self: JsonParser) -> JsonMatch {
  if self.gen_eat("u") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p30(self: JsonParser) -> JsonMatch {
  if self.gen_take_range(48, 57) { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p31(self: JsonParser) -> JsonMatch {
  if self.gen_take_range(65, 70) { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p32(self: JsonParser) -> JsonMatch {
  if self.gen_take_range(97, 102) { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p29(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p30()
  if m.ok { return m }
  self.i = start
  let m = self.p31()
  if m.ok { return m }
  self.i = start
  let m = self.p32()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p28(self: JsonParser) -> JsonMatch {
  self.p29()
}

fn JsonParser::p26(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p27()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected u"))
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
      nodes.push(self.gen_recover("expected hex"))
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
      nodes.push(self.gen_recover("expected hex"))
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
      nodes.push(self.gen_recover("expected hex"))
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
      nodes.push(self.gen_recover("expected hex"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p25(self: JsonParser) -> JsonMatch {
  self.p26()
}

fn JsonParser::p14(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p15()
  if m.ok { return m }
  self.i = start
  let m = self.p25()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p12(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p13()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected \\"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p14()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected escape_char | unicode_escape"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p11(self: JsonParser) -> JsonMatch {
  self.p12()
}

fn JsonParser::p8(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p9()
  if m.ok { return m }
  self.i = start
  let m = self.p11()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p7(self: JsonParser) -> JsonMatch {
  self.p8()
}

fn JsonParser::p6(self: JsonParser) -> JsonMatch {
  let nodes: Array[GenAst] = []
  while true {
    let start = self.i
    let m = self.p7()
    if !m.ok { self.i = start; break }
    for node in m.nodes { nodes.push(node) }
    if self.i == start { break }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p33(self: JsonParser) -> JsonMatch {
  if self.gen_eat("\"") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p4(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p5()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected \""))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p6()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected string_char"))
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
      nodes.push(self.gen_recover("expected \""))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p3(self: JsonParser) -> JsonMatch {
  self.p4()
}

fn JsonParser::p2(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p3()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p1(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p2()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "string", c: m.nodes, s: start, e: self.i }] }
}

fn JsonParser::p37(self: JsonParser) -> JsonMatch {
  if self.gen_eat(":") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p36(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p37()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p35(self: JsonParser) -> JsonMatch {
  self.p36()
}

fn JsonParser::p34(self: JsonParser) -> JsonMatch {
  let m = self.p35()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn JsonParser::p0(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p1()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected string"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p34()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected :"))
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

fn JsonParser::gen_parse_pair(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p0()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "pair", c: m.nodes, s: start, e: self.i }] }
}

fn JsonParser::p42(self: JsonParser) -> JsonMatch {
  if self.gen_eat("{") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p41(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p42()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p40(self: JsonParser) -> JsonMatch {
  self.p41()
}

fn JsonParser::p39(self: JsonParser) -> JsonMatch {
  let m = self.p40()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn JsonParser::p50(self: JsonParser) -> JsonMatch {
  if self.gen_eat(",") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p49(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p50()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p48(self: JsonParser) -> JsonMatch {
  self.p49()
}

fn JsonParser::p47(self: JsonParser) -> JsonMatch {
  let m = self.p48()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn JsonParser::p46(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p47()
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

fn JsonParser::p45(self: JsonParser) -> JsonMatch {
  let nodes: Array[GenAst] = []
  while true {
    let start = self.i
    let m = self.p46()
    if !m.ok { self.i = start; break }
    for node in m.nodes { nodes.push(node) }
    if self.i == start { break }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p44(self: JsonParser) -> JsonMatch {
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
  let m = self.p45()
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

fn JsonParser::p43(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p44()
  if !m.ok { self.i = start; return { ok: true, nodes: [] } }
  m
}

fn JsonParser::p54(self: JsonParser) -> JsonMatch {
  if self.gen_eat("}") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p53(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p54()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p52(self: JsonParser) -> JsonMatch {
  self.p53()
}

fn JsonParser::p51(self: JsonParser) -> JsonMatch {
  let m = self.p52()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn JsonParser::p38(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p39()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected {"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p43()
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
  let m = self.p51()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected }"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::gen_parse_object(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p38()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "object", c: m.nodes, s: start, e: self.i }] }
}

fn JsonParser::p59(self: JsonParser) -> JsonMatch {
  if self.gen_eat("[") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p58(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p59()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p57(self: JsonParser) -> JsonMatch {
  self.p58()
}

fn JsonParser::p56(self: JsonParser) -> JsonMatch {
  let m = self.p57()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn JsonParser::p64(self: JsonParser) -> JsonMatch {
  let m = self.p48()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn JsonParser::p63(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p64()
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

fn JsonParser::p62(self: JsonParser) -> JsonMatch {
  let nodes: Array[GenAst] = []
  while true {
    let start = self.i
    let m = self.p63()
    if !m.ok { self.i = start; break }
    for node in m.nodes { nodes.push(node) }
    if self.i == start { break }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p61(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
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
  let m = self.p62()
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

fn JsonParser::p60(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p61()
  if !m.ok { self.i = start; return { ok: true, nodes: [] } }
  m
}

fn JsonParser::p68(self: JsonParser) -> JsonMatch {
  if self.gen_eat("]") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p67(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p68()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p66(self: JsonParser) -> JsonMatch {
  self.p67()
}

fn JsonParser::p65(self: JsonParser) -> JsonMatch {
  let m = self.p66()
  if !m.ok { return { ok: false, nodes: [] } }
  { ok: true, nodes: [] }
}

fn JsonParser::p55(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p56()
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
  let m = self.p60()
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
  let m = self.p65()
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

fn JsonParser::gen_parse_array(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p55()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "array", c: m.nodes, s: start, e: self.i }] }
}

fn JsonParser::p75(self: JsonParser) -> JsonMatch {
  if self.gen_eat("-") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p74(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p75()
  if !m.ok { self.i = start; return { ok: true, nodes: [] } }
  m
}

fn JsonParser::p78(self: JsonParser) -> JsonMatch {
  if self.gen_eat("0") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p81(self: JsonParser) -> JsonMatch {
  if self.gen_take_range(49, 57) { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p80(self: JsonParser) -> JsonMatch {
  self.p81()
}

fn JsonParser::p84(self: JsonParser) -> JsonMatch {
  if self.gen_take_range(48, 57) { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p83(self: JsonParser) -> JsonMatch {
  self.p84()
}

fn JsonParser::p82(self: JsonParser) -> JsonMatch {
  let nodes: Array[GenAst] = []
  while true {
    let start = self.i
    let m = self.p83()
    if !m.ok { self.i = start; break }
    for node in m.nodes { nodes.push(node) }
    if self.i == start { break }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p79(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p80()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected onenine"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p82()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected digit"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p77(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p78()
  if m.ok { return m }
  self.i = start
  let m = self.p79()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p76(self: JsonParser) -> JsonMatch {
  self.p77()
}

fn JsonParser::p88(self: JsonParser) -> JsonMatch {
  if self.gen_eat(".") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p89(self: JsonParser) -> JsonMatch {
  let start = self.i
  let first = self.p83()
  if !first.ok { self.i = start; return { ok: false, nodes: [] } }
  let nodes = first.nodes
  while true {
    let again = self.i
    let m = self.p83()
    if !m.ok { self.i = again; break }
    for node in m.nodes { nodes.push(node) }
    if self.i == again { break }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p87(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p88()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected ."))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p89()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected digit"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p86(self: JsonParser) -> JsonMatch {
  self.p87()
}

fn JsonParser::p85(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p86()
  if !m.ok { self.i = start; return { ok: true, nodes: [] } }
  m
}

fn JsonParser::p94(self: JsonParser) -> JsonMatch {
  if self.gen_eat("e") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p95(self: JsonParser) -> JsonMatch {
  if self.gen_eat("E") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p93(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p94()
  if m.ok { return m }
  self.i = start
  let m = self.p95()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p99(self: JsonParser) -> JsonMatch {
  if self.gen_eat("+") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p100(self: JsonParser) -> JsonMatch {
  if self.gen_eat("-") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p98(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p99()
  if m.ok { return m }
  self.i = start
  let m = self.p100()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p97(self: JsonParser) -> JsonMatch {
  self.p98()
}

fn JsonParser::p96(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p97()
  if !m.ok { self.i = start; return { ok: true, nodes: [] } }
  m
}

fn JsonParser::p101(self: JsonParser) -> JsonMatch {
  let start = self.i
  let first = self.p83()
  if !first.ok { self.i = start; return { ok: false, nodes: [] } }
  let nodes = first.nodes
  while true {
    let again = self.i
    let m = self.p83()
    if !m.ok { self.i = again; break }
    for node in m.nodes { nodes.push(node) }
    if self.i == again { break }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p92(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p93()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected e | E"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p96()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected sign"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p101()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected digit"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p91(self: JsonParser) -> JsonMatch {
  self.p92()
}

fn JsonParser::p90(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p91()
  if !m.ok { self.i = start; return { ok: true, nodes: [] } }
  m
}

fn JsonParser::p73(self: JsonParser) -> JsonMatch {
  let start = self.i
  let nodes: Array[GenAst] = []
  let m = self.p74()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected -"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p76()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected int"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p85()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected frac"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  let m = self.p90()
  if !m.ok {
    if self.i > start || nodes.length() > 0 {
      nodes.push(self.gen_recover("expected exp"))
    } else {
      self.i = start
      return { ok: false, nodes: [] }
    }
  } else {
    for node in m.nodes { nodes.push(node) }
  }
  { ok: true, nodes: nodes }
}

fn JsonParser::p72(self: JsonParser) -> JsonMatch {
  self.p73()
}

fn JsonParser::p71(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p72()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p70(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p71()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "number", c: m.nodes, s: start, e: self.i }] }
}

fn JsonParser::p104(self: JsonParser) -> JsonMatch {
  if self.gen_eat("true") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p103(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p104()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p102(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p103()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "true", c: m.nodes, s: start, e: self.i }] }
}

fn JsonParser::p107(self: JsonParser) -> JsonMatch {
  if self.gen_eat("false") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p106(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p107()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p105(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p106()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "false", c: m.nodes, s: start, e: self.i }] }
}

fn JsonParser::p110(self: JsonParser) -> JsonMatch {
  if self.gen_eat("null") { { ok: true, nodes: [] } } else { { ok: false, nodes: [] } }
}

fn JsonParser::p109(self: JsonParser) -> JsonMatch {
  let start = self.i
  self.gen_skip_ws()
  let m = self.p110()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::p108(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p109()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "null", c: m.nodes, s: start, e: self.i }] }
}

fn JsonParser::p69(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p1()
  if m.ok { return m }
  self.i = start
  let m = self.p70()
  if m.ok { return m }
  self.i = start
  let m = self.gen_parse_object()
  if m.ok { return m }
  self.i = start
  let m = self.gen_parse_array()
  if m.ok { return m }
  self.i = start
  let m = self.p102()
  if m.ok { return m }
  self.i = start
  let m = self.p105()
  if m.ok { return m }
  self.i = start
  let m = self.p108()
  if m.ok { return m }
  self.i = start
  { ok: false, nodes: [] }
}

fn JsonParser::gen_parse_value(self: JsonParser) -> JsonMatch {
  let start = self.i
  let m = self.p69()
  if !m.ok { self.i = start; return { ok: false, nodes: [] } }
  { ok: true, nodes: [{ type_: "value", c: m.nodes, s: start, e: self.i }] }
}

fn json_parser_tolerant(input: String) -> GenParseResult {
  let p: JsonParser = { input, len: input.length(), i: 0, diagnostics: [] }
  let m = p.gen_parse_value()
  let nodes = m.nodes
  if !m.ok {
    nodes.push(p.gen_recover("expected value"))
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
    Some({ type_: "value", c: nodes, s: 0, e: p.i })
  }
  let ok = m.ok && p.diagnostics.length() == 0 && p.i == p.len && nodes.length() == 1
  { ok, end: p.i, ast, diagnostics: p.diagnostics }
}

pub fn json_parser(input: String, mode: ParseMode) -> GenParseResult {
  let res = json_parser_tolerant(input)
  match mode {
    Tolerant => res
    Strict => if res.ok { res } else {
      { ok: false, end: res.end, ast: None, diagnostics: res.diagnostics }
    }
  }
}

pub fn json_parser_ok(input: String) -> Bool { json_parser(input, Strict).ok }

test "json_parser parse ok" {
  let sample = "{\"a\": [1, true]}"
  inspect(json_parser_ok(sample), content="true")
  inspect(json_parser(sample, Strict).end, content=sample.length().to_string())
}

test "json_parser has ast" {
  let ast = json_parser("{\"a\": [1, true]}", Strict).ast
  inspect((ast is Some(_)).to_string(), content="true")
}

test "json_parser parse fail" {
  inspect(json_parser_ok("{\"a\": [1, 2, }"), content="false")
}

test "json_parser tolerant keeps ast" {
  let res = json_parser("{\"a\": [1, 2, }", Tolerant)
  inspect((res.ast is Some(_)).to_string(), content="true")
  inspect((res.diagnostics.length() > 0).to_string(), content="true")
}

test "json_parser tolerant recovers root" {
  let res = json_parser("?", Tolerant)
  inspect((res.ast is Some(_)).to_string(), content="true")
  inspect((res.diagnostics.length() > 0).to_string(), content="true")
}

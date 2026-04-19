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

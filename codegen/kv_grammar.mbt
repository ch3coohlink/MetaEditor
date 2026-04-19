fn kv_grammar() -> Grammar {
  let tokens: Map[String, TokenInfo] = {
    "ident": tok(Lex(Tok("ident_raw")), emit_node=true),
    "=": tok(Lex(Lit("="))),
    "[": tok(Lex(Lit("["))),
    "]": tok(Lex(Lit("]"))),
    ",": tok(Lex(Lit(","))),
    "alpha": tok(OneOf([Range(97, 122), Range(65, 90)])),
    "ident_raw": tok(Chain([Tok("alpha"), Repeat(Tok("alpha"))])),
  }
  let rules: Map[String, Expr] = {
    "list": Chain([
      Omit(Tok("[")),
      Maybe(Chain([Tok("ident"), Repeat(Chain([Omit(Tok(",")), Tok("ident")]))])),
      Omit(Tok("]")),
    ]),
    "value": OneOf([Tok("ident"), Ref("list")]),
    "pair": Chain([Tok("ident"), Omit(Tok("=")), Ref("value")]),
    "doc": Chain([Ref("pair"), Repeat(Chain([Omit(Tok(",")), Ref("pair")]))]),
  }
  { tokens, rules, start: "doc" }
}

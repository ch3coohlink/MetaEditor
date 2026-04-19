pub enum ParseMode {
  Strict
  Tolerant
}

pub struct GenAst { type_: String; c: Array[GenAst]; s: Int; e: Int }
pub struct GenDiag { msg: String; s: Int; e: Int }
pub struct GenParseResult { ok: Bool; end: Int; ast: GenAst?; diagnostics: Array[GenDiag] }

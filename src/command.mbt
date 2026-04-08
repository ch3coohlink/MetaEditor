pub(all) struct FlagDef {
  name : String
  desc : String
  has_value : Bool
}

pub(all) struct CmdContext {
  args : Array[String]
  flags : Array[(String, String)]
}

pub fn CmdContext::get_bool(self : CmdContext, name : String) -> Bool {
  for f in self.flags {
    if f.0 == name { return f.1 == "true" }
  }
  false
}

pub fn CmdContext::get_string(self : CmdContext, name : String) -> String? {
  for f in self.flags {
    if f.0 == name { return Some(f.1) }
  }
  None
}

priv suberror CmdErr {
  Fail(String)
}

pub fn parse_cmd(flags : Array[FlagDef], tokens : Array[String], allow_unknown~ : Bool = false) -> CmdContext raise {
  let args : Array[String] = []
  let out_flags : Array[(String, String)] = []
  let mut i = 0
  while i < tokens.length() {
    let token = tokens[i]
    if token.has_prefix("--") {
      let name = token[2:].to_string()
      let mut found_bool = false
      let mut found_val = false
      for f in flags {
        if f.name == name {
          if f.has_value { found_val = true } else { found_bool = true }
          break
        }
      }
      if found_bool {
        out_flags.push((name, "true"))
        i += 1
      } else if found_val {
        if i + 1 >= tokens.length() { raise CmdErr::Fail("missing value for --\{name}") }
        out_flags.push((name, tokens[i + 1]))
        i += 2
      } else if allow_unknown {
        args.push(token)
        i += 1
      } else {
        raise CmdErr::Fail("Unknown flag: \{token}")
      }
    } else {
      args.push(token)
      i += 1
    }
  }
  { args, flags: out_flags }
}

pub(all) struct CmdDef[A] {
  name : String
  usage : String
  desc : String
  flags : Array[FlagDef]
  allow_unknown : Bool
  action : A
}

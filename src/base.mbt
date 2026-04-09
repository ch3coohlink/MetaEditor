fn has_prefix(text : String, prefix : String) -> Bool {
  text.length() >= prefix.length() && text[:prefix.length()].to_string() == prefix
}

priv suberror BaseErr {
  Fail(String)
}

fn base_err(message : String) -> BaseErr {
  BaseErr::Fail(message)
}

pub fn split_shell_args(text : String) -> Array[String] raise {
  let out : Array[String] = []
  let parts : Array[String] = []
  let mut quote : String? = None
  let mut escaped = false
  let mut i = 0
  while i < text.length() {
    let ch = text[i:i + 1].to_string()
    if escaped {
      parts.push(ch)
      escaped = false
    } else if ch == "\\" {
      escaped = true
    } else {
      match quote {
        Some(q) => if ch == q { quote = None } else { parts.push(ch) }
        None =>
          if ch == "'" || ch == "\"" {
            quote = Some(ch)
          } else if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            if parts.length() > 0 {
              out.push(parts.iter().join(""))
              parts.clear()
            }
          } else {
            parts.push(ch)
          }
      }
    }
    i = i + 1
  }
  if escaped {
    raise base_err("invalid escape at end of input")
  }
  if quote is Some(_) {
    raise base_err("unterminated quoted string")
  }
  if parts.length() > 0 {
    out.push(parts.iter().join(""))
  }
  out
}

fn[T] no_raise(f : () -> T raise) -> T {
  f() catch { _ => panic() }
}

pub fn[T : @json.FromJson] decode_field(
  fields: Map[String, Json],
  key: String,
  path: @json.JsonPath,
  owner: String,
) -> T raise @json.JsonDecodeError {
  let value = match fields.get(key) {
    Some(value) => value
    None => raise @json.JsonDecodeError((path, "\{owner}: missing \{key}"))
  }
  @json.from_json(value)
}

fn[T : ToJson + @json.FromJson] assert_json_roundtrip(value: T) -> Unit {
  let actual : T = @json.from_json(value.to_json()) catch { _ => panic() }
  if actual.to_json().stringify() != value.to_json().stringify() { panic() }
}
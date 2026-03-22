pub(all) enum QueryCmd {
  Ui
  Focused
  Viewport
  Node(Int)
  Selector(String)
  Text(String)
} derive(Eq, Show)

pub(all) enum Target {
  Id(Int)
  Selector(String)
} derive(Eq, Show)

pub(all) enum ExecCmd {
  Click(Target)
  Focus(Target)
  Input(Target, String)
  Action(String, Int)
} derive(Eq, Show)

fn parse_query_json(json : Json) -> QueryCmd raise {
  let kind = json_string(json, "kind").unwrap_or("")
  match kind {
    "ui" => Ui
    "focused" => Focused
    "viewport" => Viewport
    "node" =>
      if json_int(json, "id") is Some(id) { Node(id) }
      else { raise ServiceError("invalid node id") }
    "selector" =>
      if json_string(json, "selector") is Some(s) { Selector(s) }
      else { raise ServiceError("missing selector") }
    "text" =>
      if json_string(json, "selector") is Some(s) { Text(s) }
      else { raise ServiceError("missing selector") }
    _ => raise ServiceError("unsupported query kind: \{kind}")
  }
}

pub fn parse_query(raw : String) -> QueryCmd raise {
  let text = raw.trim()
  if text == "" { raise ServiceError("missing query payload") }
  if text.has_prefix("{") { return parse_query_json(@json.parse(text)) }
  if text == "ui" { Ui }
  else if text == "focused" { Focused }
  else if text == "viewport" { Viewport }
  else if text.has_prefix("node ") {
    match (try? @strconv.parse_int(text[5:].trim()) : Result[Int, _]) {
      Ok(id) => Node(id); _ => raise ServiceError("invalid node id")
    }
  }
  else if text.has_prefix("selector ") { Selector(text[9:].trim().to_string()) }
  else if text.has_prefix("text ") { Text(text[5:].trim().to_string()) }
  else { raise ServiceError("unsupported query kind: \{text}") }
}

fn parse_target(json : Json) -> Target raise {
  if json_int(json, "id") is Some(id) { Id(id) }
  else if json_string(json, "selector") is Some(s) { Selector(s) }
  else { raise ServiceError("missing target") }
}

fn parse_exec_json(json : Json) -> ExecCmd raise {
  let kind = json_string(json, "kind").unwrap_or("")
  match kind {
    "click" => Click(parse_target(json))
    "focus" => Focus(parse_target(json))
    "input" => Input(parse_target(json), json_string(json, "text").unwrap_or(""))
    "action" =>
      Action(json_string(json, "name").unwrap_or(""), json_int(json, "settle_ms").unwrap_or(50))
    _ => raise ServiceError("unsupported exec kind: \{kind}")
  }
}

pub fn parse_exec(raw : String) -> ExecCmd raise {
  let text = raw.trim()
  if text == "" { raise ServiceError("missing exec payload") }
  if text.has_prefix("{") { return parse_exec_json(@json.parse(text)) }
  if text.has_prefix("click ") { Click(Selector(text[6:].trim().to_string())) }
  else if text.has_prefix("focus ") { Focus(Selector(text[6:].trim().to_string())) }
  else { Action(text.to_string(), 50) }
}

fn query_to_json(query : QueryCmd) -> Json {
  match query {
    Ui => { "kind": "ui" }
    Focused => { "kind": "focused" }
    Viewport => { "kind": "viewport" }
    Node(id) => { "kind": "node", "id": id }
    Selector(selector) => { "kind": "selector", "selector": selector }
    Text(selector) => { "kind": "text", "selector": selector }
  }
}

fn exec_to_json(exec : ExecCmd) -> Json {
  match exec {
    Click(Id(id)) => { "kind": "click", "id": id }
    Click(Selector(selector)) => { "kind": "click", "selector": selector }
    Focus(Id(id)) => { "kind": "focus", "id": id }
    Focus(Selector(selector)) => { "kind": "focus", "selector": selector }
    Input(Id(id), text) => { "kind": "input", "id": id, "text": text }
    Input(Selector(selector), text) => { "kind": "input", "selector": selector, "text": text }
    Action(name, settle_ms) => { "kind": "action", "name": name, "settle_ms": settle_ms }
  }
}

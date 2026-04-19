using @json { from_json, type JsonDecodeError, type JsonPath }
pub fn[T] bad_json(path: JsonPath, msg: String) -> T raise JsonDecodeError {
  raise JsonDecodeError((path, "from_json: \{msg}"))
}
pub(all) struct JsonObj { obj: Map[String, Json]; path: JsonPath }
pub fn json_obj(json: Json, path: JsonPath) -> JsonObj raise JsonDecodeError {
  match json { Object(obj) => { obj, path }; _ => bad_json(path, "expected object") }
}
pub fn[T: FromJson] JsonObj::get(self: JsonObj, key: String) -> T raise JsonDecodeError {
  let v = match self.obj.get(key) { Some(v) => v; None => bad_json(self.path, "missing \{key}") }
  from_json(v, path=self.path.add_key(key)) catch { _ => bad_json(self.path, "bad \{key}") }
}

pub(open) trait ToInt { to_int(Self) -> Int }
pub(open) trait ToString { to_string(Self) -> String }

pub fn gen_id(s: Int) -> () -> Int { let mut i = s; () => { let j = i; i += 1; j } }
let next_rng_seed: () -> Int = gen_id(@env.now().to_int())

pub fn split_path(path: String) -> Array[String] raise {
  if path == "" { fail("path should not be empty") }
  let parts = []
  for part in path.split("/") {
    let key = part.to_string()
    if key != "" { parts.push(key) }
  }; parts
}

pub fn[T, U] flat_map(a: Array[T], f: (T) -> Array[U]) -> Array[U] {
  let r = []; for i in a { for value in f(i) { r.push(value) } }; r
}

pub struct Rng { mut state: Int }
pub fn Rng::new(seed: Int) -> Rng {{ state: seed }}
pub fn new_rng() -> Rng { Rng::new(next_rng_seed()) }
pub fn Rng::next(self: Rng) -> Int {
  self.state = (self.state * 1664525 + 1013904223) & 0x7fffffff
  self.state
}
pub fn Rng::pick(self: Rng, n: Int) -> Int {
  if n <= 1 { 0 } else { self.next() % n }
}

pub fn[T] assert_fail(msg: String, f: () -> T raise) -> Unit raise {
  try f() catch { _ => () } noraise { _ => fail(msg) }
}

pub type ClearHooks = Array[() -> Unit]
pub(open) trait HasClrs { clrs(Self) -> ClearHooks }
pub fn[T: HasClrs] onclr(t: T, f: () -> Unit) -> Unit { t.clrs().push(f) }
pub fn[T: HasClrs] clean(t: T) -> Unit { let c = t.clrs(); for f in c { f() }; c.clear() }

pub(all) enum EventKind { Click; Input; Change; Focus; Blur; KeyDown; KeyUp;
  PointerDown; PointerUp; PointerMove; PointerCancel } derive(Eq, FromJson, ToJson)
pub impl ToString for EventKind with to_string(self) -> String {
  match self.to_json() { String(v) => "on" + v.to_lower(); _ => "" }
}
pub(all) struct EventCfg { prevent: Bool; stop: Bool; capture: Bool } derive(FromJson, ToJson)
pub fn EventCfg::new(prevent~: Bool = false, stop~: Bool = false,
  capture~: Bool = false) -> EventCfg {{ prevent, stop, capture }}
pub(all) struct Modify { ctrl: Bool; shift: Bool; alt: Bool; meta: Bool } derive(FromJson, ToJson)
pub fn Modify::new(ctrl~: Bool = false, shift~: Bool = false, alt~: Bool = false,
  meta~: Bool = false) -> Modify {{ ctrl, shift, alt, meta }}
pub(all) struct PointerData { mod: Modify; x: Int; y: Int; vx: Int; vy: Int
  button: Int; buttons: Int; pointer_id: Int } derive(FromJson, ToJson)
pub(all) struct KeyData { mod: Modify; key: String; code: String } derive(FromJson, ToJson)
pub(all) struct InputData { value: String } derive(FromJson, ToJson)
pub(all) enum EventData { Pointer(PointerData); Key(KeyData); Input(InputData) } derive(FromJson, ToJson)
pub(all) struct Event { kind: EventKind; data: EventData } derive(FromJson, ToJson)
pub fn Event::new(kind: EventKind, data: EventData) -> Event {{ kind, data }}
pub fn Event::pointer(kind: EventKind, x~: Int = 0, y~: Int = 0, vx~: Int = 0, vy~: Int = 0,
  button~: Int = 0, buttons~: Int = 0, pointer_id~: Int = 0, mod~: Modify = Modify::new()
) -> Event { Event::new(kind, Pointer({ mod, x, y, vx, vy, button, buttons, pointer_id })) }

pub(all) enum NodeQuery { Node; Text; Attr(String); Prop(String); Style(String) } derive(FromJson, ToJson)
pub(all) struct Box { x: Int; y: Int; w: Int; h: Int } derive(FromJson, ToJson)
pub(all) struct Scroll { x: Int; y: Int; w: Int; h: Int } derive(FromJson, ToJson)
pub(all) enum Read { Box(Int); View(Int); Scroll(Int); Text(String, Array[String]) } derive(FromJson, ToJson)
pub(all) enum ReadValue { Box(Box?); View(Box?); Scroll(Scroll?); Text(Array[Int]?) } derive(FromJson, ToJson)

pub(all) enum StrValue { Empty; String(String) } derive(FromJson, ToJson)

pub(all) struct NodeElement { tag: String; text: String; attrs: Map[String, StrValue] } derive(FromJson, ToJson)
pub(all) enum NodeData { Anchor; Text(String); Element(NodeElement) } derive(FromJson, ToJson)
pub(all) struct Node { id: Int; data: NodeData } derive(FromJson, ToJson)
pub(all) enum NodeValue { Node(Node); Text(String); Attr(String, String)
  Prop(String, String); Style(String, String) } derive(FromJson, ToJson)

pub(all) enum DomNs { Html; Svg; MathML } derive(FromJson, ToJson)
pub(all) enum JsValue { Empty; String(String); Int(Int); Float(Float) } derive(FromJson, ToJson)
pub(all) struct CreateCmd { id: Int; tag: String; ns: DomNs; value: StrValue } derive(FromJson, ToJson)
pub(all) struct InsertCmd { parent: Int; child: Int; target: Int; after: Bool } derive(FromJson, ToJson)
pub(all) struct ListenerCmd { nid: Int; id: Int; kind: EventKind; cfg: EventCfg; bind: Bool } derive(FromJson, ToJson)
pub(all) struct PointerCmd { id: Int; pointer_id: Int; capture: Bool } derive(FromJson, ToJson)
pub(all) struct FocusCmd { id: Int; focus: Bool } derive(FromJson, ToJson)
pub(all) enum DomCmd {
  Reset; Create(CreateCmd); Insert(InsertCmd); Remove(Int)
  Attr(Int, String, StrValue); Style(Int, String, StrValue); Prop(Int, String, JsValue)
  Listener(ListenerCmd); Pointer(PointerCmd); Focus(FocusCmd)
} derive(FromJson, ToJson)

pub(all) enum Role { Browser; Client } derive(FromJson, ToJson)
pub(all) struct HelloReq { role: Role; session: String } derive(FromJson, ToJson)
pub(all) struct QueryReq { browser: String; path: String; query: NodeQuery } derive(FromJson, ToJson)
pub(all) struct ReadReq { browser: String; reads: Array[Read] } derive(FromJson, ToJson)
pub(all) struct DispatchReq { browser: String; path: String; event: Event } derive(FromJson, ToJson)
pub(all) struct TriggerReq { node: Int; event: Event } derive(FromJson, ToJson)
pub(all) enum Req {
  Hello(HelloReq); QueryReq(QueryReq); ReadReq(ReadReq)
  Dispatch(DispatchReq); Trigger(TriggerReq); CliReq(String); Ping
} derive(FromJson, ToJson)
pub(all) struct ReqMsg { id: Int; body: Req } derive(FromJson, ToJson)
pub(all) struct HelloRes { session: String } derive(FromJson, ToJson)
pub(all) enum Res {
  DomCmd(DomCmd); ReadRes(Array[ReadValue])
  HelloAck(HelloRes); QueryRes(NodeValue)
  CliRes(String); Pong; Ok; Err(String)
} derive(FromJson, ToJson)
pub(all) struct ResMsg { id: Int; body: Res } derive(FromJson, ToJson)

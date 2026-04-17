using @json { from_json, type JsonPath, type JsonDecodeError }
pub fn[T] bad_json(path: JsonPath, msg: String) -> T raise JsonDecodeError {
  raise JsonDecodeError((path, "from_json: \{msg}"))
}
pub struct JsonObj { obj: Map[String, Json]; path: JsonPath }
pub fn json_obj(json: Json, path: JsonPath) -> JsonObj raise JsonDecodeError {
  match json { Object(obj) => { obj, path }; _ => bad_json(path, "expected object") }
}
pub fn[T: FromJson] JsonObj::get(self: JsonObj, key: String) -> T raise JsonDecodeError {
  let v = match self.obj.get(key) { Some(v) => v; None => bad_json(self.path, "missing \{key}") }
  from_json(v, path=self.path.add_key(key)) catch { _ => bad_json(self.path, "bad \{key}") }
}

pub trait ToInt { to_int(Self) -> Int }
pub trait ToString { to_string(Self) -> String }
fn to_lower_case(v: String) -> String {
  String::from_iter(v.iter().map(c => c.to_ascii_lowercase()))
}

pub fn gen_id(s: Int) -> () -> Int { let mut i = s; () => { let j = i; i += 1; j } }
let next_rng_seed: () -> Int = gen_id(@env.now().to_int())

fn split_path(path: String) -> Array[String] raise {
  if path == "" { fail("path should not be empty") }
  let parts = []
  for part in path.split("/") {
    let key = part.to_string()
    if key == "" { fail("path should not contain empty part") }
    parts.push(key)
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
pub trait HasClrs { clrs(Self) -> ClearHooks }
pub fn[T: HasClrs] onclr(t: T, f: () -> Unit) -> Unit { t.clrs().push(f) }
pub fn[T: HasClrs] clean(t: T) -> Unit { let c = t.clrs(); for f in c { f() }; c.clear() }

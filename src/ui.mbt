let nid : Ref[Int] = Ref::new(1)
fn next_id() -> Int { let id = nid.val; nid.val = id + 1; id }

pub(all) enum DomCmd {
  Create(Int, String)
  Text(Int, String)
  Attr(Int, String, String)
  Append(Int, Int)
  UpdateText(Int, String)
  UpdateAttr(Int, String, String)
  Remove(Int)
  Listen(Int, String, Int)
  Action(String, Int)
}
pub fn DomCmd::to_json(self : DomCmd) -> String {
  match self {
    Create(id, tag) => "{\"$tag\":0,\"_0\":\{id},\"_1\":\"\{tag}\"}"
    Text(id, text) => "{\"$tag\":1,\"_0\":\{id},\"_1\":\"\{text}\"}"
    Attr(id, k, v) => "{\"$tag\":2,\"_0\":\{id},\"_1\":\"\{k}\",\"_2\":\"\{v}\"}"
    Append(pid, cid) => "{\"$tag\":3,\"_0\":\{pid},\"_1\":\{cid}}"
    UpdateText(id, text) => "{\"$tag\":4,\"_0\":\{id},\"_1\":\"\{text}\"}"
    UpdateAttr(id, k, v) => "{\"$tag\":5,\"_0\":\{id},\"_1\":\"\{k}\",\"_2\":\"\{v}\"}"
    Remove(id) => "{\"$tag\":6,\"_0\":\{id}}"
    Listen(id, ev, cb) => "{\"$tag\":7,\"_0\":\{id},\"_1\":\"\{ev}\",\"_2\":\{cb}}"
    Action(name, cb) => "{\"$tag\":8,\"_0\":\"\{name}\",\"_1\":\{cb}}"
  }
}

pub fn reg_action(name : String, f : () -> Unit raise) -> Prop {
  let i = ci.val; ci.val = i + 1; cbs.set(i, f)
  emit(Action(name, i))
  E(f)
}

let qrs : Map[String, () -> String] = Map::new()
pub fn reg_query(name : String, f : () -> String) -> Unit {
  qrs.set(name, f)
}

pub fn trigger_query(name : String) -> String {
  match qrs.get(name) {
    Some(f) => f()
    None => ""
  }
}


let cq : Array[DomCmd] = []
pub fn emit(c : DomCmd) -> Unit { cq.push(c) }
pub fn get_cmds() -> Array[DomCmd] { let r = cq.copy(); cq.clear(); r }

let cbs : Map[Int, () -> Unit raise] = Map::new()
let ci : Ref[Int] = Ref::new(1)

pub fn trigger_callback(id: Int) -> Unit {
  match cbs.get(id) { 
    Some(f) => { 
      let _ = try { f() } catch { _ => () }
      let _ = try { flush() } catch { _ => () }
    }
    None => () 
  }
}

pub(all) struct VNode { id : Int }
pub(all) enum Prop { S(String); D(() -> String); E(() -> Unit raise) }

pub fn h(tag: String, attrs: Array[(String, Prop)], children: Array[VNode]) -> VNode {
  let id = next_id(); emit(Create(id, tag))
  attrs.each(fn(p) {
    let (k, v) = p
    match v {
      S(s) => emit(Attr(id, k, s))
      D(f) => { let _ = try { effect(fn() { emit(UpdateAttr(id, k, f())) }) } catch { _ => () } }
      E(f) => { let i = ci.val; ci.val = i + 1; cbs.set(i, f); emit(Listen(id, k, i)) }
    }
  })
  children.each(fn(c) { emit(Append(id, c.id)) }); { id, }
}

pub fn text(v: String) -> VNode { let id = next_id(); emit(Create(id, "")); emit(Text(id, v)); { id, } }
pub fn text_dyn(f: () -> String) -> VNode {
  let id = next_id(); emit(Create(id, ""))
  let _ = try { effect(fn() { emit(UpdateText(id, f())) }) } catch { _ => () }
  { id, }
}

pub fn remove(node: VNode) -> Unit { emit(Remove(node.id)) }
pub fn init_bridge(sender: (Array[DomCmd]) -> Unit) -> Unit {
  on_post_flush(fn() { let cs = get_cmds(); if cs.length() > 0 { sender(cs) } })
}

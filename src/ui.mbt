let nid : Ref[Int] = Ref::new(1)
fn next_id() -> Int { let id = nid.val; nid.val = id + 1; id }

fn escape(s : String) -> String {
  let mut res = ""
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    match c {
      '\\' => res = res + "\\\\"
      '\"' => res = res + "\\\""
      '\n' => res = res + "\\n"
      '\r' => res = res + "\\r"
      '\t' => res = res + "\\t"
      '\b' => res = res + "\\b"
      '\u000C' => res = res + "\\f"

      _ => res = res + s[i:i+1].to_string()



    }

  }
  res
}

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
    Create(id, tag) => "{\"$tag\":0,\"_0\":\{id},\"_1\":\"\{escape(tag)}\"}"
    Text(id, text) => "{\"$tag\":1,\"_0\":\{id},\"_1\":\"\{escape(text)}\"}"
    Attr(id, k, v) => "{\"$tag\":2,\"_0\":\{id},\"_1\":\"\{escape(k)}\",\"_2\":\"\{escape(v)}\"}"
    Append(pid, cid) => "{\"$tag\":3,\"_0\":\{pid},\"_1\":\{cid}}"
    UpdateText(id, text) => "{\"$tag\":4,\"_0\":\{id},\"_1\":\"\{escape(text)}\"}"
    UpdateAttr(id, k, v) => "{\"$tag\":5,\"_0\":\{id},\"_1\":\"\{escape(k)}\",\"_2\":\"\{escape(v)}\"}"
    Remove(id) => "{\"$tag\":6,\"_0\":\{id}}"
    Listen(id, ev, cb) => "{\"$tag\":7,\"_0\":\{id},\"_1\":\"\{escape(ev)}\",\"_2\":\{cb}}"
    Action(name, cb) => "{\"$tag\":8,\"_0\":\"\{escape(name)}\",\"_1\":\{cb}}"
  }
}

pub(all) struct VNode { id : Int; cb_ids : Array[Int]; clrs : Array[() -> Unit]; children : Array[VNode] }
pub(all) enum Prop { S(String); D(() -> String); E(() -> Unit raise); ActionRef(Int) }

pub fn reg_action(name : String, f : () -> Unit raise) -> Prop {
  let i = ci.val; ci.val = i + 1; cbs.set(i, f)
  emit(Action(name, i))
  ActionRef(i)
}

let qrs : Map[String, () -> String] = Map::new()
pub fn reg_query(name : String, f : () -> String) -> Unit {
  qrs.set(name, f)
  onclr(fn() { qrs.remove(name) })
}

pub fn unreg_query(name : String) -> Unit {
  qrs.remove(name)
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
      let _ = try { f() } catch { e => println("Callback Error (ID \{id}): \{e}") }
      let _ = try { flush() } catch { e => println("Flush Error: \{e}") }
    }
    None => () 
  }
}

pub fn h(tag: String, attrs: Array[(String, Prop)], children: Array[VNode]) -> VNode {
  let id = next_id(); emit(Create(id, tag))
  let my_cbs = []
  let my_clrs : Array[() -> Unit] = []
  attrs.each(fn(p) {
    let (k, v) = p
    match v {
      S(s) => emit(Attr(id, k, s))
      D(f) => {
        let stop = try { 
          effect(fn() { emit(UpdateAttr(id, k, f())) }) 
        } catch { _ => fn() { () } }
        my_clrs.push(stop)
      }
      E(f) => { 
        let i = ci.val; ci.val = i + 1; cbs.set(i, f)
        my_cbs.push(i)
        emit(Listen(id, k, i)) 
      }
      ActionRef(i) => {
        my_cbs.push(i)
        emit(Listen(id, k, i))
      }
    }
  })
  children.each(fn(c) { emit(Append(id, c.id)) })
  { id, cb_ids: my_cbs, clrs: my_clrs, children }
}

pub fn text(v: String) -> VNode { 
  let id = next_id(); emit(Create(id, "")); emit(Text(id, v))
  { id, cb_ids: [], clrs: [], children: [] } 
}

pub fn text_dyn(f: () -> String) -> VNode {
  let id = next_id(); emit(Create(id, ""))
  let stop = try { 
    effect(fn() { emit(UpdateText(id, f())) }) 
  } catch { _ => fn() { () } }
  { id, cb_ids: [], clrs: [stop], children: [] }
}

fn recursive_cleanup(node: VNode) -> Unit {
  node.cb_ids.each(fn(id) { cbs.remove(id) })
  node.clrs.each(fn(f) { f() })
  node.children.each(recursive_cleanup)
}

pub fn remove(node: VNode) -> Unit { 
  emit(Remove(node.id))
  recursive_cleanup(node)
}




pub fn init_bridge(sender: (Array[String]) -> Unit) -> Unit {
  on_post_flush(fn() { 
    let cs = get_cmds()
    if cs.length() > 0 { 
      sender(cs.map(fn(c) { c.to_json() })) 
    } 
  })
}


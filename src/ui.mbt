let nid : Ref[Int] = Ref::new(1)
fn next_id() -> Int { let id = nid.val; nid.val = id + 1; id }

// Dom Commands for the thin JS layer
pub enum DomCmd {
  Create(Int, String)
  Text(Int, String)
  Attr(Int, String, String)
  Append(Int, Int)
  UpdateText(Int, String)
  UpdateAttr(Int, String, String)
  Remove(Int)
  Listen(Int, String, Int) // node_id, event, callback_id
}

let cmd_queue : Array[DomCmd] = []
fn emit(c : DomCmd) -> Unit { cmd_queue.push(c) }

pub fn get_cmds() -> Array[DomCmd] {
  let cmds = cmd_queue.copy()
  cmd_queue.clear()
  cmds
}

// Map to store callbacks on the MBT side
let callbacks : Map[Int, () -> Unit raise] = Map::new()
let cb_id_counter : Ref[Int] = Ref::new(1)

// This will be called by JS
pub fn trigger_callback(id : Int) -> Unit {
  match callbacks.get(id) {
    Some(f) => { let _ = try { f() } catch { _ => () } }
    None => ()
  }
}

pub struct VNode { id : Int }

pub enum Prop {
  S(String)
  D(() -> String)
}

pub enum Child {
  N(VNode)
  T(Prop)
}

// Convert string to Prop
pub fn s(v : String) -> Prop { S(v) }
// Convert getter to Prop
pub fn d(f : () -> String) -> Prop { D(f) }

pub fn h(
  tag : String,
  cls~ : Prop? = None,
  id_attr~ : Prop? = None,
  style~ : Prop? = None,
  text~ : Prop? = None,
  onclick~ : (() -> Unit raise)? = None,
  attrs~ : Map[String, Prop] = Map::new(),
  children~ : Array[Child] = []
) -> VNode {
  let id = next_id()
  emit(Create(id, tag))

  fn bind_prop(name : String, p : Prop) {
    match p {
      S(v) => emit(Attr(id, name, v))
      D(f) => {
        let _ = try {
          effect(fn() {
            emit(UpdateAttr(id, name, f()))
          })
        } catch { _ => () }
      }
    }
  }

  // Bind labeled props
  match cls { Some(p) => bind_prop("class", p); None => () }
  match id_attr { Some(p) => bind_prop("id", p); None => () }
  match style { Some(p) => bind_prop("style", p); None => () }
  
  // Bind extra attrs
  attrs.each(bind_prop)

  // Handle Event
  match onclick {
    Some(f) => {
      let cid = cb_id_counter.val
      cb_id_counter.val = cid + 1
      callbacks.set(cid, f)
      emit(Listen(id, "click", cid))
    }
    None => ()
  }

  // Handle text prop as a child text node
  match text {
    Some(S(v)) => {
      let tid = next_id()
      emit(Create(tid, "")) // "" means text node
      emit(Text(tid, v))
      emit(Append(id, tid))
    }
    Some(D(f)) => {
      let tid = next_id()
      emit(Create(tid, ""))
      let _ = try {
        effect(fn() { emit(UpdateText(tid, f())) })
      } catch { _ => () }
      emit(Append(id, tid))
    }
    None => ()
  }

  // Handle Children
  children.each(fn(c) {
    match c {
      N(n) => emit(Append(id, n.id))
      T(S(v)) => {
        let tid = next_id()
        emit(Create(tid, ""))
        emit(Text(tid, v))
        emit(Append(id, tid))
      }
      T(D(f)) => {
        let tid = next_id()
        emit(Create(tid, ""))
        let _ = try {
          effect(fn() { emit(UpdateText(tid, f())) })
        } catch { _ => () }
        emit(Append(id, tid))
      }
    }
  })

  { id, }
}

// Global batch flush to JS/Socket
pub fn init_bridge(sender : (Array[DomCmd]) -> Unit) -> Unit {
  on_post_flush(fn() {
    let cmds = get_cmds()
    if cmds.length() > 0 {
      sender(cmds)
    }
  })
}

// For quick dev
pub fn div(cls~ : Prop? = None, text~ : Prop? = None, children~ : Array[Child] = []) -> VNode {
  h("div", cls~, text~, children~)
}

pub fn button(cls~ : Prop? = None, text~ : Prop? = None, onclick~ : (() -> Unit raise)? = None) -> VNode {
  h("button", cls~, text~, onclick~)
}

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
  InsertBefore(Int, Int, Int)
}
pub fn DomCmd::to_json(self : DomCmd) -> String {
  match self {
    Create(id, tag) => "[0, \{id}, \"\{escape(tag)}\"]"
    Text(id, text) => "[1, \{id}, \"\{escape(text)}\"]"
    Attr(id, k, v) => "[2, \{id}, \"\{escape(k)}\", \"\{escape(v)}\"]"
    Append(pid, cid) => "[3, \{pid}, \{cid}]"
    UpdateText(id, text) => "[4, \{id}, \"\{escape(text)}\"]"
    UpdateAttr(id, k, v) => "[5, \{id}, \"\{escape(k)}\", \"\{escape(v)}\"]"
    Remove(id) => "[6, \{id}]"
    Listen(id, ev, cb) => "[7, \{id}, \"\{escape(ev)}\", \{cb}]"
    Action(name, cb) => "[8, \"\{escape(name)}\", \{cb}]"
    InsertBefore(pid, cid, rid) => "[9, \{pid}, \{cid}, \{rid}]"
  }
}
pub(all) enum Child {
  Null
  Node(VNode)
  Str(String)
  Int(Int)
  Arr(Array[Child])
  Dyn(() -> Child)
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
      let _ = f() catch { e => println("Callback Error (ID \{id}): \{e}") }
      let _ = flush() catch { e => println("Flush Error: \{e}") }
    }
    None => () 
  }
}

fn create_text_node(v: String) -> VNode { 
  let id = next_id(); emit(Create(id, "")); emit(Text(id, v))
  { id, cb_ids: [], clrs: [], children: [] } 
}

pub fn h(tag: String, attrs: Array[(String, Prop)], children_prop: Array[Child]) -> VNode {
  let id = next_id(); emit(Create(id, tag))
  let my_cbs = []
  let my_clrs : Array[() -> Unit] = []
  attrs.each(fn(p) {
    let (k, v) = p
    match v {
      S(s) => emit(Attr(id, k, s))
      D(f) => {
        let stop = effect(fn() { emit(UpdateAttr(id, k, f())) }) catch { _ => fn() {} }
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
  
  let current_children : Array[VNode] = []
  
  fn process_child(c_in: Child, target_array: Array[VNode], anchor_opt: Option[Int]) -> Unit {
      match c_in {
          Null => ()
          Node(n) => {
             match anchor_opt {
               Some(ref_id) => emit(InsertBefore(id, n.id, ref_id))
               None => emit(Append(id, n.id))
             }
             target_array.push(n)
          }
          Str(s) => {
             let n = create_text_node(s)
             match anchor_opt {
               Some(ref_id) => emit(InsertBefore(id, n.id, ref_id))
               None => emit(Append(id, n.id))
             }
             target_array.push(n)
          }
          Int(i) => process_child(Str(i.to_string()), target_array, anchor_opt)
          Arr(a) => {
             for child in a { process_child(child, target_array, anchor_opt) }
          }
          Dyn(f) => {
             let anchor = create_text_node("")
             match anchor_opt {
               Some(ref_id) => emit(InsertBefore(id, anchor.id, ref_id))
               None => emit(Append(id, anchor.id))
             }
             target_array.push(anchor)
             
             let old_nodes : Ref[Array[VNode]] = Ref::new([])
             
             let stop_effect = effect(fn() {
                 for old in old_nodes.val {
                    emit(Remove(old.id))
                    recursive_cleanup(old)
                 }
                 let new_child = f()
                 let new_vnodes = []
                 process_child(new_child, new_vnodes, Some(anchor.id))
                 old_nodes.val = new_vnodes
             }) catch { _ => fn() {} }
             
             anchor.clrs.push(fn() { 
                 let _ = stop_effect()
                 for old in old_nodes.val { recursive_cleanup(old) }
             })
          }
      }
  }

  for c in children_prop { process_child(c, current_children, None) }

  { id, cb_ids: my_cbs, clrs: my_clrs, children: current_children }
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
    if cs.length() > 0 { sender(cs.map(fn(c) { c.to_json() }))  } 
  })
}


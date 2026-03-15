let nid : Ref[Int] = Ref::new(1)
fn next_id() -> Int { let id = nid.val; nid.val = id + 1; id }

extern "js" fn js_create(id : Int, tag : String) = "bridge.create"
extern "js" fn js_text(id : Int, text : String) = "bridge.text"
extern "js" fn js_attr(id : Int, k : String, v : String) = "bridge.attr"
extern "js" fn js_append(pid : Int, cid : Int) = "bridge.append"

pub struct VNode { id : Int }

pub fn h(tag : String, text~ : String = "", attrs~ : Map[String, String] = Map::new()) -> VNode {
  let id = next_id()
  js_create(id, tag)
  if text != "" { js_text(id, text) }
  attrs.each(fn(k, v) { js_attr(id, k, v) })
  { id, }
}

pub fn VNode::append(self : VNode, child : VNode) -> Unit {
  js_append(self.id, child.id)
}


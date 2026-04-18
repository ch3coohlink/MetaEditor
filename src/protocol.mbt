pub struct Event { mut target: Node?; kind: EventKind; data: EventData } derive(FromJson)
pub fn Event::new(kind: EventKind, data: EventData) -> Event {{ kind, target: None, data }}
pub fn Event::pointer(kind: EventKind, x~: Int = 0, y~: Int = 0, vx~: Int = 0, vy~: Int = 0,
  button~: Int = 0, buttons~: Int = 0, pointer_id~: Int = 0, mod~: Modify = Modify::new()
) -> Event { Event::new(kind, Pointer({ mod, x, y, vx, vy, button, buttons, pointer_id })) }
pub fn Event::pointer_id(e: Event) -> Int raise { match e.data { Pointer(v) => v.pointer_id;
  _ => fail("only pointer event has pointer_id") } }

struct ListenerObj { id: Int; nid: Int; kind: EventKind; cfg: EventCfg; f: (Event) -> Unit raise; dom: Dom }
pub impl ToJson for ListenerObj with to_json(l) -> Json { (l.kind, l.cfg, l.nid, l.id).to_json() }
pub fn ListenerObj::off(self: ListenerObj) -> Unit raise { self.dom.unbind_listener(self) }
fn Node::shared(self: Node) -> @shared.Node { from_json(self.to_json()) catch { _ => panic() } }
pub fn Node::on(self: Node, kind: EventKind, f: (Event) -> Unit raise, cfg: EventCfg) -> ListenerObj raise {
  self.dom().bind_listener(self, kind, f, cfg)
}
pub fn Node::off(self: Node, handle: ListenerObj) -> Unit raise {
  self.dom().unbind_listener(handle)
}
pub fn Node::capture_pointer(self: Node, pointer_id: Int) -> Unit raise {
  guard self.data is Element(_) else { fail_non_elm("capture pointer") }
  self.dom().cmd(Pointer({ id: self.id, pointer_id, capture: true }))
}
pub fn Node::release_pointer(self: Node, pointer_id: Int) -> Unit raise {
  guard self.data is Element(_) else { fail_non_elm("release pointer") }
  self.dom().cmd(Pointer({ id: self.id, pointer_id, capture: false }))
}
pub fn Node::focus(self: Node, focus?: Bool = true) -> Unit raise {
  guard self.data is Element(_) else { fail_non_elm("focus") }
  self.dom().cmd(Focus({ id: self.id, focus }))
}
pub fn Dom::bind_listener(d: Dom, node: Node, kind: EventKind,
  f: (Event) -> Unit raise, cfg: EventCfg) -> ListenerObj raise {
  let listener = { id: (d.nid)(), nid: node.id, kind, cfg, f, dom: d }
  match node.data {
    Element(el) => {
      let ls = if el.listeners is Some(ls) { ls }
      else { let ls = Map::new(); el.listeners = Some(ls); ls }
      ls.set(listener.id, listener)
      d.cmd(Listener({ nid: node.id, id: listener.id, kind, cfg, bind: true }))
      listener
    }
    _ => { fail_non_elm("bind listener"); fail("") }
  }
}
pub fn Dom::unbind_listener(d: Dom, listener: ListenerObj) -> Unit raise {
  match d.node(listener.nid).data {
    Element(el) => match el.listeners {
      Some(ls) => match ls.get(listener.id) {
        Some(l) => {
          ls.remove(l.id)
          d.cmd(Listener({ nid: l.nid, id: l.id, kind: l.kind, cfg: l.cfg, bind: false }))
        }
        None => fail("target listener not found in element")
      }
      None => fail("target listener not found in element")
    }
    _ => fail_non_elm("unbind listener")
  }
}

pub fn Node::query(self: Node, query: NodeQuery) -> NodeValue raise {
  fn str_text(v: StrValue) -> String { match v { Empty => ""; String(v) => v } }
  fn js_text(v: JsValue) -> String {
    match v { String(v) => v; Int(v) => v.to_string(); Float(v) => v.to_string(); _ => "" }
  }
  match query {
    Node => Node(self.shared())
    Text => match self.data {
      Text(t) => Text(t)
      Element(_) => Text(flat_map(self.children(), child => match child.data {
        Text(t) => [t]; _ => []
      }).iter().join(""))
      Anchor(_) => Text("")
    }
    Attr(key) => match self.data {
      Element({ xmls: Some(xmls), .. }) => Attr(key, str_text(xmls.get(key).unwrap_or(Empty)))
      Element(_) => Attr(key, "")
      _ => fail("query attr expects element node")
    }
    Prop(key) => match self.data {
      Element({ props: Some(props), .. }) => Prop(key, js_text(props.get(key).unwrap_or(Empty)))
      Element(_) => Prop(key, "")
      _ => fail("query prop expects element node")
    }
    Style(key) => match self.data {
      Element({ styles: Some(styles), .. }) => Style(key, str_text(styles.get(key).unwrap_or(Empty)))
      Element({ props: Some(props), .. }) => Style(key, js_text(props.get("style").unwrap_or(Empty)))
      Element(_) => Style(key, "")
      _ => fail("query style expects element node")
    }
  }
}
pub fn Node::dispatch(self: Node, dom: Dom, ev: Event) -> Unit raise {
  ev.target = Some(self)
  match self.data {
    Element({ listeners, .. }) => {
      let mut hit = false
      let trigger = (l: ListenerObj) => {
        try { hit = true; (l.f)(ev); flush() } catch { e => dom.report(e.to_string()) }
      }
      if listeners is Some(ls) {
        let ids = []
        for entry in ls { if entry.1.kind == ev.kind { ids.push(entry.0) } }
        for id in ids { if ls.get(id) is Some(l) { trigger(l) } }
      }
      if !hit { fail("listener not found: \{ev.kind.to_string()}") }
    }
    _ => fail("dispatch expects element node")
  }
}

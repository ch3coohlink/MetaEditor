let test_dom_state : Ref[@lib.DomState] = Ref::new(@lib.new_dom_state())

fn reset_dom_state() -> Unit {
  test_dom_state.val = @lib.new_dom_state()
}

fn realize(child: @lib.Child) -> @lib.VNode {
  @lib.realize(test_dom_state.val, child)
}

fn get_cmds() -> Array[@lib.DomCmd] {
  @lib.get_cmds(test_dom_state.val)
}

fn is_remove(cmd: @lib.DomCmd, id: Int) -> Bool {
  match cmd {
    @lib.Remove(node_id) => node_id == id
    _ => false
  }
}

fn is_create(cmd: @lib.DomCmd, id: Int) -> Bool {
  match cmd {
    @lib.Create(node_id, _, _) => node_id == id
    _ => false
  }
}

fn is_insert_before(cmd: @lib.DomCmd, id: Int) -> Bool {
  match cmd {
    @lib.InsertBefore(_, child_id, _) => child_id == id
    _ => false
  }
}

fn find_text_node_id(cmds: Array[@lib.DomCmd], text: String) -> Int {
  for i = 0; i < cmds.length(); i = i + 1 {
    match cmds[i] {
      @lib.Text(id, value) => if value == text { return id }
      _ => ()
    }
  }
  panic()
}

fn find_parent_id(cmds: Array[@lib.DomCmd], child_id: Int) -> Int {
  for cmd in cmds {
    match cmd {
      @lib.Append(parent_id, id) => if id == child_id { return parent_id }
      @lib.InsertBefore(parent_id, id, _) => if id == child_id { return parent_id }
      _ => ()
    }
  }
  panic()
}

fn assert_no_cmd(cmds: Array[@lib.DomCmd], pred: (@lib.DomCmd) -> Bool) -> Unit {
  for cmd in cmds {
    if pred(cmd) { panic() }
  }
}

fn find_listen_callback_id(cmds: Array[@lib.DomCmd], node_id: Int, ev: String) -> Int {
  for cmd in cmds {
    match cmd {
      @lib.Listen(id, name, cb_id) => {
        if id == node_id && name == ev { return cb_id }
      }
      _ => ()
    }
  }
  panic()
}

fn assert_text(cmd: @lib.DomCmd, text: String) -> Unit {
  match cmd {
    @lib.Text(_, value) => if value != text { panic() }
    _ => panic()
  }
}

fn assert_create(cmd: @lib.DomCmd, tag: String, ns: String) -> Int {
  match cmd {
    @lib.Create(id, t, n) => {
      if t != tag { panic() }
      if ns != "" && n != ns { panic() }
      id
    }
    _ => panic()
  }
}

fn assert_attr(cmd: @lib.DomCmd, key: String, value: String) -> Unit {
  match cmd {
    @lib.Attr(_, k, v) => {
      if k != key { panic() }
      if v != value { panic() }
    }
    _ => panic()
  }
}

fn assert_append(cmd: @lib.DomCmd, parent_id: Int, child_id: Int) -> Unit {
  match cmd {
    @lib.Append(p, c) => {
      if p != parent_id { panic() }
      if c != child_id { panic() }
    }
    _ => panic()
  }
}

fn assert_listen(cmd: @lib.DomCmd, ev: String, node_id: Int) -> Int {
  match cmd {
    @lib.Listen(id, name, cb_id) => {
      if id != node_id { panic() }
      if name != ev { panic() }
      cb_id
    }
    _ => panic()
  }
}

fn assert_update_attr(cmd: @lib.DomCmd, key: String, value: String) -> Unit {
  match cmd {
    @lib.UpdateAttr(_, k, v) => {
      if k != key { panic() }
      if v != value { panic() }
    }
    _ => panic()
  }
}

test "h creates elements and attributes" {
  reset_dom_state()
  let _ = realize(@lib.h("div", [("class", @lib.S("btn")), ("id", @lib.S("main"))], []))
  let cmds = get_cmds()
  assert_eq(cmds.length(), 3)
  let _ = assert_create(cmds[0], "div", "")
  assert_attr(cmds[1], "class", "btn")
  assert_attr(cmds[2], "id", "main")
}

test "h handles children" {
  reset_dom_state()
  let parent = realize(@lib.h("div", [], [@lib.h("span", [], [])]))
  let cmds = get_cmds()
  // parent: Create
  // child: Create
  // Append(parent, child)
  assert_eq(cmds.length(), 3)
  let parent_id = assert_create(cmds[0], "div", "")
  let child_id = assert_create(cmds[1], "span", "")
  assert_append(cmds[2], parent_id, child_id)
  assert_eq(parent.id, parent_id)
}

test "h dispatches comp values" {
  reset_dom_state()
  let box = @lib.comp(fn(attrs, children) { @lib.h("section", attrs, children) })
  let node = realize(@lib.h(box, [("class", @lib.S("panel"))], [@lib.Str("ok")]))
  let cmds = get_cmds()
  assert_eq(cmds.length(), 5)
  assert_eq(node.id, assert_create(cmds[0], "section", ""))
  assert_attr(cmds[1], "class", "panel")
  let _ = assert_create(cmds[2], "", "")
  assert_text(cmds[3], "ok")
  assert_append(cmds[4], node.id, match cmds[2] { @lib.Create(id, _, _) => id; _ => panic() })
}

test "h nests comp values like regular children" {
  reset_dom_state()
  let box = @lib.comp(fn(attrs, children) { @lib.h("section", attrs, children) })
  let _ = realize(@lib.h("div", [], [
    @lib.h(box, [("class", @lib.S("panel"))], [@lib.Str("ok")])
  ]))
  let cmds = get_cmds()
  assert_eq(cmds.length(), 7)
  let div_id = assert_create(cmds[0], "div", "")
  let section_id = assert_create(cmds[1], "section", "")
  assert_attr(cmds[2], "class", "panel")
  let text_id = assert_create(cmds[3], "", "")
  assert_text(cmds[4], "ok")
  assert_append(cmds[5], section_id, text_id)
  assert_append(cmds[6], div_id, section_id)
}

test "h_map provides index getter and reruns on changes" {
  reset_dom_state()
  let items = @lib.cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = get_cmds()
  assert_eq(cmds.length(), 14)
  assert_eq(builds.val, 2)
  assert_text(cmds[6], "0:A")
  assert_text(cmds[11], "1:B")

  items.set([("B", 0), ("C", 1)])
  @lib.flush() catch { _ => panic() }
  let cmds2 = get_cmds()
  assert_eq(builds.val, 3)
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      @lib.Remove(_) => true
      _ => false
    }
  }))
  assert_eq(cmds2.filter(fn(cmd) {
    match cmd {
      @lib.Create(_, "li", _) => true
      _ => false
    }
  }).length(), 1)
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      @lib.InsertBefore(_, _, _) => true
      _ => false
    }
  }))
}

test "h_map keeps duplicate items separate" {
  reset_dom_state()
  let items = ["A", "A", "B"]
  let builds = Ref::new(0)
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.h_map(items, fn(x, i) {
        builds.val = builds.val + 1
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = get_cmds()
  assert_eq(cmds.length(), 19)
  assert_eq(builds.val, 3)
  assert_text(cmds[6], "0:A")
  assert_text(cmds[11], "1:A")
  assert_text(cmds[16], "2:B")
}

test "h_map watches source function dependencies" {
  reset_dom_state()
  let items = @lib.cel([("A", 9)])
  let source_runs = Ref::new(0)
  let builds = Ref::new(0)
  let source = fn() {
    source_runs.val = source_runs.val + 1
    items.get()
  }
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.h_map_dyn(source, fn(x, i) {
        builds.val = builds.val + 1
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = get_cmds()
  assert_eq(cmds.length(), 9)
  assert_eq(source_runs.val, 1)
  assert_eq(builds.val, 1)
  assert_text(cmds[6], "9:A")

  items.set([("B", 12)])
  @lib.flush() catch { _ => panic() }
  let cmds2 = get_cmds()
  assert_eq(source_runs.val, 2)
  assert_eq(builds.val, 2)
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      @lib.Remove(_) => true
      _ => false
    }
  }))
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      @lib.Text(_, "12:B") => true
      _ => false
    }
  }))
}

test "h_map_dyn keeps explicit indexes" {
  reset_dom_state()
  let items = @lib.cel([("A", 9), ("B", 10)])
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.h_map_dyn(fn() { items.get() }, fn(x, i) {
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = get_cmds()
  assert_eq(cmds.length(), 14)
  assert_text(cmds[6], "9:A")
  assert_text(cmds[11], "10:B")
}

test "h_map removes only missing keyed item" {
  @lib.reset_test_ui()
  let items = @lib.cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let initial = get_cmds()
  assert_eq(builds.val, 2)
  let a_text_id = find_text_node_id(initial, "0:A")
  let a_li_id = find_parent_id(initial, a_text_id)
  let b_text_id = find_text_node_id(initial, "1:B")
  let b_li_id = find_parent_id(initial, b_text_id)

  items.set([("B", 0)])
  @lib.flush() catch { _ => panic() }
  let cmds = get_cmds()
  assert_eq(builds.val, 2)
  assert_true(cmds.any(fn(cmd) { is_remove(cmd, a_li_id) }))
  assert_no_cmd(cmds, fn(cmd) { is_remove(cmd, b_li_id) })
  assert_no_cmd(cmds, fn(cmd) { is_create(cmd, b_li_id) })
}

test "h_map reorders kept keyed items without recreating them" {
  @lib.reset_test_ui()
  let items = @lib.cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let initial = get_cmds()
  assert_eq(builds.val, 2)
  let a_text_id = find_text_node_id(initial, "0:A")
  let a_li_id = find_parent_id(initial, a_text_id)
  let b_text_id = find_text_node_id(initial, "1:B")
  let b_li_id = find_parent_id(initial, b_text_id)

  items.set([("B", 0), ("A", 1)])
  @lib.flush() catch { _ => panic() }
  let cmds = get_cmds()
  assert_eq(builds.val, 2)
  assert_no_cmd(cmds, fn(cmd) { is_remove(cmd, a_li_id) || is_remove(cmd, b_li_id) })
  assert_no_cmd(cmds, fn(cmd) { is_create(cmd, a_li_id) || is_create(cmd, b_li_id) })
  assert_true(cmds.any(fn(cmd) { is_insert_before(cmd, a_li_id) || is_insert_before(cmd, b_li_id) }))
}

test "h_map adds render only for new keyed item" {
  @lib.reset_test_ui()
  let items = @lib.cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let _ = get_cmds()
  assert_eq(builds.val, 2)

  items.set([("A", 0), ("B", 1), ("C", 2)])
  @lib.flush() catch { _ => panic() }
  let cmds = get_cmds()
  assert_eq(builds.val, 3)
  assert_eq(cmds.filter(fn(cmd) {
    match cmd {
      @lib.Create(_, "li", _) => true
      _ => false
    }
  }).length(), 1)
}

test "h_map stops removed item effects" {
  @lib.reset_test_ui()
  let items = @lib.cel([("A", 0), ("B", 1)])
  let source = @lib.cel("x")
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.h_map_dyn(fn() { items.get() }, fn(x, i) {
        @lib.h("li", [], [
          @lib.Str("\{i()}:\{x}:"),
          @lib.Dyn(fn() { @lib.Str(source.get()) })
        ])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let initial = get_cmds()
  let a_text_id = find_text_node_id(initial, "0:A:")
  let a_li_id = find_parent_id(initial, a_text_id)

  items.set([("B", 0)])
  @lib.flush() catch { _ => panic() }
  let _ = get_cmds()
  source.set("y")
  @lib.flush() catch { _ => panic() }
  let cmds = get_cmds()
  assert_no_cmd(cmds, fn(cmd) { is_create(cmd, a_li_id) || is_remove(cmd, a_li_id) })
  assert_no_cmd(cmds, fn(cmd) {
    match cmd {
      @lib.UpdateText(id, _) => id == a_text_id
      @lib.Text(id, _) => id == a_text_id
      _ => false
    }
  })
}

test "h_map keeps listener registration stable for kept item" {
  @lib.reset_test_ui()
  let items = @lib.cel([("A", 0), ("B", 1)])
  let clicks = Ref::new(0)
  let seen_indexes: Ref[Array[Int]] = Ref::new([])
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.h_map_dyn(fn() { items.get() }, fn(x, i) {
        @lib.h("button", [
          ("onclick", @lib.E(() => {
            clicks.val = clicks.val + 1
            seen_indexes.val.push(i())
            ignore(x)
          }))
        ], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let initial = get_cmds()
  let a_text_id = find_text_node_id(initial, "0:A")
  let a_button_id = find_parent_id(initial, a_text_id)
  let a_cb_id = find_listen_callback_id(initial, a_button_id, "onclick")

  items.set([("B", 0), ("A", 1), ("C", 2)])
  @lib.flush() catch { _ => panic() }
  let cmds = get_cmds()
  assert_eq(cmds.filter(fn(cmd) {
    match cmd {
      @lib.Listen(id, "onclick", _) => id == a_button_id
      _ => false
    }
  }).length(), 0)

  @lib.trigger_callback(a_cb_id)
  assert_eq(clicks.val, 1)
  assert_eq(seen_indexes.val, [1])
}

test "h_map removes only one duplicate entry" {
  @lib.reset_test_ui()
  let items = @lib.cel([("A", 0), ("A", 1), ("B", 2)])
  let builds = Ref::new(0)
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let initial = get_cmds()
  assert_eq(builds.val, 3)
  let a0_text_id = find_text_node_id(initial, "0:A")
  let a0_li_id = find_parent_id(initial, a0_text_id)
  let a1_text_id = find_text_node_id(initial, "1:A")
  let a1_li_id = find_parent_id(initial, a1_text_id)
  let b_text_id = find_text_node_id(initial, "2:B")
  let b_li_id = find_parent_id(initial, b_text_id)

  items.set([("A", 0), ("B", 1)])
  @lib.flush() catch { _ => panic() }
  let cmds = get_cmds()
  assert_eq(builds.val, 3)
  assert_true(cmds.any(fn(cmd) { is_remove(cmd, a1_li_id) }))
  assert_no_cmd(cmds, fn(cmd) { is_remove(cmd, a0_li_id) || is_remove(cmd, b_li_id) })
  assert_no_cmd(cmds, fn(cmd) { is_create(cmd, a0_li_id) || is_create(cmd, b_li_id) })
}

test "svg namespace propagates through foreignObject" {
  reset_dom_state()
  let _ = realize(@lib.h("svg", [], [
    @lib.h("foreignObject", [], [
      @lib.h("span", [], [])
    ])
  ]))
  let cmds = get_cmds()
  assert_eq(cmds.length(), 5)
  let _ = assert_create(cmds[0], "svg", "http://www.w3.org/2000/svg")
  let _ = assert_create(cmds[1], "foreignObject", "http://www.w3.org/2000/svg")
  let _ = assert_create(cmds[2], "span", "http://www.w3.org/1999/xhtml")
}

test "h handles dynamic attributes" {
  reset_dom_state()
  let count = @lib.cel(0)
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("div", [("data-count", @lib.D(() => count.get().to_string()))], []))
    ()
  }) catch { _ => panic() }
  
  let cmds1 = get_cmds()
  // Create, UpdateAttr (triggered by first effect run)
  assert_eq(cmds1.length(), 2)
  assert_update_attr(cmds1[1], "data-count", "0")

  count.set(1)
  @lib.flush() catch { _ => panic() }
  let cmds2 = get_cmds()
  assert_eq(cmds2.length(), 1)
  assert_update_attr(cmds2[0], "data-count", "1")
}

test "Str and Dyn" {
  reset_dom_state()
  let val = @lib.cel("a")
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("div", [], [
      @lib.Str("hello"),
      @lib.Dyn(fn() { @lib.Str(val.get()) })
    ]))
    ()
  }) catch { _ => panic() }
  
  let cmds = get_cmds()
  assert_eq(cmds.length(), 10)

  val.set("b")
  @lib.flush() catch { _ => panic() }
  let cmds2 = get_cmds()
  assert_eq(cmds2.length(), 4)
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      @lib.Remove(_) => true
      _ => false
    }
  }))
}

test "events and callback triggering" {
  reset_dom_state()
  let clicked = Ref::new(false)
  let node = realize(@lib.h("button", [("onclick", @lib.E(() => { clicked.val = true }))], []))
  let cmds = get_cmds()
  
  assert_eq(cmds.length(), 2) // Create, Listen
  let cb_id = match cmds[1] {
    @lib.Listen(id, "onclick", cb_id) => {
      assert_eq(id, node.id)
      cb_id
    }
    _ => panic()
  }

  @lib.trigger_callback(cb_id)
  assert_eq(clicked.val, true)
}

test "remove emits cmd" {
  reset_dom_state()
  let node = realize(@lib.h("div", [], []))
  let _ = get_cmds()
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("div", [], [@lib.Dyn(fn() {
      @lib.remove(node)
      @lib.Null
    })]))
    ()
  }) catch { _ => panic() }
  let cmds = get_cmds()
  assert_true(cmds.any(fn(cmd) {
    match cmd {
      @lib.Remove(id) => id == node.id
      _ => false
    }
  }))
}

test "remove cleans subtree callbacks" {
  reset_dom_state()
  let child_clicked = Ref::new(0)
  let parent = realize(@lib.h("div", [], [
    @lib.h("button", [("onclick", @lib.E(() => child_clicked.val = child_clicked.val + 1))], [])
  ]))
  let cmds = get_cmds()
  let cb_id = match cmds[2] {
    @lib.Listen(_, "onclick", cb_id) => cb_id
    _ => panic()
  }

  @lib.remove(parent)
  let _ = get_cmds()
  @lib.trigger_callback(cb_id)
  assert_eq(child_clicked.val, 0)
}

test "remove stops dynamic updates for subtree" {
  reset_dom_state()
  let source = @lib.cel("a")
  let stop = @lib.scope(() => {
    let parent = realize(@lib.h("div", [], [@lib.Dyn(fn() { @lib.Str(source.get()) })]))
    @lib.remove(parent)
  }) catch { _ => panic() }
  let _ = get_cmds()

  source.set("b")
  @lib.flush() catch { _ => panic() }
  let cmds = get_cmds()
  assert_eq(cmds.length(), 0)
  stop()
}

test "Dyn handles nested arrays and components" {
  reset_dom_state()
  let list = @lib.cel(["A", "B"])
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("ul", [], [
      @lib.Dyn(fn() { 
        @lib.Arr(list.get().map(fn(x) { @lib.h("li", [], [@lib.Str(x)]) }))
      })
    ]))
    ()
  }) catch { _ => panic() }
  
  let cmds = get_cmds()
  // Create(ul), Create(anchor), Text(anchor, ""), Append(ul, anchor), 
  // Initial run of Dyn:
  // Create(liA), Create(textA), Text(textA, "A"), Append(liA, textA), InsertBefore(ul, liA, anchor)
  // Create(liB), Create(textB), Text(textB, "B"), Append(liB, textB), InsertBefore(ul, liB, anchor)
  assert_eq(cmds.length(), 14)

  list.set(["C"])
  @lib.flush() catch { _ => panic() }
  let cmds2 = get_cmds()
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      @lib.Remove(_) => true
      _ => false
    }
  }))
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      @lib.Text(_, "C") => true
      _ => false
    }
  }))
  assert_true(cmds2.any(fn(cmd) {
    match cmd {
      @lib.InsertBefore(_, _, _) => true
      _ => false
    }
  }))
}


test "to_json gives compact array format" {
  let cmd = @lib.Text(1, "\"")
  assert_eq(cmd.to_json(), "[1,1,\"\\\"\"]")
}

test "SetStyle emits correct json" {
  let cmd = @lib.SetStyle(5, "color", "red")
  assert_eq(cmd.to_json(), "[10,5,\"color\",\"red\"]")
}

test "RemoveStyle emits correct json" {
  let cmd = @lib.RemoveStyle(5, "color")
  assert_eq(cmd.to_json(), "[11,5,\"color\"]")
}

test "RemoveAttr emits correct json" {
  let cmd = @lib.RemoveAttr(5, "class")
  assert_eq(cmd.to_json(), "[12,5,\"class\"]")
}

test "HostCmd emits correct json" {
  let cmd = @lib.HostCmd(3, "focus")
  assert_eq(cmd.to_json(), "[13,3,\"focus\"]")
}

test "EventData from_json parses pipe format" {
  let ev = @lib.EventData::from_json("Enter|Enter|1|0|0|0")
  assert_eq(ev.key, "Enter")
  assert_eq(ev.code, "Enter")
  assert_eq(ev.ctrl, true)
  assert_eq(ev.shift, false)
  assert_eq(ev.alt, false)
  assert_eq(ev.meta, false)
}

test "EK callback receives event data" {
  reset_dom_state()
  let received = Ref::new(@lib.EventData::default())
  let node = realize(@lib.h("div", [("onkeydown", @lib.EK(fn(ev) { received.val = ev }))], []))
  let cmds = get_cmds()
  assert_eq(cmds.length(), 2) // Create, Listen
  let cb_id = assert_listen(cmds[1], "onkeydown", node.id)
  let ev = @lib.EventData::from_json("a|KeyA|0|0|0|0")
  @lib.trigger_callback_ev(cb_id, ev)
  assert_eq(received.val.key, "a")
  assert_eq(received.val.code, "KeyA")
}

test "host command helpers emit correct cmds" {
  reset_dom_state()
  let _ = @lib.scope(() => {
    let _ = realize(@lib.h("div", [], [@lib.Dyn(fn() {
      @lib.focus_node(10)
      @lib.blur_node(11)
      @lib.scroll_into_view(12)
      @lib.Null
    })]))
    ()
  }) catch { _ => panic() }
  let cmds = get_cmds()
  assert_true(cmds.any(fn(cmd) {
    match cmd {
      @lib.HostCmd(10, "focus") => true
      _ => false
    }
  }))
  assert_true(cmds.any(fn(cmd) {
    match cmd {
      @lib.HostCmd(11, "blur") => true
      _ => false
    }
  }))
  assert_true(cmds.any(fn(cmd) {
    match cmd {
      @lib.HostCmd(12, "scrollIntoView") => true
      _ => false
    }
  }))
}

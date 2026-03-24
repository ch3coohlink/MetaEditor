fn assert_remove(cmd: @lib.DomCmd) -> Unit {
  match cmd {
    @lib.Remove(_) => ()
    _ => panic()
  }
}

fn assert_insert_before(cmd: @lib.DomCmd) -> Unit {
  match cmd {
    @lib.InsertBefore(_, _, _) => ()
    _ => panic()
  }
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

fn assert_host_cmd(cmd: @lib.DomCmd, id: Int, name: String) -> Unit {
  match cmd {
    @lib.HostCmd(n, cmd_name) => {
      if n != id { panic() }
      if cmd_name != name { panic() }
    }
    _ => panic()
  }
}

test "h creates elements and attributes" {
  @lib.get_cmds().clear() // clear any existing cmds
  let _ = @lib.realize(@lib.h("div", [("class", @lib.S("btn")), ("id", @lib.S("main"))], []))
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 3)
  let _ = assert_create(cmds[0], "div", "")
  assert_attr(cmds[1], "class", "btn")
  assert_attr(cmds[2], "id", "main")
}

test "h handles children" {
  @lib.get_cmds().clear()
  let parent = @lib.realize(@lib.h("div", [], [@lib.h("span", [], [])]))
  let cmds = @lib.get_cmds()
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
  @lib.get_cmds().clear()
  let box = @lib.comp(fn(attrs, children) { @lib.h("section", attrs, children) })
  let node = @lib.realize(@lib.h(box, [("class", @lib.S("panel"))], [@lib.Str("ok")]))
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 5)
  assert_eq(node.id, assert_create(cmds[0], "section", ""))
  assert_attr(cmds[1], "class", "panel")
  let _ = assert_create(cmds[2], "", "")
  assert_text(cmds[3], "ok")
  assert_append(cmds[4], node.id, match cmds[2] { @lib.Create(id, _, _) => id; _ => panic() })
}

test "h nests comp values like regular children" {
  @lib.get_cmds().clear()
  let box = @lib.comp(fn(attrs, children) { @lib.h("section", attrs, children) })
  let _ = @lib.realize(@lib.h("div", [], [
    @lib.h(box, [("class", @lib.S("panel"))], [@lib.Str("ok")])
  ]))
  let cmds = @lib.get_cmds()
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
  @lib.get_cmds().clear()
  let items = @lib.cel([("A", 0), ("B", 1)])
  let builds = Ref::new(0)
  let _ = @lib.scope(() => {
    let _ = @lib.realize(@lib.h("ul", [], [
      @lib.h_map_dyn(fn() { items.get() }, fn(x, i) {
        builds.val = builds.val + 1
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 14)
  assert_eq(builds.val, 2)
  assert_text(cmds[6], "0:A")
  assert_text(cmds[11], "1:B")

  items.set([("B", 0), ("C", 1)])
  @lib.flush() catch { _ => panic() }
  let cmds2 = @lib.get_cmds()
  assert_eq(cmds2.length(), 12)
  assert_eq(builds.val, 3)
  assert_remove(cmds2[0])
  assert_remove(cmds2[1])
  assert_insert_before(cmds2[6])
  assert_insert_before(cmds2[11])
}

test "h_map keeps duplicate items separate" {
  @lib.get_cmds().clear()
  let items = ["A", "A", "B"]
  let builds = Ref::new(0)
  let _ = @lib.scope(() => {
    let _ = @lib.realize(@lib.h("ul", [], [
      @lib.h_map(items, fn(x, i) {
        builds.val = builds.val + 1
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 19)
  assert_eq(builds.val, 3)
  assert_text(cmds[6], "0:A")
  assert_text(cmds[11], "1:A")
  assert_text(cmds[16], "2:B")
}

test "h_map watches source function dependencies" {
  @lib.get_cmds().clear()
  let items = @lib.cel([("A", 9)])
  let source_runs = Ref::new(0)
  let builds = Ref::new(0)
  let source = fn() {
    source_runs.val = source_runs.val + 1
    items.get()
  }
  let _ = @lib.scope(() => {
    let _ = @lib.realize(@lib.h("ul", [], [
      @lib.h_map_dyn(source, fn(x, i) {
        builds.val = builds.val + 1
        @lib.h("li", [], [@lib.Str("\{i()}:\{x}")])
      })
    ]))
    ()
  }) catch { _ => panic() }
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 9)
  assert_eq(source_runs.val, 1)
  assert_eq(builds.val, 1)
  assert_text(cmds[6], "9:A")

  items.set([("B", 12)])
  @lib.flush() catch { _ => panic() }
  let cmds2 = @lib.get_cmds()
  assert_eq(cmds2.length(), 6)
  assert_eq(source_runs.val, 2)
  assert_eq(builds.val, 2)
  assert_remove(cmds2[0])
  assert_text(cmds2[3], "12:B")
}

test "svg namespace propagates through foreignObject" {
  @lib.get_cmds().clear()
  let _ = @lib.realize(@lib.h("svg", [], [
    @lib.h("foreignObject", [], [
      @lib.h("span", [], [])
    ])
  ]))
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 5)
  let _ = assert_create(cmds[0], "svg", "http://www.w3.org/2000/svg")
  let _ = assert_create(cmds[1], "foreignObject", "http://www.w3.org/2000/svg")
  let _ = assert_create(cmds[2], "span", "http://www.w3.org/1999/xhtml")
}

test "h handles dynamic attributes" {
  @lib.get_cmds().clear()
  let count = @lib.cel(0)
  let _ = @lib.scope(() => {
    let _ = @lib.realize(@lib.h("div", [("data-count", @lib.D(() => count.get().to_string()))], []))
    ()
  }) catch { _ => panic() }
  
  let cmds1 = @lib.get_cmds()
  // Create, UpdateAttr (triggered by first effect run)
  assert_eq(cmds1.length(), 2)
  assert_update_attr(cmds1[1], "data-count", "0")

  count.set(1)
  @lib.flush() catch { _ => panic() }
  let cmds2 = @lib.get_cmds()
  assert_eq(cmds2.length(), 1)
  assert_update_attr(cmds2[0], "data-count", "1")
}

test "Str and Dyn" {
  @lib.get_cmds().clear()
  let val = @lib.cel("a")
  let _ = @lib.scope(() => {
    let _ = @lib.realize(@lib.h("div", [], [
      @lib.Str("hello"),
      @lib.Dyn(fn() { @lib.Str(val.get()) })
    ]))
    ()
  }) catch { _ => panic() }
  
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 10)

  val.set("b")
  @lib.flush() catch { _ => panic() }
  let cmds2 = @lib.get_cmds()
  assert_eq(cmds2.length(), 4)
  assert_remove(cmds2[0])
}

test "events and callback triggering" {
  @lib.get_cmds().clear()
  let clicked = Ref::new(false)
  let node = @lib.realize(@lib.h("button", [("onclick", @lib.E(() => { clicked.val = true }))], []))
  let cmds = @lib.get_cmds()
  
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
  @lib.get_cmds().clear()
  let node = @lib.realize(@lib.h("div", [], []))
  @lib.remove(node)
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 2)
  assert_remove(cmds[1])
}

test "remove cleans subtree callbacks" {
  @lib.get_cmds().clear()
  let child_clicked = Ref::new(0)
  let parent = @lib.realize(@lib.h("div", [], [
    @lib.h("button", [("onclick", @lib.E(() => child_clicked.val = child_clicked.val + 1))], [])
  ]))
  let cmds = @lib.get_cmds()
  let cb_id = match cmds[2] {
    @lib.Listen(_, "onclick", cb_id) => cb_id
    _ => panic()
  }

  @lib.remove(parent)
  let _ = @lib.get_cmds()
  @lib.trigger_callback(cb_id)
  assert_eq(child_clicked.val, 0)
}

test "remove stops dynamic updates for subtree" {
  @lib.get_cmds().clear()
  let source = @lib.cel("a")
  let stop = @lib.scope(() => {
    let parent = @lib.realize(@lib.h("div", [], [@lib.Dyn(fn() { @lib.Str(source.get()) })]))
    @lib.remove(parent)
  }) catch { _ => panic() }
  let _ = @lib.get_cmds()

  source.set("b")
  @lib.flush() catch { _ => panic() }
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 0)
  stop()
}

test "Dyn handles nested arrays and components" {
  @lib.get_cmds().clear()
  let list = @lib.cel(["A", "B"])
  let _ = @lib.scope(() => {
    let _ = @lib.realize(@lib.h("ul", [], [
      @lib.Dyn(fn() { 
        @lib.Arr(list.get().map(fn(x) { @lib.h("li", [], [@lib.Str(x)]) }))
      })
    ]))
    ()
  }) catch { _ => panic() }
  
  let cmds = @lib.get_cmds()
  // Create(ul), Create(anchor), Text(anchor, ""), Append(ul, anchor), 
  // Initial run of Dyn:
  // Create(liA), Create(textA), Text(textA, "A"), Append(liA, textA), InsertBefore(ul, liA, anchor)
  // Create(liB), Create(textB), Text(textB, "B"), Append(liB, textB), InsertBefore(ul, liB, anchor)
  assert_eq(cmds.length(), 14)

  list.set(["C"])
  @lib.flush() catch { _ => panic() }
  let cmds2 = @lib.get_cmds()
  // Dyn update:
  // Remove(liA), Cleanup(liA), Remove(liB), Cleanup(liB)
  // Create(liC), Create(textC), Text(textC, "C"), Append(liC, textC), InsertBefore(ul, liC, anchor)
  assert_eq(cmds2.length(), 7) 
  assert_remove(cmds2[0])
  assert_remove(cmds2[1])
  assert_insert_before(cmds2[6])
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
  @lib.get_cmds().clear()
  let received = Ref::new(@lib.EventData::default())
  let node = @lib.realize(@lib.h("div", [("onkeydown", @lib.EK(fn(ev) { received.val = ev }))], []))
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 2) // Create, Listen
  let cb_id = assert_listen(cmds[1], "onkeydown", node.id)
  let ev = @lib.EventData::from_json("a|KeyA|0|0|0|0")
  @lib.trigger_callback_ev(cb_id, ev)
  assert_eq(received.val.key, "a")
  assert_eq(received.val.code, "KeyA")
}

test "host command helpers emit correct cmds" {
  @lib.get_cmds().clear()
  @lib.focus_node(10)
  @lib.blur_node(11)
  @lib.scroll_into_view(12)
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 3)
  assert_host_cmd(cmds[0], 10, "focus")
  assert_host_cmd(cmds[1], 11, "blur")
  assert_host_cmd(cmds[2], 12, "scrollIntoView")
}

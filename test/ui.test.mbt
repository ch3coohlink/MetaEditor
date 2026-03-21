test "h creates elements and attributes" {
  @lib.get_cmds().clear() // clear any existing cmds
  let _ = @lib.h("div", [("class", @lib.S("btn")), ("id", @lib.S("main"))], [])
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 3)
  // Check Create
  match cmds[0] {
    @lib.Create(_, "div") => ()
    _ => panic()
  }
  // Check Attrs
  match cmds[1] {
    @lib.Attr(_, "class", "btn") => ()
    _ => panic()
  }
  match cmds[2] {
    @lib.Attr(_, "id", "main") => ()
    _ => panic()
  }
}

test "h handles children" {
  @lib.get_cmds().clear()
  let child = @lib.h("span", [], [])
  let parent = @lib.h("div", [], [@lib.Node(child)])
  let cmds = @lib.get_cmds()
  // child: Create
  // parent: Create, Append
  assert_eq(cmds.length(), 3)
  match cmds[0] { @lib.Create(cid, "span") => assert_eq(cid, child.id); _ => panic() }
  match cmds[1] { @lib.Create(pid, "div") => assert_eq(pid, parent.id); _ => panic() }
  match cmds[2] { @lib.Append(p, c) => { assert_eq(p, parent.id); assert_eq(c, child.id) }; _ => panic() }
}

test "h handles dynamic attributes" {
  @lib.get_cmds().clear()
  let count = @lib.cel(0)
  let _ = @lib.scope(() => {
    let _ = @lib.h("div", [("data-count", @lib.D(() => count.get().to_string()))], [])
    ()
  }) catch { _ => panic() }
  
  let cmds1 = @lib.get_cmds()
  // Create, UpdateAttr (triggered by first effect run)
  assert_eq(cmds1.length(), 2)
  match cmds1[1] { @lib.UpdateAttr(_, "data-count", "0") => (); _ => panic() }

  count.set(1)
  @lib.flush() catch { _ => panic() }
  let cmds2 = @lib.get_cmds()
  assert_eq(cmds2.length(), 1)
  match cmds2[0] { @lib.UpdateAttr(_, "data-count", "1") => (); _ => panic() }
}

test "Str and Dyn" {
  @lib.get_cmds().clear()
  let val = @lib.cel("a")
  let _ = @lib.scope(() => {
    let _ = @lib.h("div", [], [
      @lib.Str("hello"),
      @lib.Dyn(fn() { @lib.Str(val.get()) })
    ])
    ()
  }) catch { _ => panic() }
  
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 10)

  val.set("b")
  @lib.flush() catch { _ => panic() }
  let cmds2 = @lib.get_cmds()
  assert_eq(cmds2.length(), 4)
  match cmds2[0] { @lib.Remove(_) => (); _ => panic() }
}

test "events and callback triggering" {
  @lib.get_cmds().clear()
  let clicked = Ref::new(false)
  let node = @lib.h("button", [("onclick", @lib.E(() => { clicked.val = true }))], [])
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
  let node = @lib.h("div", [], [])
  @lib.remove(node)
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 2)
  match cmds[1] {
    @lib.Remove(id) => assert_eq(id, node.id)
    _ => panic()
  }
}

test "remove cleans subtree callbacks" {
  @lib.get_cmds().clear()
  let child_clicked = Ref::new(0)
  let child = @lib.h("button", [("onclick", @lib.E(() => child_clicked.val = child_clicked.val + 1))], [])
  let parent = @lib.h("div", [], [@lib.Node(child)])
  let cmds = @lib.get_cmds()
  let cb_id = match cmds[1] {
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
    let parent = @lib.h("div", [], [@lib.Dyn(fn() { @lib.Str(source.get()) })])
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
    let _ = @lib.h("ul", [], [
      @lib.Dyn(fn() { 
        @lib.Arr(list.get().map(fn(x) { @lib.Node(@lib.h("li", [], [@lib.Str(x)])) }))
      })
    ])
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
  match cmds2[0] { @lib.Remove(_) => (); _ => panic() }
  match cmds2[1] { @lib.Remove(_) => (); _ => panic() }
  match cmds2[6] { @lib.InsertBefore(_, _, _) => (); _ => panic() }
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
  let node = @lib.h("div", [("onkeydown", @lib.EK(fn(ev) { received.val = ev }))], [])
  let cmds = @lib.get_cmds()
  assert_eq(cmds.length(), 2) // Create, Listen
  let cb_id = match cmds[1] {
    @lib.Listen(id, "onkeydown", cb_id) => { assert_eq(id, node.id); cb_id }
    _ => panic()
  }
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
  match cmds[0] { @lib.HostCmd(10, "focus") => (); _ => panic() }
  match cmds[1] { @lib.HostCmd(11, "blur") => (); _ => panic() }
  match cmds[2] { @lib.HostCmd(12, "scrollIntoView") => (); _ => panic() }
}


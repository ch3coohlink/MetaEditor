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
  let parent = @lib.h("div", [], [child])
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

test "text and text_dyn" {
  @lib.get_cmds().clear()
  let _ = @lib.text("hello")
  let cmds1 = @lib.get_cmds()
  assert_eq(cmds1.length(), 2) // Create, Text
  match cmds1[1] { @lib.Text(_, "hello") => (); _ => panic() }

  let val = @lib.cel("a")
  let _ = @lib.scope(() => {
    let _ = @lib.text_dyn(() => val.get())
    ()
  }) catch { _ => panic() }
  
  let cmds2 = @lib.get_cmds()
  assert_eq(cmds2.length(), 2) // Create, UpdateText
  match cmds2[1] { @lib.UpdateText(_, "a") => (); _ => panic() }

  val.set("b")
  @lib.flush() catch { _ => panic() }
  let cmds3 = @lib.get_cmds()
  assert_eq(cmds3.length(), 1)
  match cmds3[0] { @lib.UpdateText(_, "b") => (); _ => panic() }
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

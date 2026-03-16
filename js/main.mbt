// JS 桥接 FFI
extern "js" fn js_apply(cmds : Array[@lib.DomCmd]) = "mbt_bridge.apply_batch"

pub fn trigger_callback(id : Int) -> Unit {
  @lib.trigger_callback(id)
}

fn main {
  // 1. 初始化桥接
  @lib.init_bridge(js_apply)
  
  let _ = try {
    let _ = @lib.scope(fn() {
      // 2. 状态
      let count = @lib.cel(0)
      
      // 3. UI 结构
      let root = @lib.h("div", [
        ("style", @lib.S("text-align: center; margin-top: 50px; font-family: sans-serif;"))
        ], [
        @lib.h("h1", [], [@lib.text("MoonBit + JS Thin Bridge")]),
        @lib.h("div", [("style", @lib.S("font-size: 3rem; margin: 20px;"))], [
           @lib.text_dyn(fn() { count.get().to_string() })
        ]),
        @lib.h("button", [
          ("onclick", @lib.E(fn() { count.set(count.get() + 1) })),
          ("style", @lib.S("padding: 10px 20px; font-size: 1.2rem; cursor: pointer;"+
            " background: #4caf50; color: white; border: none; border-radius: 4px;"))
        ], [@lib.text("Increment")]),
        @lib.h("button", [
          ("onclick", @lib.E(fn() { count.set(count.get() - 1) })),
          ("style", @lib.S("padding: 10px 20px; font-size: 1.2rem; cursor: pointer; "+
            "background: #f44336; color: white; border: none; border-radius: 4px; margin-left: 10px;"))
        ], [@lib.text("Decrement")])
      ])
      
      // 4. 挂载
      @lib.emit(Append(0, root.id))
    })
    ()
  } catch { _ => () }
  
  // 5. 初始渲染
  let _ = try { @lib.flush() } catch { _ => () }
}

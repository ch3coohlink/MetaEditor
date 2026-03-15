// JS 桥接 FFI
extern "js" fn js_apply(cmds : Array[DomCmd]) = "mbt_bridge.apply_batch"

fn main {
  // 1. 初始化桥接
  init_bridge(js_apply)
  
  let _ = try {
    let _ = scope(fn() {
      // 2. 状态
      let count = cel(0)
      
      // 3. UI 结构
      let root = h("div", [("style", S("text-align: center; margin-top: 50px; font-family: sans-serif;"))], [
        h("h1", [], [text("MoonBit + JS Thin Bridge")]),
        h("div", [("style", S("font-size: 3rem; margin: 20px;"))], [
           text_dyn(fn() { count.get().to_string() })
        ]),
        h("button", [
          ("onclick", E(fn() { count.set(count.get() + 1) })),
          ("style", S("padding: 10px 20px; font-size: 1.2rem; cursor: pointer; background: #4caf50; color: white; border: none; border-radius: 4px;"))
        ], [text("Increment")]),
        h("button", [
          ("onclick", E(fn() { count.set(count.get() - 1) })),
          ("style", S("padding: 10px 20px; font-size: 1.2rem; cursor: pointer; background: #f44336; color: white; border: none; border-radius: 4px; margin-left: 10px;"))
        ], [text("Decrement")])
      ])
      
      // 4. 挂载
      emit(Append(0, root.id))
    })
    ()
  } catch { _ => () }
  
  // 5. 初始渲染
  let _ = try { flush() } catch { _ => () }
}

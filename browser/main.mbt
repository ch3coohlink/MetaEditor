extern "js" fn js_apply(cmds : Array[@lib.DomCmd]) = "mbt_bridge.apply_batch"
extern "js" fn js_connect_and_listen() = "mbt_bridge.connect_to_core"

fn main {
  // 1. 初始化浏览器本地桥接
  @lib.init_bridge(fn(cmds) {
    js_apply(cmds)
  })

  // 2. 启动应用业务逻辑（本地模式）
  @app.start()

  // 3. 同时也启动远程连接监听（可选，取决于是否处于投影模式）
  js_connect_and_listen()
}

pub fn trigger_callback(id : Int) -> Unit {
  @lib.trigger_callback(id)
}

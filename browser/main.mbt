extern "js" fn js_apply(cmds : Array[String]) = "mbt_bridge.apply_batch"
extern "js" fn js_connect_and_listen() = "mbt_bridge.connect_to_core"

fn main {
  // 1. 初始化投影采集器
  // 在投影模式下，浏览器不运行本地逻辑(@app.start)，而是等待远程指令
  @lib.init_bridge(js_apply)

  // 2. 只有在本地测试模式下才取消下面注释
  // @lib.scope(fn() { @app.start() })

  // 3. 核心：建立与远程控制塔的连接
  js_connect_and_listen()
}

pub fn trigger_callback(id : Int) -> Unit {
  @lib.trigger_callback(id)
}
pub fn trigger_query(name : String) -> String {
  @lib.trigger_query(name)
}

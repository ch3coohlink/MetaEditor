// JS 桥接 FFI (Node.js 环境)
extern "js" fn js_send_cmds(cmds : Array[String]) = "mbt_server.send_batch"
extern "js" fn js_start_server() = "mbt_server.start"

fn main {
  // 1. 初始化本地逻辑到 JS 的桥接
  @lib.init_bridge(js_send_cmds)

  // 2. 启动应用业务逻辑（建立根作用域以允许创建 effect）
  let _ = try {
    let _ = @lib.scope(fn() {
      @app.start()
    })
    ()
  } catch {
    e => println("App Startup Failed: \{e}")
  }

  // 3. 启动 WebSocket 服务器
  js_start_server()
}


pub fn trigger_callback(id : Int) -> Unit {
  @lib.trigger_callback(id)
}

pub fn trigger_callback_ev(id : Int, data : String) -> Unit {
  @lib.trigger_callback_ev(id, @lib.EventData::from_json(data))
}

pub fn trigger_query(name : String) -> String {
  @lib.trigger_query(name)
}


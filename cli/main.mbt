fn main {
  // 1. 初始化 Native 桥接（将指令序列化并输出）
  @lib.init_bridge(fn(cmds) {
    let mut s = "["
    for i = 0; i < cmds.length(); i = i + 1 {
      s = s + cmds[i].to_json()
      if i < cmds.length() - 1 {
        s = s + ","
      }
    }
    s = s + "]"
    println("UI_SYNC:\{s}")
  })

  // 2. 启动应用业务逻辑
  @app.start()

  // 3. 进入事件循环
  println("CORE_READY")
}

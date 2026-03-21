async test "native websocket server works" {
  @async.with_task_group(group => {
    let addr = @socket.Addr::parse("127.0.0.1:19101")
    group.spawn_bg(no_wait=true, () => serve(addr))
    @async.sleep(50)
    let ws = @websocket.connect("ws://127.0.0.1:19101/ws")
    defer ws.close()
    ws.send_text("ping")
    inspect(ws.recv().read_all().text(), content="ping")
    ws.send_binary("pong")
    inspect(ws.recv().read_all().text(), content="pong")
    ws.send_close()
  })
}

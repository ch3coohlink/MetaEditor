pub async fn serve(addr : @socket.Addr) -> Unit {
  let server = @http.Server::new(addr)
  println("native websocket server listening on \{addr}")
  server.run_forever((request, _, conn) => {
    guard request.path is "/ws" else {
      conn.send_response(404, "NotFound")
    }
    let ws = @websocket.from_http_server(request, conn)
    defer ws.close()
    try {
      for ;; {
        let msg = ws.recv()
        match msg.kind {
          Text => ws.send_text(msg.read_all().text())
          Binary => ws.send_binary(msg.read_all().binary())
        }
      }
    } catch {
      @websocket.ConnectionClosed(_, _) => ()
      e => println("websocket client error: \{e}")
    }
  })
}

async fn main {
  let _ = @async.now()
  let addr = @socket.Addr::parse("127.0.0.1:9101") catch { _ => abort("invalid default addr") }
  serve(addr)
}

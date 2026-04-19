fn err(id: Int, msg: String) -> ResMsg {{ id, body: Err(msg) }}
fn pong(id: Int) -> ResMsg {{ id, body: Pong }}
fn hello_ack(id: Int, session: String) -> ResMsg {{ id, body: HelloAck({ session: session }) }}
fn src_event(event: Event) -> @src.Event { @src.Event::new(event.kind, event.data) }
async fn Runtime::reject(self: Runtime, conn: Conn, id: Int, msg: String) -> Unit raise {
  self.flush(conn..send(Res(err(id, msg))).id)
}
fn req_tag(tag: String) -> Bool {
  tag == "Hello" || tag == "Ping" || tag == "QueryReq" || tag == "ReadReq" ||
  tag == "Dispatch" || tag == "Trigger" || tag == "CliReq"
}
pub async fn Runtime::serve_ws(self: Runtime, conn: Conn) -> Unit raise {
  let msg = conn.recv()
  guard msg.kind is Text else { return self.reject(conn, 0, "text_only") }
  let json = parse(msg.read_all().text()) catch {
    _ => return self.reject(conn, 0, "invalid_json")
  }
  let tag = match json {
    Object(obj) => match obj.get("body") {
      Some(String(tag)) => tag
      Some(Array([String(tag), ..])) => tag
      _ => return self.reject(conn, 0, "invalid_message")
    }
    _ => return self.reject(conn, 0, "invalid_message")
  }
  if req_tag(tag) {
    let req: ReqMsg = from_json(json) catch { _ => return self.reject(conn, 0, "invalid_message") }
    let res = (match req.body {
      Hello(hello) => {
        let res = match hello.role {
          Browser => if hello.session == "" { err(req.id, "missing_session") }
            else { hello_ack(req.id, hello.session) }
          Client => if hello.session == "" { err(req.id, "missing_session") }
            else { hello_ack(req.id, hello.session) }
        }
        conn.role = match hello.role { Browser => "Browser"; Client => "Client" }
        conn.session = hello.session
        if conn.role == "Browser" { self.browsers.set(hello.session, conn.id) }
        conn.send(Res(res)); self.flush(conn.id)
        guard res.body is HelloAck(_) else { return }
        if conn.role == "Browser" {
          ignore(self.instance(conn.session))
          self.replay(conn.id)
          self.flush(conn.id)
        }
        return
      }
      Ping => pong(req.id)
      QueryReq(q) => {
        let rt = self.instance(q.browser)
        { id: req.id, body: Res::QueryRes(rt.query(q.path, q.query)) }
      }
      ReadReq(q) => {
        match self.browsers.get(q.browser) {
          Some(browser_id) => {
            let id = (self.req_id)()
            self.track(id, conn.id)
            self.conn(browser_id).send(Req({ id, body: ReadReq(q) }))
            self.flush(browser_id)
            return
          }
          None => err(req.id, "no_browser")
        }
      }
      Dispatch(q) => {
        self.instance(q.browser).dispatch(q.path, src_event(q.event))
        { id: req.id, body: Ok }
      }
      Trigger(q) => {
        self.instance(conn.session).trigger(q.node, src_event(q.event)) catch {
          // 猴子补丁: 有时候收到 pointerup 事件的时候, 会有一个迟到的 pointermove 事件
          // 这里直接沉默了这个错误, 但更好的做法是让 service 的事件处理顺序和浏览器一致
          e => if !e.to_string().contains("listener not found: ") { raise e }
        }
        { id: req.id, body: Ok }
      }
      CliReq(q) => {
        let cmd = CMD::new(["repl", ..CLIArgs::split(q)], rt=Some(self))
        { id: req.id, body: Res::CliRes(cmd.exec(is_repl=true, is_local=true)) }
      }
    }) catch { e => err(req.id, e.to_string()) }
    conn.send(Res(res))
    self.flush(conn.id)
    return
  }
  match conn.role {
    "Browser" => {
      let res: ResMsg = from_json(json) catch { _ => return self.reject(conn, 0, "invalid_message") }
      match res.body {
        ReadRes(_) | Err(_) => match self.take_owner(res.id) {
          Some(Conn(owner)) => { self.flush(self.conn(owner)..send(Res(res)).id); return }
          Some(Wait(q)) => {
            ignore(q.try_put(match res.body {
              ReadRes(v) => Result::Ok(v)
              Err(msg) => Result::Err(msg)
              _ => panic()
            }) catch { _ => false })
            return
          }
          Some(Apply(apply)) => {
            apply(match res.body { ReadRes(v) => v; Err(_) => []; _ => panic() }) catch {
              e => self.report(e)
            }
            self.flush(conn.id)
            return
          }
          None => return
        }
        _ => return self.reject(conn, 0, "invalid_message")
      }
    }
    _ => return self.reject(conn, 0, "invalid_message")
  }
}

struct Client { ws: WS; mut id: Int }
fn Client::new(ws: WS) -> Client {{ ws, id: 1 }}
pub fn Client::close(self: Client) -> Unit { self.ws.close() }
pub async fn Client::connect(port: Int) -> Client raise {
  let client = Client::new(@websocket.connect("ws://127.0.0.1:\{port}\{http_path_ws}"))
  match client.request(id => { id, body: Hello({ role: Client, session: "client-\{current_pid_ffi()}" }) }) {
    HelloAck(_) => client
    _ => { client.close(); raise ServiceError("invalid hello response") }
  }
}
fn Client::recv(text: String, expected: Int) -> Res raise {
  let res: ResMsg = from_json(parse(text)) catch { _ => raise ServiceError("invalid response") }
  if res.id != expected { raise ServiceError("unexpected response id: \{res.id}") }
  match res.body { Err(msg) => raise ServiceError(msg); body => body }
}
async fn Client::send(self: Client, req: ReqMsg) -> Res raise {
  let id = self.id
  self.ws.send_text(req.to_json().stringify())
  let body = Client::recv(self.ws.recv().read_all().text(), id)
  self.id = self.id + 1
  body
}
async fn Client::request(self: Client, req: (Int) -> ReqMsg raise) -> Res raise {
  self.send(req(self.id))
}
pub async fn Client::read(self: Client, browser: String,
  reads: Array[Read]) -> Array[ReadValue] raise {
  match self.request(id => { id, body: ReadReq({ browser, reads }) }) {
    ReadRes(values) => values
    _ => raise ServiceError("invalid read response")
  }
}
pub async fn Client::cmd(self: Client, cmd: String) -> String raise {
  match self.request(id => { id, body: CliReq(cmd) }) {
    CliRes(out) => out
    _ => raise ServiceError("invalid cli response")
  }
}
pub async fn Client::exec(port: Int, cmd: String) -> String raise {
  let client = Client::connect(port)
  defer client.close()
  client.cmd(cmd)
}

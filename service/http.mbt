fn root_file(runtime : Runtime, path : String) -> String {
  if runtime.root_dir == "." {
    path
  } else {
    "\{runtime.root_dir}/\{path}"
  }
}

fn content_type(path : String) -> String {
  match path {
    [.., .. ".html"] => "text/html"
    [.., .. ".js"] => "text/javascript"
    [.., .. ".css"] => "text/css"
    _ => "text/plain"
  }
}

pub async fn respond_json(
  conn : @http.ServerConnection,
  status : Int,
  reason : String,
  payload : Json,
) -> Unit {
  let _ = try {
    conn
    ..send_response(status, reason, extra_headers={ "Content-Type": "application/json" })
    ..write(payload.stringify())
    .end_response()
  } catch {
    _ => ()
  }
}

pub async fn respond_ok(conn : @http.ServerConnection, result : Json) -> Unit {
  respond_json(conn, 200, "OK", { "ok": true, "result": result })
}

pub async fn respond_err(
  conn : @http.ServerConnection,
  status : Int,
  reason : String,
  msg : String,
) -> Unit {
  respond_json(conn, status, reason, { "ok": false, "error": msg })
}

pub async fn serve_file(runtime: Runtime, conn: @http.ServerConnection, path: String) -> Unit {
  let full_path = root_file(runtime, path)
  if !@fs.exists(full_path) {
    respond_err(conn, 404, "NotFound", "Not Found")
    return
  }
  let body = @fs.read_file(full_path)
  let _ = try {
    conn
    ..send_response(200, "OK", extra_headers={
      "Content-Type": content_type(path),
      "Cache-Control": "no-cache",
    })
    ..write(body.binary())
    .end_response()
  } catch {
    _ => ()
  }
}

fn next_addr(addr: @socket.Addr, offset: Int) -> @socket.Addr {
  @socket.Addr::new(addr.ip(), addr.port() + offset)
}

pub fn bind_http_server(addr: @socket.Addr, max_tries: Int) -> @http.Server raise {
  let mut tries = 0
  let mut last_error: Error? = None
  while tries < max_tries {
    let candidate = next_addr(addr, tries)
    match (try? @http.Server::new(candidate) : Result[@http.Server, _]) {
      Ok(server) => return server
      Err(err) => {
        last_error = Some(err)
        tries += 1
      }
    }
  }
  match last_error {
    Some(err) => raise err
    None => raise ServiceError("failed to bind service port")
  }
}

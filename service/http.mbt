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

pub async fn call_at(port: Int, cmd: String, arg: String) -> String raise {
  let client = @http.Client::new("http://127.0.0.1:\{port}")
  defer client.close()
  let response = client.post(
    control_path,
    Json::object({
      "cmd": Json::string(cmd),
      "arg": Json::string(arg),
    }).stringify(),
    extra_headers={ "Content-Type": "application/json" },
  )
  let payload = client.read_all().json()
  if response.code < 200 || response.code >= 300 {
    raise ServiceError(json_string(payload, "error").unwrap_or("service request failed"))
  }
  if !json_bool(payload, "ok").unwrap_or(false) {
    raise ServiceError(json_string(payload, "error").unwrap_or("service request failed"))
  }
  match json_field(payload, "result") {
    Some(String(result)) => result
    _ => ""
  }
}

pub async fn call_service(cmd: String, arg: String) -> String raise {
  call_at(require_port(), cmd, arg)
}

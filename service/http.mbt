enum HttpResp { Ok(Json); Err(Int, String, String) }
pub async fn response(conn: @http.ServerConnection, data:&@io.Data, status: Int,
  reason:String, extra_headers~: Map[String, String] = {}) -> Unit {
  conn.send_response(status, reason, extra_headers~)
  conn.write(data)
  conn.end_response()
}
pub async fn respond(conn : @http.ServerConnection, resp : HttpResp) -> Unit {
  let (status, reason, payload) = match resp {
    Ok(result) => (200, "OK", { ok: Some(true), error: None, result: Some(result) }.to_json())
    Err(status, reason, msg) =>
      (status, reason, { ok: Some(false), error: Some(msg), result: None }.to_json())
  }
  response(conn, payload.stringify(), status, reason,
    extra_headers={ "Content-Type": "application/json" })
}

pub async fn serve_file(runtime: Runtime, conn: @http.ServerConnection, path: String) -> Unit {
  let full_path = if runtime.root_dir == "." { path } else { "\{runtime.root_dir}/\{path}" }
  if !@fs.exists(full_path) { return respond(conn, Err(404, "NotFound", "Not Found")) }
  let body = @fs.read_file(full_path)
  let content_type = if path.has_suffix(".html") { "text/html" }
    else if path.has_suffix(".js") { "text/javascript" }
    else if path.has_suffix(".css") { "text/css" }
    else { "text/plain" }
  response(conn, body.binary(), 200, "OK", extra_headers=
    { "Content-Type": content_type, "Cache-Control": "no-cache" })
}

pub fn bind_http_server(addr: @socket.Addr, max_tries: Int) -> @http.Server raise {
  let mut last_error: Error? = None
  for tries = 0; tries < max_tries; tries = tries + 1 {
    let candidate = @socket.Addr::new(addr.ip(), addr.port() + tries)
    match (try? @http.Server::new(candidate) : Result[@http.Server, _]) {
      Ok(server) => return server
      Err(err) => last_error = Some(err)
    }
  }
  match last_error {
    Some(err) => raise err
    None => raise ServiceError("failed to bind service port")
  }
}

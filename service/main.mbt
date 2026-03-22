async fn main {
  match @sys.get_env_var("METAEDITOR_SERVICE_PORT") {
    Some(raw_port) => run_service(default_addr(@strconv.parse_int(raw_port) catch { _ => default_port }))
    None =>
      match @env.args() {
        [_, cmd, rest, ..tail] => run_client_mode(cmd, join_args([rest, ..tail]))
        [_, cmd] => run_client_mode(cmd, "")
        _ => run_client_mode("start", "")
      }
  }
}

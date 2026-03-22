async fn main {
  match parse_mode(@env.args()) {
    Start(port, silent) => run_start_mode(port, silent)
    Serve(port) => serve_daemon(default_addr(port))
    Command(cmd, arg) => run_client_mode(cmd, arg)
  }
}

// ======== session ========
pub(all) enum RejectReason {
  UnsupportedRole
  MissingSessionId
  SessionBusy
} derive(Eq, Show)

pub(all) enum HelloResult {
  Ack(Bool)
  Rejected(RejectReason)
} derive(Eq, Show)

pub(all) struct ServiceState {
  session_id : Ref[String]
  browser_connected : Ref[Bool]
  disconnected_at : Ref[Int64]
}

pub(all) struct SessionView {
  connected : Bool
  locked : Bool
  session_id : String
  disconnected_at : Int64
} derive(Eq, Show, ToJson)

pub fn new_state() -> ServiceState {
  {
    session_id: Ref::new(""),
    browser_connected: Ref::new(false),
    disconnected_at: Ref::new(nil_at),
  }
}

pub fn session_state(state : ServiceState) -> SessionView {
  let session_id = state.session_id.val
  {
    connected: state.browser_connected.val,
    locked: session_id != "",
    session_id,
    disconnected_at: state.disconnected_at.val,
  }
}

pub fn accept_hello(
  state : ServiceState,
  role : String,
  session_id : String,
  _user_agent : String,
) -> HelloResult {
  if role != "browser" { return Rejected(UnsupportedRole) }
  if session_id == "" { return Rejected(MissingSessionId) }
  if state.browser_connected.val { return Rejected(SessionBusy) }
  let reconnected = state.session_id.val == session_id
  if state.session_id.val != "" && !reconnected { return Rejected(SessionBusy) }
  state.session_id.val = session_id
  state.browser_connected.val = true
  state.disconnected_at.val = nil_at
  Ack(reconnected)
}

pub fn disconnect_browser(state : ServiceState, at : Int64) -> Unit {
  state.browser_connected.val = false
  state.disconnected_at.val = at
}

pub fn reject_reason_code(reason : RejectReason) -> String {
  match reason {
    UnsupportedRole => "unsupported_role"
    MissingSessionId => "missing_session_id"
    SessionBusy => "session_busy"
  }
}

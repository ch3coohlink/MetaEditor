using @json { from_json, parse }
using @shared {
  type DomCmd, type Event, type EventCfg, type NodeQuery,
  type Read, type ReadValue, type ResMsg, type ReqMsg, type Res,
  assert_fail, gen_id,
}
using @src { type RuntimeOut }
type DomRt = @src.Runtime

suberror ServiceError { ServiceError(String) } derive(ToJson)

pub async fn[T] poll_until(check: async () -> T?, timeout: Int, step~: Int = 10) -> T raise {
  let max_tries = (timeout + step - 1) / step
  for tries = 0; tries < max_tries; tries = tries + 1 {
    if check() is Some(res) { return res }
    @async.sleep(step)
  }
  raise ServiceError("poll timeout")
}

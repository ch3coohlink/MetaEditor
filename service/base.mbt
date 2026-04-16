using @json { from_json, parse }
using @src { bad_json, json_obj }

suberror ServiceError { ServiceError(String) } derive(ToJson)

fn arg_value(args: Array[String], key: String) -> String? {
  let mut i = 0
  while i < args.length() {
    if args[i] == key {
      if i + 1 < args.length() { return Some(args[i + 1]) }
      return None
    }
    i = i + 1
  }
  None
}

pub async fn[T] poll_until(check: async () -> T?, timeout: Int, step~: Int = 10) -> T raise {
  let max_tries = (timeout + step - 1) / step
  for tries = 0; tries < max_tries; tries = tries + 1 {
    if check() is Some(res) { return res }
    @async.sleep(step)
  }
  raise ServiceError("poll timeout")
}

pub async fn[T] wait_timeout(
  label: String,
  poll: () -> T?,
  timeout_ms~: Int = 400,
) -> T {
  poll_until(fn() { poll() }, timeout_ms, step=20)
    catch { _ => fail("timed out waiting for \{label}") }
}

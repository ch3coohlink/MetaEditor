# 启动变慢调查记录

时间：2026-03-30

## 目标

调查当前分支里 `meta start --silent` 在 Windows 下从旧版约 `109ms` 退化到约
`1100ms` 的真实原因。

## 已确认的事实

1. 旧版 `MetaEditor-326` 的 `start --silent` 约 `109ms`。当前版约 `1100ms`。
2. `wait_port()` 本身不慢。命令里打印出来的 `start wait_port` 一直都在 `50~90ms`。
3. 页面 ready 检查不慢。`assert_page_ready()` 基本都是几毫秒。
4. 外层测试如何启动 CLI 不是真因。
   我把 `service.test.mbt` 里起 CLI 的方式改成了自写 `CreateProcessW`，
   生命周期测试仍然约 `1.1s`。
5. 直接把生产里的 `launch_background_service()` 改成自写 `CreateProcessW`
   也没有把 `1.1s` 打下来。
6. 把 `wait_port()` 里的 `call_at("status")` 改成同步端口探活以后更慢，
   这条路是错的。

## profiling 结论

新增脚本：

- [`scripts/profile-startup.ps1`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/scripts/profile-startup.ps1)
- [`scripts/analyze-startup-profile.js`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/scripts/analyze-startup-profile.js)

使用方法：

```powershell
.\scripts\profile-startup.ps1
node .\scripts\analyze-startup-profile.js --mode hot
node .\scripts\analyze-startup-profile.js --mode topdown --thread 0 --thread 5
node .\scripts\analyze-startup-profile.js --mode wait --thread 0 --thread 5
```

当前 profile 的硬结论：

1. 主线程几乎整段时间都在：
   `main -> run_async_main -> with_event_loop -> run_forever -> poll -> wait_for_event -> moonbitlang_async_poll_wait -> GetQueuedCompletionStatusEx`
2. 这说明不是某个业务函数算慢了，而是 event loop 在等事件。
3. `topdown` 模式里主线程约 `98%` 时间都在 `EventLoop::wait_for_event`。
4. `wait` 模式里 `wait_for_event` 的前面始终是 `EventLoop::poll`，
   下面始终是 `moonbitlang_async_poll_wait`，说明它不是在不同业务分支里乱跳，
   而是长时间挂在同一个等待点。

## runtime trace 结论

为了把 profile 和业务调用点对齐，临时在本地 `.mooncakes/moonbitlang/async`
里加了 trace。

当前 trace 会写到：

`%TEMP%\metaeditor-runtime-trace.log`

相关改动点：

- [`.mooncakes/moonbitlang/async/src/internal/event_loop/event_loop.mbt`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/.mooncakes/moonbitlang/async/src/internal/event_loop/event_loop.mbt)
- [`.mooncakes/moonbitlang/async/src/internal/coroutine/scheduler.mbt`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/.mooncakes/moonbitlang/async/src/internal/coroutine/scheduler.mbt)
- [`service/cli.mbt`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/service/cli.mbt)
- [`service/stub.c`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/service/stub.c)

trace 当前已经能确认：

1. `start_service()` 的顺序是：
   `detect_port -> clear_stale -> launch_background_service -> wait_port -> stdout.write`
2. 在 `wait_port()` 轮询期间确实会反复进入 event loop 等待。
3. 不是 worker/job 一直没完成。
   trace 里最终能看到：
   `no_more_work=true blocking=0 ready=0 running_workers=0 timers=0`
   然后 `run_forever break`。
4. 真正拖住退出的是 coroutine/timer 层状态，不只是 `running_workers/jobs`。
   trace 里多次出现：
   `running_workers=0`
   但 `blocking > 0`，有时 `timers=1`。
5. 目前最可疑的仍然是 `wait_port()` 内部那条 coroutine/timer 链，
   但还没有精确到“第几行哪个 async primitive 没收干净”。

## 当前改动里已经试过且应视为失败的方向

1. 只改生产 `launch_background_service()` 的 Windows `CreateProcessW` 启动器。
   失败。时间基本不变。
2. 只改测试里启动 CLI 的方式。
   失败。时间基本不变。
3. 把 `wait_port()` 改成同步端口探活。
   失败，而且更慢。

## 最新定位结论

后续继续用最小回退法只改 `start_service()`，把启动路径里的附属调用一项一项加回去，
已经把慢点缩到一行具体写法。

触发变慢的代码在：

- [`service/cli.mbt`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/service/cli.mbt)

慢的写法：

```moonbit
if !silent && !wait_browser_connected_at(running_port, 800) {
  let _ = try? open_browser("http://localhost:\{running_port}")
}
```

等价但不慢的写法：

```moonbit
if !silent {
  if !wait_browser_connected_at(running_port, 800) {
    let _ = try? open_browser("http://localhost:\{running_port}")
  }
}
```

用于后续复现和报 bug 的现场 commit：

- `a05cc8b` `fix(service): correct slow startup caused by conditional expression`

## 对照实验

为了避免继续被其他因素干扰，这一轮做了这些约束：

1. 新增计时脚本：
   [`scripts/time-startup.ps1`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/scripts/time-startup.ps1)
2. 每次测量都先重编译，再用独立 `state-dir` 跑一次 `start --silent`，
   结束后自动 `stop` 并清理状态。
3. 只改 `start_service()` 里剩下那几行 diff。
   其他启动控制流保持不变。

测到的结果很稳定：

1. 去掉 `start_service()` 里的附属日志调用后，
   `start --silent` 回到约 `100ms`。
2. 单独恢复 `trace_runtime(...)`，
   仍然约 `139ms`。
3. 单独恢复 `log_timing(...)`，
   仍然约 `124ms`。
4. 单独恢复 `stdout.write(...)`，
   仍然约 `80~100ms`。
5. 只要把 `None` 分支里的这一行恢复成
   `if !silent && !wait_browser_connected_at(...)`，
   时间就立刻稳定回到约 `1090~1185ms`。
6. 把同一段逻辑改成嵌套 `if`，
   时间又立刻回到约 `87~103ms`。

## 现在可以确认的事

1. 问题不在 `wait_port()` 本身。
   这段阶段计时一直只有几十毫秒。
2. 问题也不在 `open_browser()` 真被调用。
   当前测的是 `start --silent`，这条分支在语义上不会进入。
3. 真正触发慢点的是条件表达式的代码形态。
   具体说，就是：
   `if !silent && !wait_browser_connected_at(...)`
4. 这更像是 MoonBit 在这个场景下对
   `&&` 和 async 调用组合的代码生成问题，
   而不是业务逻辑本身慢。

## 当前建议

1. 先保留嵌套 `if` 写法。
   这是当前唯一已经验证能稳定恢复启动时间的实现。
2. 如果要继续往语言层追，
   下一步应该把这段逻辑抽成最小复现，
   单独验证是不是 MoonBit 编译器对
   `if a && async_call(...)` 的 native 代码生成有问题。

## 对后续 agent 的建议

后续不要再重复这几件事：

1. 不要再猜 `wait_port()` 本身慢。
   它已经被阶段计时和同步端口探活实验排掉了。
2. 不要再猜是页面 ready 慢。
   这段一直都很快。
3. 不要再只看热点栈。
   现在已经有 `topdown` 和 `wait` 两种模式。
4. 不要再去改测试外层怎么起 CLI。
   这条已经证明不是主因。

如果继续往下查，应该只做一件事：

直接盯 `run_forever` 的退出条件是为什么在 `wait_port()` 轮询期间迟迟不归零。
重点是 `blocking / ready / timers` 三个量，而不是 `running_workers/jobs`。

## async 本地改动的回退方法

当前本地 `.mooncakes` 的诊断改动只涉及两个文件：

1. [`.mooncakes/moonbitlang/async/src/internal/event_loop/event_loop.mbt`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/.mooncakes/moonbitlang/async/src/internal/event_loop/event_loop.mbt)
2. [`.mooncakes/moonbitlang/async/src/internal/coroutine/scheduler.mbt`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/.mooncakes/moonbitlang/async/src/internal/coroutine/scheduler.mbt)

在这两个文件里搜索这些标记，整段删掉即可回到正常版：

- `runtime_trace_ffi`
- `trace_runtime`
- `debug_blocking_count`
- `debug_ready_count`
- `debug_current_id`
- `run_forever loop`
- `run_forever break`
- `run_forever after_poll`
- `run_forever after_reschedule`
- `worker submit`
- `worker resumed`
- `evloop wait_enter`
- `evloop wait_exit`
- `evloop completed_job`

如果懒得手删，最干净的回退方式是：

1. 删掉整个项目里的 `.mooncakes/moonbitlang/async`
2. 删掉 `_build` 里对应的 async 构建产物
3. 重新跑一次 `moon test` 或 `.\scripts\build-native.ps1 -Package service`

这样会重新拉回原始依赖内容。

## 当前仓库里和这次调查直接相关的文件

- [`service/cli.mbt`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/service/cli.mbt)
- [`service/stub.c`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/service/stub.c)
- [`service/service.test.mbt`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/service/service.test.mbt)
- [`scripts/profile-startup.ps1`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/scripts/profile-startup.ps1)
- [`scripts/analyze-startup-profile.js`](/D:/Users/ch3co/Desktop/mbt_race/MetaEditor/scripts/analyze-startup-profile.js)

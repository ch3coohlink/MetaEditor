# Json 规范

这套项目里，`Json` 默认只表示边界协议格式，不表示内部正式语义。

## 核心规则

1. 内部逻辑先用 typed 结构
2. 到边界时再编码成 `Json`
3. 边界收到 `Json` 后尽快解回 typed 结构
4. 同一条协议只保留一套 codec

## 什么地方可以直接用 `Json`

- websocket 消息
- http 请求和响应
- CLI `--json` 输出
- 明确就是“导出一个 JSON 视图”的函数

像 `action_info_to_json(...)` 这类导出函数属于这一类。

## 什么地方不要把 `Json` 当正式类型

- `runtime`
- `mock`
- `dom`
- `bridge` 内部语义
- 触发、查询、命令这类系统正式语义

这些地方应该优先定义 typed 结构，再在边界层做编码和解码。

## 推荐写法

### 入站

优先用 `struct ... derive(FromJson)` 解码边界消息。

适用场景：

- websocket request
- websocket response
- http request body

不要在生产主路径里到处手写 `json_field/json_string/json_int` 去拆协议字段。

### 出站

分两类：

- 稳定协议对象：写显式 `*_to_json(...)`
- 很短的临时响应：可以直接写 `Json::object(...)`

不要把同一条协议一部分写成 `derive(ToJson)`，另一部分又手搓字段。

## 关于 derive

- `derive(FromJson)` 适合边界消息 struct
- `derive(ToJson)` 只在输出形状已经明确且稳定时使用
- `enum derive(ToJson/FromJson)` 不要直接拿来当 websocket 正式协议

原因很简单：带 payload 的 enum 形状会偏向数组，不适合当前项目一直在用的 object 协议。

## 当前项目里的推荐分层

- `BridgeUiRequestMsg` 这类 struct：边界 DTO
- `UiRequest`、`UiTriggerKind` 这类类型：内部正式语义
- `msg_to_json(...)`、`build_browser_request(...)`：协议 codec

这就是推荐主路径：

边界 `Json`
-> DTO
-> 内部 typed 语义
-> 执行
-> DTO 或结果对象
-> 边界 `Json`

## 不推荐的写法

- 让 `Json` 直接在 `runtime` 里传来传去
- 同一条协议同时存在手写字段解析和另一套 derive 解析
- 为了省几行，把内部 typed request 又压回平铺 `Json`
- 让测试 helper 里的 JSON 拆字段方式反过来定义正式协议

## 判断一段代码该不该继续用 `Json`

先问一句：

“这段数据现在是在系统边界上，还是已经进入内部语义了？”

- 如果还在边界上，可以是 `Json`
- 如果已经进入内部语义，就应该尽快转成 typed 结构

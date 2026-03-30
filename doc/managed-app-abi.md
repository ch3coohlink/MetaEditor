# MoonBit Managed App ABI 设计

这份文档讨论 wasm managed app 和宿主之间的正式 ABI。这里说的 ABI，不只是
`extern "C"` 那几条函数签名，还包括参数和返回值的编码、错误语义、宿主请求、
DOM 输出、wasm 使用宿主能力以及后续演进方式。

目标不是先把所有功能一次做完，而是先把边界定清楚，避免每来一种新需求就额外长
一组 `app_xxx_len / app_xxx_at / app_xxx_result` 之类的平行接口。

## 1. 目标

- 宿主和 wasm 之间只保留极少数固定入口
- 参数、返回值、宿主请求、DOM 输出都走同一条 payload 主路径
- ABI 尽量贴 MoonBit 的值模型，不按 C struct 思维散开
- ABI 层只负责调用和搬运数据，不直接承载业务语义
- 后续增加数组、字符串、结构体、枚举、日志、增量 DOM 时，不需要再补新的导出函数
- 能明确区分 ABI 错误、运行状态和业务错误
- 能覆盖 wasm 使用宿主能力这半边，而不是只定义 host -> wasm

## 2. 非目标

- 不追求直接映射任意 MoonBit 类型
- 不在第一版引入自动 derive 任意 ADT 编解码
- 不做 GC 对象跨边界共享
- 不把浏览器 UI 单独做成另一套旁路协议

第一版只要求把 ABI 主路径收成统一模型，让后续扩展继续走同一条路。

## 3. 分层

这套设计明确分成四层：

- FFI ABI 层：固定导出函数、线性内存搬运、状态码
- 值编码层：`AbiValue <-> Bytes`
- App 协议层：action、host request、DOM patch、query、日志这些真正业务语义
- 调度模型层：host -> wasm、wasm 请求宿主、宿主回包的执行顺序

这三层不要混。

例如：

- `app_call(op, in_ptr, in_len)` 属于 FFI ABI 层
- `Array[Int]` 怎么编码属于值编码层
- `render`、`host_reply`、`query` 属于 App 协议层
- “wasm 能不能在 host 尚未返回时反过来直接调用宿主”属于调度模型层

如果把业务语义直接做成 FFI 函数名，ABI 会很快散掉。

## 4. 固定导出入口

建议 wasm app 只保留下面这些固定入口：

```moonbit
pub fn app_init() -> Int
pub fn app_call(op: Int, in_ptr: Int, in_len: Int) -> Int
pub fn app_out_len() -> Int
pub fn app_out_word(index: Int) -> UInt
pub fn app_close() -> Int
```

说明：

- `app_init()` 负责初始化 app 自身 runtime
- `app_call(...)` 是唯一业务调用入口
- `app_out_len()` 返回输出 payload 的字节长度
- `app_out_word(index)` 按固定宽度块读取输出 payload
- `app_close()` 负责清理资源

这里保留 `word` 读取，不是因为它是理想终态，而是因为它比逐字节读取更稳，也比
直接把宿主绑死到某个平台内存布局更容易收。后面如果要继续演进成宿主一次性复制
整段内存，可以在不改 App 协议层的前提下替换这层实现。

## 5.1 宿主固定导入入口

如果后面要把 wasm 使用宿主能力也纳进统一 ABI，宿主导入侧也应尽量固定成少数入口。

理想对称形态是：

```moonbit
extern "C" fn host_call(op: Int, in_ptr: Int, in_len: Int) -> Int
extern "C" fn host_out_len() -> Int
extern "C" fn host_out_word(index: Int) -> UInt
```

但这组导入不代表第一版就应该真的开放给 wasm 在任意时刻直接调用。更稳的第一版仍然是：

- wasm 通过输出消息提出 `HostRequest`
- 宿主退出这次 wasm 调用以后自己处理
- 宿主再通过下一次 `app_call(op_host_reply, ...)` 把结果送回 wasm

也就是说，ABI 设计需要覆盖 wasm -> host 这半边，但第一版运行模型可以仍然保持协作式，
不急着启用同步反向调用。

## 6. 状态码

`app_call` 和 `app_init/app_close` 的返回值只表示运行时级状态，不表示业务结果。

建议约定：

- `0`：调用成功，输出 payload 可读
- `1`：调用成功，输出 payload 是宿主请求
- `2`：调用成功，输出 payload 是多条消息
- `< 0`：ABI/runtime 错误

负数错误码只保留给 ABI/runtime 本身，例如：

- `-1`：未知 op
- `-2`：输入 payload 非法
- `-3`：当前状态不允许该调用
- `-4`：输出 payload 构造失败
- `-5`：ABI 版本不兼容

业务层自己的失败不要塞进这里，应该放进输出 payload。

## 7. 为什么不用一堆专用函数

下面这些做法都不适合作为正式 ABI：

- `app_result()`
- `app_request()`
- `app_dom_len()`
- `app_dom_word()`
- `app_query_xxx()`
- `app_render_xxx()`

原因很直接：

- 每多一种返回形态，就要补一组并行函数
- 宿主和 wasm 两边会同时散出业务分支
- DOM、host request、日志、普通返回值会变成平行概念
- 后续数组、对象、bytes、结构体参数很难自然接进去

正式 ABI 应该让“参数是什么”和“输出是什么”都退回 payload 编码层，而不是长在
函数名字里。

## 8. 值模型

ABI 的值模型要尽量贴 MoonBit 的表达能力。第一版建议先固定一套显式值类型，而不是
试图自动反射任意 MoonBit 数据。

例如：

```moonbit
pub enum AbiValue {
  Unit
  Bool(Bool)
  Int(Int)
  UInt(UInt)
  String(String)
  Bytes(Bytes)
  Array(Array[AbiValue])
  Tuple(Array[AbiValue])
  OptionNone
  OptionSome(AbiValue)
  ResultOk(AbiValue)
  ResultErr(AbiValue)
  Variant(Int, Array[AbiValue])
  Object(Array[(String, AbiValue)])
}
```

这里不追求“最少类型”，而是追求：

- 能表达 MoonBit 里常见数据
- 宿主和 wasm 两边都容易写 codec
- 后面加新业务时不需要改 FFI 入口

`Object` 是否放进第一版可以再讨论。如果想先压复杂度，第一版可以只留 `Tuple` 和
`Variant`，上层协议先不用对象风格。

## 9. 编码规则

编码建议用带 tag 的二进制格式，不直接用 JSON，也不直接暴露 C struct。

推荐最小规则：

- 每个值先写一个 `tag`
- 变长值再写 `len`
- 内容按顺序写入 bytes

### 9.1 基础值

- `Unit`：只写 tag
- `Bool`：tag + 1 byte
- `Int`：tag + zigzag varint
- `UInt`：tag + varint
- `String`：tag + len + utf8 bytes
- `Bytes`：tag + len + raw bytes

### 9.2 组合值

- `Array`：tag + count + item...
- `Tuple`：tag + count + item...
- `OptionNone`：tag
- `OptionSome`：tag + item
- `ResultOk`：tag + item
- `ResultErr`：tag + item
- `Variant`：tag + variant_id + field_count + field...
- `Object`：tag + field_count + (`String`, `AbiValue`)...

### 9.3 为什么不用 JSON

JSON 的问题不是“不能用”，而是它不适合作为正式 ABI 基础：

- 类型太松，`Int/UInt/Bytes/Variant` 都要靠额外约定
- DOM patch、host request、错误值会越来越像“再包一层 JSON 协议”
- 宿主和 wasm 两边都要做字符串构造和解析
- 想收成稳定二进制协议时迁移成本更高

JSON 可以继续留给调试输出和文档例子，不适合作为正式 ABI 主格式。

## 10. 控制面和值编码

`AbiValue` 是控制面的公共语言，不应该吞掉所有高频数据路径。

适合默认走 `AbiValue` 的内容：

- action 调用
- query
- host request
- host reply
- 配置
- 错误
- 日志

这些内容的共同点是：

- 频率通常不高
- 更看重类型清晰和可演进
- 值结构经常会变

如果把整套 ABI 的所有东西都强行转成 `AbiValue` 再 encode/decode，两边在这些场景会很舒服，
但在热路径上会有明显额外开销。

## 11. 数据面和专用 payload

有些数据不适合每次都升格成 `AbiValue` 树：

- DOM patch
- 大文本
- 大数组
- 快照
- 流式输出
- 已经有紧凑格式的二进制块

这些内容更适合在统一消息模型里直接挂专用 payload，而不是先拆成通用值树再编码一遍。

因此正式 ABI 应该允许同时存在：

- 通用值：`AbiValue`
- 专用块：`Bytes`

这两者不是平行 ABI，只是同一消息系统里的两种 payload 形态。

## 12. App 协议层

FFI ABI 负责传值，不负责定义业务动作。业务动作应该集中放在 App 协议层。

例如：

```moonbit
let op_boot = 1
let op_action = 2
let op_host_reply = 3
let op_query = 4
let op_render = 5
```

这些 `op` 不代表最终一定是这几个，而是说明：

- FFI 入口数应固定
- 业务语义通过 `op + payload` 表达

然后再定义对应 payload，例如：

- `BootInput`
- `ActionCall`
- `HostReply`
- `QueryCall`
- `RenderCall`

返回值也一样，走 payload，不直接占函数名。

## 13. 输出模型

不要假设一次调用只能返回一个“结果值”。对于 managed app，这个假设太弱了。

更合适的做法是让输出统一表示成消息数组。

例如：

```moonbit
pub enum OutMessage {
  Done(AbiValue)
  HostRequest(AbiValue)
  HostReply(AbiValue)
  DomPatch(Bytes)
  Binary(Int, Bytes)
  Log(String)
  Error(AbiValue)
}
```

然后 `app_out_*` 读出来的是：

```moonbit
Array[OutMessage]
```

这样有几个好处：

- 普通结果、宿主请求、DOM 输出是同一层概念
- DOM 不是 ABI 特权
- 日志、调试信息、错误信息都可以自然混在输出里
- 高体量数据可以直接挂 `Bytes`
- 后面如果一个调用要同时返回“业务完成 + 一批 DOM patch”，也不需要再改 ABI

如果第一版想继续压复杂度，也可以先约定“输出 payload 顶层一定是一个 `Tuple`”，但
文档层最好先把消息数组模型定出来，避免又走回单值返回。

`Binary(Int, Bytes)` 的 `Int` 是专用块 kind。第一版如果不想一上来开放太多变体，可以先只留
`DomPatch(Bytes)`，后面再决定要不要收成更一般的 `Binary`。

## 14. wasm 使用宿主能力

wasm 使用宿主能力需要同时考虑两件事：

- ABI 是否能表示这半边能力
- 运行模型是否允许 wasm 在任意时刻直接反调宿主

这两件事不要混成一个问题。

### 14.1 第一版建议

第一版建议继续使用协作式宿主请求：

1. host 调 `app_call(...)`
2. wasm 运行后输出 `HostRequest(...)`
3. 这次 wasm 调用先结束
4. host 自己处理请求
5. host 再调用 `app_call(op_host_reply, ...)`

这条链已经足够覆盖：

- browser query
- browser exec
- 文件读取
- 外部命令
- 其他宿主能力

而且不会把调用栈和生命周期一下变复杂。

### 14.2 同步重入 host

“同步重入 host”指的是：

1. host 正在调用 wasm
2. 这次 `host -> wasm` 调用还没有返回
3. wasm 在中途又直接调用宿主
4. 宿主必须当场执行完并把结果返回给 wasm
5. wasm 拿到结果继续执行
6. 最后最外层的 `host -> wasm` 调用才结束

也就是调用栈变成：

- host -> wasm -> host -> wasm/host ...

这类模型的主要问题不是“做不到”，而是：

- 栈和控制流更难看清
- 错误传播会绕
- 宿主状态可能正处在半执行中
- 锁、buffer、生命周期和清理顺序都更容易出错
- WAMR 和宿主之间的排查成本会明显升高

所以这份文档建议：

- ABI 设计上给这条路留出空间
- 第一版运行模型不要默认启用同步重入 host
- 先用协作式 `HostRequest/HostReply` 路径把主语义跑稳

### 14.3 什么时候再考虑直接 host_call

只有在下面这些条件同时成立时，才值得认真评估 wasm 直接同步调用宿主：

- 某类宿主能力天然就是同步的
- 走协作式两段调用带来的复杂度更高
- 调用频率高到必须压掉一次往返
- 调用过程中不会把宿主带进危险的半执行状态
- 生命周期和错误传播路径已经有清楚约束

否则第一反应不应是直接开放同步重入。

## 15. 错误模型

必须明确分三层错误，不然后面很难查问题。

### 11.1 ABI 错误

例如：

- payload 长度非法
- tag 非法
- ABI 版本不兼容
- 读取输出 payload 失败

这层由 `app_call` 返回负数，或者宿主本地直接抛 runtime error。

### 11.2 调用状态

例如：

- 调用完成
- 需要宿主处理
- 输出里有多条消息

这层由 `app_call` 返回非负状态码表达。

### 11.3 业务错误

例如：

- action 不存在
- 参数类型不匹配
- query 目标不存在
- 某项宿主能力当前不可用

这层应该放在 `OutMessage::Error(...)` 或 `AbiValue::ResultErr(...)` 里，不要和
ABI/runtime 错误混在一个整型里。

## 16. 版本和能力协商

正式 ABI 需要内建版本和能力协商，不应默认宿主和 wasm 总是同时更新。

至少要有：

- `abi_version`
- `app_protocol_version`
- `capabilities`

建议在 `app_init()` 后，宿主先发一个最小握手调用，app 返回：

- 支持的 ABI 版本
- 支持的 app 协议版本
- 是否支持 browser_ui
- 是否支持 host request
- 是否支持 direct host call
- 是否支持 bytes payload
- 是否支持多消息输出

这样后续演进可以显式判断，而不是靠“调用失败了再猜”。

## 17. browser_ui 在 ABI 里的位置

`browser_ui` 不应该继续占一组专用 ABI 函数。

更合理的位置是：

- 它是一个 capability
- 它的输出是 `OutMessage::DomPatch(...)`
- 宿主绑定浏览器运行时后，app 才会开始产生这类消息

也就是说：

- browser_ui 是 App 协议层语义
- DOM patch 是 payload 内容
- FFI ABI 不需要知道 DOM 是什么

这样才能让 `browser_ui` 真正复用 MetaEditor 现有 `DomCmd -> bridge.js -> DOM`
主路径，而不是在 ABI 层又长出一套私有协议。

## 18. 宿主请求

宿主请求也应该走统一输出模型，不再保留 `app_request()` 这种专用入口。

推荐流程：

1. 宿主调用 `app_call(op, payload)`
2. `app_call` 返回成功状态
3. 宿主读取输出 payload
4. 输出里包含 `HostRequest(...)`
5. 宿主执行请求
6. 宿主再调用 `app_call(op_host_reply, reply_payload)`

这样之后：

- 宿主请求
- DOM 输出
- 普通返回值
- 业务错误

都只是在输出消息里占不同 tag，不再需要四套平行函数。

如果后面真的开放同步 `host_call(...)`，也不应直接绕开这层语义建模。更合理的做法仍然是：

- 先在 App 协议层定义宿主能力和返回值
- 再决定这条语义是走协作式 `HostRequest/HostReply`
- 还是走同步 `host_call`

这样可以避免“相同语义因为调用方向不同，又长出两套业务协议”。

## 19. 参数和返回值示例

### 19.1 单个 Int 参数

调用：

```moonbit
app_call(op_action, encode(Variant(1, [Int(3)])))
```

返回：

```moonbit
[Done(Int(5))]
```

### 19.2 数组参数

调用：

```moonbit
app_call(op_action, encode(Variant(2, [Array([Int(1), Int(2), Int(3)])])))
```

返回：

```moonbit
[Done(Int(6))]
```

数组没有额外 ABI，只是 `AbiValue::Array` 的普通用法。

### 19.3 宿主请求

返回：

```moonbit
[
  HostRequest(
    Variant(10, [
      String('browser_query'),
      Tuple([String('[data-testid=\"x\"]'), String('text')])
    ])
  )
]
```

宿主回包：

```moonbit
app_call(op_host_reply, encode(ResultOk(String('done'))))
```

### 19.4 DOM 输出

返回：

```moonbit
[
  DomPatch(Bytes(...)),
  Done(Unit)
]
```

这里 `DomPatch` 内部到底是 `Bytes`、`Array[Int]`、还是更结构化的 `Variant`，属于
App 协议层，不属于 FFI ABI 层。

## 20. 宿主侧模块边界

建议宿主侧按下面几层拆：

- `service/wamr-stub.c`
  只负责 WAMR 调用和 payload 读取，不承载业务语义
- `service/wasm.mbt`
  只负责统一 `call + read_out`
- `service/wasm_abi.mbt`
  定义 `AbiValue`、`OutMessage` 和编解码
- 更上层 managed app runtime
  负责 `action/query/render/host_reply` 等业务协议

这样之后，`service/wasm.mbt` 就不会再积累：

- `send`
- `request`
- `result`
- `dom_payload`

这类越写越业务的桥接接口。

## 21. wasm app 侧模块边界

wasm app 侧也建议分层：

- `abi_codec.mbt`
  编码/解码 `AbiValue`
- `app_protocol.mbt`
  定义 `ActionCall`、`HostRequest`、`DomPatch` 等业务消息
- `main.mbt`
  只保留 `app_init/app_call/app_out_len/app_out_word/app_close`

这样 fixture 才不会继续手抄一套和真实运行时平行的临时协议。

## 22. 第一版落地范围

第一版建议只做这些：

- 固定 `app_call + app_out_len + app_out_word`
- 固定 `AbiValue`
- 固定 `OutMessage`
- 输出顶层统一为消息数组
- 先手写 codec
- 先支持 `Int/UInt/String/Bytes/Array/Tuple/Variant/Result`
- 先支持协作式 `HostRequest/HostReply`
- 先不启用同步重入 host

先不做：

- 任意对象自动映射
- 自动 derive
- 零拷贝共享
- 复杂 capability graph
- 默认开放 wasm 直接同步调用宿主

这个范围已经足够把当前零散 ABI 收成一条主路径。

## 23. 对当前实现的影响

如果按这份文档推进，当前这几类接口都应该逐步退出：

- `app_handle`
- `app_result`
- `app_request`
- `app_dom_len`
- `app_dom_word`

它们的问题不是能不能用，而是它们都把业务语义写进了 ABI。

替换后的结构应当是：

- `app_call` 统一输入
- `app_out_*` 统一输出
- 输出 payload 里同时表达 done、host request、dom patch、error

这样之后，数组参数、字符串参数、多返回消息、DOM 输出、宿主请求就都会回到统一模型里。

## 24. 性能假设与验证点

这份文档目前只定义 ABI 方向，不把某个性能判断提前写成结论。下面这些点需要后续用实测确认。

### 24.1 统一入口和分支预测

统一 `app_call(op, ...)` 入口的主要风险之一，是调用分发可能对分支预测不友好。

这里先记两点判断：

- 如果 `op` 只保留少量粗粒度分类，这层顶层分支未必会成为主要瓶颈
- 如果 `op` 继续细化到大量具体动作，或者统一入口里堆了过多业务分支，这层风险会明显上升

当前还没有实测数据，所以这里先不把“统一入口一定没问题”或“统一入口一定会慢”写死。

### 24.2 更可能的成本来源

在这条 ABI 路径里，潜在成本不只来自顶层分发，还包括：

- host 和 wasm 之间的调用边界
- payload 搬运
- `AbiValue` encode / decode
- wasm 内部实际逻辑
- 大块 DOM patch 或大数组的构造和消费

后续如果要排性能，不应只盯顶层 `match op`。

### 24.3 建议验证项

如果后面开始做性能验证，建议至少测这些场景：

1. `host -> wasm` 空调用成本
2. 小型 `AbiValue` payload 的 encode / decode 成本
3. 大型 `Bytes` payload 的搬运成本
4. 粗粒度 `op` 分发和细粒度 `op` 分发的差异
5. 协作式 `HostRequest/HostReply` 的往返成本
6. DOM patch 走 `AbiValue` 和走专用 `Bytes` 的差异

### 24.4 当前设计约束

在没有实测数据前，这份 ABI 设计先坚持下面几条：

- `op` 只做粗粒度分类
- 统一入口只做很薄的分发，不承载业务实现
- 控制面默认走 `AbiValue`
- 热路径允许走专用 `Bytes` payload

如果后面数据证明统一入口本身就是热点，再回头讨论更激进的 fast path。

## 25. 后续工作

下一步如果真的落代码，建议顺序是：

1. 先在宿主侧定义 `AbiValue` 和 `OutMessage`
2. 写最小编解码
3. 把 `service/wasm.mbt` 收成统一 `call/read_out`
4. 把 wasm fixture 改成统一 `app_call`
5. 把当前 DOM 输出和 host request 接回这个模型
6. 再评估是否真的需要同步 `host_call`

先把 ABI 立稳，再继续讨论 browser_ui、state/local 持久化和更高层 app API，会更容易收。

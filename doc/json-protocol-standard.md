# JSON 与协议治理专项

## 目的

这份文档不讨论泛泛的“JSON 最佳实践”，只讨论 MetaEditor 里真正会把代码越改越乱的那类问题：

- 同一条协议在不同文件各写一份 shape
- 内部正式语义和边界协议混写
- 名字叫 `json`，实际却不是 JSON
- 测试手写弱 shape，反过来逼生产代码做兼容

目标只有一个：把协议钉死，让代码里同一件事只保留一份正式定义。

## 三层分离

所有数据先分清自己在哪一层，再决定该不该用 `Json`。

```text
内部正式语义
  -> encode
边界协议类型
  -> stringify / parse / transport
传输编码格式
```

### 1. 内部正式语义

这层是系统内部长期流动的概念。

例子：

- `Entry`
- `Instance`
- `Runtime`
- `VNode`
- `DomCmd`
- `UiRequest`
- `UiTriggerKind`

规则：

- 这层优先写正常类型
- 不让 `Json` 在这层长期漂
- 不在这层随手拼 `Json::object(...)`

### 2. 边界协议类型

这层描述一条正式协议的 shape。它还不是编码字符串，但已经是“对外消息”的类型。

例子：

- websocket 的 `bridge:hello`
- websocket 的 `bridge:request`
- websocket 的 `bridge:response`
- HTTP `/_meta/command`
- CLI `--json` 的输出对象

规则：

- 每条正式协议必须有唯一 shape
- 每条正式协议必须有唯一 codec
- 边界收进来的 `Json` 尽快转成协议类型或内部类型

### 3. 传输编码格式

这层只是“怎么过线”。

例子：

- JSON object
- JSON array
- 文本字符串
- 当前 `EventData` 用的管道分隔串

规则：

- 传输格式不等于内部语义
- 自定义紧凑格式可以存在，但必须明确标注，不能伪装成 JSON

## 当前系统图

```text
用户 / CLI / tests / AI
        |
        v
service/cli.mbt
        |
        v
service/bridge.mbt
        |
        | UiRequest / UiTriggerKind
        v
+-------------------+-------------------+
| 有 browser        | 无 browser        |
| request_browser   | request_headless  |
+---------+---------+---------+---------+
          |                   |
          v                   v
     websocket           src/mock_dom.mbt
          |                   |
          v                   v
      src/bridge.js       headless DOM
          |                   |
          +---------+---------+
                    |
                    v
            query / trigger result
```

当前真正最乱的不是 request，而是 query / trigger 的 result shape。

## 当前协议清单

下面这些协议都必须被当成正式协议治理，不允许继续各写各的。

### websocket

- `bridge:hello`
- `bridge:hello_ack`
- `bridge:ping`
- `bridge:pong`
- `bridge:request`
- `bridge:response`
- `repl:request`
- `repl:response`

### HTTP

- `/_meta/command` request
- `/_meta/command` response

### CLI

- `--json` 输出

### DOM 桥接

- `DomCmd` batch
- `EventData` 线协议

## 已确认的问题

### 1. 命名误导

`EventData::from_json` 实际处理的是管道分隔串，不是 JSON。

这类命名必须禁止。名字里带 `json` 的函数，输入输出都必须真的是 JSON。

### 2. 同一协议多份 shape

query / trigger 结果现在散在：

- `src/bridge.js`
- `src/mock_dom.mbt`
- `service/bridge.mbt`
- `service/cli.mbt`
- 测试里的 fake response

这意味着同一件事没有唯一正式 shape。

### 3. 同一协议多份 codec

当前常见情况是：

- 一份手写字段输出
- 一份手写字段读取
- 一份测试里再手写 fake object

这会导致协议漂移。

### 4. 测试反向定义协议

测试不该随手手写一个“差不多能跑”的弱 shape，再让生产代码兼容它。

正确方向只能是：

```text
正式协议定义
  -> 测试复用正式 builder / codec
```

不能反过来。

### 5. 历史 fallback 残留

像 `DomCmd` 既支持对象数组，又保留字符串二次 `JSON.parse` 这种逻辑，说明协议还没完全收口。

这类 fallback 要么证明仍是正式主路径，要么删除。

## 硬规则

从现在开始，JSON 和协议相关改动必须遵守下面这些规则。

### 规则 1

同一条正式协议只允许一份 shape。

不允许：

- browser 写一份
- service 再猜一份
- mock 再抄一份
- test 再编一份

### 规则 2

同一条正式协议只允许一套入口 codec 和一套出口 codec。

可以手写，但只能集中在一个地方。

### 规则 3

内部正式语义和边界协议不能混写。

如果数据已经进入 `runtime / mock / dom / bridge` 的内部执行语义，就优先转成正常类型。

### 规则 4

名字带 `json` 的函数必须真的处理 JSON。

像 `from_json` 实际解析自定义串的情况必须改。

### 规则 5

自定义紧凑协议必须显式标注。

例如：

- `decode_event_data_wire(...)`
- `encode_event_data_wire(...)`

而不是继续伪装成 JSON。

### 规则 6

测试不得手写弱化版协议 shape。

如果正式协议要求字段存在，测试也必须按正式协议构造。

### 规则 7

如果已有类型能承载同一协议，先复用现有类型。

如果只是缺 codec，就补 codec。

只有协议形状真的不同，才允许新增类型。

## 推荐整改顺序

### 第一批：先清硬伤

- 改掉 `EventData::from_json` 这类错误命名
- 删掉测试里手写的弱 response shape
- 清掉明显无主路径意义的 fallback

### 第二批：收协议 codec

- 给 websocket request/response 收唯一 builder / decoder
- 给 CLI `--json` 收唯一输出入口
- 给 query / trigger result 收唯一 shape

### 第三批：测试改成复用正式协议

- 测试不再手写散装 object
- 测试统一走 builder / codec helper

### 第四批：删除平行入口

- 删除旧 helper
- 删除旧字段读取分支
- 删除“顺手兼容一下”的临时逻辑

## 当前最该优先处理的点

不是所有 JSON 问题都同等重要。当前最优先的是：

### 1. query / trigger result shape

这条链现在最容易漂，必须先钉死。

### 2. `EventData` 协议命名

这是现成的误导源，必须尽快改。

### 3. websocket request/response codec 集中

`service/bridge.mbt`、`src/bridge.js`、测试三边要收回同一条正式协议。

## 判定问题时先问这三句

```text
1. 这段数据现在是在内部语义里，还是还在边界上？
2. 这条协议的 shape 是不是已经只有一份正式定义？
3. 这次改动是在收协议，还是又补了一层平行壳？
```

三句里只要有一句答不稳，就先不要继续加代码。

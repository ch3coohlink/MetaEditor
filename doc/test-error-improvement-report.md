# 测试错误改造报告

## 目标

这份报告只看测试代码里的失败信息质量。

重点不是“测试会不会挂”。
重点是“挂了以后能不能立刻看懂为什么挂、挂在哪、实际值是什么”。

## 结论

当前仓库的测试失败入口主要分成三类：

1. `abort(...)`
2. `panic()` 或 `catch { _ => panic() }`
3. `fail(...)`

其中第三类最适合继续扩展。
前两类是当前失败信息变薄的主要来源。

按简单文本统计，当前 MoonBit 测试里大致有：

- `abort(` 97 处
- `fail(` 31 处
- `panic(` 25 处

主要集中在这些文件：

- `src/storage.test.mbt`：93 处
- `src/reactive.test.mbt`：15 处
- `service/repl.test.mbt`：14 处
- `service/service.test.mbt`：12 处
- `service/sqlite.test.mbt`：8 处
- `src/mock_dom.test.mbt`：6 处

这份分布很清楚地说明，当前问题不在单个测试。
问题在于几套测试 helper 的失败风格还没有统一。

## 当前问题

### 1. `abort(label)` 太粗

`src/storage.test.mbt` 里的 helper 基本都是这种风格：

```moonbit
fn assert_obj(value: PersistValue, label: String) -> Map[String, PersistValue] {
  match value {
    Obj(m) => m
    _ => abort(label)
  }
}
```

这类写法的缺点很直接：

- 只能看到一个短标签
- 看不到实际值
- 看不到期望的类型
- 看不到失败发生在对象的哪一层

例如 `abort("child")`、`abort("root")`、`abort("name")` 这种消息，脱离上下文以后几乎没有定位能力。

### 2. `panic()` 让结构性断言失去上下文

`src/dom_helper.mbt` 里的 `assert_cmds`、`assert_has_cmd`、`assert_no_cmd` 现在还是直接 `panic()`：

```moonbit
fn assert_cmds(cmds: Array[DomCmd], pats: Array[CmdPat]) -> MatchEnv {
  if cmds.length() != pats.length() { panic() }
  let env = new_match_env()
  for i = 0; i < cmds.length(); i = i + 1 {
    if !cmd_matches(env, pats[i], cmds[i]) { panic() }
  }
  env
}
```

这类 helper 一旦失败，当前测试最需要的信息其实有四个：

- 第几条命令挂了
- 这条断言原本在检查什么
- 实际收到的命令是什么
- 整批命令长什么样

现在四个都没有。

### 3. `catch { _ => panic() }` 把原始错误吞掉了

`src/reactive.test.mbt`、`src/mock_dom.test.mbt`、`service/service.test.mbt` 里有不少这种写法：

```moonbit
flush() catch { _ => panic() }
```

或者：

```moonbit
ignore(@src.runtime_set_roots(editor_runtime(runtime), ["demo"]) catch { _ => panic() })
```

这类写法的问题是：

- 原始错误内容被直接吃掉
- 调用点只剩一个 `panic`
- 测试日志里没有业务上下文

如果这些调用本来就“不该失败”，也应该把原始错误带出来。

### 4. 真正写得比较对的是 `fail(...)`

仓库里已经有一部分测试在这样写：

```moonbit
Ok(_) => fail("expected invalid pid text to fail")
```

或者：

```moonbit
_ => fail("expected browser attr result")
```

这条方向是对的。
问题只是现在消息还偏短，很多地方还没有把 `actual` 一起打出来。

## 典型例子

### 例子一：`src/dom_helper.mbt` 的结构断言

当前测试里有大量这种调用：

```moonbit
let env = assert_cmds(cmds, [
  Create(id("parent"), v("div"), any(), v(DomValue::Empty)),
  Create(id("child"), v("span"), any(), v(DomValue::Empty)),
  Insert(id("parent"), id("child"), v(0), v(true))
])
```

这类断言一旦挂掉，当前输出只会告诉你测试炸了。

这个 helper 最适合改成自定义 assert。

建议不是去硬打印 `CmdPat` 的完整结构。
更实用的做法是让调用方给每条断言补一个短标签，然后 helper 统一输出：

- 序号
- 标签
- 实际命令
- 整批命令

例如把调用改成：

```moonbit
let env = assert_cmds(cmds, [
  ("create parent div", Create(id("parent"), v("div"), any(), v(DomValue::Empty))),
  ("create child span", Create(id("child"), v("span"), any(), v(DomValue::Empty))),
  ("insert child into parent", Insert(id("parent"), id("child"), v(0), v(true)))
])
```

helper 失败时输出：

```text
[assert_cmds] cmd[1] mismatch: create child span
actual: [0,2,"div"]
all cmds: [
  [0,1,"div"],
  [0,2,"div"],
  [1,1,2]
]
```

这类信息已经足够定位问题。

### 例子二：`src/storage.test.mbt` 的对象形状断言

当前 helper：

```moonbit
fn assert_obj_str(
  m: Map[String, PersistValue],
  key: String,
  expected: String,
  label: String
) -> Unit raise {
  match m.get(key) {
    Some(Str(v)) => assert_eq(v, expected)
    _ => abort(label)
  }
}
```

这里更适合改成：

- 如果 key 缺失，打印 key 和当前 object
- 如果类型不对，打印实际值
- 如果字符串值不对，打印 expected / actual

也就是失败信息至少要带：

- label
- key
- expected
- actual

这一组 helper 是全仓库最值得优先改造的一组。
因为它出现最多，而且当前消息最短。

### 例子三：`src/reactive.test.mbt` 的“本不该失败”调用

当前写法：

```moonbit
flush() catch { _ => panic() }
```

这类场景不需要新 error type。
也不需要复杂 helper。

只需要一条统一的小 assert：

```moonbit
fn assert_no_error(label: String, f: () -> Unit raise) -> Unit raise {
  f() catch { err =>
    fail("[\{label}] unexpected error: \{err}")
  }
}
```

然后写成：

```moonbit
assert_no_error("flush after count.set", flush)
```

这样至少能保住原始错误内容。

## 建议的改造方向

### 第一层：统一失败原语

测试 helper 默认优先用 `fail(...)`。

原因：

- 它走正常 `raise Failure` 路径
- 测试顶层可以直接接
- 会带调用位置
- 比 `panic()` 和 `abort()` 更适合表达“断言失败”

建议：

- 测试 helper 里尽量不用 `abort(...)`
- 除了明确要测 panic 的测试，普通断言 helper 里尽量不用 `panic()`

### 第二层：先改 helper，不先改单测

优先顺序：

1. `src/storage.test.mbt` 的 `assert_obj / assert_arr / assert_obj_str / assert_obj_int / assert_item_str`
2. `src/dom_helper.mbt` 的 `assert_cmds / assert_has_cmd / assert_no_cmd / assert_cmd / assert_cmd_json`
3. `src/reactive.test.mbt`、`src/mock_dom.test.mbt` 里重复的 `catch { _ => panic() }`

原因：

- helper 一旦改好，会自动提升整批测试的错误质量
- 先逐条改单测，收益太碎

### 第三层：错误信息格式统一

建议统一成下面这几种形状：

```text
[label] expected X, got Y
[label] missing key: foo
[label] type mismatch at key foo
expected: String
actual:   Int(3)

[label] mismatch
expected: ...
actual:   ...

[label] unexpected error: ...
```

重点不是文案花样。
重点是每条消息至少有：

- label
- expected
- actual

### 第四层：只保留极少数 panic 测试

像 `src/dom.test.mbt` 里的：

```moonbit
test "panic ui-id rejects slash" { ... }
test "panic ui-id rejects colon" { ... }
```

这类测试本身就是在锁“会 panic”的行为。
这种可以保留。

报告里的改造建议不包含这类测试。

## 推荐补的通用 assert

建议最终只保留少量高频 helper。

### 1. 结构比较型

适合比较 `expected / actual`。

```moonbit
fn[T: Show + Eq] assert_eqf(actual: T, expected: T, label: String) -> Unit raise
```

### 2. 无错误保证型

适合替换 `catch { _ => panic() }`。

```moonbit
fn assert_no_error(label: String, f: () -> Unit raise) -> Unit raise
```

### 3. 集合包含型

适合替换 `assert_has_cmd / assert_no_cmd` 这类 helper。

输出重点放在：

- label
- actual item
- all items

### 4. 结构批量断言型

适合 `assert_cmds`。

输出重点放在：

- 第几个元素失败
- 本条 label
- actual
- 整批上下文

## 不建议的方向

### 1. 不建议为测试 helper 新建很多 error type

测试 helper 的目标是让失败信息清楚。
不是把测试失败也建模成正式业务协议。

这里直接 `fail(...)` 就够了。

### 2. 不建议继续扩散 `abort("x")`

`abort` 适合非常粗的“不能继续”。
不适合细粒度断言。

一旦测试开始复杂，`abort("left")`、`abort("root")` 这类消息几乎没有维护价值。

### 3. 不建议把所有 helper 都做成通用大框架

当前仓库最缺的是几条短小、稳定、能打印实际值的 helper。
不是一整套抽象测试 DSL。

## 分阶段改造建议

### 第一阶段

只改 helper。
不批量改测试主体。

范围：

- `src/storage.test.mbt`
- `src/dom_helper.mbt`

预期收益最大。

### 第二阶段

把重复的：

- `catch { _ => panic() }`
- `catch { _ => abort(...) }`

收成统一的 `assert_no_error(...)`。

范围：

- `src/reactive.test.mbt`
- `src/mock_dom.test.mbt`
- `service/service.test.mbt`

### 第三阶段

再看要不要给 `service/repl.test.mbt` 里的 JSON 断言补更细的 `actual` 输出。

这部分当前已经比别处好一些。
优先级低于前两阶段。

## 最后判断

当前仓库测试错误信息最需要解决的不是“没有 assert”。
而是“已有 helper 失败时没有上下文”。

最值得先做的，不是去改业务错误类型。
而是把测试 helper 从：

- `panic()`
- `abort(label)`

收成：

- `fail("[label] ...")`

并且统一补上 `actual`。

只要先把 `src/storage.test.mbt` 和 `src/dom_helper.mbt` 两套 helper 收正，测试失败信息的可读性就会有最明显提升。

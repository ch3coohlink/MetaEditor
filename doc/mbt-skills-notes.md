# MoonBit 开发摘录

这份文档直接从 `../mbt-skills` 里挑了当前仓库最有用的内容，按 MetaEditor
现在的开发边界重新整理。目标不是评价哪些 skill 有价值，而是把能直接拿来用的
命令、约束和检查点落到本仓库里。

这里默认遵守当前仓库已有规则：

- 只做最小补丁，不顺手重排
- 不跑 `moon format`
- MoonBit 改动优先用 `moon-ide` 做符号级操作
- UI、CLI、service 继续走同一条底层命令路径

## 1. MoonBit 改动前先走这条顺序

改 MoonBit 代码时，默认按下面这条顺序来：

1. 先确认 module 和 package 边界
2. 再查当前包和标准库里有没有现成符号
3. 再看定义和引用
4. 最后才动代码

这条顺序的目的不是形式统一，而是避免两类常见失误：

- 明明仓库里已经有现成 utility，却又补了一层新 helper
- 明明只想改一个 package 内部符号，结果靠纯文本搜索把别处也误改了

### 1.1 先看边界

先看这几样：

- `moon.mod.json`
- 当前目录下的 `moon.pkg`
- 涉及调用链的上下游 package

当前仓库里最常用的包边界就是：

- `src`
- `service`
- `test`

MoonBit 的 package 是按目录算的，不是按文件名算的。同一 package 里的 `.mbt`
文件会拼成一个编译单元，所以真正要先确认的是“这个符号属于哪个包”，不是
“这个符号定义在哪个文件名看起来最像的地方”。

## 2. `moon ide` 工作流

这部分主要摘自 `moonbit-agent-guide`，但只保留当前仓库最常用的那几条。

### 2.1 查现成 API

优先用 `moon ide doc`，不要一上来先 `rg`。

常用写法：

```powershell
moon ide doc ''
moon ide doc '@json'
moon ide doc 'String'
moon ide doc 'String::*rev*'
moon ide doc '@async/http'
moon ide doc 'Type::method'
```

适用场景：

- 不确定标准库或依赖包里有没有现成函数
- 想确认某个类型到底已经暴露了哪些方法
- 想找某个名字但不确定完整路径

### 2.2 看包内结构

```powershell
moon ide outline .
moon ide outline src
moon ide outline service
```

适用场景：

- 想快速看当前包暴露了哪些顶层符号
- 想先摸清 package 结构，再决定往哪个文件补代码

### 2.3 看定义

```powershell
moon ide peek-def Symbol
moon ide peek-def Type::method
moon ide peek-def Symbol --loc src/file.mbt:12:3
```

适用场景：

- 想直接看实现入口
- 同名符号较多，需要靠位置 disambiguate

### 2.4 看引用

```powershell
moon ide find-references Symbol
moon ide find-references Type::method
moon ide find-references Symbol --loc src/file.mbt:12:3
```

适用场景：

- 判断某个 helper 是不是还能删
- 判断缩 public 面会不会影响别的包
- 改签名之前先估影响面

### 2.5 真要改名时再用 rename

```powershell
moon ide rename old_name new_name --loc src/file.mbt:12:3
```

只在明确要做符号级重命名时用。平时不要为了省事把 rename 退化成大范围搜索替换。

## 3. 当前仓库推荐的验证顺序

这部分保留 `moonbit-agent-guide` 里有用的顺序，但按本仓库现状改写。

### 3.1 改 `src`

先跑：

```powershell
moon test
```

如果只是局部改动，也可以先跑更小范围，再决定要不要整包跑。

### 3.2 改 `service`

先看是否涉及 native 路径，再决定验证顺序。

当前常用入口：

```powershell
moon test
.\test-native.ps1
```

如果只改 MoonBit 逻辑但没碰原生桥接，通常先 `moon test` 就够判断大方向。  
如果碰了 `service/stub.c`、`extern "C"`、进程和文件句柄之类的宿主逻辑，
就应该补跑 `.\test-native.ps1`。

### 3.3 改 app/service 联动路径

```powershell
.\meta.ps1 test
```

这条适合验证“服务入口、页面会话、测试入口”是不是还在同一条主路径上。

## 4. `service` 的 FFI 约束

这部分主要摘自 `moonbit-c-binding`，但只保留当前仓库已经会遇到的东西。

当前仓库里直接相关的文件有：

- [`service/moon.pkg`](D:\Users\ch3co\Desktop\mbt_race\MetaEditor\service\moon.pkg)
- [`service/stub.c`](D:\Users\ch3co\Desktop\mbt_race\MetaEditor\service\stub.c)
- [`service/fs.mbt`](D:\Users\ch3co\Desktop\mbt_race\MetaEditor\service\fs.mbt)

### 4.1 写 extern 前先答清楚这几个问题

1. 这个值是 primitive，还是对象/句柄？
2. 这个对象由 MoonBit 管，还是由 C 管？
3. 参数只是调用期读取，还是会被 C 保存到后面？
4. 返回值是否需要 finalizer？
5. Windows 和非 Windows 是否行为不同？

如果这些问题答不清，先不要急着落 extern。

### 4.2 参数注解不要含糊

从 `moonbit-c-binding` 里最该保留的就是这一点：

- 调用期间只读，不保存引用，用 `#borrow`
- 所有权转给 C，用 `#owned`
- C 完全自管生命周期时，考虑 `#external`

现在仓库里已有的 `service/fs.mbt` 还比较简单，但后面只要再往 `service`
补更复杂的宿主对象，这条边界很快就会变成 correctness 问题，不只是风格问题。

### 4.3 平台分支要和声明一起看

当前 `service/stub.c` 已经分成了 `_WIN32` 和非 Windows 两条路径。以后新增
原生能力时，不要只看 `.mbt` 侧签名，也不要只看某一个平台分支。

至少要同时确认：

- MoonBit 侧类型
- Windows 分支
- 非 Windows 分支

同名函数如果两边行为不一致，文档和测试都要把差异写出来，不要默默留一条隐性分叉。

### 4.4 字符串和字节边界

从 `moonbit-c-binding` 里保留下来，当前最值得反复提醒的是这条：

- C 侧到底拿的是 UTF-8 字节串，还是 UTF-16 宽字符
- MoonBit 侧到底对应 `Bytes` 还是 `String`

当前 `service/stub.c` 的 Windows 分支直接在操作 `WCHAR` 和 `moonbit_string_t`，
这就意味着以后类似的接口不能只看“都是字符串”就照抄现有写法，必须先确认宿主 API
到底吃哪种编码。

### 4.5 原生改动最好补 native 验证

只要改的是下面这些东西，就尽量别只停在 `moon test`：

- `stub.c`
- `extern "C"` 声明
- 进程检测
- 文件句柄
- 临时目录
- 平台相关路径

优先补：

```powershell
.\test-native.ps1
```

如果后面真的开始引入更复杂的 native 资源管理，再考虑把 `moonbit-c-binding`
里提到的 ASan 校验链补进来。

## 5. 从 `moonbit-lang` 摘出来的高频坑点

这部分不是完整语言说明，只保留当前仓库最常撞到、或者以后继续写 MoonBit
时很容易混的点。

### 5.1 错误处理

- 用 `suberror` 定义错误类型
- 想把抛错函数转成 `Result`，用 `try?`
- 只想继续往上抛时，不需要额外写 `try`

### 5.2 可变性

- `let mut` 只在变量本身要重绑定时才需要
- `Array`、`Map` 这类容器的原地操作，不代表变量声明必须是 `mut`

### 5.3 包调用

- 跨包调用用 `@alias.fn`
- 不要把文件名误当成命名空间

### 5.4 视图类型

下面这些都优先考虑先传 view，不要先复制一份：

- `StringView`
- `BytesView`
- `ArrayView[T]`

如果只是读，不需要拥有权，view 往往更合适。

### 5.5 测试写法

保留当前仓库已经在用、而且和 `moonbit-lang` 一致的部分：

- 简单值用 `inspect`
- 复杂结构用 `@json.inspect`
- 可抛错函数在测试里先 `try?`

## 6. 当前仓库不直接照搬的部分

下面这些在原 skill 里可能是通用建议，但不直接适用于当前仓库：

- 跑 `moon fmt`
- 为了更 idiomatic 顺手重排文件
- 在没有明确需求时主动扩 public API
- 为了兼容阶段性迁移长期保留并行入口

本仓库优先级更高的还是：

- 功能相同时代码更短
- 语义只有一条主路径
- 最小补丁
- 不引入额外状态和临时概念

## 7. 后面真的要继续沉淀的话，先补这两份

如果这份文档后面还要继续拆细，优先拆成下面两份：

- 一份单独的 `service` FFI 约束文档
- 一份单独的 MoonBit 导航与验证速查

这样后面查的时候会比继续往这份总表里堆内容更直接。

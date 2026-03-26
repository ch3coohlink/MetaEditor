# mbt-skills 可复用内容整理

这份文档不是在复述 `../mbt-skills` 的全部内容，而是只整理其中对当前
MetaEditor 仓库价值较高、并且能和现有约束兼容的部分，方便后面需要时直接取用。

这里默认以当前仓库的真实边界为前提：

- 已有 MoonBit 主体代码，分成 `src`、`service`、`test`
- `service` 已经有原生 FFI 和 `stub.c`
- 测试主路径已经存在，不准备把整仓改成另一套 spec-first 流程
- 改动风格仍然遵守当前仓库自己的最小补丁、紧凑写法和单一路径原则

## 1. 结论先放前面

`../mbt-skills` 里当前最值得吸收的是三块：

- `moonbit-c-binding`
- `moonbit-agent-guide` 里的 `moon ide` 工作流
- `moonbit-lang` 里的语法与标准包边界参考

另外两块：

- `moonbit-spec-test-development`
- `moonbit-extract-spec-test`

不是没用，但更适合新库建模或把旧实现反推成 spec 的场景。对当前仓库来说，
短期优先级不高。

## 2. `moonbit-c-binding` 为什么最有价值

当前仓库的 `service` 已经不是纯 MoonBit，它实际包含原生桥接：

- [`service/moon.pkg`](D:\Users\ch3co\Desktop\mbt_race\MetaEditor\service\moon.pkg)
  已经声明了 `native-stub`
- [`service/stub.c`](D:\Users\ch3co\Desktop\mbt_race\MetaEditor\service\stub.c)
  已经在做平台分支和宿主 API 适配
- [`service/fs.mbt`](D:\Users\ch3co\Desktop\mbt_race\MetaEditor\service\fs.mbt)
  已经在声明 `extern "C"` 接口

所以这份 skill 的价值不是“以后可能会用到”，而是现在就能作为 FFI 规则库。

它里面最值得保留的是这些点：

- 先做类型映射，再写 extern，不要边写边猜
- 非 primitive 参数要明确区分 `#borrow` 和 `#owned`
- 需要 GC 托管销毁时，用 external object + finalizer
- C 完全自管生命周期时，用 `#external`
- `Bytes` 和 C 字符串之间的传递边界要写清楚
- 原生绑定最好有一条 ASan 校验路径，避免“功能看着对，但内存语义是坏的”

这几条都和当前 `service` 目录直接相关。以后只要继续往 `service/stub.c`
里补宿主能力，这份文档都值得反复查。

## 3. `moonbit-agent-guide` 里真正该拿的是什么

这份 guide 很长，但不是整份都值得搬。对当前仓库真正高价值的是它把
`moon ide` 这套语义级工具整理成了固定工作流。

当前最值得吸收的不是“官方式开发流程”，而是下面这条很实际的操作顺序：

1. 先确认 module/package 边界
2. 用 `moon ide doc` 查已有 API
3. 用 `moon ide outline`、`peek-def`、`find-references` 做符号级定位
4. 只有在确实要做符号重命名时才用 `moon ide rename`
5. 改完立刻跑 `moon check` 和对应范围的 `moon test`

这条顺序和当前仓库的相性很好，因为它本质上是在减少两类错误：

- 误判某个名字是局部 helper，结果它其实是 package 级符号
- 纯文本搜索命中过多，改动扩散到不该动的地方

对 MetaEditor 这种 MoonBit 包比较多、测试也在持续演进的仓库来说，
这套方法比“先全局 grep 再手改”更稳。

## 4. `moonbit-lang` 适合怎么用

`moonbit-lang` 更像一份 MoonBit 语言与标准包参考库，而不是项目内风格指南。

它对当前仓库最有价值的地方主要有三类：

- MoonBit 语法边界
  - 例如 `raise`、`try?`、`suberror`、`pub` / `pub(all)` 这些容易混的细节
- 标准包与导入边界
  - 例如 `moonbitlang/x`、`moonbitlang/async` 下已有的能力
- 手写 parser 风格参考
  - 适合以后写 parser 或 token view 推进逻辑时对照

它不适合直接当项目规范照抄，原因也很明确：

- 当前仓库已经有自己的 MoonBit 风格约束
- 当前仓库明确禁止 `moon format`
- 当前仓库强调最小补丁，不鼓励顺手大整理

所以这份内容更适合作为“查语言边界和查现成能力”的资料，而不是拿来覆盖本仓库的规则。

## 5. 为什么 spec/test 两块现在不是高优先级

`moonbit-spec-test-development` 和 `moonbit-extract-spec-test` 的核心思路都比较清楚：

- 一种是先写 spec，再补实现
- 一种是从现有实现里反推 spec 和成体系测试

这两条路本身没有问题，但和当前仓库的主要矛盾不完全对口。

当前仓库已经有：

- `src` 自己的测试
- `service` 自己的测试
- `test-native.ps1`
- `meta.ps1 test`

也就是说，现在更重要的是把现有主路径继续压稳，而不是把整个工程切到新的
spec-first 工作流上。

如果后面出现下面这些场景，它们的价值才会明显上升：

- 要给一个独立子包抽正式 contract
- 要把一块已有实现的公开 API 系统化沉淀下来
- 要把测试从“功能回归集合”再往“契约验证集合”推进

## 6. 当前仓库里可以直接采用的内容

如果只提炼成可执行约定，目前最值得直接采用的是下面几条。

### 6.1 MoonBit 导航和改动前检查

改 MoonBit 代码前优先按这个顺序来：

1. 先看对应目录下的 `moon.pkg` 和模块边界
2. 优先用 `moon ide doc` 查已有符号和标准库能力
3. 用 `moon ide outline` 或 `peek-def` 定位定义
4. 用 `moon ide find-references` 看影响面
5. 再决定是不是需要真的改代码

这条顺序的核心不是形式，而是避免为了一个局部需求又发明新 helper、
新状态或平行入口。

### 6.2 FFI 改动前检查

如果要继续修改 `service` 里的原生桥接，至少先把这几个问题答清楚：

- 这个句柄的生命周期由谁负责
- 参数是只在调用期读取，还是会被 C 侧保存
- 返回值是 MoonBit 管理，还是 C 自己管理
- 是否需要 finalizer
- 是否存在平台差异
- 是否值得补一条原生路径测试

如果这些问题答不清，通常说明接口还不该急着落代码。

### 6.3 标准包优先于自造 utility

在新增 utility 之前，先确认 `moonbitlang/core`、`moonbitlang/x`、
`moonbitlang/async` 里有没有已经能直接组合出来的东西。

这点和当前仓库的总原则是一致的：功能相同时，更短、更少概念、更少并行入口的实现更好。

## 7. 需要明确过滤掉的内容

从 `../mbt-skills` 吸收内容时，下面这些不能直接搬进来：

- 默认跑 `moon fmt`
- 为了“更 idiomatic”顺手做大范围文件重排
- 在没有明确需求时主动扩张 public API
- 先引入新层次再慢慢回收

这些做法和当前仓库的协作规则有冲突。

## 8. 可以作为后续动作的最小落点

如果后面要把这些内容继续往仓库里沉淀，比较合适的方式不是大改规则，
而是分成三种最小落点：

- 给 `service` 单独补一份 FFI 约束短文档
- 在 MoonBit 相关开发文档里加一段 `moon ide` 工作流
- 需要时再按具体子模块决定是否引入 spec/test 流程

这样吸收的是有用的方法和边界，不会把外部 skill 的整套话语也一起搬进来。

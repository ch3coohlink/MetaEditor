# Codex SDK 调研

## 这份文档在回答什么

这份文档只回答三个问题：

- OpenAI 当前是否公开提供 Codex SDK。
- Codex SDK、Codex CLI 和 Codex 的 GitHub Code Review 分别是什么关系。
- 对当前仓库来说，哪一层更适合拿来做自动化。

这里不讨论设想中的未来能力，只记录当前公开资料已经能确认的状态。

## 当前确认

OpenAI 当前已经公开提供 Codex SDK。官方说明里，Codex SDK 的定位是：把驱动 Codex CLI 的同一个 agent 嵌入到自定义工作流、工具和应用里，而不是只能通过交互式界面使用。官方同时明确说明，如果目标只是直接在 shell 里使用 agent，也可以继续直接使用 Codex CLI。

目前从官方资料能直接确认的点有：

- Codex SDK 已公开。
- SDK 复用了驱动 Codex CLI 的同一个 agent。
- 当前公开说明里，SDK 现阶段提供的是 TypeScript 版本。
- SDK 提供结构化输出，适合程序消费。
- SDK 带有内建的上下文管理，可以继续 thread 或恢复会话。

## 官方最小示例

官方公开的最小 TypeScript 形态是：

```ts
import { Codex } from '@openai/codex-sdk'

const agent = new Codex({})
const thread = await agent.startThread()
const result = await thread.run('Explore this repo')
```

从这个例子至少能看出，当前公开出来的核心抽象包括：

- `Codex`
- `startThread()`
- `thread.run(...)`

## 三层东西分别是什么

### Codex CLI

Codex CLI 是终端里的 Codex 入口。它适合直接在本地 shell 工作流里使用 agent，比如读仓库、改代码、跑命令、看 diff。CLI 本身是开源的，也适合继续在 shell 层再包自己的脚本。

### Codex SDK

Codex SDK 是编程接口。它的意义不是替代 CLI，而是把同一个 agent 变成你自己的程序可以直接调用的能力。相比交互式界面，SDK 更适合做：

- 预装上下文
- 固定 prompt 模板
- 结构化解析输出
- 保存和恢复会话状态
- 嵌入现有自动化工具

### Codex Code Review

Codex Code Review 是产品层的额外能力面，主要指 GitHub 上的 review 工作流。官方描述里，它可以在仓库开启后自动 review PR，也可以通过在 PR 里显式提到 `@codex review` 来触发。

这一层和 SDK / CLI 不是同一层概念。它不只是“把同一个 agent 换个 prompt 再跑一次”，还包含：

- GitHub PR 入口
- 自动 review 工作流
- 产品侧能力配置
- 独立的计量与额度口径

## Code Review 和一般 Codex usage 的区别

当前官方帮助中心把 GitHub 上的 Code Review 单独列成一类使用方式。官方 rate card 里，Code Review 直接按 “`1 pull request`” 记，而不是按普通本地任务那类 usage 口径写在一起。帮助中心同时说明，只有 Codex 通过 GitHub 执行 review 时，才算 Code Review usage；如果是在本地或 GitHub 之外做 review，仍然算一般 Codex usage。

这意味着：

- GitHub Code Review 是单独的产品能力面。
- GitHub Code Review 的计量和一般 CLI / 本地任务不是同一口径。
- 不能把 GitHub Code Review 直接等价成“SDK 已经公开的一个普通函数调用”。

## 对当前仓库的实际意义

对这个仓库来说，当前最值得区分的是两种自动化目标。

第一种目标是“让 Codex 更容易被脚本调用”。这时最合适的是 Codex SDK 或 Codex CLI：

- 如果需要结构化输出、上下文管理、内嵌到自己的工具里，优先看 SDK。
- 如果只是想在 shell 里更顺手地调用 agent，继续包 CLI 就够了。

第二种目标是“复用 Codex 在 GitHub 上的 Code Review 工作流”。这时不能默认 SDK 就能一比一替代，因为 GitHub Code Review 还依赖产品侧入口、仓库集成和独立计量。

## 结论

如果目标是提高 Codex 在本项目里的可组合性，当前最靠谱的方向不是试图自动驱动 Codex 的交互界面，也不是把 GitHub Code Review 直接等价成 SDK 能力，而是先明确要自动化的是哪一层：

- 要做本地自动化和工具链集成，优先看 Codex SDK 或 Codex CLI。
- 要做 GitHub PR review 自动化，应该把它当成单独的产品能力面理解，不要和 SDK 混为一谈。

## 参考

- OpenAI Help Center: https://help.openai.com/en/articles/11369540/
- OpenAI: https://openai.com/index/codex-now-generally-available/
- OpenAI: https://openai.com/index/introducing-upgrades-to-codex/
- OpenAI Codex 仓库: https://github.com/openai/codex
- OpenAI Help Center rate card: https://help.openai.com/en/articles/20001106-codex-rate-card

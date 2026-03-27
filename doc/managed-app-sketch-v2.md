# managed app 草稿 v2

这份文档是在 `managed-app-sketch.md` 基础上的收敛版，只写当前更明确的部分，不展开实现细节。

## 1. 前提

MetaEditor 里的 managed app，不只是一个可以启动和关闭的运行实例，而是 host 管理下的 app 开发对象。

host 至少要记住：

- 现在有哪些 app 正在开发中
- 每个 app 的名字和身份
- 它的代码路径在哪里

这里先按 MoonBit 专用处理，不做通用 build 系统抽象。

## 2. 两层对象

当前先把模型分成两层：

- `AppProject`
- `AppInstance`

语义分别是：

- `AppProject` 表示一个被 host 纳入管理的 MoonBit app 项目
- `AppInstance` 表示从某个项目发起的一次 `run`

当前不单独引入 `Session`。先直接把一次 `run` 看成一轮开发实例。

## 3. AppProject

`AppProject` 先只保留最小字段：

- `id`
- `name`
- `path?`

字段语义：

- `id`：项目的稳定标识，也带着包身份的味道
- `name`：host 里的展示名
- `path?`：项目路径；如果为空，就表示这个项目位于统一指定的公共 app 路径下

这里不再把 `root_path` 和 `package` 拆成两个平行字段。第一版先承认它更像“一个 MoonBit app 项目入口”，不要为了形式整齐再拆出重复信息。

## 4. AppInstance

`AppInstance` 先只保留最小字段：

- `id`
- `project_id`
- `status`

字段语义：

- `id`：实例标识
- `project_id`：它来自哪个 `AppProject`
- `status`：实例当前状态

`status` 当前先只考虑最小集合：

- `starting`
- `running`
- `stopped`
- `failed`

这里默认支持多实例：

- 一个 `AppProject` 可以派生多个 `AppInstance`
- 不引入“当前 project”“当前 app”这类带单实例倾向的工作区状态

## 5. host 持久化边界

host 当前需要持久化的核心内容，先只包括项目清单：

```text
projects: Array[AppProject]
```

先不持久化实例列表，也不持久化“当前正在看哪个 app”这类工作区状态。

原因很简单：

- 项目清单是 service 重启后必须恢复的开发上下文
- 实例是运行态对象，不应该在这一步就和项目层揉在一起
- 提前保存“当前 app”很容易把模型压回单实例

## 6. 动作

如果先按最小主路径收，host/runtime 第一批动作可以只有：

- `add_project`
- `remove_project`
- `list_projects`
- `run_project`
- `stop_instance`
- `list_instances`

这里先不强行区分“动作”和“查询”。

原因是当前更重要的是统一主路径：

- 对 CLI 来说，它们都表现成一次命令调用
- 对 host/runtime 来说，它们都应该走同一套命令入口
- 真正的区别先留在语义层，不急着在接口分层上展开

所以这一版先统一把它们都叫动作，先把调用路径收成一条，再看后面是否需要单独拆查询模型。

## 7. UI / CLI 同源性

UI 和 CLI 的同源性，不应该建立在“CLI 去读取已经渲染出来的 DOM”上。

原因很直接：

- UI 可能用虚拟 DOM
- 列表项很多时，UI 不一定真的把所有项都渲染成 DOM
- 如果 CLI 依赖 DOM，拿到的就可能只是局部结果

所以更稳的主路径应该是：

- host/runtime 持有同一份结构化项目/实例数据
- UI 用它生成虚拟 DOM
- CLI 用它生成文本输出

如果后面需要共享格式化规则，也应该尽量是：

- 结构化数据 -> 展示文本 / 展示片段

而不是反过来从 DOM 抽取 CLI 输出。

## 8. 输出接管

managed app 不只是“能不能启动”，还要把开发过程里的输出接进 host。

至少要考虑这几类输出：

- 文本输出
- 错误输出
- app 自己的 UI 输出

也就是说，host 后面管理的不是一个单薄的启动器，而是 app 开发过程里的统一宿主。

## 9. 当前先不展开的部分

这份草稿暂时不展开这些内容：

- build / reload 的具体流程
- 错误和日志在 host 里的具体呈现
- host UI 的窗口系统形态
- 每个 app 独立数据空间的具体 key 设计

这些不代表方向没定，而是先不在这份最小草稿里展开。

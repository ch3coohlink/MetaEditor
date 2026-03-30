# managed app 草稿 v3

## 1. 前提

MetaEditor 里的 app 是顶层运行对象。

editor / component 是 app 内部的可组合单元。一个 app 可以从一个 editor 启动，也可以从一组
editor / component 组合出来的入口启动。

当前只保留最小模型：

- `AppEntry`
- `AppInstance`

## 2. AppEntry

`AppEntry` 表示一个可启动的 app 入口。

先只保留最小字段：

- `id`
- `name`

字段语义：

- `id`：入口的稳定标识
- `name`：host 里的展示名

`AppEntry` 由源码里的内部 API 注册。

这里的重点是：

- entry 只负责声明“这个 app 从哪里启动”
- entry 背后可以是一个 editor，也可以是一组 editor / component 的组合入口
- host 只消费这份入口表，不关心内部具体怎么组装

当前 `AppEntry` 只管加，不管删。

## 3. AppInstance

`AppInstance` 表示一次运行中的 app。

先只保留最小字段：

- `id`
- `entry_id`
- `status`

字段语义：

- `id`：实例标识
- `entry_id`：这个实例是从哪个 `AppEntry` 启动的
- `status`：实例当前状态

`status` 当前先只保留：

- `starting`
- `running`
- `stopped`
- `failed`

这里先把 `status` 明确看成生命周期状态，不让它承担日志、输出、UI 连接之类别的语义。

## 4. 注册方式

`AppEntry` 不是外部动作，也不是动态导入结果。

它来自源码内部注册。

当前先按最小能力理解：

- 某处源码定义 entry
- 初始化时把 entry 注册到 host 可见的入口表
- host 后面只做列出入口、按入口启动实例

这里先不展开具体 API 名字。

## 5. host 关心的内容

host 当前只需要关心两类东西：

- 现在有哪些 `AppEntry`
- 现在有哪些 `AppInstance`

host 不需要知道 app 内部 editor 树长什么样，也不需要直接管理 editor 组合细节。

## 6. 第一批动作

如果先按最小主路径收，host 第一批动作可以只有：

- `list_entries`
- `run_entry`
- `stop_instance`
- `list_instances`

当前不把 entry 注册写成动作，因为它本来就是源码内部能力。

## 7. 输出接管

managed app 不只是“能不能启动”，还要把 app 运行过程里的输出接回 host。

至少要考虑这几类输出：

- 文本输出
- 错误输出
- app 自己的 UI 输出

这些输出都属于 app 本体的一部分。

## 8. 当前先不展开的部分

这份草稿暂时不展开这些内容：

- `AppEntry` 的具体注册 API
- entry 背后 editor 组合的表示方式
- build / reload 的具体流程
- 错误和日志在 host 里的具体呈现
- host UI 的窗口系统形态
- 每个 app 独立数据空间的 key 设计

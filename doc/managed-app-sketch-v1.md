# managed app 草稿

这份文档只收当前已经讨论确定的最小模型，先不展开运行细节和持久化实现。

## 1. 前提

MetaEditor 里的 managed app，是 host 管理下的 app 开发对象，不只是一个可以启动和关闭的运行实例。

host 首先要记住：

- 现在有哪些 app 正在开发中
- 每个 app 对应的项目目录在哪里
- 它对应哪个 MoonBit package

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
- `root_path`
- `package`

```用户批注
id 其实就已经是包名的味道了，可能后面还要有 开发者/package_id 的名称空间区分
root_path 和 package 有点重复啊，其实是一个东西拆成两个
```

字段语义：

- `id`：项目的稳定标识
- `name`：host 里的展示名
- `root_path`：项目根目录
- `package`：这个项目要操作的 MoonBit package

这一层只描述“项目是什么”，不描述当前有没有实例正在运行。

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

## 6. 第一批动作

如果先按最小主路径收，host/runtime 第一批动作可以只有：

- `add_project`
- `remove_project`
- `list_projects`
- `run_project`
- `stop_instance`
- `list_instances`

```用户批注
list_projects 应该是一个动作吗？我感觉它是一个查询，但如果为了概念简洁性的话说它是动作也可以
另外还有一个值得讨论的问题就是，由于本项目ui和cli的同源性要求，以及ui经常会有获取一个列表，但ui里实际上使用虚拟dom，没有渲染那么多列表项的dom的情况出现，我觉得这一块需要讨论一下，同源性到底怎么实现为好
这里还有个一个值得注意的点就是 cli 需要的很多数据显示的格式化，和 ui 需要的数据格式化也是类似的，我原本想的是数据的显示格式都从 dom 获取（因为已经被格式化过了，于是格式化就能同源处理），不过考虑虚拟dom的话还得再想想
```

这批动作已经够覆盖最小闭环：

- 管理开发中的 app 项目
- 从一个项目发起多次 `run`
- 查看当前实例
- 停掉某个实例

## 7. 当前先不做的事

这份草稿暂时不展开这些内容：

- 实例内部更细的生命周期
- build / reload / error 细节
- project 和 instance 的持久化格式
- host UI 具体怎么呈现多实例
- 持久化数据目录和 storage/sqlite 接线

```用户批注
- 实例内部更细的生命周期：我觉得不太需要
- build / reload / error 细节：这个要显示在ui上，实际上我们应该接管app的所有输出，不管是文本的，还是ui的
- project 和 instance 的持久化格式：这个是在说什么
- host UI 具体怎么呈现多实例：host ui 迟早会变成一个窗口系统的
- 持久化数据目录和 storage/sqlite 接线：这个就是接入一下kv啊前面讨论得够清楚了吧，实现也写了，就是我们要给每个app都bind_with_kv一下，每个app默认有个独立的数据空间
```

这些都等 `AppProject` / `AppInstance` 这层边界先收稳以后再往下接。

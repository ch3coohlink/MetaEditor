---
name: meta-editor-skill
description: 处理 MetaEditor 仓库代码、语义、边界与相关测试时使用
---

# MetaEditor Repo Skill

进入本 skill 后，先按这里的设计逻辑理解系统，再去读当前实现。不要自己发明平行模型。

## 1. 先理解这个系统为什么这样长

MetaEditor 有两条逻辑，要一起看。

### 自底向上

这套系统是这样搭起来的：

1. `reactive` 提供最小响应式内核，解决依赖收集、作用域、增量重跑、flush
2. `dom` 建在 `reactive` 上，维护一棵会持续变化的可变 DOM 树
3. `entry / instance` 把 UI 组织成可实例化、可查询、可调用 action 的对象
4. `runtime` 把 instance tree 渲染到 DOM，并对外提供统一运行时
5. `service / browser / cli / http / repl` 只是站在不同入口去驱动同一个 runtime

所以这套系统的根，不是“先有页面，再补自动化”，而是：

- 先有响应式更新能力
- 再有可持续维护的界面树
- 再有实例化的编辑器对象模型
- 最后把这套模型暴露给不同入口

### 自顶向下

这套系统的目标也不是普通页面渲染。

它想做的是：

- 一套用于构建复杂编辑器的 UI 框架
- 一套把 AI 操作当第一等能力的控制面

这两件事一起决定了很多底层约束：

- UI 不能只是一次性 render 结果，必须能长期维护和查询
- 业务对象不能只是匿名组件，必须能作为 instance 被创建、关闭、查询、调用 action
- CLI、浏览器、HTTP、测试、AI 都在操作同一个系统，所以语义必须共用一条主路径

## 2. 这套设计自然推出的硬约束

### 运行时节点 identity 必须稳定

DOM 层维护的是一棵可变树，不是每次整棵重建。

所以只要某个节点还在被当成“同一个节点”更新，它就应该继续沿用同一个运行时
identity。增量 patch、事件绑定、节点复用都依赖这件事。

### 外部可寻址语义必须稳定

外部调用方需要稳定定位目标，但不该依赖浏览器内部瞬时节点 `id`。

所以公开 GUI 能力站在 path 上。`ui-id`、名称空间、列表作用域负责提供稳定的可寻
址语义。运行时节点 `id` 留在内部实现和白盒测试里。

### 查询作用域和列表作用域是基础设施

复杂编辑器里重复结构和动态列表是常态。path 不能靠业务层手搓长名字，更不能把业务序号硬编码进 `ui-id`。

所以名称空间、列表作用域、稳定列表 identity 都是基础设施，不是写界面时顺手补的小技巧。

### `react:scope` 是单独的 reactive ownership

查询作用域和 reactive 生命周期不是一回事。

`ui-id:scope`、`ui-id:list` 是带语义的 `ui-id` 短写。`react:scope` 另外创建本地 reactive scope，负责把这段 UI
里的 effect 和清理动作挂到正确的宿主节点上。

### 所有入口都必须走同一条底层路径

这套系统从一开始就要求：

- UI 操作
- CLI 操作
- HTTP 操作
- browser harness
- AI 驱动

描述的是同一件事。

所以不能为了局部方便再发明平行入口、隐藏入口、测试专用正式语义。

## 3. 概念只是这些约束的实现

读代码时，先把下面这些概念当成“设计落点”，不要当成孤立术语背。

### `Cel / effect / scope / flush`

这是响应式内核。

- `Cel` 保存状态
- `effect` 建依赖和重跑
- `scope` 管生命周期
- `flush / try_flush` 把积累的变更真正推出去

### `Child`

这是 DOM 构建输入，不是已经落地的节点。

`Str`、`Arr`、`Dyn`、`Lazy` 这些都还在描述“要生成什么”，真正进入可变 DOM 树以后才会变成
`VNode` 和对应的 DOM command。

### `VNode`

这是 DOM 层的节点 identity。它对应的是那棵可变界面树里的稳定节点，不是一次 render 的临时中间值。

### `DomCmd`

这是 DOM 层对外发出的增量命令流。`Create / Text / Attr / Append / Remove / Listen ...`
这些命令描述的不是业务语义，而是运行时怎样把那棵可变树同步到浏览器端。

`dom` 层重要的不是“重新吐整棵树”，而是持续维护 `VNode`，然后只推出必要的 command。

### `Dyn`

这是结构切换工具。它适合表达结构真的在变的地方，不适合把“局部样式/文本/属性更新”伪装成整棵重建。

### `h_map / h_map_dyn`

这是动态列表主路径。它同时解决两件事：

- 列表 item 的稳定 identity
- 列表查询的 list scope

当 `h_map / h_map_dyn` 带 `ui_id` 时，默认会创建一个同名 wrapper 节点。

这个 wrapper 同时承担三件事：

- 真实 DOM 宿主
- CSS 锚点
- query 的 list 域入口

需要时可以显式传 `wrap=false` 关掉。也可以传 `tag="ul"` 这类标签名改 wrapper 标签。

### `ui-id`

这是公开可寻址语义的根。path 的稳定性从这里开始。

`ui-id` 不是运行时节点 identity，也不是业务序号槽位。它负责给外部世界一个稳定名字，同时默认
也作为样式锚点。

默认推荐短 `ui-id`。path 语义靠名称空间和列表作用域补全，不靠在单个 `ui-id` 里重复编码父层语义。

对应的新写法里：

- `ui-id` 表示普通稳定名字
- `ui-id:scope` 表示“这个名字同时是名称空间入口”
- `ui-id:list` 表示“这个名字同时是列表作用域入口”

普通 `ui-id` 不自动再开一层 query 域。

list item 根可以有自己的 `ui-id`。这类 `ui-id` 默认只是 item 内普通名字，不表示再开一层域。

### 两种 query scope

这层至少要分清两种 scope：

- 名称空间 scope：由 `ui-id:scope` 提供，用来缩短局部 path
- 列表 scope：由 `ui-id:list` 或带 `ui_id` 的 `h_map / h_map_dyn` 提供，用来解析索引和 item 内路径

这两种 scope 都属于查询基础设施。它们解决的是 path 怎么走，不负责 reactive 生命周期。

query 走的是这些 scope 暴露出来的名字，不是沿 DOM 树位置一层层下钻。

### `react:scope`

这是单独的 reactive scope。它不负责给 path 命名，负责的是把一段局部 UI 的 effect ownership
挂到宿主节点上，并在宿主节点移除时停掉这段 reactive。

### `Entry / Instance`

这是编辑器对象模型。

- `Entry` 定义一类可实例化对象：数据、session、view、actions
- `Instance` 是运行时实例，可以被创建、挂树、查询、关闭、调用 action

### `runtime`

这是总运行时。它把 instance tree 渲染到 DOM，把 query/action/root 管理收在一起，再把能力交给外围入口。

### `action / query / trigger`

高层正式语义里，编辑器操作只有一个概念：`action`。

- `action` 表示高层语义级的编辑器操作
- `exec` 只是 CLI 里“执行一个 action”的命令名
- `query / trigger` 是对 GUI 的正式控制面，面向 path

AI 和自动化本来就该走这些正式能力，不该绕到内部瞬时细节上。

### `Json`

`Json` 在这个项目里默认只是边界协议格式，不是内部正式业务模型。

- 内部语义先写成正常类型
- 到 websocket / http / CLI `--json` 这类边界时再转 `Json`
- 外面进来的 `Json` 也应尽快解回 typed 结构，不要让 `Json` 在 runtime / mock / bridge 内部长时间流动
- 同形状的东西只保留一份类型。已有类型能承载时，先复用它；如果只是少编解码能力，先补 codec；只有协议形状和现有类型真的不同，才允许新建边界类型

## 4. 进入任务后先怎么读代码

先按改动落点读当前实现，不要先围着文档打转。

默认顺序：

1. 先看 `src/reactive.mbt`，理解 flush、scope、effect 的主路径
2. 再看 `src/dom.mbt`，理解可变 DOM 树、查询、列表、bridge 接口
3. 再看 `src/entry.mbt` 和 `src/runtime.mbt`，理解 instance tree 和 runtime
4. 涉及外围入口时，再看 `service/bridge.mbt`、`service/cli.mbt`、`src/bridge.js`

按需再看：

- `references/dom-query.md`
- `references/dom.md`
- `references/json.md`
- `references/bridge.md`

reference 只负责辅助说明。当前实现才是这次任务要对齐的对象。

## 5. 工作时用什么判断问题

先问这几个问题：

1. 这次改动落在 `reactive`、`dom`、`instance/runtime`、还是外围入口
2. 它是在补同一条主路径，还是又造了平行路径
3. 它是在维护稳定 identity，还是把局部更新写成整棵重建
4. 它是在补正式控制面，还是把内部瞬时细节往外泄露
5. 它会不会破坏“人和 AI 操作的是同一个系统”这条前提

这几条里只要有一条答不稳，就先停下来查代码和边界，再动手。

## 6. 硬规则

### reactive / flush

- 外部状态更新要继续走现有 `try_flush()` 主路径
- 不要自行补第二套 flush API
- 不要拿别的入口替代现有 reactive 提交路径

### DOM / identity

- 把 `VNode` 当成长期存活的真实节点看
- 只有节点真的消失时才移除
- 只改样式、属性、文本、listener 时，优先保留稳定根节点
- 不要把这类局部更新写成外层 `Dyn(fn() { h(...) })`

### 查询 / 列表 / 命名

- `ui-id` 是稳定命名源，也是默认样式锚点
- 默认推荐短 `ui-id`
- `/` 不要出现在 `ui-id` 里
- `:` 只保留给 `ui-id:scope`、`ui-id:list` 这种语法，不要拿它编码业务语义
- 不要把列表位置、业务序号、临时 serial 编进 `ui-id`
- 动态列表若需要 item 级查询、交互或稳定 identity，必须提供 list scope
- 默认优先用 `h_map / h_map_dyn`
- `ui-id`、`ui-id:scope`、`ui-id:list`、`react:scope` 各有职责，不要混着理解
- query 走的是名称空间和列表作用域，不是 DOM 树层级遍历
- 讨论结构时，先分清是在讲 DOM 树，还是在讲 `ui-id` 域树
- DOM 上被谁包住，不等于 query 上必须多一层名字
- 父层作用域已经成立时，叶子名字保持短，不要把父层语义重复编码进每个子节点

### path / 外部控制面

- 公开 GUI 能力保持 path-first
- 不要让业务层直接依赖运行时节点 `id`
- 不要在 service 或 bridge 里补第二套查询/触发语义
- 不要为了测试方便暴露新的生产接口

### 事件

- 不要通过 listener 属性字符串继续扩展事件语义
- `.stop`、`.prevent` 这类写法按禁止项处理
- 如果当前实现里还有这类残留，先向用户报告，不要顺着它继续扩写
- 需要 `preventDefault`、`stopPropagation`、capture、passive 这类能力时，走显式结构化参数设计

### 样式

- 样式主路径优先走 CSS
- `css(...)` 放模块级定义，不要塞进 render 或其他会反复执行的路径
- 内联 `style` / `style:*` 只留给窄动态值
- 不要为同一个锚点机械重复写一份同义 `class`
- 短 `ui-id` 会派生短 class。写 CSS 时用作用域组合后的层级选择器，不要直接写大范围的叶子 class 选择器
- CSS 默认按 `ui-id` 域写选择器，不按 DOM 包裹层和标签名机械抄长路径
- `css("host", ...)` 这类模块级样式会自动带作用域前缀，不要再手写同一层前缀

## 7. 改动时该联动检查什么

### 改 `reactive` 或 flush

- 检查 reactive 相关测试
- 检查 DOM 提交和 service 回调有没有被带坏

### 改 `src/dom`

- 检查 DOM 测试
- 检查 mock DOM 测试
- 涉及 query / trigger / bridge 时，再检查 browser bridge 测试

### 改 `entry / runtime / host`

- 检查 instance、runtime、host 相关测试
- 涉及路径和外部控制面时，再检查 service 和 e2e

### 改 `service / bridge / cli / browser`

- 检查 service 测试
- 检查 browser bridge 测试
- 涉及完整交互流时，检查 e2e

## 8. 最后只记住一句话

MetaEditor 不是一组零散的页面和脚本。

它是一套从 `reactive` 长到可变 DOM 树，再长到 instance/runtime，最后同时暴露给人和 AI 的统一编辑器系统。

所有代码和文档都应该沿这条主线理解和修改。

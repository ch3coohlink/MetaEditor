# MetaEditor DOM 语义

这份参考文档描述当前 DOM/UI/bridge 模型，以及写相关代码时必须遵守的语义边界

## 1. 核心心智模型

`VNode` 应被视为当前模型里的真实 DOM 节点

- `VNode.id` 是唯一节点 identity
- 节点可以移动并继续接收更新
- 节点只应在真的消失时被移除
- 移除同时意味着 `Remove(id)`、回调、effect、命名信息一起清理

判断一段写法是否正确时，先问一件事：

- 这是在更新已有节点
- 还是在替换成一个全新节点

## 2. 什么时候必须保留节点 identity

只有样式、属性、文本、listener 在变化时，应尽量保留节点 identity

典型场景：

- 选中态变化
- 焦点态变化
- 折叠/展开 class 变化
- 按钮文案变化
- 输入框值变化

推荐：

- 稳定根节点 + `D(...)`
- 稳定根节点 + 局部文本更新
- 稳定根节点 + 局部属性更新

不要把这类场景写成：

```moonbit
Dyn(fn() {
  h("button", [("ui-id", S("entry-x"))], ...)
})
```

连续交互最怕 identity 飘掉：

- `click`
- `dblclick`
- `focus`
- 键盘事件

第一次交互后如果根节点 identity 被换掉，后续事件很容易打到旧 id

## 3. 普通 Dyn 的边界

普通 `Dyn` 仍然没有通用结构复用语义

这意味着：

- `Dyn(fn() { h(...) })`
- `Dyn(fn() { Str(...) })`

只要返回的是全新子结构，就会产生新的 `VNode`
旧 id 会消失
旧节点会被移除

当前适合普通 `Dyn` 的情况：

- 明确的结构切换
- 条件分支
- 小子树，且允许整段替换

当前不适合的情况：

- 只为了改样式、文本、属性，却把整个根节点包进 `Dyn`

## 4. h_map / h_map_dyn 的边界

`h_map` / `h_map_dyn` 是动态列表默认首选，但不要把它误解成唯一合法入口

它的语义核心是两件事：

- 提供 list scope
- 缓存已挂载 item 节点，保住稳定 identity

因此，`h_map` 更接近“带 list scope 的 Dyn”，只是额外带了列表缓存和复用能力

### 当前已经成立的性质

- 保留的 item 可以重排
- 保留的 item 不会被 remove 再 create
- 保留 item 的 listener 会继续挂在原来的原节点上
- 被移除的 item 会停止它内部的动态更新
- item root 即使返回 `Dyn(...)`，当前也会保留稳定 fragment identity

### 当前还不成立的性质

- 普通 `Dyn` 的通用结构复用
- 任意 fresh children 的自动复用
- 非 `h_map` 动态列表的自动 prefix identity 保留

### 实际写法上的指导

- 动态列表若需要 item 级查询、交互或稳定 identity，必须提供 list scope
- `h_map` / `h_map_dyn` 是这类场景最稳的默认写法
- 手写动态列表也可以，但语义上必须等价地提供 list scope
- 不要写“动态列表，但没有 list scope”的结构

## 5. 查询与作用域模型

`ui-id` 是稳定命名源

- `ui-id` 命名稳定节点或宿主边界
- `ui-name` 暴露局部名称空间
- `ui-list` 暴露列表作用域
- `ui-react` 创建局部 reactive ownership 边界

列表查询会跟着当前 `h_map` fragment 模型走
如果 item root 自己是动态的，查询应落到这个 item 当前可见的节点，而不是历史旧节点

两条直接规则：

- 一个节点若需要稳定直达查询，就给它自己的 `ui-id`
- 不要把列表位置重新塞回 `ui-id`

当前查询边界：

- `ui-name` 和 `ui-list` 都要求宿主节点有 `ui-id`
- `ui-name` 只改命名，不拥有 inner reactive effects
- `ui-list` 只改列表查询语义，不拥有 reactive 生命周期
- `ui-react` 才拥有 inner reactive effects，并在宿主节点消失时负责停止它们

### 命名实践

名称空间就是用来把 `ui-id` 写短的

推荐：

- `text`
- `toggle`
- `remove`
- `close`
- `title`

不推荐：

- `todo-text`
- `todo-toggle`
- `window-close-button`

如果父层已经明确给出作用域，不要再把父层语义重复编码进每个叶子

## 6. 列表查询合同

需要 indexed query 时，推荐：

- `h_map(..., ui_id=Some("todos"))`
- `h_map_dyn(..., ui_id=Some("todos"))`

稳定查询合同优先是：

- `todos/0/text`
- `todos/0/toggle`
- `todos/0/remove`

不要把这些当成：

- `todo:1:text`
- `item:42:remove`
- `window:3:close`

也不要把 `<list-ui-id>` 或 `<list-ui-id>/0` 单独当主要业务合同

列表查询宿主只描述一份索引列表：

- 不要把多份无关列表混在同一个 list entry 下
- 不要把空态、footer、placeholder 这类非 item 节点塞进会占索引的位置

## 7. 样式语义

样式主路径优先是 CSS

- 大块视觉规则放 CSS
- DOM 定义里保留结构和语义
- `style` / `style:*` 只留给窄动态值

`ui-id` 本身会派生 class，因此推荐一开始就直接写适合作为样式锚点的 `ui-id`

推荐：

- `todo-list`
- `entry-name`
- `window-title`

默认不需要为同一个锚点再补一份同义 `class`
显式 `class` 只在确实需要额外共享样式语义时再加

不要把某种符号转写规则当成推荐命名模型
推荐实践里直接写稳定、短、适合作为样式锚点的 `ui-id`

## 8. Host / App 编码指导

Host shell、窗口、列表 item、工具栏按钮都很依赖稳定 identity

优先：

- 稳定根节点 + `D(...)` 改样式
- 稳定根节点 + 局部文本更新
- `h_map` / `h_map_dyn` 做动态列表
- item root 下局部动态切换

不要：

- 为简单 host 样式变化重建整个节点
- 在业务层自己维护一套并行列表 id，再拿它拼 UI 名字
- 把列表 identity、查询 path、显示命名绑在同一套业务 serial 上

## 9. 事件与 bridge 边界

bridge 与 DOM/事件模型必须同步

当前稳定规则：

- `DomCmd` 编号应集中定义
- bridge 消息类型应集中定义
- 生产事件分发依赖节点 `id`
- 公开 GUI 能力保持 path-first 的 `query / trigger`
- 节点 `id` 留在 bridge 内部和白盒测试 helper

当前明确禁区：

- 不要通过改 listener 属性字符串扩展事件语义
- `.stop`、`.prevent` 一类写法不可接受
- 若要支持 `preventDefault`、`stopPropagation`、capture、passive，一定要走显式结构化参数设计

当前状态还要特别记住：

- `preventDefault` 的正式参数化模型还没落成
- bridge 里若存在某个事件的局部硬编码，只能当局部补丁理解，不能把它升格成正式模型

## 10. 测试边界

测试也要沿同一条主路径写

- 业务测试优先写高层 `query / trigger`
- 白盒 bridge 测试才直接看节点 `id`
- 不要为了测试方便暴露新的生产接口
- 不要把 transport 细节伪装成 GUI 正式 API

当前目标方向是：

- 调用方只写高层 `trigger` 语义
- bridge / harness 再把它翻译成尽量接近真实浏览器操作的效果

# MetaEditor DOM 语义

这份文档只描述当前成立的 DOM / UI / bridge 语义。

## 1. 核心心智模型

`VNode` 就是当前模型里的真实运行时节点。

- `VNode.id` 是内部唯一 identity
- 节点可以移动并继续接收更新
- 节点只在真的消失时移除
- 移除同时意味着 DOM、effect、query 绑定一起清理

判断一段写法是否正确时，先问一件事：

- 这是在更新已有节点
- 还是在替换成一个新节点

## 2. 什么时候保留 identity

只有样式、属性、文本、listener 在变化时，应尽量保留节点 identity。

典型场景：

- 选中态变化
- 焦点态变化
- 文案变化
- 输入值变化
- 局部属性变化

推荐：

- 稳定根节点 + 局部动态值
- 稳定根节点 + 局部文本更新
- 稳定根节点 + 局部属性更新

不推荐：

```moonbit
Dyn(None, () => {
  h("button", [Id(save)], [Str("Save")])
})
```

## 3. `Dyn`

普通 `Dyn` 表达的是结构切换。

这意味着：

- `Dyn(None, () => h(...))`
- `Dyn(None, () => Str(...))`

只要返回的是一段新结构，就会生成新节点，旧节点会移除。

适合：

- 条件分支
- 结构真的在变
- 小子树替换

不适合：

- 只为了改样式、文本、属性，却把整个根节点包进 `Dyn`

## 4. `h_map / h_map_dyn`

`h_map / h_map_dyn` 是动态列表主路径。

它同时解决两件事：

- item 的稳定 identity
- list scope 查询语义

这里重点是 item 复用和 list scope，本身不强调额外固定 wrapper。

已经成立的性质：

- 保留 item 可以重排
- 保留 item 不会 remove 再 create
- 被移除 item 会停止内部动态更新
- item 内 query 跟着当前可见结构走

写法指导：

- 动态列表若需要 item 级查询、交互或稳定 identity，提供 list scope
- `h_map / h_map_dyn` 是最稳的默认写法
- 手写动态列表也可以，但语义上要等价地给出 list scope

## 5. `ui-id`

`ui-id` 是稳定命名源，也是默认样式锚点。

- `ui-id` 不等于运行时节点 `id`
- `ui-id` 不承担业务序号语义
- `ui-id` 的语义层级是全局定义
- `ui-id` 因为会抛错，实际求值时机放在 init 闭包里

默认推荐短 `ui-id`。

推荐：

- `text`
- `toggle`
- `remove`
- `title`

不推荐：

- `todo-text`
- `window-close-button`
- `item-42-remove`

## 6. scope

name scope 来自挂载边界。

- `comp` 的 root 不自己开 scope
- 外部挂载点赋予这段 UI 当前作用域
- host 这类拥有子实例的宿主，可以声明挂载点来挂别的 entry
- 这个挂载点携带的 `ui-id` 就是 name scope 入口

两条直接规则：

- 需要稳定直达查询的节点，给它自己的 `ui-id`
- 已有父层 scope 时，叶子名字保持短

## 7. list scope

list scope 由动态列表主路径提供。

典型 path：

- `todos/0/text`
- `todos/0/toggle`
- `todos/1/remove`

两条直接规则：

- 列表位置不要重新编码回 `ui-id`
- 非 item 节点不要混进会占索引的位置

## 8. style

样式主路径就是 `ui-id` 自带的 `style`。

- `ui-id` 会生成全局唯一 class
- `style` 默认精确绑定这个 ui 位置
- 动态样式也优先挂在对应 `ui-id` 的 `style` 上

这里的重点是“样式跟着 ui 位置走”，不是再单开一套样式注册系统。

## 9. Entry / Instance

`Entry` 是可实例化定义，`Instance` 是运行时实例。

实例状态分三层：

- `data`：同类 entry 可共享，可序列化
- `session`：实例独立，可序列化
- `runtime`：实例独立，不可序列化，每次临时创建

`ui-id` 不属于这三层实例业务态。

## 10. bridge

bridge 和 DOM 模型必须对齐。

- 生产事件分发依赖节点 `id`
- 公开 GUI 能力保持 path-first 的 `query / trigger`
- 节点 `id` 留在 bridge 内部和白盒测试

测试指导：

- 业务测试优先写高层 `query / trigger`
- 白盒 bridge 测试才直接看节点 `id`

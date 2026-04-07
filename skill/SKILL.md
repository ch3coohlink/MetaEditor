---
name: meta-editor-skill
description: 处理 MetaEditor 仓库代码、语义、边界与相关测试时使用。
---

# MetaEditor Repo Skill

进入本 skill 后，按本仓库当前语义和边界工作，不要自行发明平行模型。

## 工作流

1. 先读 `references/dom.md`。
2. 如果改了 DOM 节点 identity、查询作用域、列表语义或相关 MoonBit 实现，同时检查并更新对应 MoonBit 测试。
3. 如果改了 DOM 所有的 reactive scope 语义，同时检查并更新对应 reactive-scope 测试。
4. 如果改了 bridge 命令、事件路由、query/trigger 目标解析，同时检查并更新对应 browser bridge 测试。
5. 如果改了 host 连续交互或 service/browser 流程，同时检查并更新对应交互测试。
6. 始终只保留一条主路径，不要为了局部方便再发明并行模型。

## 硬规则

- 把 `VNode` 当成真实 DOM 节点看待。`VNode.id` 是唯一节点 identity。
- 只有节点真的消失时才应该移除。移除同时意味着 `Remove(id)`、事件回调、effect、命名信息一起清理。
- 只改样式、属性、文本、listener 时，优先保留稳定根节点，再用 `D(...)` 或局部动态更新。
- 不要把“只改样式/文本/属性”的场景写成外层 `Dyn(fn() { h(...) })`。
- 动态列表若需要 item 级查询、交互或稳定 identity，必须提供 list scope。
- `h_map` / `h_map_dyn` 是动态列表默认首选，但它不是唯一入口。它的语义本质是“带 list scope 的 Dyn”，再加上已挂载节点缓存。
- 如果手写别的动态列表，也必须提供等价的 list scope 语义。不要写出没有 list scope 的动态列表。
- 不需要 indexed query 时，用不带 `ui_id` 的 `h_map` / `h_map_dyn`。
- 需要 indexed query 时，用 `h_map(..., ui_id=Some(...))` 或 `h_map_dyn(..., ui_id=Some(...))` 暴露列表入口。
- `ui-id` 是稳定命名源。不要把列表位置、业务序号、临时 serial 编码进 `ui-id`。
- 名称空间是用来把 `ui-id` 写短的。叶子节点优先用短名，如 `text`、`toggle`、`remove`、`close`。
- 重复子节点名只有放在显式查询作用域里时才安全。作用域包括 `ui-name`、`ui-list`、带 `ui_id` 的 `h_map(...)/h_map_dyn(...)`。离开这些作用域，同名 `ui-id` 会互相覆盖。
- `ui-name` 和 `ui-list` 只改变查询语义，不拥有 reactive 生命周期。`ui-react` 才拥有并负责停止本地 reactive scope。
- 默认直接把适合作为样式锚点的名字写进 `ui-id`，例如 `todo-list`、`entry-name`、`window-title`。
- `ui-id` 会派生 class，因此“为了同一个锚点再补一份同义 class”默认是多余的。
- 不要把“符号转写”当成推荐命名规则。推荐实践里直接写适合样式锚点的 `ui-id`。
- 显式 `class` 只在确实需要额外共享样式语义时再加，不要机械地和 `ui-id` 成对出现。
- 样式优先走 CSS。内联 `style` / `style:*` 只保留窄而动态的部分，如 CSS 变量、颜色、尺寸、位置这类局部切换。
- 生产事件分发依赖节点 `id`。不要在 service bridge 里补 `ui-id` fallback 路由。
- 事件处理主路径本身会 flush reactive DOM patch。service 定时器、bridge 回调、其他事件外部状态更新，改状态后调用现有 `try_flush()`。不要再发明第二套 flush API，也不要拿 `runtime_render()` 替代增量 flush。
- 公开 GUI 能力保持 path-first：`query / trigger` 面向 path。节点 `id` 留在 bridge 内部和白盒测试 helper。
- 不要通过改 listener 属性字符串来扩展事件语义。`.stop`、`.prevent` 一类写法都不可接受。
- 若需要 `preventDefault`、`stopPropagation`、capture、passive 一类能力，必须走显式结构化参数设计。不要自行补临时字符串协议。
- 当前 bridge 里某些事件的局部硬编码，不代表正式事件模型。不要把这些局部补丁写进 skill 当最佳实践。
- 如果改了 `DomCmd` 协议、bridge 命令处理或 bridge 目标解析，同一改动里同步更新 browser bridge 测试。
- 列表查询的稳定合同优先是 `<list-ui-id>/0/<inner-ui-id>`。不要把 `<list-ui-id>` 或 `<list-ui-id>/0` 当主要业务合同。

## 样式规则

- 结构性样式优先放在模块级 `css(scope, S(...))`。`style:*` 只留给窄动态开关。
- `css(...)` 是模块级样式表定义，返回 `StyleSheet`。不要把它当普通表达式塞进 render 路径。
- 不要在组件 render、`Dyn(...)`、`h_map_dyn(...)` item render、或任何可能重跑的 DOM 更新路径里直接调用裸 `css(...)`。
- 如果父层 rerender 后子 DOM 被复用，但子样式表消失了，说明样式定义路径错了。应修定义路径，不要补 wrapper 绕过去。
- 一个样式块尽量只保留一个模块级 `StyleSheet`，复用它，不要在 render 里重复定义。
- `StyleSheet::reset(text)` 只用于“这个模块级样式表文本本身真的要换”。不要把它当局部动态 style 的替代品。
- 默认模式：保留一个模块级 `*_css()`，定义一个模块级 `StyleSheet`，把重复布局和视觉规则并进 CSS，只把真正运行时变化的值留在 `style:*`。

## 最佳实践

动态列表默认写法：

```moonbit
fn todo_item(todo: Todo, bind: ActionBind) -> Child {
  h("div", [
    ("ui-id", S("item")),
    ("ui-name", S("true"))
  ], [
    h("span", [("ui-id", S("text"))], [Str(todo.text)]),
    h("button", [
      ("ui-id", S("toggle")),
      ("onclick", bind("toggle", [ActionArg::Int(todo.id)]))
    ], [Str("Toggle")]),
    h("button", [
      ("ui-id", S("remove")),
      ("onclick", bind("remove", [ActionArg::Int(todo.id)]))
    ], [Str("Remove")])
  ])
}

h_map_dyn(fn() {
  todos.get().map(todo => (todo, todo.id))
}, (todo, _i) => todo_item(todo, bind), ui_id=Some("todos"))
```

对应查询：

- `todos/0/text`
- `todos/0/toggle`
- `todos/0/remove`

这里的重点：

- 列表入口叫 `todos`
- item 内部名字尽量短
- 不把父层前缀反复编码进每个叶子 `ui-id`
- 不自己再造一套业务侧查询 id

非 `h_map` 但语义上有 list scope 的静态列表示意：

```moonbit
h("div", [
  ("ui-id", S("todos")),
  ("ui-list", S("true"))
], [
  item_view(todo_a, bind),
  item_view(todo_b, bind),
  item_view(todo_c, bind)
])
```

这类写法适合手写静态列表或混合结构。只要开始动态增删改排，默认优先收回 `h_map` / `h_map_dyn`。

样式锚点默认写法：

```moonbit
let todo_list_style: StyleSheet = css("todo-list", S(todo_list_css()))

fn todo_view(...) -> Child {
  h("div", [("ui-id", S("todo-list"))], [
    ...
  ])
}
```

这里的重点：

- 默认直接拿 `ui-id` 当稳定样式锚点
- 不要顺手再补一个同义 `class`
- 只有真的需要额外共享样式语义时再显式加 `class`

## 当前边界

- 普通 `Dyn` 仍然会在返回全新子结构时重建新节点。
- `h_map / h_map_dyn` 已经提供稳定列表 item identity。带 `ui_id` 的形式额外暴露 indexed query 入口。
- `h_map` item root 即使返回 `Dyn(...)`，当前也仍按稳定 fragment 处理。
- `ui-react` 会创建本地 reactive scope，并在节点移除时停止。
- `ui-name` / `ui-list` 要求宿主节点拥有 `ui-id`，它们只改变查询语义。
- `css(...)` 目前是模块级样式表定义路径，不是 render 期 scoped cleanup API。
- 公开 GUI 能力应保持 path-first 的 `query / trigger`。节点 `id` 仍是内部细节。
- 业务测试目标应站在高层 `query / trigger` 语义上。节点 `id` 只给 bridge 白盒 helper。
- 事件能力的结构化参数设计目前还没正式落成。在它落成前，不要擅自扩字符串 listener 协议。



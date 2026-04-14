# MetaEditor DOM Query 示例

这份文档只给当前推荐写法。

每节只回答三件事：

- 代码怎么写
- 会暴露哪些 path
- 这段写法表达的语义是什么

## 1. `ui-id` 给最小稳定名字

推荐：

```moonbit
h("button", [Id(ui("save"))], [Str("Save")])
```

可用 path：

- `save`

关键点：

- `ui-id` 是稳定名字
- `ui-id` 同时也是默认样式锚点
- `ui-id` 推荐写短

## 2. 挂载点提供 name scope

推荐：

```moonbit
let panel = ui("panel")
let save = ui("save")

h("div", [Id(panel)], [
  h("button", [Id(save)], [Str("Save")])
])
```

假设外部把 `panel` 当挂载点使用，可用 path：

- `panel/save`

关键点：

- name scope 来自挂载边界
- `comp` 的 root 不自己声明 scope
- 叶子名字保持短

中间多包一层 DOM，不会强制 path 多走一层：

```moonbit
h("div", [Id(panel)], [
  h("div", [], [
    h("button", [Id(save)], [Str("Save")])
  ])
])
```

仍然看作：

- `panel/save`

## 3. 动态列表给 list scope

推荐：

```moonbit
let text = ui("text")
let toggle = ui("toggle")

h_map(
  todos,
  (todo, _) => h("div", [], [
    h("span", [Id(text)], [Str(todo.text)]),
    h("button", [Id(toggle)], [Str("Toggle")])
  ]),
  ui_id=Some("todos"),
)
```

可用 path：

- `todos/0/text`
- `todos/0/toggle`
- `todos/1/text`

关键点：

- list scope 由动态列表主路径提供
- 索引是 path 的第二段
- item 内继续用短名字

## 4. `h_map / h_map_dyn`

推荐：

```moonbit
h_map_dyn(
  fn() { todos.get().map(todo => (todo, todo.id)) },
  (todo, _) => h("div", [], [
    h("span", [Id(text)], [Str(todo.text)]),
    h("button", [Id(toggle)], [Str("Toggle")])
  ]),
  ui_id=Some("todos"),
)
```

可用 path：

- `todos/0/text`
- `todos/0/toggle`

关键点：

- `h_map / h_map_dyn` 同时保 item identity 和 list scope
- 重点是列表语义，不是额外固定 wrapper

## 5. path 跟着当前可见结构走

推荐：

```moonbit
let panel = ui("panel")
let label = ui("label")
let toggle = ui("toggle")

h("div", [Id(panel)], [
  Dyn(None, () => {
    if expanded.get() {
      Arr([
        h("span", [Id(label)], [Str("Open")]),
        h("button", [Id(toggle)], [Str("Close")]),
      ])
    } else {
      h("button", [Id(toggle)], [Str("Open")])
    }
  })
])
```

可用 path：

- 一直有 `panel/toggle`
- 展开时还有 `panel/label`

关键点：

- query 命中当前还能到达的名字
- query 不缓存历史旧节点

## 6. host 挂载子实例

推荐：

```moonbit
let entries = ui("entries")
let windows = ui("windows")

comp((_, _) => h("div", [], [
  h("div", [Id(entries)], [/* host 自己的内容 */]),
  h("div", [Id(windows)], [/* 子实例挂到这里 */]),
]))
```

这类 `windows` 挂载点表达的是：

- 它是一个稳定 `ui-id`
- 它是一个 name scope 入口
- 子实例的 root scope 由这个挂载点赋予

关键点：

- host 这种拥有子实例的宿主，用挂载点组织 query
- 子实例自己的 root 不再手工声明一层 root scope

## 7. style 跟着 `ui-id`

推荐：

```moonbit
let title = ui("title", style=". { color: red; }")

h("div", [Id(title)], [Str("Hello")])
```

关键点：

- `style` 绑定在 `ui-id` 上
- `ui-id` 会生成全局唯一 class
- 样式天然落到这个 ui 位置

## 8. 不推荐的 path 形状

不推荐：

- `toolbar/save`
- `todo:1:text`
- `window:3:close`
- 把列表位置重新编码进 `ui-id`

推荐：

- `save`
- `panel/save`
- `todos/0/text`
- `windows/0/title`

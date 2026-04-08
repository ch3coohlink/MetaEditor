# MetaEditor DOM Query 示例

这份文档不用来讲一大套理论，只给推荐写法。

每节都只回答三件事：

- 代码该怎么写
- 会暴露哪些 path
- 哪些写法不要用

## 1. `ui-id` 先管最小直达路径

推荐：

```moonbit
h("button", [("ui-id", S("save"))], [Str("Save")])
```

可用 path：

- `save`

关键点：

- `ui-id` 是 query 的稳定名字
- 需要稳定直达查询的节点，就给自己的 `ui-id`
- 默认推荐短 `ui-id`
- `ui-id` 同时也是默认样式锚点

不要这样写：

```moonbit
h("button", [("ui-id", S("toolbar/save"))], [Str("Save")])
h("button", [("ui-id", S("toolbar:save"))], [Str("Save")])
h("button", [("ui-id", S("save:1"))], [Str("Save")])
```

原因：

- `/` 是 path 分隔符，不允许出现在 `ui-id` 里
- `:` 也不要出现在 `ui-id` 里。不要拿它编码层级、列表、业务编号或临时语义
- `ui-id` 只放稳定名字，不放路径结构和业务序号

## 2. 需要局部名字时，用 `ui-id:scope`

推荐：

```moonbit
h("div", [
  ("ui-id:scope", S("panel"))
], [
  h("button", [("ui-id", S("save"))], [Str("Save")]),
  h("button", [("ui-id", S("close"))], [Str("Close")])
])
```

可用 path：

- `panel/save`
- `panel/close`

这段代码表达的是：

```text
panel/save
```

先进入 `panel` 这个名称空间，再找里面叫 `save` 的名字。

不是这样：

```text
panel -> div 的第一个 button
```

关键点：

- `ui-id:scope` 直接声明一个带名称空间语义的稳定名字
- 叶子节点名字可以写短
- 父层语义已经在 `panel` 这一段里，不要再写进子节点

不要这样写：

```moonbit
h("div", [
  ("ui-id:scope", S("panel"))
], [
  h("button", [("ui-id", S("panel-save"))], [Str("Save")]),
  h("button", [("ui-id", S("panel-close"))], [Str("Close")])
])
```

原因：

- 已经有局部名称空间时，继续把父层前缀写进叶子，只会让 path 变长

再看一个对比例子：

```moonbit
h("div", [
  ("ui-id:scope", S("panel"))
], [
  h("div", [("ui-id", S("wrapper"))], [
    h("button", [("ui-id", S("save"))], [Str("Save")])
  ])
])
```

这里仍然推荐用：

- `panel/save`

中间这个 `wrapper` 有自己的 `ui-id`，但这里不需要把它写进 path。

 即使中间多包了一层 `div`，path 语义也不该被迫改成“沿 DOM 多走一层”。

## 3. 静态重复结构，用 `ui-id:list`

推荐：

```moonbit
h("div", [
  ("ui-id:list", S("todos"))
], [
  h("div", [], [
    h("span", [("ui-id", S("text"))], [Str("A")]),
    h("button", [("ui-id", S("toggle"))], [Str("Toggle")])
  ]),
  h("div", [], [
    h("span", [("ui-id", S("text"))], [Str("B")]),
    h("button", [("ui-id", S("toggle"))], [Str("Toggle")])
  ])
])
```

可用 path：

- `todos/0/text`
- `todos/0/toggle`
- `todos/1/text`
- `todos/1/toggle`

再看一个例子：

```moonbit
h("div", [
  ("ui-id:list", S("todos"))
], [
  h("div", [], [
    h("div", [], [
      h("button", [("ui-id", S("toggle"))], [Str("Toggle")])
    ])
  ])
])
```

这里仍然应该查：

- `todos/0/toggle`

不是：

- `todos/0/0/toggle`

关键点：

- `ui-id:list` 直接声明一个带列表作用域语义的稳定名字
- 下一段写的是索引
- 进入索引以后，再按 item 内的局部名字继续走
- 中间多包几层 DOM，不应该逼着 path 跟着长

不要这样写：

```moonbit
h("div", [
  ("ui-id:list", S("todos"))
], [
  h("div", [("ui-id", S("todo-0"))], [...]),
  h("div", [("ui-id", S("todo-1"))], [...])
])
```

原因：

- 列表索引已经由 list scope 提供
- 不要再把位置编码回 `ui-id`

## 4. 动态列表默认走 `h_map / h_map_dyn`

推荐：

```moonbit
fn todo_item(todo: Todo, bind: ActionBind) -> Child {
  h("div", [
    ("ui-id:scope", S("item"))
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

可用 path：

- `todos/0/text`
- `todos/0/toggle`
- `todos/0/remove`
- `todos/1/text`

关键点：

- 动态列表要的不是“把一串节点吐出来”
- 动态列表要同时保住 item identity 和 item query scope
- `h_map / h_map_dyn` 就是这条主路径

如果这个 list 还需要稳定 CSS 锚点，或者需要有一个真实 DOM 宿主，就直接给 `h_map / h_map_dyn`
传 `ui_id`。

推荐：

```moonbit
h_map_dyn(fn() {
  todos.get().map(todo => (todo, todo.id))
}, (todo, _i) => todo_item(todo, bind), ui_id=Some("todos"))
```

这时会自动创建一个同名 wrapper 节点。这个节点同时是：

- `todos:list` 的 list 域入口
- CSS 的 `.todos`
- 真实 DOM 宿主

需要时可以这样写：

```moonbit
h_map_dyn(fn() {
  todos.get().map(todo => (todo, todo.id))
}, (todo, _i) => todo_item(todo, bind), ui_id=Some("todos"), wrap=false)
```

或者：

```moonbit
h_map_dyn(fn() {
  todos.get().map(todo => (todo, todo.id))
}, (todo, _i) => todo_item(todo, bind), ui_id=Some("todos"), tag="ul")
```

不要这样写：

```moonbit
h("div", [("ui-id", S("todos"))], [
  h_map_dyn(fn() {
    todos.get().map(todo => (todo, todo.id))
  }, (todo, _i) => todo_item(todo, bind), ui_id=Some("todos"))
])
```

原因：

- 这会把同一个 list 入口拆成两层同名概念
- 外层一层是业务层手包 DOM
- 里面一层才是真正的 list 域
- query、CSS、DOM 宿主会重新分叉

不要这样写：

```moonbit
Dyn(fn() {
  Arr(todos.get().map(todo =>
    h("div", [("ui-id", S("todo:\{todo.id}"))], [...])
  ))
})
```

原因：

- 这会把动态列表写成整段重建
- 还把业务 id 编进了 `ui-id`
- query、重排、节点复用都会一起变脆

## 5. `react:scope` 不负责 query 命名

推荐：

```moonbit
h("div", [
  ("ui-id:scope", S("panel")),
  ("react:scope", S("true"))
], [
  child_view()
])
```

可用 path：

- `panel/...`

关键点：

- `ui-id:scope` 负责局部 query 名字
- `react:scope` 负责这段局部 UI 的 reactive scope
- 这两个属性可以挂在同一个宿主节点上，但不是同一件事

不要这样理解：

- `react:scope` 不是 query scope
- `ui-id:scope` 也不拥有 reactive 生命周期

## 6. 动态变化以后，path 应该继续命中当前可见节点

推荐：

```moonbit
h("div", [
  ("ui-id:scope", S("panel"))
], [
  Dyn(fn() {
    if expanded.get() {
      Arr([
        h("span", [("ui-id", S("label"))], [Str("Open")]),
        h("button", [("ui-id", S("toggle"))], [Str("Close")])
      ])
    } else {
      h("button", [("ui-id", S("toggle"))], [Str("Open")])
    }
  })
])
```

可用 path：

- `panel/toggle`
- 展开后再加上 `panel/label`

关键点：

- query 应该跟着当前结构走
- 它找的是当前作用域里当前还能到达的名字
- 不要把 query 理解成“第一次找到某节点后永久缓存那个节点”

## 7. 不推荐的 path

- `todo:1:text`
- `window:3:close`
- `toolbar/save`
- `<list-ui-id>`
- `<list-ui-id>/0`

原因：

- 前三种把路径结构、列表语义、业务编号硬塞进 `ui-id`
- 后两种过度依赖当前 DOM 形状，语义太弱

推荐把path落在这种形式上：

- `panel/save`
- `todos/0/toggle`
- `root/windows/0/titlebar/close`

也就是：

- 作用域交给 path
- 稳定名字交给 `ui-id`
- 列表位置交给 list scope

## 8. `ui-id` 短，同时 CSS 选择器跟作用域写

推荐：

```moonbit
h("div", [
  ("ui-id:scope", S("todo"))
], [
  h("span", [("ui-id", S("text"))], [Str("A")]),
  h("button", [("ui-id", S("toggle"))], [Str("Toggle")])
])
```

推荐 path：

- `todo/text`
- `todo/toggle`

推荐 CSS：

```css
.todo .text { ... }
.todo .toggle { ... }
```

不要这样写：

```css
.text { ... }
.toggle { ... }
```

再看一个更完整的例子：

```moonbit
h("div", [
  ("ui-id:scope", S("editor"))
], [
  h("div", [
    ("ui-id:scope", S("toolbar"))
  ], [
    h("button", [("ui-id", S("save"))], [Str("Save")])
  ]),
  h("div", [
    ("ui-id:scope", S("dialog"))
  ], [
    h("button", [("ui-id", S("save"))], [Str("Save")])
  ])
])
```

推荐 path：

- `editor/toolbar/save`
- `editor/dialog/save`

推荐 CSS：

```css
.editor .toolbar .save { ... }
.editor .dialog .save { ... }
```

不要直接写：

```css
.save { ... }
```

关键点：

- `ui-id` 默认写短名
- 叶子 `ui-id` 越短，越依赖外层 scope 才能表达完整语义
- `ui-id` 会派生 class，所以 CSS 选择器也要跟着作用域写成层级组合
- 直接写叶子 class 选择器，范围通常过大
- CSS 选择器默认按 `ui-id` 域写，不按 DOM 包裹层和标签名机械抄长路径

再看一个 list 例子：

```css
.windows .close { ... }
.entries .icon { ... }
.topbar-windows .window { ... }
```

不要这样写：

```css
div.window .titlebar .close { ... }
.workspace .windows .window .titlebar .close { ... }
button.window { ... }
```

原因：

- 这些写法把 DOM 包裹层和标签实现细节带进了选择器
- 当前更稳定的语义是 `ui-id` 域，不是那一串 DOM 层级

## 9. 写 query 相关代码时，先对照这张表

| 需求 | 推荐能力 |
| --- | --- |
| 一个节点要被稳定直达查询 | `ui-id` |
| 一组局部叶子名字想写短 | `ui-id:scope` |
| 一组重复项要按索引查询 | `ui-id:list` |
| 一组动态项要保住 identity 和 query scope | `h_map / h_map_dyn` |
| 一段局部 UI 要独立 reactive 生命周期 | `react:scope` |

如果一个需求同时碰到 query 和生命周期，通常是：

- `ui-id:scope` 或 `ui-id:list`
- 再加 `react:scope`

不要拿其中一个去替代另一个。

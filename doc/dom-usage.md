# dom.mbt 目标用法

这份文档只写当前 `src/dom.mbt` 的使用方式，不讲实现细节。

## 0. 前置定义

```moonbit
let count = cel(0)
let items = cel(["A", "B"])
```

## 1. 最小组件

```moonbit
let Counter = comp(fn(attrs, children) {
  h("div", attrs, [
    h("button", [("click", E(fn() {
      count.set(count.peek() + 1)
    }))], [Str("inc")]),
    h("span", [], [Dyn(fn() { Int(count.get()) })]),
  ])
})
```

目标效果：

- `comp()` 定义一个可复用组件
- `h()` 负责拼元素、属性和子节点
- `Dyn()` 负责把响应式值挂进子树

## 2. 字符串和普通子节点

```moonbit
let view = h("div", [("class", S("panel"))], [
  Str("hello"),
  Int(1),
  Counter,
])
```

目标效果：

- `S()` 是静态属性
- `Str()` 和 `Int()` 会变成文本节点
- 子节点里可以直接放组件结果

## 3. 动态属性

```moonbit
let view = h("input", [
  ("value", D(fn() { count.peek().to_string() })),
  ("input", EK(fn(ev) {
    if ev.prevent {
      count.set(count.peek() + 1)
    }
  })),
], [])
```

目标效果：

- `D()` 绑定动态属性
- 依赖变化后自动更新属性
- `EK()` 能拿到事件数据

## 4. 回调

```moonbit
let save_btn = h("button", [
  ("click", E(fn() {
    println("save")
  })),
], [Str("save")])

let action_btn = h("button", [
  ("click", reg_action("save", fn() {
    println("save")
  })),
], [Str("save")])
```

目标效果：

- `E()` 直接挂普通事件回调
- `reg_action()` 先注册回调，再把 action id 发给宿主
- 触发回调后会自动走一次 `flush()`

## 5. 列表

```moonbit
let list = h("ul", [], [
  h_map(items.get(), fn(item, index) {
    h("li", [], [
      Str(item),
      Int(index()),
    ])
  })
])
```

目标效果：

- `h_map()` 用来渲染稳定列表
- `index()` 是当前项的下标读取器
- 列表项复用由 `h_map` 自己处理

## 6. 动态列表

```moonbit
let list = h("ul", [], [
  h_map_dyn(fn() {
    items.get().map(fn(x, i) { (x, i) })
  }, fn(item, index) {
    h("li", [], [
      Str(item),
      Int(index()),
    ])
  })
])
```

目标效果：

- `h_map_dyn()` 适合列表来源本身就是动态的情况
- 只要外部数组变了，列表就能跟着重排

## 7. 宿主命令

```moonbit
let node = h("div", [], [Str("x")])

focus_node(1)
blur_node(1)
scroll_into_view(1)
remove(node)
```

目标效果：

- `focus_node()`、`blur_node()`、`scroll_into_view()` 直接发宿主命令
- `remove()` 会发删除命令并清理子树回调

## 8. 桥接

```moonbit
init_bridge(fn(cmds) {
  send_to_host(cmds)
})
```

目标效果：

- `init_bridge()` 在每次 flush 后收集命令
- 有命令时统一交给宿主
- 前端只管发命令，不直接操作宿主 DOM

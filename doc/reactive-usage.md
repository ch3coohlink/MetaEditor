# reactive 目标用法

这份文档只写当前 `src/reactive.mbt` 的使用方式，不讲实现细节。

## 0. 前置定义

```moonbit
let count = cel(0)
let title = cel("MetaEditor")
let items = cel(["A", "B"])
```

## 1. 读取

```moonbit
let n = count.peek()
let s = title.get()
```

目标效果：

- `peek()` 只是看当前值，不订阅
- `get()` 会订阅当前值，后续变化会触发依赖

## 2. 写入

```moonbit
count.set(1)
title.set("IntentDoc")
```

目标效果：

- `set()` 直接替换当前值
- 替换后会通知依赖者

## 3. 原地修改

```moonbit
items.mutate(xs => {
  xs.push("C")
  xs.remove(0)
})
```

目标效果：

- `mutate()` 先拿到当前值，再在原值上直接改
- 改完后统一通知一次
- 这是容器类状态的主写法

## 4. 派生值

```moonbit
let double_count = computed(fn() {
  count.get() * 2
})
```

目标效果：

- `computed()` 自动跟踪依赖
- 依赖变了以后，派生值自动重算
- 派生值本身还是一个 `Cel`

## 5. 监听变化

```moonbit
let stop_count = watch(count, fn(old, next) {
  println("\{old} -> \{next}")
})

let stop_title = watch_raw(title, fn(v) {
  println(v)
})
```

目标效果：

- `watch()` 只在值真的变了时回调
- 回调能拿到旧值和新值
- `watch_raw()` 每次依赖触发都回调

## 6. 作用域

```moonbit
let stop = scope(fn() {
  let _ = effect(fn() {
    println(count.get())
  })
  count.set(2)
})

stop()
```

目标效果：

- `scope()` 把一组副作用收进一个生命周期
- `effect()` 只在 scope 里创建
- `stop()` 后，scope 里挂的 effect 和清理逻辑一起失效

## 7. 组合使用

```moonbit
let stop = scope(fn() {
  let doubled = computed(fn() { count.get() * 2 })
  let _ = effect(fn() {
    println(doubled.get())
  })
  count.set(3)
  items.mutate(xs => { xs.push("D") })
})
```

目标效果：

- 标量状态用 `set()`
- 容器状态用 `mutate()`
- 派生值和监听都围绕同一条响应式链工作


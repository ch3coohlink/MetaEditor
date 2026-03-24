# history 目标用法

这份文档只写当前 `src/op.mbt` 的使用方式，不讲实现细节。

## 0. 前置定义

```moonbit
priv struct Prefs {
  mut name: String
  mut age: Int
}

let store = new_store({
  name: "Ada",
  age: 18,
})
```

## 1. 读取当前状态

```moonbit
let prefs = store.read()
let peeked = store.peek()
let rev = store.version()
let rev2 = store.peek_version()
```

目标效果：

- `read()` 会走响应式读取
- `peek()` 只看当前值，不订阅
- `version()` 会订阅版本
- `peek_version()` 只看当前版本

## 2. 看快照

```moonbit
let snap = store.snapshot()
let v = snap.version
let value = snap.value
```

目标效果：

- `snapshot()` 一次拿到当前版本和值
- 快照可以直接拿去做保存、回放或调试

## 3. 本地修改

```moonbit
let next = apply_local(store, "rename", fn(p) {
  { name: "Bea", age: p.age }
})
```

目标效果：

- `apply_local()` 在当前值上算出新值
- 如果结果没变，就不推进版本
- 如果结果变了，就压入 undo 栈并清空 redo 栈
- 返回的是修改后的快照

## 4. 直接补丁

```moonbit
let ok = apply_patch(store, patch("replace-name", 0, {
  name: "Ada",
  age: 18,
}, {
  name: "Cora",
  age: 18,
}))
```

目标效果：

- `patch()` 先把标签、版本、期望值和新值打包起来
- `apply_patch()` 用 `version + expect` 做 CAS 校验
- 校验失败就返回 `false`
- 校验通过就应用补丁并推进版本

## 5. 撤销和重做

```moonbit
let a = undo(store)
let b = redo(store)
```

目标效果：

- `undo()` 回到上一个快照
- `redo()` 回到下一个快照
- 撤销后可以再重做
- 新的本地修改会清空 redo 栈

## 6. 连续编辑

```moonbit
let _ = apply_local(store, "inc-age", fn(p) {
  { name: p.name, age: p.age + 1 }
})

let _ = apply_local(store, "inc-age", fn(p) {
  { name: p.name, age: p.age + 1 }
})

let _ = undo(store)
let _ = redo(store)
```

目标效果：

- 连续本地修改会连续推进版本
- 每次修改都会留下可撤销快照
- `undo()` / `redo()` 按快照顺序走


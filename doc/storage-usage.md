# storage.mbt 目标用法

这份文档只写当前 `src/storage.mbt` 的使用方式，不讲实现细节。

## 0. 前置定义

```moonbit
let kv = open_kv()
```

## 1. 最小值绑定

```moonbit
let prefs = cel({ name: "Ada", age: 18 })
let stop = bind_with_kv(kv)("prefs", prefs) catch { _ => abort("bind") }
```

目标效果：

- `bind_with_kv()` 适合普通值树
- `prefs` 初始化时会从 `kv` 读取已有值，或把当前值写进去
- 后续 `prefs` 变化后会自动写回同一个 key

## 2. 停止同步

```moonbit
stop()
```

目标效果：

- `stop()` 只停止同步
- 后续改动不再继续写回
- 已有 kv 快照保留，不会因为 stop 被删除

## 3. 节点级对象图绑定

```moonbit
let child = obj([("name", PersistValue::Str("Ada"))])
let root = cel(obj([("left", child)]))
let stop = bind_refs_with_kv(kv)("refs", root) catch { _ => abort("bind") }
```

目标效果：

- `bind_refs_with_kv()` 适合对象图和数组图
- root 固定写在 `prefix/0`
- 子对象和子数组按节点拆开保存，父节点里只写 `Ref(id)`

## 4. 共享子节点和自引用

```moonbit
let shared = obj([("name", PersistValue::Str("Ada"))])
let root = cel(obj([
  ("left", shared),
  ("right", shared),
]))
let stop = bind_refs_with_kv(kv)("refs", root) catch { _ => abort("bind") }
```

目标效果：

- 同一个运行时对象会复用同一个节点 id
- shared child 写盘时不会被重复拆成多个节点
- 自引用和环会按 `Ref(id)` 保留下来

## 5. 直接改嵌套节点

```moonbit
match root.peek() {
  Obj(m) => {
    match m.get("left") {
      Some(Obj(c)) => c.set("name", PersistValue::Str("Bea"))
      _ => ()
    }
  }
  _ => ()
}
flush() catch { _ => abort("flush") }
```

目标效果：

- 直接改嵌套对象后，只要这一轮最后 `flush()`，对应节点就会写回
- 不需要重新 `set` 整个 root

## 6. scoped 绑定复用

```moonbit
let bind = bind_refs_scoped_with_kv(kv)

let stop_scope = scope(fn() raise {
  bind("refs", root)
  ()
}) catch { _ => abort("scope") }
```

目标效果：

- 同一个 `key + source` 会复用一条底层节点级绑定
- 最后一个作用域清掉以后，这条绑定才真正停止
- scoped stop 和普通 stop 一样，只停止同步，不删 kv

## 7. 显式 gc

```moonbit
gc_refs(kv, "refs")
```

目标效果：

- `gc_refs()` 会从 `refs/0` 出发做可达性清理
- 只清理当前 prefix 下不可达的节点键
- shared child 和 self-cycle 只要仍然可达就会被保留

## 8. 适用边界

```moonbit
let value_bind = bind_with_kv(kv)
let graph_bind = bind_refs_with_kv(kv)
```

目标效果：

- `bind_with_kv()` 用于普通值树
- `bind_refs_with_kv()` / `bind_refs_scoped_with_kv()` 用于需要节点拆存、共享子对象和自引用的对象图
- `storage` 不负责自动删盘，stop 之后的 orphan 清理由显式 `gc_refs()` 处理

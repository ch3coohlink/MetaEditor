## 0. 前置定义

```
let kv = open_kv()

priv struct Prefs {
  mut name: String
  mut age: Int
}

priv struct Doc {
  mut title: String
  mut tags: Array[String]
}

let prefs_schema = schema(
  "prefs",
  2,
  fn(p) { { "name": p.name, "age": p.age } },
  fn(raw) { { name: raw["name"], age: raw["age"] } },
)

let doc_schema = schema(
  "doc",
  1,
  fn(d) { { "title": d.title, "tags": d.tags } },
  fn(raw) { { title: raw["title"], tags: raw["tags"] } },
)

let prefs_cell = cell({ name: "Ada", age: 18 })
let doc_cell = cell({ title: "Notes", tags: ["moonbit"] })
```

## 1. 顶层绑定

```
let stop = bind("prefs", prefs_schema, prefs_cell, kv)
```

```
let stop = bind("doc", doc_schema, doc_cell, kv)
```

绑定之后不再手动调用 `save()` / `load()`。
运行时状态改动后，存储层自动异步同步。

## 2. 读取旧数据

```
let old_prefs_cell = cell({
  title: "Bea",
})

let stop = bind("prefs", prefs_schema, old_prefs_cell, kv)
```

目标效果：

- `title` 自动迁到 `name`
- 缺失的 `age` 自动补默认值
- 没用的旧字段自动丢弃

## 3. 原地修改

```
prefs_cell.mutate(p => {
  p.name = "Cora"
  p.age = 21
})
```

目标效果：

- 这次修改不会立刻写盘
- 同一轮内多次修改会被 batch 到一起
- batch 结束后自动同步一次

## 4. 细粒度字段

```
let prefs_cell = cell({
  title: cell("Bea"),
  age: cell(18),
})

let stop = bind("prefs", prefs_schema, prefs_cell, kv)
```

目标效果：

- `title` 自己可以单独变
- `age` 自己可以单独变
- storage 只在 batch 结束后同步当前整体结果

## 5. 数组

```
let doc_cell = cell({
  tags: cell(["moonbit"]),
  title: cell("Notes"),
})

let stop = bind("doc", doc_schema, doc_cell, kv)

doc_cell.mutate(d => {
  d.tags.push("storage")
})
```

目标效果：

- `Array[Pref]` 这一类数据可以直接绑定
- 数组元素按元素 schema 递归同步
- 只要当前值变了，最终都会进入同一条同步路径

## 6. 解绑

```
stop()
```

目标效果：

- 停止自动同步
- 不再监听这份状态
- 后续改动不再写回存储

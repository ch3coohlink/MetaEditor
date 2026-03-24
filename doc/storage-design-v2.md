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

let prefs_schema = schema("prefs", 2, {
  name: string(default: "anon")
  age: int(default: 18)
}, [
  migrate(1, fn(old) {
    old.rename("title", "name")
  })
])

let doc_schema = schema("doc", 1, {
  title: string(default: "")
  tags: array(string(default: ""))
}, [])
```

## 1. 顶层绑定

```
let prefs = cell({
  name: "Ada",
  age: 18,
})

let stop = bind("prefs", prefs_schema, prefs, kv)
```

```
let doc = cell({
  title: "Notes",
  tags: ["moonbit"],
})

let stop = bind("doc", doc_schema, doc, kv)
```

绑定之后不再手动调用 `save()` / `load()`。
运行时状态改动后，存储层自动异步同步。

## 2. 读取旧数据

```
let old_prefs = cell({
  title: "Bea",
})

let stop = bind("prefs", prefs_schema, old_prefs, kv)
```

目标效果：

- `title` 自动迁到 `name`
- 缺失的 `age` 自动补默认值
- 没用的旧字段自动丢弃

## 3. 原地修改

```
prefs.mutate(p => {
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
let prefs = cell({
  name: cell("Bea"),
  age: cell(18),
})

let stop = bind("prefs", prefs_schema, prefs, kv)
```

```
prefs.name.set("Cora")
prefs.age.mutate(age => { age + 1 })
```

目标效果：

- `name` 自己可以单独变
- `age` 自己可以单独变
- storage 只在 batch 结束后同步当前整体结果

## 5. 数组

```
let doc = cell({
  title: "Notes",
  tags: ["moonbit"],
})

let stop = bind("doc", doc_schema, doc, kv)

doc.mutate(d => {
  d.tags.push("storage")
})
```

目标效果：

- `Array[Prefs]` 这一类数据可以直接绑定
- 数组元素按元素 schema 递归同步
- 只要当前值变了，最终都会进入同一条同步路径

## 6. 数组里的对象

```
let group_schema = schema("group", 1, {
  members: array(prefs_schema)
}, [])

let group = cell({
  members: [
    { name: "Ada", age: 18 },
    { name: "Bea", age: 20 },
  ],
})

let stop = bind("group", group_schema, group, kv)
```

```
group.mutate(g => {
  g.members[0].age = 19
  g.members.push({ name: "Cora", age: 21 })
})
```

目标效果：

- `Array[Prefs]` 直接按 `prefs_schema` 递归处理
- 元素变更和数组结构变更都能进入同一条同步路径

## 7. 解绑

```
stop()
```

目标效果：

- 停止自动同步
- 不再监听这份状态
- 后续改动不再写回存储

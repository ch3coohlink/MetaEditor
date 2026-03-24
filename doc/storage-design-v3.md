## 0. 前置定义

```
let kv = open_kv()
let bind = bind_with_kv(kv)

priv struct Prefs {
  mut name: String
  mut age: Int
}

priv struct Doc {
  mut title: String
  mut tags: Array[String]
}

let prefs_schema = schema("prefs", [
  field(10, "name", string(anon)),
  field(20, "age", int(18)),
])

let doc_schema = schema("doc", [
  field(10, "title", string("")),
  field(20, "tags", array(string(""))),
])

let prefs = ref({
  name: "Ada",
  age: 18,
})

let doc = ref({
  title: "Notes",
  tags: ["moonbit"],
})
```

## 1. 顶层绑定

```
let stop = bind("prefs", prefs_schema, prefs)
```

```
let stop = bind("doc", doc_schema, doc)
```

绑定之后不再手动调用 `save()` / `load()`。
状态改动后，存储层自动异步同步。

## 2. 读取旧数据

```
let old_prefs = ref({
  title: "Bea",
})

let stop = bind("prefs", prefs_schema, old_prefs)
```

目标效果：

- `title` 的旧读名还能读进来
- 当前写回只使用 `name` 这个存储标签
- 缺失的 `age` 自动补默认值
- 没有任何对应关系的旧字段自动丢弃

## 3. 重命名

```
let prefs_schema = schema("prefs", [
  field(10, "name", string(anon)),
  field(20, "age", int(18)),
])
```

目标效果：

- 旧数据里读的是 `title`
- 新版本里读的是 `name`
- 落盘时还是稳定写 `store tag = 1`
- 重命名不需要显式 migration function

## 4. 原地修改

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

## 5. 细粒度引用

```
let prefs = ref({
  name: ref("Bea"),
  age: ref(18),
})

let stop = bind("prefs", prefs_schema, prefs)
```

```
prefs.name.set("Cora")
prefs.age.mutate(age => { age + 1 })
```

目标效果：

- `name` 自己可以单独变
- `age` 自己可以单独变
- storage 只在 batch 结束后同步当前整体结果
- 绑定的是引用图，不是一次性拷贝的数据

## 6. 数组

```
let doc = ref({
  title: "Notes",
  tags: ["moonbit"],
})

let stop = bind("doc", doc_schema, doc)

doc.mutate(d => {
  d.tags.push("storage")
})
```

目标效果：

- `Array[Prefs]` 这一类数据可以直接绑定
- 数组元素按元素 schema 递归同步
- 元素变更和数组结构变更都能走同一条同步路径

## 7. 数组里的对象

```
let group_schema = schema("group", [
  field(10, "members", array(prefs_schema)),
])

let group = ref({
  members: [
    { name: "Ada", age: 18 },
    { name: "Bea", age: 20 },
  ],
})

let stop = bind("group", group_schema, group)
```

```
group.mutate(g => {
  g.members[0].age = 19
  g.members.push({ name: "Cora", age: 21 })
})
```

目标效果：

- 数组元素按 `prefs_schema` 递归处理
- 单个元素引用可以单独更新
- 数组结构变化也能自动同步

## 8. 解绑

```
stop()
```

目标效果：

- 停止自动同步
- 不再监听这份状态
- 后续改动不再写回存储

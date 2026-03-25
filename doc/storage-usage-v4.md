## 0. 前置定义

这一版继续沿着前面 `v1/v2/v3` 的方向写，但把目标用法往当前代码能承接的形态上收了一步。

前面一直想把 `schema` 直接写成和类型定义同源的形式，最好能像：

```moonbit
struct Prefs {
  @tag(10) mut title: String = ""
  @tag(20) mut age: Int = 18
}
```

然后自动导出存储逻辑。  
但当前 MoonBit 这里没有现成的自定义 `derive` 能直接把这件事做完，所以现在先把入口收成手写
`Persist`。类型还是正常类型，存储定义也还是跟着类型一起写，只是暂时没有自动生成。

```
let kv = open_kv()
let bind = bind_with_kv(kv)
```

## 1. 普通值字段

```
struct Prefs {
  mut title: String
  mut age: Int
}

impl Persist for Prefs with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.title)),
    ("20", pack(self.age)),
  ])
} and unpack(value) -> Prefs {
  match value {
    Obj(m) => {
      let title = match m.get("10") {
        Some(v) => unpack(v)
        None => ""
      }
      let age = match m.get("20") {
        Some(v) => unpack(v)
        None => 18
      }
      { title, age }
    }
    _ => { title: "", age: 18 }
  }
}
```

```
let prefs = cel({ title: "Ada", age: 18 })
let stop = bind("prefs", prefs)
```

```
prefs.mutate(p => {
  p.title = "Bea"
  p.age = 19
})
flush()
```

目标效果：

- 存储里使用稳定 tag `10` / `20`
- 内存里继续用正常字段名
- 缺字段时由 `unpack` 补默认值
- 原地修改后自动写回

## 2. 包含引用字段

```
struct Prefs {
  title: Cel[String]
  age: Cel[Int]
}

impl Persist for Prefs with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.title)),
    ("20", pack(self.age)),
  ])
} and unpack(value) -> Prefs {
  match value {
    Obj(m) => {
      let title = match m.get("10") {
        Some(v) => unpack(v)
        None => cel("")
      }
      let age = match m.get("20") {
        Some(v) => unpack(v)
        None => cel(18)
      }
      { title, age }
    }
    _ => { title: cel(""), age: cel(18) }
  }
}
```

```
let prefs = cel({
  title: cel("Ada"),
  age: cel(18),
})

let stop = bind("prefs", prefs)
```

```
prefs.peek().title.set("Bea")
flush()
```

```
prefs.peek().age.set(19)
flush()
```

目标效果：

- 存储里落的还是当前值，不是引用本身
- 内部 `Cel` 单独变化后，自动保存也会跟着更新
- 根对象不需要每次重新 `set`

## 3. 数组

```
struct Doc {
  mut title: String
  mut tags: Array[String]
}

impl Persist for Doc with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.title)),
    ("20", pack(self.tags)),
  ])
} and unpack(value) -> Doc {
  match value {
    Obj(m) => {
      let title = match m.get("10") {
        Some(v) => unpack(v)
        None => ""
      }
      let tags = match m.get("20") {
        Some(v) => unpack(v)
        None => []
      }
      { title, tags }
    }
    _ => { title: "", tags: [] }
  }
}
```

```
let doc = cel({
  title: "Notes",
  tags: ["moonbit"],
})

let stop = bind("doc", doc)

doc.mutate(d => {
  d.tags.push("storage")
})
flush()
```

目标效果：

- 数组按元素递归存取
- 结构变化和元素值一起写回

## 4. 数组里的对象

```
struct Group {
  members: Array[Prefs]
}

impl Persist for Group with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.members)),
  ])
} and unpack(value) -> Group {
  match value {
    Obj(m) => {
      let members = match m.get("10") {
        Some(v) => unpack(v)
        None => []
      }
      { members }
    }
    _ => { members: [] }
  }
}
```

```
let group = cel({
  members: [
    { title: "Ada", age: 18 },
    { title: "Bea", age: 20 },
  ],
})

let stop = bind("group", group)
```

```
group.mutate(g => {
  g.members[0].age = 19
  g.members.push({ title: "Cora", age: 21 })
})
flush()
```

目标效果：

- 对象数组按元素递归存取
- 单个元素变化和数组结构变化走同一条写回路径

## 5. 引用字段加数组

```
struct Group {
  members: Array[Cel[Prefs]]
}

impl Persist for Group with pack(self) -> PersistValue {
  obj([
    ("10", pack(self.members)),
  ])
} and unpack(value) -> Group {
  match value {
    Obj(m) => {
      let members = match m.get("10") {
        Some(v) => unpack(v)
        None => []
      }
      { members }
    }
    _ => { members: [] }
  }
}
```

```
let group = cel({
  members: [
    cel({ title: "Ada", age: 18 }),
    cel({ title: "Bea", age: 20 }),
  ],
})

let stop = bind("group", group)
```

```
group.peek().members[0].peek().age.set(19)
flush()
```

目标效果：

- 数组里的引用节点也能递归跟踪
- 改内部元素时不需要重写整个数组
- 写回结果仍然是当前值树

## 6. 解绑

```
stop()
```

目标效果：

- 停止自动同步
- 后续改动不再写回

## 7. 类型系统带来的调整

`v3` 里更理想的目标其实是：

- 类型定义和存储定义完全同源
- 像 `field(10, "title", string(""))` 这种信息能直接挂到类型上
- 最后自动导出 `Persist`

但当前 MoonBit 这里暂时没有现成的自定义 `derive` 能直接把这件事打通，所以这一版先做了一个调整：

- 类型还是普通 `struct`
- 存储 tag、默认值和递归规则先写在 `Persist` 里
- 先让目标用法和运行时路径稳定下来

也就是说，`v4` 不是放弃 `v3`，而是把 `v3` 的目标先压成一个当前能落地、也能继续往 codegen 收的形态。

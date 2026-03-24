直接看目标用法，大概应该长这样。

## 1. 定义一个可持久化对象

```
priv struct Prefs {
  mut name: String
  mut age: Int
}

let prefs_schema =
  record2(
    "prefs",
    2,
    field("name", string_schema(), "anon"),
    field("age", int_schema(), 18),
    (name, age) => { name, age },
    prefs => (prefs.name, prefs.age),
  )
```
``` 用户批注
这个定义有够繁琐的，首先函数里要指定数量，这个我忍了，但后面那两个函数完全看不懂在干嘛，这些序列化反序列化还要自己写吗？？？
```
## 2. 读旧数据时自动升级

```
let old = """
{
  "schema": "prefs",
  "version": 1,
  "data": {
    "title": "Bea"
  }
}
"""

let prefs = load_text(prefs_schema, old)
```

这时目标行为是：

- title 迁到 name
- age 缺了就补 18
- 旧版本里多出来的字段自动丢掉
``` 用户批注
如果我的 perfs 是 { title: Cel[String] } 呢？
然后我也完全不理解你title迁移到name的原理，都是record的一个位置所以就认为是同一个东西吗
```
## 3. 写回当前版本
```
let text = encode_text(prefs_schema, prefs)
```
输出应该只保留当前 schema 允许的字段，比如：
```
{
  "schema": "prefs",
  "version": 2,
  "data": {
    "name": "Bea",
    "age": 18
  }
}
```
``` 用户批注
我不是很理解为什么要让写入的数据也保留这些data schema的说明，虽然我知道不是完全没用，但你这个确实有点冗余过多了
```
## 4. 绑定到 Cel，原地改完自动写回
```
let prefs = cel({ name: "Ada", age: 18 })

let stop = bind_text(prefs, prefs_schema, fn(text) {
  save_to_kv("prefs", text)
})

prefs.mutate(p => {
  p.name = "Cora"
  p.age = 21
})
```
目标效果是：

- mutate 后自动触发一次保存
- 调用方不需要手动 save()
- storage 不关心你是整值替换还是原地改动
``` 用户批注
你这就是强绑定 Cel[Pref] 这个用法，前面也说了，如果我就是想要属性本身的细粒度监听呢
另外 mutate 触发的修改是需要 batch 的，不是立即保存
在 IntentDoc 的原始设计里甚至是事务性的
```
## 5. 只改一小块 state 也一样
```
prefs.mutate(p => { p.age = 22 })
```
还是只会：

- 按当前 schema 重新编码整份文档
- 写回 KV
- 不保留废字段
- 不要求调用方补迁移逻辑
``` 用户批注
同上，原理是对的，但是强绑定了特定类型
```
## 6. 如果你有数组字段
```
priv struct Doc {
  mut tags: Array[String]
}

let doc_schema =
  record2(
    "doc",
    1,
    field("tags", array_schema(string_schema()), []),
    field("title", string_schema(), ""),
    (tags, title) => { tags, title },
    doc => (doc.tags, doc.title),
  )
```
用法还是一样：
```
doc.mutate(d => {
  d.tags.push("moonbit")
})
```

``` 用户批注
不知道你对 Array[Pref] 这样的东西支持得如何
```
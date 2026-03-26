# Storage 当前问题清单

这份文档只记录当前 `storage` 节点级实现里仍然没有收好的问题，不写修正方案。

## 已定语义

- `stop()`：只停止同步，不清 kv
- `stop(clean=true)`：停止同步，并清掉这棵树对应的 kv 数据
- 图内容变化导致的 stale child：应该删 kv
- 绑定生命周期结束导致的 stop：默认不删 kv

## 当前问题

### 1. `stop` 内部动作还没有拆开

当前节点清理逻辑本质上还是围绕 `drop_node` 一条线展开，但按已经定下的语义，后面必须明确区分两种动作：

- 只停止同步、释放运行时绑定、不删 kv
- 删除 kv，并递归处理不再可达的子节点

现在这两种语义还没有被代码层彻底拆成两条独立主路径。

### 2. scoped / bind stop 的默认行为还没跟新语义完全对齐

当前实现已经有 scoped 引用计数和最后一个作用域释放时的停机逻辑，但“默认 stop 不清 kv，`clean=true` 才清理”这条规则还没有完整落到 API 和内部动作分发上。

### 3. stale child 清理和 stop 卸载仍然容易被混成同一类动作

这两种“节点消失”表面相似，但语义不同：

- 父节点不再引用 child：这是图内容变化，应该 purge
- 整个 bind / scope 结束：这是生命周期结束，默认只应 detach

当前实现虽然已经有 stale child 清理，但还没有把这两类动作在结构上彻底分开。

### 4. `Obj` / `Arr` 两路逻辑仍然重复

对象节点和数组节点在这些核心函数里仍然分别走两套近似分支：

- `field_value`
- `encode_node`
- `attach_node`
- `ensure_node`
- `rehydrate_value`
- `hydrate_node`
- `sync_root`

这说明“节点”这个抽象还没有在代码层统一收口。

### 5. 身份索引仍然是并行结构

当前已经压缩到：

- `nodes`
- `obj_to_id`
- `arr_to_id`

比早先多张表并行的状态轻了很多，但仍然是“节点表 + 两张身份映射表”的组合，结构上还不够收。

### 6. 仍然依赖节点级浅遍历

当前 `collect_kids` 会在节点同步时重新扫描当前节点字段，更新 child refs。它已经不是旧的整图遍历，但仍然是一种节点级的小遍历，离更细粒度的字段级归因还有距离。

### 7. API 命名和参数语义还没完全稳定

`bind_refs_with_kv` / `bind_refs_scoped_with_kv` 这类名字仍然偏实现层。与此同时，既然 `stop(clean=...)` 的语义已经定了，返回 stop 句柄最终是否要正式接受参数、参数名是什么、默认值怎么表达，也还没有在公开接口上固定下来。

### 8. 测试口径还需要继续补齐

当前已经覆盖了 shared child、自引用、stale child cleanup、scoped stop、owner `Cel` 等主路径，但还缺更细的边缘用例：

- shared child 被一边解绑、另一边仍继续持有时不能误删
- root 大幅收缩后的多层 child purge
- 数组中的 shared child 删除与复用
- `stop(clean=true)` 的完整清理语义
- `stop()` 之后重新 bind 同一 prefix 的恢复语义

### 9. flush 提交路径虽然正确，但结构上仍有拼接感

当前实现已经做到“依赖追踪”和“post-flush 写盘”解耦，但代码层看起来仍然像两段机制拼在一起，而不是一个非常自然的单入口。

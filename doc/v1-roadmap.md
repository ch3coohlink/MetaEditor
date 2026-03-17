# MetaEditor V1 路径规划

> 截止日期：**2026-04-21**（距今 ~35 天）
> 截止日期：**2026-04-21**（距今 ~35 天）
> 竞赛要求：代码编辑组件，支持高亮、编辑历史、多选、搜索、扩展接口
> 核心信条：优先关注工程复杂度与能力质量，精简代码，拒绝盲目凑行数。

---

## 一、现状清单

| 模块 | 文件 | 行数 | 状态 |
|------|------|------|------|
| 响应式系统 | `src/reactive.mbt` | 62 | ✅ cel/effect/scope/flush 基本可用 |
| UI 运行时 | `src/ui.mbt` | 175 | ✅ VNode/DomCmd/h()/Child(Dyn/Arr/Str) |
| 浏览器投影 | `src/js/bridge.js` | 111 | ✅ thin DOM projector + WebSocket |
| WebSocket 服务 | `cli/server.mjs` | 146 | ✅ 指令历史 + CLI + 多客户端 |
| CLI 入口 | `cli/main.mbt` | 32 | ✅ FFI + 启动闭环 |
| 示例应用 | `app/main.mbt` | 25 | ✅ Counter demo |
| 单元测试 | `test/*.mbt` | ~250 | ✅ UI + reactive 测试覆盖 |
| JS 参考实现 | IntentDoc/dev/ | ~30 文件 | 📦 reactive/ui/text-editor/parser 可参考 |

**已验证的端到端闭环**：MoonBit Core → DomCmd 序列化 → WebSocket → bridge.js → DOM 渲染 → 事件回传 → callback 触发 → 响应式更新 → 再投影

---

## 二、五条技术线的能力边界与扩展路径

### 技术线 A：响应式与 UI 运行时

| 当前能力 | v1 目标 | 扩展路径 |
|---|---|---|
| ✅ cel(signal) | ☐ computed/memo | reactive proxy 对象 |
| ✅ effect/scope | ☐ watch(old, new) | 异步 effect |
| ✅ h() + Child enum   | ☐ 组件化 component()  | slot/context        |
| ✅ Dyn/Arr/Str/Node   | ☐ map() 高效列表      | 虚拟列表             |
| ✅ 事件(E/Listen)      | ☐ 键盘事件透传        | 手势/IME             |
| ✅ DomCmd 序列化       | ☐ style 对象支持      | CSS-in-MBT          |
| ✅ reg_query          | ☐ probe 远程属性      | AI 可观测 probe      |

**接口合约**（v1 后不变的 API 形状）：
- `cel(x) -> Cel[T]` / `.get()` / `.set(x)` / `.update(f)`
- `effect(f) -> stop` / `scope(f) -> dispose`
- `h(tag, attrs, children) -> VNode`
- `Child` enum: `Null | Node | Str | Int | Arr | Dyn`

**v1 需要新增**：
- `computed(f) -> Cel[T]`（只读派生信号，带缓存）
- `watch(source, callback)`（显式监听某个信号的变化）
- `component(state, view)` 组件抽象（可选，有 scope 已足够）
- `map(list_signal, item_fn)` 高效重渲列表
- 键盘事件：`onkeydown` 回传 key 信息到 Core

---

### 技术线 B：Bridge 协议层

| 当前能力 | v1 目标 | 扩展路径 |
|---|---|---|
| ✅ [TAG, ...ARGS] | ☐ 样式专用指令 | 紧凑二进制协议 |
| ✅ JSON 序列化 | ☐ 批量属性设置 | 差量更新 |
|✅ Listen(event)     | ☐ 事件带数据回传     | 结构化事件           |
|✅ ws duplex         | ☐ query 双向通道     | 心跳/重连           |
|✅ ui_history replay | ☐ 快照式重连         | 增量快照            |

**v1 关键补全**：
- 事件回传需要携带 `key`, `code`, `ctrlKey`, `shiftKey` 等信息（编辑器必需）
- 新增指令：`SetStyle(id, prop, value)` 与 `RemoveAttr(id, key)`
- bridge 侧需实现 `focus()`, `blur()`, `scrollIntoView()` 等宿主命令
- query 通道增强：`bridge → core` 方向可发送 DOM 测量结果

---

### 技术线 C：编辑器状态层

| 当前能力 | v1 目标 | 扩展路径 |
|------|------|------|
|(无)                 | ☐ 文档模型(lines)   | rope / piece table  |
|                     | ☐ 游标/选区模型     | 多光标               |
|                     | ☐ 编辑 op 定义      | CRDT op             |
|                     | ☐ undo/redo 栈      | 分支历史            |
|                     | ☐ 快照 snapshot     | 持久化              |
|                     | ☐ 自动保存机制      | IndexedDB           |

**接口合约**（v1 钉死，后续底层可替换）：
- `EditorState { lines, cursor, selections, version }`
- `apply_op(state, op) -> state`
- `undo(state) -> state` / `redo(state) -> state`
- `snapshot(state) -> bytes` / `restore(bytes) -> state`

**v1 实现选择**：
- 文档用 `Array[String]`（行数组），足以支撑 v1 场景
- 后续可替换为 rope 或 piece table，接口层不变

---

### 技术线 D：文本编辑器核心

| 当前能力 | v1 目标 | 扩展路径 |
|------|------|------|
|(无)                 | ☐ 基础文本输入        | IME 组合输入         |
|                     | ☐ 光标移动(方向键)    | 按词/段落跳转        |
|                     | ☐ 文本选择            | 多选区              |
|                     | ☐ 复制/粘贴/剪切      | 富文本粘贴           |
|                     | ☐ 搜索/替换           | 正则搜索            |
|                     | ☐ Tab/Enter/Backspace | 自动缩进           |
|                     | ☐ 文本测量(prefix-w)  | HarfBuzz shaping   |
|                     | ☐ 光标坐标计算        | 逻辑层布局           |
|                     | ☐ 行号 gutter         | 折叠/断点           |
|                     | ☐ 滚动/viewport       | 虚拟列表            |

**v1 文本测量策略（显式的过渡方案）**：
- 使用浏览器 `measureText` 作为 oracle
- 在 bridge 侧实现 `measureText(text, font) -> width[]`
- Core 侧通过 query 通道获取测量结果，缓存为 prefix-width 表
- **接口层**：`measure_run(text, font) -> Float[]` — 后续可替换为 `harfbuzzjs`

**v1 明确不做**：
- RTL / bidi
- 自动换行 (word-wrap) — v1 只做水平滚动 no-wrap
- 复杂脚本 shaping
- 完整 Unicode grapheme 边界 — v1 用 `Intl.Segmenter` 过渡

---

### 技术线 E：解析器与语法高亮

| 当前能力 | v1 目标 | 扩展路径 |
|---|---|---|
| (无) | ☐ 高亮标记模型 | 语义 token |
| | ☐ 简单关键词高亮 | PEG parser |
| | ☐ MoonBit 基础高亮 | 增量解析 |
| | ☐ 括号匹配 | 折叠标记 |

**v1 高亮策略**：
- 使用基于正则/关键词的 tokenizer（不是完整 parser）
- 为 MoonBit 提供关键词、字符串、注释、数字的高亮
- **接口层**：`tokenize(line) -> Token[]` — 后续可替换为完整 parser
- 括号匹配单独实现，不依赖 parser

---

## 三、周计划（5 周 = 35 天）

### Week 1（3/18 – 3/24）：核心运行时补全

| 任务 | 优先级 |
|---|---|
| `computed()` 与 `watch()` | P0 |
| `map()` 高效列表渲染 | P0 |
| 键盘事件回传（bridge + Core） | P0 |
| `SetStyle` / `RemoveAttr` 指令 | P0 |
| bridge 宿主命令（focus/blur/scroll） | P1 |
| DOM 测量 query 通道 | P0 |
| 单元测试补充 | P0 |

**交付检查点**：键盘事件可以从浏览器传到 Core 并触发逻辑；Core 可以通过 query 获取 DOM 测量结果。

---

### Week 2（3/25 – 3/31）：文本编辑模型

| 任务 | 优先级 |
|---|---|
| 文档模型 `DocState`（lines / cursor / selection） | P0 |
| 编辑 op 模型与 apply | P0 |
| undo/redo 栈 | P0 |
| 快照 snapshot / restore | P1 |
| 自动保存机制（timer + dirty flag） | P1 |
| 文本测量 bridge 集成（measureText → prefix cache） | P0 |
| 游标坐标计算（row,col ↔ x,y） | P0 |
| 单元测试 | P0 |

**交付检查点**：在 Core 内可以创建文档、执行编辑操作、undo/redo，并计算光标像素坐标。

---

### Week 3（4/1 – 4/7）：编辑器 UI 与交互

| 任务 | 优先级 |
|---|---|
| 编辑器视图组件（行渲染 + gutter + 光标） | P0 |
| 键盘交互处理（方向键/Home/End/PgUp/PgDn） | P0 |
| 文本选择（Shift+方向键 / 鼠标拖拽） | P0 |
| 复制/粘贴/剪切 | P0 |
| 搜索/替换 UI + 逻辑 | P1 |
| 滚动管理 + viewport 裁剪 | P0 |
| Tab / Enter / Backspace 处理 | P0 |
| 集成测试 | P0 |

**交付检查点**：可以在浏览器中打开 MetaEditor，进行基本文本编辑，有光标、选择、滚动。

---

### Week 4（4/8 – 4/14）：解析器、高亮与 AI 接口

| 任务 | 优先级 |
|---|---|
| Token 模型与 tokenizer 框架 | P0 |
| MoonBit 关键词/字符串/注释 tokenizer | P0 |
| 高亮渲染集成（token → span style） | P0 |
| 括号匹配 | P1 |
| AI CLI 接口（读写文档 / 执行操作 / 查询状态） | P0 |
| CAS patch 模型（AI 安全编辑） | P1 |
| query/probe 增强（AI 可查询光标位置等） | P1 |
| 测试 | P0 |

**交付检查点**：MoonBit 代码有基础语法高亮；AI 通过 CLI 可以读写编辑器内容并查询状态。

---

### Week 5（4/15 – 4/21）：集成、打磨与文档

| 任务 | 优先级 |
|---|---|
| 多选区支持 | P1 |
| 自动保存 + 恢复完整链路 | P1 |
| 性能优化（大文件 / 长行） | P1 |
| 编辑器 Demo 完善（完整可用） | P0 |
| 扩展接口设计（插件注册 / hook） | P1 |
| README / 模块设计文档 | P0 |
| 开发历程文章 | P0 |
| 端到端验收测试 | P0 |
| 补充各模块测试 | P0 |

**交付检查点**：完整可用的代码编辑器 Demo，有高亮、历史、选择、搜索、AI CLI 接口。

---

## 四、对齐竞赛评审标准

| 维度（各 25%） | MetaEditor 对应 |
|----------------|-----------------|
| **完成度** | 框架 + 文本编辑器 Demo 按 scope 交付；CLI + Web 双入口可运行 |
| **工程质量** | 清晰的 5 模块分层；接口合约与实现分离；充分的单元+集成测试 |
| **可解释性** | 文档体系（design.md -> v1-roadmap -> 开发历程）；AI 协作全程记录 |
| **用户体验** | 编辑器 Demo 可直接使用；AI 通过 CLI 无缝操作 |

---

## 五、风险项

| 风险 | 影响 | 缓解 |
|------|------|------|
| 键盘事件/IME 在 bridge 层的兼容性 | 阻塞 W3 交互 | W1 提前做 spike |
| 文本测量的 JS ↔ Core 延迟 | 影响打字体验 | 使用同步 query + 本地缓存 |
| MoonBit 编译器版本更新导致语法不兼容 | 影响进度 | 锁定编译器版本 |
| 选区/多选区交互复杂度超预期 | 影响 W3 | 降级为单选区 + W5 再补 |

---

## 六、模块代码组织建议

```
MetaEditor/
├── src/                     # 核心库
|   ├── reactive.mbt         # cel/effect/scope/computed/watch
|   ├── ui.mbt               # h()/VNode/DomCmd/Child
|   ├── state.mbt            # EditorState/op/undo-redo/snapshot
|   ├── text.mbt             # 文本模型/测量/选区/游标
|   ├── tokenizer.mbt        # 高亮 token 框架
|   ├── tokenizer_moonbit.mbt # MoonBit tokenizer 实现
|   ├── search.mbt           # 搜索/替换
|   ├── editor.mbt           # 编辑器组件(视图+交互)
|   └── js/bridge.js         # 浏览器投影层
├── app/                     # Demo 应用入口
├── cli/                     # CLI + 服务入口
├── test/                    # 测试
└── doc/                     # 文档
```

---

## 七、验证计划

### 自动化测试

- **单元测试**：`moon test --target js`
  - 响应式系统：cel/effect/scope/computed/watch
  - UI：h()/DomCmd 序列/子节点挂载/事件
  - 状态层：op apply / undo / redo / snapshot
  - 文本模型：游标移动 / 选区 / 文本变更
  - tokenizer：各类 token 识别覆盖
  - 搜索：匹配 / 替换 / 边界条件

### 集成验证

- **端到端 CLI 测试**（脚本自动化）：
  1. 启动 server
  2. 通过 CLI 发送编辑操作
  3. 通过 query 验证文档状态
  4. 验证 undo/redo
  5. 验证 AI patch 接口

### 手动验证

- 本系统不推荐手动验证，应尽量用自动测试或 AI 测试完成
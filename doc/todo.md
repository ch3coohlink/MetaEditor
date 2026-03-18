# MetaEditor TODO List

## 1. 核心通讯与协议 (Core Connectivity & Protocol)
- [ ] **紧凑协议优化**: 继续完善 [TAG, ...ARGS] 的数组协议，确保所有枚举和复杂类型都有确定的索引映射。
- [ ] **Bridge 代码风格对齐**: 根据 `intentdoc/AGENTS.md` 规范重构 `bridge.js`（移除分号、使用单引号）。
- [ ] **心跳与连接管理**: 增强 WebSocket 的稳定性，处理意外断连及指令重发逻辑。

## 2. 文本测量与关键布局 (Text Measuring & Core Layout)
- [ ] **文本测量 V1**: 按 `text-v1.md` 实现 `Intl.Segmenter + measureText` 的文本测量闭环。
- [ ] **段落布局对象**: 实现 `TextUnitMap / SegmentationResult / PrefixWidthCache / ParagraphLayout`。
- [ ] **几何查询接口**: 实现 `caret_rect / selection_rects / hit_test`，并保证结果对齐到 grapheme 边界。
- [ ] **缓存与失效规则**: 实现文本、宽度、样式、locale 变化时的缓存失效策略。
- [ ] **关键布局上收 Core**: 文本关键几何由 Core 统一计算，浏览器不负责决定最终关键视图。

## 3. UI 探针与结构化验证 (UI Probes & Structured Verification)
- [ ] **语义化探针 (UI Probes)**: 为关键节点（光标、选区等）定义探针身份，实现结构化的视觉断言。
- [ ] **Core Probe 查询**: 让 AI/测试优先查询 Core 持有的关键几何与结构化结果。
- [ ] **宿主辅助测量**: 允许浏览器回传少量宿主测量结果作为对照与调试，不建立通用 SyncProp 主路径。
- [ ] **时间序列动画 (Animation Stream)**: 实现 `[(t, val, ease), ...]` 关键帧流，Core 只负责生成逻辑路径，Bridge 视使用场景转化为 CSS animation / RAF 属性设置。

## 4. 调试与开发者体验 (Time-travel & DX)
- [ ] **时间旅行调试 (Time-travel Debugging)**: 增强 `server.mjs` 的指令历史管理，支持指令级重放 (Replay)、回滚 (Rewind) 和逐指令步进。
- [ ] **状态快照 (Snapshotting)**: 在 `server.mjs` 实现定时快照，避免新标签页加载时从头重放上万条历史指令。
- [ ] **指令可视化工具**: 开发一个基于浏览器的侧边栏，实时展示当前的指令流快照。

## 5. 与 IntentDoc 解析层集成 (Parser & IDE Kernel)
- [ ] **集成单遍容错 Parser**: 引入 `intentdoc` 设计的 `dev/parser.js` 核心，支持最远位置聚合与容错恢复。
- [ ] **增量分析支持 (Incremental Parsing)**: 实现基于行偏移（Line-relative）的缓存重定位逻辑，支持“文本 $\Delta$ 变更 -> 局部 AST 更新”。
- [ ] **语义标签与实时索引 (Semantic Tagging)**: 在语法定义层注入 `role` 标签，实现“解析即索引”，完成解析的同时建立符号表快照。
- [ ] **Follow-set 自动恢复**: 实现基于堆栈追溯的 Follow-set 同步点扫描，增强语法破损时的结构稳定性。

## 6. 协作与 AI 基础设施 (Collaboration & AI)
- [ ] **多客户端投影 (Multi-client Casting)**: 支持一个 Brain 同时投影到多个独立 Projector，并保留各自的派生状态。
- [ ] **AI 协作模型 (Intent Dispatcher)**: 将 AI 动作建模为独立用户，通过 CAS/CRDT 算法无冲突地处理人类与 AI 的并发编辑意图。
- [ ] **MCP 协议对接 (MCP Server)**: 为 AI 提供 `get_parser_vitals` 和 `trace_parse_path` 等专用工具，实现 AI 对语法的闭环调试。
- [ ] **LSP 语义回响**: 利用内部的“解析-语义-渲染”闭环，向外提供兼容 LSP 的高级语言特性支持。

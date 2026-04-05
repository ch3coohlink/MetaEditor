这里记录一些具体行为需要修正的地方
- [ ] 窗口拖拽
- [ ] 窗口大小调整
- [ ] 窗口最大化最小化
- [ ] 更窄的任务栏 / 窗口栏
- [ ] system tray 样式优化（更小， 更不占地方）
- [ ] 点击桌面应该取消图标的选择
- [ ] 图标的选择状态应该和窗口的选择状态无关
- [ ] 修复浏览器测试，并把其功能职责系统化，比如测试最终样式应用结果，以及交互是否真实有效
- [ ] cli 应该拒绝拼写错误的 command 和 flag
- [ ] 

---------
以下为过时内容
# MetaEditor TODO List

## 1. 核心通讯与协议 (Core Connectivity & Protocol)
- [x] **紧凑协议优化**: 继续完善 [TAG, ...ARGS] 的数组协议，确保所有枚举和复杂类型都有确定的索引映射。
- [x] **Bridge 代码风格对齐**: 根据 `intentdoc/AGENTS.md` 规范重构 `bridge.js`（移除分号、使用单引号）。
- [x] **本地连接层**: 明确 CLI 如何连接浏览器主运行时，定义 command/query/probe 的最小通信层。

## 2. 文本测量与浏览器真相接口 (Text Measuring & Browser Truth API)
- [ ] **文本测量 V1**: 按 `text-v1.md` 实现 `Intl.Segmenter + measureText` 的文本测量闭环。
- [ ] **段落布局对象**: 实现 `TextUnitMap / SegmentationResult / PrefixWidthCache / ParagraphLayout`。
- [ ] **几何查询接口**: 实现 `caret_rect / selection_rects / hit_test`，并保证结果对齐到 grapheme 边界。
- [ ] **缓存与失效规则**: 实现文本、宽度、样式、locale 变化时的缓存失效策略。
- [x] **浏览器真相查询**: 让 CLI/AI 能直接查询浏览器运行时内部的文本布局与 Probe 结果。

## 3. UI 探针与结构化验证 (UI Probes & Structured Verification)
- [x] **语义化探针 (UI Probes)**: 为关键节点（光标、选区等）定义探针身份，实现结构化的视觉断言。
- [x] **Probe 查询接口**: 让 AI/测试直接查询浏览器运行时持有的关键几何与结构化结果。
- [x] **结构化 command/query/probe API**: 为自动化测试和 CLI 提供稳定接口，而不是依赖 DOM selector 或截图。
- [ ] **时间序列动画 (Animation Stream)**: 实现 `[(t, val, ease), ...]` 关键帧流，由浏览器运行时负责插值与渲染。

## 4. 调试与开发者体验 (Time-travel & DX)
- [x] **时间旅行调试 (Time-travel Debugging)**: 在浏览器主运行时中支持结构化状态回放、步进与回滚。
- [x] **状态快照 (Snapshotting)**: 实现浏览器运行时内部的快照与恢复机制。
- [ ] **指令可视化工具**: 开发一个基于浏览器的侧边栏，实时展示当前的 command/query/probe 交互快照。

## 5. 与 IntentDoc 解析层集成 (Parser & IDE Kernel)
- [ ] **集成单遍容错 Parser**: 引入 `intentdoc` 设计的 `dev/parser.js` 核心，支持最远位置聚合与容错恢复。
- [ ] **增量分析支持 (Incremental Parsing)**: 实现基于行偏移（Line-relative）的缓存重定位逻辑，支持“文本 $\Delta$ 变更 -> 局部 AST 更新”。
- [ ] **语义标签与实时索引 (Semantic Tagging)**: 在语法定义层注入 `role` 标签，实现“解析即索引”，完成解析的同时建立符号表快照。
- [ ] **Follow-set 自动恢复**: 实现基于堆栈追溯的 Follow-set 同步点扫描，增强语法破损时的结构稳定性。

## 6. 协作与 AI 基础设施 (Collaboration & AI)
- [x] **多 CLI 接入**: 支持多个 CLI / 自动化工具同时连接同一个浏览器主运行时。
- [ ] **AI 协作模型 (Intent Dispatcher)**: 将 AI 动作建模为独立用户，通过 CAS/CRDT 算法无冲突地处理人类与 AI 的并发编辑意图。
- [ ] **MCP 协议对接 (MCP Server)**: 为 AI 提供 `get_parser_vitals` 和 `trace_parse_path` 等专用工具，实现 AI 对语法的闭环调试。
- [ ] **LSP 语义回响**: 利用内部的“解析-语义-渲染”闭环，向外提供兼容 LSP 的高级语言特性支持。

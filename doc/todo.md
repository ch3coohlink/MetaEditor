# MetaEditor TODO List

## 1. 核心通讯与协议 (Core Connectivity & Protocol)
- [ ] **紧凑协议优化**: 继续完善 [TAG, ...ARGS] 的数组协议，确保所有枚举和复杂类型都有确定的索引映射。
- [ ] **Bridge 代码风格对齐**: 根据 `intentdoc/AGENTS.md` 规范重构 `bridge.js`（移除分号、使用单引号）。
- [ ] **心跳与连接管理**: 增强 WebSocket 的稳定性，处理意外断连及指令重发逻辑。

## 2. UI 探针与远程属性访问 (Remote Props & Probes)
- [ ] **远程属性查询 (SyncProp)**: 实现指令 `[10, id, "propName"]`，允许 Brain 主动订阅 DOM 属性（如 `offsetWidth`, `scrollTop`）。
- [ ] **镜像状态表 (Mirror Map)**: 在 Brain 端维护 `Map[(Int, String), String]`，实现对远程属性的“准同步”读取。
- [ ] **语义化探针 (UI Probes)**: 为关键节点（光标、选区等）定义探针身份，实现结构化的视觉断言。

## 3. 响应式与进阶渲染 (Advanced Reactivity & Rendering)
- [ ] **派生状态分离**: 明确“共享语义状态”与“客户端派生状态”的界限，布局测量等环境依赖逻辑保留在 Bridge 侧。
- [ ] **时间序列动画 (Animation Stream)**: 实现 `[(t, val, ease), ...]` 关键帧流，Brain 只负责生成逻辑路径，Bridge 负责 RAF 高频插值。
- [ ] **Shadow DOM 支持**: 对组件化的 Shadow DOM 提供更深层的指令投影支持。

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

# MetaEditor (Meta-Editor Runtime)

MetaEditor 是一个专为 AI 协作时代设计的编辑器底层运行时与开发框架。它基于 MoonBit 构建，旨在通过极简的协议与深度的语义模型，解决复杂编辑器在跨平台、人机协作及自动化验证中的核心痛点。

## 1. 核心设计支柱 (Architectural Pillars)

- **无头优先 (Headless-First)**: 编辑器的“大脑”运行在 Native/Wasm 环境，浏览器仅作为无状态的“投影仪”。这种分离从物理层面解除了浏览器 DOM 对 AI 理解逻辑的干扰。
- **细粒度响应式 (Fine-grained Reactivity)**: 核心逻辑完全由 Signal 驱动。只有真正变化的部分才会产生 `DomCmd` 指令流，确保极致的传输与渲染效率。
- **共享语义与分发投影 (Shared/Derived State)**:
  - **Shared State**: 文档模型、操作历史和 UI 语义树在核心层统筹。
  - **Derived State**: 布局测量、滚动位置、视口信息等环境依赖属性，由各投影端本地维护。
- **UI 语义化探针 (UI Probes)**: 允许为关键 UI 节点（如光标、选区）注入身份。AI 不需要 OCR 截图，只需通过结构化指令即可验证视觉属性的正确性。

## 2. 系统组件

- **Brain (Native Core)**: 业务逻辑与状态真理来源，输出 `DomCmd` 指令序列。
- **Bridge (JS Projector)**: 处理 DOM 挂载、本地属性计算、时间序列动画插值及事件回传。
- **Compact Protocol**: 采用 `[TAG, ...ARGS]` 形式的数组化协议，最小化序列化开销。

## 3. 功能特性

- [x] **指令化 VDOM**: 支持 Node, String, Null 以及嵌套数组的指令化映射。
- [x] **动态子节点 (Dyn)**: 内置锚点替换算法，支持毫秒级的局部指令重刷。
- [x] **确定性指令历史**: 所有的 UI 变更都是可追踪、可序列化的追加流，天然支持录制与重放。
- [ ] **时间序列动画**: 核心下发稀疏关键帧信号，Bridge 执行高频插值。
- [ ] **远程属性同步**: 允许 Brain 向投影端订阅特定的几何属性（如 offsetWidth）。

## 4. 快速开始

```bash
# 1. 编译 MoonBit 核心为 JS 目标
moon build --target js

# 2. 启动 CLI 服务与投影投影服务器
node cli/server.mjs

# 3. 访问 http://localhost:8080 预览 UI
```

---
*Inspired by IntentDoc.*

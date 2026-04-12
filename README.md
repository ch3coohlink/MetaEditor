# MetaEditor

MetaEditor 是一个用 MoonBit 写的编辑器运行时与 UI 框架，目标是把浏览器界面、CLI、测试和 AI
控制面压到同一条底层语义路径上。

当前仓库仍在快速收核心模型，但主方向已经明确：

- headless-first，业务和状态放在运行时，浏览器主要负责投影
- 细粒度 reactive 驱动增量 DOM 命令流
- UI、CLI、service、browser harness 共用同一条 runtime 路径
- 公开控制面以 path、query、action 这类正式语义为核心

## 现阶段包含什么

- `src/reactive.mbt`
  最小响应式内核，负责 `Cel / effect / scope / flush`
- `src/dom.mbt`
  可变 DOM 树和 `DomCmd` 发射主路径
- `src/runtime.mbt`
  运行时与挂载入口
- `service/`
  native service、CLI、HTTP、bridge
- `src/bridge.js`
  浏览器投影侧 bridge
- `e2e/`
  browser e2e 与 bridge 行为验证
- `codegen/`
  独立的代码生成实验模块

## 仓库状态

这个仓库已经能跑通核心测试和 service/browser 主链路，但它还不是稳定 API 的公开发布版。

如果你现在阅读或试用它，比较适合的预期是：

- 把它当成一个正在收最小核心模型的编辑器运行时
- 可以参考现有 reactive、DOM、service 设计
- 可以直接运行测试和本地 demo
- 不能假设当前 API、协议和目录结构已经完全冻结

## 为什么和普通前端框架不一样

MetaEditor 重点解决的是“长期维护、可查询、可自动化控制的编辑器界面”，所以它从一开始就把这几件事放在一起设计：

- 运行时节点 identity 要稳定，不能每次更新都重建整棵树
- path 和 query 语义要稳定，外部调用方不能依赖瞬时 DOM 节点 id
- 人工操作、CLI、browser harness、AI agent 操作的是同一个系统
- JSON 主要留在边界层，内部优先保持 typed 语义

## 快速开始

### 环境

- MoonBit 工具链
- Node.js
- PowerShell
- Windows 原生构建环境

当前脚本默认走 PowerShell，并且 native 分支会用到本仓库现有的 Windows 构建链。

### 安装依赖

```powershell
npm install
moon update
```

### 跑全量测试

```powershell
./scripts/test-all.ps1
```

这是仓库唯一的正式测试入口。它会统一跑 core、native、browser 和 lifecycle 几条线。

### 运行 service

```powershell
./meta.ps1
```

如果你想看脚本细节，可以继续读 `scripts/` 和 `service/`。

## 目录导览

```text
src/       核心 reactive、dom、runtime、browser bridge
service/   native service、cli、http、sqlite、session
e2e/       browser 端到端测试
scripts/   构建、测试、发布辅助脚本
doc/       设计说明、协议文档、历史讨论
codegen/   独立代码生成实验
```

## 先读哪些文档

- `doc/design.md`
  总体设计草图
- `doc/meta-editor-service.md`
  service 侧能力和接口
- `doc/json-protocol-standard.md`
  边界 JSON 协议约定
- `doc/dom-api-compare.md`
  DOM API 设计对比

## 公开前你需要知道的边界

- 现在最稳定的是“统一 runtime + service/browser 测试主路径”这个方向
- 核心模型还在继续压短，接口命名和局部结构还会调整
- 这个仓库更接近 runtime/framework 实验，而不是现成应用

## License

AGPL-3.0-or-later

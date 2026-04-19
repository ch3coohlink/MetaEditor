# MetaEditor

MetaEditor 是一个用 MoonBit 编写的编辑器 runtime。
它把响应式状态、可变 DOM、实例树、service、浏览器执行面和自动化控制统一在了一个运行时里。
同时有多个

设计特点：

- 用细粒度 reactive 驱动增量更新
- 用稳定 identity 维护长期存活的界面树
- 用 path、query、trigger 这类正式语义暴露控制面
- 让浏览器、脚本、测试操作同一个 runtime

## 仓库里现在有什么

- `src/`
  核心模型，包含 reactive、dom、query、runtime 和编辑器实例主逻辑
- `service/`
  native service 运行时、协议边界和持久化相关实现
- `browser/`
  浏览器宿主、桥接 FFI 和页面入口
- `e2e/`
  浏览器黑盒测试
- `scripts/`
  构建、测试、运行脚本
- `codegen/`
  独立代码生成实验

## 它在解决什么

MetaEditor 不是把页面渲染出来就结束的 UI 库。它更关心这几件事：

- 节点 identity 稳定，局部更新不靠整棵重建
- query path 稳定，外部控制不依赖特定 DOM 结构
- UI 操作、自动化操作、测试操作描述的是同一个系统
- JSON 主要留在边界层，内部尽量保持 typed 语义

## 快速开始

### 依赖

- MoonBit 工具链
- Node.js
- MSVC 工具链（Windows环境）

### 使用
> 注意：Windows 环境需要在构建之前运行一次 `./scripts/import-vs-env.ps1` 来导入 vs 环境，一个 powershell 实例只需要导入一次

并行全量测试： `./run test-all`
构建并直接使用： `./run meta help`

## 目录导览

```text
src/       核心 reactive、dom、query、runtime、entry
service/   native service runtime、协议、sqlite stub
browser/   浏览器入口和桥接宿主
e2e/       浏览器黑盒测试
scripts/   构建、测试、运行脚本
doc/       设计记录与讨论
codegen/   独立代码生成实验
```

## 当前边界

- 仓库已经能跑通 core、service、browser 主链路
- 核心模型仍在继续压短，API 和局部结构还会调整
- 它更接近正在收敛中的 runtime/framework，而不是稳定发布版应用框架

## License

AGPL-3.0-or-later

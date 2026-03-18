# MetaEditor 文档专业分析

> 注意：这是一份历史分析记录。部分判断已被后续文档修正，尤其是：
>
> - `design.md` 中“客户端参与最终视图计算”的旧表述
> - `text-measuring.md` 里对 v1 是否 no-wrap 的早期判断
>
> 当前实现与执行应优先参考：
>
> - [text-measuring.md](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/text-measuring.md)
> - [text-roadmap.md](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/text-roadmap.md)
> - [text-v1.md](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/text-v1.md)

> 分析范围：`MetaEditor/doc/` 下全部 5 份文档

---

## 一、文档全景

| 文档 | 定位 | 篇幅 | 质量评价 |
|------|------|------|----------|
| [design.md](file:///d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/design.md) | 总体架构设计 | 131 行 | ★★★★☆ 骨架清晰，已做过一次关键修正 |
| [discuss-multiview-2026-03-17.md](file:///d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/discuss-multiview-2026-03-17.md) | 运行模型与逻辑布局讨论纪要 | 495 行 | ★★★★★ 高质量推演过程，对话式结构保留了决策脉络 |
| [text-measuring.md](file:///d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/text-measuring.md) | 文本测量技术栈深度分析 | 651 行 | ★★★★★ 迄今最扎实的单专题文档，技术选型判断成熟 |
| [css-layout-property.md](file:///d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/css-layout-property.md) | CSS 布局属性分类参考表 | 117 行 | ★★★☆☆ 纯参考性质，无分析视角 |
| [todo.md](file:///d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/todo.md) | 功能待办清单 | 34 行 | ★★★☆☆ 粒度恰当但全部未启动，缺少优先级标注 |

---

## 二、架构设计 (design.md) 分析

### 优点

1. **Headless-First 定位非常准确**——将 Core 与 Projector 解耦，这在编辑器领域是正确且罕见的选择。VS Code 和 Zed 都在不同程度上走这条路，但 MetaEditor 出发点更激进：直接要求 Core 持有可测视图真相。
2. **UI Probe 理念成熟**——让 AI 直接 `query("cursor")` 而不是截图 OCR，这相比 Playwright 截图断言提升了至少一个量级的可测性。
3. **时间序列动画设计精巧**——"离散关键帧 + 局部插值"把动画从浏览器不可控行为变成结构化数值流，这对 AI 验证和时间旅行调试都极其友好。
4. **CAS Patch 模型**——强制 AI 提交带校验的 Patch，这是保证人机协作状态安全的必要约束。

### 存在张力的部分

> [!WARNING]
> 本节原本指出 `design.md` §2.5 与讨论纪要矛盾。这个问题后来已经在 `design.md` 中修正，因此下面保留的分析只适合作为历史背景。

### 建议

- 将 §2.5 运行模型改为"关键布局由 Core 完成，客户端仅做投影执行"的最终收敛版本。
- 增加一节专门描述"布局责任边界"——哪些几何由 Core 决定、哪些外观由 CSS 负责（讨论纪要 §9-10 已有结论）。

---

## 三、讨论纪要 (discuss-multiview) 分析

这是五份文档中**最有价值**的一份。

### 为什么

1. **保留了完整的推翻与重建轨迹**——不是抽象总结，而是记录了"哪个方案为什么被否定"。对后续接手者来说，这比一份最终结论文档更有用。
2. **四次转折都很关键**：
   - metrics 本地化 → 合理
   - view 下沉客户端 → 看似合理，实际破坏可测性目标
   - semantic view / projected view 折中 → 仍然不够
   - 关键布局上收 Core → **唯一自洽的出路**

### 我的专业判断

这轮讨论得出的核心结论——**"把关键布局提升到逻辑层"**——在编辑器架构领域是正确的结论。这本质上和 Flutter 的路线一致：不依赖宿主布局引擎做关键几何，自己持有布局真相。

不过纪要中有一个隐含风险未被展开讨论：

> [!IMPORTANT]
> **关键布局上收 Core 后，Core 必须拥有可靠的文本测量能力。** 否则 Core 只能做容器级布局（flex / stack），无法做文本行级布局（caret、selection、wrapping）。这直接引出 `text-measuring.md` 讨论的全部问题。

换言之，这两份文档实际上是一条逻辑链的上下游。建议在文档中显式建立这个链接。

---

## 四、文本测量技术栈 (text-measuring.md) 分析

### 优点

1. **10 阶段流水线拆解极其专业**——从 text normalization 到 layout cache，颗粒度恰当，每阶段都明确了输入/输出/约束。这在业界同类分析中属于上乘水准。
2. **技术选型表务实**——没有盲目推荐自研，而是明确标注了每项技术的边界和风险。
3. **代价表极其诚实**——shaping 等效替代标注为"6 月以上 / 无法保守估计"，这是正确的判断。很多团队在这里犯的错误恰恰是低估复杂度。
4. **三阶段路线图 (A → B → C) 清晰可执行**。

### 我的补充意见

| 阶段 | 文档建议 | 我的补充 |
|------|----------|----------|
| segmentation | ICU / ICU4X | MoonBit 编译到 WASM-GC 后，直接调 ICU4X 的 WASM 绑定可能存在 ABI 不匹配。建议先验证 `harfbuzzjs` + `fontkit` 在 MoonBit JS backend 上的集成可行性 |
| shaping | HarfBuzz / harfbuzzjs | 完全同意。但建议在 v1 阶段直接走浏览器 `measureText` + prefix cache 的方案，不要过早引入 HarfBuzz |
| line break | linebreak JS 库 | 对于编辑器场景，v1 可以走更简化的路线：按空格/CJK 字符边界断行，连 `linebreak` 库都可以延后 |
| 阶段 A | LTR + Latin/CJK | 这个收窄非常正确。后续文档已经进一步收敛为：v1 **做基础 wrap**，而不是 no-wrap |

### 关键建议

> [!TIP]
> 这条判断仍然成立，但当前更准确的落点已经写入 `text-v1.md`：以 `Intl.Segmenter + measureText + PrefixWidthCache + ParagraphLayout` 先跑通几何闭环。

---

## 五、CSS 布局属性参考 (css-layout-property.md) 分析

这是一份纯工具性文档，列举了 CSS 中影响布局的属性分类。

### 用途判断

- 它的价值在于辅助 `discuss-multiview` 中提到的"区分 Core 负责的关键几何 vs CSS 负责的非关键外观"。
- 但当前文档缺少 **MetaEditor 视角的标注**——哪些属性应被 Core 接管、哪些保留给 CSS。

### 建议

在每个分类后增加一列标注，例如：

- §1 盒模型：`width/height` → Core 负责关键容器；`margin/padding` → 可保留 CSS
- §4 Flex：Core 应实现简化版 flex（单轴 + gap）
- §6 文本排版：Core 必须接管 `font-size`、`line-height`（影响测量）；`letter-spacing` 等可延后

---

## 六、TODO 清单 (todo.md) 分析

### 现状

6 大类共 17 个子项，**全部 `[ ]` 未启动**。

### 优先级建议

根据前面的分析，以下项应被标为 **P0**（阻塞核心闭环）：

| 项 | 理由 |
|----|------|
| §1 紧凑协议优化 | Bridge 协议是 Core ↔ Projector 通讯的基础 |
| 文本测量 V1 | 这是当前最短主路径 |
| 关键布局上收 Core | 不做就无法推进 Probe 与结构化验证 |

以下项应降级为 **P2**（可延后）：

| 项 | 理由 |
|----|------|
| Shadow DOM 支持 | 编辑器场景不急需 |
| MCP 协议对接 | 等 Core 稳定后再接 AI 工具链 |
| LSP 语义回响 | 属于进阶特性 |

---

## 七、跨文档一致性问题

| 问题 | 涉及文档 | 建议 |
|------|----------|------|
| 运行模型矛盾 | `design.md` §2.5 vs `discuss-multiview` §12-13 | 更新 `design.md` 至最终收敛版本 |
| 无头可测性 vs 客户端 view 生成 | `design.md` §2.1 vs `discuss-multiview` §6-8 | 明确 Core 持有关键布局真相 |
| 文本测量未被链接 | `text-measuring.md` vs `discuss-multiview` §8 | 在 `design.md` 增加"关键布局依赖文本测量"的说明 |
| TODO 清单已偏移 | `todo.md` | 按文本测量 V1 与关键布局上收 Core 的主路径重写 |

---

## 八、总评

### 文档体系成熟度：★★★★☆

这套文档在**问题意识**和**技术判断**上都达到了很高水准。特别是：

- `discuss-multiview` 的辩证式讨论纪要
- `text-measuring` 的技术栈深度分析

这两份文档单独拿出来，都可以作为编辑器架构分析的范本。

### 最大短板

> [!CAUTION]
> 这条短板后来已经由 [text-v1.md](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/text-v1.md) 弥补，因此这里保留为历史说明，不再作为当前缺口。

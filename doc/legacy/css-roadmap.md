# MetaEditor CSS 引擎路线图（框架稿）

这份文档不是当前主路线文档，而是一份出于技术兴趣保留的长期计划书框架。

目标是回答这个问题：

> 如果我们要自己实现一套完整 CSS 引擎，需要解决哪些问题、需要哪些概念与机制、合理的实现路径应该怎样分期展开。

这份文档当前只先建立大框架，后续再逐节填充细节。

## 1. 文档目标与边界

### 1.1 目标

- 梳理完整 CSS 引擎所涉及的问题域
- 将 CSS 属性映射到背后的布局/样式/渲染机制
- 明确每类机制的实现难点、依赖关系与工程阶段
- 为“从简化布局系统逐步逼近完整 CSS”提供一条长期路线图

### 1.2 不关注的内容

- 类型设计
- 具体 API 设计
- 当前 MetaEditor 主路线是否采用该方案
- 具体代码结构

### 1.3 关注的内容

- CSS 各类能力背后的概念模型
- 解析、级联、布局、绘制、命中、滚动、动画等机制之间的关系
- 每类 CSS 属性真正依赖的底层机制
- 完整实现一套 CSS 引擎的大致分期路径

## 2. 总体问题分层

一个完整 CSS 引擎至少要拆成下面几层：

1. CSS 源码解析
2. 选择器匹配
3. Cascade 与优先级
4. 值系统与 computed value
5. 格式化结构树
6. 布局系统
7. 文本排版与 inline formatting
8. 滚动、溢出与裁剪
9. 绘制与层叠
10. 命中测试与交互
11. 动画与过渡
12. 宿主集成与浏览器环境适配

后续每一层都要单独展开。

## 3. 从输入到输出的完整流水线

先给出全局流水线，后面各节再细化：

1. 解析 HTML / DOM / 自定义视图树
2. 解析 CSS 样式源
3. 匹配选择器
4. 计算 cascade 结果
5. 解析并归一化属性值
6. 建立格式化结构树 / formatting tree
7. 执行布局
8. 生成绘制指令或 display list
9. 执行绘制
10. 处理 hit-test / 交互 / 滚动 / 动画

每一步后续都应该补：

- 输入
- 输出
- 依赖
- 最小可用子集
- 完整行为的复杂度来源

## 4. 核心概念总表

这节后续要展开完整术语表，至少包括：

- DOM tree
- style rule
- selector
- specified value
- computed value
- used value
- actual value
- formatting context
- containing block
- box tree
- line box
- stacking context
- containing block
- scroll container
- overflow clip edge
- intrinsic size
- min-content / max-content
- anonymous box
- replaced element
- fragmentation

## 5. CSS 属性到机制的映射方式

后续整份文档会反复使用下面这个映射视角：

- 一个 CSS 属性不等于一个独立功能
- 一个属性通常依赖多个底层机制
- 同一底层机制通常支撑很多属性

因此后续每类属性都应该回答：

1. 它影响哪一层
2. 它需要哪些概念
3. 它依赖哪些前置机制
4. 它与哪些其他属性强耦合

## 6. 第一大块：样式系统本身

### 6.1 CSS 源码解析

后续要展开：

- tokenization
- 规则集解析
- at-rule
- declaration list
- 错误恢复
- 注释与空白处理

### 6.2 选择器系统

后续要展开：

- 简单选择器
- 组合器
- 伪类
- 伪元素
- attribute selector
- specificity
- 动态状态选择器

### 6.3 Cascade 机制

后续要展开：

- origin
- importance
- specificity
- source order
- inheritance
- initial value
- revert / unset / inherit / initial

### 6.4 值系统

后续要展开：

- keyword
- length
- percentage
- color
- calc
- ratio
- angle
- time
- transform function
- font shorthand
- background shorthand

## 7. 第二大块：盒模型与格式化结构

### 7.1 盒模型

后续要展开：

- content box
- padding box
- border box
- margin box
- box-sizing

### 7.2 box tree / formatting tree

后续要展开：

- DOM tree 到 box tree 的映射
- display 如何影响 box 生成
- anonymous box
- replaced element
- inline / block / inline-block 的结构差异

### 7.3 containing block

后续要展开：

- 正常流中的 containing block
- absolute / fixed / sticky 的 containing block
- 百分比尺寸依赖关系

## 8. 第三大块：正常文档流布局

### 8.1 block formatting context

后续要展开：

- block box 垂直流
- margin collapsing
- width auto 计算
- shrink-to-fit 相关边界
- float / clear 对 BFC 的影响

### 8.2 inline formatting context

后续要展开：

- inline box
- line box
- baseline
- vertical-align
- 文本与 inline 混排
- 行高协调

### 8.3 float / clear / BFC 触发条件

### 8.4 绝对定位与脱流

后续要展开：

- position: relative
- absolute / fixed / sticky
- inset / top / right / bottom / left
- z-index 与 stacking context 的关系

## 9. 第四大块：现代布局系统

### 9.1 flex 布局

后续要展开：

- flex formatting context
- main axis / cross axis
- flex base size
- grow / shrink
- align / justify
- wrap
- gap
- intrinsic size 参与 flex 计算

### 9.2 grid 布局

后续要展开：

- track sizing
- explicit / implicit grid
- auto placement
- spanning
- minmax
- fr 单位
- 内容反向影响轨道尺寸

### 9.3 多列布局

### 9.4 fragmentation

## 10. 第五大块：尺寸系统与 intrinsic sizing

这会是最难的一块之一，后续要展开：

- width / height / min / max
- auto
- percentage
- aspect-ratio
- min-content
- max-content
- fit-content
- shrink-to-fit
- replaced element intrinsic size
- contain-intrinsic-size

## 11. 第六大块：文本排版系统

这是另一块最难的核心，后续要展开：

- font matching
- font fallback
- shaping
- bidi
- line break
- whitespace
- word-break
- overflow-wrap
- line-height
- letter-spacing
- text-indent
- writing-mode
- vertical text

这部分和单独的文本测量文档会有强重叠，但这里要从 CSS 引擎视角来写。

## 12. 第七大块：滚动、溢出与裁剪

后续要展开：

- overflow
- scroll container
- clipping
- scrollbar
- scroll snapping
- scroll origin
- sticky 与 scroll 的耦合
- transform 对滚动与命中的影响

## 13. 第八大块：绘制系统

### 13.1 display list / paint order

### 13.2 background / border / outline

### 13.3 box-shadow / filter / opacity

### 13.4 transform

### 13.5 stacking context

### 13.6 compositing

这部分后续要回答：

- 什么属性只影响绘制，不影响布局
- 什么属性会反过来影响命中测试与滚动

## 14. 第九大块：命中测试与交互

后续要展开：

- pointer hit test
- z-order 命中
- transformed element hit testing
- text caret hit testing
- selection geometry
- focus navigation
- pointer-events

## 15. 第十块：动画、过渡与时间系统

后续要展开：

- transition
- animation
- keyframes
- timing function
- interpolation
- layout-affecting animation
- composited animation

## 16. 属性分类大纲

后续会把 CSS 属性按机制重新分组，不按规范目录平铺。至少包括：

### 16.1 盒模型属性

- `width`
- `height`
- `min-width`
- `max-width`
- `padding*`
- `border*`
- `margin*`
- `box-sizing`
- `aspect-ratio`

### 16.2 文档流与 display

- `display`
- `visibility`
- `float`
- `clear`
- `overflow*`

### 16.3 定位与层叠

- `position`
- `top/right/bottom/left`
- `z-index`
- `inset*`

### 16.4 flex 属性

- `flex`
- `flex-grow`
- `flex-shrink`
- `flex-basis`
- `flex-direction`
- `flex-wrap`
- `justify-content`
- `align-items`
- `align-content`
- `align-self`
- `order`
- `gap`

### 16.5 grid 属性

- `grid-template-*`
- `grid-auto-*`
- `grid-row*`
- `grid-column*`
- `grid-area`
- `place-*`

### 16.6 文本排版属性

- `font-*`
- `line-height`
- `letter-spacing`
- `word-spacing`
- `white-space`
- `word-break`
- `overflow-wrap`
- `line-break`
- `tab-size`
- `text-indent`
- `text-transform`
- `direction`
- `writing-mode`
- `text-orientation`
- `vertical-align`

### 16.7 绘制属性

- `color`
- `background*`
- `border-radius`
- `box-shadow`
- `opacity`
- `filter`
- `clip-path`

### 16.8 滚动与视口属性

- `scroll-snap-*`
- `scroll-margin*`
- `scroll-padding*`
- `scrollbar-gutter`
- `overflow-anchor`

### 16.9 包含与隔离

- `contain`
- `content-visibility`
- `contain-intrinsic-size`
- `container-*`

## 17. 每类属性未来要补的分析模板

后续每一类属性都按同一模板填：

1. 语义是什么
2. 影响哪一层
3. 依赖哪些前置机制
4. 与哪些属性强耦合
5. 最小可用实现怎么做
6. 完整行为为什么难
7. 适合在哪个阶段实现

## 18. 实现阶段大纲

这里只列大阶段，后续再细化。

### Phase A：极简样式系统

目标：

- 支持最基础的样式解析
- 不做完整 cascade
- 不做复杂 selector
- 支持少量盒模型与绘制属性

### Phase B：基础布局引擎

目标：

- block / inline 基础布局
- 绝对定位
- 基础文本排版
- 基础 overflow

### Phase C：编辑器可用布局

目标：

- flex 单轴
- 简化 intrinsic size
- 文本命中与 selection
- 滚动容器

### Phase D：通用 UI 布局

目标：

- 更完整 flex
- 基础 grid
- stacking context
- transform / opacity / clipping

### Phase E：逼近浏览器行为

目标：

- 更完整 intrinsic sizing
- 更完整 formatting context
- 更复杂文本排版
- 更多 CSS 属性兼容

## 19. 依赖图大纲

后续这里要补一张机制依赖图，至少体现：

- selector / cascade 在 layout 前
- text shaping 在 inline formatting 前
- intrinsic size 参与 flex / grid
- overflow / clipping 依赖布局结果
- hit-test 依赖布局与绘制结果
- animation 会反向影响布局或绘制

## 20. 最困难的三大问题

后续详细写，但先占位：

1. 文本排版系统
2. intrinsic sizing 与尺寸协商
3. formatting context / box tree 的完整语义

## 21. 与浏览器 oracle 的关系

后续详细写，但先占位：

- Playwright / 浏览器引擎可作为真值来源
- 可用于生成回归样例
- 可用于验证具体属性组合行为
- 不能替代机制建模本身

## 22. 与 MetaEditor 主路线的关系

这份文档当前放在 `legacy/`，意味着：

- 它不是 MetaEditor 当前执行主线
- 当前主线仍然是浏览器主运行时 + 结构化 CLI 接口
- 但如果未来再次回到“自持布局 / 自持样式系统”的方向，这份路线图可以作为长期计划书的骨架

## 23. 后续填充顺序建议

建议后续按这个顺序逐章填细节：

1. 第 18 节实现阶段大纲
2. 第 16 节属性分类
3. 第 8 节正常文档流布局
4. 第 9 节现代布局系统
5. 第 10 节 intrinsic sizing
6. 第 11 节文本排版系统
7. 第 13 节绘制系统
8. 第 14 节命中测试与交互
9. 第 15 节动画与时间系统
10. 第 21 节浏览器 oracle

## 24. 当前状态

当前这份文档只是骨架稿。

下一步不应该继续加零散想法，而应该按章节成批填充，每次只完整解决一个主题，例如：

- “只填 flex + 相关尺寸机制”
- “只填 inline formatting + 文本排版”
- “只填 stacking context + paint order”

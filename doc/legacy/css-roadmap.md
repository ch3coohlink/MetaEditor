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

这一层解决的问题不是“把字符串拆出来”这么简单，而是建立一套后续所有样式系统都能依赖的**稳定语法输入层**。

如果这一层做得草率，后面 cascade、值系统、错误恢复都会失真。

#### 需要解决的问题

- tokenization：把原始字符流切成 token
- rule parsing：把 token 组装成 rule / declaration / selector
- at-rule parsing：识别 `@media`、`@supports`、`@keyframes`、`@font-face` 等
- declaration list parsing：解析属性与值
- block nesting：处理 `{ ... }` 结构与嵌套上下文
- error recovery：在非法 token、缺失分号、缺失右括号等情况下继续向前
- trivia handling：注释、空白、换行对语义和位置信息的影响

#### 关键概念

- token stream
- component value
- simple block
- function token
- qualified rule
- at-rule
- declaration
- parse error

#### 实现上真正麻烦的点

1. CSS 不是“读到分号就完了”的语言。
   同一个值内部可能含有：
   - 函数
   - 逗号分组
   - 嵌套括号
   - url / string / calc 表达式

2. 它的错误恢复非常重要。
   浏览器之所以看起来“很宽容”，并不是因为随便忽略，而是因为解析器内置了很多恢复规则。

3. 解析结果不仅要能“读”，还要能：
   - 保留源位置信息
   - 支持后续重序列化
   - 支持调试和开发工具

#### 最小可用子集

如果只做最小版本，可以先只支持：

- style rule
- declaration list
- 少量 at-rule 直接跳过但保留块结构
- 注释和空白忽略
- 宽松错误恢复

也就是先做到：

- 能把一段普通样式表解析成 rules
- 即使遇到少量坏样式也不至于整份中断

#### 完整行为为什么难

- CSS 解析规范本身就分成 tokenization 和 parser 两段
- 不同 at-rule 语法差异很大
- 自定义属性、函数值、嵌套 block 会把“简单 parser”迅速变复杂

### 6.2 选择器系统

选择器系统是 style rule 变成“匹配到哪些元素”的桥梁。没有它，CSS 只是一个无目标的属性集合。

#### 需要解决的问题

- 简单选择器：
  - type
  - class
  - id
  - universal
- 组合器：
  - descendant
  - child
  - adjacent sibling
  - general sibling
- attribute selector
- 伪类
- 伪元素
- selector list
- specificity 计算
- 动态状态选择器的匹配更新

#### 关键概念

- simple selector
- compound selector
- complex selector
- selector list
- specificity tuple
- dynamic selector dependency

#### 实现上真正麻烦的点

1. 匹配方向不是直觉上的从左到右，而通常要从右到左优化。
   因为：
   - 先找到候选目标元素
   - 再回溯祖先或兄弟关系
   会比正向扫描整棵树高效得多。

2. 伪类里有一大批不是静态匹配。
   例如：
   - `:hover`
   - `:focus`
   - `:active`
   - `:checked`
   - `:disabled`

   这意味着选择器匹配系统不能只在初始阶段跑一次，而要和交互状态变化联动。

3. 某些选择器会强依赖结构位置：
   - `:first-child`
   - `:last-child`
   - `:nth-child()`
   - `:empty`

   这会要求 DOM / box tree 变化时进行增量失效。

#### 最小可用子集

最小可用版本可以只支持：

- type / class / id
- descendant / child
- 少量状态伪类
- selector list
- specificity

先不碰：

- 复杂 attribute selector
- `nth-*`
- 高级结构伪类
- 复杂伪元素

#### 完整行为为什么难

- 选择器不是只影响匹配，还影响失效策略
- 完整支持所有伪类后，选择器系统会和状态系统、树更新系统、布局失效系统强耦合

### 6.3 Cascade 机制

Cascading 是 CSS 的核心，不是附属功能。真正让 CSS 变成 CSS 的，不是属性有多少，而是多个来源的规则如何合并。

#### 需要解决的问题

- origin：
  - user-agent
  - user
  - author
- importance：`!important`
- specificity
- source order
- inheritance
- initial value
- special keywords：
  - `inherit`
  - `initial`
  - `unset`
  - `revert`
  - `revert-layer`
- layer / scope（如果要追现代 CSS）

#### 关键概念

- cascade candidate set
- winning declaration
- inherited property
- non-inherited property
- initial value table
- cascade layer

#### 实现上真正麻烦的点

1. Cascade 不是简单排序。
   需要同时考虑：
   - origin
   - importance
   - specificity
   - source order

2. inherited 和 non-inherited 属性行为完全不同。
   这意味着 computed value 计算必须知道每个属性的元信息。

3. `inherit / initial / unset / revert` 会让普通的“最后一个覆盖前面”模型失效。
   这类 keyword 会把当前属性的求值重新拉回更高层语义。

#### 最小可用子集

可以先支持：

- author origin
- specificity
- source order
- inheritance
- `inherit / initial / unset`

先不支持：

- user origin
- `revert` / `revert-layer`
- cascade layers

#### 完整行为为什么难

- 完整 cascade 需要每个属性都带元信息
- 一旦加上 layer / revert / scoped styles，系统复杂度会显著抬升

### 6.4 值系统

值系统的难点不在“有多少种 token”，而在：

- 值怎么解析成内部表示
- 什么阶段才把它求成 computed value
- 百分比到底依赖谁
- 哪些 shorthand 要展开成 longhand

#### 需要解决的问题

- keyword
- numeric value
- length
- percentage
- color
- angle
- time
- ratio
- image / url
- calc / min / max / clamp
- transform function list
- shorthand 展开：
  - `margin`
  - `padding`
  - `border`
  - `font`
  - `background`
  - `flex`

#### 关键概念

- parsed value
- specified value
- computed value
- used value
- percentage basis
- unresolved relative value
- shorthand expansion

#### 实现上真正麻烦的点

1. 很多值在 parse 阶段不能立刻算完。
   例如：
   - `%`
   - `em`
   - `rem`
   - `line-height: normal`
   - `calc(100% - 20px)`

2. shorthand 不是简单语法糖。
   展开时要处理：
   - 缺省值
   - 重置未显式出现的 longhand
   - 特定属性的特殊语义

3. 有些属性值实际上是小语言。
   例如：
   - `transform`
   - `grid-template`
   - `background`
   - `font`

#### 最小可用子集

最小版本可以只支持：

- keyword
- px / number
- percentage
- color
- 少量简化 shorthand

并把：

- `calc`
- 复杂 `font`
- 复杂 `background`
- 复杂 `transform`

延后。

#### 完整行为为什么难

- 值系统几乎和所有后续层都有关系
- 如果一开始内部表示设计差了，后面 intrinsic sizing、布局、动画、插值都会被拖垮

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

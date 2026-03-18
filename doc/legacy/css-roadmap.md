# MetaEditor CSS 引擎路线图

这份文档不是当前主路线文档，而是一份出于技术兴趣保留的长期计划书框架。

目标是回答这个问题：

> 如果我们要自己实现一套完整 CSS 引擎，需要解决哪些问题、需要哪些概念与机制、合理的实现路径应该怎样分期展开。

这份文档按机制分层组织，用来描述完整 CSS 引擎需要解决的问题、概念和实现路径。

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

下面每一层都对应独立的问题域。

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

每一步都适合从下面几个角度展开：

- 输入
- 输出
- 依赖
- 最小可用子集
- 完整行为的复杂度来源

## 4. 核心概念总表

这节至少应包含下面这些核心术语：

- **DOM tree**
  表示文档结构和节点关系的逻辑树。它是样式匹配和语义组织的起点，但通常不是最终参加布局和绘制的结构。

- **style rule**
  由 selector 和 declaration 组成的样式规则。它描述“谁匹配”和“匹配后给什么属性值”。

- **selector**
  用来从 DOM tree 中选出候选元素的匹配表达式。它不仅影响匹配结果，也影响样式失效策略和性能。

- **specified value**
  属性在 cascade 之后得到的规范层输入值，仍然可能包含未解析的相对量、关键字或待求值表达式。

- **computed value**
  属性经过继承、默认值补全和一部分规范化后的结果。它通常是样式系统向布局与绘制系统交付的稳定接口。

- **used value**
  属性在结合布局上下文、containing block、百分比基准等信息后，真正用于布局计算的值。

- **actual value**
  引擎和设备最终实际采用的值。它可能与 used value 有细微差异，例如受像素对齐、字体后备或设备能力限制。

- **formatting context**
  一组布局规则的局部世界，例如 block formatting context、inline formatting context、flex formatting context。它决定子内容如何参与布局。

- **containing block**
  为定位和百分比计算提供参考矩形的概念。很多“这个值到底相对谁算”的问题，本质上都在问 containing block。

- **box tree**
  从 DOM 和样式结果派生出的布局结构树。它比 DOM 更接近引擎真正排版和绘制时使用的对象。

- **line box**
  inline formatting context 中承载一行内容的布局实体。它聚合文本、inline box、replaced element 等行内片段。

- **stacking context**
  局部绘制顺序和 z-order 的边界。它让绘制顺序不是简单的全局排序，而是嵌套的局部世界组合。

- **scroll container**
  具有可滚动内容区域和滚动偏移的容器。它引入 scrollport、scroll offset 和新的坐标参考。

- **overflow clip edge**
  内容被裁剪时的可见边界。它可能由 overflow、border radius、clip-path 或 compositing 边界共同决定。

- **intrinsic size**
  元素由其内容和内部规则自然决定的尺寸倾向，而不是由外部明确指定的尺寸。

- **min-content / max-content**
  intrinsic sizing 中最常见的两类内容尺寸极值。它们是 flex、grid、多列等布局算法做尺寸协商时的重要输入。

- **anonymous box**
  不是由显式 DOM 节点直接声明，而是为了满足布局规则自动生成的盒子。它常见于 inline / block 混排、列表和 table 相关结构。

- **replaced element**
  其内部内容和尺寸语义不完全由普通 CSS 盒模型决定的元素，例如图片、视频、表单控件等。

- **fragmentation**
  一个逻辑布局对象被切分到多个片段容器中的机制。多列、分页、打印和跨页排版都依赖它。

这些术语看似只是词汇表，但它们实际上是整份文档的概念骨架。只要这些词的边界不稳，后面每一章都会开始混淆。

## 5. CSS 属性到机制的映射方式

整份文档会反复使用下面这个映射视角：

- 一个 CSS 属性不等于一个独立功能
- 一个属性通常依赖多个底层机制
- 同一底层机制通常支撑很多属性

因此每类属性都应该回答：

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

盒模型是所有布局和绘制讨论的最低层几何前提。很多 CSS 属性表面上像是在“改尺寸”，本质上是在这些盒边界之间切换约束关系。

- content box
- padding box
- border box
- margin box
- box-sizing

#### 需要解决的问题

- 各层盒边界的几何定义
- padding / border / margin 如何叠加到最终外部尺寸
- `box-sizing` 如何改变宽高属性的解释方式
- 哪些绘制和命中行为基于哪一层盒边界

#### 为什么它重要

- layout 通常围绕 content box 或 border box 计算
- background / border / outline / clipping 依赖不同盒边界
- scrollable overflow、hit-test、selection decoration 也常以不同边界为参照

#### 路线判断

- 最小可用系统必须先把 content/padding/border/margin 四层几何说清楚
- 如果这层概念模糊，后面的尺寸系统、绘制系统、overflow 系统都会反复返工

### 7.2 box tree / formatting tree

真正参加布局与绘制的结构通常不是 DOM tree 本身，而是由样式语义派生出来的 box tree 或 formatting tree。

这一步的意义，在于把“文档结构”转成“布局结构”。

- DOM tree 到 box tree 的映射
- display 如何影响 box 生成
- anonymous box
- replaced element
- inline / block / inline-block 的结构差异

#### 需要解决的问题

- 哪些节点生成 box，哪些节点不直接生成 box
- 一个元素会生成一个 box 还是多个 fragment / box
- `display` 如何改变 box 类型与参与的 formatting context
- anonymous box 在什么条件下生成
- replaced element、伪元素、列表标记如何进入布局结构

#### 关键复杂度来源

1. DOM tree 和 box tree 不是一一对应。
2. 某些元素可能不生成普通 box，但其子内容仍需要进入布局。
3. inline 内容、匿名块盒、列表标记会让结构转换远比“每个节点一个矩形”复杂。

#### 路线判断

- 最小版本可以先做接近一对一的 box tree
- 但一旦需要兼容真实 CSS 语义，就必须显式建模 anonymous box、replaced element 和 formatting context 边界
- 这是后续 block / inline / flex / grid 都共享的前置层

### 7.3 containing block

containing block 是很多 CSS 计算的参考坐标系。它不是一个“附带概念”，而是决定定位和百分比尺寸如何落地的关键机制。

它最常见的作用有两类：

- 为定位元素提供参考矩形
- 为百分比值提供尺寸基准

#### 需要解决的问题

- 正常流中的 containing block 如何确定
- absolute / fixed / sticky 的参考块如何变化
- transform、scroll container、fragmentation 是否改变参考系
- 百分比宽高、百分比 inset、百分比 padding / margin 依赖哪个 containing block

#### 为什么它难

- 不同布局模式下，containing block 的来源并不相同
- 定位语义和尺寸百分比语义常共享这个概念，但边界并不完全一致
- transform、positioned ancestor、viewport、scrollport 会一起改变参考系判断

#### 路线判断

- 最小可用实现至少要明确：
  - 正常流 block 的 containing block
  - absolute positioning 的 containing block
  - 百分比宽度的解析基准
- 如果这一层没先说清楚，后面的 absolute、sticky、overflow、transform 都会变成局部特判

## 8. 第三大块：正常文档流布局

### 8.1 block formatting context

这是“正常网页为什么默认会一块一块往下排”的核心机制之一。很多看似基础的 block 布局规则，真正复杂度都在这里。

#### 需要解决的问题

- block box 的垂直流布局
- width auto 的求值
- 横向可用空间的确定
- margin collapsing
- BFC 的建立条件
- float / clear 对正常流的影响
- overflow / flow-root / absolute / inline-block 等对 BFC 的触发关系

#### 关键概念

- block formatting context
- in-flow block
- out-of-flow element
- available inline size
- used block size
- collapsed margin set
- clearance

#### 机制拆分

1. **块级正常流**
   - 块级盒子在竖直方向依次排布
   - 每个盒子的最终宽度依赖 containing block 的可用宽度
   - 高度通常由内容反向撑开

2. **margin collapsing**
   - 相邻 block box 的垂直 margin 不是简单相加
   - 父子之间、空块、自身上下 margin 都可能发生 collapse
   - 这是很多“看起来很基础但非常反直觉”的布局行为来源

3. **BFC 隔离**
   - 某些盒子会创建新的 BFC
   - 一旦进入新 BFC，内部 block 排布、float 影响范围、margin collapse 行为都会变化

4. **clearance**
   - `clear` 不是独立布局系统，而是正常流块级布局对 float 的修正规则

#### 实现上真正麻烦的点

1. margin collapsing 不是局部二元规则，而像一个沿树传播的合并过程。
2. block 宽度虽然看起来简单，但 `auto`、百分比、min/max、scrollbar、padding/border 都会影响最终可用空间。
3. BFC 一旦引入，就不能只在单个节点局部判断，而要影响整个子树的布局语义。

#### 最小可用子集

如果是最小版本，可以先支持：

- 普通 block 垂直流
- 不做完整 margin collapsing，先按“相邻兄弟 collapse”简化
- 支持 `display: block`
- 支持 BFC 的最小触发集合：
  - `overflow != visible`
  - `display: flow-root`
  - `position: absolute`

先不碰：

- 完整父子 margin collapse
- 浮动与 clear 的全语义
- shrink-to-fit 边界行为

#### 完整行为为什么难

- BFC 是很多布局行为的交叉点
- 一旦这里做错，后面 containing block、float、sticky、overflow 全都会偏

### 8.2 inline formatting context

这是另一块难度被严重低估的基础机制。浏览器里“普通一行文本和几个 inline 元素混在一起排”背后靠的就是它。

#### 需要解决的问题

- inline box 的生成
- inline fragment 在多行中的切分
- line box 构建
- baseline 对齐
- `vertical-align`
- 文本 run 与 inline element 混排
- 行高协调
- 空白折叠

#### 关键概念

- inline formatting context
- inline box
- line box
- line fragment
- baseline
- ascent / descent
- leading
- anonymous inline box

#### 机制拆分

1. **inline content 不是简单横向拼接**
   - 它首先要被分解成可放进行盒的 fragment
   - 然后在每一行里决定能放多少内容
   - 再生成 line box

2. **line box 是真实布局实体**
   - 一行的高度不是单个文本节点决定的
   - 它依赖这一行里所有 inline 内容的 ascent / descent / line-height 协商

3. **baseline 对齐是核心**
   - 文本、inline-block、图片、不同字号元素混排时，要基于 baseline 对齐
   - 这就是为什么 inline formatting context 和文本排版系统高度耦合

4. **跨行 fragment**
   - 同一个 inline box 在换行后会被拆成多个 fragment
   - 这要求 box tree 和真正 layout tree 不再是一一对应

#### 实现上真正麻烦的点

1. 这层和文本 shaping / line break 直接耦合，无法独立实现得很完整。
2. 行高不是简单 max(height)，而和 baseline、leading、vertical-align 都有关系。
3. inline element 混排时，文本、盒子、替换元素的度量来源不一致。

#### 最小可用子集

最小版本可以先只支持：

- 纯文本 inline
- 少量 inline element
- 不支持复杂 baseline 协商
- 不支持复杂 `vertical-align`
- 不支持 replaced element 的精细行为

也就是先做到：

- 文本能换行
- 文本和少量行内盒子能共存
- line box 有基础高度与基线

#### 完整行为为什么难

- 真正完整的 inline formatting context，几乎天然要求你已经有：
  - 文本排版系统
  - baseline 系统
  - fragment tree
  - 行内命中测试系统

### 8.3 float / clear / BFC 触发条件

这一节值得单独深化，因为 float 不只是旧特性，它会深度扰动正常流布局。

#### 需要展开的问题

- float box 如何脱离正常流但仍影响 line box
- clear 如何重新定位 block 起点
- float 对 BFC 的影响边界
- float 参与可用宽度计算的方式

#### 关键概念

- float formatting interaction
- float area
- available line width
- float avoidance
- clearance
- block formatting context boundary

#### 机制拆分

1. **float 的脱流方式**
   - float 脱离普通 block 正常流定位序列
   - 但它不像 absolute 那样完全不影响周围内容
   - 它仍然会压缩后续 block 和 line box 的可用空间

2. **文本绕排**
   - inline formatting context 需要感知当前行在该垂直位置上还能使用多少水平空间
   - 这意味着 line box 构建不能只看 containing block，还要看浮动占据的区域

3. **clearance 重新定位**
   - `clear` 的作用不是简单加 margin
   - 它要求后续 block 起点避开前面相关方向的 float
   - 这会改变 block 起始位置和后续 margin collapse 结果

4. **BFC 隔离**
   - 新 BFC 通常会阻止外部 float 继续影响内部布局
   - 这也是为什么 `overflow`、`flow-root` 等机制会间接改变 float 行为

#### 关键复杂度来源

- float 不完全等于 absolute
- 它既脱离正常流，又会压缩周围文本与 block 可用空间
- 它和 inline formatting context 是强耦合的

#### 最小可用子集

最小版本可以先只支持：

- 左右浮动
- 文本和简单 block 对 float 的避让
- `clear: left | right | both`
- 用矩形 float area 简化计算

先不碰：

- 复杂 fragmentation 下的 float
- 非矩形绕排
- 与 writing-mode 结合后的更多边界
- 过于精细的 margin collapse + clearance 联动

#### 完整行为为什么难

- 它横跨 block formatting、inline formatting、available width 计算三个系统
- 一个 float 的影响不是局部节点，而是会延续到后续多行、多块内容
- `clear`、BFC、overflow、fragmentation 一旦叠加，行为很容易偏离浏览器

#### 路线判断

- 如果目标是编辑器或通用 UI，float 可以显著后置
- 但如果目标是网页级兼容，float 不能永远跳过，因为它会暴露正常流和 inline formatting 是否真的建模正确
- 比较稳的路线通常是：
  1. 先用最简矩形 float + 文本绕排建立机制
  2. 再补 `clear` 与 BFC 边界
  3. 最后再处理复杂 fragmentation 与细碎边界

### 8.4 绝对定位与脱流

脱流定位是正常流布局之外的另一套定位系统，但它并不是完全独立的，它大量依赖正常流先给出 containing block 和静态位置参考。

#### 需要解决的问题

- `position: relative`
- `position: absolute`
- `position: fixed`
- `position: sticky`
- inset 计算
- static position
- containing block 的确定
- positioned element 与 stacking context 的关系

#### 关键概念

- positioned element
- static position
- inset resolved values
- containing block
- scrollport
- sticky constraint rectangle

#### 机制拆分

1. **relative**
   - 仍然参与正常流
   - 只是最后绘制位置相对原位偏移

2. **absolute**
   - 脱离正常流
   - 但尺寸和位置仍依赖 containing block
   - static position 常被用作缺省参考

3. **fixed**
   - 类似 absolute，但参考系通常是 viewport 或特定 containing block

4. **sticky**
   - 最麻烦，因为它是正常流与滚动约束的混合物
   - 在未触发粘附前像正常流
   - 触发后又表现出类似定位元素的偏移

#### 最小可用子集

最小版本可以先支持：

- relative
- absolute
- fixed

先不支持或弱化：

- sticky
- 复杂 static position 推导
- 复杂百分比尺寸相对 containing block 的边界情况

#### 完整行为为什么难

- 它依赖 containing block 系统
- 又与 scroll、stacking context、z-index、overflow 裁剪互相耦合

## 9. 第四大块：现代布局系统

### 9.1 flex 布局

flex 是现代 UI 布局里最常见的一套机制，但它的实现复杂度远比“主轴排一排”大。真正难的是尺寸协商。

#### 需要解决的问题

- flex formatting context
- main axis / cross axis
- item 收集与匿名 item 规则
- flex base size
- hypothetical main size
- grow / shrink
- free space distribution
- min/max constraint
- align / justify
- wrap
- gap
- intrinsic size 参与 flex 计算

#### 关键概念

- flex container
- flex item
- flex base size
- hypothetical main size
- free space
- flex factor
- frozen item
- line packing

#### 机制拆分

1. **先确定 item 的初始主轴尺寸**
   - 这一步不只是读 `flex-basis`
   - 还可能回落到 width / height / intrinsic size / content size

2. **把 item 分到 flex lines**
   - `nowrap` 时是一条线
   - `wrap` 时要按主轴尺寸分行

3. **对每一行进行 free space 分配**
   - grow 时扩大
   - shrink 时缩小
   - 同时受 min/max 约束
   - 被约束的 item 可能冻结，再重新分配剩余空间

4. **再处理交叉轴对齐**
   - `align-items`
   - `align-self`
   - `align-content`
   - `stretch`

#### 实现上真正麻烦的点

1. flex 难点不在 axis 概念，而在“尺寸先猜一个，再迭代约束修正”的过程。
2. min-content / max-content / auto size 一旦参与进来，flex 就和 intrinsic sizing 紧紧绑在一起。
3. wrap 之后其实变成“两层布局”：
   - 先行内分配
   - 再行间分配

#### 最小可用子集

最小版本可以先支持：

- 单轴 flex
- 不支持复杂 intrinsic size
- `flex-grow`
- `flex-shrink`
- `justify-content`
- `align-items`
- `gap`
- 可选的简单 `wrap`

先不碰：

- 复杂 min-content / max-content
- 复杂 baseline alignment
- 非常完整的 `align-content`

#### 完整行为为什么难

- 它不是单轮计算，而像受约束的尺寸求解
- 一旦和文本 intrinsic size、百分比尺寸、min/max 混合，行为会迅速复杂化

### 9.2 grid 布局

grid 的本质不是“二维 flex”，而是一套轨道系统。它最难的地方在于：内容会反向影响轨道尺寸，而轨道尺寸又反过来决定内容布局。

#### 需要解决的问题

- explicit / implicit grid
- track sizing
- auto placement
- row / column spanning
- named lines / areas
- `minmax()`
- `fr` 单位
- auto tracks
- grid item alignment
- 内容反向影响轨道尺寸

#### 关键概念

- grid container
- grid item
- explicit grid
- implicit grid
- track
- grid line
- grid area
- intrinsic track sizing contribution

#### 机制拆分

1. **建立轨道骨架**
   - 先从 `grid-template-*` 得到显式轨道
   - 再根据 auto placement 需要补 implicit 轨道

2. **放置 item**
   - 已指定位置的 item 先放
   - auto placed item 再按规则填坑

3. **轨道尺寸协商**
   - 每条轨道有自己的 sizing rule
   - item 跨多轨道时，贡献会分摊回多条轨道
   - 内容尺寸与轨道尺寸需要来回协调

4. **最终布局**
   - 轨道尺寸确定后，才能得到 item 最终几何

#### 实现上真正麻烦的点

1. grid 是二维系统，不再能简单线性地从上到下求解。
2. spanning item 会让多个轨道的尺寸求解相互牵连。
3. `fr` 单位看似简单，实则依赖剩余空间分配，而剩余空间又依赖 intrinsic contribution。

#### 最小可用子集

最小版本可以先支持：

- 显式 grid
- 固定轨道尺寸
- 少量 auto placement
- 不支持复杂 spanning
- 不支持完整 intrinsic track sizing

先做到：

- 常见面板 / 仪表盘 / IDE 布局可用

#### 完整行为为什么难

- 真正完整的 grid 需要一套成熟的轨道求解过程
- 它和 intrinsic sizing 的耦合程度不亚于 flex，甚至更强

### 9.3 多列布局

多列布局通常不是 UI 框架的首批目标，但如果想说“完整 CSS 引擎”，它迟早会成为一个需要解释的位置。

#### 需要解决的问题

- column count / column width 的协商
- column balancing
- 跨列断裂
- column gap / rule
- 内容在多列中的 fragmentation

#### 关键概念

- column formatting context
- column count
- column width
- column balancing
- column spanner
- fragmentainer

#### 机制拆分

1. **列数与列宽协商**
   - `column-count` 和 `column-width` 不是简单二选一
   - 它们需要和容器可用宽度、gap 一起求解最终列结构

2. **内容分配**
   - block / inline 内容不会天然“知道自己在第几列”
   - 引擎需要把一个连续流重新切分成多个列片段

3. **平衡列高**
   - 多列布局的视觉目标通常不是“前一列塞满再去下一列”
   - 浏览器通常会尝试平衡各列高度
   - 这意味着布局过程会从单次顺序流，变成带回溯或迭代的求解

4. **跨列元素**
   - `column-span` 这类能力会打断普通列流
   - 它要求前后内容重新分段，并让列结构出现局部重组

#### 为什么它难

- 它不是单纯的 grid，也不是单纯的 block flow
- 它本质上依赖 fragmentation
- 会把普通 block / inline 内容切碎再重组

#### 最小可用子集

最小版本可以先只支持：

- 固定列数
- 固定 column gap
- 不做复杂 balancing
- 不支持跨列元素
- 只支持普通 block / inline 内容切分

先不碰：

- `column-span`
- 复杂平衡算法
- 与 float、positioned element 的复杂交互
- 打印 / 分页级别的一致 fragmentation 行为

#### 路线判断

- 对大多数应用 UI 来说，多列布局优先级可以极低
- 如果是完整 CSS 引擎路线，应当在 fragmentation 之后再考虑

### 9.4 fragmentation

fragmentation 是很多“高级 CSS 看起来很分散、其实共享同一套底层问题”的总机制。多列、分页、区域、跨页打印都会依赖它。

#### 需要解决的问题

- 盒子如何在多个容器片段中被切开
- 哪些边界允许断裂
- 断裂前后的 box、border、margin 如何处理
- line box、block box、replaced element 在 fragmentation 中的差异

#### 关键概念

- fragmentainer
- fragment
- break opportunity
- unbreakable box
- fragmentation context

#### 机制拆分

1. **断裂机会识别**
   - 引擎需要先知道哪里允许断裂
   - 文本、block、replaced element、表格、行盒的可断裂点都不一样

2. **片段生成**
   - 一个逻辑 box 在 fragmentation 后会产生多个视觉 fragment
   - 这些 fragment 共享逻辑身份，但几何、绘制和命中结果都可能不同

3. **断裂边界修正**
   - margin、border、padding、background 在断裂前后如何处理，并不是简单复制
   - 某些装饰应该延续，某些则只在起始或结束片段出现

4. **嵌套 fragmentation**
   - 多列里套分页、分页里套 block flow，这些场景会形成嵌套 fragmentainer
   - 一旦出现嵌套，布局结果就不再是单层切分，而是多阶段 fragment 传播

#### 实现上真正麻烦的点

1. fragment tree 往往不再等于 box tree，也不再等于普通布局结果。
2. 很多布局算法在单一视口下可以顺序求解，但 fragmentation 会迫使它们支持“中途切开再继续”。
3. line box、selection geometry、paint order、hit-test 都会被 fragment 结构连带影响。

#### 最小可用子集

最小版本如果一定要做 fragmentation，比较稳的范围通常是：

- 只支持 block flow 的简单分页
- 行内内容按 line box 断裂
- 不支持复杂跨片段装饰
- 不支持复杂 positioned / transformed element 的跨片段行为

更现实的做法往往是：

- 先在体系结构里承认 fragment 的存在
- 但把真正复杂的 fragmentation 行为延后到完整路线后期

#### 为什么它重要

- 没有 fragmentation，就很难严肃支持多列、分页和打印
- 很多布局系统在“单一滚动视口”里可以假装它不存在，但一旦要完整 CSS，就绕不开

#### 路线判断

- 这是完整 CSS 路线里的后期能力
- 不适合作为最小引擎的早期目标

## 10. 第五大块：尺寸系统与 intrinsic sizing

这会是整套 CSS 引擎里最容易被低估、也最容易把前面布局系统全部拖复杂的一块。很多“为什么浏览器最后算出来这个宽度”的问题，答案都落在这里。

### 10.1 需要解决的问题

- `width / height / min / max`
- `auto`
- percentage
- `aspect-ratio`
- `min-content`
- `max-content`
- `fit-content`
- shrink-to-fit
- replaced element intrinsic size
- `contain-intrinsic-size`

### 10.2 核心概念

- preferred size
- minimum size
- maximum size
- intrinsic size
- extrinsic size
- available size
- definite size
- indefinite size
- shrink-to-fit size
- percentage basis
- content contribution

### 10.3 为什么它难

尺寸系统的难点不在于公式多，而在于它不是单向求值。

很多情况下：

- 子元素尺寸依赖父元素可用空间
- 父元素尺寸又依赖子元素内容贡献
- 兄弟元素之间还可能通过 flex / grid 继续相互制约

这会形成大量“先估一个，再修正”的求解过程。

也就是说，CSS 尺寸系统很多时候不是简单表达式求值，而更像带约束的尺寸协商。

### 10.4 机制拆分

#### A. 明确尺寸与不明确尺寸

第一层要先区分：

- definite size
- indefinite size

这是因为：

- percentage 只有在参考尺寸明确时才能求值
- 很多 intrinsic 规则只有在参考尺寸不明确时才会生效

#### B. intrinsic size

intrinsic size 不是一个值，而是一组能力：

- 元素在不受外部约束时“天然想要”的尺寸
- 元素在最小压缩下还能保持内容语义时的尺寸

常见对应：

- `max-content`
- `min-content`

这两者本身就要求内容系统能回答：

- 不换行时多宽
- 最激进可断时多宽

这也是为什么 intrinsic sizing 和文本排版 / line break 强耦合。

#### C. shrink-to-fit

这是一类经典“浏览器黑魔法”行为。

它通常出现在：

- 浮动
- 绝对定位
- 某些 auto 宽度场景

本质上是：

- 先看内容最小能缩到哪
- 再看内容天然会扩到哪
- 再看外部给多少可用空间
- 最终取一个夹在中间的值

看起来像一个公式，实际上它背后依赖：

- min-content
- max-content
- available inline size

一个很适合记住的典型场景是：

- 外层可用宽度：`300px`
- 子内容的 `min-content`：`120px`
- 子内容的 `max-content`：`520px`

那么 shrink-to-fit 的结果通常会落成：

- 先不能小于 `120px`
- 也不应该天然扩到 `520px`
- 但外部最多只愿意给 `300px`

于是最终尺寸会收敛到 `300px`。

这个例子之所以重要，是因为它能直观看出 shrink-to-fit 不是“取内容宽度”，而是“在内容倾向和外部约束之间找折中值”。

#### D. replaced element intrinsic size

图片、视频、canvas、iframe 这类 replaced element 并不像普通文本盒子那样通过子内容推导尺寸。

它们通常有：

- intrinsic width
- intrinsic height
- intrinsic ratio

这会和：

- `width/height: auto`
- `aspect-ratio`
- min/max 约束

共同决定最终 used size。

#### E. contain-intrinsic-size

这是现代 CSS 用来做内容可见性优化和占位估计的一组机制。

它的重要性在于，它把“还没真正布局时的假定尺寸”正式引入了系统。

如果未来真的要做完整 CSS 引擎，这意味着：

- 尺寸系统不再只处理真实内容贡献
- 还要处理“声明式虚拟 intrinsic size”

### 10.5 与其他机制的耦合

intrinsic sizing 强耦合：

- 文本排版
- flex
- grid
- replaced element
- percentage 求值
- containing block

其中最关键的是：

1. **文本排版**
   - `min-content` / `max-content` 很多时候本质上是文本问题

2. **flex**
   - flex item 的 base size 与 min/max 约束经常依赖 intrinsic contribution

3. **grid**
   - grid track sizing 中大量步骤依赖 intrinsic contribution

### 10.6 典型尺寸协商案例

如果要把尺寸系统写得更像一本书，这里最好明确列出几类反复出现的协商场景。

#### 案例 A：百分比遇到不明确尺寸

当子元素写了 `width: 50%`，第一反应往往是“那就取父宽的一半”。但只有在父元素相关轴的尺寸是 definite size 时，这个说法才成立。

如果父元素宽度本身仍取决于子内容，那么这里会出现经典循环：

- 子宽依赖父宽
- 父宽又依赖子贡献

这时引擎通常不能直接求百分比，而要回退到 auto 行为、延后求值，或进入特定布局模式的约定处理。

#### 案例 B：文本内容决定 min-content

一段长文本放进 block、flex item、grid item 时，常见争议是“它到底能压多窄”。

这里真正要问的不是：

- 盒子现在多宽

而是：

- 在允许断行的前提下最小还能多窄
- 在完全不换行时天然会多宽

这就是 `min-content` / `max-content` 的来源，而答案最终会强依赖：

- shaping
- line break
- whitespace
- 字体 fallback

#### 案例 C：replaced element + aspect-ratio

图片如果同时给了：

- intrinsic width / height
- CSS width
- CSS height
- `aspect-ratio`

就会出现多组约束竞争。

真正稳定的实现必须明确：

- 哪些约束来自资源本身
- 哪些约束来自样式
- 哪些约束只是缺省推导路径

否则结果很容易在图片、视频、canvas、iframe 之间出现不一致。

### 10.7 最小可用子集

如果从零开始做最小版本，可以先只支持：

- 明确 `width/height`
- `min/max`
- percentage
- 简化 `aspect-ratio`
- 不支持完整 `min-content/max-content`
- 不支持完整 shrink-to-fit

再往前一点的折中方案可以是：

- 文本节点支持最简 `min-content/max-content`
- 普通 block box 仍然主要依赖明确尺寸或父容器分配

### 10.8 完整行为为什么难

完整 intrinsic sizing 真正难的地方在于：

- 它不是独立模块
- 它把文本、block、flex、grid、replaced element 都串起来了
- 它经常要求“先问内容，再布局，再反过来修正内容贡献”

也就是说，一旦决定认真做这块，就意味着：

- 你的布局引擎已经不再是简单树遍历
- 而进入了多阶段协商和回代求解

### 10.9 路线判断

对一套从零实现的 CSS 引擎来说：

- 可以非常早支持 `width/height/min/max/percentage`
- 可以相对较早支持简化 `aspect-ratio`
- `min-content/max-content/shrink-to-fit` 应放在更后期
- 完整 intrinsic sizing 应视为“从可用布局系统迈向浏览器级行为”的分水岭

## 11. 第六大块：文本排版系统

这是另一块最难的核心，而且它和前面的 inline formatting、intrinsic sizing、命中测试、selection 几乎全部强耦合。单独做一个文本布局系统已经很重，放到完整 CSS 引擎里只会更重。

这部分和单独的文本测量文档会有强重叠，但这里必须从 CSS 引擎视角来写，也就是：文本排版不是孤立子系统，而是格式化上下文的一部分。

### 11.1 需要解决的问题

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
- word-spacing
- text-indent
- text-transform
- writing-mode
- vertical text
- text-orientation
- tab-size

### 11.2 关键概念

- text run
- font run
- shaping run
- glyph run
- cluster
- grapheme boundary
- line break opportunity
- bidi run
- baseline
- ascent / descent / leading
- line box
- writing mode
- inline progression direction

### 11.3 机制拆分

#### A. font matching 与 fallback

文本排版的第一步不是量宽度，而是决定“这段文本到底用哪个字体画”。

这要求系统能处理：

- `font-family` 列表
- 平台可用字体集合
- 缺字 fallback
- 字重/字形/拉伸风格匹配
- 可能的 variable font axis

这里最关键的一点是：

- 文本宽度不是只由字符序列决定
- 而是由“字符序列 + 实际字体选择结果”共同决定

所以任何想做严肃文本布局的引擎，都迟早要显式持有 font matching / fallback 逻辑，而不能永远把它外包成浏览器黑盒。

#### B. shaping

Shaping 不是“把字符变成 glyph”这么简单，而是：

- 按 script / direction / language 切 run
- 应用 OpenType feature
- 决定 ligature
- 决定 glyph substitution / positioning
- 得到 advance / offset / cluster map

对 Latin 来说，很多时候可以误以为字符宽度大概就是文本宽度；对复杂脚本来说，这种想法会立刻失效。

这就是为什么：

- 文本测量
- caret 几何
- selection
- hit-test

最后都会被 shaping 反向牵制。

#### C. bidi

CSS 文本排版不能假设逻辑顺序就是视觉顺序。只要支持 RTL 或混合方向文本，就必须显式处理：

- bidi paragraph level
- bidi run 拆分
- visual order 重排
- 光标在逻辑 index 和视觉位置之间的映射

这部分的难点不是“是否支持阿拉伯语”，而是：

- 一旦系统声称自己支持完整 CSS 文本排版，就没有理由回避 bidi

一个很关键的实现事实是：

- caret 的逻辑前进方向
- 选区的视觉扩展方向
- 命中测试时“更靠左/更靠右”的直觉

在 bidi 文本里都可能和逻辑字符顺序脱钩。

所以 bidi 不能只被当成“显示顺序改一下”，它会直接进入编辑行为模型。

#### D. line break

line break 不是“宽度不够就砍一刀”。

它依赖：

- Unicode line breaking rules
- 语言与文字系统差异
- `white-space`
- `word-break`
- `overflow-wrap`
- 行内盒子边界

而且它还不是纯文本问题，因为真正的可断点也受：

- inline box 边界
- replaced element
- 原子 inline box
- unbreakable segment

影响。

#### E. whitespace 处理

`white-space` 这组属性会同时影响：

- 空格折叠
- 换行符处理
- 是否允许自动换行
- 行尾空白保留

看起来像小属性，实际它会直接改变文本 tokenization 后进入 line layout 的内容流。

#### F. line-height 与行高协调

很多人会把 line-height 当作“一个简单数值”，但在完整 CSS 里，它至少涉及：

- line box 高度
- inline box 的 vertical metrics
- baseline 对齐
- `normal` 的字体相关缺省值
- replaced element 与文本混排的高度协商

#### G. writing-mode 与 vertical text

只要进入 `writing-mode`：

- inline axis / block axis 会发生变化
- line progression 改变
- 某些文本方向与字形旋转规则改变
- 许多原本只在横排里考虑的问题都要重新处理

#### H. caret / selection 几何

文本系统最终不能只产出“这一段字怎么画”，还必须产出：

- 每个可插入位置对应的几何
- 每个 selection range 对应的高亮片段
- 光标在 bidi run 交界处的 affinity 行为

这一步之所以重要，是因为编辑器真正依赖的不是文本纹理，而是：

- 点击后 caret 放在哪
- Shift 扩选时 range 如何变化
- 上下方向键时如何在相邻 line box 中保持视觉列对齐

因此：

- vertical text 不是“把横排转 90 度”
- 而是一整组文本与布局规则的重解释

### 11.4 与其他模块的耦合

文本排版强耦合：

- inline formatting context
- intrinsic sizing
- 命中测试
- selection geometry
- 滚动
- animation（某些文本相关视觉属性）

尤其要强调两条：

1. **没有文本排版，就没有真正可靠的 inline formatting**
2. **没有文本排版，就没有真正可靠的 intrinsic width**

所以很多看起来属于“布局系统”的问题，最终都会被文本排版拉回底层。

### 11.5 典型边界案例

下面几类案例非常适合专门写样例和 oracle：

#### 案例 A：Latin + CJK + emoji 混排

这个场景能迅速暴露：

- fallback font 是否稳定
- baseline 是否统一
- 行高是否出现意外抖动

#### 案例 B：LTR 段落中夹 RTL 文本

这个场景能暴露：

- bidi run 划分是否正确
- caret 左右移动是否仍然符合视觉预期
- selection rect 是否按视觉顺序生成

#### 案例 C：长单词、空白折叠与 `overflow-wrap`

这个场景能暴露：

- `white-space` 处理
- line break 机会
- min-content 宽度是否稳定

### 11.6 最小可用子集

如果只是最小版本，可以先支持：

- LTR
- Latin / CJK
- 基础 font matching
- 隐式 shaping（依赖宿主）
- 基础 line break
- 基础 whitespace 处理
- 基础 line-height

先不碰：

- RTL / bidi
- 复杂 script shaping
- vertical writing
- 完整 fallback introspection

但如果目标是“完整 CSS 引擎”，这一整套迟早要补齐。

### 11.7 完整行为为什么难

文本排版难的根源在于：

- 它既不是单纯字符串处理
- 也不是单纯几何计算
- 而是 Unicode、字体、脚本、语言、布局上下文、交互几何共同作用的结果

你很难把它拆成一个轻量插件，因为：

- 它会反过来定义 line box
- 会影响 intrinsic size
- 会影响 hit-test
- 会影响 selection

也就是说，文本排版不是布局引擎的一个模块，而是布局引擎的心脏之一。

### 11.8 路线判断

如果真要走完整 CSS 引擎路线，这一章的现实结论是：

- 不能自欺欺人地低估文本排版
- 很可能必须引入成熟文本栈
- 或至少明确承认这是整个系统最难的几个核心问题之一

从工程顺序上看，比较合理的是：

1. 先支持最小文本闭环
2. 再支持 inline formatting 的可靠行盒
3. 再逐步补字体、shaping、bidi、vertical writing

而不是一开始就试图“顺手把文本排版也做了”

## 12. 第七大块：滚动、溢出与裁剪

这一块解决的问题不是“内容超出就加个滚动条”，而是定义元素在视觉视口、滚动偏移、裁剪边界之间的真实关系。

浏览器里的 scroll/overflow 是布局、绘制、命中测试、输入系统共同参与的结果，不是单独一层插件。

### 12.1 需要解决的问题

- 什么情况下元素成为 scroll container
- overflow 区域与 scrollable overflow 的计算
- 裁剪边界与可见区域的确定
- scroll offset 如何进入坐标系统
- scrollbar 是否占布局空间
- sticky / fixed / absolute 与滚动容器的关系
- scroll snap、scroll anchoring、programmatic scroll 的行为边界

### 12.2 关键概念

- overflow area
- scroll container
- scrollport
- scroll origin
- clip rect
- visual overflow
- layout overflow
- sticky constraint rectangle

### 12.3 机制拆分

#### A. overflow 语义

`overflow` 不是一个简单的“显示或隐藏超出内容”的开关，它至少要回答三件事：

1. 超出内容是否仍然参与布局结果
2. 超出内容是否仍然参与绘制
3. 超出内容是否可以通过滚动访问

例如：

- `overflow: visible` 倾向于保留溢出可见
- `overflow: hidden` 会裁掉可见区域，但元素未必就不是 scroll container 语义的一部分
- `overflow: auto` / `scroll` 则要求引入可滚动视口与滚动偏移

#### B. scroll container 与 scrollport

一旦元素成为 scroll container，就要区分：

- 内容真实布局范围
- 容器的可视区域
- 当前滚动偏移后实际能看到的区域

这里最核心的不是“有没有滚动条”，而是建立一套稳定坐标关系：

- 子内容在内容坐标空间中布局
- scroll offset 把内容空间映射到可视空间
- 命中测试和绘制都要经过这个偏移转换

#### C. clipping

overflow 往往伴随裁剪，但裁剪也可能来自：

- `clip-path`
- border radius
- 独立的裁剪层
- compositing 边界

所以实现上通常不能把 clipping 只写死在 overflow 上，而要把它建模成更一般的 clip chain 或裁剪栈。

#### D. scrollbar

scrollbar 看似是宿主 UI 细节，但它会反向影响：

- 可用布局空间
- 命中测试区域
- 程序化滚动范围
- overlay 与 classic scrollbar 的差异行为

如果引擎目标只是编辑器内核，最小版本可以把 scrollbar 外包给宿主；但如果目标接近浏览器，就必须明确 scrollbar 是否属于布局树的一部分。

#### E. sticky / transform / nested scroll

一旦出现嵌套滚动容器，问题会迅速变复杂：

- sticky 约束相对哪个滚动容器计算
- transformed ancestor 是否改变 fixed / sticky 的参考系
- 命中测试坐标要经过哪些 scroll + transform 链
- 程序化滚动时哪一层应该响应

这部分和布局、命中测试、绘制都强耦合，不能孤立实现。

### 12.4 实现上真正麻烦的点

1. overflow 不是纯绘制问题，因为它会反过来改变滚动、命中测试、sticky 行为。
2. scroll offset 不是单个数字，而是整条祖先滚动链共同参与坐标变换。
3. visual overflow、layout overflow、hit-test overflow 可能并不相同。
4. 一旦引入嵌套滚动容器，局部无效化、事件分发、吸附滚动都会复杂很多。

### 12.5 最小可用子集

最小可用版本可以先只支持：

- `overflow: visible | hidden | auto`
- 单层 scroll container
- 矩形裁剪
- 不参与布局的宿主 scrollbar
- 基础 scroll offset 与程序化滚动

先不碰：

- scroll snap
- scroll anchoring
- overlay scrollbar 的精细行为
- 复杂 nested scroll 协调
- sticky 与 transform 的完整兼容

### 12.6 完整行为为什么难

- 滚动不是孤立子系统，它影响布局、绘制、命中测试、输入和动画
- 不同平台的 scrollbar 模式与视口约定差异很大
- sticky / fixed / transform / overflow clip 在边界组合下非常容易出现实现偏差
- 浏览器为了性能会做异步滚动、合成层滚动，这又把问题推进到 compositing 和 scheduler

### 12.7 路线判断

- 如果目标只是“能显示一块可滚动内容”，最小 scroll container 很快就能做出来
- 如果目标是接近浏览器级行为，scroll 必须从一开始就被当成坐标系统问题，而不是 UI 小功能
- 对 MetaEditor 这类宿主型系统，更现实的路线通常是：
  1. 先做逻辑 overflow + 基础裁剪
  2. 再做稳定的 scroll offset 坐标链
  3. 最后才补 sticky、snap、复杂 scrollbar 与高级滚动行为

## 13. 第八大块：绘制系统

### 13.1 display list / paint order

绘制系统的入口不是“看到一个 box 就画一下”，而是先把布局结果转换成有顺序、有层次的绘制指令。这个中间层通常就是 display list 或 paint fragments。

#### 需要解决的问题

- 按规范定义绘制顺序
- 把 box tree / fragment tree 转成 paintable items
- 支持背景、边框、文本、阴影、outline、装饰等不同绘制项
- 为后续命中测试和合成层保留足够信息

#### 关键概念

- display list
- paint fragment
- paint phase
- painting order
- retained display list

#### 为什么它重要

- 没有稳定的 display list，很难做：
  - stacking context
  - hit-test
  - 局部重绘
  - 合成优化

#### 路线判断

- 最小引擎可以直接边遍历边画
- 但一旦要接近浏览器行为，display list 基本不可避免

#### 典型绘制顺序分层

如果要把 display list 写清楚，至少要明确一组稳定的 phase 概念。一个简化但有用的顺序通常可以理解为：

1. 背景与边框
2. 普通流内容
3. 浮动内容
4. 行内文本与装饰
5. positioned descendants
6. outline 与顶层装饰

真正浏览器行为比这个更细，但只要没有这种 phase 级概念，paint order 往往会退化成节点遍历顺序，后面很难再补正。

### 13.2 background / border / outline

这看起来像最“直观”的绘制部分，但它其实已经涉及：

- box 几何
- border box / padding box / content box
- 圆角裁剪
- background painting area
- outline 与 border 的差异

#### 需要解决的问题

- background color
- background image
- background positioning / repeat / size
- border painting
- border style
- border-radius
- outline painting

#### 关键复杂度来源

1. `background` 不是只填满 border box。
   它要区分：
   - painting area
   - positioning area

2. border-radius 会影响：
   - background clip
   - border 几何
   - hit-test 边界（如果做精确命中）

3. `outline` 不参与盒模型，但要参与绘制顺序和视觉结果。

### 13.3 box-shadow / filter / opacity

这些属性常被误认为只是“最后做个特效”，但它们会直接影响：

- stacking context
- 合成层
- 绘制边界
- 命中测试语义

#### 需要解决的问题

- 外阴影 / 内阴影
- blur 半径
- filter 链
- opacity 组合

#### 关键复杂度来源

1. blur / shadow 通常会扩大元素的视觉边界。
2. opacity 不是对子节点各自独立乘一下，而往往要求整组内容先作为一个合成单元再整体混合。
3. filter 可能迫使你引入离屏缓冲或更明确的 compositing pipeline。

### 13.4 transform

transform 不是纯绘制属性，因为它虽然通常不重新参与正常布局，但会强烈影响：

- 最终几何
- 命中测试
- 滚动
- stacking context
- containing block

#### 需要解决的问题

- transform function list
- transform origin
- 2D / 3D 变换
- 坐标变换链
- 变换后的边界盒

#### 关键复杂度来源

1. 变换后的视觉边界不再等于布局边界。
2. hit-test 需要把输入坐标逆变换回局部空间。
3. transform 和 fixed / sticky / overflow / scroll 的交互会让实现迅速变复杂。

### 13.5 stacking context

stacking context 是 CSS 绘制系统的真正骨架之一。没有它，就没有稳定的 z-order 语义。

#### 需要解决的问题

- 哪些属性创建 stacking context
- stacking context 内部如何排序
- stacking context 之间如何嵌套与合成
- positioned descendants 与 z-index 的排序规则

#### 关键概念

- stacking context
- stacking level
- painting phase buckets
- local z-order

#### 为什么它难

- 它不是简单的全局 `z-index` 排序
- 每个 stacking context 都像一个局部世界
- 子上下文先内部排好，再整体作为父上下文中的一个绘制单元

这意味着绘制顺序实际上是：

- 树结构
- 局部排序
- 全局嵌套

三者共同作用的结果。

#### 一个实用排序视角

实现时可以把 stacking context 内部排序想成“桶排序”而不是“所有对象一起比大小”：

1. 背景 / border
2. negative z-index descendants
3. in-flow block / inline descendants
4. floats
5. positioned auto / z-index: auto descendants
6. positive z-index descendants

这个视角的价值在于，它提醒实现者：

- `z-index` 不是唯一排序依据
- 普通流、浮动、定位元素本来就属于不同绘制阶段
- 子 stacking context 需要先在自己内部收敛，再整体进入父上下文

### 13.6 compositing

真正接近浏览器行为时，绘制系统不能只停留在“逻辑顺序画出来”，还要考虑哪些内容需要单独成层。

#### 需要解决的问题

- 哪些属性触发合成层
- 哪些效果需要离屏缓冲
- 局部无效化与重绘
- 多层混合与裁剪

#### 路线判断

- 最小系统可以先不做复杂 compositing，只做纯绘制顺序
- 但一旦要支持更真实的 opacity / filter / transform / animation，就需要引入至少简化版 compositing 模型

这部分还需要明确：

- 什么属性只影响绘制，不影响布局
- 什么属性会反过来影响命中测试与滚动

#### 属性影响分类

比较实用的一种分类方式是：

- 主要影响绘制：
  - `color`
  - `background`
  - `border-color`
  - `box-shadow`

- 影响绘制并可能影响合成：
  - `opacity`
  - `filter`
  - `transform`

- 影响绘制，同时影响命中测试边界：
  - `clip-path`
  - `border-radius`
  - `transform`

一旦把这类分类整理清楚，invalidation 和 compositing 策略就更容易落地。

## 14. 第九大块：命中测试与交互

命中测试不是“鼠标点到哪个矩形”的简单判断，而是把输入坐标映射回当前视觉结果背后的布局、绘制和文本结构。

对于编辑器类系统，这一层甚至比很多高级 CSS 属性更核心，因为 caret、selection、拖拽、点击定位都依赖它。

### 14.1 需要解决的问题

- pointer event 应该落到哪个可命中的目标
- z-order 与 stacking context 如何影响命中优先级
- transform / scroll / clip 后坐标如何逆变换
- 文本点击如何映射到 caret position
- selection range 如何映射到几何区域
- `pointer-events`、`visibility`、`opacity` 等属性如何影响可命中性
- focus navigation 如何定义下一个焦点目标

### 14.2 关键概念

- hit-test tree
- event target
- paint order aware hit testing
- local coordinate space
- inverse transform
- caret position
- selection rect / highlight geometry
- focusable area

### 14.3 机制拆分

#### A. pointer hit test

最基础的命中测试流程通常是：

1. 从顶层可见内容开始
2. 按绘制顺序逆序检查可命中对象
3. 判断点是否落在对象可命中区域内
4. 返回第一个有效目标

这里“按绘制顺序逆序检查”很重要，因为用户点击看到的最上层内容，通常就应该先获得事件。

所以 hit-test 不能和 paint order 脱钩；最稳定的做法通常是让两者共享 fragment / display item 层面的结构信息。

#### B. transformed / scrolled hit test

一旦对象经过 scroll 或 transform，命中测试就不再能用全局坐标直接对盒子做矩形包含判断。

需要做的是：

- 先经过祖先滚动偏移链
- 再应用裁剪链
- 再把全局输入点逆变换回局部坐标空间
- 最后在局部几何上判断是否命中

这意味着 scroll、clip、transform 在命中测试里不是附加条件，而是坐标系统本体的一部分。

#### C. text caret hit testing

文本命中测试比 box hit test 更细，因为目标不是“命中这个元素”，而是“命中这个文本中的哪个插入点”。

它至少要回答：

- 点落在哪个 line box
- 对应哪一个 text run / glyph run
- 更接近某个字符前还是字符后
- bidi 文本中视觉顺序与逻辑顺序如何映射

编辑器可用性很大程度上取决于这里是否稳定。

#### D. selection geometry

selection 不只是两个逻辑位置，它还需要导出一组视觉几何结果，用于：

- 高亮绘制
- 鼠标拖拽扩选
- 自动滚动
- copy / accessibility / IME 辅助行为

这通常要求文本系统能把逻辑 range 映射成：

- 一组 line fragment 片段
- 每段对应的局部矩形
- 在跨行、跨 block、跨 bidi run 场景下可合并或分段表示

一个稳定的 selection 模型通常还要说明：

- anchor / focus 两端的逻辑位置
- 视觉矩形和逻辑 range 的映射关系
- 双击选词、三击选段这类高层交互如何落回底层 range

#### E. focus navigation

焦点系统虽然常被看成 DOM 层逻辑，但真正可靠的 focus navigation 通常离不开布局信息。

例如：

- Tab 顺序需要结构语义
- 方向键导航可能需要几何邻近关系
- 被裁剪或不可见的元素是否可聚焦
- disabled / inert / visibility 等状态如何参与焦点候选过滤

对于编辑器宿主，这部分还要和宿主输入法、原生焦点桥接。

#### F. text selection 与 focus 的耦合

在编辑器系统里，selection 和 focus 往往不是两个独立话题：

- 没有 focus，键盘输入和 caret 往往没有宿主接收点
- selection 变化又常常决定滚动到哪里、哪一段需要重绘
- 焦点离开和恢复时，selection 是否保留、caret 是否闪烁，都需要稳定策略

这意味着命中测试层最终不只是“找到一个目标元素”，还要把结果交给输入焦点模型。

### 14.4 实现上真正麻烦的点

1. 命中测试依赖绘制顺序，但又不能完全复制一套绘制管线。
2. transform、clip、scroll 叠加后，坐标逆变换链很容易出错。
3. 文本 caret hit test 需要深入文本排版结果，而不是只看 DOM 文本节点。
4. selection geometry、focus navigation、drag behavior 都会在边界场景暴露命中系统缺陷。

### 14.5 典型边界案例

下面几类 case 很适合被单独写成样例：

- 滚动容器里的文本点击定位
- transform 后的 `elementFromPoint`
- bidi 文本里的左右方向键移动 caret
- 跨多行 selection 的高亮矩形拼接
- 被 `visibility`、`pointer-events`、裁剪链共同影响的命中结果

### 14.6 最小可用子集

最小可用版本可以先只支持：

- 矩形 box hit test
- paint order 逆序命中
- 单层 scroll offset
- 不含复杂变换的文本 caret 定位
- 简化 selection rect

先不碰：

- 精确到非矩形轮廓的命中
- 复杂 3D transform 命中
- 完整 bidi caret affinity
- 高级 focus navigation 规则
- `pointer-events` 的全部边界行为

### 14.7 完整行为为什么难

- 它站在布局、绘制、文本、输入四个系统的交叉点
- 命中测试的错误通常不是“看起来有点不对”，而是直接变成无法编辑、无法点击、无法选择
- 文本相关命中行为高度依赖字体、shaping、bidi 和行盒切分
- 浏览器还有大量和宿主平台事件模型绑定的细节，不是纯 CSS 规范能完全描述的

### 14.8 路线判断

- 对编辑器系统来说，命中测试不应该被排到最后，而应该在“基础布局 + 基础文本”之后尽早成型
- 最现实的路线通常是：
  1. 先做稳定的 box hit test
  2. 再做文本 caret / selection 的最小闭环
  3. 最后再补 transform、复杂 clip、完整 focus navigation
- 如果这一层做得不稳，前面布局和绘制做得再漂亮，也很难变成可交互系统

## 15. 第十块：动画、过渡与时间系统

动画系统解决的问题不是“每一帧改一下值”，而是把样式值变化放进一个有时间语义、插值规则、失效策略和调度机制的统一模型里。

如果前面的样式、布局、绘制、命中测试都已经建立，动画就是那个把整个系统从静态结果推向连续演化过程的层。

### 15.1 需要解决的问题

- transition 何时触发、如何启动、如何取消
- animation / keyframes 如何解析并绑定到元素
- 不同属性类型如何插值
- timing function、delay、iteration、direction 如何组合
- 动画帧如何驱动样式重算、布局或绘制
- 哪些动画可以只走 compositing，哪些必须重新布局
- 动画事件、fill mode、play state 如何影响最终样式

### 15.2 关键概念

- animation timeline
- current time
- active interval
- keyframe effect
- interpolation
- additive / replace composition
- animation stack
- composited animation

### 15.3 机制拆分

#### A. transition

transition 的本质不是独立动画脚本，而是“样式值在两个状态之间变化时，自动生成一段时间上的插值过程”。

它依赖：

- 前后样式值的对比
- 属性是否可动画
- transition-duration / delay / timing-function 等配置

所以 transition 系统必须挂在样式更新路径上，而不是单独脱离 cascade 存在。

#### B. animation / keyframes

`@keyframes` 则是显式定义一条时间轴上的目标值序列。

它需要回答：

- keyframe selector 如何解析成时间点
- 缺失属性如何继承或补齐
- 多个 animation effect 如何叠加
- animation-name 与 keyframes 作用域如何解析

相比 transition，animation 更像持续存在的 effect graph，而不是一次性的值变化补间。

#### C. interpolation

插值是动画系统最关键的数学核心之一，但它不是统一公式：

- 长度值可能按数值插值
- 颜色值可能在指定色彩空间插值
- transform 可能要逐函数分解或矩阵分解
- 离散属性则可能根本不能平滑插值

所以“属性可动画”本质上意味着该属性有明确定义的组合和插值语义。

#### 常见插值分类

如果要把动画系统写得更工程化，至少可以先把属性分成下面几类：

1. 数值插值：
   - `opacity`
   - 长度
   - 时间

2. 颜色插值：
   - `color`
   - `background-color`

3. 列表或复合值插值：
   - `box-shadow`
   - `filter`
   - `transform`

4. 离散切换：
   - `display`
   - 某些枚举型关键字

这种分类会直接决定动画引擎内部需要多少种 effect evaluator。

#### D. animation pipeline

动画不会直接输出像素，它通常输出“当前时刻的 animated style value”。

然后这些值再进入：

- 样式计算
- 布局
- 绘制
- compositing

因此必须明确每类动画触发的是：

- style-only invalidation
- layout invalidation
- paint invalidation
- compositing-only update

一个更实用的实现视角，是把动画属性按失效层分类：

- style-only：
  - 只影响样式组合结果，后续是否触发布局由属性本身决定

- layout-affecting：
  - `width`
  - `height`
  - `margin`
  - 这类属性通常需要重排

- paint-affecting：
  - `background-color`
  - `box-shadow`
  - `border-color`

- compositing-friendly：
  - `opacity`
  - `transform`

只要这层分类不清晰，动画系统就会频繁做出过重或过轻的 invalidation。

#### E. composited animation

浏览器之所以能让某些动画看起来很流畅，是因为它们不必每帧重跑完整布局和绘制，而是交给合成线程或合成层做更新。

典型候选通常包括：

- opacity
- transform
- 部分 filter

但前提是：

- 目标已成层
- 插值语义明确
- 不影响布局与文本重排

### 15.4 实现上真正麻烦的点

1. 动画不是新系统，而是对样式、布局、绘制调度的横向切入。
2. 不同属性的插值规则差异极大，不能靠统一数值补间覆盖。
3. transition 触发条件依赖“前后样式状态比较”，这很容易在增量更新时出错。
4. composited animation 需要和成层、失效、调度器配合，否则只会让系统更复杂。

### 15.5 典型边界案例

下面几类 case 很适合写成动画系统的第一批样例：

- `opacity` 过渡是否只触发 compositing 更新
- `width` 过渡是否导致连续 layout invalidation
- `transform` 列表长度不同的插值行为
- `display` 这类离散属性是否按预期切换而非平滑补间

### 15.6 最小可用子集

最小可用版本可以先只支持：

- `transition`
- 少量数值型属性插值
- `opacity` / `transform` 的基础动画
- 单一文档时间轴
- 不带复杂事件的简单播放模型

先不碰：

- Web Animations 风格的完整效果栈
- additive / accumulate 组合
- 复杂 transform 分解边界
- scroll-driven animation
- 高级 timeline 与宿主时钟桥接

### 15.7 完整行为为什么难

- 它要求系统精确地区分哪些属性影响布局、哪些只影响绘制或合成
- 动画值、过渡值、普通样式值之间需要明确优先级和叠加规则
- 浏览器常见的高性能动画依赖合成线程、成层策略和帧调度
- 动画还和事件、脚本、用户输入、可见性状态等运行时因素强耦合

### 15.8 路线判断

- 对 MetaEditor 这类系统，动画不应该一开始追求“规范全覆盖”，而应该先建立属性失效分类
- 更合理的实现顺序通常是：
  1. 先支持 transition + 少量数值属性
  2. 再支持 `opacity` / `transform` 这类高价值属性动画
  3. 最后再补 keyframes、多动画叠加、合成优化
- 如果没有先建立稳定的 invalidation 和 compositing 边界，动画系统只会把已有复杂度放大

## 16. 属性分类大纲

CSS 属性适合按机制重新分组，而不是按规范目录平铺。至少包括：

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

这组属性主要决定盒子的基础几何边界，是尺寸系统和布局系统最早接触的一批属性。

它们通常影响：

- 值解析
- 盒模型几何
- intrinsic sizing
- block / flex / grid 布局

实现上需要特别注意：

- `width/height` 和 `min/max-*` 是协商关系，不是单向覆盖关系
- `padding/border` 会改变可用内容区域，也会改变滚动与裁剪边界
- `aspect-ratio` 会把横纵尺寸耦合在一起，迫使尺寸求解不再是单轴问题

更适合的实现阶段通常是：

- Phase A 支持固定数值和最基础的 `box-sizing`
- Phase B 引入 `min/max-*` 和基础百分比
- Phase C 以后再把 `aspect-ratio` 与 intrinsic sizing 完整接起来

### 16.2 文档流与 display

- `display`
- `visibility`
- `float`
- `clear`
- `overflow*`

这组属性控制“元素以什么结构进入布局系统”，以及“它的内容是否继续参与正常流、裁剪与滚动”。

它们主要依赖：

- box tree 生成
- formatting context 选择
- overflow / scroll container 机制
- 部分绘制和命中语义

其中最核心的属性通常是 `display`，因为它会先决定：

- 是否生成 box
- 生成 block-level 还是 inline-level 结构
- 是否进入 flex / grid / table 等不同布局模式

`visibility` 看似只是显示开关，但它会同时影响：

- 绘制
- hit-test
- focus / accessibility

而 `float`、`clear`、`overflow` 则属于“会反向扰动正常流”的属性，通常不适合过晚实现。

### 16.3 定位与层叠

- `position`
- `top/right/bottom/left`
- `z-index`
- `inset*`

这组属性把普通布局推进到参考系、脱流、局部 z-order 的问题域。

它们主要依赖：

- containing block
- static position
- stacking context
- scroll / viewport 参考系

其中：

- `position` 决定元素是否仍在正常流中
- `top/right/bottom/left` 与 `inset*` 决定偏移求值
- `z-index` 则把结果接到绘制顺序和命中优先级上

这类属性往往会暴露系统是否已经真正建立了：

- 参考矩形
- 坐标空间
- 局部层叠顺序

因此它们通常是从 Phase B 到 Phase D 持续增强的一组能力。

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

flex 相关属性不是“多几个布局参数”，而是整套单轴尺寸协商算法的外部接口。

它们共同依赖：

- flex formatting context
- intrinsic sizing
- available space 计算
- baseline / cross-axis alignment

在实现上可以拆成三层：

1. 主轴分配：
   - `flex-grow`
   - `flex-shrink`
   - `flex-basis`

2. 容器方向与换行：
   - `flex-direction`
   - `flex-wrap`

3. 对齐与顺序：
   - `justify-content`
   - `align-items`
   - `align-content`
   - `align-self`
   - `order`
   - `gap`

更合理的工程顺序通常是：

- 先做单行、单方向、有限对齐
- 再做 shrink/grow 和基础 cross-axis 对齐
- 最后补 wrap、baseline、复杂 intrinsic sizing 与 `gap`

### 16.5 grid 属性

- `grid-template-*`
- `grid-auto-*`
- `grid-row*`
- `grid-column*`
- `grid-area`
- `place-*`

grid 属性是二维布局算法的控制面。它们比 flex 更依赖显式轨道、隐式轨道、放置算法和尺寸协商的组合。

它们主要依赖：

- grid track sizing
- auto placement
- intrinsic sizing
- fragmentation 与对齐系统

grid 真正复杂的地方通常不在语法，而在：

- 轨道尺寸是如何被内容反向撑开的
- item 放置顺序如何与自动放置配合
- `minmax()`、`fr`、auto track sizing 如何共同求解

如果没有稳定的 intrinsic sizing 和 fragment 模型，grid 很容易做成“能排出格子，但边界全错”的半成品。

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

这组属性共同控制文本从字符流变成行盒、字形和可交互内容的过程。

它们主要依赖：

- font matching
- shaping
- bidi
- line breaking
- inline formatting context
- caret / selection geometry

可以粗分成四类：

1. 字体与字形：
   - `font-*`
   - `text-transform`

2. 断行与空白：
   - `white-space`
   - `word-break`
   - `overflow-wrap`
   - `line-break`
   - `tab-size`

3. 行盒与对齐：
   - `line-height`
   - `vertical-align`
   - `text-indent`

4. 书写方向：
   - `direction`
   - `writing-mode`
   - `text-orientation`

这组属性的难点在于，它们表面分散，实际上都会在同一个 line layout 和 text run pipeline 里相遇。

### 16.7 绘制属性

- `color`
- `background*`
- `border-radius`
- `box-shadow`
- `opacity`
- `filter`
- `clip-path`

这组属性主要控制元素如何变成可见结果，但它们绝不是“布局完之后最后再随便画一下”。

它们通常依赖：

- paint fragments / display list
- stacking context
- clipping
- compositing
- hit-test boundary

其中可以再区分：

1. 基础绘制：
   - `color`
   - `background*`
   - `border-radius`

2. 效果与混合：
   - `box-shadow`
   - `opacity`
   - `filter`

3. 可见区域控制：
   - `clip-path`

一旦进入 `opacity`、`filter`、`clip-path` 这类属性，绘制系统就会和 compositing、命中测试、滚动边界强耦合。

### 16.8 滚动与视口属性

- `scroll-snap-*`
- `scroll-margin*`
- `scroll-padding*`
- `scrollbar-gutter`
- `overflow-anchor`

这组属性控制的不是普通盒几何，而是滚动容器如何响应输入、程序化滚动和视口对齐。

它们主要依赖：

- scroll container
- scrollport / scroll origin
- hit-test 与输入系统
- scheduler / animation frame

这些属性之所以适合单独成组，是因为它们几乎都以“已有滚动容器”为前提，而不是自己生成布局模式。

其中：

- `scroll-snap-*` 决定滚动结束时的吸附策略
- `scroll-margin*` / `scroll-padding*` 决定对齐时的逻辑边距
- `scrollbar-gutter` 影响滚动条空间是否预留
- `overflow-anchor` 影响内容变化时滚动位置是否被自动修正

### 16.9 包含与隔离

- `contain`
- `content-visibility`
- `contain-intrinsic-size`
- `container-*`

这是现代 CSS 中最偏“引擎优化接口”的一组属性。

它们主要依赖：

- layout / paint containment
- invalidation
- intrinsic size 占位
- query container 建模

这一组属性真正重要的地方不只是功能，而是它们直接影响引擎如何裁剪工作量：

- 哪些子树可以局部布局
- 哪些子树可以跳过绘制
- 不可见内容如何提供占位尺寸
- 样式查询如何基于祖先容器生效

如果前面的样式、布局、绘制、尺寸系统没有先站稳，这组属性几乎不可能正确实现。

## 17. 每类属性未来要补的分析模板

每一类属性都适合按同一模板分析：

1. 语义是什么
2. 影响哪一层
3. 依赖哪些前置机制
4. 与哪些属性强耦合
5. 最小可用实现怎么做
6. 完整行为为什么难
7. 适合在哪个阶段实现

如果目标是把这份文档继续扩展成一本真正可读的 CSS 引擎实现书，那么这一节最好不是“提醒自己以后怎么写”，而是固定成统一章法。

比较稳的写法通常包括下面几个部分。

### 17.1 推荐章节结构

每个属性组或单个关键属性，都可以按下面顺序展开：

1. 语义定义
2. 外部可观察行为
3. 内部概念模型
4. 依赖的前置机制
5. 最小实现路径
6. 完整实现中的边界条件
7. 与测试 / oracle 的关系

这种顺序的好处是：

- 先把“用户看到什么”说清楚
- 再进入“引擎内部需要什么”
- 最后才讨论实现顺序和测试方式

这样读者不会一上来就淹没在细节里。

### 17.2 单节固定问题清单

为了避免不同章节写着写着风格漂移，可以给每一节固定追问下面这些问题：

- 这个属性真正改变的是什么，是树结构、布局、绘制还是交互？
- 它影响的是局部节点，还是会沿祖先 / 后代传播？
- 它的求值发生在 parse、cascade、computed value 还是 used value 阶段？
- 它是否依赖 containing block、intrinsic size、line box、stacking context 等前置概念？
- 它是否可能触发布局失效、绘制失效或 compositing 更新？
- 它有哪些最常见、最容易误判的边界场景？

如果每一节都能稳定回答这些问题，整本书的技术密度和结构一致性就会高很多。

### 17.3 最小章节模板

一个可直接复用的章节模板可以写成：

#### A. 语义

- 属性或属性组的规范语义是什么
- 默认值、继承性、可动画性是什么

#### B. 影响层

- 它影响样式、布局、绘制、命中、滚动、动画中的哪几层

#### C. 依赖链

- 它依赖哪些前置概念
- 它会把结果交给哪些后续系统

#### D. 最小实现

- 最小可用版本支持哪些值
- 明确不支持哪些边界

#### E. 完整复杂度

- 为什么浏览器级完整行为会很难
- 最常见的规范边界在哪里

#### F. 验证方式

- 这一节适合用什么样的 oracle case 验证
- 哪些结果应验证 computed style
- 哪些结果应验证 layout / paint / hit-test

### 17.4 适合加例子的地方

不是所有章节都需要大量例子，但下面几类机制非常适合配对照例子：

- 容易被直觉误解的布局规则
- 依赖多个坐标空间的绘制或命中规则
- 文本与 bidi / caret 相关规则
- intrinsic sizing 与百分比求值边界
- stacking context 与 z-order 规则

例子的目的不是教学式“从零学 CSS”，而是帮助读者理解实现时最容易出错的分叉点。

### 17.5 章节粒度建议

如果要把文档继续写成一本书，章节粒度最好控制在：

- 一个大机制一章
- 一个高复杂度属性族一章
- 一个容易和其他机制强耦合的主题一章

不太适合的写法通常是：

- 一章塞几十个属性但没有统一机制
- 只按规范目录平铺，不解释内部依赖
- 一个章节同时横跳样式、布局、绘制、交互而没有主轴

更理想的写法是让读者每读完一章，都能明确知道：

- 这个主题解决什么问题
- 它在引擎流水线里的位置
- 它和上下游模块如何连接
- 实现时最危险的误区是什么

## 18. 实现阶段大纲

这里只列大阶段，重点是先明确实现顺序和能力边界。

### Phase A：极简样式系统

目标：

- 支持最基础的样式解析
- 不做完整 cascade
- 不做复杂 selector
- 支持少量盒模型与绘制属性

这一阶段的重点不是“先把 CSS 做得很像 CSS”，而是建立最小闭环：

- 输入样式
- 生成简单样式结果
- 建立基础 box
- 做出最基础布局
- 画出可见结果

更适合在这一阶段落地的能力通常是：

- type / class / id 级别的简单 selector
- author origin + source order 的基础 cascade
- `display: block | inline`
- 简单 `width/height/padding/margin`
- 基础 `color/background/border`

这一阶段应明确避开：

- 复杂文本排版
- 完整 intrinsic sizing
- float / sticky / grid
- 高级 compositing

如果 Phase A 不能形成完整闭环，后面所有阶段都会缺乏可验证基线。

### Phase B：基础布局引擎

目标：

- block / inline 基础布局
- 绝对定位
- 基础文本排版
- 基础 overflow

这一阶段的重点是让系统从“会显示东西”变成“具备基础文档布局能力”。

关键任务通常包括：

- block formatting context
- inline formatting context 的最小实现
- basic line box
- absolute / fixed 的基础 containing block
- overflow hidden / auto 与简单滚动偏移

Phase B 最关键的成果不是属性数，而是系统第一次真正拥有：

- 正常流
- 行内排版
- 脱流定位
- 基础可滚动区域

一旦这一阶段稳定，系统就已经具备很多编辑器和简单 UI 所需的基础。

### Phase C：编辑器可用布局

目标：

- flex 单轴
- 简化 intrinsic size
- 文本命中与 selection
- 滚动容器

这一阶段开始，目标从“能布局”转成“能交互、能编辑、能处理真实 UI 组件”。

更适合在这里推进的能力包括：

- 单轴 flex
- shrink-to-fit 的简化版本
- caret hit test
- selection geometry
- 嵌套滚动容器
- 基础 transform 命中或至少 scroll + clip 命中链

Phase C 的成功标准通常不是页面截图，而是：

- 输入框、文本块、列表、工具栏这类结构已经能稳定交互
- 点击、选择、滚动这些行为不会轻易错位
- 简单响应式布局开始可用

对于 MetaEditor 这样的系统，这通常是最具产品价值的一阶段。

### Phase D：通用 UI 布局

目标：

- 更完整 flex
- 基础 grid
- stacking context
- transform / opacity / clipping

这一阶段开始进入“逼近浏览器级 UI 能力”的区域。

适合在这里推进的能力包括：

- 多行 flex 和更完整对齐语义
- 基础 grid track sizing 与 auto placement
- stacking context
- opacity / transform / clip-path 的稳定绘制行为
- 局部 compositing

这一阶段最大的风险通常不是单个模块写不出来，而是：

- intrinsic sizing 还不稳
- paint order 和 hit-test order 脱节
- transform / scroll / clip 参考系没有统一

所以 Phase D 更像是一次系统性收敛，而不只是继续加属性。

### Phase E：逼近浏览器行为

目标：

- 更完整 intrinsic sizing
- 更完整 formatting context
- 更复杂文本排版
- 更多 CSS 属性兼容

这一阶段的重点是补“浏览器之所以像浏览器”的边界行为，而不是简单扩充功能表。

典型工作通常包括：

- 更完整的 shrink-to-fit / min-content / max-content
- 更细的 formatting context 与 anonymous box 规则
- bidi / shaping / writing-mode 的更多边界
- fragmentation、多列、复杂滚动与动画组合
- 更完善的 oracle case 与回归体系

这也是最容易掉进无限细节泥潭的阶段，因此必须坚持两件事：

1. 继续按机制分层推进，而不是逐个 patch 现象
2. 用 oracle case 管理兼容性，而不是靠印象追行为

### 18.6 跨阶段原则

无论处于哪个阶段，都有几条原则最好保持不变：

1. 先形成闭环，再增加复杂度
2. 先建立稳定概念模型，再补边界规则
3. 先区分 layout / paint / hit-test / compositing 的边界，再做优化
4. 每加一类复杂属性，都要明确它落在哪条依赖链上
5. 每前进一步，都要保留可对比的 oracle case

如果没有这些原则，阶段划分很容易退化成“看起来写了很多，但系统越来越难收束”。

## 19. 依赖图大纲

这一节不只是为了画一张漂亮图，而是为了防止实现顺序判断失真。CSS 引擎里很多问题之所以难，不是单点机制本身多复杂，而是依赖方向一旦搞错，工程实现就会不断返工。

至少要明确下面这些主依赖链：

- selector / cascade 在 layout 前
- text shaping 在 inline formatting 前
- intrinsic size 参与 flex / grid
- overflow / clipping 依赖布局结果
- hit-test 依赖布局与绘制结果
- animation 会反向影响布局或绘制

更具体地说，可以把系统粗分成这几条主链：

1. 样式链
   - parser
   - selector matching
   - cascade
   - value resolution

2. 结构与布局链
   - box tree / formatting tree
   - normal flow / flex / grid
   - intrinsic sizing
   - fragment generation

3. 文本链
   - font matching
   - shaping
   - bidi
   - line breaking
   - inline formatting

4. 绘制与交互链
   - paint fragments / display list
   - stacking context
   - compositing
   - hit testing
   - selection / caret geometry

5. 运行时链
   - invalidation
   - scrolling
   - animation timeline
   - scheduler / frame production

真正的实现顺序不能只按“规范章节顺序”排，而要按这些依赖链收敛。

## 20. 最困难的三大问题

这一节不是为了制造神秘感，而是为了明确哪些问题最可能吞噬时间、并迫使架构回退。

1. 文本排版系统
2. intrinsic sizing 与尺寸协商
3. formatting context / box tree 的完整语义

### 20.1 文本排版系统

它困难，不是因为“字符很多”，而是因为文本天然跨越了：

- 字体匹配
- shaping
- bidi
- line break
- 行高
- caret / selection
- 命中测试

这意味着文本不是布局系统旁边的一个附件模块，而是 inline formatting 的核心地基。

只要文本结果不稳定，下面这些能力都会一起失真：

- inline 尺寸计算
- baseline 对齐
- 点击定位
- 选区高亮
- 滚动到 caret

### 20.2 intrinsic sizing 与尺寸协商

尺寸系统困难的地方在于：很多元素尺寸不是“自己说了算”，而是多个约束相互协商的结果。

例如：

- 父容器给出的 available space
- 子内容的 min-content / max-content
- `min/max-width`
- 百分比与不明确尺寸
- `aspect-ratio`
- flex / grid 的分配算法

一旦 intrinsic sizing 没建模清楚，布局结果就会在复杂组合下持续出现“局部看着对，整体一塌糊涂”的情况。

### 20.3 formatting context / box tree 的完整语义

box tree 之所以难，是因为它不是 DOM tree 的简单镜像。

你必须处理：

- anonymous box
- formatting context 切换
- 脱流元素
- replaced element
- list marker
- fragmentation
- 伪元素与生成内容

这些规则共同决定“真正参加布局和绘制的结构到底是什么”。如果这一层定义不稳，后面所有模块都会被迫补丁式修修补补。

## 21. 与浏览器 oracle 的关系

这里所谓 browser oracle，指的是把浏览器行为当作外部真值来源，用来校验具体 CSS 组合的结果，而不是把浏览器实现细节直接当作内部设计。

它的价值主要在四个方面：

- Playwright / 浏览器引擎可作为真值来源
- 可用于生成回归样例
- 可用于验证具体属性组合行为
- 不能替代机制建模本身

### 21.1 它适合做什么

- 验证某组输入在主流浏览器中的 computed style / layout / paint 结果
- 为边界行为建立最小复现样例
- 在重构或补属性时做回归对比
- 为不确定的规范解读提供经验校验

### 21.2 它不适合做什么

- 不能直接替代内部概念模型
- 不能把“浏览器现在这么表现”自动等同于“我们的机制设计就该这么拼”
- 不能解决实现顺序、模块边界、数据结构设计问题

### 21.3 合理使用方式

更合理的方式通常是：

1. 先在文档里说明某机制的概念边界
2. 再为具体边界条件写 oracle case
3. 用浏览器结果校验外部行为
4. 但内部仍按自己的机制分层实现

对于 MetaEditor 这类项目，这种方式尤其重要，因为它能防止系统退化成“追着浏览器 patch 行为”的无穷游戏。

### 21.4 oracle case 的组织方式

如果要把 browser oracle 真正用起来，测试样例最好不要只是零散 HTML 文件，而要有稳定目录和命名约定。

比较实用的组织方式通常是：

1. 按机制分目录：
   - `normal-flow/`
   - `intrinsic-sizing/`
   - `inline-text/`
   - `painting/`
   - `hit-test/`

2. 每个 case 至少包含：
   - 输入 HTML / CSS
   - 关注点说明
   - 期望采集项
   - 相关规范或问题说明

3. 采集项分层：
   - computed style
   - layout rect
   - scroll metrics
   - screenshot
   - hit-test result

这样做的价值在于，样例本身既是测试资产，也是文档附录。

### 21.5 哪些结果适合比什么

不是所有行为都适合截图对比，oracle case 也应该按结果类型选择验证方式。

更稳的经验通常是：

- 样式求值问题：
  - 优先比 computed style

- 几何布局问题：
  - 优先比 box rect、line box、scroll range

- 绘制顺序或视觉效果问题：
  - 优先比 screenshot 或 paint-order probe

- 命中测试问题：
  - 优先比 `elementFromPoint`、caret position、selection range

- 动画问题：
  - 优先比时间点采样，而不是只看最终帧

如果所有问题都退化成截图比对，很多机制错误会变得很难定位。

### 21.6 从文档到 oracle 的映射

最理想的状态不是“写完文档后再想测试”，而是每一章都天然对应一组 oracle case。

一种更稳的做法是：

- 文档章节定义概念模型
- 每个概念边界配 1 到 3 个最小样例
- 每个样例只验证一个主要结论
- 样例名称直接反映机制，而不是只反映视觉现象

例如：

- `intrinsic-sizing/shrink-to-fit-with-percentage-child`
- `painting/stacking-context-opacity-vs-zindex`
- `hit-test/transformed-inline-caret-position`

这种命名方式会迫使测试和机制模型保持一致。

### 21.7 oracle 的局限与防滥用

browser oracle 很有价值，但它也很容易被滥用。

最常见的误区包括：

- 看到浏览器行为就直接照搬，却没解释背后的机制
- 一个 case 同时验证太多结论，导致失败后无法定位
- 把浏览器 bug 或兼容差异误当成唯一真理
- 为了追平截图而不断加局部特判

更好的原则通常是：

1. 先建立概念模型，再用 oracle 校验
2. 一个 case 只服务少量明确结论
3. 当浏览器存在差异时，先记录分歧，再判断目标行为
4. 不让 oracle 反客为主，替代内部架构判断

## 22. 与 MetaEditor 主路线的关系

这份文档放在 `legacy/`，意味着：

- 它不是 MetaEditor 当前执行主线
- 当前主线仍然是浏览器主运行时 + 结构化 CLI 接口
- 但如果未来再次回到“自持布局 / 自持样式系统”的方向，这份路线图可以作为长期计划书的骨架

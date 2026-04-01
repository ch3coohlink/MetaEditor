# Pretext 对照笔记

这份笔记只记录 `../pretext-main` 和当前 `doc/legacy` 文本路线最相关的结论。

目标很收窄：

- 它现在在做什么
- 它和 MetaEditor 现有文本设计哪几处对得上
- 如果完全沿这条路走，最好能做到哪里
- 哪些边界会很快卡住

## 1. Pretext 的主路径

`pretext` 的核心不是通用文本引擎，而是一套浏览器内的段落测量与断行库。

主路径很清楚：

1. `prepare(text, font, options?)`
2. 分析文本
3. 用 `Intl.Segmenter` 和一套预处理规则切 segment
4. 用 canvas `measureText` 测宽并缓存
5. `layout(prepared, width, lineHeight)` 只做纯算术断行

它的重点不是拿到更多字体内部真相，而是把热路径稳定压成“不碰 DOM 的算术”。

公开能力主要是：

- 段落高度
- 行数
- 每行文本和范围
- 一行一行地流式布局

对应 API 大致是：

- `prepare`
- `prepareWithSegments`
- `layout`
- `layoutWithLines`
- `walkLineRanges`
- `layoutNextLine`

## 2. 它已经覆盖了哪些真实问题

它并不只是“对整段文字调一次 `measureText`”。

从实现和研究记录看，它已经收了这些内容：

- `white-space: normal`
- `whiteSpace: 'pre-wrap'`
- `overflow-wrap: break-word`
- grapheme / word segmentation
- CJK 断行相关规则
- 标点粘连和若干脚本上的局部 glue 规则
- soft hyphen
- emoji 宽度修正
- 一部分 bidi 相关元数据
- 按浏览器 profile 做窄 shim

它还有一整套 browser oracle / accuracy / benchmark 工具链。

这部分和 `legacy` 文档里“浏览器要当 oracle 用，但不能把机制建模吞掉”的主张很接近。

## 3. 和 MetaEditor 现有文档对得上的地方

最接近的是这三份：

- `text-measuring.md`
- `text-roadmap.md`
- `text-v1.md`

对得上的核心判断有三条。

### 3.1 阶段 A 路线高度一致

`legacy` 里已经明确，第一阶段可以先站在：

- `Intl.Segmenter`
- 浏览器 `measureText`
- prefix cache
- 基础 wrap

之上，把编辑器文本几何先跑起来。

`pretext` 本质上就是把这条路线推进成一个能落地的库。

### 3.2 浏览器 oracle 的定位一致

`legacy` 里强调：

- 浏览器适合当真值来源
- 适合生成回归样例
- 适合对拍
- 不能替代机制建模

`pretext` 的验证体系也是这个思路。它没有把 DOM 布局当运行时主路径，而是把浏览器更多放在校验和收敛上。

### 3.3 先把 line layout 收稳，再谈更深真相

`pretext` 的实际经验说明了一件事：

- 先把 segmentation、测宽、断行和验证链路收稳
- 比过早把 shaping / 字体内部真相拉进主路径更有产出

这一点对 MetaEditor 的阶段推进很有参考价值。

## 4. 和 MetaEditor 设计不一样的地方

虽然方向接近，但 `pretext` 的边界比 `legacy` 设想窄很多。

### 4.1 它是段落断行库，不是编辑器文本引擎

`legacy/text-v1.md` 想要的公共对象更像：

- `ParagraphLayout`
- `caret_rect`
- `selection_rects`
- `hit_test`

`pretext` 目前停在“行布局和范围”这一层，没有把编辑器查询 API 直接做出来。

### 4.2 它没有显式的后端能力模型

`legacy/text-roadmap.md` 里强调：

- capability
- support level
- result quality
- source
- unsupported reason

`pretext` 没有这一层。它更像一个单后端成品，默认运行环境就是浏览器。

### 4.3 它没有把字体和 shaping 真相拉出来

`legacy/text-measuring.md` 的长期方向里有：

- bidi
- shaping
- fallback
- glyph metrics

`pretext` 当前并不打算朝这边展开。它更像是在证明：

- 浏览器 canvas 足够当阶段性宽度真值
- 只要预处理和断行策略做对，很多场景已经能很好用

## 5. “少量 DOM 校准”具体指什么

`pretext` 的主路径强调不依赖 DOM 布局。

但它有一个很小的例外：emoji 宽度修正。

某些浏览器环境里，canvas 对 emoji 的 `measureText` 会比 DOM 实际显示宽。

所以它会在少数情况下：

1. 先用 canvas 测 emoji 宽度
2. 再临时创建一个隐藏 `span`
3. 用 `getBoundingClientRect()` 读一次真实 DOM 宽度
4. 算出差值
5. 缓存这份修正值

后续再测含 emoji 的 segment 时，直接用缓存修正，不把 DOM 读带进热路径。

这里的关键点是：

- DOM 不是主测量路径
- DOM 只在发现稳定偏差时做一次校准
- 校准结果进入缓存

这可以看成一种很小粒度的 browser oracle 内嵌用法。

## 6. 如果完全沿 Pretext 这条路走，最好能做到哪里

如果 MetaEditor 在一段时间内完全采用这条路线，不自己碰显式字体解析、shaping、fallback，最好能做到一个“编辑器可用的文本几何 v1.5”。

上限大致是：

- 单段落、多行纯文本的稳定换行
- 稳定的段落高度、行数、行宽
- 基于 line layout 和 grapheme 边界实现 `index -> caret`
- 基于同一套布局实现 `range -> selection rects`
- 基于前缀宽度和行范围实现 `(x, y) -> text index`
- 先把 `LTR + Latin/CJK` 做稳
- 在浏览器环境里通过 oracle 对拍持续收敛

如果只看代码编辑器或纯文本编辑器核心区，这个阶段已经很有实用价值。

## 7. 这条路的硬边界

如果完全不自己碰字体和 shaping，边界也会很清楚。

### 7.1 复杂脚本很难给强保证

包括但不限于：

- 复杂 shaping
- 混合 bidi
- cluster 级命中
- 更严格的 caret movement

这些能力只靠段落级 `measureText` 和断行策略，很难完全收严。

### 7.2 跨平台统一逻辑真相会受限

因为底层真值仍然主要来自浏览器和平台字体栈，所以：

- 浏览器内能很强
- 浏览器外复现会难很多
- 想做平台无关的同一份文本真相，会碰到上限

### 7.3 很难走到完整富文本段落

只要进入显式 style run，问题就会明显升级。

## 8. 单段内不同 font 设置能不能做

按 `pretext` 当前主路径，严格说，做不好。

原因很直接：

- 它的公共 API 默认整段只接一个 `font`
- 分段、测宽、缓存、断行都建立在“整段共享同一套字体度量环境”这个前提上

如果单段内存在这些情况：

- 不同 `font-family`
- 不同 `font-size`
- 不同 `font-weight`
- code span / emoji / icon 用局部字体

那现成 API 都不直接支持。

### 8.1 理论上能不能硬接

理论上可以先把段落切成多个 style run，再按 run 去测宽，然后把结果拼回同一条断行流水线。

但一旦这样做，马上会碰到这些问题：

- segment 边界和 style run 边界要重新对齐
- 标点粘连和空白折叠会跨 run
- prefix width 不再是单字体前缀
- 行高和 baseline 会被局部字体影响
- caret 高度和 selection rect 高度要跟哪一个 run 走，需要新规则

所以这已经不是“直接沿用 `pretext`”，而是在往显式 inline run layout 走。

### 8.2 哪种程度还有机会保留这条路线

如果限制得很死，也许还能勉强保留大部分思路，例如：

- 同一段只允许局部换 family 或 weight
- 字号不变
- line height 不变
- 不追求复杂脚本严格正确

即便如此，也已经需要引入：

- style run
- run 级测宽
- run 级几何查询

这会把系统从“单字体段落布局”推到“简化富文本 inline layout”。

## 9. 对 MetaEditor 的实际价值

当前看，`pretext` 更适合三种定位。

### 9.1 参考实现

这是最稳的用法。

直接借鉴：

- `prepare -> layout` 的二段结构
- 各类预处理和断行细节
- browser oracle 的工具链组织方式

### 9.2 过渡后端

也成立。

把它放在 MetaEditor 的文本抽象层下面，先负责：

- segmentation + width cache
- line layout
- 高度和行范围

然后由上层继续补：

- caret
- selection
- hit-test

### 9.3 最终长期架构

不太适合作为终点。

原因不是它不够强，而是它故意把问题收窄在“浏览器内段落布局”。

如果 MetaEditor 长期要的是：

- 更完整的文本真相
- 更明确的能力边界
- 富文本段内多样式
- 浏览器外一致性

那还需要再往下走一层。

## 10. 当前可收束的判断

可以先把结论收成下面几句。

1. `pretext` 证明了 `Intl.Segmenter + canvas measureText + 纯算术 layout + browser oracle` 这条路线足以做出强实用的段落布局库。
2. 这条路线非常适合 MetaEditor 文本几何的第一阶段，尤其适合纯文本编辑核心区。
3. 它还不足以直接覆盖 `legacy` 里想要的完整编辑器查询对象。
4. 一旦进入单段多字体、多样式、复杂脚本严格支持，就不能再把整段当成单一 font 文本处理。
5. 如果后续真要走 rich text / 更深文本真相，系统需要显式引入 run 级模型，不能只在当前段落模型上继续拼补丁。

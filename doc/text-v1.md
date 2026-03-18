# MetaEditor 文本测量 V1 规格

这份文档是实现期规格，目标是给 `Intl.Segmenter + measureText` 这条 v1 路线一个足够精确、可以频繁查阅的定义。

它不重复 [text-measuring.md](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/text-measuring.md) 里的完整技术栈分析，也不重复 [text-roadmap.md](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/text-roadmap.md) 里的长期 API 路线。这里只关心：

- v1 到底做什么
- 不做什么
- 输入输出长什么样
- 缓存怎么建
- 查询接口怎么定义

## 1. V1 目标

V1 只服务于一条明确收窄的路径：

- `LTR`
- `Latin + CJK`
- 常见编辑器字体
- 单段落 / 多行纯文本编辑
- 基础 caret / selection / hit-test / wrap

V1 的目标不是拥有完整逻辑层文本真相，而是先建立一套**稳定的文本测量接口与几何模型**，让上层编辑器可以先跑起来，并为后续替换底层实现留出口。

## 2. V1 明确支持

- 使用 `Intl.Segmenter` 做 grapheme / word segmentation
- 使用浏览器 `canvas.measureText` 做字符串宽度测量
- 支持 prefix width 查询
- 支持基础软换行
- 支持 `(text index -> caret rect)`
- 支持 `(range -> selection rect[])`
- 支持 `(x, y -> text index)` hit-test
- 支持 line layout / visual rows
- 支持基于缓存的重复查询

## 3. V1 明确不支持

- RTL
- bidi
- 复杂脚本 shaping 的显式逻辑层实现
- 显式字体 fallback introspection
- 获取 glyph id / cluster map
- vertical writing
- 精细 OpenType feature 控制
- 浏览器外完全一致的文本真相

这意味着：

- V1 允许隐式依赖浏览器内部的 shaping 和 fallback
- 但这些内容不进入逻辑层中间产物
- 文档和 API 必须诚实表达这件事

## 4. V1 核心判断

对 `LTR + Latin/CJK + 常见编辑器字体` 这条路径，真正会阻塞实现的不是 segmentation，而是 shaping / 字体 fallback 的完整显式建模。但这两块在 V1 不进入逻辑层，并不会在绝大多数目标场景里造成实际问题。

因此 V1 采取下面这个策略：

- segmentation 显式化
- 宽度测量显式化
- line layout 显式化
- caret / selection / hit-test 显式化
- shaping / fallback 保持浏览器黑盒

## 5. V1 流水线

### 5.1 输入

V1 输入固定为：

```mbt
type TextStyle = {
  font_families: Array[String],
  font_size: Double,
  font_weight: String?,
  font_style: String?,
  line_height: Double,
  letter_spacing: Double?,
  word_spacing: Double?,
  tab_size: Int,
}

type ParagraphInput = {
  text: String,
  width: Double,
  style: TextStyle,
  locale: String?,
}
```

其中：

- `text` 是原始段落文本
- `width` 是当前可用排版宽度
- `style` 是 V1 可识别的最小文本样式
- `locale` 只影响 segmentation / break 候选，不引入更复杂 locale 特化

### 5.2 处理中间阶段

V1 只保留下面几层显式中间结果：

1. `TextUnitMap`
2. `SegmentationResult`
3. prefix width cache
4. `LineLayout[]`
5. geometry queries

V1 不显式保留：

- bidi runs
- script runs
- font runs
- shaped runs
- glyph metrics

### 5.3 输出

V1 最终输出固定为：

```mbt
type ParagraphLayout = {
  text: String,
  width: Double,
  style: TextStyle,
  units: TextUnitMap,
  segmentation: SegmentationResult,
  lines: Array[LineLayout],
  content_width: Double,
  content_height: Double,
}
```

以及基于 `ParagraphLayout` 的查询结果：

- `caret_rect`
- `selection_rects`
- `hit_test`

## 6. 核心数据结构

### 6.1 文本单位映射

```mbt
type TextUnitMap = {
  text: String,
  line_starts: Array[Int],
  grapheme_boundaries: Array[Int],
}
```

V1 只强制要求：

- 行起点映射
- grapheme 边界映射

V1 不强制显式保存 code point 映射；如果后续实现需要，可以内部维护，但不进入 v1 公共接口。

### 6.2 segmentation 结果

```mbt
type Segment = {
  start: Int,
  end_: Int,
}

type WordSegment = {
  start: Int,
  end_: Int,
  kind: String,
}

type BreakCandidate = {
  index: Int,
  kind: String,
}

type SegmentationResult = {
  graphemes: Array[Segment],
  words: Array[WordSegment],
  break_candidates: Array[BreakCandidate],
}
```

V1 只需要：

- graphemes：给 caret / 删除 / hit-test 提供合法落点
- words：给后续按词移动预留
- break_candidates：给 wrap 提供候选位置

V1 不需要 sentence segmentation 进入公共接口。

### 6.3 prefix width cache

```mbt
type PrefixWidthCache = {
  text: String,
  font_key: String,
  widths: Array[Double],
}
```

约定：

- `widths[i]` 表示从文本起点到第 `i` 个 grapheme 边界的宽度
- `widths[0] = 0`
- 数组长度等于 `graphemes.length + 1`

这是 V1 最关键的数据结构之一。V1 的：

- caret x
- selection left/right
- hit-test
- wrap 二分

都建立在它之上。

### 6.4 visual line 与段落布局

```mbt
type LineLayout = {
  line_index: Int,
  text_start: Int,
  text_end: Int,
  top: Double,
  bottom: Double,
  baseline: Double,
  width: Double,
}

type ParagraphLayout = {
  text: String,
  width: Double,
  style: TextStyle,
  units: TextUnitMap,
  segmentation: SegmentationResult,
  prefix_widths: PrefixWidthCache,
  lines: Array[LineLayout],
  content_width: Double,
  content_height: Double,
}
```

V1 的 `LineLayout` 故意很薄：

- 不保存 glyph fragment
- 不保存 run fragment
- 只保存文本区间与几何

因为 V1 没有显式 shaping 层。

## 7. 核心后端能力定义

### 7.1 支持等级

```mbt
enum SupportLevel {
  None
  Basic
  Approximate
  Exact
  BlackBox
}
```

### 7.2 V1 能力矩阵

V1 的能力应明确表达为：

```mbt
type TextEngineCapabilities = {
  grapheme_segmentation: SupportLevel,
  word_segmentation: SupportLevel,
  line_break: SupportLevel,
  bidi: SupportLevel,
  shaping: SupportLevel,
  glyph_metrics: SupportLevel,
  caret_metrics: SupportLevel,
  selection_geometry: SupportLevel,
  hit_testing: SupportLevel,
}
```

V1 的推荐值：

```mbt
{
  grapheme_segmentation: BlackBox,
  word_segmentation: BlackBox,
  line_break: Approximate,
  bidi: None,
  shaping: BlackBox,
  glyph_metrics: None,
  caret_metrics: Approximate,
  selection_geometry: Approximate,
  hit_testing: Approximate,
}
```

解释：

- `Intl.Segmenter` 仍然属于黑盒引擎能力，因此标 `BlackBox`
- `line_break` 由我们自己基于 break candidates + 宽度约束做，因此标 `Approximate`
- `shaping` 由浏览器隐式承担，但我们拿不到中间产物，因此标 `BlackBox`

## 8. 结果封装

### 8.1 可信度与来源

```mbt
enum MeasureQuality {
  Approximate
  Exact
  BlackBox
}

enum MeasureSource {
  BrowserCanvas
  BrowserDom
  IntlSegmenter
  Custom
}

type Measured[T] = {
  value: T,
  quality: MeasureQuality,
  source: MeasureSource,
}
```

V1 中：

- segmentation 结果来源通常是 `IntlSegmenter`
- 宽度与几何结果来源通常是 `BrowserCanvas`
- line layout / hit-test 是基于这些黑盒输入做的逻辑推导，来源标 `Custom`

### 8.2 不支持结果

```mbt
enum UnsupportedReason {
  BidiNotSupported
  VerticalLayoutNotSupported
  BlackBoxOnly
}

enum MeasureResult[T] {
  Ok(Measured[T])
  Unsupported(UnsupportedReason)
}
```

V1 里不需要做很细的错误体系，但必须显式表达“不支持”。

## 9. V1 引擎接口

V1 只需要一组最小接口。

```mbt
trait TextMeasureEngine {
  capabilities() -> TextEngineCapabilities

  segment_text(
    text: String,
    locale: String?
  ) -> SegmentationResult

  layout_paragraph(
    input: ParagraphInput
  ) -> MeasureResult[ParagraphLayout]

  caret_rect(
    layout: ParagraphLayout,
    index: Int
  ) -> MeasureResult[Rect]

  selection_rects(
    layout: ParagraphLayout,
    range: TextRange
  ) -> MeasureResult[Array[Rect]]

  hit_test(
    layout: ParagraphLayout,
    x: Double,
    y: Double
  ) -> MeasureResult[HitTestResult]
}
```

V1 不单独暴露：

- `resolve_fonts`
- `shape_runs`
- `measure_run`

这些接口保留给后续版本，不进入 v1 公共规格。

## 10. V1 关键算法约定

### 10.1 segmentation

- 优先使用 `Intl.Segmenter`
- grapheme 边界是基础位置系统
- word boundaries 仅作为后续能力预留，v1 实现期可以先不被上层大量依赖

### 10.2 prefix width

- 以 grapheme prefix 为单位建立宽度表
- 每个前缀宽度通过 `measureText(prefix)` 计算
- 必须缓存，不允许在 hit-test / caret 查询时反复全量测量

### 10.3 wrap

- 先根据 `break_candidates` 尝试断行
- 如果在当前候选集中找不到合适断点，则退化到 grapheme 级断行
- 允许使用二分找最大可容纳前缀

### 10.4 caret

- `caret_rect` 的 `x` 由 prefix width 给出
- `y/top/bottom` 由 line layout 给出
- caret 高度直接使用当前行高

### 10.5 selection

- 单行 selection 返回一个 rect
- 多行 selection 返回多个 rect
- 每行的 left/right 由 prefix width 差值得出

### 10.6 hit-test

- 先根据 `y` 定位目标行
- 再在该行文本区间内用 prefix width 做最近位置查找
- 返回的 index 必须对齐到 grapheme 边界

## 11. 缓存策略

### 11.1 缓存层级

V1 至少要有三层缓存：

```mbt
type LayoutCache = {
  segmentation: SegmentationResult?,
  prefix_widths: PrefixWidthCache?,
  paragraph_layout: ParagraphLayout?,
}
```

### 11.2 失效规则

- 文本变化：全部失效
- 字体相关样式变化：prefix width 与 layout 失效
- 宽度变化：仅 layout 失效，segmentation 与 prefix width 可保留
- locale 变化：segmentation 与 layout 失效

### 11.3 缓存目标

V1 的目标不是做到最优缓存，而是确保：

- 频繁的 caret 查询不重测
- hit-test 不重做整段 wrap
- selection rect 计算不重新跑 segmentation

## 12. 已知边界与行为约束

### 12.1 我们接受的近似

V1 明确接受这些近似：

- 浏览器内部 shaping 与 fallback 不进入逻辑层
- 宽度真值来自 `measureText`
- line break 不是完整 ICU/UAX14 等效实现
- 几何结果在复杂脚本下不承诺精确

### 12.2 我们不接受的混乱

即使是近似实现，V1 也不允许：

- 位置不对齐到 grapheme 边界
- 同一输入下查询结果不稳定
- 文档里不写清哪些能力缺失
- 上层直接偷调浏览器 API 绕过引擎

## 13. 实现顺序建议

V1 建议按下面顺序落地：

1. `TextStyle` / `ParagraphInput` / `ParagraphLayout` / `TextRange`
2. `TextUnitMap` / `SegmentationResult`
3. `segment_text`
4. `PrefixWidthCache`
5. `layout_paragraph`
6. `caret_rect`
7. `selection_rects`
8. `hit_test`
9. `LayoutCache`
10. `TextEngineCapabilities` / `Measured[T]` / `MeasureResult[T]`

这里故意把“能力矩阵”和“可信度封装”放得稍后一点，因为实现闭环优先，但接口层必须在最终成型前补齐。

## 14. V1 最终结论

V1 的核心不是“把文本测量做完整”，而是：

- 用 `Intl.Segmenter + measureText` 把文本编辑器核心几何闭环跑起来
- 建立一套稳定的段落布局与查询接口
- 清楚标注当前能力边界
- 不让上层直接依赖浏览器黑盒 API

只要这几点做到，V1 就已经具备了后续平滑升级到更完善文本测量系统的基础。

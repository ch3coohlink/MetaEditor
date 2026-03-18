# MetaEditor 文本测量系统路线设计

这份文档承接 [text-measuring.md](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/text-measuring.md)，目标不是继续分析底层技术栈，而是回答一个更工程化的问题：

- 我们应该设计出什么样的 API，才能先接基础的、外置的文本测量能力
- 然后再逐步平滑过渡到更完善的、更多逻辑层真相的、自研或半自研文本测量系统

这里强调的是**路线设计**，不是最终实现细节，也不是具体库绑定代码。

## 1. 设计目标

文本测量系统的 API 设计必须同时满足下面几个目标：

- 上层组件不直接依赖浏览器 `measureText`、DOM selection、黑盒 layout
- 不同阶段的底层实现可以替换，但上层编辑器接口尽量不变
- 系统能够非常清楚地声明当前版本“能做什么 / 不能做什么”
- 结果不仅有数值，还能表达这个数值的可信度与来源
- 允许在一段时间内同时存在多种后端：
  - 浏览器黑盒后端
  - 混合后端
  - 更完整的逻辑层后端

如果这几个目标不同时成立，那么文本测量系统后面一定会出现两个问题：

- API 绑死在当前临时实现上，后面无法替换
- 上层根本不知道当前结果是“精确真相”还是“暂时近似”

## 2. 总体原则

### 2.1 能力分层，不做一锅端接口

不要试图用一个 `layout_text()` 或一个 `measure_text()` 把整条文本流水线糊掉。

文本测量系统至少要显式区分：

- segmentation
- shaping
- line break
- paragraph layout
- geometry query

如果这些能力全都藏在一个黑盒函数后面，那么：

- 后续无法单独替换某一层
- 上层无法知道失败到底发生在哪一层
- 测试也无法知道当前后端的能力边界

### 2.2 结果对象比零散函数更重要

不要只暴露下面这种零碎能力：

- 测字符串宽度
- 算一个 caret x
- 找最近列号

更稳定的边界是中间结果对象：

- `SegmentationResult`
- `ShapedRun`
- `ParagraphLayout`
- `LayoutCache`

底层实现会变，但这些对象的语义可以长期稳定。

### 2.3 API 必须显式暴露“不支持”

文本系统不同阶段的能力差异会非常大。

例如某个实现可能：

- 支持 grapheme segmentation
- 不支持 bidi
- 只能通过浏览器黑盒得到 caret rect
- 完全不能暴露 glyph metrics

这些差异不能靠 README 口头说明，必须进入 API。

### 2.4 上层只能依赖抽象能力，不能依赖当前后端

上层编辑器逻辑不应该知道自己当前跑的是：

- `Intl.Segmenter`
- `measureText`
- `linebreak`
- `harfbuzzjs`
- 还是未来自研实现

上层只应该依赖稳定的抽象接口，否则后面每替换一次底层，组件层都要重写一遍。

## 3. 能力层设计

### 3.1 为什么能力层必须是一等公民

MetaEditor 文本系统不会只有一种实现形态。至少会经历：

1. 先用浏览器黑盒能力把编辑器核心闭环跑起来
2. 再逐步引入更显式的 segmentation / line break / shaping
3. 最后才可能拥有更完整的逻辑层真相

因此必须先有一个统一的能力描述对象，让系统和测试都能明确知道当前引擎的边界。

### 3.2 MoonBit 风格能力模型

```mbt
enum SupportLevel {
  None
  Basic
  Approximate
  Exact
  BlackBox
}

enum WritingMode {
  HorizontalTb
  VerticalRl
  VerticalLr
}

enum Direction {
  Ltr
  Rtl
}

enum ScriptCoverage {
  Limited
  Common
  Wide
  Full
}

type TextEngineCapabilities = {
  grapheme_segmentation: SupportLevel,
  word_segmentation: SupportLevel,
  sentence_segmentation: SupportLevel,
  line_break: SupportLevel,
  bidi: SupportLevel,
  shaping: SupportLevel,
  font_fallback_introspection: SupportLevel,
  glyph_metrics: SupportLevel,
  caret_metrics: SupportLevel,
  selection_geometry: SupportLevel,
  hit_testing: SupportLevel,
  writing_modes: Array[WritingMode],
  directions: Array[Direction],
  scripts: ScriptCoverage,
}
```

### 3.3 这层解决什么问题

有了这层之后：

- 上层可以根据能力决定走哪条交互路径
- 测试可以区分“功能缺失”和“实现错误”
- 文档可以非常诚实地说明当前系统做到了哪
- 不同后端可以同时共存

例如：

```mbt
let caps = engine.capabilities()
if caps.bidi == None {
  // 明确禁用 rtl 文本的严格编辑功能
}
```

## 4. 结果可信度与来源

### 4.1 为什么不能只返回值

对文本测量系统来说，下面这三种结果在工程上完全不是一回事：

- 由浏览器黑盒直接给出的结果
- 由简化算法近似得出的结果
- 由逻辑层完整流水线计算出的结果

如果 API 只返回一个 `width` 或 `rect`，上层无法分辨这三者。

### 4.2 MoonBit 风格结果封装

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
  ICU
  ICU4X
  HarfBuzz
  FontKit
  Custom
}

type Measured[T] = {
  value: T,
  quality: MeasureQuality,
  source: MeasureSource,
}
```

### 4.3 这层的意义

例如：

```mbt
Measured[Double]
Measured[Rect]
Measured[HitTestResult]
```

都能明确告诉系统：

- 这个结果是不是精确结果
- 这个结果是否来自浏览器黑盒
- 当前阶段能不能用它做严格断言

这对后续“逻辑层真相”迁移特别重要，因为它能避免系统在过渡阶段自欺欺人。

## 5. 失败与不支持的表示

### 5.1 不要用 `None` 混过去

如果一个 API 失败了，可能是：

- 这项能力当前后端不支持
- 输入超出了能力边界
- 当前实现暂时只能给近似值

这些不能全部压成 `None`。

### 5.2 MoonBit 风格失败模型

```mbt
enum UnsupportedReason {
  BidiNotSupported
  ShapingNotSupported
  FontMetricsUnavailable
  VerticalLayoutNotSupported
  ScriptNotSupported
  BlackBoxOnly
}

enum MeasureResult[T] {
  Ok(Measured[T])
  Unsupported(UnsupportedReason)
}
```

### 5.3 这层带来的好处

- 上层组件不需要靠字符串猜错误原因
- 测试可以针对边界行为写出清晰断言
- 文档和运行时能力表达一致

## 6. 核心数据模型

### 6.1 基础文本单位与范围

这份文档不拍板最终内部位置模型，但 API 层至少要显式有下面这些结构：

```mbt
type TextIndex = Int

type TextRange = {
  start: TextIndex,
  end_: TextIndex,
}

type TextPoint = {
  x: Double,
  y: Double,
}

type Rect = {
  x: Double,
  y: Double,
  width: Double,
  height: Double,
}
```

如果未来内部继续保留 `(row, col)` 语义，也应该建立在线性 index 之上，而不是把所有 API 都绑定成行列模型。

### 6.2 segmentation 结果

```mbt
type TextUnitMap = {
  text: String,
  line_starts: Array[Int],
  code_point_boundaries: Array[Int],
  grapheme_boundaries: Array[Int],
}

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
  units: TextUnitMap,
  graphemes: Array[Segment],
  words: Array[WordSegment],
  sentences: Array[Segment],
  break_candidates: Array[BreakCandidate],
}
```

### 6.3 shaping 结果

```mbt
type TextStyle = {
  font_families: Array[String],
  font_size: Double,
  font_weight: String?,
  font_style: String?,
  font_stretch: String?,
  letter_spacing: Double?,
  word_spacing: Double?,
  line_height: Double?,
  tab_size: Int?,
}

type TextRun = {
  start: Int,
  end_: Int,
  script: String?,
  lang: String?,
  dir: Direction,
  style: TextStyle,
}

type FontRun = {
  start: Int,
  end_: Int,
  font_key: String,
  fallback_chain: Array[String]?,
}

type ShapedGlyph = {
  glyph_id: String,
  cluster_start: Int,
  cluster_end: Int,
  advance_x: Double,
  advance_y: Double,
  offset_x: Double,
  offset_y: Double,
}

type ShapedRun = {
  start: Int,
  end_: Int,
  font_key: String,
  dir: Direction,
  script: String?,
  width: Double,
  glyphs: Array[ShapedGlyph],
}
```

### 6.4 paragraph layout 结果

```mbt
enum BreakMode {
  NoWrap
  GraphemeWrap
  WordWrap
  LineBreakWrap
}

type LineFragment = {
  run_index: Int,
  glyph_from: Int,
  glyph_to: Int,
  x: Double,
  width: Double,
}

type LineLayout = {
  line_index: Int,
  text_start: Int,
  text_end: Int,
  top: Double,
  bottom: Double,
  baseline: Double,
  width: Double,
  fragments: Array[LineFragment],
}

type ParagraphLayout = {
  text: String,
  width: Double,
  lines: Array[LineLayout],
  content_width: Double,
  content_height: Double,
  shaping_level: SupportLevel,
  line_break_level: SupportLevel,
  bidi_level: SupportLevel,
}
```

### 6.5 命中测试与几何查询结果

```mbt
type HitTestResult = {
  index: Int,
  line_index: Int,
  affinity: String,
}
```

## 7. 核心引擎接口

### 7.1 为什么要有一个统一引擎接口

MetaEditor 上层编辑器逻辑真正需要的不是“知道底层用了什么库”，而是拿到一组稳定的文本测量能力。

因此建议从一开始就定义一个统一的文本测量引擎接口，让不同阶段的实现都去满足它。

### 7.2 MoonBit 风格接口草案

```mbt
trait TextMeasureEngine {
  capabilities() -> TextEngineCapabilities

  segment_text(
    text: String,
    locale: String?
  ) -> SegmentationResult

  resolve_fonts(
    text: String,
    runs: Array[TextRun]
  ) -> Array[FontRun]

  shape_runs(
    text: String,
    runs: Array[TextRun],
    fonts: Array[FontRun]
  ) -> MeasureResult[Array[ShapedRun]]

  layout_paragraph(
    text: String,
    style: TextStyle,
    width: Double,
    locale: String?,
    dir: Direction,
    wrap: BreakMode
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

## 8. 为什么接口要比 `text-measuring.md` 里那版更细

`text-measuring.md` 里的最小 API 草案更像是“系统最终要提供哪些能力”。

而这里这版路线接口更细，是因为它要支持渐进迁移。

如果只有：

- `segment_graphemes`
- `break_lines`
- `layout_paragraph`

那么中间阶段很难做到：

- 只替换 segmentation
- 保留旧 shaping
- 或者只开始显式接管 font resolution

所以路线文档里的接口应该更偏工程分层，而不是更偏产品调用。

## 9. 三阶段后端路线

### 9.1 阶段 A：浏览器黑盒后端

这一阶段的目标是先把编辑器核心闭环跑起来。

后端特征：

- segmentation 主要依赖 `Intl.Segmenter`
- 宽度测量主要依赖 `measureText`
- 许多中间信息拿不到
- 几何结果很多是 `BlackBox`

示意：

```mbt
let caps: TextEngineCapabilities = {
  grapheme_segmentation: BlackBox,
  word_segmentation: BlackBox,
  sentence_segmentation: BlackBox,
  line_break: BlackBox,
  bidi: None,
  shaping: BlackBox,
  font_fallback_introspection: None,
  glyph_metrics: None,
  caret_metrics: Approximate,
  selection_geometry: Approximate,
  hit_testing: Approximate,
  writing_modes: [HorizontalTb],
  directions: [Ltr],
  scripts: Limited,
}
```

适用目标：

- `LTR + Latin/CJK`
- 基础换行
- 基础光标 / 选区 / hit-test

### 9.2 阶段 B：混合后端

这一阶段开始逐步显式接管中间产物。

后端特征：

- segmentation 不再完全依赖浏览器
- line break 开始显式化
- shaping 可能仍部分依赖黑盒或局部外部库
- paragraph layout 开始更受控

示意方向：

- segmentation: ICU / ICU4X / JS 明确实现
- line break: 显式规则或成熟库
- shaping: 逐步引入 `harfbuzzjs`
- font metrics: 引入 `fontkit` 或更强底层

### 9.3 阶段 C：更完整的逻辑层后端

这一阶段才接近真正的逻辑层真相。

后端特征：

- segmentation / bidi / shaping / line break 都是显式能力
- 浏览器退化成 oracle 与渲染宿主
- 中间产物尽量完整可查询

但这不是短期承诺，而是长期可能路线。

## 10. 上层应该如何使用这套接口

### 10.1 上层只消费布局对象与查询结果

上层编辑器逻辑应当尽量只依赖：

- `ParagraphLayout`
- `caret_rect`
- `selection_rects`
- `hit_test`

而不是自己再去拼：

- prefix width
- wrap line
- glyph cluster 映射

### 10.2 上层可以根据能力分支，但不能依赖具体后端

例如：

```mbt
let caps = engine.capabilities()
if caps.bidi == None {
  // 禁用严格 rtl 编辑能力
}
```

这是合理的。

但上层不能写成：

```mbt
if using_harfbuzzjs { ... }
if using_canvas { ... }
```

因为这会把迁移路线彻底锁死。

## 11. 当前建议的最小落地集合

如果只考虑 MetaEditor 近期最现实的一步，我建议先把下面这几个边界钉死：

### 11.1 一定要有

- `TextEngineCapabilities`
- `Measured[T]`
- `MeasureResult[T]`
- `ParagraphLayout`
- `TextMeasureEngine`

### 11.2 可以暂时简化

- `resolve_fonts` 的内部细节
- `ShapedRun` 的完整字段
- `WordSegment.kind` 的细粒度类型化
- `HitTestResult.affinity` 的完整模型

### 11.3 暂时不要过度展开

- vertical writing
- 完整 bidi
- 复杂 script coverage 分类
- 完整 font fallback introspection

## 12. 推荐结论

如果目标是“从外置文本测量平滑过渡到更完善的文本测量系统”，那么 API 设计上最关键的不是多写几个测量函数，而是先把下面三件事设计对：

1. **能力矩阵是一等 API**
2. **结果要显式带质量与来源**
3. **上层只依赖统一引擎接口，不依赖当前后端**

只要这三点成立，MetaEditor 就可以在很长一段时间里逐步演进：

- 先用浏览器黑盒把核心交互做起来
- 再逐步替换 segmentation / line break / shaping / metrics
- 同时始终清楚知道当前系统的边界在哪里

这比一开始就追求“完整文本平台”更现实，也比直接把一堆浏览器 API 暴露给组件层更稳。

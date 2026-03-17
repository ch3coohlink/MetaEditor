# CSS 布局相关属性
如果目标是“判断哪些会影响盒子位置、尺寸、换行、滚动、层叠和可见区域”，大致可以分这些类。

## 1. 盒模型与尺寸
- `box-sizing`
- `width height`
- `min-width min-height`
- `max-width max-height`
- `margin margin-*`
- `padding padding-*`
- `border border-* border-width`
- `aspect-ratio`

## 2. 文档流与显示类型
- `display`
- `visibility`
- `opacity`
- `float`
- `clear`
- `overflow overflow-x overflow-y`
- `overflow-anchor`
- `overflow-wrap`
- `white-space`
- `word-break`
- `line-break`

## 3. 定位与层叠
- `position`
- `top right bottom left`
- `inset inset-*`
- `z-index`

## 4. Flex 布局
- `display: flex | inline-flex`
- `flex-direction`
- `flex-wrap`
- `flex-flow`
- `justify-content`
- `align-items`
- `align-self`
- `align-content`
- `gap row-gap column-gap`
- `flex-grow`
- `flex-shrink`
- `flex-basis`
- `flex`
- `order`

## 5. Grid 布局
- `display: grid | inline-grid`
- `grid-template-columns`
- `grid-template-rows`
- `grid-template-areas`
- `grid-auto-columns`
- `grid-auto-rows`
- `grid-auto-flow`
- `grid-column grid-column-start grid-column-end`
- `grid-row grid-row-start grid-row-end`
- `grid-area`
- `justify-items`
- `justify-self`
- `place-items`
- `place-self`
- `place-content`
- `gap row-gap column-gap`

## 6. 文本排版与 inline 布局
这些不只是“样式”，很多会直接影响测量和换行。
- `font-family`
- `font-size`
- `font-weight`
- `font-style`
- `font-stretch`
- `line-height`
- `letter-spacing`
- `word-spacing`
- `text-indent`
- `text-transform`
- `tab-size`
- `direction`
- `writing-mode`
- `text-orientation`
- `vertical-align`

## 7. 滚动与视口相关
- `overflow*`
- `scrollbar-gutter`
- `scroll-behavior`
- `scroll-snap-type`
- `scroll-snap-align`
- `scroll-padding*`
- `scroll-margin*`

## 8. 变换与几何后处理
这些不一定参与正常布局求解，但会改变最终几何和命中。
- `transform`
- `transform-origin`
- `scale rotate translate`
- `filter`
- `zoom`（非标准但现实里有）
- `clip-path`

## 9. 包含、隔离、容器查询
这些会强烈影响布局边界和依赖关系。
- `contain`
- `content-visibility`
- `contain-intrinsic-size`
- `container-type`
- `container-name`

## 10. 多列与特殊布局
- `columns`
- `column-count`
- `column-width`
- `column-gap`
- `column-rule`
- `break-before break-after break-inside`
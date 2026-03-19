# Doc Tools

这个目录现在专门用于把仓库里的 Markdown 文稿组装成可由 Vivliostyle 渲染的书稿，并输出可审阅的 HTML 与 PDF。

当前默认目标文稿是：

- [css-roadmap.md](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/legacy/css-roadmap.md)

## 目录结构

```text
doc/
  tools/
    out/
      css-roadmap/
        index.html
        css-roadmap.pdf
        assets/
    build-book.mjs
    book-template.html
    book.css
    run-vivliostyle.mjs
    vivliostyle.config.mjs
    README.md
```

说明：

- `build-book.mjs`
  - 负责把 Markdown 解析并渲染成完整 HTML 书稿（包含目录、标题数据和 Mermaid 支持）
- `book-template.html`
  - 统一书稿模板
- `book.css`
  - A4 技术审阅版主题
- `run-vivliostyle.mjs`
  - 负责在当前环境里稳定调用 Vivliostyle CLI
  - 会优先寻找本机可用的 Edge / Chrome
  - 会清理当前环境中无效的 `socks://` 代理变量
- `vivliostyle.config.mjs`
  - 默认 PDF 构建配置
- `out/`
  - 所有中间产物与成品输出目录
  - 已被 `.gitignore` 忽略，不进入版本控制

## 依赖说明

当前工具链依赖：

- `markdown-it`
  - 负责 Markdown 解析
- `@vivliostyle/cli`
  - 负责预览和 PDF 构建

Mermaid 当前仍然使用浏览器运行时初始化，不做预渲染。

## 核心命令

在仓库根目录运行。

生成默认文稿 HTML 书稿：

```bash
npm run doc:book:html -- doc/legacy/css-roadmap.md
```

生成默认文稿 PDF：

```bash
npm run doc:book:pdf
```

完整生成默认文稿的 HTML + PDF：

```bash
npm run doc:book
```

启动 Vivliostyle 预览：

```bash
npm run doc:book:preview
```

也可以手动覆盖标题或 slug。带高级参数时，直接调用 Node 入口更稳定：

```bash
node doc/tools/build-book.mjs doc/legacy/css-roadmap.md --slug css-roadmap --title "MetaEditor CSS 引擎路线图"
```

## 默认构建对象

默认书稿对象固定为：

- [css-roadmap.md](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/legacy/css-roadmap.md)

默认输出位置固定为：

- HTML：
  - [index.html](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/tools/out/css-roadmap/index.html)
- PDF：
  - [css-roadmap.pdf](/d:/Users/ch3co/Desktop/mbt_race/MetaEditor/doc/tools/out/css-roadmap/css-roadmap.pdf)

## 输出说明

HTML 是中间书稿，不是最终出版物。它的作用是：

- 检查目录和标题层级
- 检查 Mermaid 是否渲染
- 检查代码块、表格和图片是否溢出
- 作为 Vivliostyle 的输入页面

PDF 是当前默认审阅成品。第一版规格固定为：

- A4
- 技术审阅版
- 单栏
- 带目录
- 带基础页眉页脚和页码

## Vivliostyle 审阅流程

建议按下面顺序审阅：

1. 先运行 `npm run doc:book:html -- doc/legacy/css-roadmap.md`
2. 打开生成的 `index.html`，检查：
   - 目录
   - 标题层级
   - Mermaid
   - 长代码块和表格
3. 再运行 `npm run doc:book:pdf`
4. 打开生成的 PDF，检查：
   - 封面头部
   - 目录分页
   - 章节分页
   - Mermaid 图分页
   - 长代码块和长表格
   - 页边距与字号

这样可以先在 HTML 层定位结构问题，再在 PDF 层定位分页问题。

## 已知限制

- Mermaid 当前仍依赖运行时脚本初始化
  - HTML 中可正常使用
  - PDF 路线当前可用，但如果后续出现不稳定，第二轮应考虑改为预渲染 SVG
- 第一版未打包自定义字体
  - 字体外观会受本机环境影响
- 第一版主题定位是“技术审阅版”
  - 还不是最终印厂交付版
- 复杂长表格目前只保证可读性和换行
  - 不做高级表格重排
- 极长代码块仍可能发生跨页
  - 当前优先保证不出现严重截断

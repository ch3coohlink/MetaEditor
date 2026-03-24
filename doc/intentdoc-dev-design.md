# IntentDoc/dev 设计索引

这份文档按当前 `../IntentDoc/dev` 目录快照整理，目标是把每个文件在系统里的职责、核心机制和边界写清楚。
方便将其能力迁移到 MetaEditor 项目

## 基础底座

- `basic.js`：基础工具层，集中放 UUID、哈希、CBOR、二进制/十六进制互转、深比较、
  消息编码和常用纯函数；上层模块尽量只依赖这一层，不自己重复造编码工具。
- `bit-pattern.js`：位模式相似度和训练小引擎，用随机模式、相似度评分和权重生成做
  一个最小的“匹配-学习-生成”闭环。
- `console.js`：当前为空占位，没有承载系统设计，只保留文件位置。
- `css.js`：tailwind 兼容的原子类 CSS 规则和样式 DSL 的生成器，把 class 组合、主题变量、选择器/规则定义
  收敛成可复用的样式底座，供 `ui.js` / `ui-kit.js` 使用。
- `drawing.js`：画布路径绘制辅助，只关心点序列到 canvas path 的渲染、清屏和坐标换算。
- `egwalk.js`：RLE 压缩的操作日志 DAG 与 Eg-walker 原型，核心是把连续操作打包成 DAG
  节点，再从前沿和 LCA 推导 diff。
- `firay.js`：可协作数组原型，核心语义是给每个元素维护稳定 rank，支持 `push`、
  `splice`、`move`、`sort`、`reverse`、`slice`、`map` 等操作，同时保留迭代/重放的
  确定性。
- `manage-sw.js`：service worker 启动管理器，负责 hash 校验、注册、READY 握手和
  controller 切换重试。
- `parser.js`：解析器生成器 DSL，提供 grammar 构造子、first set/依赖分析、左递归检查、
  memoization 编译和 tolerant 错误恢复。
- `reactive.js`：响应式底座，基于 Proxy、effect、scope、watch、capture、recoverable、
  cache 组织依赖追踪和生命周期；数组、对象和嵌套状态都走同一套追踪语义。
- `sandbox.js`：代码执行沙箱，把定时器、事件、DOM、fetch、Worker、WebSocket、
  indexedDB 等宿主 API 包进生命周期清理里，避免运行代码泄漏环境状态。
- `state.js`：旧版历史状态管理，使用快照栈和操作序列做 undo/redo/jump，更偏“记录与
  回放”的基础模型。
- `state-new.js`：新版状态管理，沿用 `history` 但更强调对象克隆、回放和局部撤销/重做，
  让状态树和操作日志保持可重建。
- `storage.js`：响应式状态持久化层，负责把 reactive 对象递归脱水/回水到 KV 存储，也
  提供 clone/patch 这类序列化友好的状态搬运能力。
- `sw.js`：service worker 本体，负责拦截文件系统 RPC、回传 READY、加载基础模块并把
  service worker 和后端文件系统接起来。
- `ui-kit.js`：统一 UI 组件库，主要放主题 token、Button/Input/Field/Toolbar/Group/Divider
  这类低级可组合控件，不处理业务逻辑。
- `ui.js`：UI 运行时核心，负责 `h`、`comp`、`h.map`、`cache`、事件绑定、命名空间、
  DOM 指令化与节点清理，是整个前端视图层的主入口。
- `virtual-list.js`：虚拟列表组件，按滚动位置切片数据，只渲染可见窗口和 overscan，
  重点是把完整数据集和可见子集分离。
- `webrtc.js`：WebRTC 连接封装，集中处理 peer connection、offer/answer、ICE candidate、
  data channel 和媒体流接入。

## 数据与状态

- `kv.js`：IndexedDB 包装层，提供表、索引、事务和批量访问的统一入口，供文件系统、
  存储和图数据库复用。
- `gdb.js`：图数据库核心，围绕 graph/node/edge/data 四类实体做写缓存、脏标记、hydrate/
  dehydrate、查询和写入；它的重点是把图结构与对象数据分层保存。
- `gfs.js`：图式文件/仓库存储层，更偏“图对象 + 节点/边 + 数据块”的仓库语义，核心是
  按 hash 和关系维护图状态，并支持增量查询与写入。
- `fs.js`：基于 IndexedDB 的文件系统实现，负责路径解析、目录/文件 CRUD、watch、事务
  写入和元数据维护；它的设计目标是把文件系统做成可在浏览器中长期运行的状态服务。
- `fs-ui.js`：文件系统树 UI，按目录节点递归渲染、懒加载子项、复用节点状态，并把 rename /
  add / delete / open 这些动作绑定到树项上。
- `storage.js`：把 UI/应用状态持久化到 KV 的桥梁，依赖 reactive 的可观测性来决定何时
  需要把状态写回存储。

## 应用与宿主

- `audio.js`：音频/乐谱 demo，把文字 DSL 解析成多轨音符并通过 Web Audio 生成声音，同时
  提供一个钢琴键盘 UI 用来实时触发音符。
- `bit-pattern.js`：位模式学习器 demo，展示如何通过模式匹配和训练权重生成二进制输出。
- `drawing.js`：画布绘制基础模块，负责将路径点序列转成实际绘制结果，是绘图故事和
  画板类 demo 的底层工具。
- `index.html`：宿主入口页面，负责加载模块、挂载 Shadow DOM、初始化 `Workspace`，并把
  页面作为整个 IntentDoc 的浏览器壳子。
- `story-editor.js`：故事编辑器主入口，把代码编辑、故事编译、故事选择、预设快照和运行
  预览放在同一界面里，是“写故事 + 跑故事 + 看状态”的整合层。
- `text-editor.js`：文本编辑器主实现，围绕 `st.lines`、`history`、光标、选区、IME、复制/
  粘贴、undo/redo 和行级缓存组织，属于典型的高频原地修改场景。
- `workspace.js`：多编辑器工作台，负责文件打开、编辑器类型解析、tab 管理、保存、侧边栏
  和主编辑区组合，是整个 IntentDoc 的桌面式壳层。
- `ui-kit.js`：为工作台和故事编辑器提供统一视觉组件，不直接承载业务状态。
- `virtual-list.js`：典型的窗口化渲染样板，说明列表数据和列表视图分层。

## 运行与桥接

- `sandbox.js`：运行时隔离层，设计目标是让用户代码在“可执行但可回收”的容器里跑，
  所有会产生生命周期的宿主对象都挂清理钩子。
- `manage-sw.js`：负责让浏览器中的 service worker 版本、控制权和页面状态对齐，避免
  本地缓存和 SW 版本不同步。
- `sw.js`：真正的 RPC 入口，负责把浏览器端文件系统请求路由到服务 worker 内的文件系统
  实例。
- `webrtc.js`：点对点通信封装，核心是信令流和 data channel 的建立/恢复，而不是把业务
  逻辑放进 WebRTC。

## 业务实验与扩展

- `console.js`：占位文件，当前没有形成独立设计。
- `egwalk.js`：体现操作日志/CRDT-ish 方向的实验，重点是用 DAG 和 frontier 计算差异。
- `firay.js`：协作数组实验，重点是元素身份、rank 稳定性、原地变更和回放一致性。
- `gdb.js` / `gfs.js`：两条图式数据路径，一个偏数据库引擎，一个偏仓库/文件系统语义。
- `bit-pattern.js` / `audio.js` / `drawing.js`：分别对应模式学习、声音生成和画板渲染，
  都是把单一领域能力收成可复用小模块。

## story 目录

- `story/css.story.js`：CSS 组件和样式系统的示例故事，重点是验证样式 token、布局和交互
  组合。
- `story/draw.story.js`：画板交互故事，强调路径绘制、历史记录和实时刷新。
- `story/fs.story.js`：文件系统浏览与监听故事，展示目录展开、文件变化和树状 UI 的联动。
- `story/grammar.story.js`：语法/解析器相关故事，主要用来检验 grammar DSL 的可读性和
  交互编排。
- `story/music.story.js`：音乐编辑/演奏故事，把音高、和弦、绑定和播放组合起来。
- `story/test-collab.story.js`：协作/回放故事，验证多用户动作日志、同步和恢复语义。
- `story/text.story.js`：文本编辑器故事，覆盖行级编辑、光标移动和输入法处理。
- `story/vcs.story.js`：版本控制/历史可视化故事，偏向展示 snapshot、commit 和分支语义。
- `story/video.story.js`：视频或媒体实验故事，偏向实时媒体控制和宿主交互。

## test 目录

- `test/basic.test.js`：基础工具测试，覆盖编码、UUID、hash、深比较和各种纯函数。
- `test/bit-pattern.html`：位模式 demo 的浏览器测试页，用于手工或半自动验证可视结果。
- `test/css.test.js`：CSS 规则、选择器和样式生成测试，关注 DSL 到实际规则的映射。
- `test/e2e/assertions.js`：端到端断言工具，集中封装页面状态和 DOM 断言。
- `test/e2e/editor-driver.js`：端到端驱动，负责把编辑器页面和测试动作连起来。
- `test/e2e/music-editor.html`：音乐编辑器 E2E 页面入口。
- `test/e2e/music-editor.spec.js`：音乐编辑器端到端规格测试。
- `test/e2e/README.md`：E2E 测试入口说明。
- `test/e2e/server.js`：E2E 测试服务端/静态页托管入口。
- `test/firay.test.js`：协作数组 `firay` 的行为、确定性和回放测试。
- `test/fs.test.js`：文件系统 CRUD、watch、路径解析和目录语义测试。
- `test/fs-test-worker.js`：文件系统测试的 worker 辅助，用于隔离异步或独立执行路径。
- `test/gdb.test.js`：图数据库读写、哈希、边/点关系和缓存测试。
- `test/gfs.test.js`：图式文件系统或仓库语义测试，覆盖图对象的增删改查。
- `test/index.html`：浏览器测试入口页，承载脚本加载和测试 UI。
- `test/index.js`：测试总入口脚本，用来组织浏览器端测试运行。
- `test/js-perf.test.js`：JavaScript 性能测试，关注局部算法和数据结构开销。
- `test/kv.test.js`：IndexedDB/KV 封装测试，验证表、索引和事务行为。
- `test/parser/test-migration.js`：解析器迁移样本，用来对比不同版本语法或 AST 结果。
- `test/parser/temp-regex-test.js`：临时正则实验文件，主要是调试性质。
- `test/parser/sample_json.js`：解析器样例输入，作为 JSON 语法/语义测试素材。
- `test/parser/parser.test.js`：解析器主测试，验证语法规则、 AST 结构和基础正确性。
- `test/parser/parser-rule-compiled-exp.js`：编译表达式/规则实验，用来验证生成代码的行为。
- `test/parser/parser-perf.test.js`：解析器性能测试，专门看生成器和运行时开销。
- `test/parser/parser-old.js`：旧版解析器实现样本，保留作对照。
- `test/parser/parser-old-2.js`：旧版解析器第二版本，保留作迁移和对比。
- `test/parser/parser-old-3.js`：旧版解析器第三版本，保留作迁移和对比。
- `test/parser/parser-old-4.js`：旧版解析器第四版本，保留作迁移和对比。
- `test/parser/parser-new.js`：新版解析器实现样本，当前对照对象。
- `test/parser/parser-json-shared.js`：解析器与 JSON 共享规则或共享片段。
- `test/parser/parser-handbuilt-peg.js`：手写 PEG 风格解析器实验。
- `test/parser/parser-front-compiled-exp.test.js`：前端编译表达式测试。
- `test/parser/parser-fast-but-huge-codegen.js`：大体积但高性能的代码生成实验。
- `test/parser/handbuilt-json-parser.js`：手写 JSON 解析器实现样本。
- `test/parser/gen-parser-temp.js`：解析器生成器临时产物，主要用于实验和调试。
- `test/reactive.test.js`：响应式系统测试，覆盖 effect、watch、scope、capture、recoverable
  以及数组/对象的依赖追踪语义。
- `test/storage.test.js`：持久化层测试，验证 reactive 状态脱水、回水和 patch 语义。
- `test/ui.test.js`：UI 运行时测试，覆盖 `h`、`comp`、`h.map`、命令生成、namespace、
  callback 和 DOM 指令语义。
- `test/webrtc.test.js`：WebRTC 封装测试，验证信令、data channel 和媒体接入路径。

## 当前整体判断

- `reactive.js`、`ui.js`、`storage.js`、`state*.js` 和 `firay.js` 构成了最核心的状态/视图
 / 回放主线。
- `workspace.js`、`story-editor.js`、`text-editor.js`、`fs-ui.js` 和 `virtual-list.js`
  则是 IntentDoc 上层交互的主要落点。
- `parser.js`、`sandbox.js`、`sw.js`、`manage-sw.js` 和 `webrtc.js` 更像运行时/宿主能力
  的基础设施。
- `gdb.js`、`gfs.js`、`egwalk.js`、`firay.js`、`bit-pattern.js`、`audio.js`、
  `drawing.js` 是若干条独立实验线，各自都在验证一类可复用的核心语义。

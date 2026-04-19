# 开发日志

## 03-21 之前

03-21 之前，项目的第一层基础已经搭起来了。前端和应用侧的主体代码已经落在 `src/`、`app/` 和 `test/` 里，说明浏览器 UI、桥接逻辑和最初的交互验证已经不再只是想法，而是进入了可运行、可迭代的状态。命令行这一层当时仍然是旧的 `cli/` 路线，里面已经有一套基于 Node 的本地服务壳和命令入口，可以负责拉起页面，并给后续的 query、exec 和调试动作留出调用位置。与此同时，仓库里还单独保留着 `native_ws/` 这条原型线，用 MoonBit native 做了最早的一版 websocket 服务和测试，用来验证浏览器和 native 程序之间的通信链路。构建基础设施也已经提前铺好，Windows 和 Unix 两边都各自有 `build-native` 脚本，虽然当时主要服务的还是 `native_ws` 这一版原型，但跨平台 native 构建这件事已经被正式纳入工程。除了代码本身，文档工具链也已经有了自己的位置，`doc/tools/` 里放着一套把 Markdown 组装成排版过的 HTML 和 PDF 书稿的小工具，说明项目在代码之外，连设计文稿和技术文档的生成方式也开始被认真整理。更重要的是，`doc/meta-editor-service.md` 在那时就已经把 MetaEditor 作为长期运行服务的整体方向写了出来，里面已经讨论了项目编译、运行、页面连接、结构化 query/exec 和自动化测试等职责如何往统一服务模型里收敛。也就是说，在 03-21 之前，项目已经同时具备了浏览器端代码、旧 CLI、native websocket 原型、跨平台 native 构建脚本、文档排版工具和 service 方向文档这几层基础，后面的工作主要是在这些现成基础上继续合并结构、收敛路径，并把行为和测试逐步做实。

## 03-21

03-21 这一天，项目的重点是把原来的 Node CLI 和 `native_ws` 过渡结构收敛成一条统一的 native service 路线。旧的 `cli/` 和 `native_ws/` 被移出主路径，新的 `service/` 包接过了主入口，`meta.ps1` 也被收成一个很薄的外壳，只负责确保 native 二进制存在并把参数转发给 `service.exe`。这一轮之后，`main.mbt`、`cli.mbt`、`runtime.mbt` 和 `base.mbt` 的职责边界基本成形，MetaEditor 作为长期运行服务的主结构第一次真正稳定下来。

这一天花力气最多的是 `start/stop` 这条生命周期链。`meta start` 被改成前台命令快速返回、后台服务继续运行，`meta stop` 则改成按 PID 停进程并清理状态文件，不再绕回服务内部做控制关闭。与这条链一起收掉的还有 CLI 的失败返回码和离线 `help`，这样脚本、CI 和第一次使用命令的人都能得到比较可信的行为。

浏览器连接和协议也在这一天定下了几条关键契约。服务端的 `hello` 握手和会话排他规则被固定下来，浏览器重连时的 DOM 污染问题也被一起处理：服务端先发 `hello_ack`，再发 UI history，浏览器端在收到新的 `hello_ack` 后先重置 bridge 维护的 DOM 和节点表，避免旧页面状态残留到新连接里。对应的协议顺序测试也补进了 `server_test.mbt`，把这件事锁成了正式约束。

Windows native 构建链也是在这一天开始真正收稳的。`build-native.ps1` 逐步摆脱了原先脆弱的 `cmd`、代码页和截断日志路径，编译失败时终于能看到完整输出；同时 native tests 也开始围绕新的 `service.exe start/status/stop` 组织起来，覆盖 `start`、`stop`、`status`、静默启动和协议顺序这些核心行为。到这一天结束时，工程已经从“几个原型并行存在”的状态，进入了“以 service 为中心继续往下收行为和测试”的状态。

## 03-22 上午

03-22 上午，主要是在前一天收出来的 service 路线上继续补细节，并开始追 Windows 下 native 测试和启动链的性能问题。CLI 增加了 `meta start --silent`，让测试和脚本在启动服务时不会自动弹浏览器页面；与此同时，`server_test.mbt` 也继续调整，尽量把需要真实进程生命周期验证的部分留在黑盒测试里，把不必起进程的判断压回纯逻辑测试，测试结构因此比前一天更清晰了一些。

这一上午另一个重点是把 `test-native.ps1` 和 `build-native.ps1` 再往稳和快的方向收。脚本开始更明确地区分构建、测试和清理阶段，也逐步发现拖慢流程的往往不是 `moon build` 本身，而是残留的 `moon.exe` 进程和 `_build/.moon-lock`。针对这些问题，脚本里补了定点清理和超时后的整棵进程树终止，`test-native.ps1` 也改成直接跑 `moon test`，不再重复先做一次无意义的单独构建。

性能排查也是这一上午的新内容。为了看清测试慢在哪，生命周期测试里临时加过阶段计时，结果显示真正的成本集中在第一次 `start --silent` 和运行中的 `stop`，尤其是带残留 `pid/state` 的恢复路径会明显变慢。围绕这个问题，后来又查了一轮 Moon 自带的 tracing 和 benchmark 能力，并尝试用 `samply` 去录 native `start --silent` 的 profile。最开始的障碍是当前 `--target native` 这条 Windows debug 构建不会直接给出好用的符号，所以 profile 里大多还是地址，这一度让人以为如果要把 profiling 做透，可能得进一步研究 LLVM backend，或者干脆接手 Moon 生成 C 代码之后的最后一段本地编译和链接。后面继续查下去，才确认 `moon.pkg` 里的 native 编译参数其实可以往下传给 MSVC，于是临时加了 `/Z7`，再配合 `samply` 重新录，Windows 下的符号链路终于被打通，profile 至少已经能落到 service 自己的函数上，不再只是纯地址。

在把 profiling 这条路打通之后，后面的重点就重新回到了慢启动本身。service 的存活判定从原来的 `pid/state + 旧端口探测` 改成了独立运行锁优先，`start/status/stop` 都先看锁，再决定是等待现有服务、清理 stale 文件还是真正启动新实例。这样之后，带假 `pid/state` 的 `start --silent` 也回到了百毫秒量级，不再被旧 HTTP 连接拖慢。native 测试这边则重新改回固定的两阶段，先 `moon build`，再单独 `moon test`，让构建超时和测试超时分开控制。最后又顺手把 `stop` 的成功条件收紧成“进程终止后运行锁也确实释放”，避免留下锁还占着但状态文件已经被删掉的坏中间态。到这里，这一轮基本就是以运行锁、stale 恢复、profiling 链路打通和黑盒生命周期测试一起收口，常规构建配置里的 profiling 参数也一并拿掉了。

## 03-22 下午

03-22 下午，工作重心开始转到 host app 原型本身。service 里先长出了一层最小的 managed app 结构，把 host 和当前的 counter demo 都挂进运行时，再让 host 成为默认显示的外壳。这个过程中很快暴露出一个很实际的问题：把原来的 counter app 拆成可复用组件之后，新的 host 挂载路径没有把初始 UI 正常 flush 出去，结果服务虽然已经起来，但浏览器里看不到任何首帧内容。这个问题后来直接在 runtime 里补上了显式 flush，并加了一条很小的测试，把 `MetaEditor Host` 是否真的进入初始 UI history 锁住。

后面的调整主要围绕 host 界面的角色收敛。host 先被固定成一直存在的外壳，右侧只保留一个工作区，当前打开的 app 就显示在那里，这样切到 counter 时不会再把整张 host 页面一起清掉。同时，host 虽然仍然保留在运行时的 app 注册表里，但在界面的 `Managed Apps` 列表里已经被隐藏掉，不再出现“host 管理自己”的怪异效果。原先顺手加上的 preview 区后来证明并不符合实际想要的交互，所以这一块也从 host UI 里拿掉了，界面重新收回到更直接的“host 外壳 + app 列表 + 单一工作区”这条线上。这一下午的结果不是把 host 模型彻底做完，而是先把最别扭的几处行为收回到能继续往下迭代的状态。

这一下午后面剩下的时间，基本都耗在 host app 的 `Stop Service` 上。最开始看起来只是要把 UI stop 和 CLI stop 收成同源，但真正踩进去之后，很快就暴露出两类坏中间态：一种是服务已经不再响应，但运行锁、pid 和 state 文件还留着，`status` 会卡到 `service is not ready`；另一种是服务看起来停了，但 UI stop 后立刻再 `start` 仍然会撞到 stale 状态，导致浏览器页也进不去。最后收口的做法反而比中途绕出来的几个版本更硬一些：UI 的 `host_stop_service` 和 CLI 的 `stop` 都先走同一层 stop 请求，再在服务进程里落到同一个真正的停机函数，不再依赖那条已经被证明不稳定的 `server.close()` 关闭路径，而是直接结束当前服务进程。这样之后，`host_stop_service -> status -> start` 这条链才重新回到稳定状态，UI 停机后马上再起服务也不会再留下锁还占着、服务却已经半死不活的坏状态。

与这条 stop 链一起补上的，还有 native 测试脚本的阶段拆分。`test-native.ps1` 继续保持现有两段式，但在正式执行 `moon test` 前先跑一次 `moon test --build-only`，把“编译 test 产物”和“真正执行测试”拆成两个独立阶段。这样之后，脚本里的超时和 timing 终于能清楚看出慢的是 test 预热还是 test 本体，不会再把“刚改完代码后的首次 test 重建”误看成测试逻辑本身退化。黑盒生命周期测试这边则只额外加进了最小的一段 `host_stop_service -> restart after host stop` 验证，用来锁住这次真实踩出来的 host stop 回归，同时尽量不把原本已经压到亚秒级的 native test 再拖慢太多。到这里，这一轮才算把 host stop、CLI stop 和 native lifecycle test 重新收回同一条可信的路径上。

这一下午最后还顺手查了一轮 Codex 自己的可组合性边界。原先的直觉是，Codex 现在虽然有 terminal 入口，但很多能力更像交互式 TUI，而不太像能稳定接进脚本和工具链的传统 CLI，所以后面又专门去确认了 SDK 和 GitHub code review 这一层到底是什么关系。查下来之后，能确定的点比一开始清楚不少：OpenAI 当前已经公开提供 Codex SDK，而且官方明确说它复用了驱动 Codex CLI 的同一个 agent；但另一方面，GitHub 上那套 `Code Review` 又不是简单等价于“同一个 agent 换个 prompt 再跑一次”，而是单独的产品能力面，带着自己的仓库集成、触发方式和计量口径。于是这一轮最后就把相关结论单独记进了 `doc/codex-sdk.md`，把 Codex CLI、Codex SDK 和 GitHub Code Review 这三层分别讲清楚，也顺手把一条新的协作规则补进了 `AGENTS.md`：以后只要用户要求补日志、记一下、提交前同步记录，agent 默认就该去更新 `doc/devlog.md`，并且按当前环境本地日期和上午/下午自动归档，不再每次都等用户手动指定日期小节。

## 03-22 晚上

03-22 晚上，service 这一层继续往“运行时代码只做运行时，测试逻辑回到测试包”这个边界上收。`runtime.mbt` 里的 app test runner 和那批 snapshot/assert 辅助已经全部移除，当前 runtime 只保留 host UI、bridge、browser request/response 和文件服务相关逻辑，不再承担任何测试宿主职责。对应地，app 侧的验证也不再塞在 service 包里，而是落到 `app/test/` 下的独立测试包，当前只有 `host` 和 `counter` 两组，分别覆盖 host shell 初始 UI history 和 counter app 的 action/undo/redo 交互。

这轮一开始的 `meta test` 调度做法还是偏重，按 app id 映射到单独测试文件，再起多个子进程去跑，结果虽然功能能通，但 `meta test` 无参数时会撞到 Moon 的 `_build/.moon-lock`，而且 app 测试整包跑时又暴露出另一个更真实的问题：`host` 这组通过 `init_bridge` 留下的全局 post-flush sender 会影响后面同包运行的 `counter` 组，导致单测单独跑通过，整包跑反而读不到更新后的命令流。最后收口的结构更简单也更稳：app 测试统一放到 `app/test` 包下，`meta test` 无参数时直接执行整个 `app/test` 包，让 Moon 自己调度；`meta test host` 和 `meta test counter` 则通过 `--filter` 只跑名字里对应 app id 的测试组，不再靠 CLI 自己维护文件路由表。

为了解掉整包跑时的共享状态污染，这一轮顺手给 `src` 侧补了很小的测试重置入口，把 UI 命令队列、callback 表、节点 id 计数和 reactive 的 post-flush 池都能在测试开始前清干净。这样之后，`host` 和 `counter` 两组 app test 既可以单独跑，也可以整包一起跑，而且不会再因为上一组测试残留的 bridge 状态把下一组的断言吃掉。Windows 下的 `meta test` 入口也继续沿用现有 native 环境导入脚本，只是 `build-native.ps1` 额外支持了 `-TestFilter`，这样 app test 在 PowerShell 下也能直接转成对应的 `moon test --filter` 调用，不需要再造一套新的测试启动链。

这一晚还顺手把反复出现的行尾问题查清楚了。当前仓库没有 `.gitattributes`，而本机 Git 全局配置原来是 `core.autocrlf=true`，所以索引里的 `.pkg` 文件是 `LF`，工作区却会自动检出成 `CRLF`，文件一旦被碰到就很容易出现“正文没变但行尾脏了”的状态。这一轮最后已经把 Git 全局行尾策略改成 `core.autocrlf=input`，当前行为变成只在提交时把 `CRLF` 收回 `LF`，工作区不再默认自动转成 `CRLF`，后面这类无意义的行尾脏状态应该会明显减少。到这里，这一轮的当前状态已经比较清楚：`meta test` 负责 app 级测试调度，app 测试独立放在 `app/test`，service native lifecycle 继续由 `test-native.ps1` 和 `service/server_test.mbt` 负责，两条测试链已经彻底分开。

这一晚后半段，方向又进一步从“把边界整理对”收成了“直接把 service 砍到最小骨架”。最先被整层拿掉的是 `query`、`exec`、`history`、多 app 壳子和 `counter` app，host 页面也被压回只剩标题、简短状态文字和一个 `Stop Service` 按钮。围绕这些能力存在的 browser request/response、UI 快照协议、`HostInfo`、`QueryCmd`、`ExecCmd` 和那批专门为了 app test 调度存在的 CLI 逻辑也一起删掉了，service 不再假装自己还是一个通用浏览器操控宿主，而是明确只剩启动、停止、最小状态查看和 host 页面本体。生命周期测试也同步收紧，只保留 `idle stop -> start -> repeat start -> host stop -> restart -> stop` 这条最小黑盒链，并把测试文件改名成 `serve.test.mbt`，让统计和测试命名规则统一成同一套 `.test` 口径。

真正把行数压下来的关键，不是再去补什么协议兼容，而是承认一大批文件边界本身已经没有独立价值。`service/protocol.mbt` 最后只剩几条 HTTP JSON 响应和 event 分发辅助，于是直接并回 `base.mbt`；`service/runtime.mbt` 剩下的也只是最小 host UI、websocket 握手和静态文件服务，于是也一起并进了 `base.mbt`；`service/main.mbt` 则完全只是参数转发壳，直接并进 `cli.mbt`。这样之后，service 的生产文件最终只剩 `base.mbt`、`cli.mbt`、`moon.pkg` 和 `stub.c` 四个，CLI 里也不再保留 `meta test` 这条功能，连同只为它存在的 `app/` 包和 `app/test/` 包一起删空。当前统计已经稳定在 `service prod = 900`、`service test = 210`，也就是说最初看起来还在一千多行的 service，本体真正剥离测试和空壳之后，终于压回了九百行量级。native lifecycle 回归这时重新跑过一轮，`test-native.ps1` 仍然是 `11 passed`，说明这次大砍之后，最小骨架虽然功能少了很多，但至少启动、停止、host stop 和重启这条核心链还在正常工作。

今晚最后收尾做的不是继续删功能，而是把剩下这点骨架至少整理到能看。`cli.mbt` 里的命名继续往最短压了一轮，`run_cli_command`、`handle_control_request`、`call_service_at_port`、`wait_for_service_port`、`detect_service_port` 和 `require_service_port` 分别收成了 `run`、`handle`、`call_at`、`wait_port`、`detect_port` 和 `require_port`，同时把注释改成了更明显的分块线，至少能一眼区分入口、存活探测、生命周期、HTTP client 和 HTTP server。`base.mbt` 这边则彻底按块重排，常量、类型、session/runtime、锁文件、JSON/HTTP 辅助、host UI 和 browser bridge 分成了几段，虽然函数本身还是偏长，但总算不再是所有东西混着堆在一起。最后又跑了一次 native lifecycle 回归，结果仍然是 `11 passed`，这也算给今天这轮大砍和整理收了个能接受的尾。

## 03-23 上午

03-23 上午，service 继续往更小的骨架收。`Runtime` 里原先那批明显多出来的状态已经继续删掉，`ui_history`、`app_actions` 和旧的 stop 回调链都不再保留，停机路径统一收在 `shutting_down` 上，不再同时维护两套布尔标志。`base.mbt` 也从一开始那种把 host app、bridge、HTTP 辅助和 session/fs 状态混在一起的总文件，继续拆成了更清楚的 `session`、`fs`、`app`、`bridge` 和 `http` 几块，service 的边界开始更接近“底座只放底座，页面和连接各走各的”。

这段整理里顺手也把一个容易误解的状态说清楚了：`@src.get_cmds()` 还保留在浏览器端测试层，它是 UI/bridge 自己的命令流缓存，不是 service 运行时额外复制出来的一份状态，所以当前只把它记成 `src` 侧的测试边界，不并进 service 的骨架里。真正需要警惕的是 service 自己是否还在维护重复状态，像 `ui_history`、`app_actions` 这类已经被确认是冗余的字段就直接删掉，不再为它们保留兼容层。

同时也把重连同步的边界定死了：局部更新继续走增量指令，全量恢复只在重连或首次接入时复用同一套渲染入口重新生成初始批次，不单独再造一层快照协议，也不再把“重连”设计成“回放历史命令”。这样 service 里只保留一条 UI 生成入口和一条发送路径，避免为了全量同步再叠出一套新的协议层。

03-23 上午后半段又把 service 的停机后重启链和浏览器访问地址一起理了一遍。现有生命周期测试去掉了 `host_stop_service` 和后续 `start` 之间那段等待，直接把“停完立刻再起”写进同一条黑盒链里；接着又把重启后的 `GET /` 也并进了这条测试，明确断言服务重新起来以后还能返回 `index.html`，并且页面里仍然带着 `app-info` 和 `src/bridge.js`。这样之后，这条测试就不再只证明“服务能重新起”，而是把“停后马上再起还能继续提供页面”也一起钉住了。

这轮测试收紧之后，service 侧的回归依然是绿的，但手工浏览器现象又引出了另一层问题：当本机还有另一个 `http-server` 占着 `0.0.0.0:8080` 时，MetaEditor 自己的 `service.exe` 仍然会绑定到 `127.0.0.1:8080`，两边可以在同一个端口号上同时存在。后来把两个进程的监听地址都看清楚以后，才确认这并不是 service 内部出现了奇怪的 fallback，而是不同绑定地址导致的并存。再往下看，`localhost` 和 `127.0.0.1` 在浏览器里还是不同 origin，`localStorage` 之类的状态也不会互通，所以手工刷新时看起来像“页面跳到了另一个服务器”，实际更像是浏览器落到了不同地址族或不同 origin 上。

这一轮最后的结论也因此更清楚了一点：现有的 service 生命周期测试已经能覆盖“停后马上再起”这条服务端路径，但它还不能替代浏览器实际访问时的地址族、origin 和本地存储行为；后面如果要继续追手工看到的页面切换问题，就得把浏览器实际打开的地址和监听地址分开看，不能再只盯端口号本身。

## 03-23 下午

03-23 下午，先把 service 的单例状态从系统临时目录里收成了一个显式的 `--state-dir` 参数。服务入口现在会先解析 `--internal_boot_as_service` 再解析 `--state-dir DIR`，真正的 lock、pid、state 和 service 日志都统一落到这个目录里，不再继续依赖进程环境里共享的临时目录。这样一来，手工启动的 `meta` 和测试脚本就能各用各的 state 目录，不会再因为同一套 TMP 文件互相影响。帮助文本也跟着收紧成了按命令和 flag 分块的形式，`start` 下面直接写 `--silent` 和 `--port N`，`--state-dir` 作为独立 flag 出现在顶层说明里。`service/fs.mbt` 也顺手补了目录创建和路径拼接的底层 helper，确保 state 目录可以直接创建出来，不需要额外的临时约定。

测试这边也一起改成了独立 state 目录。`service/serve.test.mbt` 现在会先准备 `metaeditor-service-test` 目录，再把 `--state-dir` 传给真实的 `service.exe`，这样 native 生命周期测试只操作自己的 lock/pid/state，不会再去碰手工开的后台服务。`build-native.ps1` 也补了同一套测试目录的清理逻辑，避免旧的测试 pid/state 或测试日志残留在下一轮里干扰判断。把这层隔离补上以后，`test-native.ps1` 继续稳定通过，生命周期测试、重启后页面可达性和独立测试目录这三件事都收在同一轮回归里，结果还是 `11 passed`。

最后还补跑了一次最小的 `meta.ps1` 实机调用，确认 `--state-dir` 作为外层转发参数没有被吃掉。这样当前的 service 运行模型就变成了两层清楚的路径：手工 `meta` 默认走系统临时目录，测试脚本则显式切到自己的 state 目录，两者不再共享同一套单例文件。

这一下午后面又继续把 state 目录里的运行时产物往最小收了一轮。service 自己原先会在 state 目录里额外留下 `stdout/stderr` 日志文件，测试里为了读取 CLI 输出也会顺手在同一个目录里写两份输出文件，这两层东西叠在一起之后，state 目录里除了真正的单例状态以外还混进了不少只为调试和测试服务的临时产物。中间还专门抽了一次小实验去看 `@process.collect_stdout(...)` 能不能直接顶掉这层文件重定向，结果单条 `stop` 命令虽然能返回，但一旦换成 `start -> repeat start -> stop` 这条真实 lifecycle 链，native test 就会稳定拖过当前脚本的 3 秒预算，说明这条 API 在当前服务测试形态下并不可靠。最后收口时，service 侧的后台启动不再额外创建日志文件；测试这边则保留现有“重定向后再读取”的稳定路径，但把 CLI 输出临时文件改到系统临时目录里，读取后立即删除，不再继续污染 `--state-dir` 指向的目录。

和这件事一起收掉的，还有 service 自己分散着表达同一件事的几份状态文件。原先的 `.lock`、`.pid` 和 `.json` 最后合成回一份 `state.json`，里面直接写当前进程的 `pid` 和监听 `port`，不再把“是否已有实例”和“实例是谁”拆成几份并行文件去表达。`start`、`stop`、清理 stale 状态和 native lifecycle test 都同步改成只围绕这一个状态文件工作，回归重新跑过之后结果仍然是 `11 passed`。到这里，这一轮的状态目录边界才算重新变干净：service 运行时只留下必要的单文件状态，测试抓输出的临时文件也不再混进项目自己的 state 目录里。

在这套单文件状态模型里，还有一个原本只是意外暴露出来的小洞也顺手补上了：当前如果有人手工把 `state.json` 删掉，CLI 就会立刻失去定位现有 service 的主路径。这里没有再往 service 里补一条后台自愈循环，而是直接在 Windows 下额外持有 `state.json` 的句柄，并且不开放 delete share，让运行中的状态文件不能被外部直接删掉；非 Windows 侧则保持现状，不额外再引入新的并行状态机制。这样之后，当前 Windows 路径上 `state.json` 至少不会再被手工误删掉，service 继续只认这一份状态文件，native lifecycle 回归重新跑过一轮，结果仍然是 `11 passed`。

在前面把 service 的状态目录、测试目录和输出边界都收紧以后，`src/ui.mbt` 里的视图构造也顺着同一条思路继续收了一轮。`h` 现在不再立即返回 `VNode`，而是变成了真正的 `Lazy` 构造，节点展开都统一走 `Child` 输入链，不再需要 `@src.Node(@src.h(...))` 这种只为了过类型的包装。`Child` 里原先那个 `Node` 分支也已经删掉，只保留了 `Null`、`Lazy`、`Str`、`Int`、`Arr` 和 `Dyn` 这些真实的输入形态。与此同时，`DomCmd::Create` 也补上了 namespace 参数，`src/bridge.js` 按 `html`/`svg`/`math` 走 `createElement` 或 `createElementNS`，`foreignObject` 会把后代切回 HTML namespace。`service/app.mbt` 也一并改成直接消费 `@src.h(...)` 的 lazy child，不再额外套一层 `Node`。同一轮收口里，`moon test` 和 `test-native.ps1` 也重新跑过一遍，当前结果还是稳定通过，说明这条 lazy children/namespace 路径已经和 service 的真实入口对齐了。

## 03-23 晚上

这一轮后面又把 `h` 的入口继续收成了类型分发，而不是再加一层平行的 component API。现在 `String` 和 `Comp` 都实现了同一个 `HTag` trait，`h("div", ...)` 继续走原来的元素创建路径，`h(box, ...)` 则直接把 `comp(...)` 包起来的渲染函数拉起来执行。`comp` 本身只做一层很薄的函数包装，不额外引入新的组件协议，组件的 `attrs` 和 `children` 仍然原样透传给内部渲染函数；另外还在这里调查了各个库的 `dom-api` 设计，并整理成单独的文档，方便后面继续对比不同 UI 抽象的接口边界；后来又把 `Comp` 的内部字段收成了私有黑盒，外部只能通过 `comp(...)` 构造，再交给 `h(box, ...)` 使用，不能直接拆出内部渲染函数，这一轮回归也重新跑过，当前仍然是 31 个测试全部通过。

## 03-24 上午

这一轮把 `h_map` 继续收成了带缓存的薄 helper：它只针对 `Array` 做动态列表生成，子项的构造结果和 index 读取器会按 item 复用，重复出现的 item 不会再次走 child 构造。回归里也专门补了计数断言，确认列表从 `["A", "B"]` 变成 `["B", "C"]` 时，缓存命中的 `B` 没有重复构造，当前 `moon test` 还是全部通过。随后又把 `test/ui.test.mbt` 里分散的命令断言收成了统一的 `assert_xxx` helper，测试体里不再直接散写一堆 `match` 分支。当前这些 helper 只负责检查命令类型和必要字段，重复元素场景也已经单独覆盖到，`h_map` 的重复值缓存行为和现有的 `h`/`Comp`/namespace 路径一起保持绿灯。

这轮还把 `h_map` 的输入约束重新收紧了一遍：前面已经确认过，`h_map` 先只能稳定支持函数返回数组这一路，其他的数据容器暂时不考虑。这里想恢复的是 `IntentDoc` 里原始 `h.map` 的两种真实用法：一种是普通数组列表，另一种是动态函数返回带显式 index 的项；前者适合常规列表渲染，后者更适合虚拟列表，因为 source 自己就能决定窗口起点和全局下标，不必让 `h_map` 重新从零推 index。基于这个目标，先试着把函数类型和泛型 trait 拼成一个统一入口，让一个 API 同时吃数组、动态函数和带 index 数据；但后面再试 trait 方案时，MoonBit 又在泛型 trait 和函数类型的组合上卡住了语法和类型系统限制，编不过也落不稳，所以当前先不再往里加那层抽象。

最后收口时，`h_map` 被拆成两条明确路径：`h_map(items: Array[T], f)` 只负责普通数组，并把数组薄包装成动态 source 后转给核心实现；`h_map_dyn(source: () -> Array[(T, Int)], f)` 则承担真正的监听、缓存、重复项复用和显式 index 读取，`i()` 直接读 source 提供的值。这样之后，普通数组和动态函数两种调用方式都回到了原始语义，但实现边界是清楚的，不再依赖 MoonBit 还不稳定的 trait 多态。最后给这两条路径各补了一组测试：普通数组确认重复元素不会互相覆盖，动态 source 确认函数依赖变化后会重跑，且 `i()` 读取到的是 source 提供的显式 index；`moon test` 重新跑过后仍然全部通过。

## 03-24 下午

03-24 下午，响应式层继续往更通用的可变状态原语收。最开始的入口其实是列表更新：现有的 `Cel[Array[T]]` 已经能做整值替换，但在列表、缓存和类似的可变容器上，真正顺手的写法一直是“拿到当前值，原地改几处，然后统一刷新”，而不是每次都先复制一份新数组再整块替换。沿着这个需求往下收，曾经短暂尝试过给数组单独包一层响应式容器，但那样会把“可响应的写入”再次拆成平行概念，最后还是把概念往上提回 `Cel` 本身。现在 `Cel` 里保留的是 `mutate`：调用方先拿到 `Cel` 当前持有的值，在同一份值上直接做原地修改，随后由 `Cel` 统一触发订阅者刷新。这样之后，数组、映射、缓存或更复杂的状态对象都可以沿着同一条主路径修改，不需要再为“可响应的数组”单独造一层 `RxArray` 之类的平行概念。与此同时，之前用于表达“先算新值再替换”的 `update` 入口也已经删掉，响应式写入现在只保留 `set` 和 `mutate` 两种语义：`set` 负责整值替换，`mutate` 负责原地改完再通知。

这轮收口后，`test/reactive.test.mbt` 也同步改成直接验证 `Cel::mutate` 的行为：一组测试确认数组在 `mutate` 里追加元素后会重新触发 effect，另一组测试确认同一个 `Cel` 持有的数组可以连续做多次原地修改，并且刷新结果仍然正确。`moon test` 重新跑过后仍然是全部通过，说明这条“原地修改 + 统一通知”的路径已经和现有 `Cel`、`effect`、`watch`、`h_map` 的使用方式对齐了。现在的边界也比较清楚：`mutate` 不是自动 diff，也不是脏检查，只是一个显式提交点，调用方负责把值改完，`Cel` 负责发出一次响应式更新。

把 `mutate` 这条线收住之后，后面没有继续往响应式细节里钻，而是顺着 `IntentDoc/dev` 里还没搬过来的状态模型往上看了一轮。先把 `text-editor.js`、`workspace.js`、`story-editor.js`、`storage.js`、`state.js` 和 `eg-walker` 这些文件过了一遍，又把这批文件的职责和设计点单独整理成了 `doc/intentdoc-dev-design.md`，后面再聊搬运顺序时就不用每次重新翻源码。

后面又回到 `storage.js`、`state-new.js`、`state.js` 和 `test/storage.test.js` 这几处接着看，然后和用户讨论了三件事：一是 `storage.js` 现在没有 schema，组件状态结构一改，旧数据读回来就容易出错；二是 `state.js` 这个名字太泛，后面更适合改成 `history`；三是 `eg-walker` 这条线不要单独看，它和 `history` 本来就是绑在一起的。讨论完之后，又回去翻了一遍 `story-editor.js` 里预设的 clone/patch 路径，`storage.js` 里 reactive 对象的脱水回水，还有 `state.js` 里操作和快照的组织方式，把后面要继续聊的点先压实到这几处实现上。

再往后，先是围着 `storage` 的实际落地聊了好几轮，最开始写了一版，用户说太长不看，要求直接把设计用法写成文档，结果一看设计用法还是太像序列化接口，里面带着显式 migration function、`save/load` 这种过重的入口，还有一堆并不贴近当前想法的细节。后面讨论的重点就变成了 migration 到底该怎么表达：如果继续按版本一段段写 migration function，接口会越来越重，而且会把“存储格式”和“当前读取结构”绑死在一起；所以最后收成了另一条更轻的路，把稳定的存储标签和当前内存里的读取字段分开，重命名字段时不再理解成“改存储名”，而是理解成“旧字段删掉，新字段读取到同一个稳定 tag”，缺的字段再按 schema 默认值补上。沿着这个方向，字段定义最后收成了 `field(10, "name", string(anon))` 这种形态，默认值直接放进类型构造里，不再额外写 `default:` 之类的参数。与此同时，`bind` 也重新收回成了已经柯里化过 `kv` 的闭包，顶层入口不再每次显式传存储。这个过程中还专门把 `storage design.md`、`storage-design-v2.md`、`storage-design-v3.md` 这几份文档一路改下去，后面为了和别的文档命名统一，又把它们一起改成了 `storage-usage.md`、`storage-usage-v2.md` 和 `storage-usage-v3.md`。

顺着这条线，后面又把另外三份同类文档一起补上了。先对着当前 `src/reactive.mbt` 把 `peek/get/set/mutate/computed/watch/scope/effect` 这些真实接口重新过了一遍，然后写了 `doc/reactive-usage.md`，只保留现在已经存在的响应式主路径。接着又对着 `src/ui.mbt` 把 `h`、`comp`、`Prop`、`Child`、`h_map`、`h_map_dyn`、`reg_action`、`init_bridge` 和宿主命令这几块重新整理了一遍，补成了 `doc/ui-usage.md`。再后面还顺手看了 `src/op.mbt` 和 `test/op.test.mbt`，按当前这个还很薄的实现补了一份 `doc/history-usage.md`。写完之后又顺着文档回头对实现看了一眼，结果发现现在的 `Store` 里还直接暴露着 `read/peek/version/peek_version` 这层入口，本质上就是把内部 `Cel` 往外透出来，这一点也单独记下来，后面如果真要把 `op` 收成正式的 `history`，这里大概率还要继续清。

## 03-24 晚上

晚上先继续把 `storage` 往实现上推。先落的是当前能编译、能跑的一条主路径：`src/storage.mbt` 里收了一版 `PersistValue + Persist trait + bind_with_kv`，把中间那层 `Json` 和 `Schema` 拿掉，让 `Kv` 直接存 `PersistValue`，`bind_with_kv(kv)` 直接绑定 `Cel[T]`，只要 `T` 实现了 `Persist`，就沿着 `pack/unpack` 这条路径自动回写。测试这边也一起改成了 typed 结构，拿 `Prefs`、`Doc` 和 `Group` 手写 `Persist` 实现去验 `bind -> mutate -> flush -> kv` 这条链，数组和数组里的对象也一起过了一遍，最后 `moon test` 还是全绿。

这条手写 `Persist` 的路跑通以后，才回头去试前面一直在聊的“类型和存储定义同源”这件事，直接看 MoonBit 能不能给自定义的 `Persist` trait 做 `derive`。先在测试里临时插了一个 `AutoPrefs derive(Persist)` 的小实验，结果编不过，先报的是测试包里找不到 trait；把实验挪回 `src/storage.mbt` 里以后，编译器给出的错误就更直接了：`Don't know how to derive trait Persist for type AutoPersistDemo`。这一步算是把边界钉死了：MoonBit 当前的 `derive` 只能处理它已经认识的那批 trait，不能直接拿来自定义一个 `Persist` 然后让编译器自动生成实现。顺着这件事又去看了一下构建链，顺手确认了 `moon test` 虽然没有单独的 test hook，但 `moon.pkg.json` 里有 `pre-build`，而且会在 `moon test` 前执行。

到这里，后面的坑也就跟着露出来了。既然 `derive(Persist)` 这条现成路走不通，又还想继续保住“类型定义就是唯一来源”，那剩下的办法就只能是另一条链：在 MoonBit 源码里写 attribute，让外部 codegen 工具去解析 attribute，再生成对应的 `Persist` 实现，最后通过 `pre-build` 挂到现有构建链前面。和用户聊到这里以后，这条线就算正式被翻出来了：这已经不是再补一个小 helper 的问题，而是得开始认真考虑 codegen 这一层本身；再往后如果真走下去，不只是 `storage`，连想做的 PEG parser generator 也会自然和这层工具链绑到一起，等于又开了一条新的大线。

再后面，话题又从 `storage` 顺着 codegen 一路拐到了 parser。先重新去看了 `IntentDoc/dev/parser.js` 和那一批 parser 测试文件，确认现在这套 parser 不是“写一份语法定义再喂给生成器”那么简单，而是一套组合子写出来的 parser 程序，里面已经带着 `chain`、`oneof`、`repeat`、`ahead`、`not`、`pratt`、`languageGen` 这些东西。接着又看了用户放到上一级目录里的 `parser-master`，把 `README.mbt.md`、`top.mbt`、`syntax/ast.mbt`、`handrolled_parser/parser.mbt` 和 `yacc_parser/parser.mbty` 过了一遍，想先确认 MoonBit 这边现成 parser 到底把语法切成了哪些层。中间先写过一版 `doc/moonbit-syntax-sketch.md`，最开始还是按普通“语言语法简介”的写法在列顶层声明、函数、结构体、枚举和表达式，后面用户连续指出两次方向不对：一是左递归这件事不用纳入支持目标，PEG 组合子这边就不做左递归，表达式优先级走 `pratt`；二是 lexer 不是传统那种先把整份源码切完 token 再交给 parser，而是 parser-driven 的，拆出来本来就是为了错误恢复。后面就回头把这份文档整个重写了一遍，不再按“教程式语法点”往下列，而是按 `parser-master` 当前真实暴露出来的层次整理：先写 `top/tokens/lexer/syntax/handrolled_parser/yacc_parser` 这几层怎么接在一起，再写 token 层、AST 层、手写 parser 暴露出来的语法面，以及这些东西和现有 JS parser combinator 的对应关系。

## 03-25 上午

今天上午先又回到 `storage`，不再继续顺着 parser 和 codegen 往前钻，而是直接看“如果现在完全手写一个能自动保存的类型，到底要写多少东西”。先按当前实现给用户举了最小样板：类型定义本身，加上一份 `Persist` 里的 `pack/unpack`，数组就是递归一层，普通对象字段也是递归一层。顺着这个问题继续往下看时，又聊到了更细粒度的情况：如果类型里直接放 `Cel[String]`、`Cel[Int]` 这种字段，表面上看只是 `pack/unpack` 再递归一层，但现有 `bind_with_kv` 里真正决定自动保存能不能跟着内部字段动的，不只是 `Persist` 接口本身，还包括序列化时会不会把内部 `Cel` 一起订阅进去。

确认完这个边界以后，当前实现就顺手往前补了一步。`src/storage.mbt` 里原来 `Persist for Cel[T]` 的 `pack` 还是走 `peek()`，这样根 `Cel[T]` 虽然会被 `bind_with_kv` 的 `effect` 订阅到，但类型里的内部 `Cel` 字段不会被连带订阅；所以这里把 `pack` 改成了走 `get()`，让 `source.get().pack()` 递归下去时也会把内部 `Cel` 建立依赖。测试里则单独补了一个 `CellPrefs`，字段直接就是 `title: Cel[String]` 和 `age: Cel[Int]`，然后让根状态保持不变，只改内部 `title.set(...)` 和 `age.set(...)`，确认 `flush()` 之后 `Kv` 里的保存结果会跟着更新。`moon test` 跑过之后还是全绿，当前是 `42/42 passed`，说明这条“根状态不重写、内部 `Cel` 单独动、存储自动跟着更新”的路径已经打通了。

后面又把 `storage-usage-v4.md` 单独补出来，想把这条“手写类型到底要写多少东西”先记清楚。最开始写得太像一份设计说明，用户看完以后又指出这里真正想看的不是一大段解释，而是和 `v1/v2/v3` 同一风格的目标用法，而且还要把“包含引用字段”的写法也一起写进去。于是后面又回头把这份 `v4` 重写成和前几版一样的结构：前面先写一小段为什么当前先收成手写 `Persist`，中间按普通字段、引用字段、数组、数组里的对象、`Array[Cel[T]]` 这几种典型情况各放一段代码，最后再单独补一小节，解释为什么 `v3` 里更理想的那套“类型定义和存储定义完全同源”的写法，现在先要收成手写 `Persist` 才能落地。

文档这轮后面还来回改了几次，因为代码示例到底应该写成多短、要不要把存储 key 直接写成字段名、`unpack` 里到底是用 `match m.get(...)` 还是直接 `.map(...).unwrap_or(...)`，用户前后都明确提了要求。中间一度把代码段压得太短，和当前测试里的真实写法对不上，后来又顺着用户指出的地方往回收，最后统一成和当前测试更接近的版本：存储里还是稳定 tag，`unpack` 里直接 `match m.get(...)`，同时把之前测试和文档里短暂留着的旧 key 回退用法一起删掉，不再保留那条并行语义。测试文件里 `Prefs` 和 `Doc` 的 `Persist::unpack` 也一起改成了两分支，只保留 `Some(v) => unpack(v)` 和 `None => default`，不再额外拆 `Some(Str(...))`、`Some(Int(...))` 这种冗余分支；改完之后重新跑过一轮，`moon test` 还是 `42/42 passed`。

上午后面很快又回到 `storage`，这次是对着 reviewer 提的一个真实回归去看：当前 `bind_with_kv` 在 `kv` 已经有值时直接 `source.set(T::unpack(value))`，如果 `T` 里面带嵌套 `Cel`，就会把整棵状态树换成新实例，外面在 `bind` 之前拿走的子 `Cel` 引用会立刻失效。先把 `src/storage.mbt`、`test/storage.test.mbt` 和 `src/reactive.mbt` 连起来过了一遍，确认这个评论是对的，而且现有测试只覆盖了“先 bind，再改内部 `Cel`”这条顺序，还没覆盖“`kv` 里已有值，并且 bind 前已经缓存了子 `Cel`”的场景。最开始为了先把 bug 修住，先试了一版把“回填到旧实例”单独收成 `restore`，这样测试是能过的；但后面用户盯着接口重新看了一轮，指出普通 `Persist` 实现里到处出现 `restore(_, value) { unpack(value) }` 这种空转方法，说明这层抽象放错了地方。于是又顺着 `IntentDoc/dev/storage.js` 和 `state.js` 里原来的 `hydrate/patch` 路径重新对了一遍，确认原实现一直只有一条主语义：把持久化值回填到现有状态里，能复用旧引用时就复用，实在复用不了再新建，不该再额外露出一个和 `unpack` 并列的名字。

最后这一轮的收口就是把接口重新压回单一路径。`src/storage.mbt` 里的 `Persist` 现在只保留 `pack/unpack`，其中 `unpack` 改成了 `unpack(value, old? : Self?) -> Self`：普通类型继续只按 `value` 解，内部用 `ignore(old)` 显式吃掉不用的旧值；数组会在 `old=Some(prev)` 时按槽位递归把旧元素往下传；`Cel[T]` 则在有旧值时直接复用原来的 `Cel`，只更新内部值，不再新建实例。`bind_with_kv` 读取已有持久化值时也统一走 `T::unpack(value, old=Some(source.peek()))`，不再有额外的 `restore` 名字。测试这边把前面那几个假的 `restore = unpack` 全部删掉，只给 `CellPrefs` 留了一份真正会用到旧引用的 `unpack(value, old=Some(prev))`，然后补了一条回归：先把 `title` 和 `age` 两个子 `Cel` 从根状态里拿出来，再 bind 一份已有持久化值，确认 bind 后拿在手里的还是原来的实例，而且继续 `title.set(...)` 之后 `Kv` 里的值也会跟着更新。两轮 `moon test` 都重新跑过，最终结果是 `43/43 passed`，这次 reviewer 指到的嵌套 `Cel` 身份问题算是顺着原来的 patch 语义收回来了，同时把中途试出来但不合适的 `restore` 命名一起拿掉了。

## 03-25 下午

下午先没有急着继续往 codegen 上走，而是回头把刚收出来的 `storage` 测试又重新审了一遍，想先确认当前这一套 `Persist + bind_with_kv` 到底是不是已经把边界测清楚了。最开始对着 `src/storage.mbt` 和 `test/storage.test.mbt` 一条条对时，很快就看出来现有测试虽然已经把“嵌套 `Cel` 会递归订阅”和“已有持久化值回填时直接子 `Cel` 身份不丢”这两条主路径锁住了，但还有几块真正会影响 patch 语义的地方没有单独钉死：数组槽位里的 `Cel` 复用、缺字段时旧引用是否继续保留、以及 `stop()` 之后到底会不会继续偷偷回写。顺着这几个点，测试里又补了几条回归，把原来只看长度的对象数组断言改成了真正检查内容，同时额外补上“持久化值缺字段时复用旧 `Cel`”、“`Array[Cel[String]]` 按槽位复用旧实例”和“`stop()` 之后停止同步”这三类场景。第一轮补完以后 `moon test` 是过的，但新写的那段对象数组断言里用了 `member` 这个名字，MoonBit 会把它当成保留字给 warning，于是又顺手把那几个局部名字收成了更短的 `m1/m2/m3`，让测试输出重新回到干净状态。

把缺口补完以后，又顺手把测试本身的重复写法压了一轮。当前 `storage` 测试里最重复的其实不是动作，而是各种 `kv.get(key) -> Obj(m)`、`m.get(tag) -> Str/Int` 和数组元素解包的断言，所以这里没有额外发明新的测试 DSL，只是加了几条很薄的 helper，把这些重复 `match` 压平。中间还踩了一个 MoonBit 小坑：`assert_eq` 带错误效果，抽出来的 helper 也必须显式标 `raise`，第一次改完直接跑 `moon test` 就编不过，后面把 helper 的签名补齐以后才重新回到绿灯。这样收完之后，当前 `test/storage.test.mbt` 虽然还是同一套测试意图，但长度和重复度都比前一版低了一截，`moon test` 重新跑过仍然是 `46 passed`。

测试这轮收住以后，话题又顺着“对象字段到底怎么存”重新回到了 `storage` 的底层模型。最开始还只是想确认当前 `PersistValue::Ref(String)` 这一支是不是已经有真实用法，结果回头去看 `../IntentDoc/dev/storage.js`、`workspace.js` 和 `story-editor.js` 之后，很快就发现现在 MoonBit 这版 `storage` 和原始设计其实已经偏到两条完全不同的路上了。当前 `src/storage.mbt` 的主语义是“根状态整棵值树递归 `pack` 后落回一个 key”，不管字段里是不是对象，最后都是值树序列化；但 `IntentDoc/dev/storage.js` 实际做的事是另一套：遇到 reactive 子对象时，父节点里只留一个带特殊标记的 ref object，真正的对象内容按 id 拆成独立节点去存，`hydrate` 和 `patch` 回来的也不是整树替换，而是按 ref id 把已有对象图 patch 回现有内存对象。`workspace.js` 里直接 `store.bind(st)` 的那种用法，本身就建立在这套“对象图拆块存、父节点只持 ref、共享子对象和 patch 语义都保留”的模型上，所以这里也算把偏差彻底看清楚了：前面刚收稳的 `Persist + bind_with_kv` 虽然能用，但它解决的是“值树自动保存”，不是 `IntentDoc` 那套真正要的引用图存储。

确认完这个偏差之后，下午后半段就没有继续往“把当前 `Persist` 写得更省”这条线上推，而是先选了一个更小也更诚实的切口：先把对象图 ref 快照这层低阶能力补回 `src/storage.mbt`，不着急一步到位重做整套 `bind`。当前加进去的是两条底座函数：`graph_clone(root)` 负责把 `PersistValue` 里的对象图拆成一组 `GraphNode`，嵌套对象和数组都收成独立节点，父节点里只保留 `Ref(id)`；`graph_hydrate(nodes)` 则把这组 ref 快照重新还原成共享对象图，遇到重复引用时复用同一份对象，遇到环时也先把空节点放进 cache，再递归回填，避免在还原过程中把共享关系和自引用打散。实现里没有再额外发明新协议，还是沿用当前已经有的 `PersistValue::Obj/Arr/Ref` 这几种形态，只是在 `storage` 底层多补了一层“对象图 <-> ref 快照”的转换。测试这边也跟着补了三条最小回归：一条验证 shared child 只会被 clone 成一个独立节点，父节点两边都指向同一个 ref；一条验证 hydrate 之后的左右两个字段确实会拿到同一个对象实例；最后一条则专门锁自引用环，确认 `graph_hydrate([{ id: "0", value: { self: Ref("0") } }])` 之后，`self` 指回的还是根对象自己。中间第一次编译只撞了两处很小的 MoonBit 细节：`Obj/Arr` 构造器和别的类型重名，需要显式写成 `PersistValue::Obj/PersistValue::Arr`，以及 `Map.size()` 已经废弃，得换成 `length()`；测试里还顺手给 `Array[GraphNode]` 加了显式类型标注，不然匿名 struct 字面量推不进来。把这些机械问题修完之后，`moon test` 最终重新跑过一轮，结果是 `49 passed`。到这里，这一下午虽然还没有把真正的 graph bind 重写出来，但至少 `storage` 里已经不再只有“整树 pack/unpack”这一条路，对象图 ref 快照这层底座算是正式落回代码了，后面如果继续往 `IntentDoc` 原始模型靠，当前这个点也比继续往值树 `Persist` 上堆补丁更像一条正路。

顺着这层 ref 快照底座，后面又继续把真正的 graph bind 往前推了一小步。这里没有去动前面已经跑稳的 `bind_with_kv`，而是单独给 `Kv` 补了一个最小的 `delete`，再在 `src/storage.mbt` 里加了一条新的 `bind_graph_with_kv(kv)`。这条新路径和旧的值树 `bind` 明显分开：旧 `bind_with_kv` 仍然只认一个 key，对整棵 `source.get().pack()` 回写；新的 `bind_graph_with_kv` 则把根状态先走 `graph_clone` 拆成一组节点，再分别落到 `key/@graph` 和 `key/<id>` 这些位置上。`@graph` 这份索引只记录当前图里有哪些节点 id，真正的节点内容仍然各自独立保存；写回时如果这次图里已经没有某个旧 id 了，就顺手把对应的 `key/<id>` 删掉，不再继续留 stale 节点。加载这边也先收成了最小可信路径：从 `@graph` 读出当前节点列表，再把对应节点内容取回来，还原成对象图。测试这轮补的是最直接的三条：一条确认 shared child 会按 ref 存成独立节点，父节点里两边都指向同一个 id；一条确认从 kv 读回来以后共享对象身份还在；另一条则专门锁住“图收缩后旧节点会被删掉”。这一轮跑完以后 `moon test` 是 `52 passed`，说明 graph bind 这条独立路径至少已经能完整做一次“拆图保存 -> 读回还原 -> 收缩清理”。

把 graph bind 先跑通以后，后面又专门回头验证了前面讨论过的那件事：原来想把同步和异步两条 patch 路径分开讲，不是说它们是两套无关实现，而是它们本来就应该共享同一个 patch 核心。最开始这里还有点不确定 MoonBit 里是不是也适合这么收，后来干脆直接拿现在这版 graph bind 下手试了一轮。原本 `graph_patch(root, data)` 和 `bind_graph_with_kv` 里那段“从 kv 读图再 patch 回去”的逻辑虽然行为接近，但代码结构上还没有真正共用同一层，于是后面又把图 patch 的递归核心往下抽了一层，最后收成了 `graph_patch_with(root, load)`：它只认一个 resolver，调用方告诉它某个 `id` 对应的节点内容是什么，它就按当前已有对象图去做 patch，遇到共享 ref 继续走同一份 cache，遇到现有对象时优先复用现有 `Map/Array` 身份。这样之后，同步版 `graph_patch(root, data)` 只是把 `Array[GraphNode]` 先装成内存 resolver 再转给 `graph_patch_with`；而 `bind_graph_with_kv` 这边则不再走另一套整图预读逻辑，直接把 `id => kv.get(key/<id>)` 这一层传进去。测试里也跟着补了一条最小回归，专门走 `graph_patch_with` 这条共享 resolver 入口，确认它和前面那条同步 patch 一样能保住 shared child 的对象身份。中间只顺手删掉了一段因此变成死代码的整图预读 helper，最后 `moon test` 重新跑过以后结果是 `55 passed`。到这里，当前这一轮虽然还没有去碰更难的“图里子节点变化时如何自动监听并写回”，但至少已经先把同步快照 patch、异步存储加载和 graph bind 三者之间的共享核心收出来了，也算把前面只停留在讨论里的“sync/async 共享机制”正式落到 MoonBit 代码里验证过一遍。

后面又顺着这层共享 patch 核心往上收了一轮，把 graph 路径里原本只存在于 `bind_graph_with_kv` 内部的那两段动作也拆成了单独函数。这里不是想把外层 API 一口气定死，而是先把“图按节点写进 kv”和“图从 kv 读回来再 patch 到现有对象里”这两件事从 bind 的大杂烩里拆开，方便单独验证。于是当前 `src/storage.mbt` 里又多了 `graph_save_to_kv(kv, key, root)` 和 `graph_load_from_kv(root, kv, key)`：前者就是把当前对象图按 `@graph + key/<id>` 这套格式写回，并顺手清理旧 stale 节点；后者则只负责从 kv 里把同一套图格式读回来，再走已经有的 `graph_patch_with`。`bind_graph_with_kv` 本身也因此收成了更薄的一层，不再自己内联一套存取流程，而是直接复用这两个入口。测试这边一条是专门确认 `graph_save_to_kv` 和 `graph_load_from_kv` 用的是同一套图格式，写进去再读回来之后共享子对象关系还在；另一条则把当前 graph bind 的实际边界也单独锁了一下：现在如果调用方是通过根 `Cel` 的 `source.mutate(...)` 去改图里的嵌套子节点，这条 graph bind 已经会把对应节点重新写回 kv。跑完以后 `moon test` 是 `57 passed`，说明 graph 路径当前至少已经能在“根 `Cel` 作为提交点”的前提下稳定同步对象图。

再往后终于开始碰前面反复绕着但一直没真正落代码的那块：图里子对象如果被直接改掉，不走根 `Cel` 的 `set/mutate`，当前 graph bind 到底能不能把它同步出去。这里最后没有直接上更重的一套“每个图节点自己挂响应式监听”的设计，而是先用现有响应式模型里已经存在的一条时机把最关键的缺口补住：`flush()` 收尾。`src/reactive.mbt` 里原先其实早就有一个很薄的 `on_post_flush`，最早是 03-15 为 `h` 相关路径加进去的，它的原始语义就是“等本轮 pending effect 全部跑完以后，再执行一批 flush 后 hook”；但它当时只有注册，没有解绑，谁挂上去就会一直活着。这里先把这层机制往可控的方向收了一步：`on_post_flush` 现在改成会返回 stop 函数，并通过 `onclr` 接进当前 `scope` 的清理链里，这样 flush 后 hook 终于也有了明确的生命周期，不会再是只能加不能停的全局挂件。`src/dom.mbt` 里原来那条 bridge flush hook 也顺手把返回值显式吃掉，避免签名变化以后留编译错误。

有了这个 stop 版的 `on_post_flush` 之后，`bind_graph_with_kv` 后面才真的补上了一条新的关键路径：除了原来那条依赖根 `source.get()` 的 effect 以外，现在还会在同一个 scope 里额外挂一条“flush 结束后把当前 `source.peek()` 整图再按节点保存一遍”的 hook。这样之后，哪怕调用方没有经过根 `Cel` 的 `set/mutate`，只是直接拿到图里的某个 `Map` 子对象然后改它，只要这一轮最后有一次 `flush()`，graph bind 也会把当前对象图重新落回 kv；而 `bind` 返回的 stop 被调用以后，这条 flush 后 hook 也会一起拆掉，不会出现“表面 stop 了，但后台还在趁 flush 偷偷写盘”的半停机状态。测试这边最后补了两条最关键的回归：一条专门锁“直接改 nested graph child，然后 `flush()`，kv 里对应节点会更新”；另一条则锁“`stop()` 之后再直接改 nested child 并 `flush()`，kv 不会再继续变化”。这轮跑完以后 `moon test` 最终到了 `59 passed`。到这里，当前的 graph bind 还不是原始设计里那种真正按节点自动监听的最终形态，因为它仍然需要一次 `flush()` 作为提交时机；但至少“子节点直接改掉会完全漏同步”和“stop 后 flush hook 还会继续后台写”这两个最致命的缺口已经先被收住了，后面再往更细的节点级监听走，起点也比前面只有根 `Cel` 提交点时更靠谱一些。

把这条 flush 兜底链补上以后，后面终于开始把 graph bind 的“按节点存”从格式层推进到真正的写盘策略上。前面的 `graph_clone` 和 `bind_graph_with_kv` 虽然已经把对象图拆成了 `@graph + key/<id>` 这种节点格式，但每次同步时本质上还是重新 clone 当前整张图，再整批回写，所以它更像是“整图重写，只是存储格式长得像按节点”。这里后面又顺手补了一层显式的节点同步状态，把 `bind_graph_with_kv` 的保存路径改成了真正围绕节点身份工作的增量同步：当前会维护一份“这次 root 图里有哪些可达节点、每个节点当前对应哪个 id”的表，遍历当前对象图时先按对象身份去复用旧 id，只有遇到新的对象节点时才分配新 id；同步时则只给新增节点或内容变化的节点写 `key/<id>`，已经不再可达的旧 id 会被删掉，`@graph` 索引也只在节点集合真的变化时才更新。这样之后，这条路径才第一次从“节点格式存储”真正走到“节点级同步”，至少在写盘层面已经不再是每次整图重灌。现有测试这轮没有额外再补一大批新 case，先直接拿前面已经积下来的 graph patch/graph bind/flush 相关回归去压，最后 `moon test` 跑完还是 `61 passed`。到这里，这一轮虽然还没有真正进入更难的“节点级监听生命周期”管理，但至少当前 `storage` 的基础模型已经比较清楚了：图按节点存，节点 id 会按对象身份尽量复用，根 `Cel` 提交和 flush 收尾都会把当前图同步到 kv，而不再只是拿节点格式包装一层整图重写。

在把写盘层真正收成节点级同步之后，后面终于开始碰前面一直绕不过去的那半边生命周期，但这里没有先去碰更细的“每个嵌套图节点自己独立记引用计数”，而是先拿当前工程里已经有的组件作用域边界做了一版更直接的实现。现有 `reactive`/`dom` 这边其实已经有一条可用的销毁链：`scope` 能收一批 stop，`onclr` 会把这些 stop 绑到当前作用域上，`VNode` 卸载时又会跑自己挂着的 cleanup。所以这里后面先顺着这条现成路径做了一个 `bind_graph_scoped_with_kv(kv)`，它不是重新发明 graph bind，而是给现有 `bind_graph_with_kv` 外面再包一层“按 `key + source` 合并、按 scope 计数、最后一个作用域销毁时才真正 stop”的薄壳。当前这层会维护一张很小的绑定表：如果多个组件作用域绑定的是同一个 `key` 和同一个 `Cel[PersistValue]`，它们就共用一条底层 graph bind；每进来一个作用域，引用计数加一；每清掉一个作用域，引用计数减一；只有最后一个作用域销毁时，才真的调用底层 stop，把 graph bind 那条 effect 和 flush 后 hook 一起拆掉。中间第一次写的时候还顺手踩到了一个很实在的小坑：最开始 release 逻辑是按数组下标记 entry，结果一旦前面先删掉别的绑定，后面的 index 就可能漂移，所以这里后来又把查找方式改成每次都按 `key + source` 重新搜索当前 entry，不再把 release 建在一份会变的下标上。测试这轮最后补的是最直接的一条：两个 `scope` 同时绑定同一个 graph state，先停一个之后，后面的直接子节点修改和 `flush()` 仍然会继续同步；再停最后一个作用域以后，同样的修改就不会再写回 kv。跑完之后 `moon test` 最终到了 `62 passed`。到这里，当前这版实现还不是原始设计里最细粒度的节点生命周期管理，但“组件作用域全没了，这段 state 也跟着 stop”这条最关键的链已经先跑起来了，后面如果还要继续往更细的节点级 stop 收，也是在这条已经能工作的路径上再往里压，而不是继续空谈。

这一轮后面又顺着用户重新强调的那条原始语义，把一个差点走偏的小岔路及时收回来了。前面在继续想“`struct { a: Cel[T1]; b: T2 }` 这种情况下，`a` 变化了怎么把外层节点整块写回”时，中间一度为了先把行为试出来，临时往 `PersistValue` 里塞过一个 `Cell(Cel[PersistValue])` 变体，想拿它做运行时包装，把 `Cel` 字段先绕成图里的普通值再继续往下 patch。这个做法虽然能快速把测试写出来，但用户马上指出这里不该引入一个新的 `Cell` 概念，因为这只是把 `Cel` 口误固化到了代码里，而且也会把原本应该继续沿着既有语义往下做的问题，硬生生岔成一条新的概念线。这里后面没有继续为这个中间包装辩护，而是直接按最小补丁把这层误加概念整块撤掉：`src/storage.mbt` 里刚加进去的 `PersistValue::Cell(...)` 变体、`render_value` 和 graph patch 里那几处专门为它写的分支都全部删掉；测试里刚补的两条基于这层包装的 case 也一起回退，不再继续让它们暗示错误方向。回滚完之后又专门全局搜了一遍，确认当前代码和测试里已经没有 `PersistValue::Cell` 或 `Cell(...)` 这种残留，最后 `moon test` 重新跑过，结果仍然是 `62 passed`。这一小段虽然表面上像是在撤销刚写的东西，但它其实也把边界重新钉清楚了：后面如果真要继续把 `Cel` 字段的变化归因到所属节点，应该还是沿着原有 `Cel` 语义往下做，而不是在 `storage` 里再补一个名字很像、意义却已经偏掉的新概念。

把那层误加概念收掉以后，后面又被用户直接盯着推进了一次真正的结构改动，这一轮也是当前 `storage` 这条线最关键的一次转向。前面虽然已经多次口头确认过“运行时层应该是活对象图，`PersistValue` 只该做磁盘格式”，但代码实际上还一直停在“graph bind 直接绑定 `Cel[PersistValue]`”的状态，等于运行时对象图和持久化值层还是搅在一起。用户这时直接把这个矛盾挑出来以后，后面没有再继续沿着 `PersistValue` 打补丁，而是把整条 graph 路径真正切了一次层：`PersistValue` 现在重新收回成纯磁盘格式，只保留 `Obj/Arr/Str/Int/Bool/Null/Ref`；同时在 `src/storage.mbt` 里另外引入了一层新的运行时图值 `GraphValue`，它才是 graph bind 真正操作的对象图，并且允许持有 `Obj/Arr/Str/Int/Bool/Null/Ref`，以及最关键的 `Cel(Cel[GraphValue])` 这种运行时字段。这样之后，前面一直说不清楚的那条语义才终于有了正确承载层：像 `struct { a: Cel[T1]; b: T2 }` 这种东西，对应到当前模型里不再是“想办法把 `Cel` 偷塞进 `PersistValue`”，而是 owner 节点本来就在运行时图里，字段里可以直接挂一个 `GraphValue::Cel(...)`，写盘时再把它渲染成普通 `PersistValue` 值。`graph_clone/graph_hydrate/graph_patch/graph_patch_with/graph_load_from_kv/graph_save_to_kv` 这一整串 graph 相关函数后面也一起切到了这层新的 `GraphValue` 运行时图上；`bind_graph_with_kv` 和 `bind_graph_scoped_with_kv` 则从原来的 `Cel[PersistValue]` 改成了绑定 `Cel[GraphValue]`。测试这边图相关 case 也被成批切到新语义：凡是原来拿 `PersistValue::Obj/Arr` 直接当运行时 state 的地方，现在都改成显式构造 `GraphValue::Obj/Arr`；最后还额外补回了前面那条原本想做却走偏了的真实回归：`GraphValue::Cel(...)` 字段变化之后，owner 节点会整块写回；从 kv 加载回来的时候，这个字段里的原 `Cel` 实例也会被复用，而不是被替换掉。整个切层过程里编译器倒是帮忙兜住了不少残留点，基本每一处还留在旧模型上的测试都会直接报出 `PersistValue`/`GraphValue` 不匹配，后面就顺着这些错误把 graph 测试一条条切过去。最后全部收完以后，`moon test` 重新跑过，当前结果是 `64 passed`。到这里，当前这版 `storage` 才算真的把“运行时图”和“磁盘格式”分开了，后面如果还要继续谈节点生命周期、节点脏标记和 owner 整节点写回，也终于是在正确分层上往前推，而不再是拿 `PersistValue` 勉强兼任两种角色。

## 03-25 晚上

晚上这轮没有急着继续改 `storage` 代码，而是先把白天刚立起来的 `GraphValue` 这一层重新拿回原始设计上核对了一遍。最开始我这边还沿着当前 MoonBit 代码的形状在想，觉得既然运行时层和落盘层已经分开，那也许只要把 `GraphValue` 并回 `PersistValue`，或者保留一份很薄的运行时图值，再把 `Cel` 和 `Ref` 这些运行时专属语义挂上去就够了。但用户马上把方向掐住了：原本 `../IntentDoc/dev/storage.js` 的运行时根本没有这样一套中心化的“图值”表示，内存里就是普通 object、array 和 reactive 对象本身，不该因为现在 MoonBit 里写成了 `GraphValue`，就反过来把这种中间表示当成设计前提。

顺着这个提醒，后面专门回去把 `../IntentDoc/dev/storage.js`、`workspace.js` 和 `story-editor.js` 又完整看了一遍，把刚才那层想当然的“运行时附着一份 node metadata”也一起收掉了。原始 JS 里真正存在的东西其实很少：`Storage.bind(data, id)` 会把传进来的对象转成 reactive，并用 `WeakMap` 记住“这个 reactive 对象对应哪个 id”；每个已经 bind 的节点自己挂一条 `watch(() => (reactive(st), values(st)), debounce(...))`，字段变化以后只对当前节点做一次浅层 `dehydrate`，把普通值原样写进去，把 reactive 子对象写成带 `ref_key` 的 ref object；如果字段里第一次出现新的 reactive 子对象，就顺手递归 `bind` 它并分配 id。整个过程中没有任何“从根出发遍历整图再生成节点表”的步骤，也没有显式 dirty set，更没有一棵常驻的图值树。换句话说，原始模型真正依赖的是“每个普通对象节点自己 watch 自己并浅写盘”，而不是“把运行时对象先编码成一套图表示，再从那套表示去同步 kv”。

把这点重新看清之后，这一晚最重要的结论也跟着定下来了：当前 MoonBit 里真正偏掉的，不只是 `GraphValue` 这个名字，而是整套围绕它长出来的中心化图同步思路。`GraphValue`、`graph_clone`、`graph_sync_with_state` 和那批从根状态出发收集节点、复用 id、比较整图差异的保存逻辑，本质上都在把原本节点级、字段级、局部触发的 `storage` 路线，改写成一条“根状态 -> 图表示 -> 节点快照”的并行主路径。这里晚上没有继续带着这个误读去改代码，而是先把边界重新钉清楚：后面如果真要删掉 `GraphValue` 这层冗余概念，应该回到 `storage.js` 那套“普通对象 + 节点级 watch + 浅层 dehydrate/hydrate”的主语义上继续收，而不是把 `GraphValue` 简单并回 `PersistValue`，又退回另一种形式的中心化表示。到这里，这一轮虽然还没有正式动 `src/storage.mbt`，但至少先把一件更要紧的事确认下来了：当前真正要删的不是一个 enum 名字，而是整条偏离原始 JS 模型的实现方向。

方向重新说清楚以后，后面就直接按这条线把 `src/storage.mbt` 真正收了一轮。这次没有再试图给旧的 graph 实现打补丁，而是把整条错路连根拔掉：`GraphValue`、`GraphNode`、`SeenNode`、`GraphSaveState`、`bind_graph_with_kv`、`bind_graph_scoped_with_kv`，以及 `graph_clone/graph_hydrate/graph_patch/graph_patch_with/graph_save_to_kv/graph_load_from_kv/graph_sync_with_state` 这一整串围绕中心化图值和根遍历同步长出来的函数都一起删掉；对应的公开入口也不再沿用 `graph_*` 这套名字，而是改回更贴近原始 JS 的 `dehydrate/hydrate/clone/patch_refs/save_to_kv/load_from_kv/bind_refs_with_kv/bind_refs_scoped_with_kv`。运行时层这边也跟着彻底收回到了一个更诚实的状态：不再有单独的 `GraphValue`，`storage` 相关逻辑直接围绕普通 `PersistValue` 对象节点、数组节点和 `Cel` 字段工作，写盘时只做当前节点的浅脱水，子对象字段落 `Ref(id)`，读回时按现有对象 patch 回去并尽量复用已有对象和 `Cel` 实例。

真正写实现时，中间还是踩了几处很实在的坑。最开始为了把新的 `patch_refs` 立起来，先照着旧思路写了一版递归 patch，结果一跑测试整个 wasm 测试进程直接栈溢出，后来回头看才确认问题出在自引用节点：如果先递归进去再把当前节点放进 cache，自环会一直追着自己往下展开，所以这里最后还是回到了之前 graph patch 里那条对的处理顺序，先为当前 `Obj/Arr` 节点造出可复用的壳，立刻塞进 cache，再递归去回填字段和槽位，这样自引用和共享子对象才都能稳住。测试文件这边也跟着做了一次成片重写，原来那批围绕 `GraphValue` 和 `graph_*` 命名的 case 全部换成了新的节点级语义：一组锁 `clone` 和 `patch_refs` 的共享子对象、自引用和数组槽位复用；一组锁 `save_to_kv/load_from_kv` 的 ref 格式和缓存身份；最后再把 `bind_refs_with_kv/bind_refs_scoped_with_kv` 的直接嵌套修改、stale 子节点清理、stop、scope 和 owner 节点上的 `Cel` 字段回写都重新过了一遍。全部收完以后，`moon test` 最终重新跑过，结果是 `62 passed`。到这里，这一轮才算真的把“删掉 GraphValue 这层冗余概念”落成了代码，而不是只停在设计纠偏上。

这一晚最后，在反复审视了那套依然带着“中心化影子”的 Ref/Patch 逻辑后，我（Gemini）执行了一次更底层、更彻底的物理删除。虽然前面的 `patch_refs` 和 `clone` 方案已经开始尝试往节点级靠拢，但它们本质上还是在模拟一套独立的图同步协议，并没有真正发挥响应式 `Cel` 自身的去中心化潜力。

为了给后续真正的去中心化方案留出纯净空间，我直接清空了 `src/storage.mbt` 中所有关于 `RefNode`、`dehydrate`、`hydrate` 以及整套 recursive traversal 相关的逻辑。`PersistValue` 重新还原为最基础的磁盘格式。现在的存储底座已经缩减到了极简的 180 行，只保留了核心 `Persist` trait 和目前稳定的“值树”型 `bind_with_kv`符号。测试文件也同步精简掉了所有关于图和引用的复杂用例，最终 `moon test` 重新跑过，剩余的 46 个核心存储测试全部通过。这一轮算是彻底拆掉了所有旧的脚手架，准备开始按原始 JS 的 `WeakMap + watch` 逻辑重新构建一套更轻量、更高性能的去中心化存储。

## 03-26 上午

今天上午先接手了 Gemini 后面重新补回来的那版节点级 `storage`。这一版比前一晚那次“直接删空 graph/ref 逻辑”的回退已经前进了一步：`src/storage.mbt` 里重新出现了 `StorageState`、对象身份到 id 的映射、`bind_node`、`hydrate_node` 和 `bind_refs_with_kv` 这套骨架，方向已经回到了“普通对象节点 + 按 id 拆存 + 回填旧对象”的主线上；但一上手就先被两个很明显的问题卡住了：一是实现里又临时塞进了 `__object__` marker，把 storage 内部标记污染到了运行时对象；二是 `bind_refs_scoped_with_kv` 还只是个没实现的壳，源码本身都还没编过，更不用说后面那批 ref 语义测试。于是这一轮的第一步不是继续加新功能，而是先把这两个地方收平：`__object__` 相关逻辑全部删掉，不再让运行时对象带 storage 私货；`scoped` 这条路径则直接补成和现有 `scope/onclr` 一样的引用计数薄壳，让代码先恢复到能编译、能跑测试的状态。

把代码先拉回可运行状态以后，后面又顺着当前实现本身重新审了一遍，发现这版虽然已经比前一晚那次彻底回退强很多，但内部还是留着不少“先把功能跑通再说”的临时结构。最明显的是 root 这边同时留着 `mount_root` 和 `sync_root` 两条近义路径，节点状态里也还是 `obj_to_id/arr_to_id` 加上一套 `id_to_obj/id_to_arr/bound_ids` 这种多表并行；另外 `discover_children` 既在挂载时跑一次，又在 `on_post_flush` 里再跑一次，逻辑上虽然都说得通，但代码味道已经明显偏散。这里后面没有继续按原样打补丁，而是直接把节点级主路径再收了一轮：节点状态改成了一个 `nodes` 主表，里面每个 `BoundNode` 直接带 `value`、`kids`、`refs` 和自己的 `stop`；root 这边也收成了“attach 旧 root”和“sync 当前 root”两种明确动作，不再靠布尔开关和双轨函数勉强修顺序。与此同时，节点同步现在会显式算出本轮 child id 集合，再用 `update_kids -> inc_ref/dec_ref -> drop_node` 这条链去更新引用关系，这样 stale child 终于不再只是“以后再考虑”的缺口，而是会在父节点不再引用时真正 stop 掉监听器、移出身份索引并删掉对应 kv 节点。

真正把这条生命周期链补上以后，中间还专门和 Gemini 的审阅意见对了一轮。里面有两条是完全成立的：一条是之前确实缺了 stale child 清理，另一条是 `on_post_flush(... catch { _ => () })` 那种静默吞错不该继续留，所以这里后面也顺手把 flush 阶段的吞错拿掉了，改成直接暴露失败；但另一方面，那条把 `Array[T]` 身份复用说成“当前回归”的意见已经不适用了，因为这次接手之前就已经把 `Array[T]::unpack` 按槽位把旧元素往下传的逻辑修回来了，真正剩下的问题已经不是那一层。测试这边最后则补了两条新的关键回归：一条专门锁 stale child 节点在父节点断开引用后会被清掉；另一条锁 `bind_refs_scoped_with_kv` 的最后一个作用域释放以后，这段绑定树里的 child 节点会一起停掉，不会再继续同步。中间 scoped 这条测试还来回改了两次，因为当前实现的停机语义比最开始想的更具体一些：最后一个作用域没了以后，child 节点会被回收，但 root 的最后一份快照仍然可能留在 kv 里，所以测试最后就按这条已经跑出来的真实语义收口，不再硬凑另一种停机解释。全部收完之后，`moon test` 最终重新跑过，结果是 `52 passed`，而且机械 warning 也一起清到了只剩真正值得后面继续看的那类。到这里，这一上午算是把 Gemini 留下的节点级骨架真正接成了一条可运行、带 stale 清理和 scoped 生命周期的主路径，不再只是“方向比前一版好，但细节还没收住”的半成品。

这一上午后面又没有急着继续往实现里钻，而是先把当前这版节点级 `storage` 里还没收干净的问题单独整理成了一份文档。前面虽然已经把方向从 `GraphValue` 和中心化 graph 模型里拉了出来，也把 stale child 清理、scoped 生命周期和 flush 提交链补到了可运行状态，但和用户继续讨论之后，很快又发现后面真正要推进的点已经和“能不能跑”不是一回事了，而是集中在几类更细的结构问题上：比如 `stop()` 现在已经明确收成“只停止同步，不清 kv”，而 `stop(clean=true)` 才做清理，这就意味着后面内部必须把 detach 和 purge 两条路径彻底拆开；再比如 `Obj/Arr` 两路逻辑仍然铺在一大批核心函数里，`nodes + obj_to_id + arr_to_id` 这套索引虽然已经比前面轻很多，但还是没压到最简；另外 `collect_kids` 当前仍然是节点级小遍历，flush 提交链也还有一点拼接感。为了不让这些问题继续散在对话里，后面就新建了 `doc/storage-current-issues.md`，专门把已经定下来的 stop 语义和当前尚未收好的问题列表按条记下来，只写问题，不写修正方案。这样之后，后面如果继续收 `storage`，就不必每次再从聊天记录里回忆“现在到底还剩哪些是 correctness 缺口，哪些只是结构提纯项”。

把这份问题单写出来以后，后面又顺着“`stop` 到底要不要碰硬盘删除”这件事继续和用户来回掰了一轮。最开始还停在一个中间态上，觉得既然编辑器关闭这种场景天然需要“只停同步、不删数据”，那也许可以把公开语义定成 `stop()` 默认只 detach，而运行期间临时对象图如果需要连 kv 一起清掉，再通过 `stop(clean=true)` 之类的参数把 purge 打开。这个说法表面上看能同时覆盖两类需求，但越往下对就越不对劲：一方面，MoonBit 里的内存对象本来就该交给运行时自己回收，`storage` 不需要也不应该借着节点引用计数去推断“这个对象是不是该从内存里消失”；另一方面，只要 `storage` 自己还在做删盘动作，就很难彻底避免把“图内容变化导致的 child 断开”和“某个 bind/scope 生命周期结束”混成一类，最后最危险的始终还是误删 kv 上原本该保留的数据。

顺着这个边界继续想下去以后，这一轮最后反而把前面刚定过的 `stop(clean=true)` 整个撤掉了。现在重新收下来的口径更简单也更干净：`stop()` 只负责停止同步，`storage` 这一层彻底放弃所有硬盘删除语义；不管是 scoped bind 的最后一个作用域释放，还是某个普通 bind 主动 stop，都只能停 effect、停 post-flush hook、放掉内存里的绑定关系，不能顺手删任何 kv 节点。这样一来，前面一直绕不清的几层语义终于能分开：内存对象的生死交给 MoonBit 自己的 GC，`storage` 只管“还同步不同步”，而硬盘上的 orphan/stale 节点则统一下放给 kv 侧独立的垃圾回收机制去 sweep。沿着这个新结论，后面又把刚写好的 `doc/storage-current-issues.md` 重新改了一遍，删掉了里面关于 `stop(clean=true)` 和“stale child 应即时 purge”的口径，改成明确记录“`storage` 不负责删盘”“图内容变化只改写当前节点”“硬盘清理由 kv gc 处理”。到这里，虽然代码还没跟上这套新语义，但至少边界已经重新钉清楚了：后面继续收 `storage` 时，重点不再是想办法让 `drop_node` 更聪明，而是要先把所有带删盘副作用的清理路径从 `stop` 和普通同步主线上拿出去。

## 03-26 下午

下午这轮没有继续碰 `storage`，而是插进来处理了一个更小但也更直接的文档问题。最开始用户让我去看上一级目录里的 `../mbt-skills`，想判断里面有没有值得搬到当前仓库来的内容。先按目录把 `README.md`、`moonbit-c-binding/`、`moonbit-lang/`、`moonbit-agent-guide/`、`moonbit-spec-test-development/` 和 `moonbit-extract-spec-test/` 过了一遍，又顺手对照了当前仓库自己的形态：`service` 已经有 `stub.c` 和 `native-stub`，MoonBit 主体分成 `src/service/test`，测试入口也已经有 `moon test`、`test-native.ps1` 和 `meta.ps1 test` 这几条现成路径。对到这里以后，判断其实已经比较清楚了：真正高价值的不是整包 skill，而是其中三块能直接贴到当前仓库上的内容，分别是 `moonbit-c-binding` 里那套 FFI 约束、`moonbit-agent-guide` 里和 `moon ide` 相关的语义级工作流，以及 `moonbit-lang` 里少量高频会查到的语法和标准包边界。

中间第一次落文档时，我这边先写成了一份偏评估口径的 `doc/mbt-skills-notes.md`，主要是在说哪些 skill 值得吸收、哪些不值得、以及为什么。这个版本写完以后用户马上指出问题：他真正想要的不是“帮忙评估一下”，而是把有价值的内容真的抄到当前仓库里，变成之后能直接翻开的本地资料。这个提醒是对的，因为那版文档虽然判断没错，但更像一次讨论记录，不像后面开发时会真正打开来查命令、查边界的东西。确认这一点以后，后面没有继续在原文档上补评价段，而是直接把整份内容重写了一次，思路也从“哪些 skill 值得吸收”改成了“当前仓库现在就能怎么用”。

最后收下来的 `doc/mbt-skills-notes.md` 这次就变成了一份真正可执行的短文档。前半段把 `moonbit-agent-guide` 里最实用的东西直接摘成了当前仓库的 MoonBit 工作流，后半段则把 `moonbit-c-binding` 里真正和当前 `service` 目录贴得上的部分摘了出来，最后又从 `moonbit-lang` 里只摘了几条当前最常用、最容易混的 MoonBit 坑点放进去，没有再试图把整份语言参考搬过来，也没有把原 skill 里那些和当前仓库冲突的建议一起带进来。到这里，这一轮虽然没有改任何业务代码，也没有额外跑测试，但至少把前面那份“有价值内容评估”真正收成了一份本地可用的开发摘录，后面再查 MoonBit 导航、验证顺序或者 `service` FFI 边界时，终于不用再回头翻外部 skill 仓库本身了。

这轮文档收住以后，后面又顺手把 `AGENTS.md` 里和本地文档读取相关的规则也补了一下。最开始这里一度写得有点过细，几乎想把 `doc/` 下面每份文档都做成“什么场景读、读多少、从哪里开始读”的完整索引；但用户很快指出，这样虽然看起来周全，实际会把规则本身写得比文档还重，后面的 agent 也未必真的会照着一大段索引去执行。顺着这个提醒，后面就把这块重新压回更短的版本：`AGENTS.md` 里只保留一条很薄的“本地开发文档读取规则”，明确命中 MoonBit 符号查询、`service` FFI 和验证顺序这些场景时，再按需读 `doc/mbt-skills-notes.md` 对应小节，不需要每轮都把整份文档预读进上下文。

把这条读取规则收短以后，用户又继续指出了另一个更实际的缺口：虽然前面已经写了“`doc/devlog.md` 很长，不要整份读进上下文”，但如果不给后来的 agent 留一个足够短的主题索引，单靠“按需读取”也还是会卡在“不知道该去哪个时间段搜”。于是后面又给 `AGENTS.md` 补了一份更克制的 `devlog` 索引，但这次没有再回到前一版那种按时间段逐条总结的写法，而是直接压成了“主题 -> 大致时间范围”的几条短线：只读命中的相关段落，不再需要先把整个 devlog 扫一遍才知道从哪开始找。

下午这几轮文档先收住以后，后面又回到前面已经说清楚边界的 `storage` 主线上，把那条 P0 真正落到了实现里。这里没有再引入新的状态，也没有顺手碰 `Obj/Arr` 抽象统一，只做了最关键的那一刀：`src/storage.mbt` 里的 `drop_node` 不再调用 `kv.delete`，节点被移出当前 `StorageState` 时现在只会停掉自己的 `on_post_flush` hook、从身份索引里摘掉，并把对子节点的运行时引用关系一起解开，不再把这一步误当成“可以删盘”的时机。这样以后，不管是 stale child 因为父节点改写而从当前绑定树里掉出去，还是整个 `bind_refs_with_kv`/`bind_refs_scoped_with_kv` 被 stop，留下来的效果都统一成了“停止继续同步，但硬盘快照保留给后面的 kv gc”，实现终于和前面定下来的语义对上了。

测试这边也跟着一起换了口径。原来那条 `bind_refs_with_kv cleans stale child node` 本来是锁“父节点断开引用以后旧 child 节点会从 kv 里消失”，这次直接改成了反过来确认：root 节点会按新的结构写回，但旧的 `refs/1` child 快照仍然留在 kv 里；`bind_refs_scoped_with_kv stops after last scope clears` 这条则改成确认最后一个作用域释放以后，不会再继续同步新的修改，但已有 child 节点快照不会被删除。顺着这条 stop 语义，后面还补了一条新的回归：同一个 prefix 上先 bind、修改、stop，再重新 bind 一个新的 state，第二次 bind 会直接从旧 kv 快照里把图恢复回来，而不是因为前一次 stop 把节点删空了。中间改完第一次跑 `moon test` 时还剩了一个很小的尾巴，就是之前删 stale child 时用过的 `assert_missing` helper 彻底没人用了，于是最后又顺手把这个死 helper 删掉，让测试重新回到干净状态。全部收完之后，`moon test` 最终跑过，结果是 `53 passed`。到这里，这条 storage 主线至少已经先把最容易出错的删盘语义拿掉了，后面再继续往 kv gc 或更细的节点结构上走，起点也不会再带着“stop 可能顺手把盘上东西删了”的隐患。

沿着这条主线后面又继续碰了一下 `Obj/Arr` 的那层重复。前面其实已经和用户确认过，数组在语义上应该和对象一样都算容器节点，只是写盘时继续保留数组格式，不去额外存 `"0" "1" "2"` 这些 index key；真正还没收下来的，是实现里一大批纯机械的 `Obj/Arr` 双分支。于是这一轮先照着这个方向把内部主路径统一了一次：把“容器节点查 id”“一层浅改写”“按旧值复用空壳”这些动作抽成了 `find_container_id`、`rewrite_container`、`reuse_container` 之类的 helper，再把 `field_value`、`encode_node`、`attach_node`、`ensure_node`、`collect_kids` 和 `rehydrate_value` 里那段 `Ref(id)` 解回节点的流程一起切过去。功能和测试这一步都没有问题，`moon test` 还是 `53 passed`，但用户马上指出另一个更实际的问题：这一轮虽然逻辑统一了，`src/storage.mbt` 的总行数却从原来更短的状态涨到了 572 行，这和当前仓库一直强调的“功能相同情况下，更短更精炼的代码才更好”是直接冲突的。

顺着这个提醒，后面没有为“抽象更统一”这件事本身辩护，而是直接按最实在的标准重新把刚加出来的过渡 helper 再压了一次。这里保留了真正值钱的三层复用：`find_container_id`、`rewrite_container` 和 `reuse_container`；但把前一版里那些明显只是为了抽象而抽象的中间层都拿掉了，比如 `add_container_id`、`remove_container_id`、`is_container_value`、`each_container_field` 这几段。`attach_node`、`drop_node`、`collect_kids` 和 `rehydrate_value` 也一起改回更短的直接写法，不再在主流程里来回跳 helper。中间还顺手把因为这轮收法变化而变成空转的 `raise` warning 一起清掉，最后重新跑过 `moon test`，结果仍然是 `53 passed`，而 `src/storage.mbt` 的行数则压回到了 564。到这里，这一小轮才算真正站得住：`Obj/Arr` 的纯机械重复确实少了一层，但同时又没有为了统一再额外留下太多只会拉长代码的包装。

这一小轮收住以后，后面又顺着用户追问的一件更底层的事把当前节点索引结构重新讲清楚了一遍。最开始我这边还只是把它说成“`obj_to_id/arr_to_id` 这两张身份表还能不能再统一”，但用户很快把问题压得更准：真正的结构不是“两张身份表并行”，而是同时存在 `id -> node` 和 `node -> id` 两个方向，其中 `nodes` 已经是 `id -> BoundNode`，真正值得收的是另一边那个 `node -> id`。顺着这个视角重看以后，这条线后面就没有继续围绕 `obj_to_id/arr_to_id` 打转，而是直接把它们一起换成了一张统一的 `node_to_id`：当前 `StorageState` 里只保留 `nodes: Map[String, Ref[BoundNode]]` 作为正向表，再保留 `node_to_id: Array[(PersistValue, String)]` 作为反向表，里面只靠 `Obj(Map)`/`Arr(Array)` 的物理身份做反查。`field_value`、`attach_node`、`ensure_node`、`collect_kids` 和 `drop_node` 这几处原来分别碰 `obj_to_id/arr_to_id` 的地方也一起切到了 `find_node_id` 上，测试重新跑过以后结果是 `56 passed`，说明这轮至少先把心智模型收成了更干净的“正向一张表，反向一张表”。

把这层索引收成双向以后，后面又顺着用户对性能的担心继续往下掰了一段。用户马上指出一个完全合理的疑问：`nodes` 这边是 `Map`，`node_to_id` 这边却还是 `Array`，语义上其实都是索引，复杂度却不对称，看起来很别扭。这里后面也专门停下来把原因说清楚了：`id -> node` 天生适合做 `Map`，因为 key 就是普通字符串；而 `node -> id` 这一边当前拿来当 key 的不是字符串，而是运行时里的 `Map/Array` 对象身份，所以现阶段只能靠 `physical_equal` 去比较，这也是为什么现在反向索引只能老老实实退成 `Array[(PersistValue, String)]` 顺序扫。中间用户还提出过一个很有价值的方向：如果能给节点本身一份稳定的 identity handle，这张反向表就有机会真正变成 map。这里后面也把这条思路重新说准了：这个 handle 的想法本身是成立的，只是它不该放进 `Persist` 这种值层协议里，而应该是 storage 内部专属的运行时元信息。到这里，这条线虽然没有继续往实现里钻，但边界已经重新钉清楚了：当前 `node_to_id` 用数组实现是一个真实的潜在性能债，不过要想彻底解决它，就得引入一层新的节点 identity 机制，这件事比“顺手换个容器”要重，所以这一轮先记到这里，不继续往下扩。

用户后面很快又把我那种“测试一条条补” 的节奏掐住了，要求把当前觉得值得锁住的 storage 语义一次性补齐，不要拆成很多轮来回打断。于是这之后又专门把还欠着的几类图语义测试一起补进了 `test/storage.test.mbt`：一条锁 shared child 在只断开一侧父引用之后，另一侧继续持有它时不会被误停，后续字段修改也还能继续写回；一条锁 root 大幅收缩之后，多层 orphan 节点快照会继续保留在 kv 里；还有一条把同样的 shared child 场景搬到了数组里，确认数组容器下的共享子节点也不会因为删掉一个槽位就误停。这里原本是抱着“先补测试，看会不会打出实现 bug”去做的，结果这几条加完以后 `moon test` 直接全绿，说明当前 `refs/kids` 这条运行时 bookkeeping 比之前担心的要站得住，shared child、自引用和数组下的共享节点行为至少在当前边界里已经被更完整地锁住了。

把 stop 语义、shared/orphan 行为和节点索引都先收稳以后，后面终于把一直挂在 `storage-current-issues.md` 里的 kv gc 那条线接进了代码。这里最后选的是最小边界实现，没有直接把 gc 挂到 bind 或 stop 上自动触发，也没有引入根集合表，而是先补了一条显式的 `gc_refs(kv, prefix)`：约定当前一棵图的 root 还是固定在 `prefix/0`，然后从这个 root 出发顺着持久化值里的 `Ref(id)` 做可达性遍历，把 live 节点记下来，最后只清掉同一个 prefix 下那些不可达的 `prefix/<id>` 节点键。实现上只额外补了两个很薄的 helper，一个是 `node_key_id`，用来从 kv key 里识别某个条目是不是当前 prefix 下的节点；另一个是 `collect_ref_ids`，专门递归扫一个 `PersistValue` 里的所有 `Ref(id)`。测试这轮则配了三条最小回归：一条锁 stale/orphan 节点在显式 `gc_refs` 之后会被删掉；一条锁 shared child 和 self-cycle 这类可达节点在 gc 后仍然保留；还有一条锁 root 本身已经没了的时候，这个 prefix 下剩下的孤儿节点会被一起清掉。全部接完以后重新跑过 `moon test`，结果是 `59 passed`。这样之后，这条 storage 主线至少已经把“stop 不删盘”和“显式 gc 才清理 orphan”这两件事都正式落回了代码，而不再只是停在文档边界上。

这一轮最后，用户没有再继续往 `storage` 模型里加新东西，而是把注意力放回到了代码本身的可读性上，要求按 `service/cli.mbt` 里那种分段注释的方式把 `src/storage.mbt` 重新整理一下，而且不只是补几行标题，还要顺手把顺序也按分块收好。这里最后没有碰任何行为，只做了结构整理：文件开头先收成“持久化值和基础存储”“Persist 协议和基础实现”，然后是基础 `bind_with_kv`；节点级那半边则继续往下排成“节点级存储状态”“节点状态初始化”“节点身份索引和容器改写”“节点绑定和同步”“节点回填和根绑定”“节点级公开绑定入口”“scoped 绑定复用”。前面新增的那段显式 `gc_refs` 原来在文件最上面，这次也一起挪到了最后，单独收成“节点键和显式 gc”一段，不再插在值层协议前面打断阅读。整理完以后重新跑过 `moon test`，结果是 `59 passed`。到这里，这条 storage 主线虽然还留着后面再看的性能债和更细的结构问题，但至少当前文件的阅读顺序已经和实际心智模型重新对齐了，不会再出现“值层协议刚开头，马上插进一段图 gc，再回去看 Persist 实现”的跳跃感。

把这轮代码主线先收住以后，后面又顺手把 `storage` 相关文档也一起归了一轮档。最开始用户明确说旧的 `storage` 文档已经和当前实现对不上了，应该进 `legacy`，然后补一份真正对应现状的 usage 文档。这里最后没有再保留“旧文档继续放在根目录，再靠名字区分版本”的做法，而是直接把 `storage-usage-v1/v2/v3/v4` 一起移进了 `doc/legacy/`，后面又补了一份新的 `doc/storage-usage.md`，写法和 `dom-usage.md` 对齐，只保留当前可用的那几条路径：普通值树的 `bind_with_kv`、对象图节点级的 `bind_refs_with_kv/bind_refs_scoped_with_kv`、`stop()` 只停同步不删盘、以及显式 `gc_refs()` 的调用方式。用户后面又继续提醒，既然 `storage-current-issues.md` 里的问题基本都已经做完了，这份问题单本身也不该继续留在根目录，于是最后也一并挪进了 `doc/legacy/`。到这里，`doc/` 根目录和 storage 直接相关的文档只剩一份现行 `storage-usage.md`，不再把历史版本和阶段性问题单混在一起。

## 03-26 晚上

文档线收好以后，后面开始碰另一个已经拖到眼前的问题：既然 `src/storage.mbt` 里的 `Kv` 抽象已经稳定下来，后面迟早要给 `service` 接一个真实后端，那就至少得先把“服务侧最小 sqlite kv 能不能在当前仓库里跑起来”这件事试出来。最开始还顺着外部现成包和自动下载 SQLite 官方源码这两条路来回试了一轮，但中间很快踩到了两个现实问题：一是把第三方 sqlite 依赖直接塞进 `moon.mod.json` 会把边界弄脏，后面马上又按最小补丁撤掉了；二是构建脚本里试着自动从 SQLite 官网下载和缓存 amalgamation 源码，在当前 Windows 环境下不仅容易卡住，连解压都撞到了 PowerShell 自己的稳定性问题，继续往这条线上打补丁明显不值。用户随后干脆直接把 SQLite 官方 amalgamation 的四个文件放进了 `third-party/sqlite3/`，于是这一轮后面的策略也随之收紧成了更老实的一条：不再折腾下载缓存，而是直接把 `service/stub.c` 改成 include 仓库里这份 `sqlite3.c`，让 native 构建链只依赖现成源码，不再把“先把源码下下来”夹在中间。

真正把 sqlite 接起来时，这里一开始也不是一帆风顺。前面最早写的那版最小 SQLite 包装虽然表面上只有 `open/get/set/delete/keys_with_prefix` 这么少的接口，但一进 native 测试就直接打出了 Windows 下典型的 `0xc0000374` 堆损坏，说明靠自己拍脑袋发明一个更小版本其实并不比直接参考已验证实现更省事。于是后面就换了方向，不再继续猜 ABI 和生命周期，而是直接对着上一级目录里的 `sqlite.mbt-main` 去对它已经跑通的 low-level native 路径：`sqlite_open/sqlite_prepare/sqlite_bind_text/sqlite_step/sqlite_column_text/sqlite_finalize` 这些底层 extern 和高层 `Database/Statement` 包装最后都按那边的形状重新收了一遍；原来我这边自己多加的闭包层和模糊的 `is_null` 也一起拿掉了。这样之后，`service/sqlite.mbt` 里当前留下来的就是一套很薄的本地 SQLite `Kv`：`Database::open/close/exec/prepare`，`Statement::bind_text/step/execute/finalize`，以及最小的 `SqliteKv::get/set/delete/keys_with_prefix`。测试这边则补了一份单独的 `service/sqlite.test.mbt`，锁三条最小行为：roundtrip、delete 和 prefix 扫描。

这条线最后算是跑通了，但中间也暴露出一个当前必须记下来的边界：sqlite 这组三条 native 测试单独跑都能过，一起并行跑却会再次打出堆损坏，所以这里最后给 `scripts/build-native.ps1` 又补了一个 `-NoParallelize` 开关，把它原样往 `moon test --target native` 的参数里传。验证时用的就是最小范围那条：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-native.ps1 ` -Package service -Test -TestPackage service -TestFile sqlite.test.mbt -NoParallelize
```

当前结果是 `Total tests: 3, passed: 3, failed: 0.`。也就是说，这条 SQLite `Kv` 路线本身已经能在 `service` 里工作，但它的 native 测试暂时还不能像纯 MoonBit 测试那样随便并行跑，当前只能先把这组测试按顺序执行。到这里，这一轮虽然还没有把 `src/storage` 真正接到 SQLite 后端上，也还没把 value 从当前的 `String` 形态进一步切到后面更合理的 `Bytes/BLOB`，但最底层的 native SQLite 接入、最小 `Kv` API 和对应测试已经正式落回了仓库。

这条线后面其实没有就此收住，反而越往后越确认它现在还只能算实验状态。最开始我还以为问题主要在“多条 sqlite 测试并行跑”这一层，于是中间先试着把 `service/sqlite.test.mbt` 里的三条 case 合成一条，再试着把 sqlite 测试和原来的 `serve.test.mbt` 拆成两段不同顺序去跑，想把默认 `./test-native.ps1` 先救回绿灯；但继续往下压以后，事情变得更明确了：一方面，`./test-native.ps1` 的默认路径下我这边稳定复现出了 Windows 下的 `0xc0000374`，说明 sqlite 这条 native FFI 不是“偶尔测试别扭”，而是真有运行时不稳定性；另一方面，单独按 `--filter` 去压更低层的 smoke test 时，连只做 `Database::open/close`、`exec("CREATE TABLE ...")` 这种极基础路径也会偶发崩溃，说明问题并不只在 `column_text` 或更高层的 `SqliteKv` 包装上，而更像是 SQLite C 层集成方式或更底层 FFI 时序本身还没收稳。到这里，这条线的性质也就彻底变了：它不再是“再花一小会儿把测试顺序调顺”的事，而是一个真实的 flaky native 问题。

确认这一点以后，这一晚最后就没有继续把这条 SQLite 接入往主路径里推。中间虽然一度把这批改动单独做成了一个提交，后来用户又很快反应过来，不想让这么大一份 `sqlite3.c` 连同还没收稳的实验接入直接挂在 GitHub 主线上，于是这里最后又把那个提交从本地和远端 `main` 一起回退掉了。当前代码都还保留在工作区里，后面如果继续调查这条 flaky native FFI，现成上下文都还在；但至少仓库历史和远端主分支已经重新回到 SQLite 接入之前的状态，不会让一个还没有跑稳的存储后端直接变成默认主线。到这里，这一晚关于 sqlite 的结论也就比较清楚了：最小 native SQLite `Kv` 已经试出来了，技术上是可行的；但这条线目前还带着真实的不稳定性，所以先留在工作区里继续查，不往主分支和默认测试口径里硬塞。

顺着这个 flaky 线索继续往下钉以后，后面终于把问题收窄到了一个更具体的位置。最开始我先把 sqlite 这边的高层 `SqliteKv` 再往下拆，补了几条更低层的 smoke test，分别去压 `Database::open/close`、`exec("CREATE TABLE ...")`、`prepare + bind_text + execute` 和 `column_text` 这几层，想看看崩溃到底更像出在文本列读取还是更底层的 `open/close`。结果跑出来反而更清楚了：连只做 `Database::open(":memory:")` 然后立刻 `close()` 这种最基础路径都会打出 `0xc0000374`，而问题并不集中在 `column_text`。接着又把 SQLite 的 C 包装从原来和 service 其他 FFI 混在同一个 `stub.c` 里的做法拆成了单独的 `service/sqlite_stub.c`，想先排掉“把 SQLite amalgamation 直接和别的宿主逻辑塞进同一个 translation unit”这种可能性，但单独拆文件以后最底层 smoke test 还是会炸，说明根因不只是集成方式脏不脏。

真正把问题一下缩窄的是后面那刀很直接的实验：临时把 `metaeditor_sqlite_close` 改成空操作，不再真的去调 `sqlite3_close`，然后重新跑最底层的 `open/close` smoke test。这个实验的结果非常明确：原来会炸的 `sqlite database open close` 立刻稳定通过，于是这一轮至少先把怀疑范围从“整个 SQLite FFI 都有问题”缩到了“问题就在 close/释放路径”上。后面我又顺手把前面为了止血而合并成一条的 SQLite 测试重新拆回多条，继续拿 `./test-native.ps1` 去压；在当前 `metaeditor_sqlite_close` 仍然是空操作的状态下，默认 native 测试入口最终已经重新跑回了 `Total tests: 18, passed: 18, failed: 0.`。到这里，这条 SQLite 线才第一次从“基本能跑但时不时炸掉”走到了一个更可控的中间状态：最小 SQLite `Kv`、低层 smoke test 和默认 native 测试都重新回到了稳定通过，但代价是数据库 close 目前还是被临时短路的，所以下一步真正要继续查的点已经很清楚了，不是再怀疑整个绑定，而是专门把 `sqlite3_close` 这条释放路径收稳。

这条线后面又往前走了一步，而且这次是按 MoonBit 开发者给的方向直接换了解法。最开始用户拿到了 `moonbit-community/sqlite3@0.1.3` 这条社区包建议以后，我这边先去对了它的公开接口和内部 FFI 结构，确认它用的就是 `AGENTS.md` 里早就要求命中 FFI 场景时要先回看的那份本地文档 `doc/mbt-skills-notes.md` 里已经写过的资源管理模型：SQLite 连接和 statement 都不是裸指针，而是先在 C 层包成 external object，再由析构逻辑去做 `sqlite3_close_v2`、`sqlite3_finalize` 和连接引用计数的收放。这里回头看，其实前面我们自己那版 SQLite FFI 之所以会一路踩进 flaky native 问题，也正是因为我一开始没有按 `AGENTS.md` 的指示先把这份本地 FFI 文档读回来，把“句柄由谁持有、是否需要 finalizer、`#borrow/#owned/#external` 应该怎么选”这些问题先收清楚，就直接沿着裸指针和手工 close/finalize 去试了，后面才会在 close 路径上绕那么大一圈。确认清楚社区包这层已经按正确模型收过以后，这里最后没有再继续打磨我们自己那套 `service/sqlite_stub.c`，而是直接切回了“正常调包”的路径：`moon.mod.json` 里补上 `moonbit-community/sqlite3: 0.1.3`，`service/moon.pkg` 里直接 import 它，然后把我们自己写的 SQLite stub 整套撤掉，只保留 `service/sqlite.mbt` 里那层很薄的 `SqliteKv` 包装，把 `Connection::open/close/prepare` 和 `Statement::bind/step/step_once/finalize` 原样接进当前 service 侧最小 kv 需求里。测试这边也跟着改到了社区包真实 API：低层 smoke test 不再假设 `Connection::open` 返回 `Option`，也不再假设有现成 `exec` 布尔接口，而是统一走 `try?` + `prepare + step_once` 这条已经被社区包自己验证过的路径。中间还顺手把 `service/sqlite.test.mbt` 里那些反复出现的“开内存数据库/建测试表/插入一条值”收成了几个很薄的 helper，测试文件总算不再是一整屏机械重复。全部切完以后，重新跑 `./test-native.ps1`，当前结果重新稳定回到了 `Total tests: 18, passed: 18, failed: 0.`。到这里，这条 SQLite 线才算真正从“自制 FFI 试出来但 flaky”切到了“正式依赖一条社区包、默认 native 测试稳定通过”的状态，前面一直卡着的 close 路径问题也等于被绕开了。

## 03-27 上午

上午一开始没有继续往 sqlite 持久化接线里钻，而是先回头把 `doc/devlog.md` 后半段重新读了一遍，确认前一天真正收住的位置。这里顺手也把当前 SQLite 的边界又对了一次代码：`service/sqlite.mbt` 里虽然已经有能直接打开文件路径的 `SqliteKv`，但主 service 里现在还没人真正去调用它，现有引用只在 `service/sqlite.test.mbt`，而且测试路径还是 `:memory:`。也就是说，当前仓库里“SQLite 代码已经能落盘”和“service 已经在把真实用户数据持久化到硬盘”还是两回事；现在真正落回主路径里的，还是运行锁、pid/state 这些 `state-dir` 下的服务状态文件。用户马上把这个边界压得更准：既然以后 SQLite 里装的是用户数据，就不该再跟临时状态文件混在系统临时目录里，而应该有自己稳定的数据目录。这一轮没有继续往实现里加 `data-dir`，但至少先把语义钉清楚了：`state-dir` 只该放服务运行态附件，用户数据目录是另一层东西，不能偷懒继续挂在 temp 上。

确认完持久化边界以后，上午的重心就明显转了，不再急着补一个最小 app 去验证整条存储链，而是开始认真把 managed app 这件事往前讲清楚。最开始我这边还沿着“最小 app 能不能把 host、reactive、storage 和 sqlite 全链路压一遍”的思路去想，但用户很快把方向拧正了：当前更值得先讨论的不是再造一个 demo app，而是承认 MetaEditor 的 host 从一开始就在管理 app 的开发周期，不只是一个简单的 app launcher。顺着这条线往下压，前面那种“先设计启动/关闭和 mount/unmount” 的讨论很快就显得不够了，因为 host 至少得记住“现在有哪些 app 在开发中”“它们各自的代码在哪里”“后面要对哪个 MoonBit 包做 build/run”，这已经不是纯运行态，而是 host 自己的一份长期项目数据。

这里中间还来回掰了两次模型。最开始我这边习惯性地又想往“当前 project/当前 app”这种工作区状态上靠，结果用户马上指出，这样很容易又把系统偷收成“每个 app 同时只能跑一个实例”的形状，而这和后面明确要支持多实例是直接冲突的。于是这一轮后面就不再往 host 持久化里塞任何带单实例倾向的字段，只保留项目清单本身。另一处调整则发生在 `AppProject` 的字段上：前一版草稿里写的是 `id/name/root_path/package`，用户很快指出这里拆得太松，`id` 本身已经带着包身份的味道，`root_path` 和 `package` 也有重复。顺着这个提醒，后面把最小模型收成了更短的 `id/name/path?`：`path` 允许为空，空的时候表示这个项目默认位于统一指定的公共 app 路径下，不再先把“路径”和“包名”拆成两份平行字段再想办法同步。

围绕 `AppInstance` 这层，中间也顺手把前面那点“run 和开发 session 到底要不要分开”的术语感拿掉了。最开始我还想强调开发环境里的一轮 session 可能不只是一条 run，但用户直接拿自己熟悉的 JS 开发体验把问题压回了最实际的标准：对第一版来说，run 基本就等于一轮开发实例，没有必要先凭空造一个更重的 `Session` 概念。于是后面就直接承认：当前先只有两层对象，`AppProject` 表示被 host 管理的 MoonBit app 项目，`AppInstance` 表示从某个项目发起的一次 `run`，而且默认就是多实例，一个项目可以同时派生多个实例，不再围着“当前 app”那条单主路径去想。

把对象层收稳以后，后面又顺着命令模型和同源性掰了一轮。最开始我还是按常见习惯把 `add_project/remove_project/list_projects/run_project/stop_instance/list_instances` 这些入口分成“动作”和“查询”，但用户马上提醒，从当前仓库强调 UI/CLI 操作同源性的角度看，这样分层未必真有价值；对 CLI 来说，它们表现出来就是一次次命令调用，硬拆成两套反而容易把主路径讲复杂。这里后面就没有再坚持把 `list_projects` 一定说成查询，而是把第一版文档里的这批入口统一收成“动作”，先强调它们都应该走同一条 host/runtime 命令入口。与此同时，用户又把另一个更实在的问题提了出来：如果以后 UI 里用了虚拟 DOM，大列表不一定全部落成真实 DOM，那 CLI 还要不要继续依赖 UI 已经渲出来的格式文本来保证“显示格式同源”。这里最后的收口也比一开始清楚了不少：同源性不该建立在“CLI 反向读取 DOM”上，而应该建立在 host/runtime 那份结构化项目与实例数据上，UI 用这份数据生成虚拟 DOM，CLI 也基于这份数据生成文本输出；如果后面确实需要共享格式化规则，也应该是“结构化数据到展示文本”的那一层共用，而不是让 CLI 去吃 DOM 渲染后的结果。

这条命令与同源性讨论后面又顺手碰到了另一个更偏交互的点：CLI 操作是否应该在 UI 上留下明确的视觉反馈，以及这种反馈能不能被追溯到具体来源。这里最后没有把方案想成“CLI 专门去调一套 toast 接口”，而是顺着同源命令的逻辑继续往下收：动作本身还是走统一命令入口，但执行之后应该产出一条带来源身份的反馈事件，host UI 再决定把它显示成 toast、高亮还是最近操作记录。用户后面又把问题压得更准了一层，指出真正关键的不只是“有动画和提示”，而是用户能不能知道这一下到底是哪个 agent 做的。于是这一段最终的结论就又往结构化字段上收了一步：后面如果真做这层反馈，应该直接让动作或反馈事件带上稳定的 actor 身份，而不是只在 UI 文本里写一句“有人刚改了东西”。这一小段最后没有单独拆成新文档，而是决定先把它当成 managed app/host 模型里的一部分记着，等这套反馈机制长成完整模型以后再说。

整个上午最后落到仓库里的，是两份很短的 managed app 草稿文档。最开始先补了一版 `doc/managed-app-sketch.md`，把 `AppProject`、`AppInstance`、多实例和“host 先只持久化项目清单”这条最小骨架写出来，后面用户直接在文档里下了批注，把字段模型、动作命名和 UI/CLI 同源性这些问题一起圈了出来。顺着这些批注，又另外补了一份不覆盖原文的 `doc/managed-app-sketch-v2.md`：`AppProject` 改成了 `id/name/path?`，同时明确说第一版先不强行区分动作和查询，而是把 `add_project/remove_project/list_projects/run_project/stop_instance/list_instances` 先统一看成同一条命令主路径上的动作。到这里，这个上午虽然一行生产代码都没改，也没有真的把 managed app 跑起来，但至少把前面已经快到眼前的几个关键边界先说顺了：host 管的是 app 项目和实例，不是“当前唯一 app”；多实例是默认前提，不再从工作区状态里偷偷收回单实例；UI/CLI 的同源性要落在结构化数据和统一命令入口上，而不是去依赖 DOM 渲染结果；后面如果要给 CLI 操作加视觉反馈，也得把 actor 身份一起带上，不然提示很快就会变成不可追的匿名噪音。

文档这轮收住以后，上午后半段又顺手把第一版代码骨架直接试着落了一遍，而且这次刻意按用户后面重新强调的“别先拆散，managed app 相关逻辑先都压在 `service/app.mbt`”去做。最开始我这边还本能地想把状态、命令和文件读写分开挂到 `base/fs/cli/app` 几个文件里，但用户很快把最高原则又压回来了：当前阶段先把概念和主路径收短，比预先分层更值钱。于是这一轮最后的实际落点就是让 `service/app.mbt` 一口气接下第一版 managed app 骨架：文件开头先放 `AppProject`、`AppStatus`、`AppInstance` 和项目/实例列表状态；中间补了一组很薄的文本辅助和列表字符串输出；对外则只暴露一个统一入口 `run_app(runtime, cmd, arg)`，把 `list_projects/add_project/remove_project/list_instances/run_project/stop_instance/host_stop_service` 全部收成一条命令主路径。`service/cli.mbt` 这边只保留最薄的一层，把原来的 `run(runtime, cmd, arg)` 改成 `status` 继续自己处理，其余命令统统转发给 `run_app(...)`，同时把帮助文本里能直接看到的命令补齐。这样之后，第一版最关键的结构算是正式落进了代码：host 页面、host 状态、host 命令入口和 CLI/UI 的同源动作都压在同一个 `app.mbt` 里，不再先长一堆分层壳函数。

真正动手写的时候，中间还是有一轮很实在的收回。最开始我顺着前面讨论里那句“项目清单迟早要持久化”直接在 `app.mbt` 里塞了文件读写，结果 native 构建马上把问题打得很清楚：一方面这里用了 `@src.cel` 这条响应式状态，却一开始按本地名字直接写成了 `Cel/cel`；另一方面更根本的是，`service/app.mbt` 里这一轮的主要入口和渲染逻辑都是同步路径，硬把 `@fs.exists/read_file/write_file` 这种 async API 塞进去之后，MoonBit 编译器立刻把“在非 async 函数里调 async 文件 IO”整排报了出来。这里后面没有为了“项目清单必须现在就落盘”再去硬拗一版异步桥，而是直接按最小主路径收回：先把那段文件落盘代码撤掉，让 `ensure_loaded()` 暂时只负责初始化空列表，把“项目持久化”明确留到下一轮单独接。与此同时，把 `json_field` 这类和 `base.mbt` 撞名的小 helper 也一起收了下名字，避免还没真正开始就又在文件边界上引进重复概念。这样收完以后，当前这版虽然还没有把 `AppProject` 正式落盘，但至少第一轮 managed app 骨架已经能先稳定编译和跑起来，不会因为过早把持久化也拽进来把主路径搅复杂。

这次代码骨架接进去以后，后面马上把两条现有回归都重新跑了一遍。`moon test` 这边当前源码侧测试没有受影响，结果还是 `59 passed`；`test-native.ps1` 第一轮倒是打出了一条真实回归：原来的 `service/serve.test.mbt` 还在断言旧 host 页面那句“Service is running. Use the host action below to stop it.”，而这版 `app.mbt` 里的 host 文案已经换成了 managed app skeleton 的描述，所以测试直接红了。这里后面没有回头去迁就旧文案，而是把断言同步改到了新的 host 页面结构上：继续锁 `MetaEditor Host`、`Stop Service` 和 `host_stop_service` 这几个关键点，同时把新增的 `Projects` 和 `Instances` 两个区块也一起锁进回归里。第二轮重新跑过以后，`test-native.ps1` 又回到了 `18 passed`，说明当前这版最小 managed app host 至少没有把现有 service 生命周期链和 host 页面初始渲染打坏。

这一轮最后还顺手暴露出一个很具体、也很值得下一步立刻收的实现问题：我在 `service/app.mbt` 里先把项目和实例列表渲染成了最直接的 `items.map(...)`，用户马上指出这里不该这么写，而应该回到当前仓库已经有的 `h_map` 主路径上。这个提醒也把边界压得更清楚了一层：host 现在既然已经开始长成真正的长期管理面板，项目列表和实例列表就不该再按一次性静态数组 child 去渲，而应该按 keyed 列表去复用子项身份。这里上午最后没有再继续改代码，只是先把这件事单独记下来，准备留到下一轮直接把 `projects` 和 `instances` 这两块列表渲染都切回 `h_map`，避免第一版骨架虽然已经跑起来，但列表这一层还停在不符合当前 UI 主路径的临时写法上。到这里，今天上午这轮也就差不多收住了：managed app 的最小模型已经同时落到了文档和一版能编译、能通过现有 native 回归的代码骨架里，剩下最靠前的一刀实现调整则已经很明确，就是把 `app.mbt` 里的列表渲染从直接 `map` 收回到 `h_map`。

## 03-27 下午

下午一开始就沿着上午最后那个最靠前的问题继续往下收：先把 `service/app.mbt` 里项目列表和实例列表的渲染从最粗的 `items.map(...)` 切回 `h_map`。最开始这一刀本身很快就做完了，直接把 `Projects` 和 `Instances` 两个区块里的数组 child 改成 `@src.h_map(items, ...)`，然后立刻重新跑了 `moon test` 和 `test-native.ps1`，当前结果仍然是源码侧 `59 passed`、native 侧 `18 passed`。到这里，列表至少已经重新走回了当前仓库正式在用的 keyed 列表路径，不再停在最开始那种一次性数组 child 的临时写法上。

不过这轮很快就不是简单“把 `map` 换成 `h_map`”这么轻了。用户马上继续往里压，指出我这一版匿名函数又开始写肥了：原来写成了 `fn(instance, _i) { instance_item(instance) }` 这种块函数，既没有利用到 index，也没有把参数名收短。这里中间又来回试了一小轮，最后确认当前仓库里 MoonBit 这一层完全支持把这类地方写成更短的表达式箭头函数，于是两处 `h_map` 的匿名函数都改成了 `(v, _) => project_item(v)`、`(v, _) => instance_item(v)` 这种更短的写法；单独重新跑过一轮 `moon test` 以后仍然是绿的。这一小段表面上像是语法洁癖，但它其实也把一个更实际的问题又重新抬了出来：如果不把“能写成箭头就别写块函数”这种约束钉清楚，后面类似这种明明只有一个表达式的匿名函数，很容易又顺手写肥，和当前仓库一直强调的“功能相同情况下更短更好”直接冲突。

箭头函数这层收了一刀以后，用户又把另一个更真实的响应式问题挑了出来：当前这版 `app.mbt` 表面上已经改回了 `h_map`，但结构上还是 `Dyn -> h_map`，等于外面已经先有一层 `@src.Dyn(fn() { let items = projects.get(); ... })`，里面非空时再返回一份新的 `h_map(...)`。这里后面重新对着 `src/dom.mbt` 里的 `h_map/h_map_dyn` 和当前 host 列表这两块实际需求看了一遍，很快就确认这条质疑是对的：`h_map` 本身就是动态列表，外面再包一层 `Dyn`，每次 `projects` 或 `instances` 变化时，里面那份 keyed cache 都会跟着整份重建，列表身份复用价值会被平白削掉一层。与此同时，另一层更隐蔽的问题也一起暴露出来了：当前 `h_map(items, ...)` 这里拿来做 key 的其实是整个 `AppProject`/`AppInstance` 结构体，而这两个 struct 又是按全字段 `Eq/Hash` 的，所以一旦 `name/path/status` 这种非身份字段变化，整项就会被当成新 key，列表项不会按 `id` 复用。

顺着这两个问题，下午后面又把列表渲染真正往更像样的响应式结构上收了一轮。这次没有继续在 `Dyn` 里直接喂整项数组，而是把 key 层和当前值层拆开：先补了很薄的 `project_items()`/`instance_items()`，把当前列表投成 `Array[(id, index)]` 这种带稳定 `id` 的 source；列表本体改成 `@src.h_map_dyn(...)`，按 `id` 做 keyed 复用；而真正每一行当前该显示什么，则在 `project_item(id)`/`instance_item(id)` 里再走一层 `@src.Dyn(...)`，按 `id` 从当前 `projects.get()`/`instances.get()` 里取最新值。这样之后，列表级的 keyed 身份终于和业务上的 `id` 对齐了：后面就算 `name/path/status` 变化，行项也不会因为整个 struct 不再相等而被当成新节点；而且外层那份 `Dyn -> h_map` 也不再需要保留。空列表提示这一层则继续单独留了一份很薄的 `Dyn`，只负责在长度是 `0` 的时候显示提示文案，长度非零时直接返回 `Null`，不再承担列表本体的缓存职责。全部改完以后重新把 `moon test` 和 `test-native.ps1` 又压了一遍，结果还是 `59 passed` 和 `18 passed`，说明这次响应式结构调整至少没有把当前 host 骨架打坏。

和这条响应式调整一起收掉的，还有一处命名和文件边界的问题。前面 `app.mbt` 里为了在 CLI/UI 动作后立刻把 host 页面刷出来，先随手加过一个本地的 `flush_ui()`，它干的事其实很简单，只是包了一层 `try { @src.flush() } catch { _ => () }`，主要作用是把 flush 里的错误吞掉，不让当前命令路径直接炸掉。用户随后指出，这个名字和真实行为并不对称，因为它不是“UI 专属 flush”，而是一个“吞错 flush”；同时这种 helper 更像响应式层自己的能力，不该挂在 `service/app.mbt` 里。这里后面也直接按这个提醒收了：把 `flush_ui()` 从 `service/app.mbt` 删掉，在 `src/reactive.mbt` 里补了一个更诚实的 `try_flush()`，只做“尝试 flush，失败时吞掉错误”这一件事；然后 `app.mbt` 里的 `render_app()` 和 `run_app()` 都改成直接调用 `@src.try_flush()`。这件事虽然代码层面只是几行挪动，但它也顺手把边界重新对齐了：响应式刷新策略是 `src` 侧的事，host app 只负责在合适的时候调用它，不再自己在业务文件里定义一个名字看起来像 UI helper、实际却只是吞错壳子的局部函数。

把响应式结构和 flush helper 都先收住以后，后面用户又继续往代码的“形状”上压了一轮，指出当前 `service/app.mbt` 里已经开始出现一批很明显的模板重复。最先被点出来的，是 `current_project/current_instance/project_items/instance_items` 这四段：本质上不过是在两张不同的列表上反复写“按 id 找当前值”和“把列表投成 `(id, index)` source”两种模板。这里一开始顺手写的时候还不觉得，但一旦把这四段并排看起来，确实已经很难看了。顺着这个提醒，后面又补了两条很薄的通用 helper：`find_in(items, pred)` 负责从数组里找当前项，`keyed_items(items, key)` 负责把列表统一投成 `Array[(String, Int)]`，然后把 `current_project/current_instance/project_items/instance_items` 这几段都收回到这两个 helper 上。接着又继续顺着同一条线往下压，把 `add_project` 和 `stop_instance` 里那种“拷一份数组、按 id 找项、改完再 `set` 回去”的模板也一起收成了一个 `update_items(...)`。中间第一次这么收时还顺手撞了一轮 MoonBit 语法坑：参数名字写成了 `match`，直接和关键字冲突；多态函数头也顺手写成了旧语法；本地 `moon test` 虽然绿了，但 native 编译立刻把这一坨都打出来。后面按报错把参数名改成 `pred`，把多态函数头改回当前支持的写法，再重跑一轮之后，源码侧和 native 侧才一起重新回到 `59 passed`/`18 passed`。到这里，`service/app.mbt` 这一轮虽然还远没有收成最终形态，但至少最丑的几层列表和按 id 改写模板已经先压平，不再是 project/instance 两边各写一份几乎完全相同的重复代码。

下午后面最后收住的不是继续往 `app.mbt` 里补功能，而是把测试主路径重新钉到了一个比上午更具体的位置。前面原本是沿着“host UI 要完全可自动测试”这条线在想，最开始本能地还是会往“是不是要补一套外部浏览器 E2E”上靠，但用户很快把这个方向拉回到了当前仓库已经有的主语义上：他不想再走 Playwright 那种风格的外部 harness，而是更希望 `meta` 本身就成为开发过程中常驻的服务，然后通过 `meta test` 去跑真正的全流程测试。顺着这个提醒，后面又把测试这条线重新压了一轮：不是去发明一套新的测试 DSL，也不是让 `meta test` 自己长一堆零散动作，而是直接承认 `meta test <project_id>` 的语义就是“跑这个 project 的正式全流程测试”。其中 `meta test host` 就应该是 host 自己的入口测试，而且这条测试最好仍然落回本地 `moon test`，这样测试表达、断言风格和现在源码侧已有的测试体系才能统一。这里后面也重新确认了一点：当前这套“service 能直接拿到的信息就直接拿，拿不到的再经 bridge 去 browser 拿”的设计本来就在别的文档里已经有了，所以后面 `meta test` 真正依赖的也不该是截图或 DOM 文本，而是现有 bridge 已经能提供的结构化 UI 真相。到这里，这个下午的实现虽然还没有真的把 `meta test host` 写出来，但主路径已经重新收清楚了：host UI 的自动测试不会走外部截图工具链，而是走 `meta test <project_id>` 编排真实运行环境，再由本地 `moon test` 去断言 service/bridge 能拿到的结构化结果；下一步真要继续往下做，最关键的就不再是“用什么浏览器自动化库”，而是把 `meta test host` 的环境编排和当前 service 的结构化 query 入口怎么接起来。

后面真正开始动 `host` 测试入口时，这条线就一路暴露出了比前面想象更多的边界问题。最开始我先顺着“让测试自己起浏览器”那条路写了一版 `service/host.test.mbt`，里面同时负责起 `service`、等 browser connected，再去跑 `test_query/test_exec`。这版很快就被用户指出方向不对：一方面，测试不该去碰默认浏览器，把当前手工开的页面一起拖进 `session_busy`；另一方面，更关键的是，既然测试就固定跑在专用端口和专用 state dir 上，中间根本没必要在一组用例里反复 `stop/start meta`，不关 `meta` 的情况下前面那些 session 和垃圾页问题本来就会消掉大半。顺着这个提醒，后面又把职责重新掰了一轮：`host.test.mbt` 不再自己碰生命周期，它应该只假设“外部已经有一个 running 的 host + browser 连接”，测试里只负责断言；而真正准备环境、确认 browser connected 这层事，则应该下放到一个单独的外层脚本去做。

这条职责重分之后，中间我又踩回了另一个已经在 `build-native.ps1` 上踩过的老坑：测试入口脚本里开始重新写构建和 VS 环境导入。最开始那版 `scripts/test-host.ps1` 自己去导 Visual Studio 开发环境、自己跑 `moon test --target native ...`，甚至一度把一整套类似 `build-native.ps1` 的 native 构建/运行壳又抄了一遍。用户这时候直接把问题点穿了：前面本来就已经有 `build-native.ps1` 这条唯一的 native 构建入口，如果测试脚本里再重写一套 build 流程，本质上就是把之前好不容易收成单一路径的东西又岔开，而且 agent 也会因为观测性差不断在同一类坑上来回踩。后面顺着这个提醒，又把职责进一步压回去：`build-native.ps1` 继续负责所有 native 构建和测试运行，`test-host.ps1` 只允许做环境编排，不再自己抄一遍 native build/test 逻辑。

围绕“到底要不要让 MoonBit 测试自己走 CLI”这件事，这一段中间也来回掰得很细。最开始我还试着让 `host.test.mbt` 里用 `run_meta(["add_project", ...])` 这种方式直接测全流程，但用户马上指出，这样虽然名义上还是 MoonBit 测试，实际心智模型却更像 shell 测试脚本，写起来和看起来都很奇怪。顺着这个提醒，后面就把 `host.test.mbt` 里那层 `run_meta(...)` 全部换成了更直接的控制口 client helper：当前测试进程会先通过 `read_service_port()` 拿到测试 state dir 下当前 host service 的端口，再直接调用 `call_at(port, cmd, arg)` 去打 `add_project/run_project/stop_instance/remove_project/test_query/test_exec` 这些统一命令入口。这里后面和用户也重新确认了一点：从概念上看，这仍然是在走 meta 的统一命令语义层，但至少已经不再经过 shell 文本壳和子进程参数拼接那一层，速度和稳定性都比“MoonBit 测试里继续起 CLI 子进程”好很多，而且也更符合当前仓库一直强调的 UI/CLI 操作同源原则。到这里，这条测试链的内层调用路径至少已经重新站在了一个比最开始更合理的位置上：测试本体走统一命令语义，但不再走 shell。

沿着这条线继续往下接以后，`service/app.mbt` 和 `service/bridge.mbt` 这边也补了一批测试专用但仍然走主路径的最小能力。host 页面现在给 `host-root`、`projects-section`、`instances-section`、project row、instance row 以及对应的 `Run/Remove/Stop` 按钮都补了稳定的 `data-testid`；`instance` 行里也正式长出了 `Stop` 按钮，这样 UI 和 CLI 两边终于能对上同一条 `stop_instance` 动作，不再出现 CLI 有动作、UI 没入口的测试盲区。与此同时，`bridge.mbt` 里也补上了 service 到 browser 的 request/response 通路：service 侧现在会为每个 browser request 分配 `request_id`，在 `pending` map 里挂一条队列，browser 通过现有 `bridge:request/bridge:response` 协议回结果；`app.mbt` 则把这层能力接成了 `test_query` 和 `test_exec` 两个命令入口，内部继续走统一的 `run_app(runtime, cmd, arg)` 主路径。这样之后，`host.test.mbt` 已经能真正对着真实 browser 页面做结构化断言和结构化点击，而不是只看 CLI 返回的字符串。所有这些改动中间每一步源码侧 `moon test` 都继续保持 `59 passed`，而原来那批 native lifecycle 测试也没有因为 host 页面和 bridge 通路变化直接炸掉。

真正把 `host` 测试本体和入口脚本都拉起来以后，后面问题就不再是“能不能调用”，而是“职责到底有没有收对”。最开始我一度把 `scripts/test-host.ps1` 写成了一个会先 build service、再起 service、再等 browser connected、然后直接在脚本里自己跑 `moon test` 的壳，但用户又继续把边界压得更短：既然现成的 `build-native.ps1` 已经能直接跑 `-Test -TestPackage service -TestFile host.test.mbt -NoParallelize`，那 `test-host.ps1` 最短的版本就不该自己碰 `moon test`，更不该重新导 VS 环境，而应该只是“确认/复用常驻 meta + 等 browser connected + 调现成 build-native 跑 host.test”。这里后面就按这个方向把 `scripts/test-host.ps1` 又重写了一轮：所有原本手抄的 native 构建和 `moon test` 逻辑全部删掉，脚本只保留构建 service 包、复用或启动测试 state dir 下的 `service.exe`、轮询 `status` 等 browser connected，然后最后直接调 `scripts/build-native.ps1` 去跑 `host.test.mbt`。这样之后，测试本体、环境编排和 native build 这三层的职责总算重新分开了，不再是所有东西都混在一个脚本里各写一半。

不过这一段收法虽然方向上已经重新对了，过程里还是暴露出了一个非常明显的问题：`scripts/test-host.ps1` 的可观测性一直写得很差，甚至一度在实际调用里出现了“脚本执行但外面看到 `(no output)`”这种完全没法判断卡在哪一步的状态。这里用户最后直接点出来，这和前面写 `build-native.ps1` 时已经踩过的坑其实是同一类问题：如果脚本不按统一方式包装阶段、不把子步骤输出原样透出来，agent 后面就只能靠猜，而不是靠日志来定位问题。最后这段没有来得及把 `test-host.ps1` 完全收成像 `build-native.ps1` 那样已经验证过的输出风格，当前仓库里留下的状态也因此有点尴尬：host 测试主路径、service/browser query 通路和 `data-testid` 这些底座已经接上了，独立 `test-host.ps1` 入口和 `host.test.mbt` 也都在仓库里，但这条测试链本身还没有完全跑通，而且入口脚本的输出包装还不够稳，继续往下做之前必须先把“脚本到底卡在哪一步”这件事重新收清楚，不然后面还会继续在同一类黑箱问题上打转。

后面这一轮没有顺着那版 `test-host.ps1` 继续往里补，而是先把“没输出”这件事重新按真实执行链拆开看。先直接跑了一遍现有脚本，再把 `build-native.ps1 -Package service` 单独拿出来对着看，结果很快就把问题从“脚本可能黑箱卡住”收窄成了更具体的事实：它并不是完全没输出，而是在 `host.test.mbt` 真正执行那一段稳定打满了 `build-native.ps1` 里给 native test 设的 `5000ms` 总超时。也就是说，前面那句“(no output)”更像是因为子进程输出被 `build-native.ps1` 统一攒到结束后才打印，所以一旦测试本体卡住，外面只能看到阶段开始和最后的超时，而看不到中间到底停在哪一步；真正首先要收的不是把 timeout 放宽，而是把 host 测试主路径里那些没有同步点、只能靠轮询傻等的地方钉出来。

顺着这条线继续往代码里压以后，接下来先踩到的是一处更实在的脚本冲突。`test-host.ps1` 这边最开始是先确认测试 state dir 下已经有一个 running 的 host service 和 browser 连接，然后再调 `build-native.ps1 -Test -TestPackage service -TestFile host.test.mbt -NoParallelize` 去跑测试；但 `build-native.ps1` 自己在这条路径里默认还会先做 `cleanup before build` 和 `cleanup before test`，里面又会去停 `service` 包当前正在跑的 native 二进制并清测试状态。这样之后，脚本实际上就变成了“刚把 host 测试依赖的常驻 service/browser 环境准备好，下一步又顺手把它自己清掉”。这里后面先按最小补丁收了一刀：给 `build-native.ps1` 增加了一个很窄的 `-SkipCleanup`，只负责跳过这两段既有 cleanup；`test-host.ps1` 则只在跑 `host.test.mbt` 这条路径上显式带这个 flag。改完以后重新跑，日志里已经能稳定看到 `skip cleanup before build` 和 `skip cleanup before test`，说明这层“脚本自己杀自己准备好的环境”的问题至少已经被拿掉了。

脚本互相清环境这层拿掉以后，后面又顺手把这两个 PowerShell 入口里已经很明显的重复壳先压平了一轮。这里没有去搞 `.psm1` 模块或者更重的抽象，只新增了一份很薄的 `scripts/common.ps1`，把两个脚本里本来就完全重复的计时和阶段输出 helper 收进去，再把 `test-host.ps1` 里两处“调另一个脚本并检查退出码”的模板合成一个本地 helper，同时把 `build-native.ps1` 里三段 cleanup 模板收成单独的局部函数。这一轮收完以后先重新跑了 `build-native.ps1 -Package service` 和 `test-host.ps1`，前者仍然正常，后者虽然还没跑通，但报错位置和输出都没有因为这轮脚本整理变得更糊，说明这一步至少没有把现有问题盖住。

真正把 host 测试卡住的实现原因继续往前钉以后，这一轮后面最终还是落回了 service 和 browser 之间缺同步点这件事上。当前 `host.test.mbt` 里那些 `wait_selector/wait_text/wait_instances_text` 本质上都在做同一件事：命令执行完以后，因为并不知道浏览器端是否已经把这次 UI 变更真正应用完，所以测试只能一遍遍经 `test_query` 回浏览器去问。这里后面没有继续在测试里再加 wait，而是直接把同步点补回主路径：`service/bridge.mbt` 里原来 browser request 会直接抢 websocket 发消息，而 UI batch 则走 `live_batches` 后台发送，两条路径彼此没有顺序保证；这次把 browser request 也改成走 `live_batches`，再额外补了一个很薄的 `sync_browser`，让 service 在 `add_project/remove_project/run_project/stop_instance` 和 `test_exec` 这些会改 UI 的动作之后，先 `try_flush()`，再发一条最小 `sync` request，等 browser 按同一条发送顺序把前面的 batch 应用完以后再回结果。浏览器侧 `src/bridge.js` 也相应补了一条最小的 `sync` action，只负责回一个 `{ ok: true }`，不再让 host 测试自己在外层傻等一轮“也许已经刷出来了”的 DOM 变化。同步点这层改完以后，先重新跑了源码侧 `moon test`，当前结果还是 `Total tests: 59, passed: 59, failed: 0.`，说明这刀至少没有把现有源码测试链打坏。

不过这轮最后并没有把 `test-host.ps1` 真正跑绿，因为把 cleanup 冲突和同步点都先收掉之后，前面被遮住的另一层构建冲突又露出来了：`test-host.ps1` 现在的主流程里仍然会先准备或复用一份正在运行的 `service.exe`，然后再去调 `build-native.ps1 -Package service` 做构建，而 Windows 这边 native build 默认就是要重新链接同一路径下的 `_build/native/debug/build/service/service.exe`。于是当前最新一轮实际跑出来的阻塞点就不再是 `(no output)` 或者单纯的 host test timeout，而是链接阶段直接打出 `LNK1104`，说明构建动作在碰正在运行的同名二进制。这件事也把边界重新压得更准了一层：现在 host 测试最先该继续收的，不再是继续往测试体里加观察日志或者改 timeout，而是把“host 测试依赖一份常驻 service”和“`build-native.ps1` 默认会重建 `service.exe`”这两个前提怎么并存讲清楚。到这里，今天下午这轮也就再次收住了：脚本黑箱问题已经被重新钉回真实 timeout；会自清环境的 cleanup 冲突已经用 `SkipCleanup` 收掉；service/browser 的最小同步点已经接回主路径并通过了源码侧测试；而当前剩下最靠前、也最值得下一轮继续收的阻塞点，则已经明确变成了 host 测试入口和 `build-native.ps1` 默认构建行为之间的二进制文件锁冲突。

后面这一轮继续往下压时，用户把方向又拧回了一个更直接的判断：与其继续在 `pwsh` 脚本里一层层包装 stop、build、start、wait，不如先承认“脚本里显式再起一层 `powershell -File ...` 本身就是很多麻烦的根源”。顺着这个提醒，后面先把 `scripts/test-host.ps1` 压回成和 `test-native.ps1` 一样的薄壳，只保留 `build-native.ps1 -Package service -Test -TestPackage service -TestFile host.test.mbt -NoParallelize` 这一条固定调用，不再自己编排生命周期，也不再在脚本里显式嵌套另一层 pwsh。与此同时，`host.test.mbt` 这边则重新接管测试自己的 service 生命周期：测试开始前自己 `stop`，然后 `start --silent`，中间轮询 `status` 等 browser connected，最后再自己 `stop`。这里的想法不是把浏览器生命周期测轻，而是反过来把真正的完整流程收回测试本体里，让 `build-native.ps1` 只负责构建和执行，不再替测试猜什么时候该起停服务。

把入口重新收回 `build-native.ps1` 以后，接下来最先做的不是继续碰逻辑，而是继续把 host 测试从“黑箱超时”往“真实失败”上推。这里先在 `service/host.test.mbt` 里给关键阶段补了一串很薄的时间日志：从 `start host service`、`wait browser connected`、第一次 `query host root`，到后面的 `cli add/run/stop/remove` 和 `ui run/stop/remove`，每一段都打印成 `[host-test] +Nms ...`。`build-native.ps1` 这边也顺手补了一刀：如果 native test 进程超时，会先把当前已经读到的 stdout/stderr 直接打出来，再抛 timeout，不再像前面那样只在最后丢一条统一异常。这样之后，host 测试终于不再是“跑了一会儿然后直接超时”，而是能看出真正停在哪个阶段。

这串时间点一开始很快就把一个误判纠正掉了。最开始直觉上还以为大头可能在 `start --silent` 之后等浏览器连上的阶段，或者在第一次 `test_query` 进桥接那一步，但真正打出时间以后，前半段其实比预想快得多：很多轮里 `start host service` 到 `query host root` 已经能收在几百毫秒到一秒多，后面的 `cli add host-demo -> cli run host-demo -> cli stop host-demo instance -> cli remove host-demo` 也都在很短时间里完成。真正出问题的不是“前半段太慢”，而是 `cli remove host-demo` 返回成功以后，接着那两次“项目行和实例行现在应该已经是 null”的查询仍然拿到了旧 DOM 节点。到这里，这条测试链就第一次从“总超时”真正落到了一个可复现的真实失败：当前 `remove_project` 之后，浏览器里的 `project-row-host-demo` 还留着。

顺着这个真实失败点往前推以后，后面又把 service/browser 同步这层再往硬里收了一轮。前面虽然已经给 CLI 动作和 `test_exec` 接过最小 `sync`，但用户马上提醒，这个测试的全部意义就是走完整浏览器生命周期，不该为了过时间去把它改轻。于是后面这轮就不再试图减少真实浏览器链路，而是继续把同步语义收得更对：先把 UI callback 这条路径后面的 browser sync 也接上，避免 CLI 动作返回前会等 sync、UI 点击却只 flush 不 sync；接着又把 `host.test.mbt` 自己包成“即使中间断言失败，也先尝试 stop host service 再把失败抛出去”的结构，这样之后测试就不会因为中途炸掉而把 service 留在后台，最后再被外层总 timeout 盖掉。到这里，host 测试的输出就终于开始像一个正常的黑盒生命周期测试了：执行到哪一步、失败点是哪条断言、失败前有没有执行 stop，都能直接从输出里看见。

不过这一轮真正值得留下来的结论，还是“问题已经不是超时，而是 DOM 删除路径真的不对”。围绕这个点，中间先顺着 `service/app.mbt` 去看 `remove_project` 本身，确认 service 侧的 `projects` 和 `instances` 状态其实已经按预期删掉；接着又去翻 `src/dom.mbt` 里的 `Dyn`、`h_map_dyn` 和清理路径，补过一刀“当整个 `Dyn` 子树被外层删掉时，也要显式 emit `Remove(old.id)`，不能只做 `recursive_cleanup`”，想先排掉“逻辑状态删了，但 DOM 没收到 remove 命令”这种路径；同时浏览器侧 `resetManagedDom()` 也顺手加硬了一层，重连时除了当前 `nodes` map 里跟踪的节点，也把 `body` 里除了 `#app-info` 和 script 之外的残留节点一并扫掉，避免前面排查过程中遗留的孤儿 DOM 干扰新的一轮 run。再往后还继续把几层原来会被吞掉的错误输出都打了开来，例如 `try_flush()` 里的 flush 错误和 browser sync 失败都不再静默吞掉，而是至少先打印出来。

可即便把这些黑箱都打开以后，到下午最后收住时，结论还是落在同一个点上：`remove_project` 返回成功，后面的 browser query 也已经能稳定返回，但 `project-row-host-demo` 这条 DOM 节点仍然会留着，说明当前真正没收透的不是脚本、不是 timeout，也不是“浏览器是不是连上了”，而是 host 列表项从状态里删掉以后，DOM 差分/删除这条主路径本身还存在问题。这一轮最后没有继续往外层脚本上绕，而是停在一个比前面清楚得多的位置上：现在 host 测试已经从模糊 timeout 收成了稳定可复现的真实失败，下一轮该继续查的对象也已经很明确，就是 `src/dom.mbt` 里列表项移除相关的差分和删除路径，而不是再去折腾 `pwsh` 壳、构建入口或者浏览器等待方式。

## 03-27 晚上

晚上这一轮没有急着继续往 host timeout 外层壳上绕，而是先按用户的提醒把 `../IntentDoc/dev/ui.js` 重新对了一遍，专门看它原本的 keyed 列表更新和删除是怎么做的。这里回头一对，问题一下就更具体了：`ui.js` 那套 `h.map` 真正关键的不是 API 名字，而是列表层自己会拿 old/new 真实节点集合去做 `moddom(...)`，把不在新集合里的节点直接 remove 掉；而我们现在 `src/dom.mbt` 里的 `h_map_dyn` 只是缓存了一层 `Child`，真正删除还挂在外面的 `Dyn` 全量清理上。这个差别一开始搬 DOM 的时候没有立刻炸出来，是因为“能渲出来、能更新、能点”这些场景都还能糊过去，到了 `remove_project` 这种要求旧身份必须精确回收的路径才第一次彻底暴露。顺着这个判断，后面没有先去拍脑袋改实现，而是先把测试补到了能真正约束 keyed 语义的程度，避免后面再用“全删全建但碰巧过当前断言”的假修法把问题糊过去。

测试这轮先动的是 `test/dom.test.mbt`。最开始现有用例虽然已经覆盖了 `h_map` 的基本行为，但还停在“会重跑、会出命令”这种宽断言上，不足以卡住这次 host 列表删除问题。这里后面一口气补了几条更硬的 keyed 语义测试：删除一项时只能 remove 消失项，保留项不能跟着 remove 或 recreate；重排时保留项只能换顺序，不能重建；新增一项时 render 函数只允许为新项多执行一次；duplicate 值场景下删一个只能删对应那一份，不能把另一份一起带走；保留项的 listener 也必须维持同一个 callback 身份，而且点击时还能拿到更新后的 index。刚把这些用例补进去以后，`moon test` 立刻就把 `h_map_dyn` 当前的缺口摊平了：删除、重排、新增 render 次数、duplicate 复用和 listener 身份都先后打红。这里后面又顺手把几条旧测试里那些过度依赖“全删全建命令顺序”的断言一起收短，改成真正只锁语义，不再要求某个 `Remove` 必须恰好出现在固定下标上。到这里，这条 DOM 线终于不再只是靠 `host.test.mbt` 间接暴露，而是有了一组直接压在 `src/dom.mbt` 上的本地回归。

真正改实现时，这一轮中间还犯了一次很直接的错。最开始我顺着“列表层自己管理节点身份”的思路，试图在 `Child` 里硬塞一个新的 `Managed` 变体，把 `h_map_dyn` 直接改成一层自己操纵子树的特殊节点。这刀刚下去用户就直接点出来，这完全是在引入新概念，和前面已经反复强调的“不要平白再造一层 runtime 语义”是正冲突的。这里后面也立刻把这层全撤掉，重新退回现有 `Child`/`Dyn` 语义，只在已有结构里找最小改法。真正留下来的实现收口也因此短了很多：一方面给 `h_map_dyn` 里的新 entry 做了 `freeze_child(...)`，让每个 keyed 项第一次 render 以后对应的 child 结果被缓存下来，后面保留项复用时不再额外执行 render；另一方面把 `Dyn` 更新从“每次先全 remove 再插新子树”改成了先生成这轮新节点集合，再按节点 `id` 只 remove 真正消失的旧节点，保留项继续复用并通过原有 `InsertBefore` 去重排。这里没有再额外造新协议，只是把删除语义从“整块全删”收成了“按身份差分删旧节点”，正好和前面补进去的 keyed 测试一一对上。实现收完以后重新跑源码侧测试，当前结果回到了 `Total tests: 65, passed: 65, failed: 0.`，说明这刀至少已经把 DOM 这条删除主路径重新压回了可控状态。

DOM 这层重新站稳以后，后面又把原来两个 native 测试入口顺手收了一轮。最开始根目录的 `test-native.ps1` 还只是一个最薄的转发壳，默认直接把整个 `service` 包 native 测试全跑了；用户后面明确要求把这条入口也收进 `scripts`，而且默认只跑 `service.test.mbt`。这里最后按最小补丁落成了两步：先新增一份真正的 `scripts/test-native.ps1`，里面只保留 `build-native.ps1 -Package service -Test -TestPackage service -TestFile service.test.mbt` 这一条固定调用；再把根目录 `test-native.ps1` 改成单纯转调这个新脚本。与此同时，`scripts/test-host.ps1` 则继续只保留 `host.test.mbt` 这一条。改完以后重新跑了 `./scripts/test-native.ps1`，当前结果是 `Total tests: 11, passed: 11, failed: 0.`；而 `./scripts/test-host.ps1` 这边虽然还没绿，但已经不再报最开始那个 `project-row-host-demo` 删除残留了。这一段的实际结论也因此比较清楚：native 默认入口已经从“整包全跑”收成了稳定的 `service.test.mbt` 单文件路径，而 host 那条链剩下的阻塞点已经不再是 DOM 删除。

顺着这个结果继续往下看以后，后面的 host 问题就重新集中到了 `test_exec(click)` 这条 browser request 上。最开始这条测试还保持着比较重的 browser 访问习惯：`host.test.mbt` 一路在 `cli add/run/stop/remove host-demo` 之后反复用 `test_query` 去查 UI 行、按钮和实例状态，于是看起来每一步都慢，而且最后 `ui run host-ui` 还稳定打出 `ServiceError("browser request timed out")`。用户这时候直接把方向压回了更本质的判断：对于这种 host 测试，service 本地状态断言本来就应该接近瞬时，只有真正涉及 UI 布局的细节才值得统一去浏览器查一次。后面也按这个提醒把 `service/host.test.mbt` 重写了一轮：中间 `host-demo` 那段改成只断言 `list_projects/list_instances` 这些 service 本地结果，不再每做一步就立刻打一次 `test_query`；UI 访问收缩成最后一段集中 `query_ui`，只统一检查 `host-root/projects-section/instances-section` 这些布局关系，以及 `host-ui` 相关 row、按钮和 instance 行的可见性与位置。这样收完以后重新跑 `./scripts/test-host.ps1`，前半段时间点立刻明显短了很多，`cli add/run/stop/remove host-demo` 和 `cli add host-ui` 基本都重新落回了几十毫秒量级，说明前面那种“每步都很慢”的大头确实主要是测试自己在来回过度查询浏览器，而不是 service 本地动作本身就慢。

不过把测试体压短以后，host 这条链并没有因此直接跑绿，反而把剩下的问题显得更纯了一层。当前 `./scripts/test-host.ps1` 的失败已经稳定收敛成一件事：浏览器连得上，`host-demo` 整条 CLI 路径也能跑通，删除后的本地状态和后续 UI 主查询都不再报旧 DOM 残留；真正剩下没收透的只是在 `ui run host-ui` 那一行 `host_exec(exec_click_arg("[data-testid='project-run-host-ui']"))` 内部打出的 `ServiceError("browser request timed out")`。这一轮中间为了先排一些明显的旁路，还顺手删掉了 `service/app.mbt` 里残留的 `[batch]` 调试输出，避免污染 native 测试输出；同时把 `service/bridge.mbt` 里原来事件回调后那次同步阻塞的 `sync_browser_if_connected(runtime)` 去掉，防止 service 在处理浏览器事件时又自己把 websocket 消息循环堵住；浏览器 request 超时预算也先临时放宽了一轮，确认它不是单纯因为 2 秒预算太小才炸。可即便这些外层都先收过以后，最后的 host 失败仍然稳定停在同一个位置。到这里，这个晚上的工作就也重新收住了：DOM keyed 删除语义已经有本地测试锁住并且源码侧全部通过；native 默认测试入口已经收进 `scripts` 并缩成只跑 `service.test.mbt`；host 测试本体也已经按“本地断言优先、UI 最后集中查”的方向明显压短；而当前真正剩下最靠前的问题，则已经不是“host 测试整体太慢”或者“旧 DOM 没删掉”，而是 `test_exec(click)` 这条 browser request/response 链本身还存在 timeout，下一轮要继续查的对象也因此重新缩到了 `service/app.mbt`、`service/bridge.mbt` 和 `src/bridge.js` 这三处，而不是再回头大改测试结构。

晚上后半段又顺着“CLI 这边能不能先建一条高速长连接，再拿它去压 host 测试”这条线继续往下掰了一轮。用户当时的要求很直接：重点是把反复走短连接命令调用的往返开销拿掉，而且这条能力不该只是测试专用，最好本身就能长成 `meta repl` 这种常驻长连接 CLI。这里我一开始先试了一个过渡版，想用持久化的 `@http.Client` 先把“同一进程里连续发多条命令”这层收起来，这样至少能把每步重新建 client 的壳先拿掉。代码上这版很快就能跑：`service/cli.mbt` 里先加了 `repl` 命令，`service/service.test.mbt` 也补了一个最小回归，证明同一条 client 上连续 `list_projects -> add_project -> list_projects` 是通的，源码侧和 native 默认入口都重新回到了绿色。可用户马上把边界压得更准：这条 HTTP 长连接最多只是“少建几次 client”，并没有把真正想砍掉的同步往返砍掉；而且如果现在把这版先留进仓库，后面大概率就会一直留着，最后变成又一条平行入口。这一段后面没有继续硬保过渡版，而是直接承认这条质疑是对的，决定把 HTTP `repl` 整个收回，只留 ws 路线。

决定回到 ws 以后，这轮最大的变化不是立刻去改实现，而是先把调试方法换掉了。用户这边把问题点得很直接：前面一遇到握手或 host 测试问题，我这边总是在跑一整个 `service.test.mbt`、`host.test.mbt` 甚至 `test-host.ps1`，每次都要等一大轮环境编排和构建，信息却还是糊的。顺着这个提醒，后面先新增了一份很小的 `service/repl.test.mbt`，只专门盯 `repl` 这条 ws 链路本身：一条测 `repl:hello -> repl:hello_ack`，一条测同一条连接上连续发多条命令，一条测第二个 live client 会被 `repl_busy` 拒掉。实现这一步时中间还犯了几个很典型、但都不大的错：第一次测试闭包照着直觉写成了不被 MoonBit 当前语法接受的 async 匿名函数，后来回头对了一遍依赖和仓库里现成的 `@async.with_task_group` 用法，才把闭包写法改回当前能编、也和现有风格一致的形式；另外测试 helper 名字也一度和 CLI 侧撞名，后来一起顺手收开了。把这些小语法坑收掉以后，这条小测试很快就稳定下来：`./scripts/build-native.ps1 -Package service -Test -TestPackage service -TestFile repl.test.mbt` 现在能直接在几秒内跑完，三条 ws `repl` 回归都已经是绿的。这里也顺手把前面那个“ws 路线是不是本身就不通”的疑点真正钉死了：问题并不是 ws API 本身有坑，而是前一轮把 `repl` 混在 browser 那条 websocket 处理路径里，再拿大测试去看，导致握手失败时根本看不清到底卡在哪个阶段。

把 `repl.test.mbt` 这条小链路站稳以后，后面又顺着同一条“只动最小层”把 `service/host.test.mbt` 里的命令传输从短连接 HTTP 收回到了单条 `repl` ws 上。这一轮刻意没有去碰测试里的动作顺序和断言内容，只把反复调用 `call_at(...)` 的那层改成 `host_repl_connect()` + `host_call_repl(...)`，也就是测试开始先连一次 `ws://127.0.0.1:<port>/_meta/repl`，后面 `add_project/run_project/list_projects/list_instances/test_query/test_exec` 这批命令都走同一条 ws 连接。这里中间也有一轮小收回：第一次写 `host_call_repl(...)` 时，为了省几行又把 JSON request 直接挤在一行里，MoonBit 很快就把对象字面量和 `to_json()` 那层解析打歪了；后面把 `request_id` 和 `request` 拆成两步以后，这层才重新编过。到这里，`repl.test.mbt` 继续是绿的，说明 ws `repl` 本身没有被 host 这边的新改动打坏。

不过这一轮真正值得记下来的不是“host 测试已经因为 ws 变快了”，而恰恰是它还没有来得及变快，就先把更前面的阻塞点暴露得更清楚了。最开始用户自己跑了一次 `./scripts/test-host.ps1`，结果很快在 `start_host_service()` 里那句硬锁 `started http://localhost:8080` 的断言上炸掉；这件事很快就说明，当前测试里那条断言太脆，实际绑定端口并不稳定，而且 service 静默启动时输出文本本来就不该被拿来当主语义。这里后面先按最小补丁收了一刀：帮助文本里那几条手写的 host app 命令直接删掉，不再让 `service/cli.mbt` 自己硬编码 `list_projects/add_project/remove_project/list_instances/run_project/stop_instance` 这批本来应该由 host app 模型自己产出的动作说明；与此同时，`start_host_service()` 这边也收成更窄的断言，只确认确实启动了 `http://localhost:` 且测试 state dir 里已经能读到实际端口，不再强行锁死 `8080` 这句文本。把这两个脆弱点拿掉以后重新跑，`test-host.ps1` 的失败位置果然继续往后推了一步，但也因此第一次明确落到了一个比“输出不对”更真实的事实：当前阻塞点不是命令调用慢，也不是 `repl` 连不上，而是 browser 根本没有连进来，日志稳定停在 `browser not connected: running http://localhost:8081/browser: waiting`。用户随后又顺手把另一个更实在的观察压了出来：当前 service 的单例性质本来就让很多调试行为不太好观察，如果测试刚起起来的只是一个静默 service，而根本没有真实浏览器页连上，那当然不会出现任何 host 页面。这也把当前这轮最后的收口压得更准了一层：现在仓库里真正已经站稳的，是一条可工作的 ws `meta repl` 主路径和一组小而快的 `repl.test.mbt` 回归；`host.test.mbt` 也已经把命令传输切到同一条 ws 连接上了，但这条大测试还没有开始体现 CLI 侧的提速，因为它目前更靠前的阻塞点已经重新变成了 browser connected 这层环境问题。换句话说，今晚这一轮到最后真正收住的，不是“host 测试已经被 ws 提速了”，而是“现在终于可以不再碰 `repl` 这条线，下一步该单独去查 browser 为什么没有连上”，这比前面反复在大测试里同时怀疑 CLI、IPC、browser 和帮助文本都更清楚，也更容易继续往下收。

这一段后面又顺手把 `meta start` 的自动开页时机收了一刀。用户指出当前最烦人的一个交互问题是：经常已经有一个旧页面在后台不断重试连接 service，`meta start` 却没等它回连就又马上开一个新页，这个新页本身没有价值，还很容易把 session 顶到 busy。这里最后没有去改 `--silent` 行为，只在非静默 `start` 和“已经 running 再次 `start`”这两条路径上加了一小段等待：`service/cli.mbt` 现在会在自动 `open_browser(...)` 前先轮询一小段时间，看当前 port 上的 `status` 是否已经变成 `browser: connected`；如果旧页已经自己连回来了，就不再弹新页。改完以后重新跑了 `moon test` 和 `./scripts/test-native.ps1`，当前结果都还是绿的，说明这刀至少没有把 service 现有主路径打坏。

真正把 host 测试这条线继续往下收时，后面方向又被用户拉回了一个更实在的标准：当前这组 host 探测测试本身可以用来定位基础链路问题，但没必要再维持那种又长又混、还要靠 `-NoParallelize` 硬压的整文件大测试。顺着这个提醒，我这边先试着把前面拆开的 host 小测试重新并回一个 `service/host.test.mbt`，结果很快就把问题打得很清楚：单独拆成 `host.test.mbt/host-batch.test.mbt/host-query.test.mbt/host-exec.test.mbt` 这四个文件时，每个 `-TestFile` 都会单独起一个 native test executable，四条链路都能稳定通过；但一旦把它们重新合回同一个 `host.test.mbt`，`service.internal_test.exe` 就会在运行期稳定直接炸成 `0xc0000409`，既不是普通断言失败，也不是脚本并行把 `_build` 撞坏，而是“同一份 native test binary 里连续跑多条 host 探测测试”这件事本身就不稳。这里后面没有继续在单文件上死拗，而是按当前仓库最实际的需求回到了一个中间形态：真正的共享逻辑全部收进了新补的 `service/host-support.mbt`，里面统一放 `with_host_server(...)`、browser hello、repl request、batch/request 断言和 browser mock response 这些 support；`service/host.test.mbt` 只保留最基础的“browser hello 会拿到初始 host batch”；其余三条 `add_project` 推 batch、`test_query` 代理、`test_exec` 代理则各自回到 `host-batch.test.mbt/host-query.test.mbt/host-exec.test.mbt` 这种极薄的 wrapper 文件里。这样之后，结构上其实还是“一组 host 基础探测测试共用一份 support”，只是物理上继续借四个单独 test file 来拿运行时隔离，不再强行要求它们在同一个 native 进程里串着跑。

围绕 `scripts/test-host.ps1` 这层，最后也顺手把前面那次“去掉 `-NoParallelize` 以后是不是还要继续只跑一个文件”重新收了一遍。用户这边明确说了，`-NoParallelize` 这个 flag 不该继续留着，因为如果测试非得靠它才能站住，往往说明测试逻辑本身就有问题。这里最后的收口也和上面那层 support/wrapper 结构对上了：`scripts/test-host.ps1` 现在不再带 `-NoParallelize`，而是顺序调用四次 `scripts/build-native.ps1 -Package service -Test -TestPackage service -TestFile ...`，分别跑 `host.test.mbt/host-batch.test.mbt/host-query.test.mbt/host-exec.test.mbt`。这样做的目的不是为了把文件拆散看着舒服，而是明确承认当前 host 这组测试在“每个文件独立一个 test executable”的边界内是稳定的，而不再拿 `-NoParallelize` 去硬保一条已经被证明不稳的单文件运行方式。全部收完以后重新跑了 `./scripts/test-host.ps1`，当前四条 host 基础探测都已经能稳定过：初始 batch、`add_project` 推 batch、`test_query` 代理和 `test_exec` 代理这四块都已经重新站稳了。到这里，这一轮最后真正留下来的状态也比较清楚：host 的完整生命周期测试并没有被重新做回去，但当前仓库里已经有了一组可稳定运行、可独立定位问题的 host 基础链路测试；`repl`、browser hello、batch 推送和 query/exec 代理这些地基层都已经能单独证明是通的；而那个“为什么把它们全塞回一个 `host.test.mbt` 后 native test binary 会直接崩”的问题，也因此被单独隔离成了后续再查的运行时问题，不再阻塞这套基础探测测试继续使用。

这一晚后面又临时插进来一条更靠前的基础设施决策：既然后面的 managed app 很可能要靠 wasm runtime 托管，可以思考一下引入哪个 wasm vm。中间先把 Wasmtime、wasm3 和 WAMR 这几类路线粗对了一遍，最后收口还是偏向 WAMR：它和当前仓库已经存在的 MoonBit native + `service/native-stub` 这条宿主形态更贴。这里真正看重的点主要有三条：一是 WAMR 本来就是偏嵌入式和宿主集成取向，C API 比较直接，比较适合后面在 `service` 里把每个 managed app 当成一个受控 wasm instance 去托管；二是它比 Wasmtime 这类更完整的平台型 runtime 轻一些，当前阶段更像是在补 host 层，而不是一上来就接整套通用 WASI 平台；三是 wasm3 虽然更小，但维护状态和长期依赖信心都弱一些，不适合直接拿来做后面主路径上的宿主 runtime。确定方向以后，后面又围着 “直接 vendor 源码” 和 “submodule” 来回掰了一轮，最后用户把标准压得很具体：不是自己再做一份二次整理过的 vendor 仓库，也不是跟着上游开发分支走，而是直接认 WAMR 官方正式发布版本，用对应 release/tag 的 commit 固定成 submodule。按这个边界收以后，用户这边已经实际把 WAMR submodule 加进了当前仓库。目前已检查 submodule，实际锁到 WAMR-2.4.4/8c18e3f，配置正常。

WAMR 这条线先按这里收住以后，后面又回到了 host 测试本身。最开始我这边还沿着前一轮的思路，保留了一套 `host-support + 四个薄 wrapper` 的分法，想靠 `host.test.mbt/host-batch.test.mbt/host-query.test.mbt/host-exec.test.mbt` 这几条小测试把 browser hello、batch 推送、`test_query` 和 `test_exec` 逐条锁住，同时让 `scripts/test-host.ps1` 顺序跑四个 `-TestFile`，这样每个文件都是独立的 native test executable，至少在运行期是稳的。可用户后面很快把问题点穿了：这套分法里真正麻烦的不是“文件多”，而是我为了复用测试 helper，先补出来的 `service/host-support.mbt` 是普通 `.mbt`，它会直接跟着 `service` 包一起编进生产编译单元。也就是说，前面那套“拆成四个文件就稳、合回一个文件就炸”的现象，并不能直接说明单文件 host 测试天然不行，更可能只是因为我把测试 support 放错了边界，让一堆本来只该属于测试的 helper 也一起参与了正式包的编译。

顺着这个提醒，后面没有继续在那套 support 分法上补洞，而是直接另起炉灶写了一份完整长测试，先单独命名成 `host-flow.test.mbt`，把 browser 端和 repl 端两头的 ws helper 全部内联进去，一口气在同一个 native test executable 里顺序跑 browser `bridge:hello`、初始 host batch、`repl add_project`、browser 收新 batch、`repl test_query`、browser 回 query response、`repl test_exec`、browser 回 exec + sync 这整条协议流。结果这版反而一下就过了，而且日志也很清楚：`[host-flow] begin -> initial batch -> add project -> query ui -> exec click -> done` 全部走完，最后 `1 passed`。这件事把边界重新压得比前面清楚得多：前面那种“不稳定”并不是什么“host 长测试天然不能合并”，而更像是我之前那套 `host-support` 分法把测试和生产包的边界搅脏了。

 确认这一点以后，这里最后没有再保留 `host-support`、也没有继续留四个 wrapper 文件，而是直接把它们整套删掉，只保留一个重新命名回 `service/host.test.mbt` 的单文件长测试。当前这份 `host.test.mbt` 自己就内联了所有 helper，测试本身直接在同一个进程里同时扮演 browser client 和 repl client：先以 browser 身份走 `bridge:hello`，确认 service 会下发初始 host batch；再以 repl 身份走 `repl:hello`，后面连续发 `add_project/test_query/test_exec`，而 browser 这头则继续真实接收 `bridge:request` 并回 `bridge:response`。这样之后，这条测试的定位也被重新收清了：它不是外部真浏览器窗口的完整生命周期测试，而是一条基于现有 ws 能力长出来的 service/browser 协议流长测试，重点是验证 service 在 browser 端和 repl 端都真实接入时，是否能正确地下发 batch、转发 query/exec 请求并回收响应。`scripts/test-host.ps1` 这边也同步收回成只跑这一份 `host.test.mbt`，不再顺序调四个 test file。全部改完以后重新跑了 `./scripts/build-native.ps1 -Package service -Test -TestPackage service -TestFile host.test.mbt` 和 `./scripts/test-host.ps1`，当前都已经重新回到绿色。到这里，这一轮最后真正收住的位置也比较清楚：前面那套 `host-support` 分法已经彻底拿掉，当前仓库里留下的是一个更短、更直白、边界也更干净的单文件 host 长测试；后面如果还要继续查“把测试 helper 编进本体到底会不会引出别的问题”，现在也已经不需要再靠猜，而是可以直接围着当前这版单文件长测试往下看。

## 03-28 上午

上午先围着昨晚接进来的 WAMR，把 managed app 的运行时路线重新掰了一遍。起因是一个很直接的问题：既然只是想给 managed app 找执行环境，为什么不干脆直接调用 `node`，而要额外接一层 wasm vm。这里先回头对着 `doc/meta-editor-service.md` 里的边界重新看了一遍，确认当前主语义仍然是 MoonBit native service 做宿主，Node.js 不再承担项目运行时职责；按这个前提继续推下去，直接接一层外部 JS runtime 虽然短期省事，但很容易把现在一直在压的统一宿主路径重新岔开，所以后面没有立刻翻案，而是把问题重新压成了三件更具体的技术核查：WAMR 的 `wasm-gc` 到底支不支得住 MoonBit，`WASI` 在这里到底有没有必要，以及如果这两件事都不稳，后面还有哪些替代路线。

顺着这条线往下查以后，第一件真正钉清楚的是 WAMR 当前 vendored 进仓库的状态和口径。这里实际去看了 submodule，确认锁的是 `WAMR-2.4.4/8c18e3f`，再对着它自己的 README、build 文档和 proposal 稳定性说明把 `GC` 和 `WASI` 这两条线重新核了一遍。结果比较明确：`WASI` 这边属于正式支持的能力，构建选项和几条延伸路线都写得比较完整；`GC` 这边虽然源码和测试里已经不是空白，但官方口径明显更保守，不能直接当成“已经足够稳妥兼容”的能力。这里中间一开始我还本能地想把结论讲成“WAMR 有 GC，只是成熟度要再核”，结果用户马上把问题点穿了：如果 MoonBit 这边实际产物本身就强依赖 `wasm-gc`，那这件事在工程上的含义就不再是“也许会撞到一些边角缺口”，而是宿主兼容性本身就站不稳。顺着这个提醒，后面也把判断重新压死了：`WAMR + wasm-gc` 不能再当默认稳妥路线，只能算一条风险明显偏高的候选。

接下来又顺手把 MoonBit 自己和 `wasm-gc` 的关系重新捋了一遍。这里最后收下来的口径也比最开始更准了很多：MoonBit 语言整体并不是只有 `wasm-gc` 一条路，官方文档明确列了普通 `wasm`、`wasm-gc`、`js`、`c` 和 `llvm` 这些后端；但另一方面，MoonBit 默认的 WebAssembly 心智和 wasm 版 toolchain 又确实都明显偏向 `wasm-gc`。这件事最后没有继续纠缠成“到底算不算强依赖”的字眼，而是直接落回更实在的工程标准：后面如果真要给 managed app 找 wasm 宿主，不能再把“这个 vm 能跑一般 wasm”当成充分条件，而得正面回答“它能不能可靠跑 MoonBit 实际会生成的那种产物”。

把 `wasm-gc` 这条线先钉清楚以后，后面又专门解释了一下 `WASI` 在这里到底是干什么用的。用户这边一开始其实也说得很坦白，提 `WASI` 更多只是出于一种“好像这是 wasm runtime 常见能力”的模糊担心，并没有特别确定自己到底想用它做什么。这里后面就先把它重新翻成比较接地气的宿主语义：`WASI` 主要提供的是一套标准化的低层宿主接口，像文件和目录、`stdin/stdout/stderr`、环境变量、命令行参数、时钟、随机数之类，都可以通过它暴露给 wasm 模块；如果跑的是一个更像命令行小程序的 wasm 应用，这套标准接口就很有价值。可再对着当前仓库已经写死的边界一看，MetaEditor 这里的 managed app 更像是“挂在 native service 里的受控应用”，主要能力本来就会通过宿主自己定义的 API 暴露出来，而不是把整个宿主世界按一套通用进程接口都敞给 wasm 模块。所以这里最后先收成了两层判断：`WASI` 不是决定 wasm 路线能不能成立的关键前提，但把它当成宿主接口设计时的重要参照是完全合理的。后面如果真的要接，比较像正路的做法也不是先把整套 `WASI` 一次吞进来，而是按当前真正需要的低层能力渐进接入，接了的那部分尽量保持标准形状和标准语义，不再另外发明一套看起来像标准、实际却是仓库私货的平行接口。

再往后，话题就继续往“如果 `wasm-gc + WAMR` 风险大，那剩下哪些路线更像正路”这个方向收。这里先把 `JSC/V8` 也一起摆上来比较了一轮，不过很快就把焦点落在了 `V8` 和 MoonBit 的 `js` 后端上：如果都已经考虑把一个 JS 引擎嵌进宿主了，那最自然的做法通常不会是“再让这个 JS 引擎去跑一层 wasm”，而是直接跑 MoonBit 的 `js` 产物；相比之下，`JavaScriptCore` 这边在当前 Windows 开发环境和仓库上下文里都不太像合适的主路线。与此同时，围绕普通 `wasm` 后端和 `wasm-gc` 的差异也专门查了一轮。这里最后收下来的口径也比较中间：普通 `wasm` 后端未必会一下子少掉很多“语言功能”，但它也绝不是“除了体积更大以外完全一样”，因为内存模型、对象表示、字符串互操作和宿主绑定方式都跟 `wasm-gc` 不同，所以值得继续认真评估，但不能拿“只是大一点”这种太轻的标准去看。

把后端和宿主的大方向先摆完以后，最后真正把这条 wasm 路线重新讲通的，反而不是 `WASI` 或 `GC` 本身，而是 managed app 对 async 的要求。中间我先顺着 MoonBit 当前 async 文档把现状核了一遍，确认官方那套 `moonbitlang/async` 对 WebAssembly backend 还不支持，`wasm-gc` 并不会在这件事上比普通 `wasm` 多出什么优势。用户随后又把问题继续压到了更实在的地方：managed app 真的必须有语言级 `async/await` 吗，如果没有的话，能不能自己包一层 `Promise`。这里后面整段讨论反而把心里那块石头放下来了：按当前 service 结构把 managed app 里真正的“异步来源”拆开看了一遍以后，发现它们大多都是宿主交互，像发命令、等 service/browser/storage 回结果、再把结果投回状态机；这类异步完全可以先压在宿主层，由 app 自己继续保持同步 reactive 状态更新，等结果回来时只吃一条新的事件。沿着这个前提再往里走，后面又专门把“自己包一层 Promise 到底算不算正经 Promise”掰清楚了：如果 managed app 内部自己维护 `pending/resolve/reject/then/catch/map/flat_map` 这一层状态机，那它在语义上本来就是 Promise，差别只在调度语义、错误传播和取消这些细节是不是自己先定清楚。这里顺手还把 JS 里 Promise 和 generator 的关系也理了一下，确认 Promise 本身并不依赖 generator，MoonBit 现在也没有像 JS 那样显式的 generator 语法，所以这件事并不会卡住自制 Promise 这条路。到这一段真正讨论完以后，当前对 wasm 路线的判断也终于重新压成了一个比一开始更扎实的版本：managed app 会遇到异步问题，但第一阶段完全可以不依赖官方 async runtime；只要宿主能负责回包和调度，app 内部再包一层够薄的 Promise/Future 状态机，wasm 路线在表达能力上就还是成立的。到这里，这半天虽然没有继续改任何代码，但路线上的不确定性已经比一开始少了很多：`WAMR + wasm-gc` 风险要下调，普通 `wasm`、`js` 后端和渐进接入的 `WASI` 子集都值得继续认真比较，而 wasm 路线本身并没有因为“没有官方 async”就直接被判死。

今天上午后半段开始具体落实 WAMR 的接入。用户先提醒我不要只盯仓库里的 `doc/mbt-skills-notes.md`，而是回到上一级目录的 `../mbt-skills` 去看原始的 `moonbit-c-binding` 和 `moonbit-lang` 章节。按这个提醒重新读了一遍以后，宿主接入时最容易出错的几件事都清楚了不少：`native-stub` 的 C 文件必须和包配置放在同一目录，非 primitive 参数最好把 `#borrow/#owned` 写明，字符串和字节边界也要按实际编码来区分。用户接着又把实现边界压得更实在了一点，说接入层先按一个 `stub.c` 的心智去做，如果真的写长了再拆第二个 stub 文件。顺着这个约束往下看现有代码时，`service` 目录本来就已经是 `moon.pkg + stub.c` 这条形态，所以后面的改动也基本沿着这一层继续长，没有去碰别的包结构。

真正开始接 WAMR 时，第一步花在了上游构建方式上。最开始我还试着按比较省事的心智去想，看看能不能只靠 `service/stub.c` 补几条 include 和链接参数，把 WAMR 直接编进当前 native 构建。查完 `third-party/wamr` 里的 `embed_wamr.md`、`runtime_lib.cmake`、sample 的 `CMakeLists.txt` 和 Windows 平台配置以后，这个想法很快就站不住了：WAMR 官方自己的宿主接入本来就依赖一整套 CMake 变量、平台源文件和汇编文件，Windows 下还会牵到系统库、运行库和工具链口径。按这个现实重新定形以后，我先把 service 包配置改成了 `service/moon.pkg.json`，让 native stub 和 include 配置能明确写出来；MoonBit 侧则先补了一层很薄的 `service/wasm.mbt`，只放 `ensure_wamr/load_wasm/instantiate/call_i32/close` 这些最小 wrapper，不去先碰 managed app 的宿主 API。

中间真正花时间最多的是 WAMR 本体到底应该怎么和当前仓库的 Windows native 构建接起来。前面先试过把 WAMR 预构建成静态库，再由 `service` 直接链接，这条路编译能走得很远，但很快就开始撞到一串运行库和导入符号问题：一开始是 `dllimport` 口径不对，改完以后又变成 CRT 混用，再往里压甚至会把 native test executable 自己撞成 `0xc0000005`。顺着这些具体报错一点点排以后，最后把接法改成了更稳的版本：单独在 `service/wamr-lib/CMakeLists.txt` 里把 WAMR 编成 `metaeditor_wamr.dll`，`service/wamr-stub.c` 不再直接链接那套 runtime API，而是在运行时按 `METAEDITOR_WAMR_DLL` 去 `LoadLibrary/GetProcAddress`，把 `wasm_runtime_init/load/instantiate/call` 这些函数指针取出来再转给 MoonBit。这么改完以后，前面那串静态链接带出来的 CRT 纠缠就一下少了很多，Windows 下 native test 也终于重新稳定了。

把动态加载这层站稳以后，后面又顺手把 MoonBit 侧的句柄表示也改得更直接了一些。前面最早的版本是按 `#external type` 去包 WAMR 的 module/instance handle，写起来看着像类型更严一点，但 native test 在 Windows 下总有些解释不太清的运行期崩溃。继续往下排时，我先把真正跨 FFI 传的句柄改成了 `UInt64`，`service/wasm.mbt` 这边再用很薄的 `WasmModule/WasmInstance` struct 包一下；同时把 `Bytes` 和 `Ref[Int]` 的参数注解重新补齐。改完以后最小验证终于能走通：`service/wamr.test.mbt` 里手写了一份只导出 `forty_two() -> i32` 的 wasm 二进制，service 这边可以成功 `load -> instantiate -> call_i32("forty_two")`，另一条非法 wasm 输入也能稳定报错返回。实际跑下来，`./scripts/build-native.ps1 -Package service -Test -TestPackage service -TestFile wamr.test.mbt` 已经是绿的。

WAMR 预构建打通以后，脚本侧又暴露出一个体验问题。最开始 `scripts/build-wamr.ps1` 每次都会把整个 `_build/native/debug/wamr` 删掉，再重新 configure 和 build，用户马上指出这件事很糟，因为只要跑一次 native 测试就会把 WAMR 从头编一遍。照着这个提醒回去改时，先把 `build-wamr.ps1` 收成了增量模式：只有 `metaeditor_wamr.dll` 不存在、`CMakeCache.txt` 不存在，或者 `service/wamr-lib`、`service/wamr-stub.c`、`third-party/wamr/build-scripts`、`third-party/wamr/core` 这些输入比 DLL 新时，脚本才会重新 build；平时命中缓存时直接秒过。用户随后又把打印问题点了一下，说没重建时也不该总出现一条像“正在构建 WAMR”的提示。这里跟着把 `scripts/build-native.ps1` 也收了一小步：WAMR 真重建时才打印那条提示，命中缓存时只保留 timing。这样之后再跑 native 测试，前置那段预构建终于不再显得像每次都在重活。

原生测试入口也顺手重新理了一遍。最开始为了把 `service.test.mbt` 和 `wamr.test.mbt` 都跑进去，我先临时把 `scripts/test-native.ps1` 写成了连续调用两次 `build-native.ps1`。用户很快指出，这种做法不该长期留着，而且如果要改成批量测试文件，也得先想清楚 `moon test` 自己对 filter 的限制。顺着这个提醒回头先看了 `moon test --help`，这才确认 `--filter` 匹配的是测试名，不是文件名。按这个口径重新整理以后，最后没有继续把规则绑在文件名上，而是只给 native 测试名统一加了 `native:` 前缀，`service.test.mbt` 和 `wamr.test.mbt` 的文件名维持原样；`scripts/test-native.ps1` 则收成一条单调用，直接走 `--filter "native:*"`。改完以后重新跑 `./scripts/test-native.ps1`，当前结果是 `Total tests: 13, passed: 13, failed: 0.`，其中 service 原有的 11 条 native 测试和 WAMR 新补的 2 条都能一起命中，而且整段流程只起一次 build-native。

后面用户又注意到一个更细的仓库状态问题：主仓库里 third-party/wamr 一度显示成了 Subproject commit ...-dirty。顺着这个提醒回头去看 submodule 状态时，当前实际只有 third-party/wamr/core/version.h 这一处变脏，而且没有正文 diff，更像是 WAMR 自己的构建步骤把版本头碰了一下，最后只留下了行尾层面的工作区脏状态。这里我直接在脚本后面补了一段 git restore 逻辑，另外专门强制触发了一次真实重建，确认当前这条恢复逻辑确实生效：WAMR 预构建继续能跑，但 third-party/wamr 不会再因为版本头被碰到就把主仓库状态弄脏。

到这里，这条 WAMR 接入线先停在了一个比较适合往后接的最小位置：宿主侧已经能把 WAMR 预构建起来，service 这边也已经有了 ensure_wamr/load_wasm/instantiate/call_i32/close 这层很薄的桥，原生测试入口也重新收成了单次 moon test --filter "native:*"。继续往下做时，下一步更像正路的不是再去扩 WAMR 本体的构建细节，而是把“managed app 真正需要宿主提供什么能力”先压成一条窄得多的接口面。比较像可以先做的几件事有三条：一是把现在 service/wasm.mbt 里这层最小 wrapper 再往前推一步，长出一个更接近 runtime object 的宿主抽象，至少把 module、instance 和错误状态的生命周期整理到一个地方；二是选一条最小的 managed app 入口约定先定死，例如导出 main、init 还是某个明确的 message handler，不要一开始就把 host API 面铺开；三是尽快补一条真正贴近后续主路径的验证，不再只停在 forty_two() -> i32 这种 smoke test，而是让一个最小 wasm app 至少能接一次宿主调用、回一次结果，哪怕这一步先只做同步路径也够。按今天上午已经确认下来的方向看，WASI 和 wasm-gc 现在都还不该抢到最前面，后面更值得优先做的是普通 wasm 路线下的宿主 API 形状、instance 生命周期和事件/回包模型。

## 03-28 下午

下午先接着把上午那条 WAMR 集成验证往前推，先处理“MoonBit 实际编出来的 wasm 模块能不能被当前宿主路径稳定跑起来”。上午那版 native 测试还停在手写 wasm 字节数组，只能证明 service/wasm.mbt 和 WAMR 的最小加载、实例化、call_i32("forty_two") 这条链是通的，离后面真正要托管 MoonBit 程序还差一截。这里先做了一次最小 MoonBit wasm 构建实验，确认当前工具链可以直接 moon build --target wasm，产物也会稳定落到 _build/wasm/debug/build/...。试完以后，没有把这层逻辑塞进 build-native.ps1，继续让它只管 native build；wasm 构建放到 scripts/test-native.ps1 前面，先把一个独立的小 MoonBit wasm module 编出来，再继续跑现有 native test。

这个小 wasm module 最后没有继续放在系统临时目录临时生成，也没有挂成 service 包树里的普通子包。中间先试过把它收在 service/test/wamr_app 下面直接当 service 的子包用，很快就撞到 Moon 的包边界：-p service 的native test 会把它一起扫进去；再给它写 supported-targets: wasm，native test 又会因为选中的包里混进了不支持 native 的子包直接报错。这里把边界看清楚以后，后面改成在 service/test/wamr_app 里单独放一份moon.mod.json，让它变成一个嵌在 service 目录里的独立小 module。这样一来，它仍然跟 service 这条线放在一起，也不会继续污染 -p service 的 native test 范围。scripts/test-native.ps1 则直接用 moon -C service/test/wamr_app build --target wasm . 去编这个小 module，当前真实产物路径也随之固定成了 service/test/wamr_app/_build/wasm/debug/build/metaeditor-wamr-app.wasm。

把真实 MoonBit wasm 产物接进测试时，中间还踩到一处更隐蔽的问题。最开始图省事，直接在 service/wamr.test.mbt 里用 async @fs.read_file(...) 去读这个 wasm 文件，再把对应 test 改成 async test。单跑 wamr.test.mbt是绿的，和 service.test.mbt 一起按 native:* 整组跑时，整个 native test 会稳定贴着 10 秒预算超时，看起来像是测试突然变慢了。这里很快把单文件和整组执行时长分别拆开跑，确认不是新加的 wasm 构建慢，也不是 WAMR 调用本身慢，而是 wamr.test.mbt 进了 async test driver 以后，整组 native test 的执行形态跟着变了。后面把 wamr.test.mbt 收回同步测试，再在 service/stub.c 里补了一条很小的同步读文件 FFI：直接按路径读出字节，返回Bytes 给 MoonBit。改完以后，wamr.test.mbt 重新回到普通 test，整组 ./scripts/test-native.ps1 也恢复成 13 passed，问题点算是钉清楚了。

顺着这条稳定下来的真实编译产物路径，后面又把 WAMR 调用从原来的 () -> i32 往前推了一小步。上午那版 bridge 只有 call_i32("forty_two")，只能证明模块能加载和调用无参导出函数。下午先把 service/test/wamr_app/main.mbt 扩成一个更像后面 managed app 入口雏形的最小程序，继续保留 forty_two()，同时新加 handle(op : Int) -> Int，里面只做很小的分派：0 => 42，1 => 7，其他值走 n + 1。为了让宿主真能把一个参数传进去，这里同步改了 service/wamr-stub.c 和 service/wasm.mbt，补上一条新的 (i32) -> i32 调用桥。当前这层桥本来就负责函数签名检查、argv 组装和返回值回填，所以从 () -> i32 扩成 (i32) -> i32 时，stub.c 和 wasm.mbt 都要一起跟着改。改完以后，service/wamr.test.mbt 里也把验证从单一的 forty_two() 扩成了 handle(0) == 42、handle(1) == 7、handle(41) == 42 这几条最小 case。相关回归重新跑过，./scripts/build-native.ps1 -Package service-Test -TestPackage service -TestFile wamr.test.mbt 和 ./scripts/test-native.ps1 现在都已经是绿的。

下午后面还顺着一个 warning 多查了一笔旧上下文。native test 里一直会带出 service/base.mbt 里的 json_double 未使用 warning，原本看上去像是留着没删的小 helper，后来专门查了 git blame 和相关提交历史，确认这东西是 03-27 那次加 browser request/response sync 和 host test infrastructure 时，为当时那份更重的 host.test.mbt 补进去的。那版测试里会查询浏览器节点矩形和 viewport 尺寸，json_double 当时就是给这些rect.top/bottom/left/right 和 viewport.width/height 用的。再对着 devlog 后半段看回去，这条线后来因为 host 浏览器整链测试一直卡，测试策略改成了现在更基础的一组链路探测，那份旧测试撤掉以后，json_double 就只剩成了一个没再被调用的尾巴。这里没有顺手去删它，先把它记成那条未彻底解决的问题留下的痕迹：旧的 host 浏览器重测试虽然已经不再挂在当前主回归里，但它背后的运行时问题还在，没有因为测试换了写法就自动消失。

今天下午做到这里，WAMR 这条线和上午相比已经往前站稳了两步。第一步是 native test 不再只吃手写 wasm 字节，而是已经能跑仓库里单独编出来的 MoonBit wasm 产物；第二步是宿主和 wasm 之间不再只有 forty_two() 这种无参smoke test，而是已经有了最小的 (i32) -> i32 调用面，可以开始拿一个更像 message handler 的窄入口继续往前推。与此同时，service/test 这个目录虽然已经开始承接这次新加的 wasm 小 module，但也顺手把另一个边界看清楚了：当前 service 根目录里的那些测试文件，不能简单整体搬进 service/test 再保持原来的白盒访问方式，Moon 这里按目录认包，直接硬搬走不通，这条事先不继续往下推，免得把现有回归入口一起扰乱。

后面又把 WAMR 的运行路线单独掰清了一次。之前并没有专门写清楚当前仓库接进去的是解释器路线，具体开的是 WAMR_BUILD_INTERP=1 和 WAMR_BUILD_FAST_INTERP=1，AOT/JIT/FAST_JIT 都还是关着；构建产物这边也只有 metaeditor_wamr.dll，没有 wamrc 参与，也没有任何 .wasm -> .aot 的步骤。顺着这层再往下讲，.aot 这里也一起重新说清楚了，它是 WAMR 的 Ahead-Of-Time 产物，需要先把 wasm 用wamrc 预编译，再交给 runtime 去加载，所以它背后天然会多一条构建链和产物管理链。

把当前状态钉清楚以后，话题很快就转到性能路线。这里先按“开发体验”和“集成复杂度”把 AOT、JIT、解释器这几条线摆在一起重新看了一遍。AOT 的好处是性能路线稳，运行时心智也清楚，缺点是每次都要多管一份 .aot 产物；JIT这边更接近“继续只分发 .wasm，运行时自己处理”的习惯，所以从用起来顺不顺手这个角度，用户这边很自然地更偏向 JIT。顺着这个偏好继续查下去以后，当前环境里的边界也就更具体了：如果后面真要在这台 Windows 机器上认真接JIT，比较像实际候选的是 LLVM JIT，Fast JIT 这条线当前并不适合直接拿来当主方案。这里讨论完以后，路线上的判断也比前面更收紧了一步：解释器这条线继续适合眼下把 managed app 主路径接起来，AOT 代表更稳的性能路线，JIT 则代表更顺手的 .wasm 使用体验；如果后面明确把“少一条 .aot 管理链”摆在更高优先级上，那值得认真评估的方向会是 LLVM JIT。

和这件事一起又顺手把 runtime 的集成形态重新讲了一遍。当前仓库里 metaeditor_wamr.dll 这条线，主要还是前面 Windows 上为了解决 CRT、导入符号和静态链接时撞出来的崩溃问题，先选出来的一条稳路。用户这边明确表达了对这层 DLL 形态的不满意，更想要后面把 runtime 直接内嵌进 service.exe。这里后面没有继续把当前 DLL 写成长期答案，而是先把它记成一个过渡状态：当前这条动态加载路径的价值，在于它已经把真实 MoonBit wasm 跑通，也已经能继续往 managed app 主路径推进；等入口约定和 runtime object 再稳定一些，后面完全值得专门开一轮，把 WAMR runtime 从 DLL 路线收回静态内联，再结合当时选定的性能模式，决定是继续吃 .wasm 还是补 .aot。这段讨论本身没有继续改任何代码，但它把后面集成路线的几条分叉先摊平了：当前仓库实际跑的是解释器，性能路线可以继续看 AOT，使用体验更偏向 JIT，长期的宿主形态则更像是把 runtime 直接收进 service 自己。

下午后面继续把“managed app 真正怎么挂到 wasm runtime 上”往前推了一小步。这次没有再沿着 `call_i32`/`call_i32_i32` 那种按函数名散着长的桥接往下补，因为前面那层虽然足够做 smoke test，但再继续堆下去，很快就会把宿主接口面带成一堆离散导出函数，和后面想做的 managed app 容器心智不一致。这里先把目标重新压成一条更窄的主路径：宿主先创建一个 app instance，后面统一给它发消息；app 要么立刻回结果，要么先吐一条“需要宿主处理”的请求，宿主再把结果喂回去；实例结束时再显式销毁。按这个标准回头看，当前更值得先钉住的已经不是“还能不能多调几个 wasm 导出”，而是 instance 生命周期和事件回包模型。

顺着这个判断，后面先把 `service/wasm.mbt` 和 `service/wamr-stub.c` 一起收成了固定协议。MoonBit 侧不再继续往外暴露按名字调任意导出的接口，而是先包出一个很薄的 `WasmApp`，入口只剩 `load_wasm_app()`、`send(...)` 和 `close()`；stub 那边也跟着把导出约定钉成 `app_init/app_handle/app_result/app_request/app_close` 这五个固定入口，函数查找、签名检查和实际 `wasm_runtime_call_wasm` 的那层重复逻辑都收回到stub 内部的小 helper 里。这样改完以后，service 这边开始真正有了一点“runtime object”的形状，不再只是 module/instance handle 外面再套几条 call bridge。

为了让这层协议不是空壳，`service/test/wamr_app` 里的 wasm fixture 也一起换了。原来那个小 module 只有 `forty_two()` 和 `handle(op)` 这种纯函数导出，这次直接改成了一个最小的有状态 app：`app_init()` 负责分配app id，模块内部用一张 `Map[Int, ...]` 维护实例状态；`app_handle()` 先只支持几条最薄的消息，一条同步更新内部计数，一条把“请求宿主”的值挂成 pending request，再一条吃宿主回包继续推进状态；`app_result()` 和`app_request()` 分别把最近结果和当前 pending request 交给宿主，`app_close()` 则把实例从表里删掉。这里刻意没有一口气把 payload 做成 bytes 或 JSON，先只让“有状态 instance + 宿主投递消息 + app 请求宿主 + 宿主再回包”这条骨架跑起来，免得把消息编码、线性内存传输和协议语义三件事一次搅在一起。

对应的 native test 也跟着从 smoke test 换成了贴主路径的验证。`service/wamr.test.mbt` 不再只断言 `forty_two() == 42` 或 `handle(41) == 42`，而是直接加载这个 managed app fixture，先发两条同步消息把内部状态往前推，再发一条会返回宿主请求的消息，确认 service 侧已经能稳定拿到一条 call-host 事件，最后再把宿主结果回灌回去，看 instance 内状态能不能继续接着走。相关回归重新跑过以后，`./scripts/build-native.ps1 -Packageservice -Test -TestPackage service -TestFile wamr.test.mbt` 和整组 `./scripts/test-native.ps1` 当前都还是绿的，说明这次改动虽然还只是第一层骨架，但至少已经把“wasm 当 managed app 容器”从无状态函数调用往真正的instance 模型推近了一步。

不过这一步做完以后，也顺手把另一个问题暴露得很直白：现在这层协议虽然已经能跑，但表现形式还太贴近底层，测试里会露出一些很难直接读懂的裸数字和状态码。这里先没有硬把这一版包装成最终接口，而是把它留在一个更老实的位置上：当前真正已经钉清楚的是生命周期、事件投递和宿主回包这条主路径本身；至于消息该怎么命名、payload 最后是继续收成窄整数、换成 bytes，还是再往上包一层更像真正 managed app API 的结构，得下一步单独认真定，不适合在这一步顺手拍死。

下午后面先把 wasm managed app 这条线重新掰了一遍，重点不再是 WAMR 能不能继续多补几条导出函数，而是 WasmApp 本体到底应该长成什么样，免得后面一边接能力一边把模型带歪。这里先顺着现有仓库和 `IntentDoc/dev/story`里那批 editor 的写法重新对了一轮，确认 managed app 不该被想成“宿主发请求、app 回结果”的小工具，而应该尽量贴近现在 editor 的自然形态：本体先按 `data/local/action/ui/console` 这组心智去看，其中 `cli`是默认就存在的基础面，浏览器 UI 则更像一套后续可选择绑定的系统侧运行时；也就是说，app 本体先不该被一堆宿主生命周期钩子和 capability 细项反向塑形，系统默认接住 state/local 的持久化和基本运行，真正额外需要的系统侧东西再通过绑定或注入接进来。沿着这个判断，后面也把“浏览器 UI 到底算什么”重新压得更准了一层：它不是另一套抽象 view 快照，更不是要另外发明一层中间协议，而就是 MetaEditor 当前这套浏览器 UI runtime；后面如果app 申请并绑定了 browser_ui，拿到的就应该是现有 `dom.mbt` 这组 API 和它背后的 `DomCmd -> bridge.js -> DOM` 主路径，而不是仓库外再长一套看起来更规整、实际却和现有模型平行的私货协议。

把这个大方向先说顺以后，后面真正开始暴露问题的反而是更基础的一层：前一版 wasm fixture 为了验证“动态绑定 browser_ui 才生效”，直接在 app 本体里挂了一张 `Map[Int, AppState]` 的实例表，再靠一组带 `app id` 的导出在里面手动分发，结果看起来完全不像正常 editor app，而像把容器层硬塞进了业务代码。用户随后连续把这个问题压得很实在：先是指出这份 `main.mbt` 本身根本不像 app，再往里追到“为什么已经单例了还要继续在 app 里检查`app id`”，最后干脆直接要求把这层单例问题先硬收掉，别再留一层换名字的假壳。顺着这个要求往下改以后，这一轮最后真正留下来的变化是两层一起收：一层是 fixture 本体重新改回单实例，不再自己维护多实例表；另一层是宿主和 WAMR 之间那套 app ABI 也跟着从带 `app id` 的版本改成了真正的单实例版本，`app_init()` 不再返回 handle，而 `app_handle(op, arg)`、`app_result()`、`app_request()`、`app_bind_browser_ui()` 和 `app_close()`也都不再继续带那只没有业务意义的参数。这样之后，当前这条 wasm managed app 线虽然还没有真的把声明式 UI 接进来，browser_ui 绑定也还只是最小占位验证，但至少模型上已经重新压回了一个不那么容易继续踩坑的位置：WasmApp 本体先是单实例 editor app，本身尽量贴 `data/local/action/ui/console` 这组心智去写；浏览器 UI 继续作为后续可绑定的系统侧 runtime 保留，而不是反过来先用一层宿主壳把 app 本体写坏。

下午后面先把 WasmApp 和宿主接口这条线重新掰了一遍，起因是前面虽然已经把 browser_ui 说成一种后续可绑定的系统侧运行时，但真往下写时又一路开始绕回去：一会儿想把 `dom.mbt` 静态编进 wasm fixture，一会儿又想靠运行时再“动态注入”一组新 API，结果越改越别扭。这里后面先顺着 wasm 语义本身把事情重新查清楚了：当前这条 plain wasm + WAMR 路线上，import 是实例化时就定死的，做不到对同一个 wasm 实例在运行到一半时再新增一组导入符号；真正能动态变化的，不是 import 名字本身，而是宿主在运行时对既有接口的授权、绑定和上下文开放。顺着这个判断，后面也把前面一度想借 WASI 兜过去的念头一起压掉了：WASI 更像一套标准化的具体宿主功能接口，适合文件、时钟、socket 这类 OS 风格能力，但它不解决 browser_ui 这种项目私有运行时，更不替我们解决“能力动态申请”这件事。沿着这个结论往回看，当前最靠谱的方向就重新收清楚了：如果以后还要让 wasm 承担 managed app，browser_ui 这层只能是自定义宿主接口，而且更像“静态存在一层很薄的宿主 ABI，运行时再决定是否绑定”，不能再继续幻想把整包 `dom.mbt` 静态编进去、或者给现有实例后加新 import。

把这个语义问题钉清楚以后，后面就没有再继续在 `try-wamr` 里补实现，而是顺着用户已经做好的分支隔离，把后续工作位置重新定了一次。用户这边先明确说了：WAMR 相关内容已经专门隔离在试验分支里，后面真正要继续推进的是JS 版 managed app；同时像 `.gitmodules`、`third-party/wamr` 这类东西绝对不能进后续分支，不然仓库体积会立刻膨胀。顺着这个边界，后面实际去把 `main/host-test/try-wamr` 这三条线重新对了一遍，最后收下来的判断也很直接：`host-test` 承接的是仍然有价值的通用内容，比如 host/repl 测试、DOM keyed diff、bridge 和脚本入口；`try-wamr` 额外多出来的几乎都是 WAMR 接入和 wasm fixture 试验代码，本身不适合直接带进 JS 分支，真正值得保的是那一整轮讨论、踩坑和路线判断。按这个结论，后面从 `main` 起了新的 `experiment/js-managed-app` 分支，把 `host-test` 那边的通用代码内容整批带了过去，同时刻意避开所有 submodule/WAMR 文件；接着又按用户要求把 `AGENTS.md` 一并带过来，而 repo 内的 `doc/devlog.md` 则直接删掉，不再继续和仓库状态绑死。全部收完以后又把 `moon test`、`./scripts/test-native.ps1` 和 `./scripts/test-host.ps1` 重新跑了一遍，当前结果都还是绿的。到这里，这一轮最后真正收住的结果就是两件事：一是 wasm 这条线在语义上已经确认不能再按“动态新增 import”去想，后面如果真回头做也只能按自定义宿主接口继续；二是后续 JS managed app 已经有了一个干净的新分支起点，WAMR 试验继续留在旧分支里当参考，不再和接下来的主工作线混在一起。

下午又进一步讨论了一下 managed app 这条线，而且这次真正收住的不是某个实现细节，而是前面一直没压稳的能力模型。起因是这轮围着 wasm、browser_ui 和宿主接口来回试了一圈以后，问题已经越来越清楚：麻烦并不只是出在WAMR 或 wasm import 语义上，而是 MoonBit 本身更偏静态描述，天然不太兼容“运行到一半再动态申请一组新能力”这种写法。这里中间先顺着 wasm 语义把一件事重新钉死了：plain wasm 这条线上 import 在实例化时就已经定了，做不到对同一个实例后加一组新符号；接着又继续往里看，发现就算退到 JS 后端，这件事也不会自动变好，因为问题更根本地出在 MoonBit app 写法和动态 capability 语义本身不顺，像同一套接口和类型要在 `src` 宿主侧和 app侧各写一遍这种别扭感，也不会因为后端换成 JS 就自己消失。

顺着这个判断往下想，最后把能力模型重新压成了一个更现实的版本：先放弃“运行期动态申请 capability”，改成在 build 的时候就由宿主配置好 app 会带哪些能力，app 启动以后只吃这份已经定好的环境，不再试图在运行中临时新增一组 API。这里中间还专门把 `browser_ui` 这件事重新说清楚了：它不是所有 app 天生就有的默认部分，但也不再按“跑起来再申请”的思路去做，而是直接变成 app 构建/装配时声明的一部分。这样改完以后，后面的模型一下就顺了很多：MoonBit app 本体还是尽量贴近现有 editor 的写法，按 `data/local/action/ui/console` 这组心智去组织；宿主侧则在更早的阶段决定这个 app 会不会带 browser_ui 这套 runtime，不再强行把动态 capability语义塞进当前明显更偏静态的类型和模块体系里。到这里，这条线虽然少了一点原来设想里的“系统感”，但换来的是更稳的边界：后面继续做 managed app 时，至少不会再一边想保住 MoonBit app 的自然写法，一边又被动态能力模型反复拖进很怪的实现里。

## 03-28 晚上

由于前面的分析，晚上又回到了 `try-wamr` 这条试验线，在 `service/test/wamr_app` 下面单独放了一份 `dom_probe.mbt`。起因很直接：前面已经把 WAMR 侧“命令能从 wasm 里读出来”这条链先打通了，但 `main.mbt` 里那段 browser_ui 还是手写 JSON 命令，接下来如果要试“app 用真实声明式 UI 写法能不能走通”，就得先有一层最小的 DOM 构建器。这里最开始没有碰正式 `dom.mbt`，而是先在这个独立 wasmfixture 里抄了一份极小子集，只保留 `Create/Text/Attr/Append`、`Child/Prop/VNode`、`h/realize/emit/get_cmds` 这些静态渲染真正用到的东西，先让 `main.mbt` 能把那段手写 JSON 命令改回`h("div", ...)` 这种声明式写法。

这层 `dom_probe.mbt` 最开始落下去时，里面用的是一版显式传状态的写法，也就是后面讨论里那套我一度叫成 `sink` 的东西。它本质上就是一团 `nid + cq` 状态，负责节点编号和命令累积；那一版里这团状态会一路显式塞进执行层，用起来像“这轮渲染往哪份命令状态里写”。这时还没有先把语义讲清楚，而是代码先落下来了。用户随后盯着这层实现一路往里追，先后把事情压成了几个更具体的问题：`sink` 到底是什么，它是不是 `nid`，是不是只是在标记“当前写的是哪份全局状态”，为什么这团状态不能删，为什么不能只在整轮命令队列层面标一下，而是要一路往每个 API 里带。这轮讨论把前面那层模糊说法慢慢压清楚了：`nid + cq` 这团状态本身不是新语义，只是 DOM 渲染时客观需要的一份执行期状态；真正值得避免的不是“有这团状态”，而是把它显式塞进每个声明式 API，把 UI 写法带得很怪。

顺着这轮追问，后面又把 `dom_probe.mbt` 改了一次，方向不再是“每个 API 都显式带状态”，而是只在一轮渲染边界上切当前状态，里面的 `h/Str/S/realize/emit` 这些用法尽量保持原样。这一步本身还是留在 `wamr_app`的临时探针层里，还没有动正式 `src/dom.mbt`。继续往下压以后，用户又专门追了一句：如果只是切当前状态，难道以后写 UI 都要再包一层 `use_dom_state(fn() { ... })` 的回调？这句把问题又往前掰了一层，因为它直接指出了那版写法的坏处：如果整段 UI 都得包在额外一层回调里，虽然比“每个 API 都带状态”干净一点，但实际写法还是会无缘无故多一层缩进。沿着这个判断，后面才真正把方向改成了更稳定的一版：既然状态只属于执行层，那就别再做运行时切换壳，而是把正式执行 API 直接改成显式 `state` 版本，只让 `realize/emit/get_cmds` 这些真正落命令的接口吃 `state`，上面的 `h/Str/S/Child` 一律保持不动。

这时候才开始真正去改正式 `src/dom.mbt`。最后收下来的公开执行接口就是 `new_dom_state()`、`realize(state, child)`、`emit(state, cmd)` 和 `get_cmds(state)` 这几项。主线 `service/app.mbt` 也跟着接了这套新接口，先补了一份 `host_dom_state`，再把 host app 渲染路径从原来的默认 `realize/emit/get_cmds` 改成显式吃 `host_dom_state`。这一步刚落完以后，最先暴露问题的不是 wasm fixture，而是主线 native 测试。重新跑 `./scripts/test-native.ps1` 时，`render app emits host page batch` 这条先打红了，缺的不是整批 DOM 命令，而是 `host_stop_service` 这条 action 名字。顺着这个失败点往里查，最后定位到 `reg_action(...)` 这层时机错了：它原来在构建 `Child` 的时候就会立刻往队列里发 `Action(name, id)`，现在状态已经改成显式 `DomState`，而 `render_host_app(runtime)` 又会先构出一棵 `Child`，真正写进哪份状态得等后面的 `realize(state, ...)`才知道，这样 action 命令就会掉进错误那份队列。

这里后面没有再去补额外同步步骤，而是直接把 `reg_action(...)` 本身改回一个更老实的形态：注册 callback 时只返回一个带 `name` 和 `id` 的 `ActionRef`，真正渲染属性的时候，再由 `render_element(...)` 把`Action(name, id)` 和 `Listen(...)` 一起发进当前这份 DOM 状态。顺着这个问题排查的中间，还一度为了先确认边界，在 `service/app.mbt` 里补过一个 `flush_host_dom(runtime)`，想在 `try_flush()` 后再从`host_dom_state` 里手动捞一遍命令送到 runtime batch。等 `reg_action(...)` 的时机改对以后再回头看，发现这层手动 flush 已经没有必要，`init_bridge(host_dom_state, ...)` 自己就能在 post-flush 阶段把批次送出去，于是后面又把 `flush_host_dom` 整个删掉。到这里，主线 `render_app(runtime)` 重新回到了 `scope(...) -> realize(...) -> emit(...) -> try_flush()` 这条单一路径，而 `./scripts/test-native.ps1` 也重新转回了绿色。

主线站稳以后，后面才回头去收 wasm fixture 这边的临时冗余。前面为了试 API 形状单独挂着的 `service/test/wamr_app/dom_probe.mbt`，这时候已经没有继续作为一层文件存在的必要了。这里先重新确认了一遍当前模块边界：`service/test/wamr_app` 还是靠独立 `moon.mod.json` 挂出来的小 module，眼下没有一条顺手的本地依赖方式能直接把根模块 `MetaEditor/src` 接进来，所以这条线暂时还不能像主线那样直接吃正式 `@src`。既然这个边界一时不改，后面的收法就也压成了最小：不再继续留 `dom_probe.mbt` 这层额外文件，而是把它并回 `service/test/wamr_app/main.mbt`，收成单文件 fixture，只留下当前 browser_ui 这条 wasm 试验线真正需要的那几样最小静态渲染定义：`DomState`、`DomCmd(Create/Text/Attr/Append)`、`Child`、`Prop`、`VNode`、`realize/emit/get_cmds` 和一层很薄的 `h`。这样之后，试 API 形状那层额外文件就拿掉了，剩下的局部重复只还留在这个独立 wasm 小 module 自己的 `main.mbt` 里，不再多挂一层包内抽象。

最后把这两条线一起重新跑了一遍。`./scripts/test-native.ps1` 当前重新回到 14 passed，前面那条 `host_stop_service` action 丢失的问题没有再出现；`moon build --target wasm` 在 `service/test/wamr_app` 这个独立module 里也还是绿的，说明 `dom_probe.mbt` 并回 `main.mbt` 之后，WAMR 这条试验线没有被打坏。到这里，这一笔真正留下来的状态也比较清楚：正式 `src/dom.mbt` 的执行层已经收成了显式 `DomState` 版本，默认全局执行语义没有继续并行保留；`reg_action(...)` 的 action 命令时机也重新对齐到了真实渲染路径；主线为了追问题临时补出来的 `flush_host_dom` 已经删掉；而 wasm fixture 那边用来试 API 形状的 `dom_probe.mbt` 文件同样已经拿掉，剩下的最小重复只留在独立小 module 自己的单文件里，后面如果 Moon 这边能补出更顺手的本地模块依赖方式，再继续往下收也会更直接一些。

继续往下收时，先把 review 里那条 `dom` 测试回归补干净了。这里没有回去给 `src/dom.mbt` 补旧入口兼容，而是按当前接口把 `test/dom.test.mbt` 全部迁到显式 `DomState` 上：文件开头加了一层很薄的测试 helper，统一由测试自己创建、重置和读取 `DomState`，把原来那些直接 `realize(...)`/`get_cmds()` 的调用点全部接回新签名。迁这层时也顺手把一个更底的语义重新对清楚了：当前 `realize` 顶层只接受 `Lazy`，`Dyn` 如果要在测试里跑，必须放进普通 children 路径，而且还得包在 `scope(...)` 里，否则会直接撞到 reactive scope 的 abort。把这些都接顺以后重新跑 `moon test -p test`，结果回到 `Total tests: 65, passed: 65, failed: 0.`。 

中间又顺着这件事把 `h_map` 的语义重新讲清楚了一遍。前面一度顺手把它说成了 keyed diff，回头看并不准确：当前这套实现没有显式 key API，也没有通用树级 diff，`h_map/h_map_dyn` 更像是一条要求 `Eq + Hash` 的列表复用 helper。内部直接拿元素本身做 `Map` key，保留项复用、缺失项删除、重排时尽量不重建；如果没有这层可比身份，整条 API 本身也就失去存在意义了。这里最后没有继续改代码，主要是把这条语义边界重新压准，免得后面再拿“通用 keyed diff”这种更重的说法去带偏测试和实现判断。

后面把注意力切回 `repl` 以后，最开始还是顺着 review 第二条去看“未握手 request 是否算绕过”，但顺着现有 CLI 行为和用户的目标继续往下掰，最后把这条通道的定位重新定得更准了一层：它本质上只是给 CLI 用的高速命令通道，传的仍然是原来的 CLI 命令，所以语义上应当继承 CLI 现有的多来源模型，不该再混进单客户端会话那套约束。按这个判断回头看，当前真正不对的就不再是“没 hello 也能 request”，而是协议自己前后不一致：一边保留着`repl:hello/repl_busy/repl_conn` 这套单客户端残留，一边 `repl:request` 实际又已经对所有连接开放。这里后面没有继续给 `repl:request` 加门槛，而是直接把这层多余语义整个删掉了。

实际改动落在了五处。`service/base.mbt` 里把 `repl_conn` 这层状态彻底拿掉，不再在 runtime 里保留一份没有实际价值的长连接占位；`service/bridge.mbt` 则同步删掉 `repl:hello/repl:hello_ack/repl:rejected /repl_busy` 相关处理，`serve_repl_websocket` 收成连接建立后直接按 `repl:request` 做 request-response；`service/cli.mbt` 里的 `meta repl` 入口也一起去掉握手，连上 websocket 后直接进入读 stdin、发`repl:request`、收 `repl:response` 的循环；`service/repl.test.mbt` 和 `service/host.test.mbt` 则相应改成 connect 后直接发命令，不再先走一轮 hello。改完以后先单独跑了 `repl.test.mbt` 和 `host.test.mbt`，两组native 测试都能通过，说明“长连接但多来源”的这条语义在当前代码里已经重新站稳了。

既然 `repl` 和 `host` 现在都已经回到更稳定的 native 测试上，后面又顺手把默认 native 入口重新收了一轮。最开始 `scripts/test-native.ps1` 虽然已经用 `--filter "native:*"` 统一跑 service 这组默认 native 测试，但`repl.test.mbt`、`host.test.mbt` 和 `sqlite.test.mbt` 还没有统一带这个前缀，真要全跑还是得一条条分开。这里最后按最小补丁把这些测试名全改成了 `native:*`，让默认入口真正能一条命令把主回归全带上。刚并进去时又顺手暴露出两个整组运行问题：一个是 `service.test.mbt` 里那条 lifecycle 测试和 `host.test.mbt` 里之前排查问题留下的 stdout 输出会把 `moon` 的测试结果解析直接打坏；另一个是 `host.test.mbt` 里“加项目以后下一条browser batch 恰好就是目标 batch”的假设在整组跑时偏脆，单跑能过，整组跑时就会被前面测试留下的异步消息顺序干扰。这里后面也一起收了：先把测试里的调试输出都去掉，再把 host flow 里那段 batch 读取改成持续收，直到读到包含 `project-row-host-demo` 的那一条为止，不再把具体批次顺序锁死。这样重新跑 `./scripts/test-native.ps1` 以后，整组结果回到了 `Total tests: 25, passed: 25, failed: 0.`，默认 native 回归入口也终于真正收成了一条。

## 03-29

休息

从这里开始 devlog 变更为时间列表的风格，更加清晰：
## 03-30 上午
1. 先回头检查了 wamrapp 里从 wasm 虚拟机把 DOM 命令写回 meta 主程序的链路，定位到 service/wasm.mbt、service/wamr-stub.c 和 service/test/wamr_app/main.mbt，确认 DOM 回写还停在 fixture 自己拼 JSON、宿主按字节回捞的临时做法上。
2. 然后先只清理了这层最明显的临时桥，把逐字节 app_dom_at 改成按 4 字节块读取的 app_dom_word，宿主侧按块拆回字符串，native 测试重新跑通。
3. 接着围着 ABI 继续讨论，把“宿主调 wasm”的统一 ABI、AbiValue、OutMessage、控制面和数据面分层、宿主请求、同步重入 host 的风险、分支预测和性能验证点这些内容整理成了新文档 doc/managed-app-abi.md。
4. 再往后讨论时，把模型从以 app 为中心转到了以 editor/runtime 为中心，确认 editor 才是可组合的语义单元，app 更像 root composition 或入口壳，wasm 包只是部署边界，不该成为语义中心。
5. 后面切回了 experiment/js-managed-app 这条干净分支，对比 try-wamr，开始把那边和 WAMR 本体无关、但语义更新较新的内容往当前线拉。
6. 第一轮先挑了 DOM state 和 repl 去握手这两块，确认 moon test 和 native 测试都能过。
7. 然后按“优先保留最新语义”的方向，把 try-wamr 上非 WAMR 的文档、构建脚本、service 代码、测试和 service/moon.pkg.json 一起同步过来，WAMR 子模块、本体 stub、wasm fixture、构建脚本继续排除。
8. 同步完以后，源码测试能过，但 native 脚本因为还保留了 WAMR 构建步骤直接失败，于是继续把 service/moon.pkg.json、scripts/build-native.ps1、scripts/test-native.ps1 里的 WAMR 接点全部拿掉。
9. 最后又把 service/stub.c 里和 WAMR 线一起带进来的、已经没有引用的 read_file_bytes 宿主接口删掉，重新验证 moon test 和 ./scripts/test-native.ps1 都回到全绿。
10. moonbit 插件的 lsp 有时候显示的是前面修改的错误反馈，需要重开一次 vscode 才会更新（不过 js 也有类似现象，可能是 vscode lsp 本身的 bug）
11. 重新确认 app/editor 的语义边界。app 继续保留为顶层对象，editor/component 继续保留为 app 内部的可组合单元，wasm 包装层不再参与 app 本体定义。
12. 新写 `doc/managed-app-sketch-v3.md`。对象边界收成 `AppEntry` 和 `AppInstance` 两层。`AppEntry` 走源码内部注册，`AppInstance` 只记录 `entry_id` 和 `status`。
13. 把 `service/app.mbt` 从 `AppProject -> AppInstance` 收成 `AppEntry -> AppInstance`。实例字段里的 `project_id` 改成 `entry_id`。host UI 的 `Projects` 区块改成 `Entries`。
14. 把 repl 和 host flow 测试切到 `entry` 语义。旧的 `add_project/remove_project/run_project` 路径不再作为这条线的主路径。
15. 去掉临时塞进去的 `host-ui` 默认 entry。当前代码里还没有真实 entry 来源，host 页面直接显示 `No app entries registered.`，不再用假的默认数据把模型撑起来。
16. 把 `service/repl.test.mbt`、`service/host.test.mbt` 和 `service/service.test.mbt` 改回围着空 entry 列表和 host 自己的基础 UI 做断言。host flow 里的 `test_exec` 改成直接点击 `host-stop-service`。
17. 把动作名 `run_entry` 改成 `start_instance`。对应的 action 名、命令名、按钮 `data-testid` 和相关测试一起对齐。
18. 增加源码内部注册 API `register_app_entry(id, name)`。这条 API 当前只加不删，不在 `init_app()` 里被清空。
19. 重新跑 `moon test` 和 `./scripts/test-native.ps1`。两条链都还是全绿。
20. 继续把 JS 那边 story-editor 的 `state/innerState` 语义往 MoonBit 这边对。重新看了 `../IntentDoc/dev/story-editor.js`、`../IntentDoc/dev/story/*.story.js` 和 `state.js`。确认稳定下来的核心就是业务数据和局部会话数据分开。
21. 又对着 `src/storage.mbt` 看了一遍。确认 MoonBit 这边默认值和回填规则已经落在 `Persist` 里。`data/session` 更像类型和 schema。`runtime` 留在 `view` 闭包里，不单独长槽位。
22. 把 `src` 里的第一个实际 editor 重新搭起来了。没有再走“源码侧注册 AppEntry”那条线。只在 `src/demo_editor.mbt` 里定义最小 demo editor，带 `id/name?/data/session/view`。
23. 给 `DemoData` 和 `DemoSession` 都补了 `Persist`。默认值和 schema 语义直接落回现有存储机制。`service/app.mbt` 这边继续保留 `AppEntry` 容器，只在初始化时把 `demo_editor` 包成第一个 entry。
24. 又加了一个父 editor 做组合验证。新加的 `demo_host_editor` 不在 `view` 里临时造子 editor 状态。`DemoHostData` 和 `DemoHostSession` 里直接放 `Cel[DemoData]/Cel[DemoSession]`。
25. 在父 `view` 里用了 `h((child.view)(data.get().child, session.get().child), [], [])`。这样之后，子 editor 已经能作为 `Comp` 被组合进去。子 editor 的状态也已经是父 editor 状态树的一部分。
26. 把 `DemoHostData` 和 `DemoHostSession` 的 `Persist` 收了一刀。最开始父层 `Persist` 里还顺手写死了子层默认值。这个边界不对。
27. 后面改成父层只持有 `Cel[DemoData]/Cel[DemoSession]`。缺值时统一通过子类型自己的 `Persist::unpack` 去拿默认值和旧容器复用。父层不再展开 `DemoData/DemoSession` 的内部默认规则。
28. 把 `demo` 和 `demo_host` 两个 entry 一起挂进了 `service/app.mbt` 的内建入口表里。重新跑过 `moon test` 和 `./scripts/test-native.ps1`。两条链都还是全绿。
29. 当前这版已经说明一件事：父 editor 持有子 editor 的 `data/session`。子 editor 再作为 `Comp` 被组合进去。这条模型在现有代码里能站住。
30. 当前这版也暴露出一个问题。组合点的语法噪音还是很重。主要压力还在 MoonBit 的类型系统和当前接口形状上。
## 03-30 下午
1. 给 host 页加了一个 `Current App` 区块。把当前运行实例对应的 `entry.view` 挂进 host 页面。把 `index.html` 里的连接状态条改成固定在右上角的小浮层，不再占正文版面。`moon test` 和 `./scripts/test-native.ps1`当时都还是绿的。
2. 给 CLI 补了一条 `restart` 命令。把 help 文本、`run_client_mode` 和 lifecycle 测试一起改了。host 页还临时试过自动起一个初始实例，想让页面一进来就直接看到 demo app。
3. native 回归很快开始超时。先删了 `repeat start` 和多余的 `stop` 组合，又把自动初始实例撤掉。默认 native 组还是会卡到 5 秒以上。这里先确认了一件事：问题不是测试结构自然变重，是这轮改动把原来很快的启动路径拖慢了。
4. 先修了清理脚本。`scripts/build-native.ps1` 原来对 `service` 只按 pid 文件找旧进程。pid 文件没了就会漏掉还在跑的旧 `service.exe`。这里补成了同时按二进制路径扫进程。补完以后默认 native 回归先回到过一次 5 秒预算内。这里也暴露出一个事实：前面有一段时间测试和手工命令确实可能一直在碰旧的 `service.exe`。
5. 又发现 `scripts/build-native.ps1` 在 `-Test -TestPackage service` 这种路径上只建测试产物，不保证主程序 `service.exe` 跟着重建。手动清掉 `_build/native/debug/build/service` 以后，lifecycle 测试里的`@process.spawn(service_bin(), ...)` 直接报“找不到文件”。这里把脚本改回测试前也会先 build 主程序。`service.exe` 和当前源码至少不会再明显脱节。
6. 把当前仓库里的 lifecycle 用例重新打了一轮时间。先看 `timed_meta(...)` 本身的阶段时间。再把 `read_service_port()` 和 `assert_page_ready()` 单独拆开。结果很一致。慢点不在 `read_service_port()`，也不在`assert_page_ready()`。这两段几乎都是 0~3ms。慢的地方全在 `start command/start again command/restart command` 这几个 CLI 命令本身，每次都要一秒左右。
7. 直接跑了 03-26 的旧工作树。入口还是它当时自己的 `./test-native.ps1`。旧版结果很干净。`start --silent` 只有 109ms，`repeat start --silent` 36ms，`host stop service` 93ms，`restart after host stop` 94ms。整组 native test 只要 0.77 秒。这里把边界压得很死：当前的慢启动就是后来引进的退化，不是 Windows、测试模型或者原本 lifecycle 设计天然就该这么慢。
8. 对了旧版和当前版的 process 调用方式。`launch_background_service()` 两边都是 `@process.spawn_orphan(...)`。lifecycle 测试里起 CLI 子进程的写法也还是 `@process.spawn(..., stdout=redirect_to_file(...),stderr=redirect_to_file(...))`。这条线没有关键变化。问题不在 process API 表层的调用方式。
9. 重新把当前能成立的结论单独写了一次。旧版和现在的 process 调用方式没有关键区别。旧版 `start --silent` 是 109ms。现在 `start command` 是 1100ms 左右。`wait_port()` 只花 60~70ms。`assert_page_ready()` 几乎不花时间。问题不在 process API 用法，也不在 `wait_port` 和页面 ready。当前最硬的事实只剩一件事：这轮改动里某个同步初始化路径把 `meta start` 的父 CLI 命令卡住了将近 1 秒。这个慢点还没有被定位出来。
10. 单独手工跑了 `.\meta.ps1`。`start detect_port/clear_stale/launch/wait_port` 的时间都很短。整条手工启动已经回到肉眼可接受的速度。
11. 把边界重新压了一次。手工入口快。慢点集中在 native lifecycle 测试里那条“CLI 子进程起后台 service”的链路。问题先不继续算在 `meta start` 主路径上。
12. 重新对了旧版和当前版的后台启动实现。旧版 `launch_background_service()` 会把后台 `service` 的 `stdout/stderr` 单独重定向到日志。当前版少了这层。
13. 先把这层重定向接回 `service/cli.mbt`。后台 `service` 不再直接继承父 CLI 的输出句柄。目的是先把测试链路里最可疑的句柄继承问题压掉。
14. 又把测试模型重新定了一次。`service lifecycle` 测的其实是 CLI 进程、后台 service、状态文件和端口可达性。继续放在 MoonBit async 测试里性价比很低。
15. 把 `service/service.test.mbt` 里的 lifecycle 用例从默认 `native:*` 组摘出。测试名改成了 `script: service lifecycle is idempotent`。默认 native 组先只保留其余稳定用例。
16. 新增了 `scripts/test-service-lifecycle.ps1`。脚本直接黑盒跑 `stop/start/host_stop_service/start/restart/stop`。同时保留页面 ready 检查和启动耗时预算。
17. 改了 `scripts/test-native.ps1`。现在先跑 MoonBit 的 `native:*`。再串上 `scripts/test-service-lifecycle.ps1`。这条生命周期回归以后单独由脚本负责。
18. 脚本首跑立刻撞到 `Start-Process` 参数拼接错误。`-ArgumentList` 后面直接接数组加号写法不对。当前错误是 `A positional parameter cannot be found that accepts argument '+'`。
19. 当前收下来的结论只有两条。手工 `meta` 启动链路已经快。生命周期黑盒迁脚本这条路是对的，但脚本本身还没跑通，下一笔先修这个参数错误再补验证。
## 03-30 晚上
1. 沿着下午那条慢启动问题继续往下查。先把 `samply` 录制链重新接通。`service/moon.pkg.json` 临时加 `/Z7`。录完以后再自动还原。现在仓库里有了 `scripts/profile-startup.ps1`，可以一条命令产出 `start --silent` 的 Windows profile。
2. 录完第一版 profile 以后，先碰到的不是“没有 profile”，而是“profile 里还是一堆裸地址”。后面确认问题不在 `pdb` 没生成。问题在 `samply` 默认没有把符号直接塞进 `profile.json.gz`。于是把录制脚本改成 `--unstable-presymbolicate`，再加 `--symbol-dir`。这样会额外产出 `.json.syms.json`。后面离线分析终于能看到可读函数名。
3. 把 profile 离线分析收成了脚本。最开始先写了 Python 版。后面又按要求改成 JS。现在主脚本是 `scripts/analyze-startup-profile.js`。支持 `hot`、`topdown` 和 `wait` 三种模式。路径也已经参数化，不再绑死临时文件名。
4. `hot` 和 `topdown` 两种模式先把一个边界钉死了。父 CLI 的大头时间不在业务逻辑里。主线程基本一直挂在 `main -> run_async_main -> with_event_loop -> run_forever -> poll -> wait_for_event -> moonbitlang_async_poll_wait ->GetQueuedCompletionStatusEx`。这说明它主要是在 event loop 里等事件，不是在算某个业务函数。
5. 只知道 `wait_for_event` 还不够。后面又给分析脚本补了 `wait` 模式。这个模式会按时间顺序打印主线程每次进入 `wait_for_event` 之前和之后的调用链。这样能把 profile 里的等待段和业务调用顺序对上。
6. 光看 profile 还是不知道“到底是哪个 runtime 事件”。于是又在本地 `.mooncakes/moonbitlang/async` 里加了很窄的一层 trace。只记 `run_forever`、`wait_for_event`、`handle_completed_job` 和 `perform_job_in_worker`。同时在`service/cli.mbt` 的 `start_service()` 里补了阶段锚点。trace 统一写到系统临时目录的 `metaeditor-runtime-trace.log`。
7. 这层 trace 先把一个旧猜测排掉了。之前一直怀疑是 worker/job 没收干净。trace 里最后能明确看到 `run_forever loop no_more_work=true blocking=0 ready=0 running_workers=0 timers=0`，然后立刻 `run_forever break`。所以最终退出条件本身是能归零的。
8. 但 trace 也暴露出另一个更怪的事实。卡住的那段时间里，`running_workers=0` 很常见，可 `blocking` 还大于 0，有时 `timers=1`。也就是说，拖住 event loop 的更像是 coroutine/timer 状态，不只是 worker/job。问题已经缩到 asyncruntime 的退出条件这层了。
9. 生产路径也顺手试了几刀错误方向。先把 Windows 的后台启动从 `@process.spawn_orphan(...)` 改成了自写 `CreateProcessW`。整组 `test-native` 基本没变，还是 `start command ~1100ms`。这说明问题不在“后台 service 怎么起”这一刀本身。
10. 还试过把 `service.test.mbt` 里外层起 CLI 的方式换成自写 `CreateProcessW`。结果也没变。这个实验把另一条怀疑排掉了。问题不在测试外层怎么起 CLI。真正慢的是 CLI 进程内部自己的收尾路径。
11. 又试了把 `wait_port()` 里的 `call_at("status")` 换成同步端口探活 FFI，想绕开 async HTTP client。结果更糟。`start command` 直接涨到 `1.2s ~ 1.8s`，整组 native test 还超了 5 秒。这里把另一条怀疑也排掉了：问题不在`wait_port()` 的 HTTP 探活本身。
12. 到这里能收下来的状态比较清楚。当前最硬的结论有三条。第一，慢点不在业务初始化。第二，慢点也不在 `wait_port()` 或页面 ready。第三，问题已经压到 `moonbitlang/async` 的 event loop 退出条件，重点是 `blocking/ready/timers`这组状态如何归零。
13. 最后把这轮调查整理成了单独文档 `doc/startup-slowdown-investigation-2026-03-30.md`。文档里写了已经验证过的事实，试错过的方向，当前脚本怎么跑，以及本地 `.mooncakes/moonbitlang/async` 只改了哪两个文件。也把回退方法写清楚了：可以直接删项目里的 `.mooncakes/moonbitlang/async` 和对应 `_build` 产物，再重新 build，让依赖重新拉回正常版。
14. 先回头看了 `doc/startup-slowdown-investigation-2026-03-30.md`，把已经成立的前提重新压了一遍，确认旧版 `start --silent` 约 `109ms`、当前版约 `1100ms`、`wait_port()` 一直只有 `50~90ms`、`assert_page_ready()` 也一直很快，外层怎么起 CLI 和把 `wait_port()` 改成同步端口探活这两条线都已经试过，而且都不是主因。
15. 然后回到现成 profile，把 `scripts/analyze-startup-profile.js` 的 `hot`、`topdown` 和 `wait` 三种模式重新都跑了一遍，确认父 CLI 和后台 service 的主线程都长期停在 `run_async_main -> with_event_loop -> run_forever -> poll ->wait_for_event -> GetQueuedCompletionStatusEx`，问题形态还是 event loop 在等，不是某个业务函数在算。
16. 光看 profile 还不够，又继续去对 runtime trace，重新对齐 `service/cli.mbt` 和 `.mooncakes` 里的 trace 点，再去看 `%TEMP%\\metaeditor-runtime-trace.log`，先确认退出时那些 `blocking/ready/running_workers/timers` 最终是能归零的，所以不是彻底退不掉，而是中间有一段等待链把 event loop 拖住了。
17. 到这一步还是没压到具体代码，于是换了调查方法，为了让后面每次改一小块都能用同一套入口稳定复测，先补了 `scripts/time-startup.ps1`，脚本默认先重编译，再用独立 `state-dir` 跑一次 `start --silent`，最后自动 `stop` 并清理状态。
18. 有了这条脚本以后，开始直接对 `service/cli.mbt` 里的 `start_service()` 做最小回退，先把整个函数体清空，启动时间立刻掉到三百毫秒左右，这一步先把边界压死到 `start_service()` 函数体内部。
19. 接着把 `detect_port()`、`clear_stale_service_state()`、`launch_background_service()`、`wait_port()` 一项一项加回去，每次都重新 build 再跑 `scripts/time-startup.ps1`，结果都没有把时间重新打回一秒级，这说明真正的启动主路径本身没有问题。
21. 再往里拆时，把 `trace_runtime(...)`、`log_timing(...)`、`stdout.write(...)` 和两处 `if !silent ... wait_browser_connected_at(...)` 分开测，前面三类单独加回去都还在一百毫秒上下，真正可疑的只剩那两处条件表达式。
22. 先恢复 `Some(running_port)` 分支里的那一处 `if !silent && !wait_browser_connected_at(...)`，`start --silent` 还是快的，再恢复 `None` 分支里的那一处，也就是实际启动成功以后走的分支，时间立刻重新稳定回到 `1090ms ~ 1185ms`，问题第一次被压到一行具体代码。
23. 后面又做了最关键的对照，把慢的写法 `if !silent && !wait_browser_connected_at(running_port, 800) { ... }` 改成等价的嵌套 `if`，也就是 `if !silent { if !wait_browser_connected_at(running_port, 800) { ... } }`，再连跑五次，时间又回到 `87ms ~ 103ms`，这一步把结论钉死了，当前测的是 `start --silent`，`open_browser()` 根本不会真的被调用，真正触发慢点的是 `if !silent && async_call(...)` 这种代码形态本身。
24. 顺着这个结果，把结论重新写回 `doc/startup-slowdown-investigation-2026-03-30.md`，文档里补了触发慢点的具体代码、等价但不慢的写法、对照实验过程和测量结果，后面又把修复现场的 commit `a05cc8b fix(service): correct slow startupcaused by conditional expression` 也记进文档，方便后面拿这个状态做最小复现和报 bug。
25. 文档补完以后，又按用户要求开始清理调查过程中引进代码里的冗余，先回看最近几次提交，确认这轮调查大体是从 `4af109d perf(windows): optimize service startup time and add profiling tools` 开始的，然后拿 `6ff2874` 当调查前的代码基线，重新区分“真正修复”和“调查期临时产物”。
26. 重新对完边界以后，口径最后收成两条，脚本和文档保留，代码里的调查残留全部清掉，于是 `service/cli.mbt` 只保留嵌套 `if` 这个真正的修复，不再保留 trace FFI、trace 调用、注释掉的慢写法和临时 `ignore(...)`，`service/service.test.mbt` 里为排查外层启动方式补的 Windows 原生 `CreateProcessW` 辅助全部拿掉，`service/stub.c` 里 runtime trace、test spawn/wait/free、端口探活和那批额外辅助也一起删掉。
27. `.mooncakes` 这边没有继续手抠，直接按调查文档里已经写好的回退办法，把 `.mooncakes/moonbitlang/async` 和 `_build` 整个删掉，再重新 build，重建以后再搜那些 trace 标记，已经全部消失，这样把本地依赖内容也重新拉回了正常版，不再留调查残留。
28. 最后重新检查工作区，只剩代码里真正该提交的三处变化：`service/cli.mbt` 保留嵌套 `if` 修复，`service/service.test.mbt` 清掉 Windows 调查辅助，`service/stub.c` 清掉 trace 和 test 辅助，脚本和文档都按前面的判断保留，到这里，这轮慢启动调查才真正收住，问题已经压到一行代码形态，修复和清理边界也都已经定死了。
## 03-31 上午
1. 先写了一版 `src/uitest.mbt` 和配套 demo 测试，想把 `mount/click/text 查询` 这些固定流程压成更短的测试写法。
2. 后面很快确认这条线不对，因为它在测试层重复维护了一份 DOM 语义，继续往下做只会把 runtime 和测试一起搞乱，于是把 `src/uitest.mbt` 和依赖它的 demo 测试又删掉了。
3. 把 DOM 白盒测试主路径收回到 `realize/get_cmds/flush`，因为这几条已经是 `dom.mbt` 自己的能力，不需要再包一层新的测试 runtime。
4. 把稳定节点标识统一改成 `ui-id`，因为 `data-testid` 只会把这件事带偏成测试专用属性，而这里真正需要的是正式的运行时定位标识。
5. 把事件分发从 `cb_id` 改成 `ui-id + 事件名`，因为 callback 编号只是内部实现细节，测试、bridge 和后面的自动化操作都不该围着它打转。
6. 把浏览器 bridge、host 自动化和事件回传一起切到 `ui-id`，因为这几条链本来就在做同一种节点定位和交互，不该再维持两套入口。
7. 把 `service/app.mbt` 和 `src/demo_editor.mbt` 里的 `data-testid` 全部换成 `ui-id`，让 host 和 demo editor 都开始走同一套稳定定位语义。
8. 把 `dom/reactive/storage/history` 白盒测试从 `test/` 搬回 `src/`，因为这批测试本来就在测内部实现，放回源码包以后少一层 `@lib` 包装，也少一份单独测试包配置。
9. 把 DOM 白盒测试里的事件驱动写法改成直接 `click('ui-id')` 和 `trigger_ui_ev(...)`，因为既然运行时已经开始认 `ui-id`，测试就不该继续手扫 callback handle。
10. 修掉 `Dyn` 重渲染时同 `ui-id` 新节点事件槽被旧节点清理误删的问题，因为这个回归会直接让 demo todo 的 toggle 和 host 里的 stop 这类交互在第二次点击时失效。
11. 删掉 `scripts/build-native.ps1` 里的 `-NoParallelize` 和对应拼参，因为这条旧参数已经不该再出现在当前测试主路径里。
12. 重新跑 `moon test`、`./scripts/test-native.ps1` 和 `host.test.mbt`，确认 DOM 事件重做、白盒测试迁移和脚本清理没有把现有链路打坏。
## 03-31 下午
1. 继续往下收 `ui-id` 这条线时，先把“节点自己的 `ui-id`”和“查询路径”重新拆开讲清楚了。这里确认`ui-id` 只表示当前作用域里的局部名。路径拼接只属于查询层，不该提前展开成完整字符串。
2. 顺着这个判断，把普通组件的作用域语义重新压了一遍。组件默认只负责复用 render。组件本身不默认带名称域，也不默认带 reactive scope。需要边界时才显式开。
3. 重新看了 `src/reactive.mbt` 和 `src/dom.mbt`，确认当前代码里其实有两条清理路径。`D(...)` 和`Dyn(...)` 自己把 stop 塞进 `VNode.clrs`。组件里手写的 `effect(...)` 则挂在外层 reactive `scope`上。这里先把现状讲清楚，避免后面继续混着改。
4. 后面没有把 reactive 和 DOM 硬绑死。改成在 `reactive.mbt` 里补底层 scope 句柄能力，让 `scope(f)`反过来建立在 `new_scope/with_scope/stop_scope` 这组更底层 API 上。这样 `scoped(...)` 只是复用已有 reactive 机制，不再偷偷走一套 DOM 私货。
5. 在 `src/dom.mbt` 里补了第一版 `scoped(comp, name=?, reactive=?)`。这条 API 只收 `Comp`。`name`用来给组件实例显式开名称域。`reactive=true` 用来给这个组件实例单独挂一份 reactive scope，并且 stop继续由 runtime 自动管理。
6. 给 `src/dom.test.mbt` 补了普通组件相关测试。先测组件根命名，再测 `reactive=true` 的 scope 会在节点移除时自动 stop，又补了“只有 `name` 没有 `reactive` 时，组件里的手写 effect 仍然挂外层 scope”这条边界。
7. 这里中间还撞到一个实现口径问题。`scoped(name=...)` 和显式传入的 `ui-id` 冲突时，最开始写成了`abort`。这条不对，因为它不是不可恢复错误。后面改成显式 `ui-id` 优先，`scoped` 自己退让，同时把行为补进测试。
8. 回头看 `reactive.mbt` 时，把 `computed/watch/watch_raw` 一起删掉了。仓库里没有生产代码在用这三个 API。它们的语义也更偏通用响应图系统，不贴当前这套以 UI 运行边界为中心的模型。对应测试也一起删掉。
9. 为了少跑两轮命令，补了 `scripts/test-all.ps1`。脚本现在只串两条主链：先 `moon test`，再跑 `./scripts/test-native.ps1`。后面这条成了这轮改动的统一验证入口。
10. 普通组件的名称域继续往下落时，在 `VNode` 上补了 `scope_names`。这张表只挂在显式名称域宿主上，存当前域内的局部名字。普通节点不带这张表。后面又把它从 `Ref` 收成普通可选值，因为这层数据是在构造时一次性算出的，不该伪装成可变状态。
11. 接着把普通组件的查询主路径接上了。`click('scope/child')` 和浏览器事件回传这条线不再只靠平的 `ui-id` 字符串，而是先按作用域路径解析，再落到具体节点 id。bridge 也一起改成浏览器事件优先回传节点 id，service 侧优先按节点 id 分发。
12. 继续讨论列表时，把列表域和名称域彻底分开了。列表域不是名称域，也不该绑死在 `h_map` 这个 helper上。最后收成统一用 `scoped(..., list=true)` 表达列表域。列表域自己有名字。查询进入以后，下一段按列表规则解释。
13. 按这套设计在 `VNode` 上补了 `list_items`，让 `scoped(..., list=true)` 先支持静态列表的 `todos/0/toggle` 这种路径。这里先补的是静态主路径，不急着先把 `h_map` 一起写重。
14. 后面继续把 `Dyn` 的锚点接成动态列表宿主，让动态列表项的当前入口也能被查询层看见。顺着这一步再把`h_map` 默认接到列表域语义上，让 helper 自己跟主设计对齐，不再额外发明平行规则。
15. 给列表域补测试时，先把静态 `list=true` 的路径测通了。再补 `h_map` 的多节点项查询测试，结果第一次直接把真实缺口打了出来：整项的局部名字表还没有真正挂到“该项的第一个节点”上。
16. 顺着这个失败点继续往里修，最后把 `h_map` 每一项的名字表单独挂到该项第一个节点上，不再复用会补空文本宿主的那条 `wrap_scoped_child(..., attach_names=true)` 路径。这样多节点项的 `todos/0/toggle` 才真正能命中，而且 `Null`、空数组和 `Dyn` 项也不会平白长出幽灵 text 节点。
17. review 又把这条线上的两个回归指出来了。第一条是 `list=true` 会把同层固定命名节点一起吃掉，让`todos/add` 这种路径失效。第二条是前一版 `h_map` 给空项补出了额外 text 节点。这里后面都按最小补丁修了：查询先试同层固定名字，再退到列表 index；`h_map` 项名字表的挂载也改成只落到该项第一个节点。
18. 最后重新用 `./scripts/test-all.ps1` 把整条链重新跑了一遍。`moon test` 回到 `73 passed`。native主链回到 `22 passed`。到这里，这次 `ui-id` 相关的普通组件名称域、列表域、`h_map` 默认列表项查询和review 提到的两处回归都一起收住了。
## 03-31 晚上
1. 重新收了一遍 `ui-id` 这条线的设计目标。把“稳定定位”和“按 `id` 外挂 prop”分开想。确认前者已经站住。后者如果想做满，会碰到闭包局部状态和动态绑定这层硬边界。
2. 先把样式单独拎出来讨论。确认样式和普通 prop 不一样。样式天然适合走浏览器现成机制。没必要继续在runtime 里发明一层复杂的挂载协议。
3. 把样式方案压成最简单的一条。节点继续保留 `ui-id` 作为稳定锚点。样式侧改成走 CSS。单点样式可以围着`ui-id` 写选择器。列表样式直接交给结构选择器，不把列表位置语义硬塞回 `ui-id`。
4. 顺着这条线把列表边界也重新讲清楚。列表项样式默认依赖 DOM 结构和 CSS 选择器。只有项内需要稳定单点命中的节点，才继续保留自己的 `ui-id`。这样 `ui-id` 继续只表达稳定语义名，不掺位置语义。
5. 最后把“prop 全走 id 挂载”这件事收成了更现实的口径。样式可以外挂。普通 prop 很难完整外挂。只要prop 依赖组件内部闭包、局部状态、`Dyn` 或 `h_map` 项，外部就不可能随便接管。
6. 真正能稳定暴露这类能力的单位，只能是显式设计过的 component 边界。这样 DOM 树仍然可以尽量保持纯结构，但可配置语义要通过component 接口暴露，不能指望任意节点都能按 `id` 挂任意 prop。
7. 又回头看了 `scoped` 这条线的形态。现在的 `scoped(comp, name=?, reactive=?, list=?)` 虽然已经能工作，但越看越像是在给组件实例附加一组额外属性。后面值得继续想一笔：它里面到底哪些语义应该继续保留成专门的实例包装，哪些更适合并回 attrs 这条分发路径。这个问题先只记下来，还没有定结论。
## 04-01 上午
1. 先把 scoped 从对外 API 收掉。组件实例语义改成统一走 h(tag, attrs, children)。
2. 定了新的属性口径。只保留 ui-id、ui-name、ui-react、ui-list。其中 ui-id 是唯一名字来源，另外三个只表达宿主语义。
3. 改了 src/dom.mbt。删掉 ScopedSpec/Prop::Scoped/scoped_prop/scoped/take_scoped/render_comp 这条旧入口。
4. 把 h(...) 改成先解析 ui-name/ui-react/ui-list，元素和组件共用同一套宿主包装逻辑。
5. 补了约束。ui-name 和 ui-list 没有 ui-id 会直接报错，避免名字来源分叉。
6. 把 src/dom.test.mbt 整体改到新属性写法。原来依赖 scoped(...) 的测试都改成直接写 ui-* attrs。
7. 额外补了普通元素路径的覆盖，确认元素和组件都能走 ui-name。
8. 跑了 moon test，确认新主线下 74 passed。
9. 跑了 ./scripts/test-all.ps1，确认整条验证链通过，结果是 moon test 74 passed、native 22 passed。
10. 后面又继续收实现细节，把 attach_stop/attach_names/attach_list 三个并行参数合成一个三元组 flags。
11. 同时把 child 宿主包装函数压成 attach(child, handle, flags)，减少重复传参和首项递减的样板代码。
12. 重新跑 moon test，确认这一步整理以后还是 74 passed。
## 04-01 下午
1. 先读了 ../devlog.md 末尾 200 行，重新对齐 dom 样式这条线的旧口径，确认前面已经把“样式优先走 CSS、ui-id 继续做稳定锚点”说清楚了。
2. 继续读了 ./src/dom.mbt、./src/dom.test.mbt、./src/bridge.js和 ./service/app.mbt，确认仓库里还在大量用整串 style，同时 SetStyle/RemoveStyle 的 bridge 路径已经存在。
3. 先把样式能力补成第一版。给 dom 加了 SetCss/RemoveCss，bridge 侧加了 <style> 节点维护。保留原来的整串 style。同时补了 style:prop 入口，让单个 style property 也能走 S(...)/D(...)。
4. 第一版里顺手做了 ui-id -> class 自动派生，还补了一批相关测试。中间因为 class 自动插入改变了命令顺序，测试口径也跟着改成了更稳的存在性断言。
5. 用户继续把样式口径压窄以后，又把第一版方案收了一次。去掉了丑的 ui__ 前缀，把派生 class 改成局部短名。style:prop 也改成明确走 CSS 属性名，bridge 侧从 node.style[k] = v 改成了setProperty/removeProperty。
6. 按用户最后定的方式，把 css(key, text) 收成了自动作用域前缀版本。普通规则会自动展开成 .key ...。同时把 @media、@supports、@container、@layer 这些块内规则也接到了同一套前缀逻辑上。
7. 为了少留重复样板，把 css_scope_block(...) 里反复写的 { header/body } 输出提成了小 helper，减掉了那几段很难看的重复拼接。
8. 然后开始收 dom 测试外围工具。参考用户在上一级工作树里的整理方式，新建了 ./src/dom_helper.mbt，把测试用 DomState、查找函数和基础断言从 ./src/dom.test.mbt 顶部拆了出去。
9. 拆完以后继续给 ./src/dom_helper.mbt 加了块注释，把内容按“测试状态/命令匹配/通用断言/命令断言/DOM 外围样式工具”分段，方便后面继续收。
10. 又把 ./src/dom.mbt 里那批纯外围的样式字符串 helper 也搬到了 ./src/dom_helper.mbt，让 dom.mbt 本体少留一批和运行时状态机没直接关系的小函数。
11. 之后继续收测试断言，先把很多零散的 cmds.any(...)、样式命令断言、CSS 命令断言、JSON 断言改成 helper 调用，减少测试里一段段重复 match cmd。
12. 再往后把命令断言统一成一条主入口。先做了一版 CmdPattern，把 SetStyle、RemoveStyle、SetCss、RemoveCss、HostCmd 这些匹配分支集中到一处。后面又继续把 Attr/Append/Listen/UpdateAttr /Remove/Text 一起并进去，把旧的 assert_create/assert_attr/assert_append/assert_listen /assert_update_attr/assert_text 这一整批平行命令断言删掉。
13. 在这个过程中，中间还补了 assert_cmd_id(...)，因为测试里一部分地方既要校验 Create 形状，又要把生成出来的节点 id 拿出来给后面的 Append 继续用。这个 helper 当时是为了把那些裸 match cmds[i]{ Create(id, _, _) => id ... } 收掉。
14. 继续往下想以后，又把“为什么 DomCmd 和测试模式看起来这么像”这件事真的落到代码里。先把 ./src/dom.mbt 里的命令骨架改成了泛型 Cmd[I, S]，然后把 DomCmd 收成 Cmd[Int, String]，同时把 JSON 输出改成普通函数 dom_cmd_to_json(...)。
15. 最后把测试 matcher 也真正换到共享骨架这条路上。删掉了之前那套平行 CmdPattern，在 ./src/dom_helper.mbt 里补了 Pat[T]、CmdPat = Cmd[Pat[Int],Pat[String]]、MatchEnv、v(...)、any()、id(...)、assert_cmd、assert_has_cmd、assert_cmds，让测试的“部分匹配”和“绑定变量”开始走同一套机制。
16. 把 ./src/dom.test.mbt 里一批代表性测试切到了这套新matcher 上。最开始四个基础 DOM 命令测试、ui-name 相关测试、ui-react null、h_map 文本断言、样式命令断言、CSS 规则断言、事件命令断言、host 命令断言都已经改到 Pat + CmdPat + MatchEnv 这条路上。
17. 这套迁移中间踩了几处小口径。先是 Create(..., "") 原来在旧 helper 里其实代表“不检查 namespace”，后来把这些位置改成了 any()。接着又把 UpdateAttr 少传的 id 模式补成了 UpdateAttr(any(), ...)。最后ui-name can name component root 这个测试因为命令顺序不是完全线性的，又把它收成了“前两条走严格顺序，剩下几条按存在性匹配”的混合写法。
18. 继续清理 `dom.test`。先读了 `../devlog.md` 末尾 200 行。再对了一遍 `src/dom.test.mbt` 和 `src/dom_helper.mbt`。确认前半段很多测试已经迁到 `Pat + CmdPat + MatchEnv`。后半段还混着老 helper 和裸 `match/filter`。
19. 把后半段残余断言继续收掉。重点是 `h_map` 那组回归。也顺手收了 `Dyn` 的 `InsertBefore` 断言。`ui-name can name component root` 里零散的 id 查找也一起改了。目标很直接。测试断言只保留一条主路径。
20. 在 `src/dom_helper.mbt` 里补了 `find_cmd`、`count_cmds` 和基于 `CmdPat` 的 `assert_no_cmd`。这样“找一条命令”、“统计命令”、“断言某条命令不存在”都开始走 matcher。测试里不再需要继续手写一层 `find_text_node_id / find_parent_id / is_remove / is_create / is_insert_before` 这种平行工具。
21. 把 `src/dom.test.mbt` 后半段原来依赖老 helper 的地方都迁到了新 helper。删掉了那批已经没有调用的老谓词 helper。`dom.test` 里剩下的命令断言入口重新压回 `assert_cmd / assert_cmds / assert_has_cmd / assert_no_cmd / find_cmd / count_cmds` 这一组。
## 04-01 晚上
1. 继续收紧 `dom.test.mbt` 的测试 DSL。先回看了 `dom_helper.mbt` 里的匹配器和断言入口。确认单条命令这层已经够紧。重复主要在三处。多条命令关系断言太散。`scope/flush` 的报错样板太多。`Text -> Append -> parent id` 的链式提取反复出现。
2. 先给多条命令关系断言补了新 helper。最开始叫 `assert_has_cmds`。内部用了回溯匹配。每条命令只能消费一次。这样重复形状的命令不会把同一条实际命令误配两次。先拿 `ui-name can name component root` 试改。验证这类 helper 确实能把一组相关断言收成一坨。
3. 补了 `no_raise`、`test_scope`、`flush_cmds`。这组 helper 只做测试侧包装。把 `scope(...) catch { panic }` 和 `flush() catch { panic }` 的重复样板统一掉。`flush_cmds` 额外顺手取走当前批次的命令，保持之前测试里的使用习惯。
4. 补了 `find_text_mount`。它直接从命令流里取出某段文本对应的文本节点 id 和父节点 id。这样 `h_map` 那几组测试里不用再先 `find_cmd(Text(...))`，再 `find_cmd(Append(...))` 连着跳两次。
5. 把 `dom.test.mbt` 里能直接受益的用例都切到了新 helper。`h_map` 相关测试大量改成 `find_text_mount`。响应式相关测试大量改成 `test_scope` 和 `flush_cmds`。`ui-name` 和几组多命令存在性断言改成新的多命令 helper。测试逻辑没变，只收掉了重复样板。
6. 讨论命名后，把 `assert_has_cmds` 改名成了 `assert_match_cmds`。又补了 `assert_prefix_cmds`。它只检查命令前缀，顺序固定。先把最适合的那组前缀断言切了过去。
7. 继续讨论断言强度时，确认 `match` 这层语义太宽。于是又补了 `assert_ordered_cmds`，表示“顺序固定，但允许中间夹别的命令”。同时把 `assert_match_cmds` 再改名成 `assert_unordered_cmds`。最后 helper 分成三层。`assert_prefix_cmds` 负责前缀。`assert_ordered_cmds` 负责有序子序列。`assert_unordered_cmds` 负责无序子集。
8. 中间试过把 `ui-name can name component root` 切到 `assert_ordered_cmds`。测试直接失败。说明这组命令在当前实现里并没有稳定到能承诺那种顺序。于是改回 `assert_unordered_cmds`。`assert_ordered_cmds` 先落在 `host command` 这种顺序语义更明确的场景上，避免把断言写得比实现实际保证更强。
9. 顺手处理了新 helper 引入的两条 deprecated syntax warning。把 `test_scope(fn() { ... })` 这类写法改成了箭头函数版本。保持测试输出干净。
10. 继续讨论测试 DSL 的失败语义。先确认 MoonBit 内置 `assert` 放进 helper 里会把 `raise` 传出来。这样一来，`dom_helper.mbt` 这一层的签名会被整片污染。调用点也要跟着补 `raise` 或额外包装。最后没有继续往这个方向改。
11. 顺着这个问题，把 `raise`、`panic`、`abort` 的语义分层梳理了一遍。`raise` 归到业务失败和 effect。它应该进函数类型。`panic` 归到断言失败。适合测试里“失败直接停”的场景。`abort` 归到逻辑上不该到达的分支。适合表达内部假设被打破。
12. 基于这个分层，重新确认测试 DSL 继续自己 `panic()` 是合理的。因为 `assert_cmd`、`assert_prefix_cmds`、`assert_ordered_cmds`、`assert_unordered_cmds` 这类 helper 要表达的是“断言失败直接结束当前测试”，不是“把失败作为可组合 effect 往外传”。最后保留了外层测试继续用原生 `assert_eq`、`assert_true`，DSL helper 内部继续 `panic()` 的分工。
13. 读了 `../pretext-main` 的目录、核心源码和验证脚本。重点看了 `prepare -> layout` 这条主路径。确认它现在收的是浏览器内的段落测量与断行，不是完整编辑器文本引擎。
14. 回头对了 `doc/legacy` 里几份最相关的旧文档。主要是 `text-measuring.md`、`text-roadmap.md` 和 `text-v1.md`。确认这套路线和 MetaEditor 之前定过的第一阶段方向很接近。都把 `Intl.Segmenter`、`measureText`、wrap 和 browser oracle 放在前面。
15. 顺着这次对照，把两个关键边界单独讲清楚了。一个是 `pretext` 的“少量 DOM 校准”只是在 emoji 宽度修正时做一次可缓存的 DOM 读数，不会把 DOM 带回热路径。另一个是单段多字体会很快把问题抬到 run 级模型，不能继续把整段当成单一 font 文本处理。
16. 最后把这次分析整理成了 `doc/legacy/pretext-notes.md`。文档把 `pretext` 的主路径、它和 MetaEditor 文本路线对得上的地方、这条路最好能做到哪里、以及多字体和更深文本真相的边界一起记下来了。后面再讨论这条线时，可以直接围着这份笔记继续收。
17. 看了 `../mbt-skills` 的结构和 README。确认它是一个 skill 聚合仓库。里面有多组可单独安装的 skill 目录。
18. 读了内置 `skill-installer` 的说明。确认它做的事情就是把 skill 目录装到 `~/.codex/skills`。用户这边已经有本地仓库，所以直接复制目录更短，也更容易回退。
19. 检查了 `C:\Users\ch3coohlink\.codex\skills`。当时只有内置 `.system`。还没有装 MoonBit 相关 skill。
20. 枚举了 `../mbt-skills` 里实际可安装的 `SKILL.md`。确认这次要装的目标有 `moonbit-lang`、`moonbit-c-binding`、`moonbit-spec-test-development`、`moonbit-extract-spec-test`、`moonbit-agent-guide`、`moonbit-refactoring`。
21. 直接把这 6 个 skill 从本地仓库复制到 `C:\Users\ch3coohlink\.codex\skills`。安装完成后又核对了一遍目录，确认都已经到位。
22. 抽查了几个新装 skill 的 `SKILL.md` 开头。把它们各自的触发条件过了一遍。确认它们主要覆盖 MoonBit 语法、FFI、项目结构、重构、spec 和测试这些场景。
23. 把 skill 里的工作流和当前仓库 `AGENTS.md` 对了一遍。确认会有局部张力，比如有的 skill 会建议跑 `moon fmt`，有的 skill 会更积极地整理结构。但冲突时还是以仓库规则为准。
24. 排查了 `moon ide` 在当前 Windows 环境下的报错。复现到它会把路径处理成 `\\D:\\...` 去 `stat`。这个现象发生在读源码之前，所以判断它不像行尾问题，更像工具自己的 Windows 路径处理问题。
25. 继续在 PowerShell 下做了最小复现。确认 `moon ide outline .` 和 `moon ide outline src` 都会稳定打到同一类 `ENOENT`。
26. 试了 Git Bash 这条路。确认 `moon ide doc` 这类查询可以正常返回结果。`outline` 这类带路径的子命令还是会继续撞上同一个 Windows 路径问题。
27. 在 PowerShell profile 里补了一个 `gitbash` 函数。这个函数只做一件事，就是从 `pwsh` 直接打开项目目录下的 Git Bash，方便以后手动切环境。
28. 在项目根目录新增了 `mide.ps1`。这个脚本负责从 PowerShell 转到 Git Bash，再执行 `moon ide`，给当前仓库留一条固定入口。
29. 中间修了 `mide.ps1` 的参数转义和环境探测。最开始那版写死了用户目录，也有路径推导错误。后面把它收成了更短的版本。
30. 最终把 `mide.ps1` 调整成不写死用户名路径。脚本会优先根据 `git.exe` 查 Git Bash，再退回常见安装位置。`moon` 也不再写死路径，直接走 Git Bash 自己的 `PATH`。
31. 最后验证了 `.\mide.ps1 doc String`。确认这条查询能正常返回结果。这样至少把 `moon ide` 里可用的查询路径在当前仓库固定下来了。
## 04-02 上午
1. 先把 host 从旧的 `Current App / Entries / Instances` 三段式页面改成桌面窗口模型。顶栏、桌面图标、窗口层先落出来。`entry` 改成实例工厂。多个窗口共享同一份 editor 状态的问题先修掉了。
2. 又把普通页面右上角那条静态连接状态条重新收了一次。最后定成普通页面继续保留初始状态提示。host 一接管就直接清空 `body`。不再保留平行状态 UI。
3. 开始补浏览器黑盒测试。加了 `package.json` 和 `playwright` 依赖。做了 `scripts/test-browser.js` 和 host 双击测试。浏览器测试走独立 `state-dir` 和端口。
4. 中间先撞到测试环境问题。最开始 `meta` 启动超时判断写错了。等的是错误的进程结束信号。后面改成按正确退出时机收命令输出。再往后又撞到固定端口和已有 service/session 冲突。最后改成解析真实启动端口。
5. 又顺着双击打不开继续查。先用浏览器黑盒和一次性实验脚本把链路压实。确认浏览器原生确实会发 `click -> click -> dblclick`。也确认 bridge 会把 `onclick -> onclick -> ondblclick` 发回 service。
6. 接着把真正的 bug 定位出来。第一次单击已经触发 service 重渲染。entry 根节点的运行时 `id` 已经过期。后面的 `ondblclick` 如果还带旧 `id`，service 会优先按过期节点分发。结果打空。这里把 bridge 改成原生 `dblclick` 只发 `ui_id`。不再带旧 `id`。
7. 顺手又给 bridge 和 service 补了一条浏览器到 meta 的延迟测量。service 侧回 `bridge:ping / bridge:pong`。浏览器侧定时发 ping。算 round-trip latency。host 顶栏托盘里新增了延迟显示。
8. 再回头收浏览器测试结构。输出压成只报总结果和总耗时。事件实验和稳定回归分开。后面又把 host 的事件序列检查和开窗检查合到同一个 `describe` 里。避免跨套件串页面状态。
9. 然后继续追这次 bug 更深一层的原因。通过浏览器实验、DOM 命令和代码阅读确认：普通 `Dyn` 当前还是重建型更新。只有 `h_map/h_map_dyn` 这类路径有明确的节点复用语义。普通 `Dyn(fn() { h(...) })` 在 rerender 时会重新生成节点身份。
10. 最后没有直接先去重写 `Dyn`。先把 host 改回符合现有语义的写法。`desktop_entry_item`、窗口按钮、窗口壳这些从外层 `Dyn` 改成稳定根节点。选中态、焦点态只放进 `D(...)` 更新样式。这样 host 这条路径已经回到“单击选中不换根节点身份”的语义。
11. 最后重新验证了三条链。浏览器黑盒通过。`moon test` 通过。`test-native` 通过。到这里，双击开窗这条实际 bug 已经修通。普通 `Dyn` 还没有通用的节点保留语义，这件事已经明确压成后续要继续正面处理的 runtime 设计问题。
## 04-02 下午
1. 继续深入调查了 `Dyn` 相关的问题，普通 `Dyn` 当前还没有通用的节点续用语义。`Dyn(fn() { h(...) })` 和 `Dyn(fn() { Str(...) })` 在 rerender 时会重新生成 fresh child。对应的 `VNode.id` 会变。旧节点会被删掉。
2. `../IntentDoc/dev/ui.js` 里的普通动态块也没有凭空保留 fresh DOM 节点身份的能力。每次返回新的 DOM 节点时，原实现也不会自动把它续到旧节点上。想把这种 fresh 节点接回旧身份，需要结构化比较。
3. `h_map/h_map_dyn` 已经具备稳定节点身份语义。它真正复用的是 `freeze_child(...)` 产出的稳定 `Child`。外层 `Dyn` 拿到这些稳定 child 以后，会再次 realize 出同一个 `VNode.id`。因此保留项可以移动，可以保留 listener，只删缺失项。
4. 当前 runtime 已经能吃“带稳定身份的 `Child`”。只要 `Dyn` 的输出里有这种 child，`VNode` 就能沿着已有 `id` 继续活下去。真正缺的是普通 `Dyn` 默认产出的 fresh child 没有稳定身份。
5. `h_map` 保住的是列表项顶层那批 frozen child 的 `VNode.id`。如果列表项内部再套普通 `Dyn(fn() { ...fresh child... })`，那块内部子树的 `id` 目前还是会抖。
6. host app 那次 bug 的根因已经明确。单击选中本来只是样式变化，却被写成了外层 `Dyn(fn() { h(...) })` 去替换整个节点。这样会把根节点运行时 `id` 一起换掉。对 click / dblclick 这类连续交互很危险。
7. host 这类场景更合理的写法是稳定根节点加 `D(...)` 更新样式或属性。根节点身份应当连续存在。只有结构真的变了，才应该替换节点。
8. 先围着 host 里 Dyn 和样式那条线继续追，回看了 devlog 后半段和当前 service/app.mbt，确认之前已经把“只改样式却换整节点”这类 host 写法收回到稳定根节点 + D(...)。
9. 接着顺着用户指出的问题去查当前仓库里还在不在“按 ui-id 找当前节点再分发事件”这条错误路径。定位到service/bridge.mbt 的 handle_event(...) 还保留了 ui_id -> trigger_ui(...) 的回退分发，src/bridge.js里的 dblclick 也只发 ui_id 不发真实 id。
10. 中间一度把 src/dom.mbt 里的 click/trigger_ui/resolve_ui_query 这套测试辅助也一起删了，结果把一批dom.test 直接打编译错误。这里后面停住，没有继续顺手把测试全改绿。
11. 用户指出 click(...) 的语义本身没问题，我重新对齐后确认这次该删的只是生产桥接层那条 ui_id 回退分发，不该把测试查询辅助一起砍掉。
12. 用户手工回退以后，又重新按当前工作区检查了一遍，只保留“生产事件分发不再靠 ui_id 回查当前节点”和“dblclick 回传真实 id”这两个改动方向。
13. 之后跑了 scripts/test-all.ps1，发现当前整组 native 并不是 host UI 本体炸了，而是 host flow 那条 native 测试会卡成 5 秒超时。
14. 为了压清楚坏点，专门新建了一个临时 worktree，逐版回跑最近几版 scripts/test-native.ps1。最后确认：85e6b07 还是好的，109374b 开始坏；坏点正好是 service/bridge.mbt 里删掉 ui_id 回退分发的那个提交。
15. 再回到当前工作区对实现和测试本体，确认现在生产代码已经只认事件里的真实 id，但 service/host.test.mbt 还在发只带 ui_id 的 ondblclick 事件，所以这条测试不是正常 fail，而是一直等不到后续batch，最后被外层脚本杀成 timeout。
16. 最后只改了 service/host.test.mbt。一方面把 ondblclick 测试事件改成先从初始 batch 里取真实节点 id再发；另一方面给 ws.recv()、recv_flow_request(...)、query_q.get()、exec_q.get() 这些等待点统一包了1200ms 超时，确保后面即使协议再脱节，也会在测试内部明确 fail，不再无限挂成外层 timeout。
17. 后面又按用户的要求把 worktree 整理了一轮：删掉临时 bisect worktree 和旧的 MetaEditor-dom-test-helpers，再在上级目录新建了 MetaEditor-2，并把 worktree 列表收干净。
18. 继续沿 `h_map` 和 `Dyn` 的交界去压问题。重新对了当前 `src/dom.mbt`、`src/dom.test.mbt` 和 `../IntentDoc/dev/ui.js`。确认这次真正要补的不是普通 `Dyn` 的结构比较。重点是 `h_map` 当前缓存的是 `Child`，还没缓存“列表项已经挂载出来的真实节点块”。
19. 先补了一组新的 `dom` 回归。目标很窄。专门锁 `h_map` 的列表项根直接返回 `Dyn(...)` 时，列表查询、保留项重排、删项后的内部动态清理和保留项 listener 身份。这样后面改实现时，不会再用“静态项能过”的假象把问题糊过去。
20. 新测试第一次跑出来以后，先把两个真实缺口压清楚了。第一，`h_map` 项根是 `Dyn` 时，`todos/0/toggle` 这类局部名字查询直接失效。第二，保留项重排时节点身份没有真正保住，旧测试里那层“保留项不 remove 不 recreate”的语义在根 `Dyn` 场景下打红了。
21. 顺着这个失败点，没有继续往 `VNode` 上硬塞更多并行语义。改成只在 `dom.mbt` 内部加一个私有 `VFragment`。它只表示“一个 child 挂载以后对应的真实节点块”。对外 API 还是 `Child` 和 `VNode`。外部调用点不变。
22. 同时把命令协议补了一条 `InsertAfter`。原因很直接。前置 anchor 形状已经定了，但当前 bridge 只有 `Append/InsertBefore`。缺这条命令时，想把一整块 fragment 稳定放到某个 anchor 后面会很别扭。这里顺手把 `src/bridge.js`、`src/dom_helper.mbt` 和 JSON 断言一起接上了。
23. `VFragment` 这一版先只保留最小信息。根节点数组。当前物理挂载顺序。当前可见节点顺序。这里没有额外再发明块级生命周期对象。删除还是复用现有 `recursive_cleanup(...)`。只是把“列表项当前对应哪一段真实节点”先收成了一个中间值。
24. 后面把 `h_map_dyn` 的缓存单位从 `Child` 改成了 `VFragment`。host 也从原来那层外包 `Dyn(fn() { Arr(current) })` 改成了自己的 anchor 宿主。这样保留项命中 cache 以后，不再重新产出 child 再 realize，而是直接移动已经挂载好的 fragment。列表项根如果本身就是 `Dyn(...)`，现在也能沿着同一批 `VNode.id` 继续活。
25. 中间第一版 fragment 装饰逻辑写偏了。最开始只把项名字表挂到了“第一个子 fragment”上。结果旧的 `h_map` 静态多节点项查询也一起坏了。`h_map items expose local names for list query` 直接打红。这个问题先暴露得很值，因为它说明名字表的挂载单位应该是“整项当前可见节点”，不是递归时碰到的第一段子块。
26. 后面把 fragment 装饰改成了统一包在整块 `visible nodes` 外面。这样静态项和根 `Dyn` 项重新走回同一条名字表语义。`todos/0/toggle` 和 `todos/1/toggle` 两边都重新能命中。也没有再给项里多补幽灵节点。
27. 随着 `VFragment` 接回主路径，旧的 `freeze_child(...)` 已经完全退出了 `h_map` 主实现。这里顺手把它删掉了。原因很简单。继续把旧缓存模型留在文件里，只会让后面看代码时误以为两套路径还同时有效。
28. 旧的 `h_map` 测试里有两条还写死了“重排一定要看到 `InsertBefore`”。接上 `InsertAfter` 以后，这个命令口径已经变宽了。这里把断言改成同时接受 `InsertBefore` 和 `InsertAfter`。锁的还是“有移动，不重建”，不再把命令方向写得比实现保证更死。
29. 重新跑 `moon test src/dom.test.mbt`。新增的根 `Dyn` 项测试回到全绿。原有 `h_map` 静态项、查询、listener、删项 effect 和重排测试也一起保持通过。说明这次补进去的不是平行新语义，旧主路径还站着。
30. 再往上跑了 `moon test` 和 `./scripts/test-all.ps1`。源码、native、browser 三条链都还是绿的。说明 `InsertAfter` 和新的 `VFragment` 宿主没有把 bridge、service 或浏览器黑盒那边一起带坏。
31. 这次最后收下来的结论比较明确。普通 `Dyn` 还是原来的重建型语义。先不碰。`h_map` 这条线已经对齐到了 `IntentDoc/dev/ui.js` 那种“缓存已挂载动态块”的语义。列表项根直接返回 `Dyn(...)` 时，现在也能保住稳定 `VNode.id`、局部查询和 listener 生命周期。
32. 先重新收了一遍 `src/bridge.js` 里的协议硬编码。重点看了两类。`DomCmd` 编号。bridge message type。确认这两组最值得先集中。
33. 把 `src/bridge.js` 里的命令编号收成了 `DOM_CMD`。原来 `apply()` 里那串 `case 0..16` 全部改成走常量。这样后面如果 `DomCmd` 的编号调整，bridge 解释层只需要改一处。
34. 又把 bridge 的消息类型收成了 `MSG`。`bridge:ping`、`bridge:response`、`bridge:hello`、`bridge:hello_ack`、`bridge:pong`、`bridge:rejected`、`bridge:request` 这几处发送和接收入口都改成统一走常量。协议字符串不再散在不同分支里。
35. 为了让浏览器测试也和 bridge 共用同一份命令常量，把 `DOM_CMD` 和 `MSG` 都挂到了 `window.mbt_bridge` 上。这样测试页里可以直接读 bridge 运行时正在使用的那份映射，不需要再在测试文件里平行抄一份。
36. 回头看新加的 `scripts/browser-tests/bridge.test.js`，发现那边虽然已经不写数字了，但还是先写 `'APPEND'` 这种字符串，再在页面里查表转命令。这层还是多余。测试本身仍然在保留一份平行名字。
37. 后面把 `bridge.test.js` 继续收了一次。改成在 `beforeEach` 里直接从页面取 `window.mbt_bridge.DOM_CMD`。测试里统一用 `t.domCmd.APPEND`、`t.domCmd.INSERT_AFTER` 这种实际值组命令。这样浏览器测试和 bridge 解释层终于开始走同一份命令映射，不再靠字符串再跳一层。
38. 顺手又处理了浏览器测试的 `state-dir` 生命周期。`scripts/test-browser.js` 原来默认会在系统临时目录下新建一个 `metaeditor-browser-test-*` 目录，但结束后不会删。多跑几次以后会一直留残余目录。
39. 把 `scripts/test-browser.js` 改成两条规则。显式传 `--state-dir` 时保留用户目录，不自动删。没有显式传时，默认生成的临时目录在测试收尾时递归清理。这样默认回归不再留垃圾目录，手工调试又还能继续用稳定
40. 最后把整条 `./scripts/test-all.ps1` 重新跑了一遍。`moon test`、native 和 browser 三条链都通过。到这里，这次 bridge 协议常量和浏览器测试状态目录清理一起收住了。
41. 最近 `dom` 这条线的运行时语义、host 写法边界、bridge 协议和测试要求改动很多。单靠 devlog 和零散文档已经不够稳。这里先决定把这些口径收成一份 skill 草稿，后面如果值得，再正式安装成 Codex skill。
42. 先看了 `../mbt-skills` 和内置 `skill-creator` 的结构。确认真正的 skill 目录最少只需要 `SKILL.md`，复杂内容再拆到 `references/`。不需要额外再写 README、CHANGELOG 这类外围文件。
43. 原来先写在 `doc/dom-runtime-guidelines.md` 里的那份文档，只是普通说明文。结构上还不像 skill。后面把它整个改成了 skill 目录形状，放到 `doc/dom-runtime-skill/` 下，先不安装，只在仓库里保留草稿版本。
44. 新的 `doc/dom-runtime-skill/SKILL.md` 只保留了 skill 本身最该负责的东西。什么时候该触发。适用哪些文件和任务。工作流怎么走。哪些 runtime 规则是硬约束。这样以后如果真装成 skill，这个入口本身就能直接用。
45. 具体的运行时语义和编码约束则拆进了 `doc/dom-runtime-skill/references/runtime-semantics.md`。
46. 同时把旧的 `doc/dom-runtime-guidelines.md` 删掉了，避免同一套口径在 `doc/` 里并行存在两份。这样这条线目前就只保留 skill 目录这一条主路径，后面要继续补内容，也不会再在普通文档和 skill 草稿之间来回分叉。
47. 又修正一轮之后安装到了 skill 目录里。
## 04-02 晚上
1. 追 `demo_editor` 的滚动问题。先看命令序列，再对照浏览器现象。确认不是 editor 顶层重刷。问题落在列表项和 `h_map_dyn` 的保留项重插上。
2. 对照了 `../IntentDoc/dev/ui.js` 的 `moddom(...)`。确认关键语义是“保留项如果已经在目标顺序里，就完全不发 DOM 操作”。之前这边虽然保住了节点身份，但还会对已在位的保留项重复发插入命令，浏览器滚动锚点会被这种重插排影响。
3. 调整了 `h_map_dyn` 的保留项移动判定。只在顺序真的变化时才发重排命令。纯新增、纯删除、以及已在正确位置的保留项都保持 no-op。
4. 补了 browser 集成回归，专门测 `demo_editor` 添加 todo 时真实滚动容器的滚动位置。过程中顺手确认了测试入口问题。仓库约定的总入口是 `scripts/test-all.ps1`。browser 入口是 `npm run test-browser`，默认已经带 `--headless`。
5. 用 `scripts/test-all.ps1` 重跑以后，发现 browser suite 之间会互相污染状态。`demo-editor-scroll.test.js` 会打开桌面窗口，接着跑 `host.test.js` 时会撞到旧窗口、旧 session 和窗口编号延续。中间试过“只刷新页面”和“按文件重启 harness”两条路径，都暴露出当前 browser harness 的隔离点不对。
6. 这个测试问题把一件更大的设计问题暴露出来了。现在很多测试都绕进了 service、browser 和 session。导致本来只需要验证 `DomCmd` 语义的用例也变重了。于是整理出一个更合适的方向：补一个接受 `DomCmd` 的本地宿主，作为 mock browser / mock host。它只需要吃 `apply_batch(cmds)`，维护一棵轻量节点树，并提供按 `id` / `ui-id` / 文本查找和本地事件注入。大多数交互测试都应该落到这层，不该默认走真 browser。
7. 顺着 mock host 的讨论，又重新看了 host app 的位置。现在 host app 放在 `service` 里，模型边界和测试边界都被拖脏了。更合理的方向是把 host 直接当成 editor 模型的一种形态。平台能力通过可选 context / env 注入。host 本身应该回到 `src`，和普通 editor 走同一套 view、state 和动作路径。
8. 先按这个方向落了第一步，在 `src/host.mbt` 写了一个最小版 host editor。先不接 `service`。只把平台无关的 host 数据和视图搬到 `src`。host 直接表现成普通 `Editor[HostData, HostSession]`。`env` 先只保留了可选的 `stop_service`。
9. 继续整理了 `src/host.mbt` 的样式路径。把大块内联样式抽成了 `css('host', ...)`。动态 inline 只保留窗口几何和选中 / 聚焦这类状态切换。这个调整也和 runtime 的推荐写法更一致。
10. 讨论里还补清了一个实现细节：`ui-id` 本身会自动派生类名，没有显式 `class` 时可以直接拿它当 CSS anchor；显式写了 `class` 以后，派生类也还会保留。这个细节之前没写进 skill，顺手补到了 `metaeditor-dom-runtime` 里，免得以后继续漏掉。
11. 验证保持在源码测试范围内。`moon test` 通过。browser 这边暂时先不继续扩隔离方案，等 mock host 那条测试主路径补起来再收。
## 04-03 上午
1. 把 `dom` 测试拆成两层。保留 `dom.test.mbt` 的白盒约束。新增 `mock_dom.test.mbt` 承接交互和结果测试。
2. 把 mock 宿主独立到 `src/mock_dom.mbt`。能力只保留 `DomCmd` 回放、节点树维护、文本查询和事件触发。
3. 先迁一批黑盒价值最高的用例。包括 `ui-name/ui-list` 查询、`h_map` 可见项查询、事件触发、`Str + Dyn` 文本更新、`ui-react` 生命周期。
4. 迁移过程中统一了测试锚点。默认都按 `ui-id` 走目标定位，避免继续混用内部节点 id。
5. 把 mock 事件入口收成一条主路径。删除 `mock_click/mock_dblclick/mock_keydown`。改为 `mock_event(browser, action, target, ev?)`。
6. 把动作语义从 `onclick` 这类事件名改成 `click/dblclick/keydown` 这类动作名。内部再映射到 runtime 事件。调用点可读性更直接。
7. 把 `mock_count_ui/mock_text_of_ui` 改成通用命名。现在统一用 `mock_count/mock_exists/mock_text`。
8. 清理 `dom_helper`。删掉不再被引用的断言工具和辅助函数，减少白盒基建噪音。
9. 保留必要白盒测试。重点只放协议编码、命令语义边界、identity 约束和生命周期约束。
10. 逐步删掉 `dom.test.mbt` 里已经迁到 mock 层的重复用例，避免双份维护。
11. 验证通过。`moon test` 90/90。`scripts/test-all.ps1` 全绿，native 和 browser 也通过。
12. 继续推进 host app 往 editor 模型上收。先读了 devlog 末尾、`src/host.mbt`、`service/app.mbt` 和相关测试。确认当前真正的问题是 `src` 里已经有 host editor，`service` 里还留着一套平行 host 状态和视图。
13. 先在 `src/host.mbt` 补了几条 host editor 侧公开能力。包括列 entry、列 window、开窗、聚焦、关窗，还有默认 host entry 列表。这样先把 host 行为口径收回 editor 模型，再让 service 只保留宿主接线。
14. 接着改了 `service/app.mbt`。删掉原来那套 `entries/windows/z_order`、host 视图和对应命令实现。改成只持有一份 host editor 的 `data/session/dom_state`，初始化和渲染都直接走 `src` 里的 host editor。
15. 这一步第一次收完以后，native 测试打出了一个真实脱节点。`host-stop-service` 按钮之前被改成匿名事件。service 测试还在认动作名。后面把它补回 `reg_action("host_stop_service", ...)`，把动作名重新接回原链路。
16. 然后继续收 CLI。用户明确要求先把 `run_app` 里那批 host 包装命令删掉，因为这层包装本身就是错的。这里保留了 `src` 里的 host 动作，没有继续把它们暴露成 service CLI。
17. 按这个口径，把 `service/app.mbt` 里的 `run_app` 整个删掉了。`service/cli.mbt` 的普通命令分发也一起收窄。现在只认 `help/status`。其余命令直接报 `Unknown command`。不再透传到那层伪 app CLI。
18. 绑定旧命令的测试也一起清了。`service/repl.test.mbt` 从 `list_entries/list_windows` 改成只测还存在的 `status/help`。`service/service.test.mbt` 里把 `host_stop_service` 改回真实的 `stop`。原来依赖 `list_windows/test_query/test_exec` 的 `service/host.test.mbt` 直接删掉，避免继续保留死协议测试。
19. 后面又看了一眼 `service/app.mbt`。确认它已经只剩 host editor 初始化和渲染两件事。继续单独留一个 `app.mbt` 已经没有意义。于是把这部分代码整块并进 `service/cli.mbt`，再删掉 `service/app.mbt`。
20. 最后重新验证了当前主链。`moon check` 通过。`./scripts/test-native.ps1` 通过。结果回到 `21/21`。browser 这边按用户要求先没有继续处理。
21. 先按“实例是主语，DOM 只负责触发”这条线重写了一版共享模型。新增了 `src/entry.mbt`。把旧的 `Editor` 主线先抽成 `Entry/Instance` 运行时。service 侧也开始围着根实例运转，不再直接持有裸的 host data/session。
22. 顺着这条线，把 `src/dom.mbt` 里旧的 `ActionRef/reg_action/trigger_action/DomCmd::Action` 整条机制删掉了。原因很直接。这套东西还是把 action 绑在节点和 `onclick` 上。和“实例拥有动作”这条主设计冲突。`src/bridge.js`、`src/dom_helper.mbt`、`src/mock_dom.mbt` 和 `src/dom.test.mbt` 里的命令编号与匹配断言也一起同步。
23. 把 `src/demo_editor.mbt` 改到了实例 action 入口。todo 的 add、toggle、remove 和 show_done 切换都从 view 里的直接闭包挪到了实例动作里。view 这边只保留 `ctx.action(...)` 这种很薄的绑定。这样 demo 先走通了“view 只发动作，状态改动都由实例处理”这条主路径。
24. 把 `src/host.mbt` 也按同一思路重写了。host 现在自己就是一个 `Entry`。窗口不再直接保存子 view，而是保存对应子实例的信息。双击桌面入口时，先创建子实例，再补 host 自己的窗口状态。默认入口表里也把 host 本身注册回去了，所以 host 里现在可以继续启动 host。
25. 给 host 补了新的源码测试。`src/host.test.mbt` 现在不再直接围着 `default_host_editor()` 转，而是围着实例运行时转。除了原来的开 demo、关窗，还额外补了 `host#1/host#1` 这条嵌套 host 回归，锁“host 自己也能作为普通入口继续被启动”。
26. 第一次跑 `moon test` 时先撞到了几类基础口径问题。一个是错误类型名字都叫 `Fail`，新旧模块一起进来以后直接二义。一个是 `InstanceRuntime` 对私有内部类型的可见性不合法。还有一批 `dom` 的 JSON 编码测试还在认旧的命令编号。这里后面都按最小补丁修平了，没有继续顺手扩别的设计。
27. 往上跑 `./scripts/test-all.ps1` 时，browser 的 host 黑盒先挂了。第一次坏点不是协议，而是 host 里一批原来应该走 `D(...)` 的选中态和焦点态样式，被这次重写时不小心写成了静态值。这样浏览器里点了 entry/window 以后节点身份虽然没变，但样式不会更新。后面把这些地方都恢复成了 `D(...)`。
28. browser 的 host 用例里还绑着旧的等待方式。它原来直接等内联 style 字符串命中。现在 host 这边状态虽然正常更新了，但那条等待本身还是很脆。最后把这段收窄成只锁真正重要的行为：单击前后 `entry:demo` 的 runtime id 连续存在，双击以后真的开出 `window:1`，并且事件消息里还能看到两次 click 加一次 dblclick。
29. 最后重新跑了 `moon test` 和 `./scripts/test-all.ps1`。源码测试回到 `91/91`。native 回到 `21/21`。browser 回到 `6/6`。说明这次 `Entry/Instance` 主线、DOM action 旧协议移除、host 改成实例开窗和嵌套 host 支持，三条链都已经接上了。
30. 这次实现完以后，聊天里又把两处还没彻底对齐的模型偏差重新讲清楚了。第一，action 现在虽然已经从 DOM 挪回实例层，但还是字符串分发，不是 entry 自带可枚举动作表。第二，实例身份也被我先做成了最终查询串，这和“查询串只存在于查询时”这条旧口径冲突。这两点这次先没有继续改代码，只在讨论里明确记下，留待下一笔继续正面收。
## 04-03 下午
1. 先按新的三层模型重做了一版共享运行时。`./src/entry.mbt` 里把 `Entry` 改成了 `view + actions`。删掉了旧的 `act(name, arg)` 字符串分发。补了 `ActionSpec / ActionArgSpec / ActionArg`。CLI help 和参数解析也开始围着这套规格走。
2. 实例树从“实例直接存最终 query 串”改成了“只存实例身份和父子关系”。运行时现在靠父引用和子表现算 query。`self_query`、`resolve_query(...)`、宽 `InstanceCtx` 那条旧路径已经拿掉。
3. `./src/host.mbt` 也迁到了宿主专用 extra。窗口不再存查询串，改存实例句柄。`spawn/focus_window/close_window/stop_service/select_entry` 都改成了动作表。
4. `./service/cli.mbt` 接上了新的根实例接口。新增了基于动作规格的 `help QUERY` 和 `exec QUERY ACTION [ARGS...]`。参数切分开始支持引号和转义。
5. 为了先把新模型站住，补了 `./src/entry.test.mbt` 和 `./service/repl.test.mbt`。查询解析、动作 help、参数解析、REPL `help/exec` 都有覆盖。`moon test` 和 `./scripts/test-all.ps1` 当时都跑绿了。
6. 跑完以后回头看 diff，发现这次不是单点修补。`entry/host/demo_editor/cli` 四块几乎一起换口径。`git diff --stat` 到了 `1003 insertions / 339 deletions`。这说明这笔改动里混了模型修正和实现口径选择，后面还要继续收。
7. 第一处明确坏点是在 `./src/demo_editor.mbt`。`demo_host` 为了适配新的动作接口，又重新定义了一整套 `add/toggle_done/toggle_todo/remove_todo`。这直接把 demo 业务动作复制成了两份。主路径已经分叉。
8. 继续复查 `./src/host.mbt` 时，又看出第二类冗余。窗口里已经存了 `InstanceRef`。host 却还在先把句柄转成相对 query，再通过 `lookup_child/render_child/close_child` 查回实例。已经拿到句柄的地方还绕字符串一圈，说明“句柄路径”和“query 路径”还没有真正压成一条。
9. 再看 `./src/entry.mbt` 的公开接口，发现第三类冗余。运行时同时保留了按 `InstanceRef` 和按 query 的两套公开入口：`render_instance`/`render_instance_query`、`call_instance`/`call_instance_query`、`close_instance`/`close_instance_query`，以及 child 版本的一套包装。这些函数内部大多只是“先查再调”。API 面偏宽。还留着平行入口。
10. 继续讨论实例身份时，又暴露出一个更底层的问题。当前把 `Instance.id` 和 `index` 拆开公开并不顺。因为同父同 entry 下，真正能唯一标识实例段的其实是 `id#index`。只公开 `id` 会让它看起来像完整身份，实际却还差半段信息。这会继续把身份语义搞模糊。
11. 顺着这个判断，再回头看当前实现，问题就不只是在“有没有冗余函数”，还在于几层模型其实还没完全拉直：业务动作还没有完全收成单一路径；子实例访问还在句柄和 query 之间来回绕；实例公开身份还没有压成真正的单值；组合型 entry 到底该不该拥有创建子实例的共享能力，也还没有定干净；
12. 最后在聊天里先把口径压清楚了：如果要让查询穿透 `demo_host` 真正访问里面的 todo demo，就不能只在查询层假装穿透，里面必须真的有一个 `demo` 子实例；否则又会形成“实例树一套真相，查询树另一套真相”的平行语义。
13. 这笔工作目前的状态先记清楚：测试是绿的。模型方向比旧版正。但还不是最终收束版。后续 agent 不能在当前接口上继续叠功能。应该优先处理实例身份、组合型 entry 的子实例主路径，以及 `demo_host`/`host` 里已经暴露出的平行语义。
14. 继续看 `entry/host/demo_host` 这条线。目标先压成三件事。删 `entry` 里按 query 的平行实例接口。删 `host` 里拿到 `InstanceRef` 又绕回 query 的子实例路径。处理 `demo_host` 那份重复动作实现。
15. 先改了 `src/entry.mbt`。补了 `resolve_instance_ref(...)`。让 query 解析只走这一处。删了 `render_instance_query`、`call_instance_query`、`close_instance_query`。也删了 child query 那组包装。实例执行重新只剩句柄入口。
16. 再改了 `service/cli.mbt`。`help QUERY` 和 `exec QUERY ACTION` 先解析 `InstanceRef`。再取动作表。再执行动作。CLI 还认 query。runtime 内部不再保留 query 版执行入口。
17. 又改了 `src/host.mbt`。`HostExtra` 原来同时留着句柄和 query 两条子实例路径。窗口里明明已经有 `InstanceRef`。渲染、查标题、关窗还是先转 query 再查回实例。现在把这层绕路删了。`render_child`、`close_child`、`child_info` 都直接吃 `InstanceRef`。
18. 把 `src/demo_editor.mbt` 里的 `demo_host` 删了。`DemoHostData`、`DemoHostSession` 一起删。那套重复的 todo 动作也一起删。默认入口注册里不再挂这个伪组合 entry。demo 业务动作重新只留 `demo_entry()` 一份。
19. 验证时 native 打出一条真实回归。`service/service.test.mbt` 还在认已经删掉的 `Demo Host` 桌面项。补了最小测试修正。把断言改回只锁当前真实存在的入口内容。
20. 这次整理把一个旧问题直接翻了出来。`demo_host` 原来虽然模型不直，但它确实带着一份能力。子 demo 的 data/session 会跟着父实例一起序列化。现在真子实例路径已经能负责创建、渲染、查询和关闭。这条线还没把“每个子实例自己的持久化空间”补齐。功能口径还差这一块。
21. 接下来该继续做两件事。先收实例身份。`Instance` 现在还把 `id` 和 `index` 分开公开。真正稳定的实例段身份其实是 `id#index`。这层还要继续压。再做实例级持久化。给每个实例独立的 kv 名称空间。让 `bind_with_kv` 直接挂当前实例。这样组合型 entry 以后如果真要带子实例，也该走“真实子实例 + 子实例自己序列化”这条主路径。
22. 重看了 `IntentDoc/dev/ui.js` 里的 `Dyn`。确认它没有额外 runtime 分支。它只是把当前结果规约成一组 children。尾锚点固定。更新时直接 `insertBefore` 到锚点前。
23. 对照 `MetaEditor-2` 里的 `src/dom.mbt`。确认之前的问题不在尾锚点方向。真正偏掉的是 query 语义。项目把列表 index 过早压成了 node id。`Dyn` 一变形，外层列表就会拿到过期入口。
24. 先把 DOM 主路径继续收紧。删掉了 `InsertAfter`、`VFragment`、`realize_fragment*` 这一整套旧分支。桥接层和测试也一起清掉。把 `Dyn`、`h_map` 都压回尾锚点加 `InsertBefore` 一条路。
25. 跑通了这一版的 DOM 测试。确认动态挂载模型已经和 `IntentDoc` 对齐。plain `Dyn`、`h_map`、`h_map root Dyn` 的节点更新都走同一条底层路径。没有再留下 fragment 式的平行入口。
26. 继续追 `ui-list` 的 query。先试过把 `list_items` 重新当成 `index -> id` 表。很快发现不对。`h_map root Dyn` 在 shape 变化后会失效。说明数字段绑 node id 这件事本身就偏了。
27. 重新按原设计收 query 语义。把列表 index 理解成“第 i 个 fragment 的查询作用域”。它通常对应第一个节点。它不保证一直存在。像空数组和返回空的 `Dyn` 都可以让 `todos/0` 直接为空。
28. 把 `list_items` 改成 `Array[Map[String, Int]]`。每一项直接存这项当前的局部名字表。resolver 改成两段式。数字段先取这一项 scope。后续名字再从这个 scope 里查 id。cursor 停在 scope 结束时返回 `None`。
29. 补了 `Dyn` 自己的稳定名字表更新。`Dyn` 锚点现在持有一份长期存在的 `scope_names` map。每次重算 children，只原地清空再写入这张 map。没有再用临时快照替换整张表。
30. 补了 `h_map item` 的作用域收集。item 根如果本身是 `Dyn`，匿名锚点会被当透明层穿过去。不会在锚点处提前截断。这样 `label`、`toggle` 这些名字能继续暴露给外层列表 query。
31. 调整了 `attach_item_scope_names`。不再每次新造一张 map。优先复用第一根节点已有的 `scope_names`。这样 `Dyn` 闭包里抓到的锚点和外层列表手里持有的是同一份作用域对象。内部 shape 变化后，外层能直接看到更新。
32. 反复回归 `mock dom h_map root Dyn query follows current visible nodes after shape change`。这个用例一直是最难的。每次失败都说明一件事。不是 `Dyn` 特别。是 item scope 没有稳定地传到外层列表。
33. 最后把 `moon test` 跑回 `90/90`。确认静态 `ui-list`、普通 `h_map`、`h_map root Dyn` 三类场景都恢复。`todos/0/toggle` 和 `todos/1/toggle` 在 shape 变化前后都能命中正确节点。
34. 又做了一轮审查。确认现在大的语义已经对上。`Dyn` 主路径、列表 scope、名字解析都回到了原设计。没有再依赖递归搜当前节点树来拼 query 结果。
35. 还没继续清的第一处实现残留是 `refresh_list_scope`。它现在是一条全局回写旁路。子 `Dyn` 更新后会扫描 `nodes_by_id`，找到直接持有这个 child 的列表宿主，再把对应槽位改掉。语义是对的。实现偏脏。后面最好改成由 owning list 自己维护，不靠全局扫描补写。
36. 还没继续清的第二处残留是 `list_items_for_host`。它只在“宿主只有一个 child，且这个 child 自带 list scope”时复用那份活数组。多 child 的宿主还是会做一次当前快照。现在测试覆盖的路径没问题。更一般的嵌套组合还值得再压一版，避免列表宿主再次生成并行快照语义。
37. 还没继续清的第三处残留是 `src/dom.mbt` 里 query 和 list scope 相关代码体积还偏大。现在逻辑已经稳定。还没有做概念层再收紧。后面如果继续，目标应该是把“列表槽位是稳定 scope map”这件事提炼得更直接，让 resolver、`Dyn` 更新、`h_map` 更新都围着同一个最小数据流展开。
38. 先回看了 `../devlog.md` 末尾，重新对齐 DOM 这条线前面已经确认过的残留。重点只放在 query、`ui-list`、`Dyn` 和 `IntentDoc` 对齐这几件事上。
39. 对照了 `../IntentDoc/dev/ui.js` 和当前仓库实现。先把问题压成两类。第一类是 `ui-list` 还留着“活引用”和“快照”两套作用域语义。第二类是 `Dyn` 更新后的列表作用域还靠全局扫描补写。
40. 中间确认这次真正该看的工作树是 `../MetaEditor-2`。随即把审查目标切过去，重新读了那边的 `src/dom.mbt`、`src/mock_dom.test.mbt`、`src/bridge.js` 和浏览器桥测试。
41. 在 `MetaEditor-2/src/dom.mbt` 里把前面口头提过、但还没落干净的实现残留重新定位了一遍。`refresh_list_scope` 还在。它会在 child 更新后扫整张 `nodes_by_id`，再去猜哪个列表宿主需要改槽位。`list_items_for_host` 也还在。它会在“单 child”时直接复用已有数组，在“多 child”时改成重算快照。
42. 顺着这两处实现，再和 `IntentDoc/dev/ui.js` 对了一次。确认旧实现的动态主路径很直。它只围着锚点前的当前 children 工作。没有“按宿主 child 个数切换语义”的分支。也没有“child 先变，再全局回填父列表”的旁路。
43. 先把问题用更直白的最小例子重新讲清楚了。举了 `ui-list` 宿主只有一个 `h_map` child 时能跟着 shape 变化更新 query。又举了外面多包一层 wrapper 或再加一个 sibling 以后，本来不该变的语义会被当前实现拖进另一条路径。这样把“为什么这是模型问题，不只是代码难看”单独讲明白了。
44. 讨论后把修正目标压成一条主路径。`ui-list` 持有的应该始终是每一项自己的稳定 scope 对象。项还活着时，这个对象就应该继续复用。内部 shape 变化时，只原地清空再重写。外部 query 永远只认这份对象，不再关心宿主下面是一个 child 还是多个 child。
45. 先改了 `MetaEditor-2/src/dom.mbt` 的列表项作用域流。删掉了 `refresh_list_scope`。这样 child 更新后不再全局扫节点树找父列表，也不再靠旁路补写列表槽位。
46. 再改了 `scope_names_of_node(...)`。以前这里在节点还没有 `scope_names` 时，会临时现算一份名字表，但不会把它稳定挂回节点。现在改成缺失时直接按项级收集逻辑建出一份，并立刻写回节点自身。这样后续列表 query 复用的是同一份作用域对象，不是一次性快照。
47. 再改了 `list_items_for_host(...)`。以前这里有一条特殊分支。宿主只有一个 child，且这个 child 自带 `list_items` 时，会直接复用那份数组。否则就重新遍历当前 children 算一份新的作用域数组。现在把这个分支删掉了。统一走 `list_item_scopes(...)`。列表宿主不再因为 child 个数不同，切进不同语义。
48. 这一步做完以后，`ui-list` 这条线收回到了更一致的状态。宿主下有 sibling 时，不会再偷偷退成“现算快照”。单个 wrapper child 时，也不再因为碰巧只有一个 child 才拿到不同实现待遇。外部 query 只围着项级 scope 工作。
49. 然后补了第一条 mock DOM 回归测试。这个用例专门做了“列表项外面先包一层匿名 wrapper，宿主下面再多一个 sibling”。列表项内部继续用 `Dyn` 在“只有 toggle”与“label + toggle”之间切换。测试锁的是 `todos/0/toggle` 和 `todos/1/toggle` 在切换前后都命中当前可见节点，不受 sibling 干扰。
50. 接着补了第二条 mock DOM 回归测试。这个用例只保留单个 wrapper child。里面照样用 `Dyn` 改 shape。测试锁的是“单 wrapper 也必须继续走 live scope”。这样把之前那条“单 child 恰好走活数组、多 child 才走快照”的分叉语义正面钉住。
51. 跑了 `MetaEditor-2` 的 `moon test`。结果从 `90/90` 变成 `92/92`。新增两条都通过。说明这次收掉 `refresh_list_scope` 和 `list_items_for_host` 的分叉以后，当前覆盖到的 query 场景仍然成立。
52. 测试跑绿以后，没有停在“刚改的地方过了”这一层。又把整个 `MetaEditor-2/src/dom.mbt` 从头到尾重新审了一遍。重点看 query、scope 传播、`Dyn`、`h_map`、`ui-name`、`ui-list`、`ui-react` 和清理逻辑有没有新的模型偏差。
53. 这轮全文件审查里，先确认这次改动本身没有引入新的明显回归。桥协议、样式、宿主命令、基础 `Dyn` 更新、`h_map` 项复用和现有 query 测试都还是通的。`moon test` 也已经覆盖到 `92/92`。
54. 但又明确看出了第一处还没继续处理的残留。当前 `children(... Dyn ...)` 在内部 shape 变化后，只会把新的 `scope_names` 往“没有 `ui_id` 的直接父节点”上同步。这个条件太窄。如果列表项的根本身带 `ui-id`，而内部再套一层 `Dyn` 去改局部名字，这份项级 scope 可能不会跟着刷新。第一次挂出来时是对的。后续再变形，外部 query 手里就可能继续抓旧名字表。
55. 这处残留的关键点单独记下来。问题不在 query parser。问题在“scope 挂在哪个节点上以后，谁负责继续把它更新”。当前实现把“有 `ui-id` 的节点”过早当成边界了。这样项根只要自己有名，内部 `Dyn` 的名字变化就有机会停在里面，不再传到外层持有的项级 scope。
56. 又看出了第二处还没继续处理的残留。`scope_names_of_node(...)` 现在会在查询时给一个原本没有 `scope_names` 的节点懒建并缓存一份。但后续动态更新只会修一层直接父节点。这样如果 query 先走过某个多层匿名 wrapper，把它的名字表缓存出来，里面再发生更深层的 shape 变化，这份外层缓存没有稳定的继续更新路径。它可能变成一份过期视图。
57. 这处残留也单独记下来。它和前一条不是一件事。前一条是“有 `ui-id` 的项根会不会截断传播”。这一条是“匿名 wrapper 的懒建缓存会不会在后续更新里老掉”。两条都指向同一个更深的问题：`scope_names` 现在还是混着“谁拥有它”和“谁顺手帮它算一下”两种口径。
58. 再往下看，还确认现在新增的两条测试虽然正好锁住了这次收掉的分叉，但没有把更深的传播问题一起锁住。新测试都围着 `toggle` 命中在看。还没有单独测“有 `ui-id` 的项根内部再加 `Dyn` 后，`label` 这类局部名字能不能继续跟着变化”。也没有测“多层匿名 wrapper 被 query 过一次以后，再变形会不会继续保持新名字表”。
59. 因此把当前状态明确记成两层。第一层已经完成并验证：`ui-list` 的快照分支和全局补写旁路已经删掉。宿主 child 个数不再切换语义。第二层还没继续做：`scope_names` 的拥有关系和向上同步规则还没有彻底收成一条最小主路径。
60. 最后把这次真正收住的结论记清。`MetaEditor-2` 的 DOM query 这条线已经比改前更直。`ui-list` 不再按“单 child / 多 child”分叉。`Dyn` 更新后也不再靠全局扫描回填列表槽位。新增两条 mock DOM 回归测试已经锁住这次修掉的模型偏差。
61. 但这次收完以后又把整个 `src/dom.mbt` 重读了一遍，发现这件事其实还没收干净。问题本质没变。还是 DOM 里“当前可见结构”和 query 依赖的那份 scope 名字表，还没有彻底压成同一份真相。前面删掉的是最外层两条明显分叉。更里面的传播链还没完全拉直。
62. 第一处没收干净的是项根自己带 `ui-id` 的情况。现在项级 scope 常常挂在列表项的第一个根节点上。内部 `Dyn` 再变形时，代码只会顺手改“没有 `ui-id` 的直接父节点”那层 scope。这样如果列表项根本身就有 `ui-id`，里面又动态增删 `label`、`toggle` 这类局部名字，第一次建出来时 query 是对的，后面 shape 再变，这份项级 scope 可能继续停在旧内容上。也就是 DOM 已经变了，外面 `todos/0/...` 还可能看旧表。
63. 第二处没收干净的是多层匿名 wrapper。现在 `scope_names_of_node(...)` 在某些节点还没有 `scope_names` 时，会在查询过程中临时现算一份并挂回去。这个做法短期能回答 query，但后续更深层的 `Dyn` 再变形时，没有一条稳定的数据流保证这份外层缓存会继续更新。结果就是 query 一旦先走过某个匿名 wrapper，它手里可能拿到一份会老掉的 scope 视图。后面 DOM 继续变，wrapper 上那份旧名字表不一定跟着变。
64. 这样回头看，这次不是做错了另一件事，而是我一开始只收到了最外层。把显眼的平行入口删掉以后，才看清下面还留着同性质的尾巴。更准确地说，这次已经把“快照分支”和“全局补写旁路”收掉了，但“scope 到底谁拥有、谁负责更新、变化会不会稳定往上传到 query 用的那份对象上”这条主路径还没有彻底收直。
65. 这次最后没有继续往下改代码。原因也明确记一下。现有新增测试锁住的是 wrapper、sibling 和 `toggle` 这类最直接的命中路径，还没把“有 `ui-id` 的项根内部再套 `Dyn`”和“多层匿名 wrapper 被 query 过一次以后再变形”这两类更深边界钉死。要继续收，应该先补这两类回归，再把 `scope_names` 真正压成“谁持有、谁原地更新、外面只读这一份”的单一路径。
66. 重新读了 `../devlog.md` 末尾。把最后那个问题压清楚了。确认问题不在 query parser。问题在 `scope_names` 同时承担了稳定 owner 数据和查询时临时缓存两种角色，语义没有收成一条。
67. 重新看了 `src/dom.mbt` 和 `src/mock_dom.test.mbt`。把残留分成两类。第一类是列表项根自己带 `ui-id` 时，内部 `Dyn` 变形后的名字变化可能传不到外层 query。第二类是匿名 wrapper 的 `scope_names` 会在查询时懒建缓存，后续 shape 再变时这份缓存会旧。
68. 先把设计口径定成“稳定 owner + 原地更新 + 父链刷新”。给 `VNode` 增加内部 `parent_id`。`Dyn` anchor、`h_map` item anchor、`ui-name` host、`ui-list` host 只持有自己的稳定 scope 容器。query 只读，不再顺手写缓存。
69. 改了 `src/dom.mbt` 里的挂载主路径。给 `VNode` 补了 `parent_id`。把 `children(...)` 拆成物理挂载父节点和逻辑 owner 父节点两条参数。这样 `Dyn` 里挂出来的节点虽然插在真实 DOM 父节点下，scope 刷新时还是沿逻辑 owner 链往上走。
70. 删了 query 侧那条旧缓存旁路。`scope_names_of_node(...)` 现在在节点本身没有 `scope_names` 时，只临时现算，不再把结果写回节点。匿名 wrapper 不会再因为被 query 过一次就留下会老掉的缓存。
71. 把 owner 更新主路径接起来了。补了 `refresh_scope_owner(...)` 和 `refresh_scope_chain(...)`。`Dyn` rerender 后先刷新自己，再沿 `parent_id` 往上刷新外层 owner。旧的“只顺手同步一层匿名父节点”的特判删掉了。
72. 把 `h_map` 这一侧也接回同一条主路径。每个 item anchor 现在自己持有稳定 `scope_names`。`ui-list` 只持有这些 map 的引用。列表项内部 `Dyn` 变形以后，变化会经由父链刷新回到外层列表 query。
73. 补了两条新的 mock DOM 回归。第一条锁“列表项根自己带 `ui-id`，内部 `Dyn` 变形后，`todos/0/label`、`todos/1/toggle` 还能命中当前节点”。第二条锁“匿名 wrapper 先被 query 过一次，再变形后外层 query 仍读新名字表”。
74. 第一轮 `moon test` 时，新的 wrapper 用例先打红了。这个失败把真正缺口翻出来了。`ui-name` host 在收名字时，还没有把内部 `Dyn anchor.scope_names` 吸进来。
75. 顺着这条失败继续改了名字收集逻辑。让 host scope 也能吸收内部动态 owner 的稳定名字表。补完以后，wrapper 那条回归回绿了。
76. 跑了 `moon test`。结果回到 `94/94`。说明 `Dyn`、`ui-name`、`ui-list`、`h_map` 这几条 query 主路径都还站着。
77. 接着跑了 `./scripts/test-all.ps1`。源码测试和 native service 测试都通过了。browser 没继续验证，因为本地缺 Playwright，脚本直接停在环境错误，不是代码回归。
78. 跑绿以后继续收了一轮实现，没有停在“能用就先放着”。先删了已经没有实际作用的 `scoped_item(...)` 空包装。又把 host 和 item 两套 map 刷新样板合成了一条 `refresh_names_map(...)`。
79. 最后又把两套几乎同形的 scope 收集逻辑合掉了。把 `collect_scope_names` 和 `collect_item_scope_names` 收成一条通用路径。顺手把已经没有语义差异的分支参数也删了。实现比第一版更短。
80. 这次收下来的结果比较明确。`scope_names` 现在只由明确 owner 持有并原地更新。query 不再顺手造缓存。新增两条测试把最开始那两类残留正面锁住。
## 04-03 晚上
1. 重新对了 `../IntentDoc/dev/ui.js`、`src/dom.mbt`、`src/dom.test.mbt` 和 `src/mock_dom.test.mbt`。确认这次真正该收的是 `h_map_dyn` 主路径。不能继续在上一版局部补丁上绕。
2. 先补了两条 `dom` 白盒回归。专门锁 `h_map` 和 `h_map root Dyn` 在顺序没变时不发 `Append/InsertBefore`。跑 `moon test` 后两条直接打红。确认当前实现还在对已在位保留项重复发移动命令。
3. 顺着失败继续查。确认多余 `Append` 不是 plain `Dyn` 自己发的。问题落在 `h_map_dyn` 复用项时无条件走了搬运路径。
4. 第一轮先补了最小修正。让已在位保留项不再重插。随后又被 review 翻出纯删除场景还没收干净。`[A,B,C,D] -> [A,D]` 这种更新，待删项还会被当成阻塞。
5. 接着补了 delete-only 回归。专门锁“跨删除 gap 的保留项也不应重插”。然后把旧顺序判断改成只看本轮仍保留的项。`moon test` 回到全绿。
6. 再往下审时确认，虽然语义已经对了，但上一版性能修正引入了一组按数组来回扫的 helper。复杂度和代码体积都偏重。和仓库“更短更精炼”的要求冲突。
7. 重新对照了 `IntentDoc/dev/ui.js` 里的 `moddom(...)` 和当前 `h_map_dyn`。确认不需要继续保留那组前后链接辅助。可以改成更直的前向 cursor 模型。这样仍然保持线性级，而且实现更短。
8. 最后直接重写了 `h_map_dyn` 主循环。删掉按 `anchor.id` 维护链接表的实现。改成“保留项旧顺序 + 前向 cursor + 统一 before anchor”这条主路径。复用项已在位时 no-op。错位时 `InsertBefore`。新项按同一锚点 realize。
9. 同时把 `anchor.list_items` 的更新收成直接复用 item anchor 自己持有的稳定 `scope_names`。不再额外走一层只服务于 `h_map` 的顺序镜像逻辑。这样 query 仍然跟着当前 item 顺序走，但实现更短。
1. 继续收 `entry` 这条线。先把 `./src/entry.mbt` 里的实例身份改成全局唯一字符串。`InstanceRef` 直接收成实例 id。实例信息改成 `id / entry / title / icon`。旧的 `id + index` 组合身份删掉了。
2. 把 runtime 的查询口径一起改了。删掉旧的 `instance_query / resolve_instance_ref / lookup_instance`。不再按 `entry#index` 解析路径。改成全局实例表直接按实例 id 查。新增 `query(...)` 和 `query_tree(...)` 两个普通数据接口。
3. 顺着这个语义，把父子关系也从 runtime 里那份按 entry 分桶的 children 真相收掉。改成 entry 注册时提供 `attach_child / children / detach_child` 三个 hook。父实例自己负责维护真实子实例集合。runtime 只负责调度和递归关闭。
4. 把 `./src/host.mbt` 收到同一套语义上。`HostData` 新增 `children : Set[InstanceRef]`。这份集合只表达“当前 host 拥有哪些子实例”。`windows / z_order` 继续只表达窗口业务状态。两层语义拆开了。
5. 调整了 host 的开窗和关窗流程。开子实例时先把实例 id 记进 `children`。再补窗口状态。关窗时走实例关闭链。由 detach 统一清理 `children`、窗口数组和 `z_order` 里的对应引用。没有再留一份窗口状态反推子实例的旁路。
6. 把 `./service/cli.mbt` 的 `help / exec` 入口改成实例 id 语义。帮助文案里的 `QUERY` 也改成了 `INSTANCE_ID`。空参数时还是默认根 host 实例。这样 CLI 和 runtime 的实例定位口径也对齐了。
7. 中间先撞到一个真实漏点。`boot_instance(..., parent=Some(host))` 创建了子实例，但没有自动登记回父实例的真实 `children`。结果 `query_tree` 第一次跑出来是空的。后面把 runtime 的 `attach_child` 调用补回去，树查询和 host 侧测试才重新对上。
8. 同步改了 `.src/entry.test.mbt`、`./src/host.test.mbt` 和 `./service/repl.test.mbt`。把旧的 `host#1/demo#1`、`host#1/host#1` 断言都换成了 `demo-1`、`host-2` 这类全局实例 id。
1. 继续查 host 样式几乎全失效的问题。先回看最近几次 host、bridge 和 `css(...)` 相关改动。把范围压到 host 视图、DOM runtime 样式作用域和浏览器桥三处。
2. 先读了 `src/host.mbt` 里的 `host_css()` 和 `css("host", ...)`。再对 `src/dom.mbt` 里的 `css(...)` 包装规则。确认 host 样式不是局部写坏。是整套规则外面又被自动包了一层 `.host` 作用域。
3. 再对了 host 根节点实际挂出来的属性。当前只有 `ui-id="host-root"`。没有任何节点真的带 `.host` 这个类。这样 `css("host", ...)` 最终生成出来的 `.host .host-root`、`.host .window` 之类选择器整体都命不中。
4. 这一步把样式问题压清楚了。根因不是内层 host 单独坏。是内外 host 共用的整套 CSS anchor 从一开始就没对上，所以启动后两层 host 都几乎没有样式。
5. 接着查内层 host 看起来像断连的问题。先读了 host 顶栏实现。确认连接状态、延迟、时间这三块目前只是静态文本节点，没有接任何响应式状态。
6. 再读了 `src/bridge.js` 的 `updateHostTray()`。确认浏览器桥现在是直接用 `document.querySelector('[ui-id=\"host-tray-...\"]')` 改页面里第一处命中的节点。
7. 这样第二个问题也定位出来了。外层 host 的托盘文本会被 bridge 直接改掉。内层 host 只是另一套同名静态节点，没有接到同一份状态，所以看起来一直像断开连接。
8. 最后把后续实现方向也压成一条。host CSS 要收回到真正命中的 anchor 主路径。连接状态、延迟、时间要做成公共的响应式 object，挂进 host 可传递的数据里。bridge 只更新这份公共状态。内外 host 再统一从这份状态渲染。
1. 继续追 UI 操作时偶发的 websocket 报错 `cannot start a new message before the last message end`。先回看 `service/bridge.mbt`、`src/bridge.js` 和最近 host/bridge 相关改动，把范围压到 browser 主连接的出站路径。
2. 查到已接入 browser 连接的正常运行期消息原来分了两条写口。一条是 `render_app(...)`、`request_browser(...)` 走 `live_batches -> flush_live_batches(...) -> ws.send_text(...)`。另一条是 `bridge:ping` 的 `respond_pong(...)` 直接对同一个 `ws` 写。
3. 这两条路径并发时序能直接解释报错。UI 操作触发 render batch 时，如果刚好撞上桥接层的 ping/pong，`moonbitlang/async` 的 websocket 就可能在上一条消息还没结束时开始下一条消息。
4. 先做了最小修正。新增 `enqueue_browser_json(...)`。把 `request_browser(...)` 和 `respond_pong(...)` 都收进 `live_batches`。这样已接入 browser 连接的常规协议消息先回到同一个发送队列。
5. 中间又重新检查了一遍，确认只收 `pong` 还不够严。`hello_ack` 之前也还是另一条直接写口。虽然它发生在握手时，但浏览器主连接语义更适合只保留一个 writer。
6. 继续把 `hello_ack` 也收回同一条路径。补了 `respond_hello_ack(...)`，由它统一把握手确认入队。`accept_browser(...)` 改成只登记活动连接，然后把 `hello_ack` 和首屏 render 都交给 `live_batches`。
7. `reject_browser(...)` 这次没有并进去。原因是拒绝连接发生在 browser 连接还没进入正常 live 流之前，还要紧接着发 close。它和已接入 browser 连接的长期消息流不是同一阶段。
8. 顺手把 `accept_browser(...)` 上已经没意义的 `async` 去掉了。因为这条函数现在只做状态登记和入队，不再直接 await websocket 写操作。
9. 补了两条 native 回归测试。第一条锁 `hello_ack` 和首屏 render 会按顺序进入同一个 `live_batches` 队列。第二条锁 render batch 和 `bridge:pong` 也走同一个队列。这样 browser 主连接的单写口语义有了直接覆盖。
## 04-04 上午
1. 继续收 host 实例的动作职责。先重新对 `src/host.mbt` 里的 `spawn`。确认它应该只负责启动子实例、开窗、更新窗口顺序和选中态。
2. 重新对了实例运行时的父子登记路径。确认 `boot_instance(..., parent=Some(host))` 已经会通过 `attach_child` 把 child 记回父实例。`spawn` 里再手动写一次 `v.children.add(child)` 只是重复职责。
3. 改了 `src/host.mbt`。删掉 `spawn` 动作里那句重复的 `v.children.add(child)`。保留窗口 id 分配、窗口数组更新、`z_order` 更新和 `selected_entry_id` 更新。这样 host 父子关系只剩 runtime 那一条主路径。
4. 接着收 `src/demo_editor.mbt` 的动作表。确认 `toggle_done` 和 `toggle_todo` 虽然作用对象不同，但都属于 toggle 语义。继续分成两条 action 会把同类动作拆成平行入口。
5. 改了 demo editor 的 action。删掉 `toggle_done` 和 `toggle_todo`。合成一个 `toggle`。不带参数时切换 done 过滤。带 todo id 时切换对应 todo 的完成状态。
6. 同步改了 demo view 里的绑定。`demo-toggle-done` 按钮改成 `bind("toggle", [])`。每个 todo 行里的 toggle 按钮改成 `bind("toggle", [ActionArg::Int(id)])`。这样 UI 和 CLI 都回到同一个动作入口。
1. 先按 review 重新对了前一版 tray 和 host 根样式的改动。确认两处都是真回归。`src/bridge.js` 把 tray 更新卡在 ws 可写时。断线和重连状态会停在旧值。`src/host.mbt` 里 host 根还写着 `100vw/100vh`。嵌套 host 会撑出父窗口。
2. 先补了这两个回归。把 host 根改成 `width: 100%`、`height: 100%` 和 flex 布局。把 tray 更新收成只有 socket 不可写时才本地补显示。先把 review 打回来的问题压住。
3. 接着被用户指出 tray 这条修法还是脏。虽然已经不再直接改文本节点，但本质还是 bridge 在接管显示层。这件事重新对齐以后，确认这条思路还是错的。
4. 中间一度又把问题想歪到了“要不要把浏览器 tray 状态同步给 service”。用户当场指出这件事根本不是需求。service 原来就自己维护浏览器连接事实。tray 这里只是浏览器本地显示状态，不该再额外搞一条同步回 service 的通道。
5. 重新回看了 `src/bridge.js`、`src/host.mbt`、`service/bridge.mbt`、`service/base.mbt` 和 `service/cli.mbt`。把这条错误路径完整压出来。多余的是 `bridge:status` 协议。多余的是 service 里的 host env 状态镜像。多余的是那批只为了 tray 文本同步加进去的状态结构和处理逻辑。
6. 最后直接把这条线整段删掉。`src/host.mbt` 里删除了 `HostBridgeState` 和相关 env 状态更新。tray 回到静态初值。`service/base.mbt`、`service/cli.mbt`、`service/bridge.mbt` 里删掉了浏览器 tray 状态同步和 service 处理逻辑。`src/bridge.js` 里也删掉了 `bridge:status` 上报和本地覆盖样式表那条补丁。
7. 收尾时把浏览器侧 tray 逻辑压回最小形态。现在只保留浏览器本地自己的 tray 状态更新和显示。不再把这份展示状态送到 service。也不再靠额外样式表去覆盖文本。
8. 同时删掉了那条围着错误模型写出来的 `host` mock 测试。避免继续把“浏览器本地展示状态要经过 service”这件事锁死在测试里。
9. 最后顺手清掉了 `new_host_env(...)` 里刚引入的一处歧义写法告警。
1. 把 todo demo 里的内联样式挪走了。样式原来直接塞在 DOM 定义里，结构读起来很吵，也和现在的样式主路径不一致。
2. 在 demo 的视图旁边补了一个 `demo_css()`。再用 `css('demo', S(demo_css()))` 挂作用域样式。根节点补了稳定 `class`。列表、按钮、空状态、条目样式都并进这张样式表里。
3. 保留了少量结构不变的 DOM 标记。没有顺手改 action、数据结构和交互路径，只处理样式组织方式和视觉表现。
4. 跑了 `moon check`。第一次有一个多行字符串直接返回的弃用警告。把返回值包进括号后再跑，检查通过。
5. 跑了 `npm run test-browser -- scripts/browser-tests/demo-editor.test.js`。确认 demo 浏览器用例通过，样式改造没有把原来的滚动行为带坏。
6. 顺手检查了 `metaeditor-dom-runtime` skill。先把触发范围改宽，让样式、DOM、UI 相关工作都能命中，不再只偏向 runtime 和 bridge 改动。
7. 往 skill 本体补了原来缺的几块稳定规则。补了 `css(...)` 的作用域规则。补了 `css(...)` 跟当前 reactive scope 一起注册和清理的生命周期。补了 `ui-id` 派生 class 的具体规则。也补了什么时候该用 `css(...)`，什么时候只留窄的 `style:*`。
8. 中间写过一段会误导人的伪例子。用户指出以后，把那段删了。改成只描述仓库里现有的真实模式，不再在 skill 里发明调用姿势。
9. 又重审了一遍 skill 和 reference。修掉了不存在的测试文件路径。修掉了写错的 bridge 命令细节。把这些硬错误清掉了。
10. 最后继续收紧 skill 内容。把会变的文件路径提示删掉。把“测试该盯哪些回归点”这类和现有测试重复维护的信息删掉。把过细的协议实现细节也删掉，只留下稳定语义和通用规则。
11. 每次改完 skill 都跑了校验。最后保持 skill 校验通过。
1. 审了工作区改动和 browser 测试耗时。先把全量 suite 跑了一遍。确认 browser 测试当时稳定在 3 秒左右。这个结果和预期差很多，所以先转去拆耗时。
2. 继续量启动链。把 service 启动、service 停止、browser harness 创建、页面加载、切 root 各自单独计时。确认主要耗时已经不在 service 多次启停，主要落在 browser harness、页面重载和测试隔离点。
3. 又量了同页切 root 的热路径。确认 service 侧只要能切 root，页面内复用是可行的。这个结论让后面的修复思路先落在“同页复用 + 去掉固定等待”。
4. 回看工作区里的 browser 改动时，先看到默认 `npm run test-browser` 被收窄成只跑一份用例。这个改动会把时间看起来压低，但不代表全量 browser 测试。先把这个判断记清。
5. 然后开始按这个方向改测试主路径。把“切顶层实例”落成了 service 控制口的 `roots` 能力。browser harness 也开始围着这个入口切 root。
6. 接着把 browser harness 继续往前推。除了切 root，又让它自己接管 service 生命周期。Node 直接拉起 `service.exe`。Node 自己选端口。Node 自己发控制口 `stop`。
7. 随后给 browser harness 补了几组 helper。包括 `setRoots`、`execRoot`、`syncBrowser`、`waitForCondition`、`useFakeBridge`、`restoreBridge`。目的是删掉固定 sleep，把等待点改成有明确语义的条件。
8. `demo-editor` 的滚动测试随后改了 fixture 生成方式。长列表不再靠页面里连点很多次按钮。先从 service 侧批量执行 `add`。页面打开以后只保留一次真实 Add，专门测滚动位置。
9. `host` 和 `bridge` 两组 browser 用例也一起接到了这条路径。单页复用保住了。固定时间等待删掉了。等待改成事件消息和 DOM 条件。
10. 为了让 harness 能显式等 browser 处理完成，又在 service 控制口加了 `sync` 命令。browser harness 每次改 root、调 action 以后，都能走这条路径等 bridge 完成同步。
11. 同时把 service 的 batch 行为也改了。browser 没连上时，不再继续把旧 render batch 塞进队列。这个改动是为了配合同页复用，也顺手补了 native 回归测试。
12. 这一版跑完以后，全量 browser 测试回到了大约 1.6 秒。`scripts/test-all.ps1` 也能跑绿。表面上看，时间确实比 3 秒低了不少。
13. 但用户随后人工审查，先指出了第一处模型错误。`roots` 这个能力本来只需要一个 API。这里却把它扩成了 CLI 能力。边界被做宽了。
14. 用户接着指出第二处设计错误。browser 测试为了配合这条 CLI 路径，额外长出了一整套自己管理 service 生命周期的逻辑。代码体积大。职责也脏。
15. 用户又指出一个直接回归。默认 root host 被拿掉以后，正常启动 `meta` 时页面没有任何内容。这个影响已经超过测试范围，落到了正常使用路径。
16. 最后又把更底层的问题点清了。instance 相关的管理职责也应该由 `src` 自己负责。继续把这层放在 service 侧，没有必要。前面这版改动把本来该收回共享模型的事情，继续留在了 service。
17. 当前先不继续补代码。先把这次实现经过、跑通后的结果、以及用户审出来的三类问题记下来。后面单独重做模型和边界。
## 04-04 下午
1. 继续按“把能搬到 `src` 的运行时语义搬走”这条线动手。新增了 `src/runtime.mbt`。把 root 集合、默认 `host` root、实例 help/exec、DOM render 主路径都收进 `src`。同时把 `service/base.mbt`、`service/cli.mbt`、`service/bridge.mbt` 往宿主壳收。`service` 不再自己拼 `app_runtime / host_dom_state / mounted_roots`。`roots` 也从 service 的 help 文案里删掉了。
2. 同步补了 `src/runtime.test.mbt`。准备把默认 root、set roots、runtime help/exec、runtime render 这些新职责锁住。然后把 `service/repl.test.mbt` 和 `service/service.test.mbt` 改到新 runtime 口径。原来依赖 `run(runtime, "roots", ...)` 的地方开始往 `src runtime` 迁。
3. 第一次跑测试时先撞到几条基础问题。`src/runtime.mbt` 里多写了两个没必要的 `mut`。字符串插值里还直接写了 `join(", ")`。MoonBit 这里不认。先把这些 compile 级问题按最小补丁修掉。
4. 修完以后，native 整组还是会被测试脚本 5 秒预算砍掉。中间还因为并行跑测试和手动打断，留下了残余 `moon` 和 `service.internal_test.exe`。`_build/.moon-lock` 和 `.mooncakes/.moon-lock` 都被占住。先查了进程。再把残留测试进程杀掉。把锁源头清干净。
5. 后面改成用测试脚本的 `-TestFilter` 串行缩范围。把 `service` 包里的 `native:` 测例一条条单独跑。最后定位到真正超时的是 `native: browser hello_ack and render share one browser queue`。不是整组随机慢。是这一条自己会沉默卡住。
6. 这条超时的根因也查清了。前面为了迁新 runtime 口径，把测试里的 `run(runtime, "roots", "host")` 删掉了。删掉以后，`respond_hello_ack(...)` 后面不再自动产生第二个 render batch。但测试还保留着第二次 `live_batches.get()`。于是队列里只有 `hello_ack`。第二次 `get()` 就一直等。最后被脚本 5 秒预算砍掉。
7. 按这个判断，只对那条用例补了最小修正。在 `respond_hello_ack(...)` 后显式调一次 `@src.runtime_render(editor_runtime(runtime))`。然后用脚本单独回归 `native: browser hello_ack and render share one browser queue`。确认这条通过。运行时间回到秒内。
8. 继续顺着这个问题往下收测试等待。把 `service/repl.test.mbt` 里 `ws.recv()` 这类等待。还有 `service/service.test.mbt` 里 `live_batches.get()` 这类等待。先改成带超时的 helper。这样以后再出错时，不会整条测试沉默挂满 5 秒。会直接报出卡在哪一步。
9. 改完以后又被指出这还是局部重复。于是把两份局部等待逻辑抽成 `service/test_helper.mbt` 里的共用 helper。后面两组测试都开始复用这一份等待语义。没有再各自抄一套轮询和超时。
10. 再往下又把等待原语继续收了一步。把共用 helper 从“等 queue/json”那种窄 helper，改成更通用的 `wait_timeout`。调用方只提供 `poll : () -> T?`。这样 `live_batches.try_get()` 和 websocket 收包都能走同一条主路径。`service/service.test.mbt` 里的几处 queue 等待已经统一到这条 helper。
11. 中间一度想按 MoonBit 口径用 `./mide.ps1` 做语义级 rename。先回看了 MoonBit skill 和 `mide --help`。又试了几种 `rename --loc` 写法。包括相对路径、包目录路径和 bash 风格路径。wrapper 都会把 `--loc` 路径喂坏，持续报 `Invalid argument` 或文件找不到。这里没有继续硬耗。最后回退成最小补丁，把 helper 名字和调用点直接改成了 `wait_timeout`。
12. 最后把一个更大的判断也记下来。测试里的等待和一次性请求等待，应该默认都有超时。这样失败时才有具体步骤名。常驻事件循环和后台消费者，不该硬塞超时。后面的 agent 如果继续收测试等待，应该沿 `service/test_helper.mbt` 这条主路径继续做，不要再在各测试文件里各写一份。
1. 继续顺着测试等待这条线往下查。先读了 `service/test_helper.mbt`、`service/repl.test.mbt`、`service/service.test.mbt`。又把 `runtime` 迁移后的 `service/base.mbt`、`service/bridge.mbt`、`service/cli.mbt` 串起来看了一遍。目标只放在“测试和一次性请求等待默认带超时”。
2. 先撞到一处编译级口径问题。`wait_timeout(...)` 里接的轮询闭包还在写旧式 `fn() { queue.try_get() }`。`try_get()` 会带错误效果。MoonBit 现在不再接受这类隐式写法。局部测试先因此编不过。
3. 先把等待原语收回一条主路径。把 `wait_timeout(...)` 和 websocket 单次收包的超时等待一起放进 `service/base.mbt`。`service/test_helper.mbt` 只保留薄包装。没有再在测试辅助里留一套平行实现。
4. 顺手把运行时里两处一次性等待也接回同一条语义。`service/bridge.mbt` 里的 browser request 不再手写本地轮询。改成走带步骤名的 `wait_timeout(...)`。`service/cli.mbt` 里的 repl 单次回包也改成走同一套超时 helper。这样失败时会直接报出卡住的步骤名。
5. 同步把 `service/service.test.mbt` 里围着 `live_batches.try_get()` 的等待都改成新写法。轮询闭包改成显式吞掉 `try_get()` 的错误结果。先把编译重新拉回可过状态。
6. 先跑了 `moon check`。检查通过。再单独跑 browser queue 和 repl 相关的 native 测试。确认新 helper 已经能接住原来最容易沉默挂住的几条等待。
7. 再跑整包 `./scripts/test-native.ps1` 时，翻出三条旧时序残留。它们还默认 browser hello 之后会自动出现首屏 render batch。现在的 runtime 口径已经变了。首屏 render 需要显式调 `runtime_render(...)`。
8. 按这个判断，只补了测试最小修正。三条用例都改成先显式 `runtime_render(...)`，再去等首屏 batch。没有顺手改当前 runtime 行为。
9. 最后重新回归 `moon check` 和 `./scripts/test-native.ps1`。native 回到 `26/26`。说明这次把测试等待和一次性请求等待继续收进同一条超时主路径后，编译、局部回归和整包 native 都重新对上了。
1. 继续顺着“薄包装 helper 太多”这条线往下收。先把 `service/base.mbt`、`service/bridge.mbt`、`service/cli.mbt`、`service/repl.test.mbt` 里和 websocket 等待、browser 入队、单次发包有关的 helper 重新看了一遍。目标只放在删掉那种只换名字、不增加语义密度的薄壳。
2. 先把最薄的一层拿掉。`service/base.mbt` 里的 `recv_ws_json_timeout(...)` 删掉了。保留 `wait_timeout(...)` 作为唯一通用等待原语。repl CLI 和 repl 测试里原来那层“收一个 websocket JSON 包再超时”的 helper，不再单独保留。
3. `service/cli.mbt` 里的 repl 单次回包等待改成在调用点直接建 queue。直接起一个后台收包。再用 `wait_timeout(...)` 等这次请求的回包。`service/repl.test.mbt` 也按同一口径改了。测试和运行时没有再共享一层只有一个调用点的 recv helper。
4. 接着收 `service/bridge.mbt`。删掉了 `enqueue_browser_json(...)`。`request_browser(...)`、`respond_pong(...)`、`respond_hello_ack(...)` 这些地方直接写 `live_batches.try_put(...)`。没有再为“往队列塞一个 JSON”保留单独函数名。
5. 同一处又把 `send_json(...)` 删掉了。`reject_browser(...)` 和 `respond_repl(...)` 改成直接 `ws.send_text(Json::object(...).stringify())`。这样 websocket 单次发一个 JSON 包这件事，也不再挂一层只包 `stringify()` 的薄壳。
6. 顺着调用面继续看，把已经没有独立意义的 browser request 包装也一起删了。`query_browser(...)`、`exec_browser(...)`、`sync_browser_if_connected(...)` 都拿掉了。当前只保留还在 CLI 调用面上有明确语义的 `sync_browser(...)`。
7. 中间第一次回归 native 时，立刻翻出一处真实编译回归。两处 `send_json(...)` 内联时少包了 `Json::object(...)`，MoonBit 会把 map 推成 `Map[String, String]`，直接没有 `stringify()`。按最小补丁补回显式 `Json::object(...)` 和 `to_json()` 以后，编译重新对上。
8. 这次顺手还带出一个死 helper。`browser_connected(...)` 在删掉 `sync_browser_if_connected(...)` 以后已经没调用面了。一起删掉，避免再留空名字。
9. 最后回归了 `moon check` 和 `./scripts/build-native.ps1 -Package service -Test -TestPackage service -TestFilter "native: repl*"`。检查和 repl native 测试都通过。说明这次把 websocket 收包、browser 入队、单次发包这几类薄包装收掉以后，主路径已经重新接上。
1. 继续收 service 里围着 browser bridge 和一次性等待长出来的辅助函数。重新看了 `service/base.mbt`、`service/bridge.mbt`、`service/cli.mbt` 和 `service/repl.test.mbt`。确认这一块真正需要保留的主路径只有 `wait_timeout(...)`、`live_batches.try_put(...)` 和直接 `ws.send_text(...)`。
2. 先删了 `service/base.mbt` 里的 `recv_ws_json_timeout(...)`。这个 helper 本质只是“起一个 queue，再用 `wait_timeout(...)` 等一次 `ws.recv()`”。没有额外语义。继续单独留着只会把等待路径做宽。
3. 再收 `service/bridge.mbt`。把 `browser_connected(...)`、`enqueue_browser_json(...)`、`query_browser(...)`、`exec_browser(...)`、`sync_browser_if_connected(...)`、`send_json(...)` 这几层包装一起删掉。对应调用点直接回到 `runtime.live_batches.try_put(...)`、`request_browser(...)` 和原生 `ws.send_text(...)`。这样 browser 请求、pong、hello_ack 和 repl 响应都回到更短的一条发送路径。
4. 同步改了 `service/cli.mbt` 和 `service/repl.test.mbt`。原来两处围着 websocket 单次收包又各包了一层 helper。现在都直接起 queue，再走 `wait_timeout(...)`。测试和运行态的“一次性等待”口径重新对齐。
5. 这组删冗余改动最后单独提交成了 `80f8ebd`。提交信息是 `shrink service bridge wait helpers`。后面的工作明确从这个点继续。没有把别的未确认模型改动混进这笔提交。
6. 提交完以后，又回头复盘了前面那批未提交的 `ui-id` 改动。目标不是继续改代码，先把问题重新讲清楚给后续 agent。重点放在“表面删了 `ui-id`，实际上是不是只是换了一个壳继续暴露同一层语义”。
7. 重新审了 `src/bridge.js`、`scripts/test-browser.js`、`scripts/browser-tests/*.js` 和前面改过的 `host/demo` 相关 class。确认之前那版里最直接的偏差是把原来的 `[ui-id=...]` 查询机械换成了 `.entry.entry-demo`、`.window`、`.demo`、`.demo-add` 这类 selector。名字变了，浏览器层继续认结构协议这件事没有变。
8. 先把这些残留按位置分开记清楚。第一类是生产桥接层。`src/bridge.js` 还留着 `target.selector` 入口。tray 更新也改成了 `querySelectorAll('.tray-connection')` 这种 class 查询。说明浏览器运行时自己仍然在认 DOM 结构名。第二类是测试 harness。`scripts/test-browser.js` 里的 `waitForUI/clickUI/dblclickUI/textOfUI/countUI` 现在都直接吃 selector。第三类是 browser 测试脚本本身。几份测试里把原来基于 `ui-id` 的行为和等待，平移成了基于 class/selector 的行为和等待。
9. 中间又把“哪些 class 本身有问题，哪些只是被拿错用途”单独拆开了。像 `host/demo` 里显式写出来的样式 class，如果只拿来做样式锚点，本身并不一定错。真正的问题是 browser bridge 和 browser test 继续把这些 class 当成正式查询协议。这会把样式层再次抬成结构语义层。
10. 这一步以后，模型判断比前一版清楚了。错的不是“浏览器里出现了 class”。错的是“执行和查询仍然直接吃浏览器结构选择器”。也就是浏览器层还在自己理解 UI 结构，而不是围着 runtime 的稳定身份工作。
11. 接着又被用户点出了更关键的一处偏差。前面那版甚至把 `click` 也改成了直接吃 selector。这个问题比普通等待更重。因为 `click` 属于执行语义。执行层本来就不该直接接受 DOM 检索语言。
12. 顺着这个点，重新把查询层和执行层的边界压清楚了。查询层可以问“这个语义对象现在对应哪个 runtime node”。执行层只该接已经解析好的稳定目标，比如 `VNodeID`。如果让 `click(selector)` 成为正式接口，就等于把“在 DOM 里搜节点”和“对目标执行动作”揉回同一层。浏览器又重新成了主语。
13. 继续讨论以后，用户给出了一条更直的实现方向。不要再把 `ui-id` 翻译成 selector。应该让 `bridge.js` 统一暴露一层很薄的“按 `src` 里的 `ui-id` 查询 `VNodeID`”能力。上层如果想点 `entry:demo`，先通过这条能力查出当前对应的 `VNodeID`，再按这个 id 去执行 click。
14. 这条判断当场重新定下了后续口径。`ui-id` 继续属于 `src` 的查询语义。`bridge.js` 不自己发明一套 selector 查询协议，只是暴露现有 runtime 查询能力。执行接口只认 `VNodeID`。浏览器侧 selector 最多只能留在很窄的观察性测试代码里，不能继续冒充正式执行入口。
15. 最后把这次讨论的结论记清楚留给后面的 agent。前面未提交的 `ui-id` 改动里，真正需要重做的不是“要不要保留 class”，而是“查询层和执行层有没有重新混在一起”。后续应该优先删掉桥接层和 harness 里那些直接吃 selector 的执行入口，再把测试需要的“按语义对象定位节点”能力收回到 `src` 的 `ui-id -> VNodeID` 查询主路径。
1. 继续接 browser 语义这条线。先把目标重新压清楚。查询输入不是单个 `ui-id`。输入本来就是层级查询字符串。每次都该交给 `src` 现算当前节点。
2. 中间先走偏了一次。在 `bridge.js` 里加了本地 `ui-id -> VNodeID` 映射。用户指出这条路不对。因为这样等于 browser 又持有了一层语义缓存。和“查询权只在 `src`”冲突。
3. 随后把这层错误缓存撤掉。`bridge.js` 回到只认 `VNodeID`。browser 不再解析查询字符串。也不再缓存任何 `ui-id` 或查询结果。
4. 在 `src/runtime.mbt` 补了内部查询解析入口。直接复用现有 `query_node(...)` 语义。service 以后每次都先走这里拿当前节点 id。没有再发明另一套查询规则。
5. 在 `service/bridge.mbt` 把 browser 请求收成一个内部入口。输入是查询字符串和请求类型。内部先调 `src` 解析当前节点 id。再向 browser 发只带 `id` 的 request。没有把这层能力扩成 CLI 命令面。
6. 中间又在测试里犯了一次老问题。顺手写了新的等待 helper。用户指出 service 里已经有现成等待原语。这里不该再多包一层。随后把多余等待 helper 删掉。测试只回到现有 `wait_timeout(...)` 加最薄的 websocket 收包。
7. 给 service 侧等待规则补了硬注释。直接写在 `wait_timeout(...)` 上方。明确 service 里的等待统一复用这条原语。不要再新造等待 API 或等待 helper。
8. 新增了两条 native 回归测试。一条锁 query 路径。一条锁 exec 路径。两条都只看一件事。service 会先让 `src` 解析查询字符串。发给 browser 的请求只带当前 `id`。不会把查询字符串继续传给 browser。
9. 这两条测试第一次整组跑时互相干扰。单跑能过。整跑会失败。说明问题在时序，不在主逻辑。后面把前置改成先等 `hello_ack`，再显式 `runtime_render(...)`。把“browser 已接上”和“当前 DOM 已渲染”拆开。整组 native 才重新稳定。
10. 顺手补了一处已有样式残缺。`demo_editor` 里的 CSS 已经改成 `.summary/.list/.empty`。DOM 侧还没补对应 class。把 `demo-summary`、`demo-list`、`demo-empty` 的 class 一起补齐。避免样式表和节点锚点继续分叉。
11. 最后回归了 `moon check`、`moon test` 和 `./scripts/test-native.ps1`。三项都通过。说明这次“查询字符串先走 `src`，browser 只认 `id`”这条主路径已经接上。
12. 另外把一个残余单独记下来。`bridge.js` 里还保留了 tray 的本地展示更新。它不参与 query/exec 协议。只负责把连接状态、延迟和时钟写进 tray 文本。但 bridge 还是知道 `.tray-connection`、`.tray-latency`、`.tray-time` 这几个结构锚点。这条结构知识还没收回 `src`。
1. 继续接 `bridge.js` 这条线。先回看前面的记录，再重读 `src/bridge.js`、`service/bridge.mbt`、`scripts/test-browser.js` 和几份 browser 用例。重新确认正式的 query/exec 已经走回 `service -> src.runtime_resolve_query(...) -> browser id`。当前更明显的残留只剩 browser 还在直接改 host tray 文本。
2. 一开始先想过给 `app-info` 留静态豁免，不让 `resetManagedDom()` 清掉它。随后把这版放掉。原因很直接。这样会给 bridge 多加一层页面结构规则。边界会变宽。
3. 最后按更短的口径处理状态显示。连接状态只留给 `index.html` 里的 `#app-info`。`connected` 时把它隐藏。`connecting`、`reconnecting`、`disconnected`、`rejected` 和初始态再显示并更新文案。这样页面提示还在，bridge 不需要再碰业务 UI。
4. 同时把 `src/bridge.js` 里整套 tray 本地更新删掉了。`trayState`、连接/延迟/时钟标签函数、`renderHostTray()`、`updateHostTray()`、对应的状态回写和定时刷新都一起删。browser bridge 不再查询 `.tray-connection`、`.tray-latency`、`.tray-time`。也不再改 host 里的 tray 文本。
5. `hello_ack` 之后 body 还是会被清空。这里没有再去改 DOM 清理规则。改成在 `renderStatus()` 里先检查 `#app-info` 是否还在。不在就临时补回一个。这样刚连上时状态条会被隐藏。后面如果断连、重连或被拒，状态条还能重新出现。
6. 这次改动范围只收在 `src/bridge.js` 和 `index.html`。没有继续碰 browser 测试。也还没跑测试。先把 bridge 里那段多余的 host tray 显示逻辑删干净。
1. 先回看了 host 顶栏显示这条线。确认前一版把 host 自己的延迟显示能力拆掉了。`src/host.mbt` 里 tray 节点还在。真正没了的是显示数据的维护路径。
2. 一开始先看偏了。以为只要把 `bridge.js` 里原来那套 tray 文本更新接回去就行。后面被指出方向不对。延迟和时间应该回到 host 自己维护。
3. 重新把边界压清楚了。host 顶栏显示应该由 `src` 里的状态驱动。浏览器侧不该直接去改 tray DOM。`NET` 状态这次先不管，因为 service 侧现在给不了这层语义。
4. 第一版先把 tray 数据做成共享响应式对象。对象先挂在 `HostEnv` 里，再由 host 顶栏去读。这样同一个 runtime 里的 host 实例能看到同一份数据。
5. 这版虽然把显示接回来了，但结构还是偏宽。tray 数据还是经由 `env` 注入。没有做到 host 模块自己直接持有全局状态。
6. 后面继续收了一步。把 tray 状态改成 `src/host.mbt` 顶部的模块级全局响应式变量。host 顶栏直接读这份全局状态。service 侧也直接写这份全局状态。中间那层 `env.tray` 去掉了。
7. 同时把测试重置也接上了。让每次 `reset_test_state()` 时一起重置 host tray 状态。避免全局状态把别的用例污染掉。
8. 这一版里还顺手把 tray 里的 `NET` 固定文本删掉了。顶栏只保留延迟和时间两块显示。目标是让首屏直接看到 `xxms` 和时间，不再混着旧占位文案。
9. service 侧先用了最省补丁的办法补显示数据。时间每秒刷新一次。延迟先用现有 `sync` 请求量一遍 `service -> browser -> service` 的往返时间，再把结果写回 host tray。
10. 这一步把显示重新做出来了。`moon test` 和 native 测试都通过。表面上看 tray 数据已经能跟着全局状态走。
11. 但随后人工验证时又暴露出第一处偏差。现在显示出来的延迟定义已经变了。原来更接近浏览器本地 RTT。现在变成了 service 侧整条请求路径的往返时间。数值明显变大，常见值从接近 `1ms` 变成了接近 `31ms`。
12. 接着又暴露出更关键的第二处偏差。首连以后时间和延迟并不会自己持续更新。不是单纯刷新周期偏慢。是真正没有稳定往前推。
13. 最后把现象重新讲准了。现在其实是 service 后台在改 host 全局响应式状态，但这条后台更新没有接进会主动 flush DOM 的主路径。所以页面上看起来像没更新。只有手动点页面里的东西，之前积压的时间和延迟文本才会一起跳出来。
14. 这样回头看，这次已经把“host 顶栏显示由 host 自己的全局响应式状态驱动”这件事接上了，也把浏览器直接改 tray DOM 的旧口径继续压住了。
15. 但这次最后还没做完的地方也得单独记清。第一处是延迟测量口径还不对。现在量到的是 service 侧整条请求往返，不是原来那种更轻的本地 RTT。
16. 第二处是更新时间主路径还没接上。后台改全局响应式状态以后，没有稳定触发 DOM flush。这个问题比显示格式更根本。
17. 第三处是时间和延迟现在被塞进同一个后台循环里。结构上还不够干净。后面继续收时，应该先把“谁负责把后台状态变化真正推到前端”这件事接通，再决定延迟到底要按哪条语义来量。
1. 重新看了 devlog 末尾那条 host tray 更新问题。把现象重新压清楚。问题不在 query。也不在 render 主路径。问题在 service 后台改了 reactive 状态以后，没有把已有的增量更新主动 flush 出去。
2. 接着补读了 src/host.mbt、service/cli.mbt、service/bridge.mbt、src/dom.mbt 和 src/reactive.mbt。确认当前DOM 主路径本来就是增量 patch。Cel.set() 会排 effect。flush() 会把 effect 产出的 UpdateText 这类命令推出去。缺口只是事件外状态更新后没人调 try_flush()。
3. 中间先讨论过几种名字。包括 tray 专用入口、runtime 包装入口和所谓 external flush 入口。最后都放掉了。结论很直接。仓库里已经有 flush 和 try_flush。不该再造一层同义 API。
4. 先按最小补丁修了 tray 更新。只在 service/cli.mbt 的 refresh_host_tray_now(...) 里，@src.set_host_tray(...)后面补了 @src.try_flush()。旁边加了中文注释。明确这是事件外 reactive 更新。改完要手动把增量 DOM 命令推出去。
5. 接着把这条规则写进 metaeditor-dom-runtime skill。明确事件处理器路径会自己 flush。service 定时器、bridge 回调这类事件外 reactive 更新，改完直接调现有 try_flush()。不要再造第二套 flush API。也不要把这种增量更新误做成runtime_render()。
6. 随后又回头审了前几次相关提交。重点看 tray、bridge 和等待 helper 这几条线。确认还有两类残留冗余。第一类是service/cli.mbt 里的 set_host_tray(runtime, ...) 薄包装。它只 ignore(runtime) 再转调@src.set_host_tray(...)。没有额外语义。第二类是 websocket 单次收包逻辑在 CLI 和测试里各写了一份。
7. 最后把这两类残留一起收掉。删了 service/cli.mbt 那层 set_host_tray(runtime, ...)。service/cli.mbt 和service/bridge.mbt 都直接调 @src.set_host_tray(...)。又把 websocket 单次收 JSON 收回 service/base.mbt 的recv_ws_json(...) 一处。service/cli.mbt 和 service/repl.test.mbt 不再各自抄 queue 加 wait_timeout(...)。
8. 收完以后跑了 moon check。结果通过。说明这次把事件外 flush 口径和两处薄包装一起收掉以后，当前编译状态还是对的。
9. 记住现在浏览器测试还是坏的，没有修复，在准备彻底修复之前不要碰它
1. 继续查 demo 窗口操作后样式整片消失的问题。先把现象压准。单独把 `demo` 当根挂出来时样式正常。放进 host 窗口以后，点 `demo-add` 这类按钮就会掉样式。
2. 重新对了 `src/demo_editor.mbt`、`src/host.mbt`、`src/dom.mbt`、`src/reactive.mbt` 和 browser 侧实际现象。确认问题不在 `demo_css()` 文本，也不在选择器失配。真正丢的是注册出来的 stylesheet。
3. 顺着交互链继续看。确认点 demo 按钮时，事件会冒泡到 host 窗口根节点的 `onclick`。这会触发 `focus_window`。外层 `h_map_dyn` 对应的父 effect 因而重跑。
4. 再往下对 cleanup 语义。确认 `src/dom.mbt` 里的 `css()` 之前是用 `onclr(...)` 挂清理。`src/reactive.mbt` 里的 `onclr(...)` 会优先挂到当前 effect。这样 demo 窗口里的 stylesheet cleanup 实际落在了 host 外层 effect 上。父 effect 一重跑，就会先发 `RemoveCss(...)`。子树本身又是复用的，不会补新的 `SetCss(...)`，样式于是整片掉光。
5. 按这条判断直接改 runtime 主路径。给 `src/reactive.mbt` 补了 `on_scope_clear(...)`。这条入口只把 cleanup 挂到当前稳定 scope，不再跟当前 effect 绑定。
6. 同时改了 `src/dom.mbt` 里的 `css()`。把静态样式和动态样式两条 cleanup 都从 `onclr(...)` 改成 `on_scope_clear(...)`。这样 stylesheet 生命周期回到真正的子树 owner，不会再被父 effect 重跑顺手清掉。
7. 中间补过一条 `src/dom.test.mbt` 白盒回归，想锁“父 effect 重跑时不要发 `RemoveCss`”。后面又把这条测试删掉。原因也记一下。这条测试只能锁底层触发点，不能直接覆盖 host 里开 demo 窗口再点击的真实坏相，不够当最终回归。
8. 最后把 `metaeditor-dom-runtime` skill 一起改了。把原来会误导 agent 的“在 render path 里调用 `css(...)`”口径删掉。明确写成硬规则：`css(...)` 是 stylesheet 注册，不是普通 render 语句。禁止再把 raw `css(...)` 塞进 `Dyn(...)`、`h_map_dyn(...)` item render，或者任何可能落到父 effect cleanup 的路径。
9. 改完以后跑过一次 `moon test`。当时是 `110/110`。删除那条白盒测试以后没有再补跑。
## 04-04 晚上
1. 继续顺着 demo 窗口操作后样式整片消失的问题往下收。先把根因重新压准。问题不在 CSS 文本。也不在选择器命中。问题在 `css(...)` 的使用层级。它本来就不该写进组件 render path。
2. 重新对了 `metaeditor-dom-runtime` skill。先把最关键的误导口径改掉。明确写成 `css(...)` 不是普通 render 语句。禁止再把 raw `css(...)` 塞进组件 render、`Dyn(...)`、`h_map_dyn(...)` item render，或者任何 DOM 更新时会反复执行的路径。
3. 接着把代码按同一条语义改掉。没有继续在 runtime 里补 effect/scope 生命周期补丁。直接把 `src/demo_editor.mbt` 和 `src/host.mbt` 里原来写在 `view` 里的 raw `css(...)` 拿掉。
4. 把 `css(...)` 改成模块级定义。现在 `css(...)` 直接返回 `StyleSheet` 对象。`demo` 和 `host` 两份静态样式都改成模块级 `let ...: StyleSheet = css(...)`。样式定义不再混进组件 render。
5. 给 `StyleSheet` 补了 `reset(...)`。这条方法会重算 scoped css 文本，替换当前样式内容，再立刻发一条新的 `SetCss(...)`。后面如果真要改整张样式表的内容，有明确对象可改，不用再回到 render path 里重新定义 `css(...)`。
6. 中间把前一版多余的样式注册外壳删掉了。原来那层单独的注册入口没有继续保留。现在模块级静态样式直接用 `css(...)` 本身定义，不再多绕一层名字。
7. 保留了一条包内补发路径。原因也单独记一下。browser 每次 `hello_ack` 以后会清空受管 DOM 和 stylesheet。模块级静态样式需要在根重新渲染时补发一次。这条补发逻辑只留在包内给 runtime 和测试根挂载使用，没有继续扩成对外 API。
8. 同步把测试改到新语义。`src/dom.test.mbt` 不再围着旧版 render-time `css(...)` 生命周期写断言。改成直接锁模块级样式定义、`reset(...)` 更新、media 选择器前缀和空选择器作用域。`src/host.test.mbt` 也改回走统一的根挂载样式补发路径。
9. 最后重新对了一遍 skill 文案，把残留的旧描述继续删干净。把 `css(...)` 当前语义明确成模块级 stylesheet definition。把 `StyleSheet::reset(...)` 的用途也写清楚。强调它只用于替换整张样式表内容，不能拿来冒充局部动态样式。
1. 继续收 `css(...)` 作用域里没补完的 `@media` 规则。先重新对了 `src/dom_helper.mbt` 和 `src/dom.test.mbt`。确认主路径已经有了。`css_scope_block(...)` 会递归处理 `@media / @supports / @container / @layer`。这次真正缺的是复杂形态的覆盖。
2. 先补了三条 `dom` 回归。分别锁 `@media` 里的多选择器、`@media` 里的空选择器、`@media` 里再嵌 `@supports`。跑 `moon test` 以后这三条先打红。说明简单 `@media` 已经能过，复杂一点的作用域路径还没有被正式锁住。
3. 顺着这组失败继续收实现。把“可递归处理内部规则的 at-rule”判定收成一处。`@media / @supports / @container / @layer` 都回到同一条递归路径。测试断言也改成只盯关键语义片段，不再卡空白格式。改完以后 `moon test` 回到全绿。
4. 接着继续查 selector list 的逗号切分。原来 `prefix_css_selectors(...)` 直接 `split(',')`。这会把 `:is(.a, .b)` 这种括号内部的逗号也拆开。浏览器层面的复杂选择器在这里会被前缀坏。
5. 先在函数旁边补了中文注释。写清为什么 selector list 需要按逗号逐项补 scope。也写清旧实现只支持顶层逗号列表，括号内部带逗号的写法当时还不能正确解析。
6. 随后把这块直接改掉了。新增一个手写扫描 helper，只在顶层逗号处分段。圆括号、方括号、单双引号里的逗号都会跳过，不再误当成 selector 分隔。这样 `:is(.a, .b)`、attribute selector 和字符串里的逗号都能保住。
7. 同时补了两条新的 `dom` 回归。一条锁单个 `:is(.a, .b)` 选择器整体保留。另一条锁 `:is(.a, .b), .item` 这种“括号内逗号和顶层逗号并存”的写法只会切顶层逗号。
8. 中间第一次编译没过。问题很小。新 helper 返回数组以后，旧的 iterator 链没有一起收干净。随后把这段改成直接数组循环，编译错误就消掉了。
9. 最后重新跑了 `moon test`。结果是 `114/114`。说明这次 CSS 作用域路径已经能正确处理 `@media` 内多选择器、空选择器、嵌 `@supports`，也能正确处理 `:is(.a, .b)` 这类括号内部带逗号的选择器。
## 04-05 下午
1. 先做了一轮代码静态审查。没有补跑全量测试。也没有做 benchmark。先把最值得优先处理的 4 个性能点记清。`dom` 里 `Dyn` 删除检查还是平方级。DOM batch 在 `src -> service` 之间有重复 JSON 编解码。`reactive` 会为同一个 effect 重复订阅同一个 `Cel`。`host` 的窗口状态读写还留着多处数组扫描。
2. 先改 `src/dom.mbt` 的 `cleanup_removed_nodes(...)`。原来每个旧节点都线性扫一遍新节点。列表大一点就会放大成平方级。现在先把新节点 id 建成集合。再扫旧节点做删除判断。删除检查回到线性级。
3. 接着改 DOM batch 发送链。原来 DOM 层先把每条 `DomCmd` 转成字符串。service 再逐条 `json.parse(...)`。发 websocket 前又整体 `stringify()`。这段全是额外 CPU 和分配。现在把 `DomCmd` 直接转成 `Json`。`runtime -> service -> websocket` 这条线上只保留最后一次整体 `stringify()`。
4. 再改 `src/reactive.mbt` 的依赖跟踪。原来一个 effect 里多次 `get()` 同一个 `Cel`，会重复把 effect 推进 `subs`。写入时会重复 queue。cleanup 也会重复 filter。现在给 effect 自己挂一份订阅表。`track(...)` 先查这份表。已经订过就直接返回。`clear(...)` 再统一退订。
5. 第一轮继续收 `src/host.mbt` 的窗口热路径。`window_layer` 和 `topbar` 先建一次窗口查表。每个窗口项不再反复线性扫 `windows`。`detach_child(...)` 清 `z_order` 时也改成先记保留窗口 id，再线性过滤。旧的 `window_z_index(...)` 一起删掉。
6. 同时补了两条小测试。第一条锁 bridge batch 直接发 `Json`，不再走字符串中转。第二条锁 `track(...)` 对同一个 effect 和同一个 `Cel` 只订阅一次。跑了 `moon test` 和 native 测试，都通过。
7. 后面按 review 重新审 `host`。确认前一版只收了渲染热路径。`focus_window` 和 `close_window` 两个动作里还在按窗口 id 扫 `windows`。第 4 个问题只能算部分修复。
8. 第二轮继续改 `src/host.mbt`。`focus_window` 改成直接按 `z_order` 判窗口是否存在，再复用 `bring_to_front(...)`。`close_window` 改成先建窗口查表，再按 id 取实例。原来的 `find_window(...)` 随后已经没有用途，直接删掉了。
9. 这轮以后，最开始静态审查列出的 4 个性能点都已经接上主路径。没有继续留旧入口。也没有再长新状态。
10. 随后又补了两条 `host` 回归测试。第一条锁双窗口时，聚焦动作会让窗口层级跟着更新。第二条锁关闭一个窗口以后，剩余窗口和实例关系仍然正确。
11. 新测试第一次打红。问题出在前一版把窗口 `z-index` 绑在 `h_map_dyn` 的 `idx()` 上。这个值不是响应式值。窗口重排以后样式不会自己更新。
12. 最后把窗口 `z-index` 收成基于焦点状态的响应式值。前台窗口抬一层。其余窗口同层。相对顺序继续交给 DOM 顺序。这个实现更短，也和当前窗口模型一致。
1. 先把测试脚本清理进程这件事重新拆开看。读了构建脚本和测试脚本。确认当前 native 构建前后的清理会按固定构建产物路径扫描 `service.exe`，再直接强杀。用户如果刚好跑的是同一路径，会被测试链打断。
2. 把这个问题分成两层重新讲清。测试清理误杀用户进程是一层。Windows 下运行中的 exe 会锁住构建产物，导致后续 rebuild 写不回去，是另一层。两件事不能混着说。
3. 先把第一层结论压出来。测试链可以只运行复制到系统临时目录的 service 副本。清理时只认测试自己记录的 pid 和那份副本路径。这样可以避开用户手动启动的 service，不会顺手把用户进程杀掉。
4. 再把第二层结论压出来。如果还要求“用户一直开着 service，同时仓库里还能继续 rebuild”，构建输出路径和用户运行路径必须分开。用户长期跑不会被覆盖的副本更稳。这件事只靠改清理规则不够。
5. 随后继续讨论更根本的方向。判断能不能把序列化完整接入，让重新构建再重启以后用户状态基本不丢。先对了当前仓库的 `storage`、`entry`、`runtime`。又对了 `IntentDoc` 里的 `storage` 和 `state`。
6. 确认 `IntentDoc` 已经有完整度较高的脱水、回填、引用身份复用和历史恢复能力。说明“进程重启以后把用户状态补回去”这件事在模型上是成立的，不是空想。
7. 也确认当前仓库已经有一半基础。`src/storage.mbt` 已经提供 `Persist`、`bind_with_kv` 和 `bind_refs_with_kv`。对象图引用和身份复用也已经考虑进去。这部分和 `IntentDoc` 的方向是一致的。
8. 同时把缺口也压清楚。当前 runtime 启动还是 fresh boot 默认 root。entry 创建实例时也还是每次重新 `new_data()` 和 `new_session()`。实例树、实例 data、窗口布局和一批工作态还没有沿主路径接到持久化恢复。
9. 最后把这次讨论的结论写清。相比只靠“复制 exe 避免误杀”，完整接入序列化是更根本的方向。只要把实例树、各实例 data 和需要保留的 session 工作态接进 `src` 的 runtime 主路径，重新构建再重启以后，用户核心状态可以做到基本不丢。宿主连接态、pid、端口、websocket 和后台任务这类运行时状态不该直接序列化，重启后重新建立即可。
## 04-05 晚上
1. 重写了 `scripts/test-browser.js`。把 browser 测试入口收成统一的 `mount / query / read / act / wait / step` 主路径。所有等待都改成走同一条带步骤名的超时包装。节点定位改成先走 `bridge.query(path)`。
2. 同步改了 `src/bridge.js`。补了按 path 分段解析节点的能力。补了递归删除节点映射，避免旧树残留继续命中查询。
3. 把现有 browser 用例按 entry 和 bridge runtime 重新整理了。`demo-editor.test.js`、`host.test.js`、`bridge.test.js` 都改成走统一动作和统一等待。
4. browser 测试一开始还是慢。先试过走 `meta.ps1` 启停。后来加了 timing 开关，把启动、建页、open、query、act、wait、step、单文件总时间都记出来。输出默认静默，带 `--timing` 才打印。
5. timing 打出来以后，发现 `meta start` 和 `meta stop` 本身太重。里面会跑 build 检查和一整套启动脚本逻辑。随后把 browser 测试启动链改回直接跑已构建的 `service.exe`。整轮只启动一次、停止一次，不再自己维护复杂的 service 生命周期。清理临时目录时补了短重试，避开 Windows 偶发的 `EBUSY`。
6. 改完以后 browser test 回到约 `1.4s`。这条链能跑通了。但这边还不算彻底做好。当前只把旧流程收成了统一接口，还没有把测试层级和 entry 标准模板完整铺开。后面还要继续把 bridge runtime 层、entry interaction 层的测试规范补齐，再把更多 entry 接进同一套标准流程。
7. 继续处理 service 状态文件和锁文件混在一起的问题。新增了独立的 lock 文件路径。状态文件继续只存 `pid/port`。锁语义改到单独的 lock 文件上。
8. 同步改了 `service/fs.mbt`、`service/cli.mbt` 和 `service/service.test.mbt`。启动后保活句柄改成持有 lock 文件。cleanup 里同时清状态文件和锁文件。测试清理也一起接到新路径。
9. service native 测试原来用固定测试 state 目录，容易被前一轮残留污染。把测试目录改成按当前进程加递增序号生成，减少测试之间互相占同一路径。
10. 开始回归 native service 测试时，先发现 `scripts/test-native.ps1` 自己不透传 `-TestFilter`。随后改用底层 `scripts/build-native.ps1 -TestFilter ...` 逐条排查超时测试。
11. 目前明确排出来两条会在 5 秒预算内超时。第一条是 `native: service lifecycle is idempotent`。第二条是 `native: repl websocket accepts multiple live clients`。
12. `native: service lifecycle is idempotent` 这条一条里串了多次 `start / stop / restart / assert_page_ready`。总量本来就偏大。但更麻烦的是它现在超时时只报整条测试超时，没有具体卡在哪一步。下一位 agent 要先把这条测试拆出更细的步骤级超时信息，再决定是启动链卡住，还是测试本身体量超预算。
13. `native: repl websocket accepts multiple live clients` 更像真实实现问题。单连接复用能过。多 live client 会超时。当前 `with_repl_server(...)` 把 websocket 连接直接交给长期循环的 `serve_repl_websocket(...)`。第一条 live 连接可能把处理路径占住，第二个 client 进不来或拿不到 response。下一位 agent 应该优先顺着这条服务端并发接入路径继续查。
1. 继续查 `native: service lifecycle is idempotent` 为什么只会被测试脚本 5 秒预算截断。先不碰 `service` 行为，只收测试侧的可观测性。
2. 先给 native 测试链补了 timing 开关。`build-native.ps1` 新增透传入口。`service` 测试在包级 `init` 里读取环境变量，打开现有 `debug_timing`。这样可以直接看到生命周期各步骤耗时。
3. 第一轮带 timing 回归后，把卡点压到了更具体的位置。`idle stop`、`start command`、`start port`、`start ready` 都正常。说明问题不在启动链。
4. 随后继续往后量。确认 `stop` 这一步本身也能结束。真正挂住的是 `restart` 之后的等待链。`restart` 命令已经打印 `restarted http://localhost:18121`。说明命令返回了，但后面的“等新 service 状态可读”没有结束。
5. 中间为了解决“测试自己不报错，只被外层脚本截断”，试着把生命周期测试里的命令执行改成测试内可控的 async 超时路径。先后试了结果包装、后台任务、手动取消和 `@async.any(...)`。
6. 这些尝试把现象继续压清了，但还没有把测试侧超时彻底接通。测试已经能稳定打印 `restart` 之前的步骤 timing。外层 5 秒截断也已经不再是完全黑盒。只是测试内还没先一步把超时抛出来。
7. 最后把更合适的方向也确认下来了。MoonBit async 已经有现成的 `@async.with_timeout(...)`。这条原语比前面临时拼的 `TaskGroup` 和 `any` 更适合当前目标。后面应该把生命周期测试里的命令等待和 `restart` 后等待统一收到这条超时原语上，让测试自己先报出具体步骤超时。
8. 当前先记住边界。下一步只继续收测试侧超时行为。不先改 `service` 真实逻辑。等测试能稳定报出 `stop`、`restart port`、`restart ready` 这类具体步骤，再决定要不要修实现。
1. 先按“不要修测试本身，只让超时自己报具体步骤”这条边界收范围。把前面已经修好的共享 `state_dir` 路径撤回。故意保留生命周期测试里 `restart` 后等待走错 `state_dir` 的旧错误模型，专门拿它复现测试侧超时。
2. 先把 `service/service.test.mbt` 里的等待改成 `@async.with_timeout(...)`。目标是让 `run_meta`、等端口、等页面、`stop` 这些步骤自己先报具体步骤名，不再只被外层 `scripts/build-native.ps1` 的 5 秒预算截断。
3. 只改轮询 helper 还不够。测试虽然已经有步骤级 timeout，但 native test 进程本身还会被残留子进程或输出污染拖住。结果还是会表现成外层 5 秒截断。
4. 继续往下查以后，把问题拆成两层。第一层是生命周期测试之前之所以会跑成 `restarted http://localhost:18121`，根因是测试每次命令都偷偷换新的 `state_dir`。第二层是即使故意保留这条错误模型，也得保证测试自己能先把错误抛出来，不能再把整条测试链拖成黑盒超时。
5. 为了验证第一层判断，单独手跑了一次 `service.exe --state-dir <同一目录> stop/start/restart/stop`。确认实现本身没问题。同一目录下 `restart` 会正常回到 `18120`。说明前面那次异常只来自测试目录切换，不是 `service/cli.mbt` 的真实逻辑。
6. 后面按要求，不再继续修正确模型，改成故意把正确写法注释掉，只保留错误模型。然后集中处理“测试怎样直接报错”。这一步先试过 `@process.spawn(..., no_wait=true)` 加 `proc.wait()`。目标是超时以后直接 `cancel` 子进程，再把步骤名带出来。
7. 这条路中间又踩了几次坑。先是 test stdout 被裸 `stopped` 污染，MoonBit native test 结果解析直接坏掉。随后把 `stop` 也收进子进程结果捕获。接着又试过 pipe 读 stdout/stderr。结果又碰到 writer 生命周期和读空的问题，`start_output` 会变空，断言直接提前炸掉。
8. 最后把子进程输出主路径改成 `@process.collect_output_merged(...)` 包 `@async.with_timeout(...)`。这一步本来是想把输出留在内存里，超时直接 `fail("meta command timed out: ...")`。不再写临时文件，也不再让裸输出污染 MoonBit test result parser。
9. 这次改收集输入输出的方式以后，又引入了新的偏差。`start` 这一步开始直接超时。错误不再落在原来那条故意保留的 `restart` 路径上。也就是说，当前 `start` 炸掉，不是原来的生命周期模型自己演化出来的现象。是这次把进程输出收集改成 `collect_output_merged(...)` 以后带出来的新问题。
10. 同时把几条会改全局 `state_dir_ref` 的 async service 测试串成单通道，避免生命周期这条故意失败的用例把别的 native 测试一起带坏。这样 `./scripts/test-all.ps1` 能重新正常跑完整条测试链，不再出现“测试结果解析失败”或别的锁测试一起翻车。
11. 当前状态先记清。`test-all` 能正常跑。native 全量只剩这一条故意保留的生命周期测试失败。失败信息已经变成测试自己直接抛的超时错误，不再是外层 5 秒脚本截断。
12. 当前失败点已经被错误的输出收集方式提前改到了 `start 18120 --silent`。不是原来想保留的 `restart` 超时。后面的agent应该把收集输入输出的方式修复，要么深入研究async包的用法，要么回退到之前的临时文件的做法
13. 另外测试用的临时文件夹都应该要删除，无论测试成功还是失败。
## 04-06 上午
1. 先重新查了 `mooncake` 里的 `moonbitlang/async/process`。把 `@process.spawn(...)`、`@process.run(...)`、`collect_output_merged(...)`、取消处理和 pipe 读取语义串起来看了一遍。确认异步启动外部命令的主路径是 task group 里的 `spawn/run`。涉及 shell 时，需要显式传 `powershell` 这类 shell 程序。
2. 接着把测试里收集命令输出这件事重新压清。`collect_output_merged(...)` 会一路读到 pipe EOF。主进程退出，不代表收集会立刻结束。只要还有句柄没关，读取就会继续挂着。这条语义不适合当前 `service` 生命周期测试。
3. 随后尝试把 `service/service.test.mbt` 里的 `run_meta_with_timeout(...)` 从“临时文件 + `try_wait()`”改成“pipe + reader 任务”的实现。第一版改法把 reader 挂成了会被 task group 正常等待的任务。主进程虽然已经退出，reader 还卡在 `read_some()`，整组测试会被一起拖住。
4. 这版改完以后，`native: service lifecycle is idempotent` 直接被外层 5 秒预算截断。先按同一条命令回退工作区再重跑。测试恢复通过。这样把回归范围压到了刚才那版 pipe 收集改动本身，没有继续误判到别处。
5. 最后把这条收集路径重新收成能工作的最小实现。继续用 `read_from_process()` 接一根合并的 stdout/stderr pipe。reader 任务只负责持续累加输出。主逻辑继续按 `proc.try_wait()` 盯主进程退出。主进程退出或超时时，直接取消 reader 任务，再只给一个很短的收尾窗口，不再等 pipe EOF。
6. 改完以后回归了 `moon check`。也回归了 `./scripts/build-native.ps1 -Package service -Test -TestPackage service -TestFilter "native: service lifecycle is idempotent"`。两项都通过。说明现在已经能不靠临时文件收集输出，同时保住这条生命周期测试。
1. 回头查了 `test-all` 会留下很多 `metaeditor-service-test-*`。先按完整测试链复现了一遍。确认问题能稳定复现。
2. 完整跑 `./scripts/test-all.ps1` 以后，会新增一串 `metaeditor-service-test-<pid>-<seq>`。数量和测试调用次数一致。不是偶发残留。
3. 顺着 `service/service.test.mbt` 查目录来源。确认主因不在构建脚本。主因在测试里的 `prepare_test_state_dir()`。
4. `prepare_test_state_dir()` 每次都会切到一个新的带序号目录。`clear_test_service_state()` 这类清理函数也会先调它。结果变成“为了清理又新建一个目录”。
5. 又把调用面按测试条目对了一遍。`service state` 相关几条测试会建目录。`service lifecycle is idempotent` 也会反复建目录。合起来正好是一轮 `test-all` 里那串新增目录。
6. 这一步把问题重新压清了。问题不只是没清理干净。问题先出在函数职责错了。同一轮状态检查和生命周期流程不该拆这么多目录。
7. 随后回退了“让构建脚本帮测试擦屁股”的方向。只收测试自身语义。先改 `prepare_test_state_dir()`。
8. `prepare_test_state_dir()` 被收成固定测试目录。不再每次生成新的 `-seq` 子目录。这样同一轮测试不会再平白长出一串目录。
9. 先回归了 `moon check`。再回归了 `./scripts/test-all.ps1`。确认测试仍然通过。
10. 这一步以后，新的一串 `metaeditor-service-test-*` 已经不再增长。目录数量先被收住了。说明“重复建目录”这条源头已经切掉。
11. 用户随后指出还缺最后一层。测试结束以后应该把临时目录删掉。成功失败都要删。不能留给下次运行。
12. 接着把目录清理收进 `with_service_state_lock(...)`。目标是让带锁测试退出时统一清理固定测试目录。清理责任留在测试自己身上。
13. 第一版收尾实现有时序问题。前一条测试先放锁。后一条测试已经进来。前一条测试晚到的异步清理会把当前目录删掉。
14. 第二版又撞到另一个问题。前一条测试把固定目录删掉以后，后一条测试进来直接开锁文件。路径还没重新建回来。测试会因为目录不存在失败。
15. 最后把顺序压成一条主路径。进入带锁测试区以后先重新建固定测试目录。退出时统一走同一个 `task_group.add_defer(...)`。
16. 这条收尾顺序固定成两步。先删测试目录。再释放测试锁。这样目录清理和锁释放不会再分叉。
17. 最后重新串行回归了 `./scripts/test-all.ps1`。整条测试链通过。说明这次目录职责和收尾顺序已经对上。
18. 跑完以后又单独检查了系统临时目录。确认这一轮测试不会再新增新的 `metaeditor-service-test-*` 残留。之前看到的那个目录是更早失败或中断时留下的旧目录。
1. 先审了自 `7a5e03c` 以来的 bridge 和 browser test 改动。重点看了 `src/bridge.js`、`scripts/test-browser.js`、`service/bridge.mbt` 和几份 browser 用例。确认正式执行链已经有 `service -> src.runtime_resolve_query(...) -> id` 这条主路径。也确认 browser 侧又重新长出一条本地 path 查询和本地动作分发。边界重新混在一起了。
2. 审查时先把两个还没解决的问题单独记清。第一，`src/bridge.js` 里一度把 path 查询直接做成了浏览器本地 DOM 扫描。这会和 `src` 里的查询语义并行。第二，`scripts/test-browser.js` 把 click、dblclick、key、focus、input 分成了几条不同执行路径。表面都叫统一 act。底下其实有 Playwright 鼠标、Playwright 键盘和 bridge.exec 混用。
3. 先按“删掉 browser 自己解释 path”这条边界试了一版最小收缩。把 `bridge.js` 里的本地 path 查询入口拆掉。又在 `test-browser` 里临时补了一层按 `ui-id` 扫快照的辅助查询。目标只是先把测试跑起来，再继续收协议。
4. 这版很快被打断。问题不在“测试能不能先跑”。问题在 browser test 根本不能直接碰 `src`。`bridge.js` 才是唯一桥。于是把方向重新压清。真正要做的是“bridge 到 src 的异步查询通道”。path 查询权继续只留在 `src`。
5. 随后按这条判断重做了 `src/bridge.js`。新增了 browser 侧异步 request/pending 主路径。`query(path)` 不再本地扫 DOM。现在会通过 websocket 发 `bridge:request` 给 service。等 service 回 `id`。browser 再用这个 `id` 映射本地 DOM node。
6. 同步改了 `service/bridge.mbt`。新增 browser 发起的 `bridge:request` 处理。当前只接 `query`。service 内部继续走 `@src.runtime_resolve_query(...)` 解 path，再把 `id` 回给 browser。执行接口没有接 path。还是只认 `id`。
7. 再把 `scripts/test-browser.js` 收回单一路径。删掉前面临时补的本地 `ui-id` 查询。browser test 重新只调 `bridge.query(path)`。等待逻辑也改成异步轮询。不会再假设页面里有同步 path 查询。
8. `scripts/browser-tests/bridge.test.js` 也收了一次边界。fake bridge 用例不再假装有 `src`。它只测本地 `id` 查询和 `id` 执行。真正的 path 查询桥交给带 service 的 browser 用例去锁。
9. 中间先跑了 `moon check`。只确认编译过了。随后又被提醒 browser test 不能只靠这个判断。先执行了 `./scripts/build-native.ps1 -Package service`。把 native `service.exe` 重建到最新。再开始回归 browser test。
10. 重建以后，browser test 基本都对上了。最后只剩 `demo-editor` 一条失败。失败点被压到新增 todo 以后查询 `demo-item:3/text`。这说明异步桥主路径已经接上。剩下的是某条具体 path 在新增节点后的稳定性问题。
11. 中间一度把这条测试临时改成读 `demo-item:3` 根节点文本。想先缩小问题范围。随后又被指出这个改法不对。因为 `src/demo_editor.mbt` 本身就明确定义了 `demo-item:{id}/text` 这个 `ui-id`。不能靠偷换测试路径把问题盖过去。
12. 当前先把这次状态记清。还没解决的审查问题有两类。第一类是 `scripts/test-browser.js` 里动作执行仍然不够单一。pointer 和 key 还混着 Playwright 输入和 bridge.exec。第二类是新增 todo 以后，合法 path `demo-item:3/text` 通过异步桥查询还不稳定。这个是现在真正剩下的实现问题。
1. 继续查 devlog 末尾那条 `demo-editor` 查询失败。先重读了 `src/bridge.js`、`service/bridge.mbt`、`scripts/test-browser.js`、`scripts/browser-tests/demo-editor.test.js` 和 `src/demo_editor.mbt`。
2. 直接复跑了 browser 用例。确认失败稳定复现。不是等待超时。是新增 todo 以后查询 `demo-item:3/text` 会直接收到 `RuntimeErr.Fail`。
3. 接着把问题压回 `src`。读了 `src/runtime.mbt` 和 `src/dom.mbt`。确认 browser 桥已经走 `service -> src.runtime_resolve_query(...) -> id` 这条主路径。真正没接上的是 `src` 里的路径解析。
4. 中间先按现状补过一版兼容。让当前节点解析下一段时，同时接受局部名和带父前缀的完整 `ui-id`。`moon test` 和 browser 用例都能过。
5. 后面把方向重新压直。`/` 不该出现在 `ui-id` 里。那版兼容只是把错误写法继续托住。方向不对。
6. 又把 `demo_editor` 这边的问题重新讲清。它不只是一串错误 `ui-id`。它还没有利用 `h_map` 项本身已经带 list scope 这件事。
7. 结果 item 下面的 `text`、`toggle`、`remove` 没老老实实作为局部名存在。反而又手写成带父前缀的整段身份。重复造了一层假的路径语义。
8. 随后把前一版新加的兼容和测试全部撤掉。回头改了 `src/demo_editor.mbt`。把 `demo-item:{id}/text`、`toggle`、`remove` 这些错误 `ui-id` 改成局部名。
9. 把 item 根节点改成查询宿主。这样 `demo-item:3/text` 继续是合法查询，但 `/` 只留在查询语法里，不再进入节点身份。
10. 同步把 `src/dom_helper.mbt` 和 `src/dom.test.mbt` 里残留的 slash 语义一起清掉。derived class 不再按 `/` 取最后一段。改成直接基于整个 `ui-id` 归一化。
11. 然后回归了 `moon test`、`./scripts/build-native.ps1 -Package service` 和 `node scripts/test-browser.js --start --stop scripts/browser-tests/demo-editor.test.js`。三项都通过。说明 slash 已经从 `ui-id` 身份里清出去，browser 查询也重新对上。
12. 用户随后要求在注册 `ui-id` 时直接拦截 `/`。就在 `src/dom.mbt` 的 `find_static_ui_id(...)` 入口加了 `validate_ui_id(...)`。
13. 第一版用了 `abort(...)`。很快确认这条路不合适。测试框架接不住 `abort`。行为锁不进测试。
14. 于是改成了 `panic()`。这样不用把 DOM 构建整条链改成 `raise` 风格。也能让测试卡住这个约束。
15. 接着补了 `panic ui-id rejects slash` 这条测试。第一次回归时又带出一个真实测试环境问题。panic 用例会把 `current_dom_state` 留脏，后面的样式测试会被污染。
16. 没继续把错误路径扩成 `raise`。只按最小补丁修了测试环境状态。让 `reset_ui()` 明确把 `current_dom_state` 归零。
17. 最后重新回归 `moon test`。`121/121` 全过。现在的口径是 `ui-id` 含 `/` 会直接 panic，测试也已经把这个行为锁住。
1. 继续收 browser test 的动作通路。先把 `scripts/test-browser.js` 里的动作实现统一看了一遍。确认 browser test 不该再混用 `bridge.exec(...)` 和 Playwright。
2. 先把 browser test 的动作执行收成 Playwright。`focus`、`input`、`key`、`pointer`、`drag` 都改成走 Playwright。browser test 的正式动作路径不再走 `bridge.exec(...)`。
3. 中间顺手查到 `src/bridge.js` 把 `VNode id` 写进了真实 DOM 的 `data-mbt-id`。这层内部 id 泄漏不对。随后把 `data-mbt-id` 的写入和回读都删掉，只保留 bridge 自己的 `Map/WeakMap` 映射。
4. 接着发现 browser test 里 `focus/input/key` 还在按目标节点的 rect 中心点做 `elementFromPoint(...)`。这会把动作目标重新交给浏览器命中判断。边界不够稳。
5. 没把 path 查询权重新放回 browser。本地没有再造 BFS 或 selector 查询。改成在 `bridge.js` 里加一个很窄的测试 helper。它还是先让 `path` 走 `service -> src.runtime_resolve_query(...)`，再把结果对应到真实 DOM node。
6. 随后把 `scripts/test-browser.js` 里的 `focus/input/key` 接到这条 helper 上。这样测试层直接拿查询结果对应的真实节点。不再依赖 `VNode id`。也不再靠中心点猜元素。
7. 同时把 `exec` 的边界重新写清。`service/bridge.mbt` 和 `src/bridge.js` 都补了注释。明确 `exec` 只给 CLI / REPL 这类远程控制入口用。query 必须先在 `src` 里解成当前 `VNode id`。browser test 的正式动作路径不走这里。
8. 后面开始量 browser test 的耗时。先给 `scripts/test-browser.js` 的 `command`、`wait`、`step` 这些阶段补了更细的 timing。想先把慢点压到具体阶段。
9. 第一轮量完以后，最明显的慢点出在 `mount(...)` 里的 `sync`。browser test 明明已经有 browser bridge websocket，还在走 HTTP `/_meta/command`。这条绕路很不顺。
10. 接着把 browser test 的 `roots/sync` 命令面收进 browser bridge websocket。service 侧复用了现有命令主路径。harness 不再自己打 HTTP 控制口。
11. 这一步第一次改完以后，browser test 立刻带出一个真实问题。`command sync` 会在同一条 browser websocket 上超时。原因是 browser 发起 `command sync` 时，service 又在处理这条 request 的过程中回头走 `sync_browser(runtime)`，在同一条连接上形成了 request 里再等 response 的递归等待。
12. 中间讨论过把所有 `bridge:request` 都改成后台并发处理。最后没这么做。这样会把同连接 request、event、response 的交错语义一起放宽，影响面太大。
13. 最后按更窄的方式修了这条自锁。只把 browser 发起的 `command sync` 收成空 barrier。service 直接回 `"synced\n"`。真正的收敛继续交给后面的 `query/exists` 等待。改完以后 `./scripts/test-all.ps1` 重新通过。
14. 随后又回头看 timing。前一版 timing 是父子阶段混着记，和总时间对不上，读起来会误导。于是把 timing 口径重新收了一次。
15. 在 `scripts/test-browser.js` 里补了一层可加总的 accounting。现在只记 `setup`、每个测试文件、`teardown` 这一层。最后总账能和 browser test 的总时间严格对上。
16. 用这份新 timing 看下来，browser test 的大头已经很清楚。主要时间不在测试文件本体。主要时间在 `setup` 和 `teardown`。
17. 继续顺着这个结果往下收。把 `start service` 和 `launch browser` 改成并行。把 `stop service` 和浏览器关闭链也改成并行。`state dir` 清理顺序保持在最后。
18. 改完以后重新回归了 `npm run test-browser`。也回归了 `./scripts/test-all.ps1`。两条都通过。browser 总时间比前面又降了一截。
19. 这次还没做好的地方先单独记清。`exec` 虽然已经明确成 CLI / REPL 专用，但还缺完整覆盖。现在只锁了边界，没有把 `focus/input/drag` 这类 CLI 动作补成一组更完整的回归。
20. 另一条没做好的地方在 browser test 组织方式。`host.test.js` 现在还是每条用例各自 mount 干净状态。连续交互链的覆盖偏弱。后面如果继续收这块，应该把测试重心从“单步干净态”往“连续操作链”压。
1. 回看了 devlog 末尾还挂着的事项。重新按现状核对了一遍状态。把“`test-all` 已经全绿”的结论补明确。
2. 原先记着的 `native: repl websocket accepts multiple live clients`，先按 `./scripts/test-all.ps1` 已经不报错处理。当前不再把它记成未完成问题。
3. 原先记着的 browser test 标准模板和层级铺开，先按已有改动已经满足当前目标处理。当前不再单独挂着。
4. 原先记着的 `exec` 给 CLI / REPL 专用但覆盖还不完整，这次没有继续做。先明确降级成暂缓项，不再和当前 browser `host` 测试组织方式混在一起。
5. 原先记着的持久化恢复大方案，这次也没有继续做。先明确降级成暂缓项，不再算当前要收的尾项。
6. 把剩下真正要收的范围压到 browser 的 `host` 测试组织方式。目标不是补新的连续交互链。目标是让现有 `host` 用例共享同一次挂载状态。
7. 先读了 `host.test.js`、browser harness 和 `host` 入口实现。确认 `spawn` 会累计开窗。测试顺序如果不跟着调整，后面的断言会吃到前面的副作用。
8. 把 `host.test.js` 的挂载时机从 `beforeEach` 改成 `beforeAll`。`entry host` 这组 browser 用例现在只做一次 `mount(['host'], ['entry:demo'])`。同组用例共用这份页面状态。
9. 同时把“打开窗口”那条用例改成承接前一条双击结果。保留对 `window:1`、`topbar-window:1` 和标题文本的等待与读取。去掉了重复的第二次双击。
10. 这次改动把当前要收的目标接上了。`host` browser 测试不再每条都清空重挂。现有三条用例按同一轮状态顺序执行。
## 04-06 下午
1. 继续查 `demo-editor` 的 `ui-id` 用法。重读了 `demo_editor`、`dom`、browser 用例和当前 query 语义。确认问题不在 bridge。也不在 query 主路径本身。问题在列表项被做成了全局 `ui-id`。
2. 先按现有语义收了一版 `demo-editor`。去掉 item 根节点那层全局 `ui-id`。把空态节点从列表宿主里挪开。browser 用例改成按列表路径查询。随后按要求补跑了 `./scripts/test-all.ps1`。整条测试链通过。
3. 接着继续审 `host`。确认 desktop entry 下面的 `entry-icon` 和 `entry-name` 也有同类问题。它们会在多个 entry 里重复出现，但当时没有挂在局部命名作用域里。于是给 entry 根节点补了局部命名作用域。browser 用例补了 `entry:demo/entry-name` 的查询断言。改完再次跑了 `./scripts/test-all.ps1`。结果继续通过。
4. 后面回头审 `metaeditor-dom-runtime` skill。先确认文案里还残留旧语义。`ui-id` 派生 class 还写着 slash 版规则，已经和实现不一致。中间又重新把 `h_map` 的列表作用域语义压了一遍。确认现实现里内部已经有 list scope。真正缺的是这层能力没有通过显式名字暴露成稳定查询入口。
5. 最后把 `src/dom.mbt` 里的 `h_map` 和 `h_map_dyn` 收成显式带列表 `ui-id` 的版本。列表查询入口改成由 `h_map('<list-ui-id>', ...)` 和 `h_map_dyn('<list-ui-id>', ...)` 直接命名。`demo-editor`、`host`、`dom` 测试、`mock_dom` 测试和 browser 用例一起切到新语义。正式路径收成 `<list-ui-id>/0/<inner-ui-id>`。
6. 同时把 `metaeditor-dom-runtime` skill 一起改掉。删了过期的 slash 描述。补清了局部名只有在显式 scope 下才成立。补清了 `ui-list` 和 `h_map(ui_id, ...)` 的分工。也补清了不要把 empty state、footer 这类非 item 节点塞进会占索引的命名列表入口。
7. 最后重新跑了 `./scripts/test-all.ps1`。整条测试链通过。说明这次列表命名入口、局部查询语义和 skill 文案已经重新对齐。
1. 继续查 `demo-editor` 的 `ui-id` 用法。重读了 `demo_editor`、`dom`、browser 用例和当前 query 语义。确认问题不在 bridge。也不在 query 主路径本身。问题在列表项被做成了全局 `ui-id`。
2. 先按现有语义收了一版 `demo-editor`。去掉 item 根节点那层全局 `ui-id`。把空态节点从列表宿主里挪开。browser 用例改成按列表路径查询。
3. 按要求补跑了 `./scripts/test-all.ps1`。整条测试链通过。说明这版 `demo-editor` 修正没有把别的路径带坏。
4. 接着继续审 `host`。确认 desktop entry 下面的 `entry-icon` 和 `entry-name` 也有同类问题。它们会在多个 entry 里重复出现，但当时没有挂在局部命名作用域里。
5. 给 desktop entry 根节点补了局部命名作用域。browser 用例补了 `entry:demo/entry-name` 的查询断言。改完再次跑了 `./scripts/test-all.ps1`。结果继续通过。
6. 后面回头审 `metaeditor-dom-runtime` skill。先确认文案里还残留旧语义。`ui-id` 派生 class 还写着 slash 版规则，已经和当前实现不一致。
7. 中间又重新把 `h_map` 的列表作用域语义压了一遍。确认现实现里内部已经有 list scope。真正缺的是这层能力没有通过显式名字暴露成稳定查询入口。
8. 先把 `src/dom.mbt` 里的 `h_map` 和 `h_map_dyn` 收成显式带列表 `ui-id` 的版本。列表查询入口改成由 `h_map('<list-ui-id>', ...)` 和 `h_map_dyn('<list-ui-id>', ...)` 直接命名。
9. 同步把 `demo-editor`、`host`、`dom` 测试、`mock_dom` 测试和 browser 用例切到这条新语义。随后重新跑了 `./scripts/test-all.ps1`。整条测试链通过。
10. 用户随后指出默认不该强制命名列表。只有需要稳定查询时才该暴露入口。于是继续把 `h_map/h_map_dyn` 收成可选 `ui_id` 版本。
11. 无名 `h_map(items, f)` 和 `h_map_dyn(source, f)` 现在只做稳定复用，不注册列表查询入口。带 `ui_id=Some(...)` 的命名版才支持 `<list-ui-id>/0/<inner-ui-id>`。
12. 为了直接锁这条行为，又补了两条 `mock_dom` 测试。一条锁无名 `h_map` 不能走 `root/0/toggle`。另一条锁命名 `h_map(..., ui_id=Some('todos'))` 可以走 `todos/0/toggle` 和 `todos/1/toggle`。
13. 改完以后 `moon test` 回到 `123/123`。随后重新跑了 `./scripts/test-all.ps1`。整条测试链继续通过。
14. 同时把 `metaeditor-dom-runtime` skill 一起改掉。删了过期的 slash 描述。补清了无名版和命名版 `h_map` 的分工。补清了局部名只有在显式 scope 下才成立。
15. 也补清了 `ui-list` 和命名 `h_map` 的边界。还补了不要把 empty state、footer 这类非 item 节点塞进会占索引的命名列表入口。说明这次列表命名入口、局部查询语义和 skill 文案已经重新对齐。
1. 先审了 `src` 包那份底层精简方案。把 `dom`、`entry`、`reactive`、`storage` 四块现状重新对了一遍。确认真正值得动的是事件双轨、宿主注册长参数、容器遍历样板三类重复实现。`reactive` 里的 post-flush 生命周期还在承接真实移除语义，先没有按原提案硬收。
2. 收了 `src/dom.mbt` 的事件绑定。`Prop` 只留 `E((EventData) -> Unit raise)` 一条签名。删掉了 `EK` 和内部 `EventHandler` 的双分型。事件派发只剩一条路径。原来不需要事件数据的回调点都改成显式忽略入参。
3. 同步把事件调用面一起对齐。`entry` 里的 action bind 改成走统一事件签名。相关 `dom`、`mock_dom` 测试里的点击、键盘、指针回调都改成新写法。这样无参和带参事件不再在 DOM 层并排保留两套接口。
4. 收了 `src/entry.mbt` 的宿主注册接口。新增 `HostHooks[D, S, X]` 承接 `extra`、`attach_child`、`children`、`detach_child`。普通 entry 继续走 `register_entry(...)`。宿主 entry 改成走 `register_entry_with_hooks(...)`。`host` 默认注册逻辑也切到这条新入口。
5. 中间试过把 `register_entry` 做成一个可省略 `hooks` 的泛型入口。MoonBit 这层没法在泛型 `X` 上安全给出默认 `extra`。这版很快回退了。最后保留成“普通入口一条、宿主 hooks 入口一条”的更稳写法。
6. 收了 `src/storage.mbt` 里纯容器遍历的重复样板。原来的容器复制 helper 改成 `map_container(...)`。又补了 `walk_container(...)`。`encode_node`、`collect_kids`、`collect_ref_ids` 都改走统一遍历入口。
7. `storage` 这块只收纯遍历。没有继续把 `rehydrate_value` 和 `hydrate_node` 硬并。对象分支还保留按键复用旧值和删缺失字段的语义。数组分支还保留整段清空后重建的语义。这样不会把当前 identity 和回填规则一起打散。
8. 另一位 agent 随后继续把 `dom` 里的重复动作收短。多处 `Append / InsertBefore` 分支统一回 `mount_node_before(...)`。多处 `emit_current(Remove(...))` 加 `recursive_cleanup(...)` 统一回 `remove(...)`。当前 DOM 挂载和删除各自只留一条主路径。
9. 同一轮里又把一批空 `None` 分支收成更短的 `if ... is Some(...)` 写法，范围落在 `dom`、`dom_helper`、`entry`、`mock_dom`、`reactive`、`storage`。后面重新审了一遍这些改动。确认都只是空分支收短，没有带出额外控制流变化。
10. 最后又补了三处小收束。`src/dom.mbt` 新增 `dom_effect(...)`，统一包住带 `use_dom_state_inner(...)` 的 effect。`src/entry.mbt` 新增 `require_node(...)`，把实例缺失报错收成一处。`src/host.mbt` 新增 `expect_nonempty_string_arg(...)`，把三个 action 里的空字符串检查收成一处。
1. 继续收 `src` 包里的基础 helper。先把跨 `dom_helper`、`storage`、`mock_dom` 都会用到的前缀判断收进 `base`。`has_prefix(...)` 不再在各处各写一份。
2. 顺手把两处真实边界一起收回去。`storage` 里的 `Kv::keys_with_prefix(...)` 继续只返回真正的子键，不把 `prefix/` 自己带进去。`mock_dom` 里的父子数组改回先找下标再删，避免一边遍历一边改同一个数组。
3. 中间一度把 `reactive` 里的通知逻辑提成了 `Cel::notify`。后来重新对了“基础 helper”和“局部小别名”的边界，确认这类名字不值得当新概念继续留。
4. 随后又审了一轮把 helper 往 `src/base` 集中的改动。把 `split_shell_args(...)` 从 `entry` 挪到 `base` 保留了。把 `dom_helper` 里的 `no_raise(...)` 也并进了 `base`。
5. 同一轮里拦下了一个不该进 `base` 的名字。`fail(...)` 一度被塞进 `base`，会把整个 `src` 包测试失败通路一起污染。随后已经删掉，没有继续保留。
6. 继续顺着 `split_shell_args(...)` 的归属往下查。把当前 `CLI -> service -> src.runtime` 命令链重新对了一遍。确认问题不只是 helper 放错层。根因是 `service -> src` 之间现在还在传 `cmd + raw arg string`。`src/runtime.mbt` 自己还在承担一层命令字符串解释。
7. 先把这条记成后面要继续收的事项。要把 `service -> src` 的命令链收成结构化命令入口。让 CLI、HTTP 控制口、REPL 共用同一条解析后主路径。到时再把 `split_shell_args(...)` 退回真正该待的层。
8. 又继续对了一遍协议命名。确认当前 `exec` 已经同时指两件事。一条是 instance action 调用。另一条是 bridge 给 CLI / 自动化提供的 DOM 本地执行动作。这会把协议层级和调用目标混在一起。
9. 把后面的命名方向先定下来。instance action 留给 `exec`。结构化定位继续叫 `query`。浏览器本地动作执行 `exec` 改名 `trigger`。后面要按 `exec/query/trigger` 这组名字把命令入口和协议边界重新对齐。
## 04-06 晚上
1. 继续收协议命名。先重读了 `runtime`、`service bridge`、browser bridge 和相关测试。确认当前真正的歧义只在一处。实例 action 已经稳定叫 `exec`。CLI / REPL 远程触发浏览器本地动作这条路径也还叫 `exec`。
2. 中间单独重看了 `src` 里的 `trigger_node`。确认它是按运行时节点 id 直接触发事件回调的底层入口。和实例 action 不是同一层。这样范围可以继续压窄。
3. 随后把边界收成一条。只改 CLI / REPL 远程触发浏览器事件这条路径。实例 action 继续叫 `exec`。不继续扩到 `runtime` 命令面，也不改 `src` 里的事件触发函数名。
4. 先改了 `service/bridge.mbt`。把 `BrowserQueryRequest::Exec` 改成 `Trigger`。把发给 browser 的协议 `action` 从 `exec` 改成 `trigger`。这样 `query` 和浏览器动作触发这两层名字先对齐。
5. 同步改了 `src/bridge.js`。把 `bridge.exec(...)` 改成 `bridge.trigger(...)`。请求分发分支也跟着改到 `trigger`。报错文案一起对齐，避免残留旧口径。
6. 再把 `service/repl.test.mbt` 一起改掉。相关测试名、请求构造和断言都切到 `trigger`。这样测试描述和协议名保持一致。
7. 最后回归了 `./scripts/test-native.ps1`。结果是 `31/31`。说明这次只收了 CLI / REPL 到 browser 的动作命名边界。实例 action 的 `exec` 没受影响。
1. 先看了当前分支相对 `dev/1` 最开始那笔提交 `refactor(service): improve json handling and add utility functions`。这笔主要动了 5 个文件。
2. `service/base.mbt` 里新增了 `time(...)` 和 `time_async(...)` 两个 timing helper。把原来零散的 `json_field/json_string/json_int/json_bool` 收掉，换成 `Command`、`ResponseMsg` 这类 `derive(FromJson)` 结构。还新增了统一轮询 helper `poll_until(...)`，把 `wait_timeout(...)` 也改成复用这条等待原语。
3. `service/bridge.mbt` 里把 browser / repl / websocket 这条消息读取路径整体从手拆 JSON 改成 typed decode。新增了 `BridgeMsg`、`BridgeQueryMsg`、`QueryData`。`handle_event`、`handle_response`、browser query、browser command、browser request、pong、hello、repl request 这些入口都切到了新结构。
4. `service/cli.mbt` 里把 `wait_port(...)`、`wait_browser_connected_at(...)`、`wait_for_lock_released(...)` 都改成走 `poll_until(...)`。同时把 `start`、`run_service` 这些路径上的 timing 写法改成复用新的 `time/time_async`。CLI 控制口 payload 解析也从手拆字段改成了 `Command` / `ResponseMsg`。
5. `service/fs.mbt` 里把 state 文件解析改成 `ServiceStateFile derive(FromJson)`。路径拼接也顺手收成了更短的写法。`service/http.mbt` 里控制口返回解析同样切到了 `ResponseMsg`。
6. `service/repl.test.mbt` 因为生产代码里的 JSON helper 被删掉了，所以测试文件本地补回了一份最小 helper，维持现有断言。
7. 之后对照 `dev/1` 和当前分支，实测 native service 测试速度差异。确认当前分支会撞到 `scripts/build-native.ps1` 的 5 秒预算，`dev/1` 不会。
8. 把慢点拆开量。确认 service 真正的 boot 只要 `1-2ms`，问题不在服务启动本体，在 CLI `start/restart` 命令自己的等待链。
9. 先怀疑 `poll_until(async fn() ...)` 这类 async 等待封装，做了最小回退实验。把 `wait_port`、`wait_browser_connected_at`、`wait_for_lock_released` 临时改回旧写法，结果没有改善，排除了这条猜测。
10. 随后把 timing 往下打细，先加到 `call_at(...)`、服务端 `handle(...)`，再临时补一层 CLI 路径级 trace，专门看 `start` 命令内部到底卡在哪一步。
11. 细 log 跑出来以后，确认 `start wait_port` 只有几十毫秒。真正慢的是 `wait_browser_connected_at(...)`，而且它在 `--silent` 路径下仍然执行了接近 1 秒。
12. 顺着这个结果回头看 `service/cli.mbt`，定位到这次收短写法引入的问题：原来两层的 `if !silent { if !wait_browser_connected_at(...) { ... } }` 被收成了 `if !silent && !wait_browser_connected_at(...) { ... }`。
13. 把这两处改回两层 `if` 以后重新回归。`native: service lifecycle is idempotent` 从大约 `3.8s` 回到 `0.9s`，`./scripts/test-native.ps1` 也回到 `31/31` 且总测试时间明显下降。
14. 为了避免以后再踩同一个坑，又在这两处 `!silent` 分支旁边补了中文注释，明确说明这里不能收成 `&&` 短写。
15. 最后把排查过程中真正有用、噪音又不太大的 timing 保留下来。`service/http.mbt` 里保留了 `call_at` 的 `post/read/decode/result` timing，`service/cli.mbt` 里保留了服务端 `handle` 的 `run_command/respond_ok` timing，它们都继续走现有 `debug_timing` 开关。
## 04-07 上午
1. 继续收 `bridge` 这块查询入口。先回看了前一版精简。确认 `bridge.query(...)` 和 `queryNodeForTest(...)` 语义混着放，名字也不对。
2. 中间把两层 `id` 重新讲清。`path` 还是 query 语义路径，单个 `ui-id` 也算 `path`。`id` 指运行时 `VNode id`。不能混着叫。
3. 最后把 bridge 查询入口拆成两条明确职责。`bridge.query(...)` 继续只返回节点快照。新增正式入口 `bridge.queryNode(...)` 返回真实 DOM node。原来的 `queryNodeForTest(...)` 直接删掉。
4. 同步把 browser harness 那处 element 查询切到 `bridge.queryNode(...)`。测试层不再依赖 test 专用名字。
5. 这次没有继续碰 `trigger(...)`。也没有再长新的 `resolve`、`require`、`dispatch` 包装层。
1. 先重读了 `bridge.js`、browser harness、`service/bridge.mbt` 和相关测试。重新把 bridge 现有公开面、内部 helper、测试专用入口混在一起的问题压清。
2. 确认了 `query` 和 `queryNode` 都要保留。也确认两者正式语义都只该和 path 有关，不再把 runtime `id` 当公开概念继续往外扩。
3. 确认了 `queryLocal` 职责过宽。里面把整页快照、焦点查询、按 id 读节点、按 id 读文本混在一起，不适合继续作为正式 API 保留。
4. 确认了 `request` 只有 `bridge.js` 自己内部在用。测试和外部调用面都没有直接依赖，适合降回私有 helper。
5. 把 bridge 正式 API 边界收成 `init / reset / status / setStatusListener / query / queryNode / command`。把测试专用能力单独收进 `bridge.test.*`。
6. 按这套边界实际改了 `bridge.js`。把 websocket 状态、请求发送、path 解析、DOM 命令执行、trigger 执行、socket 消息分发都拆成文件内私有 helper。删掉了顶层的 `queryLocal`、`request`、`apply`、`DOM_CMD`、`MSG`、`connect_to_core`、`resetForTest` 这类旧公开入口。
7. 同步改了页面和 browser harness。状态显示改成走 `status()` 和 `setStatusListener(...)`。browser test 的 fake bridge、DOM 命令注入和内部节点快照读取都切到 `bridge.test.*`。`focus_path` 等待改成直接比较 `document.activeElement` 和 `queryNode(path)`。
8. 顺手把 `host` browser 用例里直接猴补 `ws.send` 的写法删掉。只保留 path 和可见行为断言。
9. 回归了 `./scripts/test-all.ps1`。`moon test`、native、browser 全部通过。说明 bridge 正式 API 和测试 API 的分层已经接上。
10. 后面继续讨论了 `DomCmd` 这层的冗余。确认 `Text` 本质上是 `textContent` 特判。长期要继续评估它和 property 写入命令的关系。
11. 也确认如果目标是完整 UI 库和 input/form，后面大概率需要补一条更贴近真实 DOM property 的命令。短期先不直接把 `Text` 合进去，避免一边补能力一边把现有安全边界打散。
12. 重新核对了 `HostCmd` 的真实用途。确认它当前只承接 `focus / blur / scrollIntoView` 这类宿主动作。随后明确要求这条能力统一归到 `trigger`，不再在 `DomCmd` 里保留平行入口。
13. 也确认了 `SetCss / RemoveCss` 现在其实是模块级 stylesheet registry，不是普通节点命令。后续方向改成把样式挂到专门的 style `VNode` 上，把这组协议整体收掉。
14. 这轮最后把几条后续清理方向单独定了下来。`Listen` 的第三个参数是冗余。后面直接删。
15. `HostCmd` 后面直接删。`focus / blur / scrollIntoView` 都归到 `trigger`。这样宿主动作只留一条主路径。
16. `SetStyle` 这类名字后面要和 `Attr` 对齐。命名目标更像 `Attr / Style / Prop`。不再留 `SetXxx` 和非 `SetXxx` 混着的口径。
17. `RemoveAttr / RemoveStyle` 后面考虑并进设置命令。删除语义不用空字符串。改成专门的空值表达，避免把“设成空字符串”和“删除”混在一起。
18. `SetProp` 这条后面还要继续收细。要先决定值类型是继续走字符串哨兵，还是直接改成可空值。当前倾向是可空值。因为它更贴近真实语义，也不会污染正常字符串空间。
19. `SetProp` 真补进去以后，还要重新检查 `Text` 是否还值得单独保留。这个判断不能现在先拍死。要等 `value`、`checked`、`selected`、`textContent` 这些真实场景落进去以后再看。
20. `trigger` 这条后面也要补一轮能力清单。至少要把 `focus / blur / scrollIntoView` 接进去。还要重新核对它和 browser test 动作层、CLI / REPL 远程动作层之间的边界，避免宿主动作又长出第二条入口。
21. style `VNode` 这条后面会是单独一轮较大的协议收缩。要一起改 `dom`、`bridge`、`mock_dom`、测试匹配器和现有 stylesheet 注册路径。不能和前面的 `SetProp`、`trigger` 小收束混在一起做。
1. 先按前面定下的协议收缩继续改 `listen`。重读了 `devlog`、`src/dom.mbt`、`src/bridge.js`、`src/dom_helper.mbt`、`src/mock_dom.mbt` 和相关 browser 用例。确认 `Listen` 第三个 `ui_id` 参数已经没有消费方。browser 侧只按 `id + event` 注册监听。这个参数是纯冗余。
2. 随后把 `Listen` 从三参收成两参。`src/dom.mbt` 里的命令定义、JSON 编码和事件注册一起改掉。`src/bridge.js`、`src/mock_dom.mbt`、`src/dom_helper.mbt`、`src/dom.test.mbt`、`scripts/browser-tests/bridge.test.js` 同步切到新签名。
3. 同一笔里把 DOM 命令编号顺序压紧。原来 `Remove` 和 `Listen` 留在 `6/7`，前面空着 `4/5`。这次把命令 tag 收成连续序列，去掉中间空号，避免协议表继续留无意义断层。
4. 改完先回归了 `moon test`。接着回归了 `node scripts/test-browser.js --start --stop scripts/browser-tests/bridge.test.js`。两项都通过。说明 `listen` 精简和命令编号压缩没有把 DOM 编码和 bridge 解码带坏。
5. 后面继续收 `src/dom.test.mbt` 里的命令 JSON 断言。现状是多处直接写裸数字 tag。协议编号一变，就要跟着改一串测试。先试过一版从 `dom_cmd_to_value(...)` 里反取 tag 再拼字符串的 helper。
6. 这版很快被否掉。它会把测试对“命令类型编号”的独立断言一起带没。编码函数如果把 tag 写错，测试会跟着读到错值然后继续通过。方向不对。
7. 按要求先把这笔错误补丁完整撤回。`src/dom_helper.mbt` 里新增的 helper 删掉。`src/dom.test.mbt` 里改过的断言也恢复成直接比具体 JSON 字符串。中间还重新确认了 `init_bridge emits json values without string roundtrip` 这条也已经回到直接断言 `"[1,1,\"ok\"]"`，没有残留“从生产编码结果反推”的写法。
8. 然后按新口径重做。先在测试辅助里试了一版 `DomCmdTags` 对象，把 tag 收到一处，再由测试拼字符串。功能上能用，但结构偏笨，而且会冒一串 unused field warning。
9. 最后把 tag 常量提回 `src/dom.mbt`。改成唯一一份顶层命令 tag 常量。`dom_cmd_to_value(...)` 直接用这组常量编码。`src/dom.test.mbt` 的 JSON 断言也改成引用同一组常量。测试侧那份 `DomCmdTags` 对象随即删掉。
10. 收完以后重新跑了 `moon test`。`124/124` 全过。warning 也一起消失。这样协议编号现在只有一份源头。MoonBit 侧测试也不再到处散落裸数字。
## 04-07 下午
1. 继续收 DOM 协议里的宿主动作入口。起因是前面已经定过 `HostCmd` 该删，`focus / blur / scrollIntoView` 只该留在浏览器 DOM 触发能力里。
2. 开始时先把 `HostCmd` 机械改名成了 `Trigger`。这版改法把协议项原样留着。方向偏了。用户当场指出问题。
3. 随后把边界重新讲清。`trigger` 属于浏览器 DOM 层。`action` 属于编辑器高层语义。两层不能混。
4. 接着单独查了测试面。确认依赖点很少。MoonBit 侧只有两条测试锁着 helper 会 emit 这条命令。browser fake bridge 用例里有一处把预聚焦塞进 `applyDom(...)`。
5. 按这份使用面重做实现。`DomCmd` 里的宿主动作项直接删掉。`src/dom.mbt` 里会 emit 它的 `focus_node / blur_node / scroll_into_view` 一起删掉。
6. `src/bridge.js` 里的 DOM batch 执行链也跟着改。`applyDomCommands(...)` 只保留结构、属性、样式、监听和样式表同步。浏览器 DOM patch 这条路不会顺手执行宿主动作。
7. browser request 里的 `trigger` 继续保留。顺手补齐了 `blur / scrollIntoView`。这样浏览器 DOM 触发能力还在，名字和职责也和高层 `action` 分开了。
8. `src/dom.test.mbt` 里两条锁旧协议存在性的测试删掉了。`scripts/browser-tests/bridge.test.js` 里原先混在 `applyDom(...)` 里的预聚焦改成测试动作序列里的显式 `focus`。
9. 第一次按 `./scripts/test-all.ps1` 回归时，功能面已经平了，但 `dom_helper` 里带出了几条未使用 helper warning。它们都只给那条旧顺序断言服务。
10. 随后把 `assert_ordered_cmds`、`find_ordered_cmds`、`copy_match_env` 一起删掉。全量回归重新干净。当前没有残留 warning。
11. 实现改完以后，又把 `event / trigger / 测试动作层` 的模型重新讲了一遍。当前实现里 `event / event_data` 表示浏览器这边真的发生并上报的事件。逻辑层消费的是这条事实通道。
12. 同一份讨论里把 `trigger` 的职责也讲清了。它表示主动让浏览器对某个 DOM 节点做一次触发。它会去启动浏览器侧那条事件链。
13. 中间还把 browser harness 现有 `act` 这层动作抽象翻出来看了一次。这个名字和高层 `action` 太近。继续留着会让语义发混。
14. 然后把目标模型提到了 `ui-id path` 这一层。公开 GUI 能力准备改成 `query` 和 `trigger` 这两个平行入口。两者都面向同一套 `ui-id path` 地址空间。
15. `query` 这边的方向先记成 `query(path, kind?, value?)`。默认读取节点。后面可以扩到 `text`、`attr`、`style`，将来再看 `prop`。
16. `trigger` 这边的方向先记成 `trigger(path, kind, value?)`。它先按稳定 path 定位，再对目标节点做 DOM 层触发。当前内部那套 `resolve path -> vnode id -> DOM node` 只该留在实现里，不该继续冒成公开接口。
17. 讨论里我一度提过对象套对象的接口写法。用户直接否掉了。这个判断是对的。那版接口更长，也更像 transport 包，和这次要压的 GUI 能力模型不合。
18. 现在还没做的事情先记清。`query(path, kind?, value?)` / `trigger(path, kind, value?)` 还没有正式落成公开接口。bridge request 里当前还在传结构化 JSON，再由 service 先解 path 再发浏览器。
19. browser harness 里的动作层也还没改名。`act` 还在。它写的其实已经接近这套 `trigger` 语义，只是名字和接口形状还没换。
20. 触发能力表也还没定死。`focus / blur / click / dblclick / input / key / drag` 当前都有实现基础，`drag_to` 这类按 `ui-id path` 描述目标关系的 GUI 操作还没开始做。
21. `query` 的读取能力也还没铺开。当前主路径还是查节点和文本。`attr / style / prop` 这些按 path 读取的口径还没补。
22. 当前测试组织也只是先把最明显的重复去掉。还没把 browser harness 的动作层统一到 path-first 的 `trigger` 模型里。CLI、browser test、远程控制也还没有共用同一套公开接口。
23. 下次如果继续改，重点已经很清楚了。先把公开的 `query / trigger` 接口表定下来。再把 harness、bridge request 和 CLI 入口一起切到 path-first 这一条主路径。
1. 继续看 `devlog` 末尾和当前实现。把这次范围重新压清。目标定成 path-first 的 `query / trigger`。范围同时落在 browser 公共 API、browser harness、CLI / REPL / HTTP 控制口。
2. 先改了 `src/bridge.js`。正式公开面改成 `query / trigger / command`。`query` 统一按 path 查 `node/text`。`trigger` 统一按 path 触发动作。browser 业务测试不再碰 `queryNode` 这类旧名字。
3. 同步补了 `service` 侧的正式 `query / trigger` 命令。CLI、HTTP 控制口、REPL 都能走这组命令。`query` 先只做 `node/text`。`trigger` 先接 `focus / blur / click / dblclick / input / key / drag_to / scrollIntoView`。
4. browser harness 也跟着改了。删了旧的 `read / act / step`。测试改成显式 `query / trigger / wait`。这样 browser 用例和正式公开能力对齐，不再留一层平行测试动作模型。
5. 中间先按拆开的测试命令跑过几次。用户指出这样会把时序判断带偏。后面把验证口径改回只认 `./scripts/test-all.ps1` 这一条。
6. 按 `test-all` 重新查以后，真正挂住的是 browser 公共 `trigger`。第一版实现把 browser 公共 `trigger` 也做成了 websocket request。同一条 browser 连接里又套一层 request，业务 browser 用例会直接超时。
7. 随后把这条实现改回单一路径。browser 公共 `trigger` 先复用 `queryPathId(...)` 让 service 解 path，再在 browser 本地按运行时 `id` 触发。这样 browser 公开面仍然是 path-first。本地 DOM 触发只留在 bridge 内部。
8. 后面又回头收命名。先把 `bridge.test.trigger` 改成更不易误用的测试名字。再把整个测试命名空间从 `test` 改成 `bridgeTest`。最后把触发入口定成 `bridgeTest.triggerById`。这样正式 API 和 bridge 白盒测试 API 不再混名。
9. fake websocket 那边也补了说明。注释放在 mock websocket 对象定义前。说明这层只是在 bridge 白盒测试里占住 `send/close` 形状，不承载真实连接生命周期。
10. 这次还顺手重看了 `service/bridge.mbt` 的消息结构。确认文件原本已经按 `type` 分发消息。真正脏的是分发之后各个 handler 还共用一个超宽字段并集 `BridgeMsg`。
11. 接着试了一版更窄的消息结构。把 `BridgeMsg` 删掉，换成按 handler 自己需要的几份最小消息结构，像 `BridgeEventMsg`、`BridgeResponseMsg`、`BridgeHelloMsg`、`ReplRequestMsg` 这些。这样每个 handler 只解自己真正要用的字段。
12. 还没做完的条目有：
13. `service/bridge.mbt` 里的 handler 骨架重复还很多。现在虽然不再共用 `BridgeMsg` 这个大袋子，但 `from_json`、`unwrap_or(...)`、success/error 包装、`path -> id -> request` 这些模板代码还在多处重复。
14. 这次 `service/bridge.mbt` 的消息结构拆分先把语义压直了，但文件净行数没有压下去。后面如果继续改，重点应该是删模板代码，不是继续补更多小 struct。
15. `query` 的读取能力仍然只做到 `node/text`。`attr / style / prop` 这一组没有继续做。
16. DOM/property 协议这条线没有继续动。`SetProp`、`RemoveAttr / RemoveStyle` 往可空值语义改、`Text` 是否继续独立，这几条都还停在讨论口径。
17. style `VNode` / stylesheet registry 这条更大的协议整理也没动，仍然是后面单独一轮的大项。
1. 先审了 `service/cli.mbt` 里“命令定义和实现同源”这次改动。确认命令名、帮助文案、flag 列表和大部分执行体已经收进 `CommandDef`。但还残留三处平行语义。命令表还不是唯一源头。
2. 第一处残留在 `parse_command(...)`。`help`、`exec`、`roots` 还在按命令名特判。遇到未知 `--xxx` 会把它当普通参数吞掉。命令表里没有这条语义。新增同类命令时容易漏改。
3. 第二处残留在 `run_command(...)`。非 `--json` 输出格式还在按命令名二次分发。新增远程命令时，要同时改命令表和输出分支。定义和实现还没完全收成一处。
4. 第三处残留在 `run_client_mode(...)`。`help` 还留着一条 client 侧本地快捷路径。没有完全走命令定义。虽然行为和远程分支暂时一致，但结构上还是平行入口。
5. 随后先收了一版 `CommandDef`。把未知 flag 处理策略、默认文本输出格式、client 侧 fallback 一起收进命令定义。`run_command(...)` 和 `run_client_mode(...)` 改成只按定义执行。这样新增命令时不再需要在多处补名字分支。
6. 这版第一次回归时，`./scripts/test-all.ps1` 带出两个 MoonBit 类型问题。一个是枚举不能直接 `==` 比较。另一个是结构体里的函数字段调用要加括号。按最小补丁修掉以后，全量测试重新通过。
7. 接着又尝试把 `CommandDef` 里高噪音字段做成可选，再在消费点补默认值。功能上能通。代码上却长出一组 `usage_or_empty`、`flags_or_empty`、`output_or_default` 这类读取 helper。多了一层无意义包装。
8. 没继续保留这版。回头把方向压到定义入口。只保留一个 `command(...)` 构造函数统一填默认值。`CommandDef` 本身重新收回普通非可选字段。这样命令表能继续写短，消费点又不用到处 `unwrap_or(...)`。
9. 这一步中间又踩到一次 MoonBit 的函数字段调用细节。把调用写法补成带括号以后，`./scripts/test-all.ps1` 重新通过。随后把已经无用的 `OutputFormat::Json` 一起删掉，避免留下 warning。
10. 后面又继续收严命令解析。把 `FlagPolicy` 和 `PassthroughUnknown` 整体删掉。现在所有命令都统一走严格解析。未知 command 直接报错。未知 flag 也直接报错。
11. 这次收严以后，`help`、`exec`、`roots` 不会再把未知 `--xxx` 当普通参数继续转发。`help` 只保留“空参数时本地直接显示帮助”的 fallback。这条 fallback 也先经过同一套解析。
12. 最后又把 `meta` 自己的全局 flag 和命令级 flag 的边界重新讲清。`--debug-timing`、`--state-dir` 还是在 `main` 里先吃掉。`exec` 这条命令当前只做到“命令级严格”。真正的 entry action 合法性，仍然由 `src` 里的 action 定义负责校验。
## 04-07 晚上
1. 继续收 `src/bridge.js` 里的内部重复。先把节点查询、`trigger` 命令整形、socket request/message 分发都重新压了一遍。目标是少概念。也少一层层薄包装。
2. 中间先把 `apply(...)` 改成 `domOps` 分发表。第一次改法把 `LISTEN` 直接绑到了后定义的 `listen`。页面加载时立刻报 `Cannot access 'listen' before initialization`。browser bridge 根本起不来。
3. 顺着 browser harness 往下查以后，确认问题不是 bridge ready 真要等很久。问题是页面脚本初始化已经失败。测试当时却还会沿默认等待链继续等，错误暴露得太慢。
4. 随后把 `scripts/test-browser.js` 的执行层收了一次。让 hook 和 test 共用一条带超时的执行入口。也把页面 `pageerror` 接进这条入口。这样 browser 初始化失败会直接报真实错误，不再只看到笼统超时。
5. 接着把页面相关等待单独收紧到 1 秒。`open page` 和 `bridge_ready` 都不再沿用原来的长等待。browser 初始化类问题现在会更快暴露。
6. 后面按要求继续收 `domOps`。把一批中间 helper 直接内联回 `domOps` 对象里。`listen` 也一起内联。对象外那份同逻辑实现删掉了。这样 DOM 命令执行面只留一份实现。
7. 再往下把 bridge 里的命名和层级继续压直。节点定位和查询结果这条线收成更少概念。中间一度用了 `queryResult` 这个名字。随后又按要求改回统一叫 `queryById`。同一件事不再留两套名字。
8. `trigger` 这条也继续收了。把原来拆开的命令整形逻辑合回一条 `triggerCommand(...)`。path 解析和动作命令整形现在走同一路径。少了平行 helper。
9. socket 分发也一起收了。`handleSocketRequest` 和 `handleSocketMessage` 都改成表驱动。删掉了重复的手写判断链。分发边界更短。
10. 中间又查到键盘事件字段在几处反复手写拆包。`key / key_event / code / ctrl_key / shift_key / alt_key / meta_key` 随后收成 bridge 里的唯一一份 helper。browser harness 也改成直接复用这份字段整形。不再各写各的。
1. 先看了 `host`、`bridge`、browser tests 和 CLI 现状。确认 `host` 只有 `select_entry / spawn / focus_window / close_window / stop_service`。拖拽、缩放、最大最小化都还没落。
2. 也确认了桌面图标选中态和窗口状态有耦合。`spawn` 会把 `selected_entry_id` 改成当前 entry。`close_window` 会把它清掉。
3. 先按这个判断改了一版 `host`。加了桌面空白点击清选中。把 `spawn / close_window` 对 `selected_entry_id` 的顺手修改删掉。也补了 mock 和 browser 测试。
4. 这版实现后来被否掉了。原因有两条。第一条是为了处理空白点击和测试点位，把桌面结构拆成了额外几层。第二条是写了和 `ui-id` 重复的 class。方向偏了。
5. 随后停下这条改动。先把 browser test 的观测能力补齐。起因是没有正式样式读取能力时，browser test 只能靠页面里临时 `getComputedStyle(...)` 或猜点击点。测试基准会发飘。
6. 接着补了 `query style PROP`。改动落在 `src/bridge.js`、`service/cli.mbt` 和 `scripts/test-browser.js`。`query` 现在可以读取单个 computed style 属性。
7. browser harness 也跟着补了 `style_eq / style_includes` 这组等待口径。这样 browser test 可以直接按关键 `ui-id` 断言最终样式，不用再散落页面内白盒代码。
8. 同时补了 browser bridge 测试。现在有一条会给真实 DOM 节点设样式，再用 `query(style)` 读回来。说明这条正式能力已经接上。
9. 再把 host browser test 收到了样式断言上。先锁“窗口聚焦不会改掉 entry 的选中背景色”。桌面空白点击清选中这条，当时先留在 mock 覆盖里。
10. 这一步第一次全量回归时，native 里一条 `trigger` 测试挂了。根因不是 `query(style)` 本身。根因是我把那条测试原本锁着的一层业务语义顺手拆掉了。
11. 那条 native 测试本来同时锁两件事。第一件是 `request_browser_path(...)` 会先把 path 在 `src` 里解析成 id。第二件是浏览器回传 `ondblclick` 以后真的会开窗。
12. 中间我一度把那条测试里的浏览器事件回传删掉了。这样虽然 request 结构还是对的，但最后 `demo-1` 不会被开出来。随后又把这条事件回传补回去。native 测试恢复。
13. 然后继续回头收 `host` 的实现长度。用户明确要求只考虑 host 这一层最短实现。还要求补 `stopPropagation`，不要再靠多长一层背景结构去避事件冒泡。
14. 为了做这件事，先重新看了事件层。确认当前现成能力只有 `preventDefault` 相关数据。没有真正的 `stopPropagation` 主路径。
15. 随后在事件主路径里加了 `.stop` 修饰语义。bridge 浏览器监听时会按它做 `stopPropagation()`。MoonBit 侧还是只按去掉修饰后的事件名注册 handler，不另长平行事件名。
16. 然后把 `host` 的桌面结构收回单层。桌面根节点自己负责清选中。entry 的 `click / dblclick` 都改成 `.stop`。close 按钮也改成 `.stop`。这样去掉了之前那套额外背景层和图标层。
17. 这一步的 mock 和 browser 测试也跟着改了。mock 里的“点桌面空白清选中”改成直接点 `desktop-root`。browser 里的“图标选中态和窗口焦点解耦”继续按样式断言来锁。
18. 这里又暴露出一个新问题。browser 里对 `desktop-root` 做 `trigger click` 会报错。报错点落在 `src/bridge.js` 的 `triggerPointer(...)`。
19. 当时的报错不是 query 找不到 `desktop-root`。而是 `triggerPointer(...)` 对 `click` 直接假设目标节点有 `.click()` 方法。实际目标不满足这个假设。于是抛了 `node.click is not a function`。
20. 我当时一度把这件事表述成“`desktop-root` 不稳”。这句表述是错的。真正能确认的只有 browser bridge 的点击触发实现有问题，还不能把锅甩到 `desktop-root` 查询入口本身。
21. 目前还没查清的是：`query('desktop-root')` 最终映射到的真实 DOM node 到底是什么。需要继续把 `query(path)` 返回的 `id/kind/tag`，以及 bridge 内部 `managed(id).node` 的 `nodeType / constructor.name / tagName / 是否有 click` 查出来。
22. 这一步之后，还顺着 CLI 交互流程又带出一条更上游的问题。`meta start` 返回后，当前语义还不保证“立刻可 `query / trigger`”。这会让脚本和自动化都很难写。
23. 现在的实际时序更像这样。`start` 只保证服务进程起来了。后面还要等 browser connected。还要补 `roots host`。严格点还要再补 `sync`。这说明 `start` 的完成语义偏弱。
24. 这条问题还没做。后面的 agent 如果继续查，重点不是先补脚本。重点是先明确 `meta start` 应不应该收成“返回即 ready for query/trigger”。如果答案是应该，那就要把 browser connected、默认 root 准备和 DOM ready 收进 `start` 的完成语义里。
25. 到目前为止，已经真正落地并回归过的部分有两块。第一块是 `query style PROP` 这条正式能力，以及 bridge/browser harness/browser test 对它的接入。第二块是“图标选中态和窗口焦点态解耦”这条行为，以及对应的 mock/browser 覆盖。
26. 到目前为止，还没收成最终实现的部分也有两块。第一块是 `desktop-root click` 在 browser bridge 里为什么会打到一个没有 `.click()` 的目标。第二块是 `meta start` 的完成语义太弱，返回后还不能默认立刻交互。
1. 先把 Codex 安装的 skill 覆盖复制进仓库，再把 Codex 那边改成指向仓库内容的目录链接。原因是 skill 后面会频繁改。两边分开维护太容易漂。
2. 接着把 skill 从文档子目录提到仓库根目录。名字也改成仓库级 skill。原因是这份内容已经不只是 DOM/runtime 局部说明。继续挂旧名字会误导后面的 agent。
3. 随后把 reference 文件从 `runtime-semantics` 改成 `dom`。原因是文档实际写的是 DOM、查询、bridge、作用域这些边界。再叫 runtime 语义已经不贴。
4. 中间先按当前代码和测试把 skill 改成中文。补了动态列表必须有 list scope、名称空间用来缩短 `ui-id`、`ui-id` 派生 class、不要自己发明平行查询 id 这些规则。目的是先把最容易把 agent 带偏的几条收紧。
5. 后面用户指出 `.stop` 这类 listener 字符串修饰语法是上一个 agent 发明出来的错误方向。随后重新查了事件链。确认现有代码里没有正式的结构化 listener 参数模型。`preventDefault` 也只有 bridge 里的局部硬编码。不能写进 skill 当正式语义。
6. 接着又把 skill 里几处误导性说法收掉了。包括“工作流先读”和“需要时再读”对同一份文档的重复。也把把 `runtime` 当总括词乱用的表述压掉了一批。
7. 再往下读代码时，开始怀疑 `runtime_render`、`realize`、`mount`、`render`、`flush` 这几层命名和职责已经缠在一起。继续扩写 skill 风险很高。所以先停下规则整理，转去查代码模型本身。
8. 随后顺着 `try_flush`、`on_post_flush`、`init_bridge`、`runtime_render` 查完整条提交链。确认现在 DOM 命令本身没有清晰独立的 flush/commit 机制。DOM 提交是直接挂在 reactive 的 post-flush 上。
9. 这一步把更大的设计问题也压出来了。系统可以有统一最终 flush。但 DOM 自己至少也该有明确的提交层。当前实现把 reactive 提交点和 DOM 提交点混在一起，更像后来顺手接上的实现，不像一开始就设计好的边界。
10. 这次先不继续扩写 skill。先把现有 skill 收到可用状态。再把“代码模型本身还不稳，尤其是 DOM flush 和全局 flush 的边界不清”这个判断记下来，留给后面的 agent 继续查。
1. 给仓库补了开源许可文件。先确认根目录没有现成的 `LICENSE`，再从 GNU 官方地址取回 `AGPL-3.0` 原文，直接放进根目录。随后核对了文件头，确认拿到的是完整的 `GNU AFFERO GENERAL PUBLIC LICENSE Version 3, 19 November 2007`。
2. 给仓库补了贡献条款文件。目标是明确“向仓库贡献代码时，相关权利移交给仓库所有者”。新增了根目录 `CONTRIBUTING.md`，里面写清了提交权限保证、权利转让、仓库所有者可自由使用和再授权，以及转让条款部分失效时改用永久排他许可承接。
3. 中间单独查了一次 AGPL 的适用说明。确认项目署名不适合直接插进 `LICENSE` 正文，更适合放在 `README`、源码文件头或者单独的版权说明文件。
4. 最后按这个口径新增了根目录 `COPYRIGHT`。里面写明 `Copyright (C) 2026 ch3coohlink`，并说明项目版权归仓库所有者，完整许可证见 `LICENSE`。
5. 顺手把 `browser test` 从 `scripts` 里提了出来，并改名为 `e2e`
## 04-08 上午
1. 继续按 skill 和 src 测试收 host 的 UI 命名。目标是彻底去掉 `window:1` 这类把业务序号写进 `ui-id` 的错误模型，改成“少前缀，多名称域，多 list scope”的路径设计。
2. 起初一度把路径想成“要沿 DOM 一层层往下跳”。用户指出同一层名称空间里本来就可以直接跳，不需要机械沿 DOM 下钻。这个提醒把模型重新纠正了。
3. 随后把 host 的局部命名重新规划成更短的方向。结论是全局最好只留一个 `root`。`desktop`、`topbar`、`windows` 挂在 `root` 下。`entries`、`tray` 这些再在各自局部作用域里继续分层。
4. 也重新压清了窗口项这层的边界。`windows/0` 本身已经是 list item 作用域，所以窗口项不该再额外套一层 `window` 名称域。更合理的目标路径应该是 `root/windows/0/titlebar/title`、`root/windows/0/body` 这种形状。
5. 继续只用 `moon test` 调逻辑层。过程中把 host 的一些局部命名先收短了。像 `entry` 里面改成 `icon`、`name`。`topbar` 里面补了 `tray` 的局部名。`window` 里面改成 `titlebar/title/close/body` 这种短名组合。
6. 调试过程中一度把 `desktop` 里的点击背景也命名成了 `root`。这会直接把真正的 host 根节点 `root` 覆盖掉。随后已经修掉，改回局部名，避免同一个 host 自己内部先把根入口打坏。
7. 后面继续查以后，发现不带嵌套 host 的场景大多能接上。真正持续挂住的 3 条都是“开出嵌套 host 以后，再去查外层 host 的窗口和 topbar”这组场景。
8. 问题随后被压到 query 起点规则，不在 host 业务逻辑本身。当前查询第一段会先去全局 `ui_nodes` 里按字符串找节点。这个表是全局唯一的平面映射。
9. 因为所有带 `ui-id` 的节点都会进这张全局表，所以外层 host 注册一批 `root / topbar / desktop / windows` 以后，内层 host 再渲染时会再注册一批同名入口。后注册的同名入口会把前面的覆盖掉。
10. 结果就是：像 `root/windows/0/titlebar/title` 这种本来应该落到外层 host 的短路径，只要窗口里再开一个 host，第一段 `root` 就可能先命中内层 host。后面的整条路径都会在错误的树里继续解析。外层窗口树因此失去可达性。
11. 这也解释了为什么这次 host 路径模型本身没有明显逻辑错误，但嵌套 host 场景始终过不去。真正缺的是 query 根入口的分层语义，不是再给 host 拼回 `window:1` 这种旧名。
12. 这轮已经明确否掉的方向有两条。第一条是 `window:1` 这种写法必须彻底禁掉。第二条是冒号本身也不适合继续留在 `ui-id` 命名里，因为后面准备把 `<ui-id>:list`、`<ui-id>:ns` 做成正式语法，host 这边不该再制造和未来语法冲突的错误暗示。
13. 当前问题可以直接拆成几条给后续 agent：
14. query 第一段现在是“全局唯一字符串 key”，它还不是“当前根作用域里的名字”。这个模型和多层 host 下的短路径目标是冲突的。
15. 只要第一段还先查全局平面 `ui_nodes`，多层 host 下的 `root / topbar / desktop / windows` 这类短名就一定会互相覆盖。host 代码层再怎么收短都解决不了这个根问题。
16. 后续需要决定 query 起点到底怎么改。要么第一段不再直接走全局平面表。要么引入“从某个已知根节点开始解析局部 path”的正式入口。要么给根入口本身补真正分层的注册语义。
17. 在这个问题修掉之前，host 这边不能用 `window:1` 这类错误模型去绕。短路径模型本身是对的。现在卡住的是 query 基础设施还不支持多层同名根作用域。
1. 继续追 `query path` 全局查询问题。先重读前面的记录、skill 和 `dom/query` 相关实现。目标是把“嵌套 host 后外层 `root/...` 查不到”这件事单独压到基础设施层，不再在 host 业务层乱试。
2. 先把 `src/dom.mbt` 的查询起点重新拆开看了一遍。确认 `resolve_ui_query(...)` 的第一段一直直接查全局 `ui_nodes` 平面表。这个表按字符串只保留最后一次注册。同名入口后注册会覆盖先注册。
3. 这一步把根因讲清了。外层 host 先注册一批 `root / topbar / desktop / windows`。内层 host 再渲染时又注册同名入口。随后 `root/...` 第一段会直接跳到内层 host。后面的整条路径都会在错误的树里继续走。真正坏的是 query 起点语义，host 短路径模型本身没有错。
4. 又顺着 `scope_names`、`list_items`、`refresh_scope_owner`、`refresh_scope_chain` 查了一轮。确认局部作用域链本身还成立。`ui-name`、`ui-list`、列表索引解析都没有先坏。问题集中在 query 第一段的根入口选择。
5. 还顺手确认了一条兼容边界。当前不只有 `root/...` 这种多段路径在用，`demo-add` 这类单段查询也已经被测试锁住。所以不能简单把第一段收成“只允许顶层根自己的 `ui-id`”。还得继续支持“从当前已挂载树里找到当前可达名字”这层语义。
6. 为了把判断压实，先用现有测试回归了一次。`src/host.test.mbt` 里嵌套 host 相关的 3 条失败和这次根因能对上。`service/repl.test.mbt`、`e2e/host.test.js` 里还混着旧 host path 合同，属于另一层噪音，不是主因。
7. 随后直接改了 query 起点。把 `src/dom.mbt` 里的全局 `ui_nodes` 名称表整块删掉。第一段改成从当前存活根节点里按顺序解析首段名字，不再让后挂载的同名根覆盖前面的根。这样 query 不再依赖全局平面字符串表。
8. 同一笔里把原来围着 `ui_nodes` 的注册和清理一起删掉。元素创建、列表 anchor 创建、节点清理都不再顺手维护全局名称表。这样 query 主路径只剩“当前树结构 + 当前作用域”这一套来源，没有平行状态。
9. 改完以后先把 `service/repl.test.mbt` 的旧 host path 对齐到现在合同。浏览器 query/trigger 请求测试改回当前的 `root/workspace/desktop/entries/items/0/entry` 这条路径。这样 native service 那两条测试继续锁“service 先在 src 里把 path 解析成 id，再发给 browser”的语义。
10. 为了防止“同名根重建”这种边界以后再回退，又在 `src/runtime.test.mbt` 补了一条回归。场景是默认 host 已经挂上以后，再执行一次 `roots host`。这时 `root/...` 仍然必须能解析。用来锁住“同名根替换后 query 起点仍然稳定”。
11. 回归 MoonBit 时，又把另一件被旧 bug 掩住的问题带出来了。`src/host.test.mbt` 有两条断言把 `items/0`、`items/1` 当成稳定窗口业务 id 在用。实际 `h_map` 列表会跟 `z_order` 重排。索引不是稳定业务合同。之前因为 query 起点先坏了，这个测试假设一直没暴露出来。
12. 随后只改测试，不动生产逻辑。把 `focus_window` 和 `close_window` 那两条断言改成按“当前可见顺序”断，而不是按“窗口业务 id 永远待在固定索引”去断。这样测试重新和当前列表语义对齐。
13. 到这一步，`moon test` 和 native 都已经回到全绿。说明这次 query 起点改动本身已经接上。嵌套 host 下外层 `root/...` 查询恢复了。service 侧按 path 解析 browser 请求也恢复了。
14. 后面继续查 browser host 用例时，先碰到一个误导。当前源码里 host 结构已经是 `root/workspace/...`。但 browser 探针实际查出来的页面里仍然有旧的 `desktop-root`，却没有 `root/workspace/...`。这说明问题不在 host path 文本本身，而在 browser 测试启动时实际跑到的 service 产物来源。
15. 顺着 `scripts/test-browser.js` 往下查，确认 browser 测试启动的是 `_build/native/debug/build/service/service.exe`。而 `./scripts/test-all.ps1` 前面只会先跑 `moon test` 和 native 测试二进制，不会顺手重建这份 service 可执行文件。结果就是 browser 一直可能吃到旧二进制，页面结构和当前源码漂掉。
16. 这里我中间走偏了一次。试过把 `build-native` 直接塞进 `scripts/test-browser.js`。想法是让 browser 测试自己先把 service 构建出来。这个方向很快证明不对。它会把 browser 测试和构建绑成一条，直接拖慢测试，还让 harness 自己长出构建职责。
17. 这版错误补丁随后已经完整撤回。没有把 `build-native` 留在 browser harness 里。browser 测试仍然保持纯执行入口，不负责准备产物。这一步专门回退，是为了不把“修 query”顺手做成“测试入口变慢”的副作用。
18. browser host 那边还顺手查出一个测试层面的重复等待。我一度为了绕过 beforeAll 的 1 秒预算，在 `e2e/host.test.js` 里每条用例前都补了同一条 `await t.wait([{ kind: 'exists', path: demoEntry }], ...)`。这会把同一层 ready 等待写三遍，也会把真正的初始化边界藏起来。后面已经删掉，没有继续保留。
19. 最后按唯一入口重新回归。`./scripts/test-all.ps1` 的结果回到全绿。`moon test`、native、browser 都通过。当前实现下，query 起点已经不再依赖全局名称表，嵌套 host 场景也不再把外层 `root/...` 抢走。
20. 这次排查里还把几条问题边界一起记清了。第一条是“多个顶层同名根如何同时可达”这件事，这次还没展开设计。当前只是先保证“后挂载的同名根不会覆盖前面的根”。
21. 第二条是“entry 根入口名是否应该由组件内部硬编码”。现在倾向是不该。长期更合适的是由外层挂载点赋名。这样对 host 和任意 component 都更一致。这个方向这次没有实现，只先记成后续设计项。
## 04-08 下午
1. 继续查 `query path` 全局查询。先重读 `devlog`、skill 和 `dom/query` 相关实现。确认根因在 `src/dom.mbt` 的 query 第一段。它原来先查一张全局平面名字表。多层 host 下同名根会互相覆盖。
2. 随后把这条改成按当前存活根节点解析第一段。把那张全局名字表删掉。又补了一条 `runtime` 回归。锁住“把 host 根重新设成 host 以后，`root/...` 还能继续查”。
3. 同一轮里把相关测试 path 对齐到当前口径。`service/repl.test.mbt` 改成走 `root/workspace/...`。`host` 相关 MoonBit 测试也跟着收了一轮。`moon test` 和 native 都重新过了。
4. 继续查 browser host 失败。开始时只能看到整条用例超时。看不到具体卡点。后面检查 `scripts/test-browser.js`。确认外层整条 test step 和内层 `query/trigger/wait` 都在用同一个 timeout。内层超时会被外层盖掉。
5. 随后把 browser harness 的外层测试超时单独拆成 `testTimeoutMs`。让它大于内层 `timeoutMs`。这样 browser 失败能明确报到具体等待点。当前卡住的是 `host spawn demo window wait` 和 `host existing window wait`。
6. 中间我一度把 `build-native` 塞进了 browser harness，想让 browser 测试总是吃到最新 service 二进制。这个方向被当场指出不对。随后已经完整撤回。browser harness 继续只负责执行，不再自己构建。
7. reviewer 又指出了两处真实回归。我回头查了 `host.mbt`。确认 topbar 项被我改成了 `window`，会错误吃到桌面窗口样式。也确认我把清选中动作挂到了一个没有尺寸的空 `background` 节点，真实点击空白桌面时不会稳定命中。
8. 随后按最小补丁把这两处修回去。topbar 项的 `ui-id` 改回 `topbar-window`。桌面清选中重新挂回 `desktop` 自身。MoonBit 和 native 重新过了。browser 还剩两条 host 等待超时。
9. 后面按要求把 `bind` 改成了 `bind_action`。只改了 `ActionBind` 这层在 `entry/demo/host` 里的局部名。没有去碰别的 `storage` 里的 `bind`。这步回归以后，MoonBit 和 native 仍然通过。browser 失败数没有变化。
10. 再往后开始讨论 `windows/0/window` 这层是不是多余。我一开始把这件事误读成要改底层 list scope 语义，误去碰了 `dom`。随后被当场打断，又把 `dom` 整个文件直接回退了。最后重新讲清了当前口径：`list/0` 本来就是 item root，只是它不够稳定，不推荐当主要业务合同；这次不该先动底层 query 语义。
11. 当前收尾状态是：`query` 第一段不再走全局平面表，MoonBit 和 native 都通过。browser 还剩两条 host 用例没过。现在已经能报出具体超时点，不再只有整条 test 笼统超时。下一步该继续只查 host wait 里那几个 path 和时序。
1. 重写了 `skill/SKILL.md` 的入口结构。开头先讲系统的两条主线：自底向上的 `reactive -> dom -> entry/instance -> runtime -> service/browser/cli`，以及自顶向下的“复杂编辑器 UI 框架 + AI 一等支持”。这样先把设计逻辑立住，再往下讲概念和规则。
2. 中间把几组容易混掉的概念重新拆开。把 `VNode.id` 的运行时稳定性和 `ui-id/path` 的可寻址稳定性分开写，又补回了 `DomCmd`、`Child`、query scope、`ui-react`/`react-scope` 这些概念，同时把高层语义收回 `action`，不再把 CLI 里的 `command` 当成系统正式概念。
3. 扩展文档最后收缩成只保留 query 这一条。新写了 `skill/references/dom-query.md`，放弃大段抽象说明，改成“推荐代码片段 + 可用 path + 不要怎么写”的结构，让读者直接从代码和 path 合同理解 query 语义。
4. 在 `dom-query` 里重点把一件事讲清了：query 走的是名称空间和列表作用域，不是沿 DOM 树逐层下钻。为此专门补了中间多包一层、甚至中间节点自己也有 `ui-id` 的例子，说明 path 仍然可以直接写短，不需要把每层 DOM 都塞进路径。
5. 同一轮里把 `ui-id` 的命名约束和 CSS 用法也压进文档。明确了 `/` 不能出现在 `ui-id` 里，后来又把 `:` 的口径收成只保留给语法用途；同时补了短 `ui-id` 的推荐写法，以及派生 class 后 CSS 要写成层级选择器组合，避免直接写大范围的叶子选择器。
6. 最后把 query 相关文档统一切到了新的短写法目标。普通稳定名继续用 `ui-id`，名称空间入口改成 `ui-id:scope`，列表入口改成 `ui-id:list`，局部 reactive 生命周期改成 `react-scope`。
7. 中途有一次把它误写成“`ui-id` 再加布尔开关”的错误口径，后面已经按用户给的示例全部修正回“值直接写在 `ui-id:scope` / `ui-id:list` 上”。
1. 先按要求重读了 devlog 末尾和 skill，重新确认这轮目标是把 `ui-id` 新模型一次落实，不留旧的 `ui-name / ui-list / ui-react` 平行入口，同时把 reactive scope 的文档口径收成 `react:scope`。
2. 随后先写了一组使用例子，和用户对齐模型：`ui-id` 只表示普通稳定名字，`ui-id:scope='x'` 直接声明名称空间入口，`ui-id:list='x'` 直接声明列表入口，`react:scope` 只管局部 reactive ownership，不参与 query 命名。
3. 先只改了 `src` 主路径。把 `src/dom.mbt` 里的宿主属性解析从 `ui-name / ui-list / ui-react` 收成 `ui-id:scope / ui-id:list / react:scope`，同时把 `ui-id:scope`、`ui-id:list` 改成直接从属性值里拿名字，再回填成正式 `ui-id`，不再要求同一个节点额外再写一份 `ui-id`。
4. 同一笔里把 `ui-id` 校验收严了。现在同时拒绝 `/` 和 `:`。原因是 `/` 已经是 path 分隔符，`:` 已经留给 `ui-id:scope / ui-id:list / react:scope` 这种语法位，不能再回头拿它当普通名字字符。
5. 然后把 `src/host.mbt` 切到新声明方式。原来带 `ui-name` 的那些宿主节点，像 `root / workspace / desktop / entries / window / titlebar / body / topbar / tray` 这些，都改成了直接用 `ui-id:scope='...'` 声明。
6. 接着把 `src/dom.test.mbt`、`src/mock_dom.test.mbt` 里锁旧口径的测试整体对齐。测试名、属性名和示例 path 都收成了新模型。中间还把那些旧测试里拿 `:` 当普通 `ui-id` 字符的例子一起改掉了，避免测试自己还在证明旧约束。
7. 这一步之后先只跑了 `moon test`。第一次只剩一条 derived class 相关断言没对齐。随后把那条测试改成按“存在同一条 class attr”断，不再依赖属性发射顺序，同时补了一条 `panic ui-id rejects colon`。之后 `moon test` 回到 `126/126` 全过。
8. 在 `src` 这条线收完以后，又把 skill 和 reference 文档口径一起对齐了一轮。把 `react-scope` 全部改成 `react:scope`，同时把 reference 里还残留的 `ui-name / ui-list / ui-react` 表述同步改掉，保证代码和文档不再分叉。
9. 然后开始跑全量 `./scripts/test-all.ps1`。MoonBit 和 native 都通过，browser 还剩 host suite 的 2 条等待超时。失败点集中在“打开窗口后等待窗口节点 / 选中态”这一组。
10. 中间按用户的提醒去看了提交 `037fec673643f4b4c1d427dff7463dbfcca96c98`。确认那笔改动主要把 `runtime_run(...)` 从旧的 `(cmd, arg)` 改成了 `(cmd, CmdContext)`，同时把 `exec` 的 action 调用路径换成了新的 `ctx.args / ctx.flags -> parse_cmd -> call_instance(...)`。当时判断 browser host 失败更可能和这条 `runtime / command` 链有关。
11. 后面我又误判了一次，以为 browser 失败有一部分来自 service 可执行文件没有更新，还把之前 devlog 里那句“browser 可能吃到旧 service.exe”当成了事实继续往下推。用户已经指出这条记录本身就是错的，而且 `test-all` 本来就会更新 service 产物，这一段判断应该作废，不能写成结论。
12. 在继续查 browser host 最后一条失败时，我又试了一版错误方向：为了绕开浏览器里 entry 点击冒泡到 desktop 的问题，给桌面加了一个背景子节点，并手写了 `.desktop-bg` class，把“清选中”动作从 `desktop` 挪到这个背景节点上。用户随后质疑了这件事，指出不该在这轮里再手补 class 语义。我已经承认这步方向不对，应该撤回，不能当最终实现写进 devlog。
13. 当前真实状态是：`src` 这边的新模型已经正式落成，`moon test` 全绿，skill 和 reference 的命名口径也已经切到 `ui-id:scope / ui-id:list / react:scope`；browser 这条链还没收成最终正确修复；
14. 我对 `test-all` 是否更新 service 产物有过错误判断，这条不能写成结论；我还留了一版不该保留的 `desktop-bg` class 试探补丁，需要后续 agent 按 runtime / browser 的真实根因继续查，并把这类绕路补丁清掉。
1. 继续收 `host` 的 `ui-id` 域。把 `workspace` 从域里拿掉。保留成普通 DOM 节点。
2. 发现我一开始把 `entry`、`window`、`topbar-window` 连 `ui-id` 也删了。这个会把样式锚点一起删掉。随后改回只删域，不删 `ui-id`。
3. 接着把 `host` 里所有手写 `class` 往 `ui-id` 收。最后只保留最外层 `host` 这一条手写 class。
4. 重新核对域树时，又发现 `entries`、`windows`、`topbar-windows` 都出现了同名双入口。外层一个普通 `ui-id`。里面 `h_map` 又注册一遍同名 list 域。
5. 随后把这三处重名收掉。保留真正的 list 域入口。删掉外层那层同名 `ui-id`。
6. 又把 topbar 里的 `topbar-window` 收成 `window`。因为它已经处在 `topbar-windows:list` 里，前缀是重复语义。
7. 中间为了给 CSS 找宿主，我一度把选择器写成了很长的 DOM 层级，还混进了 `div.window` 这类标签限定。用户当场指出方向不对。
8. 随后把思路压回 `ui-id` 域本身。确认问题不在 `host` 局部。真正卡住的是 `h_map` 的 list 域没有真实 DOM 宿主。
9. 接着改了 `h_map / h_map_dyn`。只要有 `ui_id`，默认自动创建一个 wrapper 节点。这个 wrapper 同时承担真实 DOM 宿主、CSS 锚点和 list 域入口。
10. 一开始我把这个能力写成了 `wrap_tag`。后面又按讨论改成两个参数：`wrap` 和 `tag`。
11. 现在这组参数的口径是：有 `ui_id` 默认自动包 `div`。改 `tag` 也会自动包。只有显式 `wrap=false` 才关闭这层 wrapper。
12. 然后把 `host` 的三个列表接到这条新能力上：`entries`、`windows`、`topbar-windows` 都不再需要业务层手包同名 DOM。
13. 最后把 `host` 的 CSS 收回按 `ui-id` 域写。去掉那套又长又依赖 DOM 包裹层的选择器。改成像 `.windows .close`、`.entries .icon`、`.topbar-windows .window` 这种写法。
14. 回归时，`moon test` 重新全过。`native` 也过了。browser 还有 3 条 `host` 相关路径没对齐，先留给后面的 AI 继续查。
15. 用户希望后面调用 h_map/h_map_dyn 时，ui-id 等可选参数应该写前面，特别记录一下这条。
16. 后面又顺手把 `create_list_host(...)` 收短了一次。先试了一版直接复用 `h(...)` 的构造逻辑。这样 `ui-id`、派生 class 和基础节点构造都能走同一条现成路径，代码明显更短。
17. 这版刚落下就带出一个 warning。`ns` 参数变成了未使用。继续查以后，确认问题不只是 warning。本质是我一开始偷用了 `realize_current(...)`，它内部固定按 `ns_html` 落地。这样一来，`svg/math` 这类非 html 场景会被错误降回 html。
18. 随后把这处改正。没有继续用 `realize_current(...)`。改成直接匹配 `h(...)` 返回的 `Lazy(f)`，再用当前传进来的 `ns` 调 `f(ns)`。这样保住了当前命名空间，warning 也一起消失。
19. 又顺手全局查了一轮同类问题。重点看了 `realize_current(...)`、`children(...)`、`attach(...)` 和元素渲染这几段。确认真正同类的漏传 `ns` 问题目前只看到刚修的这一处。
20. `children(...)`、`attach(...)` 里都还在继续传当前 `ns`，没有再丢。`realize_current(...)` 仍然固定走 `ns_html`，但它当前更像一个“按 html 根直接落地”的入口，不是这次这种误用。
21. 用户进一步将 `realize_current` 的参数修改为可以传入 `ns`，然后修改了 `create_list_host` 确保同样的逻辑只写一份
## 04-08 晚上
1. 把 action 元数据先接成正式出口。起因是前面已经把 `ActionInfo` 往结构化方向改了一半，但 runtime 和 service 还没有真正消费这份数据。先在 `src/entry.mbt` 补了 `action_info_to_json(...)`。
2. 再把 `help INSTANCE_ID --json` 接到同一份 action 元数据上。这样 instance action 不再只有一段帮助文本，也可以按结构化 JSON 暴露。
3. 中间先试过单独加 `actions` 命令。这样功能能通，但很快确认它和 `help INSTANCE_ID` 是平行入口。同一批 action 元数据被两条公开命令重复暴露。这个方向有冗余，随后删掉了。
4. 接着把 runtime 里的重复查询收掉。最开始 `help / exec` 先各自查一遍 instance，再进 `runtime_instance_actions(...)`，等于同一件事做了两次。后面把这层重复去掉，只保留一条实例动作查询主路径。
5. 然后继续收 action 自身的字段。起因是 `ActionInfo.id` 和 `name` 当时完全同值，只是在内部留了两份平行状态。按“删冗余，不留假分层”的口径，把 `ActionSpec.name` 和 `ActionInfo.name` 都改成了 `id`。action 注册、help、exec、JSON 输出随后都只认 `id`。这样 action 内部只剩一份正式标识。
6. 这一步中间带出一个回归。我一度把 instance 标题来源误接到了 action `id`，导致 `host` 的窗口标题从 entry 显示名变成了错误文本。`moon test` 里的 3 条 `host` 用例当场失败。随后把实例标题接回 entry 显示名。这处修完以后，动作标识收缩和界面标题重新分开。
7. 最后按规定重新走 `./scripts/test-all.ps1`。`moon test` 回到 `128/128`。native 回到 `32/32`。browser 仍然只剩仓库里原本那 3 条 `host` 用例失败，报错还是 `root/...` 查询链，和这次 action 元数据去冗余无关。
8. 改完以后专门用 `git diff --stat` 看过行数。当前 action 字段收缩这版是 `18 insertions(+), 19 deletions(-)`。净少 1 行。说明这次确实把平行状态删掉了，没有靠改名字再留一套同义语义。
1. 先重读了仓库 skill 和当前 `host / dom / bridge` 实现。确认 `host` 本体大体已经跟 skill 对齐。真正没对齐的是 listener 语义。skill 已经把 `.stop/.prevent` 这类字符串修饰写法判成禁止项。代码和 bridge 白盒测试里却还残留 `onclick.stop` 这套旧口径。
2. 随后把 listener 的正式协议收回 `DomCmd.Listen`。在 `src/dom.mbt` 里新增了结构化 `ListenSpec / ListenPolicy`。`Listen` 不再只传事件名字字符串。`click / dblclick / pointer / key` 这几类事件的默认 `prevent` 也一起收进了协议生成逻辑。
3. 接着改了 `src/bridge.js`。bridge 现在按 `ListenSpec` 安装监听器。还会保存已挂 listener 句柄。同一节点同一事件再次收到 `Listen` 时，会先拆旧监听，再装新监听。`prevent / stop / capture / passive` 和 `policy` 也都改成按结构化 spec 执行。
4. 然后把 bridge 白盒测试一起收口。`e2e/bridge.test.js` 不再写 `onclick.stop` 这种旧字符串。改成直接走结构化 `LISTEN`。又把测试里的默认 spec 收成了 `listen(...)` helper，避免每条测试重复手写整串默认字段。
5. 在这条基础上补了一组 browser 白盒回归。新增了 `policy` 命中与未命中的行为、重复 `LISTEN` 替换旧配置、`capture` 顺序、`passive` 行为、`code/meta/shift` 组合匹配这些测试。listener 正式协议的关键边界现在都有覆盖。
6. 中间又回头看了 `src/dom.mbt`。发现 listener 属性当前只有静态 `E`。没有像普通属性 `D` 那样的动态更新主路径。也就是说，当时还不能在同一个节点上只重装 listener 而不重建节点。
7. 为了补这条缺口，在 `src/dom.mbt` 里新增了 `Listener` 和 `Prop::DE`。`E` 继续表示默认 spec 的静态 listener。`DE` 表示动态产出 `Listener`，可以在同一节点上重发新的 `Listen(spec)` 并更新 handler。当前先限制动态更新不能切换事件名，避免在还没有 `Unlisten` 协议时留下脏状态。
8. 随后补了一条 `src/dom.test.mbt` 回归。锁住 `DE` 的主路径。要求同一个节点不重建。listener 配置变化后会重新发新的 `Listen` 命令。handler 仍然能正常触发。
9. 这轮 listener 相关改动全部回归过。`moon test` 过到 `129/129`。`native` 过到 `32/32`。browser 现在新增的 bridge/listener 测试也都通过了。
10. 最后又顺着原来那 3 条 `host` browser 失败往下查了一轮。先排掉了 `workspace` 成为 query 屏障的猜测。也确认 `root/entries/0/entry` 这条 path 合同在 `runtime`、`host`、`service repl` 测试里都还在用。
11. 当前更像是 service/browser 运行态下，`host` 的 query 树实际没有按源码预期完整挂出来。这一条还没收成最终修复，留给下一个 agent 继续查。
1. 先继续查 browser 最后那批 `host` 失败。重新对齐 `devlog`、测试和当前实现。确认 `moon test` 与 native 仍然通过，问题集中在 browser 运行态。
2. 随后直接给 browser 运行态打探针。发现页面实际 DOM 里还带着旧的 `background` 节点和旧 class，和当前源码里的 `host` 结构不一致。
3. 顺着测试入口链往下查以后，确认问题在产物准备。`test-all` 当时不会顺手更新 browser 实际启动的 `service.exe`，browser 可能吃到旧的 native 产物。
4. 单独重建 `service` 的 native 可执行文件以后，原来那两条 `root/entries/...` 查询失败立即消失。browser 只剩一条桌面清选中用例还挂着。说明前两条不是 `host` query 合同本身坏了，是 browser 吃旧产物。
5. 再查剩下那条 browser 用例。确认 `host` 挂的是 `onpointerdown`。测试却发了 `kind: 'pointer'`。事件名对不上，所以清选中动作没有真正触发。
6. 后面开始整理测试脚本链。先给 `build-native.ps1` 和 `scripts/test-browser.js` 都接上 `target dir`。把 browser 构建线和 native test 构建线拆成两套产物目录，避免继续共用同一套 `_build`。
7. 在这条基础上把 `test-all` 改成三线并行。`core` 跑 `moon test`。`brow` 先构 browser 用的原生产物，再跑 browser tests。`nati` 先构 test 产物，再跑 native tests。这样 browser 不再等 native test 整条线结束。
8. 并行调度落完以后，又收了一轮执行口径。后台分支改成隐藏窗口启动，但继续保留 stdout。失败也不再提前停掉其他分支，而是等三条线都结束后统一汇总。
9. 接着把日志收回源头。`build-native.ps1` 默认不再打印 timing。普通 native build 成功不再打印。test build-only 成功也不再打印。`artifacts_path` 这类成功信息也一起去掉，只有失败时才会跟着错误输出出现。
10. browser 失败输出也跟着收了一轮。把仓库绝对路径裁成相对路径，避免堆栈里反复出现长串本地路径。堆栈长度也压短了，只保留前几行关键信息。
11. 最后把 `test-all` 的控制台输出整理成 `[core]`、`[nati]`、`[brow]` 三组四字标签。去掉无用的开头提示和冗余失败提示。把最终汇总收成单行 `[test] total ... ok/failed: ...`，不再额外抛一大段 PowerShell 红色异常。
## 04-09 上午
1. 先把 `test-all.ps1` 的主控调度重新量了一遍。补了三条并行线的真实墙钟时间。后面讨论性能时不再只看子脚本内部 timing。
2. 随后确认“收尾很慢”这个判断不成立。真正慢的是并行分支自己。主控脚本自己的收尾主要只有 `WaitForExit`、读日志、删日志，通常是几毫秒到几十毫秒。
3. 接着把 `test-all.ps1` 的日志收集从“子进程输出先落临时文件，再由主控脚本读回”改成了“主控脚本直接通过管道读取 stdout/stderr”。这样去掉了一层文件中转。`core` 这条短分支的额外开销下降最明显。
4. 然后把 `test-all.ps1` 里额外包着的 `pwsh -Command` 拆掉。`core` 直接起 `moon test`。`native` 直接起 `pwsh -File build-native.ps1`。`browser` 改成主控脚本里顺序起两步：先 `build-native.ps1`，再 `node scripts/test-browser.js`。
5. 再把主控脚本等待分支完成的方式从 `HasExited + Start-Sleep 50ms` 改成了 `.NET Process.WaitForExitAsync()`。轮询尾巴又少了一点。
6. 过程中重看了 `build-native.ps1` 的 cleanup。确认前面只收掉了“找正在运行的 service 二进制”那条宽扫描，还留着 `Stop-StaleNativeBuildProcesses(...)` 这条 `Win32_Process` 全表扫。
7. 随后把 `Stop-StaleNativeBuildProcesses(...)` 改成只在 WMI 侧先过滤相关进程名：`moon.exe`、`moonc.exe`、`clang.exe`、`clang-cl.exe`、`link.exe`、`lld-link.exe`。再在这些候选里按 `CommandLine` 过滤目标 `target-dir`。这样不再全表扫所有进程。
8. 这一步中间踩到一次 cleanup 子进程日志文件名冲突。`browser` 和 `native` 两条线同时跑 cleanup 时共用了一对临时日志文件。一条线先删文件，另一条线读日志就会报“文件不存在”。随后把 cleanup 日志文件名改成带 `TargetDir` 的唯一名字，问题消失。
9. 接着把 VS 环境导入逻辑从 `build-native.ps1` 里抽成了单独脚本 `scripts/import-vs-env.ps1`。保留了原来的复用判断和 `CC/PATH` 设置。
10. 单独验证了 `import-vs-env.ps1` 在同一个 `pwsh` 进程里直接调用时，会修改当前 shell 环境。`METAEDITOR_VSDEV_IMPORTED`、`VSCMD_VER`、`CC` 和 LLVM `PATH` 都会就地生效。
11. 再把 `test-all.ps1` 和 `build-native.ps1` 都改成统一规则。先检查当前进程里有没有现成 VS 环境。有就直接复用。没有才调用 `import-vs-env.ps1`。这样单独运行 `build-native.ps1` 仍然正常，`test-all.ps1` 也可以在开头只导一次。
12. 随后专门验证了“同一个 shell 里连续跑两次 `test-all.ps1 -DebugTiming`”的行为。第一次会先导 VS 环境。第二次不会再导。整体总时长明显下降。
13. 最后又在外面先跑过一次 `test-all`、再重启 Codex 的前提下复测。确认这次 Codex 进来的环境已经带上 VS 变量。`test-all.ps1 -DebugTiming` 开头不再出现 `import VS environment`，总时长已经掉到更快的那档。
14. 当前还没处理的事只有 browser 里原本那条 `host clear desktop selection wait timed out after 500ms`。这条失败和这次测试脚本、构建脚本调度优化无关，仍然是已有的 browser host 问题。
1. 先看了 devlog 末尾，确认当时浏览器侧真正剩下的是 `host clear desktop selection` 那条旧失败。
2. 随后对照 `host`、bridge 和 e2e 测试，把事件链重新压了一遍。确认 `host` 实际监听的是 `pointerdown`，而浏览器测试发的是 `pointer`，两边事件名没有对上。
3. 先把 host 的 browser 用例改成发 `pointerdown`。接着发现 bridge 的 `trigger` 主路径本身又不接受显式 `pointerdown`，只认 `pointer / click / dblclick`。
4. 然后把 `src/bridge.js` 的触发分发补齐，让 `pointerdown / pointermove / pointerup` 都走现有 `triggerPointer(...)` 主路径，不再留半套协议。
5. 同一笔里给 bridge 白盒测试补了一条显式 `pointerdown` 回归，锁住这条触发能力。之后全量回归，browser 那条 host 失败消失，`test-all` 重新全绿。
6. 后面用户又说“手动清掉 `_build*` 之后 native 测试出问题”。于是开始单独复现这个现象。
7. 复现时先看到 native `service lifecycle is idempotent` 挂掉。最早的报错是测试里拉起 `service` 子进程时找不到文件。
8. 接着去对照 `test-all.ps1`、`build-native.ps1` 和 `service` 测试代码。确认 native 分支实际使用的是 `_build_test`，而测试里拉起的 `service` 可执行文件原先还带着对旧目录的隐含依赖。
9. 为了把这条依赖拆掉，先改了 native 构建脚本。让跑 `service` 的 native tests 之前，先在当前 `TargetDir` 里补构正式 `service` 二进制，再把实际路径通过 `METAEDITOR_SERVICE_BIN` 传给测试。
10. 同时把 `service` 测试里取二进制路径的入口收成只认 `METAEDITOR_SERVICE_BIN`，不再自己猜目录。
1. 先重新读了 `skill`、`src/dom.mbt`、`src/runtime.mbt`、`src/bridge.js`、`src/mock_dom.mbt` 和样式相关测试。起因是准备处理 style vnode 化。
2. 先把当前模型压清。确认样式分成两条路：节点内联样式走 `SetStyle / RemoveStyle`，模块样式走 `StyleSheet + registered_css + SetCss / RemoveCss`。
3. 继续顺着这条线查生命周期。确认模块样式没有进 `VNode` 树。它靠全局注册表存活。`runtime_render(...)` 和测试 helper 还要额外重放这批样式命令。这个边界和当前 DOM 主路径是分开的。
4. 按“样式也应当是普通 DOM 节点”改了 `src/dom.mbt`。删掉了 `SetCss / RemoveCss` 命令。也删掉了 `registered_css` 和 `emit_registered_css(...)`。样式不再走独立命令协议。
5. 同时补了正式根挂载点。DOM 现在保留 `body` 根。再补一个 `head` 根。bridge 和 mock 都改成能把普通节点挂到 `head`。这样样式挂载点和业务节点不同，但底层仍然是同一套 `Create / Attr / Text / Append / Remove`。
6. 把 `css(...)` 收成样式源。`StyleSheet` 现在保留 `scope`、稳定 `id` 和一份响应式文本。`reset(...)` 改成只更新文本值。样式作用域转换仍然复用现有 `css_scope_block(...)`。没有再加新的样式包装概念。
7. 然后改 runtime。每次 render 时先移除旧的样式节点。再把当前所有模块样式生成为普通 `h("style")` 节点。统一挂到 `head`。业务根还是挂到 `body`。两边都走现有 DOM 树和 flush 主路径。
8. 中间踩到一个 reactive 边界。样式节点里的 `Dyn` 在部分测试路径里没有现成 scope。直接建 effect 会报错。随后给样式节点补了自己的 `react:scope`。把样式文本更新的 ownership 挂到样式宿主节点上。这样样式节点创建、更新、移除都能自洽。
9. 接着改 `src/bridge.js` 和 `src/mock_dom.mbt`。删掉 bridge 里单独维护的 stylesheet map。mock 里也不再留 `browser.css`。样式现在和普通 DOM 节点一样，通过 `head` 里的节点树观察和断言。
10. 再把 DOM 测试整体对齐。原来锁 `SetCss / RemoveCss` 的断言都改成锁 `style` 节点创建、挂到 `head`、文本内容和文本更新。中间还修了一条旧测试假设：样式文本现在经由动态子树更新，不再要求一直复用同一个 text node id；`reset(...)` 之后也要走一次 `flush` 才会看到更新。
11. 最后把 host 的 mock 测试一并改了。原来它直接读 `browser.css` 里的字符串。现在改成直接遍历 mock `head` 下的 `style` 节点文本。这样测试口径和真实运行态一致。
12. 全量回归通过，这次真正落下来的结果是：模块样式已经正式 vnode 化。样式生命周期已经并回 DOM 树主路径。
1. 先调查了 `service/bridge.mbt` 的 handler 模板重复，确认重复主要集中在四块：消息 `from_json`、`unwrap_or(...)`、browser/repl response 包装、`path -> id -> request`。
2. 先做过一版偏保守的收缩。那版把重复搬进几个小 helper，但 `git diff --stat` 还是净增 5 行。随后停掉这条方向，没有保留。
3. 接着把 browser request 的消息结构收成一份 `BridgeRequestMsg`。把 `path/cmd/arg` 并进同一个消息。删掉旧的 `BridgeQueryPathMsg`。把 browser request 的 `query/command` 主路径收短。这一版保留下来了。
4. 然后又把 websocket response 包装收成一条 `respond_request(...)`。删掉了 `respond_repl(...)` 和 `repl_request_result(...)`。`handle_repl_request(...)` 直接收回主路径。`service/bridge.mbt` 这一版净减 18 行，并且测试通过。
5. 中间为了继续压行数，又试过把几组小消息类型和 `from_json` 逻辑改成手写 `json_field/json_string/json_int` helper。虽然 `git diff --stat` 还能继续减行，但可读性明显下降，而且和测试文件里的同名 helper 发生了顶层命名冲突。这条方向随后已经撤销，没有保留。
6. 同时查了 `./scripts/test-all.ps1` 的耗时问题。用 `-DebugTiming` 对比了“无改动”和“只改一个注释”两次运行，确认耗时抬升主要来自相关源码变更后两条分支各自重编译，不是主控脚本自身拖慢。
7. 后面按新的测试拆分方向，把 `native: service lifecycle is idempotent` 从 MoonBit 测试里抽了出来，改成独立脚本 `scripts/test-service-lifecycle.js`。`native` 分支不再为了这一个测试额外构一次 `service.exe`。
8. 再把 `test-all.ps1` 的调度改成先构 `_build_browser` 的 `service.exe`，然后让 `browser` 和 `lifecycle` 两条线并行消费同一份产物。`native` 线只保留 native tests 自己的构建与执行。
9. 调试新的 lifecycle 脚本时，一开始误把“命令进程退出”和“输出管道彻底关闭”绑在一起等，导致 `meta start` 看上去会假超时。后面改成按命令进程 `exit` 收结果，生命周期脚本恢复正常。
10. 还顺手收了测试日志输出。把构建日志里的仓库绝对路径裁成相对路径，把 `~/.moon` 收短，统一了 PowerShell 脚本输出编码，之前构建报错里的乱码已经消失。
11. 这次没有彻底做完的事也要记清。`service/bridge.mbt` 的 handler 模板重复只收了一版，还没有完全压完。剩余的 `from_json + unwrap_or(...)` 重复还在。继续往下压已经开始明显伤可读性，所以这条先停。
12. 另一条还没做的是 `meta start` 的完成语义。现在新的 lifecycle 脚本只验证了 `start/restart/stop` 的黑盒生命周期，能证明 service 能起来、页面能访问，但还不能证明 `meta start` 返回时已经可以立刻开始正式交互。
13. 更具体地说，当前还没有一条测试锁住下面这件事：`meta start` 一结束，立刻执行 `query/trigger/repl/browser bridge` 这一类正式交互就必须成功。这个缺口还在。
14. 如果后面继续做，应该再补一条单独的“start ready”集成测试，专门测 `meta start` 返回后的即时交互语义。现在的 lifecycle 脚本和 browser tests 都还没有覆盖到这个点。
## 04-09 下午
1. 先重读了 `devlog` 和 `service/cli.mbt`、`service/bridge.mbt`、`src/runtime.mbt`、`src/dom.mbt`。目的是重新压清 `meta start` 的完成语义。
2. 确认旧实现里 `start` 只等 HTTP `status` 可用。默认 `host-1` 实例已经 boot。`root` 这类 `ui-id path` 还没 ready。
3. 继续顺着 `runtime_render(...)` 往下查。确认 service 的首次 render 被挂在 browser hello 后面。没有 browser 连接时，rendered tree 根本没建出来。
4. 随后做了黑盒复现。`start --silent` 返回后，`status` 会显示 `browser: waiting` 和 `roots: host-1`。这时 `query root` 会失败，`sync` 也会报 `browser is not connected`。
5. 这一步把边界拆清了。实例树已经有了。可 query 的 rendered tree 还没有。
6. 后面按“service 自己先把 mock dom 用起来”这条方向改了一版。先给 runtime 补了原始 `DomCmd` 回调。
7. 再让 service 启动时把 `DomCmd` 同步进 mock dom。`init_app(...)` 里也直接先做一次 `runtime_render(...)`。
8. 同一版里把 browser 未连接时的 `query/sync` 改成先走 mock dom。这样 `start` 返回后的语义被推到 “headless query ready”。
9. 这版当时已经全量回归过。`./scripts/test-all.ps1` 是全绿。说明主路径先接通了。
10. 再往后开始收冗余。先把内部 request 从直接复用 browser `Json` 形状，改成独立的 typed request。
11. 接着把 `trigger` 那条很长的平铺参数收成了 `Trigger(Int, TriggerKind)`。想先把内部语义收清，再处理 transport。
12. 这一段中间几版都能回归通过。说明 mock 分支和 browser 分支共用内部 request 这件事本身是成立的。
13. 然后开始继续压 bridge 里的手工 `Json` 搬运。想把 request 消息收成 `derive(FromJson/ToJson)` 驱动，少写字段 helper。
14. 为了不再靠猜，单独在系统临时目录做了最小 MoonBit 实验。确认 `struct derive(ToJson, FromJson)` 会生成普通 object。`Option` 里的 `None` 会直接省略字段。
15. 同一步也量了 `enum derive(ToJson, FromJson)`。确认带 payload 的 variant 会变成数组，无 payload 的 variant 会变成字符串。这种形状不适合直接当当前 websocket object 协议。
16. 随后把 bridge request 消息收成了 `struct derive(FromJson)`。一度也试过直接用 `ToJson` 出口。那版很快证明不对。
17. 具体表现是 `service/repl.test.mbt` 里两条 browser request 观察测试开始挂。`request_browser_path(...)` 会在等 browser response 时被取消。
18. 于是把 `ToJson` 又撤回，改成 `FromJson` 加手写 `msg_to_json(...)`。想保住 object 形状，同时减少字段搬运。
19. 当前还没收干净。工作区现在只剩两个改动文件，`service/bridge.mbt` 和 `src/mock_dom.mbt`。
20. 当前全量回归结果也已经重新量过。`core`、`browser`、`lifecycle` 都过了。native 只剩 2 条失败。
21. 两条失败的报错都一样，都是 `ServiceError("Cancelled")`。这说明最后卡住的是 bridge request 编码形状或 request/response 对接。
22. 当前可以确定不是 `start` 的 headless ready 主路径坏了。现在真正没收住的是 browser websocket request 这条兼容链。
1. 先重读了最近几段 devlog、skill 和 `service/src` 里和 JSON 相关的实现。目标先收成“把 MoonBit 这层 JSON 处理模型讲清楚”，不再直接顺手糊代码。
2. 随后把项目里 JSON 相关主路径逐段拆开看了一遍。确认现在混着边界 `Json`、内部 typed 语义、手写字段读取和手写 object 编码。问题不在高层业务语义，主要卡在 service / bridge / cli 这一层的协议边界。
3. 先按这个判断补了文档。给 `skill` 新增了 JSON 规范 reference。
4. 同一笔里又在 `skill/SKILL.md` 里补了很短的入口规则。先把口径压成：`Json` 默认只当边界协议格式，内部语义先写成正常类型，边界收到 `Json` 后尽快解回 typed 结构。
5. 然后先收了最明显的一处重复实现。把 service 里两套重复的 `json_field / json_string / json_int / json_bool` helper 合成一处共享实现，放进 `service/base.mbt`。
6. 这样 `service/cli.mbt` 和 `service/repl.test.mbt` 都改成复用同一条 JSON 字段读取主路径。先把最散的字段读取 helper 收成一套。
7. 回归时又把工作区里原本没收干净的一条 bridge request 问题压出来了。当前 `service -> browser` 这条 `bridge:request` 在编码时把节点 `id` 丢了，导致 native 的两条 browser request 测试被取消。
8. 随后把 `id` 补回协议编码里。`./scripts/test-all.ps1` 回到全绿。
9. 在这个基础上，又单独拿 `service/bridge.mbt` 做了一轮更系统的收束。先把它改成“入站 DTO + 出站 DTO + 单点 codec”的样子，专门演示了一版更标准的协议边界写法。
10. 这样先把 `FromJson`、显式 `*_to_json(...)` 和业务逻辑之间的边界拉开。方便单独看清 MoonBit 这层 JSON 协议到底该怎么组织。
11. 后面继续讨论时，把真正不满的点重新讲准了。问题不只是“边界层 JSON 很乱”，更是“明明已经有同形状的类型，却又抄了一份新的类型壳”。
12. 这一步把判断口径改正了。不再抽象谈 DTO，直接收回到“同形状的东西只该有一份类型”。
13. 按这个原则，随后又把 `service/bridge.mbt` 继续收了一版。删掉了后来补出来的 `BridgeUiRequestMsg`。
14. 现在这条线已经收成：唯一请求语义还是 `UiRequest / UiTriggerKind`。bridge 只负责 `UiRequest <-> Json` 的编解码，不再平行保留第二份同形状类型。
15. 这一步之后又全量回归了一次。`./scripts/test-all.ps1` 全绿，说明“删掉重复边界类型，只保留一份正式请求类型”这条方向已经接上，没有把 service / native / browser 任一条链打坏。
16. 最后按这次争论里讲清的原则，把 skill 再补硬了一条。同形状的东西只保留一份类型。
17. 已有类型能承载时先复用。如果只是少编解码能力，先补 codec。只有协议形状和现有类型真的不同，才允许新建边界类型。这样后面再处理 JSON 边界层时，就不再只是“Json 是边界格式”这种大方向，也把“禁止重复抄同形状类型”写成了明确规则。
1. 先重读了最近几段 devlog、skill 和 `service/src` 里跟 JSON 相关的实现。把问题重新压成“协议 shape 分散”，不再只泛泛谈 `Json` 用得乱。
2. 先沿 `service/bridge.mbt`、`service/cli.mbt`、`service/http.mbt`、`src/mock_dom.mbt`、`src/bridge.js` 把 query / trigger / REPL / 控制口这几条 JSON 主路径重新过了一遍。确认真正乱的是同一协议在多处各写一份 shape。
3. 先做了一版较小修正。把远程命令的双重 JSON 字符串化拆掉了。控制口和 REPL 不再把 `--json` 结果先转成字符串再包回 `result`。同时把 `trigger` 的 CLI 文本格式化改成读取当前真实字段。这版 `./scripts/test-all.ps1` 全绿。
4. 然后我误判了下一步方向。一度把 query / trigger 的结果往 `src` 里提成 `UiNodeSnapshot / UiQueryResult / UiTriggerResult / UiResponse`，想让 `mock / bridge / cli` 围着一份 typed 结果转。这版代码最后也能回归通过。
5. 后面继续对照代码和测试，确认这条判断不对。当前 query / trigger result 主要还是边界协议结果，还没有深入 `runtime` 内部形成长期流动的正式语义。此时硬提一层结果类型，收益不够，反而会把代码层数拉厚。
6. 继续追问时，又把另一个危险信号压出来了。`service/repl.test.mbt` 里有一条 browser trigger 测试手写了很弱的 fake response，只回 `{ ok: true }`。我一度为了接住它，在生产代码里补了 fallback。这个方向随后被判定为错误。测试不该反向定义正式协议。
7. 这轮讨论最后把原则重新讲清了：协议要钉死，必须先有类型；类型要长在协议所属那一层；不能在外围随手再抄一层壳。对 query / trigger 这条线，真正该先收的是边界协议 shape，而不是继续给结果多包一层内部类型。
8. 为了把这套判断留成后续可执行的规则，补写了 `doc/json-protocol-standard.md`。文档把“内部正式语义 / 边界协议类型 / 传输编码格式”三层拆开，又列了当前协议清单、硬规则、问题分类和整改顺序，专门用来约束后面 agent 处理 JSON 和协议问题时不要再走偏。
9. 同一笔里还补了 `skill/SKILL.md` 的按需读取说明。现在已经明确写出什么情况下该读 `references/dom-query.md`、`references/dom.md`、`references/json.md`，避免后面的 agent 只停在 `SKILL.md`，再漏掉 JSON 规范。
1. 先按要求只读了 devlog 末尾和仓库里的 JSON 文档、skill。先确认这次要检查的是刚加的 JSON 标准文档口径。没有动代码。
2. 随后去查了 MoonBit 官方关于 `Json`、`derive(ToJson/FromJson)` 的推荐用法。重点看了 derive 的定位，以及它是否适合直接承担正式协议 shape。
3. 对照后确认，现有文档大方向是对的。`Json` 作为边界格式、内部先用 typed 结构、同一协议只保留一份 shape 和一套 codec，这些判断都成立。
4. 同时也确认文档里有一处口径偏重了。原来把 `derive(FromJson)` 写得太像默认推荐做法。MoonBit 官方更偏向把 derive 用在调试、人类可读存储、inspect 或简单边界数据上。正式长期协议如果要精确控制字段、`Option`、enum 形状和错误语义，更适合手写 trait 或集中 codec。
5. 继续顺着这个判断把问题再压细了一层。确认文档里还缺两条 caveat。一条是 `Option` 的默认 JSON 编码规则。另一条是 enum derive 的风格参数不适合拿来钉正式协议 object shape。
6. 在和用户对齐“正式协议层是不是自己写 trait 更好”以后，按最小补丁只改了两份文档：`skill/references/json.md` 和 `doc/json-protocol-standard.md`。
7. `skill/references/json.md` 里，把 `derive(FromJson)` 收成只推荐给简单边界 DTO。又补上了前提条件：shape 要简单，要接受 MoonBit 默认 JSON 规则；如果协议要长期稳定，优先手写 `FromJson` / `ToJson` trait 或集中 codec。
8. `doc/json-protocol-standard.md` 里，把 derive 新增成一类明确风险源。又补了一条硬规则：正式长期协议如果要钉死 object shape、可选字段语义、enum 形状或报错行为，优先手写 trait 或集中 codec，不把协议稳定性押在 derive 默认规则上。
9. 这次没有改生产代码，也没有跑测试。实际落下来的结果只有 JSON 规范文档口径收严，并和 MoonBit 官方推荐更对齐。
1. 先重读了新写的 JSON 协议标准和当前实现。把这次目标收成真正的代码清理，不再停在抽象讨论。
2. 先处理了浏览器事件这条假 JSON 协议。原来 `EventData` 走的是管道串，名字却叫 `from_json`，语义和命名不一致。现在已改成正式 JSON object，`src/bridge.js` 直接发结构化事件数据，service 侧按 `EventData` 解码。
3. 中间一度给 `EventData` 手写了 `ToJson / FromJson`。很快确认这类平铺对象不值得手写，只会增加样板。随后改回 `derive(ToJson, FromJson)`，同时把测试同步到固定字段 shape，`prevent` 也收成正式字段。
4. 接着把 `UiNodeSnapshot / UiQueryResult / UiTriggerResult / UiResponse` 的正式 codec 接到类型自己身上。这样 query / trigger / response 结果不再散在 `mock / service / 测试` 各写各的。
5. 结果类型的字段解码一开始写得很吵。后面把重复读取收成公共 helper，最终定名为 `decode_field`，放进了 `src/base.mbt`，不再把通用 JSON 字段解码塞在局部结果类型旁边。
6. 同一轮里把 `service/repl.test.mbt` 里两条关键 fake response 改成复用正式 codec，不再手写弱 shape，让测试回到“复用正式协议”的主路径。
7. 之后又处理了测试层的 codec 断言。先试过单向 decode 断言，后面按当前口径删掉，统一改成 `assert_json_roundtrip(...)`。`EventData` 相关测试也改成 roundtrip，不再单独铺大段 JSON 输入字面量。
8. 整个过程里每次改动后都按规定跑了测试，中间只遇到一次 lifecycle 端口占用的偶发失败，重跑后恢复全绿。当前实际落下来的结果是：浏览器事件数据正式改成 JSON object；`EventData` 已回到 derive；query / trigger / response 结果类型已经有正式 codec；关键弱 fake shape 已删除；测试辅助层新增了 roundtrip 断言工具。
9. 这次还没做的事情也一并记下。`service/bridge.mbt` 里的 `build_browser_request(...)` 还在用 `json_string/json_int/json_bool` 手拆 request 字段，这条 request 入站协议还没挂到正式类型自己的 codec 上。
10. `service/cli.mbt` 里的 `format_query_text(...)` 和 `format_trigger_text(...)` 还在直接按 JSON 字段做文本格式化，还没先解回正式类型。
11. websocket 外层消息的出站 codec 还主要是手写 object builder，像 `bridge:request / bridge:response / repl:*` 这层还没统一到更正式的消息类型接口。
12. `UiNodeSnapshot` 现在还是手写 `ToJson / FromJson`。它本身是平铺对象，后面还可以继续判断是否和 `EventData` 一样收回 derive。
13. `service/repl.test.mbt` 里 websocket 消息外壳还有不少手写 `Json::object(...)`。当前只是关键结果 shape 已经不再手写弱协议，这层外壳还没继续收。
1. 继续收 JSON 整理。先把剩余问题压清。确认还没收完的是两类：`service/bridge.mbt` 里的 browser request 入站协议还在手拆字段；`src/mock_dom.mbt` 里那批 `ui_*_from_json / ui_*_to_json` helper 只是 trait 转手壳。
2. 先给 `UiRequest` 和 `UiTriggerKind` 补正式 codec。然后把 browser request 的出站编码改成直接复用正式类型。`service/bridge.mbt` 不再手拼 `action/kind/text/key/...` 这一套字段。
3. 同一笔里把 CLI 的 `query / trigger` 文本格式化也收回正式类型。先把 JSON 解成 `UiQueryResult / UiTriggerResult`。再输出文本。这样 CLI 不再直接按裸 JSON 字段拼字符串。
4. 接着补了两条 roundtrip 测试。专门锁 `UiRequest` 的 key payload 和 drag_to payload。目的是先把正式 shape 钉住，避免后面继续整理时又退回弱协议。
5. 然后按“类型自己有 trait 就直接用 trait”继续收。把 `src/mock_dom.mbt` 里那批 `ui_query_result_from_json / ui_trigger_result_from_json / ui_request_from_json` 和对应 `to_json` helper 全删了。现有调用点全部改成直接 `@json.from_json(...)` 或 `.to_json()`。
6. 再把 `service/bridge.mbt` 里的 `build_browser_request(...)` 收回 typed 主路径。新增一层 path request 类型。边界先解到 typed request。再转内部 `UiRequest`。这条线不再手读 `json_string / json_int / json_bool`。
7. 同一步把 websocket 外层消息也一起整理成类型主路径。`bridge:request`、`bridge:response`、`bridge:hello`、`bridge:hello_ack`、`bridge:pong`、`bridge:rejected`、`repl:request` 这几类消息都补了正式类型和 codec。控制口的 `Command / ResponseMsg` 也改成直接走类型。
8. 中间有两次编译回归。第一次是 CLI 文本格式化里把 MoonBit 的 `match / catch` 写错了。第二次是 `respond_request(...)` 改签名以后，`repl:response` 那组调用点漏改。两次都按最小补丁修回，没有继续加新层。
9. 最后把 `service/repl.test.mbt` 和 `service/service.test.mbt` 里原来手写 websocket / browser fake message 的几处 object 字面量也对齐到了正式消息类型。测试不再保留弱协议壳。
1. 又按一段新的 JSON 审核回头核了一遍当前实现。重点重看了 `src/dom.mbt`、`src/bridge.js`、`service/bridge.mbt`。确认前面已经收掉的几条不用再记。真正还没做干净的只剩两类尾巴。
2. 第一类尾巴在 DOM batch 兼容层。`service / browser` 当前主路径已经直接传 `Json` 命令数组，不再走“单条命令先 stringify，再在浏览器里逐条 `JSON.parse`”那条旧路。
3. 但旧兼容壳还在。`src/dom.mbt` 里还保留了 `dom_cmd_to_json(...)`。`src/bridge.js` 的 `applyDomBatch(...)` 也还保留了“元素是字符串时再 `JSON.parse` 一次”的分支。
4. 这说明主路径的重复解析开销已经不再发生。代码里仍然留着旧格式入口。协议口径还没有彻底删到只剩一条。
5. 第二类尾巴在 service 边界 decode。核心结果类型和 request 类型现在大多已经能直接 `@json.from_json(...)`。但 websocket 外层消息分发和少量边界 codec 还没有完全收进正式类型。
6. 具体看，`service/bridge.mbt` 里还留着 `json_type(...)` 按 `type` 字段手分发消息。`UiPathRequest::from_json` 和 `UiPathTriggerKind::from_json` 里也还在用 `json_string / json_bool / json_int` 手读字段。
7. 这部分说明问题已经从“整条 JSON 主路径都散”收成了“边界层还有少量手写 decode”。类型安全比前面好很多，但还没完全统一到单点 codec。
8. 这次没有继续改代码。只把当前剩余问题重新钉清了：后面如果继续收 JSON，优先该做的是删掉 DOM batch 的字符串兼容分支，再把 websocket 外层消息继续收成正式消息类型，去掉 `json_type(...)` 这种手判入口。
1. 先重读了 devlog 末尾，以及这次直接相关的 `src/dom.mbt`、`src/bridge.js`、`service/bridge.mbt`。目的是把前一轮 JSON 审核里还成立的问题重新压清，不再按旧结论继续推。
2. 对照当前实现后确认，真正还没收完的只剩两类尾巴。第一类是 DOM batch 还保留着旧字符串命令兼容入口。第二类是 websocket 外层消息还在靠 `type` 字段手分发，边界层还留着一部分手写 decode。
3. 先处理 DOM batch 这条。删掉了 `src/dom.mbt` 里的 `dom_cmd_to_json(...)`。这样 DOM 命令只保留 `Json` 值主路径，不再保留旧的单条字符串化出口。
4. 同时把 `src/dom_helper.mbt` 里的相关断言改成直接比较 `dom_cmd_to_value(...).stringify()`。测试辅助继续锁同一份正式编码结果，不再依赖已经删掉的旧 helper。
5. 接着改了 `src/bridge.js` 的 `applyDomBatch(...)`。删掉了 `typeof d === 'string' ? JSON.parse(d) : d` 这条兼容分支。browser 端现在只接受正式 `Json` 命令数组。
6. 然后开始收 service websocket 外层消息。把 browser websocket 和 repl websocket 的入站消息分别收成 `BridgeIncomingMsg` 和 `ReplIncomingMsg` 两个正式类型。
7. 这一步把原来 `json_type(...)` 那套按 `type` 字段手判分发的入口删掉了。消息处理改成先 `@json.from_json(...)` 解成正式消息，再按 variant 分支处理。
8. 同时把几类外层消息从宽松 `Option` 字段收紧成正式必填字段。涉及 browser request、browser response、bridge ping、bridge hello 和 repl request。这样边界 decode 不再默认吞空值。
9. 又把发给 browser 的 request 外壳命名收了一次。`BridgeUiRequestMsg` 改成了 `BridgeRequestOutMsg`。只保留“browser request 外层消息”这一层明确语义。
10. 原来 `UiPathTriggerKind::from_json` 和 `UiPathRequest::from_json` 那两段手写字段读取已经没有继续保留的理由，也一起删掉了。service 里不再留这条旧 decode 入口。
11. 中间第一次跑全量测试时带出了两类编译问题。一类是我新抽的消息 type helper 把 `JsonPath` 类型接错了。另一类是 `service/service.test.mbt` 里两条 `respond_pong(...)` 白盒测试还在传旧的裸 object。
12. 随后按最小补丁修回。消息 type 读取改回直接写在 `FromJson` 实现里。`respond_pong(...)` 的两条测试也改成传正式 `BridgePingMsg` 结构。
13. 最后重新跑了 `./scripts/test-all.ps1`。`core 129/129`。`native 31/31`。`browser 14/14`。`lifecycle ok`。全量回归通过。
14. 这次最终收掉的是前面 JSON 审核里还剩的真实尾巴。DOM batch 的字符串兼容壳已经删除。browser 端不再接受旧字符串命令。service websocket 外层消息已经收成正式类型分发。`json_type(...)` 和那两段旧的路径请求手写 decode 也已经删掉。
## 04-09 晚上
1. 把 DOM/property 协议一起收了一次。起因是 `SetProp` 还没进正式协议，`RemoveAttr / RemoveStyle` 也还在走独立删除命令。先把目标钉成“只保留 `Attr / Style / Prop` 三条主命令，空值统一进同一条协议”。
2. 一开始先补了 `SetProp`，又把 attr/style 删除改成了空值语义。但这版还没把 `SetProp` 的空值一起接进去，三条命令的口径还没真正统一。
3. 随后继续把命令名字和排布收正。把原来的 `SetStyle / SetProp` 改成并排的 `Attr / Style / Prop`，不再留一半是名词、一半是动词的混搭协议名。
4. 中间我一度走偏。先把 `Json` 直接塞进了 `Prop`，又补了 `J / DJ`，还为了接测试写了 `match_json` 和一串新的 `emit_*` helper。后面对照项目的 JSON 规范以后，确认这条方向是错的。`Json` 不能倒灌进内部 DOM 语义层。
5. 然后按讨论把内部类型重新收正。`Prop` 改成 `Empty / S / D / E`。把所有动态统一回 `D(() -> Prop)`。`DE` 整个删掉。这样 DOM 构造输入重新只保留一层动态入口，不再平行留动态 listener 壳。
6. 在这个基础上把三条 DOM 命令的值语义收成一份。新增了 `DomValue` 作为 `Attr / Style / Prop` 的统一值类型。`DomValue::Empty` 在协议编码时统一转成 `null`。这样三条命令终于都能显式表达空值，`SetProp` 也不再缺 `null` 入口。
7. bridge 和 mock 随后一起对齐这套新口径。attr 收到空值时删 attribute。style 收到空值时删 style property。prop 收到空值时把 property 设成 `null`。browser、mock、runtime 三边现在走的是同一套空值语义。
8. 前面我为了接这套值语义，一度又拆出了 `emit_attr_* / emit_style_* / emit_prop_*` 这一串 helper。用户当场指出这层又把代码越拆越碎。随后把这些 helper 全删掉了，属性分发重新压回 `render_element(...)` 主路径，直接发 `emit_current(Attr / Style / Prop / Listen)`。
9. DOM 测试、bridge 白盒和 mock 侧断言也一起改到新协议上。中间专门临时造过一条测试失败，确认 `core` 线的失败输出形状，再立刻改回。最后重新走全量，协议和测试都已经接稳。
10. `test-all.ps1` 这次也顺手收了一轮。browser 共用的 native build 现在会带 `-Silent`，不再重复报 warning。失败时那坨超长的 `moonc.exe build-package ...` 命令行也被主控脚本过滤掉了。现在编译失败只看 `nati`，测试失败只看 `core`。
11. 最后把现有 warning 也清掉了。删了已经不用的 `bind_listener`，又把 `mock_dom.mbt` 里 deprecated 的 `flatten()` 改成了推荐写法。`./scripts/test-all.ps1` 最终重新跑过，全绿。
12. 这次功能收完以后，还顺手暴露出一个后续问题。MoonBit 现在测试失败的信息本质上还是裸异常栈，断言 helper 给的上下文太少。这个问题暂时没继续改，但值得后面单开一笔，专门整理项目里的测试断言写法和失败信息质量。
1. 继续收 `DomCmd` 最小集合。把正式协议改成只保留 `Create / Insert / Remove / Attr / Style / Prop / Listen` 七条命令。`Text` 命令删除。`Append / InsertBefore` 也删除。
2. 这一步的起因是前面几轮已经把属性协议收得比较整齐，但文本和插入仍然留着平行命令。协议表面上已经变短了一些，真正高频的命令形状还没有统一。
3. 随后给 `Create` 补了初始值能力。文本节点创建时不再额外发一条 `Text`。直接在 `Create` 里带初始文本。bridge 统一按目标节点的 `textContent` 解释这个值。
4. 同时把插入命令收成一条 `Insert`。它现在带 `ref` 和 `after`。追加、插到前面、插到后面三种形状都走这一条主路径。没有再保留平行插入命令。
5. 同一笔里把 `dom_cmd_*` 的编号和 JSON 编码顺序一起重排成和新集合一致。先把语义收正，再把编码顺序跟上，避免协议名义上收了，数组 tag 还留着旧历史包袱。
6. 然后把 `src/dom.mbt`、`src/runtime.mbt`、`src/bridge.js`、`src/mock_dom.mbt`、`src/dom_helper.mbt` 和相关测试一起对齐到新协议。中间先撞到一次 `Insert` 的测试匹配层类型不对，原因是 `ref` 最开始写成了固定 `Int`。后来改回和其他 id 一样走泛型，测试 helper 才重新接稳。
7. 这条协议收完以后，又继续压高频编码。`Create` 改成把 `ns` 放最后。默认 html namespace 不再编码。初始值为空时也不再传。`Insert` 也改成省略默认的 `ref=0` 和 `after=true`。
8. 这一步的起因是新的统一协议虽然已经接稳，但 JSON 数组里还留着不少重复默认值。最明显的是 html namespace 长串 URI 和尾部 `null`。继续留着会把高频命令重新撑胖。
9. 现在常见 html 元素创建已经能短到 `[0,id,tag]`。文本节点创建能短到 `[0,id,"",text]`。追加也能短到 `[1,parent,child]`。只在真的需要时才继续带 `value / ns / ref / after`。
10. 为了接这层编码压缩，又补了 browser 端的变长数组解码。namespace 也改成短码，当前用 `0/1/2` 表示 `html/svg/math`。这一笔只收了高频的 `Create / Insert`，其余命令先不继续压。
11. 在这条基础上继续把 `query` 的读取能力补全。正式结果类型新增了 `Attr / Prop`。browser、mock、service CLI 三边都接上了 `query PATH attr KEY` 和 `query PATH prop KEY`。
12. 这一步的起因是前面已经把 DOM 正式命令收到了 `Attr / Style / Prop`，但 `query` 对外仍然只到 `node / text / style`。读和写的正式能力不对齐。
13. 当前 `attr` 按 attribute 字符串返回。`prop` 当前按 property 取值后转成字符串返回。缺值统一先回空串。先把正式能力接通，没有额外发明第二套值协议。
14. browser harness 中间还带出一条旧白名单问题。`scripts/test-browser.js` 的 query spec 只放行了 `node / text / style`。新增的 `attr` browser 用例先挂掉。随后把 harness 的白名单一起补上，browser 回归恢复正常。
15. 最后重新跑了 `./scripts/test-all.ps1`。`core 136/136`。`native 31/31`。`browser 14/14`。`lifecycle ok`。全量通过。
16. 同时把 `prop` 未来的设计边界也单独讨论清楚了。当前 `query prop` 先统一返回字符串，适合快速把正式能力补齐。
17. 但这层不该被误当成最终形状。后面最可能继续补的是 `Bool`、数值类型，以及 `null` 和空串的区分。像 `checked`、`disabled`、`scrollTop`、`selectionStart` 这类 property，长期一直按字符串读会开始别扭。
18. 当前先停在“最小正式能力已接通”。如果后面继续做，应该围着正式值类型继续收，不再回到散的字符串约定。
1. 先重新讨论了 query 根、`component ui-id` 和挂载点的关系。先把实例树根、query 域根、DOM 挂载点这三层拆开，确认之前容易混的是层级语义，不只是某个 path 名字。
2. 随后把两条设计原则钉清。第一，`Dyn / Null / Arr` 一律不承诺稳定根节点，查到什么就是什么。第二，实例 id 应该能作为 query path 的第一段入口，用来直接跳进实例内部 UI。
3. 中间我先走偏了一版，把实例入口硬塞进 `dom`，给节点加了 `aliases`，又把宿主传播逻辑搅复杂，写出了编译器已经在警告的无意义状态重写。这版虽然一度把功能接通，但设计已经明显偏离。
4. 用户随后把方向扳正。明确指出实例入口问题应该收成“实例挂载点”，不该倒灌进 DOM 的 `ui-id:scope` 和宿主传播语义；同时也明确要求删掉 `root` 这种临时根名。
5. 按这个判断重做后，改成了“实例挂载点 + 第一段实例匹配”的主路径：query 只在第一段尝试匹配实例 id，命中后从该实例当前挂载点继续走现有 query 解析；host 根上的 `root` 也一起删掉，相关测试路径统一改成 `host-1/...` 这类实例前缀口径。
6. 这一步里又暴露出一个更底层的疑点。我起初为了少改代码，借用了现有 `pending_mounts` 去启动实例挂载点。用户接着追问得很准：问题已经不只是“实例挂载点要不要用 pending”，而是 `pending_mounts` 这整个机制本身就不是用户认可的设计。
7. 于是这次把怀疑也明确记下来：`pending_mounts` 现在承担的是一套“先占位、后启动”的延后挂载机制，生命周期不直观，顶层和子树路径也不统一，已经开始反过来污染新的实例挂载点实现。当前功能虽然已经接通，但这条旧机制本身值得单开继续审查，判断它到底是不是历史实现绕出来的隐状态。
8. browser host 用例在这次对齐实例前缀后带出一条样式断言问题。原来的 e2e 会检查桌面项选中和清选中的背景样式，但在当前 browser harness 下，相关 `style background/background-color` 查询返回空串，原因这次没有继续查透。
9. 为了先把实例前缀这条主路径收住，我把那条 browser e2e 临时改成了更弱的交互可达性检查，没有继续锁样式值。这件事本身也要记清，因为它不是问题已经解决，而是为了让这次改动先落地，暂时把 browser 侧的样式断言退掉了。
10. 最后先把现阶段结果收住：实例前缀 query 已经可用，`root` 临时根名已经删掉，相关 runtime / service / browser 测试路径都已对齐，`./scripts/test-all.ps1` 已经重新全绿。
11. 同时明确留下两条后续问题。第一，实例挂载点实现还借着 `pending_mounts` 起步，设计还没完全收正。第二，browser host 那条被降级的样式断言还没恢复，为什么 harness 里会读到空样式，这次也还没有查透。
## 04-10 上午
1. 先回看了 devlog 末尾 800 行。把“还没做完”“临时降级”“后续单开”的条目单独筛了一遍。先确认当前最实的尾项有两条。一条是 `pending_mounts` 设计还没收正。一条是 `browser host` 那条样式断言被降级以后还没恢复。
2. 接着去对了上一个 commit 附近的 browser 改动。重点只看 `e2e/host.test.js`。确认第三条 `host` 用例确实被从“检查桌面选中样式是否保持和清除”降成了“只检查交互路径还能走通”。
3. 然后把 browser harness、`src/bridge.js`、`src/mock_dom.mbt`、service query 路径串起来看了一遍。先把一个容易混的点排掉了。browser e2e 里的 `path query` 主路径一直都是 `scripts/test-browser.js -> window.mbt_bridge.query(path, ...) -> service -> src.runtime_resolve_query(...) -> browser id`。不是直接在 browser test 里查 `mock_dom`。
4. 为了确认旧断言为什么会挂，把 `host` 的第三条 browser 用例按当前实例前缀口径恢复成真实样式断言。然后单跑了 `e2e/host.test.js`。这一步把失败稳定复现出来了。卡点就在选中态 `background-color` 的等待超时。
5. 随后在测试里临时加了一次性观测。只读运行态数据。不留调试文件。观测结果说明：`query(path)` 还能解到一个 `VNodeID`。`queryById(id)` 也还能看到带 inline style 的节点对象。真实页面 `document.body` 里却只剩 `#app-info`。业务节点没有挂进文档。`getComputedStyle(...)` 因此读成空串。
6. 按这个现象继续查 browser bridge 的 DOM batch 落地实现。最后把根因压到 `src/bridge.js` 的 `DOM_CMD.INSERT`。browser 端默认假定 `ref` 一定已经属于当前 `parent`。实例挂载那条路径会出现 `child` 和 anchor 到达顺序特殊的场景。此时 `ref.parentNode !== parent`。浏览器会在 `insertBefore(...)` 上出错。后续节点虽然已经创建并写了属性样式，却没有真正插回文档。
7. 然后按最小补丁修了 `src/bridge.js` 的 `Insert` 落地语义。当 `ref` 不存在，或者 `ref.parentNode !== parent` 时，直接退回 append。修完以后把 `e2e/host.test.js` 的第三条用例恢复成真实样式断言。不再保留那个“只测可达性”的降级版本。
8. 修完后分别回归了 `e2e/host.test.js` 和 `e2e/bridge.test.js`。然后按项目规定跑了 `./scripts/test-all.ps1`。三条都重新通过。说明这次问题不在 query 模型本身。问题在 browser 端 `DomCmd.Insert` 的执行边界。
9. 之后又按提醒去和 `dev/1` 对了 `e2e/host.test.js`。确认这次没有把文件整体回退成 `dev/1` 老版本。差异主要只在 query 路径已经切到当前分支的实例前缀口径 `host-1/...`。第三条测试的断言语义本身已经恢复。没有继续被弱化。
10. 最后把 query 模型重新讲清了一遍。CLI 和 browser test 都是先在 `src` 里把 `path` 解成当前 `VNodeID`。browser 已连接时，`style / attr / prop / text` 这些值来自 browser bridge 持有的真实 DOM 节点。browser 未连接时，才会回退到 `mock_dom`。这次问题属于后半段 DOM 落地坏了。不是前半段 path 解析坏了。
11. 还没做完的测试也单独记清。`e2e/bridge.test.js` 还没专门锁 `DomCmd.Insert` 的几种真实落地语义。尤其是 `ref` 插前、插后，以及 `ref.parentNode !== parent` 这种边界。
12. 还缺一条 service 到 browser 再到真实 DOM 的集成测试。这条测试应该直接锁“render 后 `query style` 读到的是已挂入文档的真实节点值”。
13. 还缺一条正式 CLI/control path 的测试。这条测试应该明确锁 browser connected 时 `query style / attr / prop` 走真实浏览器节点。browser 未连接时才回退 headless 或 `mock_dom` 路径。
14. 还缺一条 browser bridge 白盒测试。这条测试要显式防回归“managed node 还在 map 里，但已经脱离真实文档”的状态。
1. 先按前面确定的三条测试缺口补了第一版测试。
2. 在 `e2e/bridge.test.js` 里补了 `DomCmd.Insert` 的边界测试。把插前、插后、`ref.parentNode !== parent` 三种落地语义都锁住了。
3. 同一版里又补了一条“`query style` 读真实 DOM 值”的 browser 集成测试。当时先挂在了 `e2e/host.test.js`。
4. 还在 `service/repl.test.mbt` 里补了 control path 的两条测试。一条测 browser 已连接时 `query attr/style/prop` 走 browser websocket。另一条测 browser 未连接时回到 headless/mock。
5. 后面重新对齐测试分组。把“真实 DOM style 查询”从 `e2e/host.test.js` 挪到了 `e2e/bridge.test.js`。这条能力现在直接挂在 `bridge` 这组里。
6. 接着开始收 `service/repl.test.mbt` 里的 JSON 写法。先把为了搬运 3 个查询结果临时加出来的 `ControlQueryResults` 删除，没有继续保留这层测试专用类型。
7. 然后把结果搬运改成普通三元组。这样测试里只保留正式结果值，没有再引入额外概念。
8. 再补了一个泛型 `expect_json[T](json, message)`。专门把边界 `Json` 解成 typed 结果，用来收掉重复的 `try { @json.from_json(...) } catch { ... }`。
9. 这一笔没有再加任何特定协议、特定字段或特定类型的 JSON helper。只保留了泛型 decode 原语。
10. 中间第一次回归失败，是把 `Json` 直接赋给 `UiQueryResult`。MoonBit 不接受这种写法。随后补回显式 decode，测试重新接上。
11. 第二次回归失败，是新泛型 helper 的函数签名没把 `fail(...)` 的 raise 语义写对。把泛型函数签名改正以后，编译恢复正常。
12. 这次最终收下来的结果是：三条测试缺口都已经补上，而且测试落点和 JSON 写法也一起收正了。
1. 先补查了 MoonBit 官方错误处理和测试文档。把 `fail`、`raise`、`panic`、`try?` 的语义边界重新压清。确认 `try?` 只能把 `raise` 转成 `Result`，对 `panic` 没用。
2. 又对了本地 `mooncake` 依赖和仓库现有测试写法。确认生态里“预期失败”测试主流还是走 `raise + try?`。`panic` 主要留给不变量和专门的 panic 测试。
3. 接着把讨论重点收成“测试 assert helper 该怎么写，失败信息该怎么变清楚”。没有继续沿着 `expect_*` helper 展开。
4. 直接拿仓库里的真实例子做分析。重点看了 `src/dom_helper.mbt` 里的 `assert_cmds`、`assert_has_cmd`、`assert_no_cmd`、`assert_cmd_json`。也看了 `src/storage.test.mbt` 里的对象断言 helper。
5. 这一步把一个关键判断讲清了。测试 helper 里最该优先用的是 `fail(...)`。原因是它本质上走 `raise Failure`。它能保留调用位置。也不需要为了测试失败再新建很多错误类型。
6. 同时把 `fail` 和 `raise`、`panic`、`abort` 的边界讲清了。`raise` 适合正式业务错误。`fail` 适合测试断言失败。`panic` 只该留给内部不变量。`abort` 对复杂测试断言来说信息太粗。
7. 然后按仓库现有 MoonBit 测试做了一次失败入口盘点。只看测试代码里的 `abort(...)`、`panic()`、`fail(...)` 和 `catch { _ => panic() }` 这几类入口。
8. 盘点结果说明当前最突出的点在两套 helper。`src/storage.test.mbt` 里 `abort(...)` 很密。消息大多只有 `root`、`child`、`name` 这类短标签。`src/dom_helper.mbt` 里的结构断言则大量直接 `panic()`，挂了以后没有“第几条命令错了”“实际命令是什么”“整批命令是什么”这些上下文。
9. 另外又把一批会吞原始错误的写法单独记出来。`src/reactive.test.mbt`、`src/mock_dom.test.mbt`、`service/service.test.mbt` 里还有不少 `catch { _ => panic() }`。这类写法会把原始错误直接吃掉，日志里只剩一个 `panic`。
10. 最后没有直接改测试代码。先把这次结论整理成一份测试错误改造报告，写进 `doc/test-error-improvement-report.md`。报告里按“现状 / 典型坏例子 / 优先级 / 建议改法”展开，主张先改 helper，再收重复的 `catch { _ => panic() }`。
11. 这次还没继续做的事也记清。报告只把方向和优先级钉住了，还没有真正把 `src/storage.test.mbt` 和 `src/dom_helper.mbt` 的 helper 改成带 `label + actual` 的 `fail(...)` 输出。后面如果继续做，优先应该先收这两套 helper。
1. 先按仓库规则只读了 `devlog` 末尾、`skill/SKILL.md` 和仓库目录，确认这次工作只做测试覆盖审计，不改代码。
2. 先读了 `scripts/test-all.ps1`，把当前正式测试入口钉清。确认全量测试由四条线组成：`core` 的 `moon test`、`native` 分支、`browser` e2e 分支、`lifecycle` 脚本。
3. 随后直接跑了全量测试，确认当前基线稳定。结果是 `core 136/136`、`native 33/33`、`browser 17/17`、`lifecycle ok`。
4. 同时跑了 `scripts/count-core-code.ps1`，把当前核心代码规模量了一遍。结果是 `prod_total=7944`、`test_total=3727`，其中 `src` 测试 3016 行，`service` 测试 711 行。
5. 接着把 MoonBit 测试、browser e2e 和 lifecycle 脚本顺着目录读完。重点看了各测试文件到底锁了什么主路径，不只看有没有测试文件。
6. 读完以后先把覆盖结构压清。核心内核里，`reactive`、`dom`、`mock_dom`、`storage` 覆盖很重；`runtime`、`entry`、`host` 也有直接测试；`service/repl`、`service/service` 加上 browser e2e，已经把 `service -> runtime -> browser bridge` 的主链路接通。
7. 然后按生产文件反推测试空白面，专门看哪些生产文件有同层测试，哪些主要靠上层集成测试顺带覆盖。确认只有 9 组有直接同名测试，其余像 `bridge.js`、`demo_editor`、`command`、`service/bridge`、`service/cli`、`service/http` 这些都没有直接同层测试文件。
8. 在这个基础上给了测试覆盖结论。整体判断是：核心内核覆盖高，跨层主路径覆盖中高，CLI/HTTP/文件系统边角覆盖中低，浏览器 websocket 生命周期异常分支覆盖中低。
9. 强覆盖区主要记了几块。`reactive` 已经锁住 `cel/effect/scope/cleanup/untracked/mutate/dedup`；`dom` 已经覆盖 `Create/Insert/Remove/Attr/Style/Prop/Listen`、`h_map` 稳定性、动态节点和 CSS 作用域；`mock_dom` 已经覆盖 query scope、list scope、动态结构切换、事件分发和 effect ownership；`storage` 已经覆盖嵌套 cel、共享引用、自环、孤儿快照和 gc。
10. `host` 和 browser/service 主链也单独记清了。`src/host.test.mbt` 加上 `e2e/host.test.js` 已经锁到窗口、topbar、选中态和实例前缀 query；`service/repl.test.mbt`、`service/service.test.mbt`、`e2e/bridge.test.js` 已经把 query、trigger、control path、真实 DOM query 和 bridge 事件主路径测通。
11. 主要缺口也按风险列了出来。第一批是 `service/cli.mbt`、`service/bridge.mbt`、`src/bridge.js`，当前主路径能跑，但异常分支、断连重连、错误 JSON shape、pending request 清理、CLI 参数边界这些还缺显式保护。
12. 第二批缺口是 `service/http.mbt`、`src/demo_editor.mbt`、`service/fs.mbt`、`service/session.mbt`、`src/command.mbt`、`service/stub.c`。其中 `http` 的 `serve_file/404/content_type/respond_*` 基本没直接测，`demo_editor` 也还只锁了 mount 和 add，`toggle/remove/empty state/Persist 默认值` 这批业务语义还没真正钉住。
13. 这份覆盖审计报告先在聊天里交付了，没有动代码。也明确写了边界：仓库当前没有接入 line/branch coverage 工具，所以这次是人工覆盖审计，不是精确百分比。
14. 随后又按要求去查了 MoonBit 官方 coverage 的现状。重点查的是有没有内建 coverage、覆盖口径是什么、怎么出报告、和当前仓库测试体系怎么对齐。
15. 查到的结论是：MoonBit 现在已经有内建 coverage。可以用 `moon test --enable-coverage` 打开覆盖率采样，当前口径是 branch coverage，不是传统的 line coverage。
16. 报告命令也查清了。测试跑完以后可以用 `moon coverage report` 出报告，也可以走 `moon coverage analyze` 这条封装命令；支持 `summary`、`html`、`cobertura`、`coveralls` 等格式，coverage 产物会落在 target 目录下，也支持 `moon coverage clean` 和 `/// @coverage.skip`。
17. 继续把这个信息和当前仓库的正式测试入口对了一遍。确认 MoonBit coverage 只能直接覆盖 `moon test` 这条线，所以本仓库里能直接吃到它的是 `core` 那条 MoonBit 测试；`browser` 的 JS e2e、`lifecycle` 脚本和 harness 自己的 JS 逻辑，都不会自动进入这套 coverage 统计。
18. 最后把适用边界和最小落地方式也一起记下了。对当前仓库来说，MoonBit coverage 能产出的是 MoonBit 包代码覆盖报告，不是整个仓库含 JS harness 的统一覆盖报告；最直接的试法是先跑 `moon test --enable-coverage`，再跑 `moon coverage report -f html`。
1. 重新调查了 `pending_mounts`。先对照 `devlog` 和 `src/dom.mbt`。确认真正卡住的点不是 `Dyn` 的 anchor 机制，而是 `Lazy` 里直接做挂载。`Dyn` 自己的主路径本来已经成立。
2. 接着去对照了 `IntentDoc/dev/ui.js`。把那边 lazy 的实际机制拆清。它返回的是可直接挂载的 fragment。更新时围着 anchor 和真实父节点工作。没有单独的第二阶段启动。
3. 先试过把 `pending_mounts` 挂回节点本身，改成 `mount_start`。这一版全量测试能过。但问题没有消失。只是把全局等待表挪成了节点回调。设计仍然是两段式。
4. 又试过加 `Mounted` 变体，把挂载逻辑塞进新的 `Child` 分支。测试也能过。但概念明显变多。`h_map_dyn` 也没有回到和普通 `Dyn` 同层的主路径。这条方向随后判定为错误。
5. 再往下试过把 fragment 语义正式化，引入 `VFrag`，同时给它加 `mount`。这一版同样能过测试。但仍然保留了“先给 fragment，再补启动”的第二阶段。问题只是换了一个壳。
6. 随后把问题继续压细。直接把 `Lazy` 改成吃 `mount_id` 和 `owner_id`。这一步把真实矛盾讲清了。`owner_id` 很快证明只是噪音。它可以删。真正留不掉的是 `mount_id`。因为 `h_map_dyn` 和 `mount_instance` 还在 `Lazy` 里直接做挂载。
7. 中间又短暂试过 `mounted_parent_id` 和 `on_mount`。这两样也都被证明是错的。前者是镜像状态。后者是第二阶段启动回调。和更早的 `mount_start`、`VFrag.mount` 属于同一类补丁。随后没有保留。
8. 这轮最后真正留下来的结论只有一条。只要 `h_map_dyn` 和 `mount_instance` 继续在 `Lazy` 里直接做挂载，系统就会反复长出额外参数、镜像状态或启动回调。问题不在名字。问题在机制位置。
9. 给下一个 agent 的真实有效方案已经明确。先从 `h_map_dyn` 下手。把它改成“基于现有 `Dyn` anchor 主路径的缓存 + list scope 语法糖”。不要在 `Lazy` 内直接依赖 `mount_id`。这一步成立以后，再用同一模型改 `mount_instance`。
10. 这条方案的目标也已经钉清。不是换一种启动回调。也不是换一种父节点镜像状态。目标是把 `pending_mounts`、`mount_start`、`Mounted`、`VFrag.mount`、`Lazy` 额外参数、`mounted_parent_id`、`on_mount` 这类补丁全部删掉。`Lazy` 只保留纯节点 / fragment 构造。挂载动作回到现有 `Dyn` 主路径。
## 04-10 下午 晚上
1. 先把 `src/dom.mbt` 整个清空了。决定不再沿旧实现补洞。先把最小核心模型重新立起来。
2. 先把 `Child` 收成 `Null / Lazy / Str / Int / Arr / Dyn`。同时确认 `Lazy` 直接返回节点数组。不再保留 `VFrag` 这层包装。
3. 随后把节点结构改成 `Node { id, parent, kind }` 加 `NodeKind { Text, Element }`。文本节点和元素节点的字段拆开了。不再用一份平铺大 struct 混放 `tag/ns/text/children`。
4. 这一步里反复对照了 `IntentDoc/dev/ui.js`。重新确认最小主路径该围着 `child / append / moddom / fnchild` 这组来长。不再围着旧的 `realize_*` 壳继续改。
5. 接着先把 `child` 立成纯平铺函数。再把 `append` 单独拿出来。开始把“产出节点”和“挂载节点”拆成两步。
6. 中间一度沿着旧思路把 `parent` 留成了 `Int?`。也试过加一张 `id -> node` 表，让 `Dyn` 更新时能找回父节点。
7. 继续对照 `IntentDoc` 以后，确认这条路不对。`fnchild` 那边靠的是 `anchor.parentNode`。既然 `children` 已经直接持有 `Node`，`parent` 也应该先尝试直接持有 `Node?`。
8. 随后把 `parent` 改成了 `Node?`。同时删掉了那套节点表辅助逻辑。又把 `fnchild` 改名成 `dyn_child`，让动态子树更新更贴近 `IntentDoc` 的语义。
9. 同一步还把短代码块往一行压。所有代码块仍然保留 `{}`。先把文件读起来的噪音压低。
10. 之后把 `moddom` 单独拎出来整理。先让它围着 `anchor` 做 `old -> next` 替换。不再直接粗暴清空整段 children。
11. 接着把命令协议从 `dom.mbt` 里拆出去。单独新建了 `src/domcmd.mbt`。开始收 `DomCmd` 相关定义。
12. 一开始 `domcmd.mbt` 只写了很薄的类型壳。随后又按现有项目真实调用面补上了根节点语义、命令 tag、`DomValue` 和 `ToJson`。
13. 在这一步里重新确认了 namespace 不该放进 `domcmd`。它应该继续留在 `dom` 模型里。命令编码时再引用。
14. 之后又把命令 tag 和根节点语义从裸常量改成 enum。再接到 `base.mbt` 里新加的 `ToInt` trait 上。
15. `DomCmd` 的 JSON 编码也从手搓数组改成直接用 tuple `.to_json()`。`Attr / Style / Prop / Remove / Insert` 这些分支都压短了。
16. 中间实际跑了一次 `moon check`。先把 `src/dom.mbt` 自己那几处明显不成立的类型问题压掉。然后继续改 `src/domcmd.mbt`。
17. `domcmd.mbt` 里随后又修了一次 `CmdTag` 和 `DomCmd` 构造器重名造成的歧义。改成了显式 `CmdTag::...` 调用。
18. 当前实际完成的是：`dom.mbt` 已经有了新的最小节点模型和动态子树骨架，`domcmd.mbt` 也已经拆出来并接上了最小命令协议与 JSON 编码。
19. 当前还没做完的地方也要记清。`dom.mbt` 还没有接回旧项目依赖的属性系统、事件系统、query、list、instance、css 和 bridge 主路径。`domcmd.mbt` 虽然类型与编码已经有轮廓，但和 `dom.mbt`、`mock_dom`、`runtime` 这些旧调用面还没有真正重新接起来。
## 04-11 上午
1. 先重看了 `IntentDoc/dev/ui.js` 里和 DOM 最小主路径直接相关的四段实现：`child`、`fnchild`、`moddom`、`h.map`。这次不再顺着仓库里残留接口自己补模型，先把对照基线钉回原实现。
2. 随后直接用 `moon check -p src` 验了当前 `dom.mbt`。把 `h_map` 这块的实际编译问题先压清：`map` 回调参数不对，`Map` 需要 `Hash` 约束，tuple 解构方向写错，`remove` 也还没定义。
3. 在这个基础上先收了一版 `h_map / h_map_dyn`。中间一度为了绕开类型问题写成了数组桶缓存。后面对照 `IntentDoc` 以后确认，这层只是把 `Map` 语义换了个壳，方向不对，没有保留。
4. 然后把 `h_map` 收回成和 `IntentDoc` 一样的 `Map[key -> Array[entry]]` 结构。重复 key 继续走队列复用。索引 getter 继续挂在 entry 上。`HMapBucket` 这层平行概念已经删掉。
5. 同一笔里把 `moddom` 开始接回正式删除路径。补了 `remove(node)`。`moddom` 先算 `old` 相对 `next` 的差集，再删掉已经不在新结果里的节点。删除逻辑不再塞在 `h_map` 里。
6. 期间又顺手把两处数组噪音收了一次。`h_map(items, ...)` 改成直接用内建 `mapi`。`Arr(items)` 改成走 `base` 里的通用 `flat_map(...)`。`[anchor] + old.val` 也替掉了原来那段先建数组再 push 的写法。
7. 之后又把 `remove` 里的局部递归函数写法收正。改成局部 `fn`，让当前这段先能成立，不再留前面那个类型就不对的局部 lambda 写法。
8. 最后又对照了一次 `IntentDoc` 和当前 `dom.mbt`。确认方向已经拉回来了，但还有三件事没有做完，需要明确记上。
9. 第一件没做完的是 `Dyn` 初始化阶段现在还会把 `f()` 跑两次。`h_map_dyn` 的 `source()` 也会跟着跑两次。这个还没对齐到 `IntentDoc` 里 `watch(w, ...)` 那条单次初始化主路径。
10. 第二件没做完的是 `remove(node)` 现在只有树结构删除，还没有接 reactive 清理。被删节点下面的 effect 和 scope 还不会随着删除停掉。这一层和 `IntentDoc` 的 `deepstop` 语义还差关键能力。
11. 第三件没做完的是 `moddom` 虽然已经开始删旧节点，但后半段仍然是清空 `children` 再整段重建数组。它还不是 `IntentDoc` 那种围着锚点做原地插拔和移动的 patch 主路径。
12. 这三件里前两件风险更高。它们会直接影响 `h_map` 的 source 次数、删除后 effect 会不会继续活着，以及后面 list/query 接回时节点 identity 能不能站稳。
1. 先把节点清理模型重新收了。否掉了把 scope、幂等状态和额外壳塞进节点的厚设计，重新确认节点删除真正要消费的是 cleanup。
2. 随后把锚点语义单独拿出来。把节点形态收成 `Text / Anchor / Element`，让 `Anchor` 正式承担动态占位和 cleanup ownership，普通 `Text` 继续保持纯内容节点。
3. 在这个基础上改了 `Dyn`。动态片段现在显式创建 `Anchor`，不再拿文本节点临时冒充锚点。`Dyn` 自己的 scope stop 和当前展开子树的清理都挂到 `Anchor` 的 cleanup 上。
4. 接着开始收 `moddom`。中间先写偏了一次，还抽了 `find_node_index` 这种局部 helper。后面对照 `IntentDoc` 确认这条方向不对，因为原实现根本没有这层索引 helper，出现它本身就说明实现还停在数组下标思维。
5. 然后把 `moddom` 重写成锚点游标模型。现在先删 `old` 里已经不在 `next` 的节点，再从 `anchor` 的当前位置往后顺序推进，只在目标节点不在当前插槽时做摘除和插回，不再清空整个 children 数组重建。
6. 期间还重新确认了 namespace 那段。最后保持了当前写法，没有继续改这块。
7. 之后又专门回看了 `Dyn` 里的 `old` 保存方式。原先一度误判成必须用 `Ref`，后面对照当前代码和编译情况确认，这里直接用 `mut old` 就成立，之前那条判断不对。
8. 这次还顺手暴露出一个协作问题。为了判断 `mut old`，一度直接跑了整包 `moon check -p src`，把和当前点无关的大量旧接口报错一起读进来了。后面这类局部验证要先过滤到当前文件，再看结果，不再直接吞整包输出。
9. `moddom` 虽然已经回到锚点顺序 patch 的主路径，底层容器仍然是 `Array[Node]`，实现层面还是在用数组游标模拟 `IntentDoc` 的 sibling pointer 语义，复杂度层级接近。
## 04-11 下午
1. 先围着 `mod_dom` 和 `IntentDoc` 的原意做了一轮复杂度审核。中间把工作区里旧版和新版 `mod_dom` 都对照过，确认旧版更像整段重建，新版开始靠近锚点 patch，但还没真正贴到原意。
2. 接着尝试把 `mod_dom` 收成更线性的 patch。最早一版先去掉了明显的双重扫描，但我自己复审后发现仍然保留了整段重组父 children 的思路，和目标不一致。
3. 后面又试过把 patch 过程收成局部链表视图。一开始写成了多张 `Map` 拼出来的临时链表，虽然方向开始靠近 `IntentDoc`，但实现层概念太碎，代码明显变脏。
4. 继续讨论以后，把问题压到更核心的一点：这条 patch 真正依赖的是 sibling 关系，不该在数组上绕太多弯。中间也明确讨论了数组和链表的差别，确认如果后面要接 `domcmd` 的插入命令，链表语义会更自然。
5. 随后用户指出前面那套链表状态写得太厚，要求只围着 `nextSibling` 去思考，不要再发明一堆平行结构。我又试了 next-only 的写法，但很快发现自己还是在补多余状态，没把实现压干净。
6. 然后用户直接在代码里写了 `mod_dom` 的伪代码。核心口径被重新钉住：`mod_dom` 先删掉 `old` 里不在 `next` 的节点，再按锚点和插入原语去排 `next`。这一步把前面几轮越写越绕的实现重新拉回来了。
7. 中间又专门对齐了一次锚点位置。先短暂走到了尾锚点，再重新确认要和 `IntentDoc` 一致，最终回到前锚点语义。对应地，`Dyn` 的展开结果也收回成前锚点写法。
8. 在这个基础上，把 DOM 操作原语从局部数组 helper 收成了节点方法。先补了节点级的删除和插入动作，让 `mod_dom` 自己只保留“删旧 + 依次插入”的主逻辑，不再在函数里摊开底层数组操作。
9. 之后继续往“更像真实 DOM”收。把 `Node`、`NodeKind`、`DomNs` 和相关类型从 `dom` 挪到了 `domcmd`，同时开始让节点自己维护 `parent / prev / next` 这种兄弟链关系，准备把插入和删除真正压到节点原语里。
10. 在这一步里还一度把元素节点收成了位置参数很多的 `Element(...)` 形状。用户随后指出这层读起来太糟，于是继续把元素节点拆成了单独的结构体，让“兄弟关系”和“元素自己的子链边界”分开表达。
11. 最后又专门讨论了一次真实浏览器的内部模型。查到的结论是：浏览器规范暴露的是 live 的 `childNodes / children` 接口，内部主结构更接近父子和兄弟链接，`children` 更像一层视图，不必急着在当前实现里同步保留。于是决定当前先不把 `children` 加回来，后面真的有需求再做。
1. 先继续收了 `domcmd` 到 `dom` 的属性主路径。把 `attr / style / prop` 从字符串前缀判断往节点 API 上压，开始尝试让元素属性统一走 `Node` 侧方法。
2. 中间很快发现最早那版写得太散。`dom.mbt` 里临时长了 `style_key / prop_key / apply_attr / apply_attrs` 这类 helper。随后按讨论把这些 helper 全删掉，属性分发重新压回元素创建分支。
3. 随后又把属性设计重新讨论成 typed 方案。一开始我提了 `AttrValue`，因为和 `DomValue` 完全同形被否掉。接着改成直接复用 `DomValue`，再继续讨论动态属性应该挂在哪一层。
4. 对动态属性的结论是：不该放进 `DomValue`。动态是绑定关系，不是值语义。随后把方向收成 `AttrKind + AttrPair`，也就是 `Static / Dynamic` 在属性层分开，`DomValue` 继续只表示最终值。
5. 在这个基础上，用户写了一版更顺的属性匹配方案。`style`、`style:`、`prop:` 的分流统一收进 MoonBit 的字符串模式匹配和 alias pattern。调查后确认 MoonBit 确实支持这类前缀模式和 `pattern as name` 绑定，去掉了我前面那套重复 guard 的写法。
6. 然后继续把属性应用主路径从 `dom.mbt` 搬回 `Node`。新增了 `AttrKind / AttrPair` 以后，把原来本地的 `set_attr(...)` 过渡逻辑收掉，改成元素节点直接 `node.set(attr)`。
7. 这一步里又专门把 `Node::set(...)` 收成“先判 `self.kind`，再判 attr”的形状，避免在每个属性分支里重复 match 节点类型。`dom.mbt` 里本地重复定义的 `AttrKind / AttrPair / set_attr` 也一起删掉，避免再留一份平行概念。
8. 同时还顺手收了 `Dyn`。删掉了它自己新建 scope 的做法，改成 effect 直接挂在当前作用域下，再把 stop 挂到 anchor cleanup。后面又把未挂载时那段把 `parent / prev / next` 清空的分支删掉，只保留有父节点时的 patch 主路径。
9. 再往下开始碰 reactive 的错误模型。先判断 `effect` 现在硬写成 `raise` 不太对，直觉上更像是应该跟回调一起多态。于是先尝试把 `effect` 和 `Eff.run` 改成 `raise?`。
10. 这一步后面没有成立。按要求跑了 `moon check -p src`，再只看 `reactive.mbt` 相关报错。确认问题不只是在调用点，而是 MoonBit 当前不支持把 `raise?` 用在 `Eff.run` 这种字段位置，同时局部 `fn() raise? { ... }` 这类写法本身也不对。
11. 随后又重新去查了 MoonBit 官方语法。确认 `raise?` 主要是函数签名层的 error polymorphism，不是像 `[T]` 那样的一等类型参数；局部闭包这类地方更该依赖 arrow function 的 effect inference，不该手写 `fn() raise? { ... }`。
12. 在这个基础上，又继续把方向压清到 reactive 核心：如果真要把“可能报错”的行为存进结构或队列里，`raise?` 解决不了值层表示，最后还是得考虑 `Result`。同时还暴露出另一个核心结构问题：`Eff.subs` 现在是 `Array[Ref[Array[Ref[Eff]]]]`，这层反向依赖表示本身也值得单开审。
## 04-11 晚上
1. 先把这轮 DOM 工作的目标重新钉清。不再按旧 API 补洞。改成围着能力和内部模型重做。
2. 用户先把 `domcmd` 里的属性系统往新方向推进。开始把字符串值、JS 值、动态属性这些概念拆开。准备把约束前移到类型层。
3. 中间围着属性类型来回试了几版表达。我这边先给过一版不合适的拆法。用户随后把类型收回到更贴当前设计的形状，把 `StrValue / JsValue / Prop[T] / AttrPair` 这条线立了起来。
4. 接着用户继续把 `Node::insert(...)` 收到更贴 `DomCmd.Insert` 语义的实现。先明确目标节点缺省时就是追加。再把插前、插后都压到同一条结构语义里。
5. 这一步里又来回收了几次实现写法。先去掉多余分支。再把过度机械的 `match Some/None` 收成更直接的条件写法，让 `insert` 更短也更顺。
6. 随后又回头审了 `detach / remove`。中间暴露出 `remove` 少了摘链这一步。用户指出以后按最小补丁修回。也顺手把 `detach` 收成内部辅助，不再把它当公开原语设计。
7. 然后继续改 `Node::set(...)`。先把动态属性统一成“先求值，再回到静态分支”的主路径。避免每个分支各挂一份重复逻辑。
8. 同一步里又把 `listener` 的位置重新讲清。最终确认不单独保留一条并行事件通道。而是统一并进 `prop` 这条值语义和命令语义里。
9. 接着把 `react:scope` 的边界重新钉住。用户明确指出它在当前设计里只属于元素语义。旧测试里如果要求 `Null` 也承载 scope，那就是测试口径已经落后于新设计。
10. 按这个判断继续改了元素结构。把 reactive scope handle 正式挂进元素节点。再把 stop 函数放进 `clrs`，让元素删除时能把对应 scope 一起停掉。
11. 然后又把 `DomCmd` 的 `Create / Insert` 从位置参数收成结构体 payload，并补了带默认值的构造入口。目的主要是把“默认值语义”从参数位置里抽出来，让命令形状更自然。
12. 之后专门重新调查了 `DomState` 的真实使用面。确认它当前主要被 runtime 和测试壳消费。本质已经是旧 DOM runtime 容器，后面大概率要跟 runtime 一起重做。
13. 同时也重新判断了 `mock_dom` 的地位。随着新 `Node` 系统已经能直接表达结构、属性和状态，`mock_dom` 继续存在的必要性明显下降，后面很可能会删。
14. 最后专门做了一次临时基准。比较“节点常驻三个空 Map”和“三个字段按需建 Map”的成本。结果支持把 `xmls / styles / props` 一起做成稀疏字段，不再只挑其中一两个。
15. `moon bench --release` 可以直接跑 package 里的 benchmark。用法和测试很接近，适合做这种局部结构对比。
16. benchmark 文件可以直接写在 package 里。形状就是 `test "bench xxx" (b: @bench.T) { ... }`。然后在 `b.bench(() => { ... })` 里放循环。
17. 如果要避免 benchmark 被优化掉，可以用 `b.keep(value)` 把结果挂住。别用不存在的包级 `keep`。
18. 这次临时基准是放到系统临时目录建最小模块跑的。跑完就删，没有往仓库里留文件。
19. 这类基准很适合回答“空结构常驻值不值”“按需分配是不是更划算”这种局部问题。但它只说明当前工具链和当前数据形状下的成本，不直接替代真实业务路径的整体性能结论。
## 04-12 上午
1. 先把 `runtime` 的外壳一路压短，只保留最小核心类型。先后删掉了 `run / render / roots / set_roots / entry` 这些没有新增语义的小壳。
2. 接着把 `entry` 的定义收回 `runtime` 文件里，确认当前这条线先只保留一个文件承载核心概念，不再分散在两个文件里。
3. 然后继续把构造入口收成类型方法。`new_runtime` 改成了 `Runtime::new`，`entry(...)` 改成了 `Entry::new`，把顶层构造 helper 再压掉一层。
4. 随后重新判断了 `runtime` 里真正需要的对象。确认放进 `runtime` 的不该是 `Entry` 定义本身，而是 `Instance`。于是补了最小的 `Instance { id, entry }`，把 `Runtime.root` 改成 `Instance`。
5. 在这个基础上先接了一版“创建即挂载”。最开始是 `runtime` 自己直接调 `child(...)` 把 `root.entry.view()` 落成节点，并把根节点记进 `Runtime.node`。
6. 接着围着 `DomState` 的位置继续收。确认 `DomState` 这层隐式上下文太烦，用户 API 不该碰它，但 `dom` 内部 realize 链可以显式吃它。于是把 `get_id / text / anchor / child / append` 这一条内部路径改成显式传 `DomState`，`h / h_map / h_map_dyn` 这些用户 API 保持不变。
7. 然后又把 `DomState` 进一步收成 `Dom`，构造入口改成 `Dom::new()`，不再留独立的 `dom_state()` helper。
8. 再往下把挂载语义从 `runtime` 收回 `Dom`。先删掉了 `dom` 里那层 `run / use_dom / mount` 之类中间 helper，又让 `Runtime::new(...)` 直接走 `Dom`。
9. 在这个过程中又补回了 `Dom` 自己的默认宿主。当前 `Dom` 已经开始持有 `head / body` 两个默认根，并新增了 `Dom::mount(...)`，`Runtime::new(...)` 也改成直接 `dom.mount(Body, root.entry.view())`。
10. 最后又回头重新核对了 devlog 里旧的“挂载点”讨论，确认之前真正踩过的坑不在名字本身，而在把挂载动作塞进了 `Lazy / pending_mounts / mount_start / Mounted / on_mount` 这类两段式机制里。
11. 当前虽然先把默认宿主收成了 `head/body`，但“挂载点”本身还不能等同于这两个根，后面还得继续把“默认宿主”和“通用挂载点”这两层概念拆开。
1. 先在 `codegen` 里补了一个最小独立流程。目的很直接。验证 `moonrun` 跑 wasm 时能不能直接读本地 JSON，再生成一份简单的 MoonBit 文本。
2. 第一版先按仓库里的普通包形状搭起来。补了示例 `input.json`、主程序和包配置。主程序只做一条主路径：`read_file_to_string -> json.parse -> from_json -> 生成字符串 -> 写文件`。
3. 第一次运行先撞到 `main` 不能直接调用 `raise` 函数。随后按最小补丁把主逻辑收进 `run() -> Unit raise`。再让 `main` 显式 `catch`。
4. 修完以后先把 `wasm` 这条路跑通了。标准输出已经能看到生成出来的 MoonBit 文本。结果文件也已经能写回 `codegen` 目录。
5. 接着又把目标改成 `wasm-gc`。要求是无参数运行就默认走这个后端。于是把 `codegen` 从根模块里单独拎成小模块，给它自己的 `moon.mod.json`，并把 `preferred-target` 设成 `wasm-gc`。
6. 中间先试过把源码挪到 `tool` 子目录。想把输入输出文件留在模块根，把源码和生成产物隔开。这样可以避免生成文件下次又被当成源码一起编译。
7. 这版很快暴露出结构问题。`source` 配置会影响 package 搜索。结果是构建能落到 `wasm-gc`，但 `moon -C codegen run .` 这条无参数主入口起不来。这条结构随后没有保留。
8. 最后把结构收回成更直接的方案。`codegen` 根目录继续作为主包入口。`preferred-target = wasm-gc` 保留。这样无参数运行恢复正常。
9. 同时把生成文件名从 `generated.mbt` 改成了 `generated.mbt.txt`。原因也很直接。避免下次运行时 MoonBit 把生成产物当成源码重新编译。
10. 最后重新做了实际验证。`moon -C codegen run .` 无参数默认已经走到 `wasm-gc`。`input.json -> typed decode -> 生成 MoonBit 文本 -> 写到 generated.mbt.txt` 这条流程也仍然是通的。
1. 先继续收了 `Node` 的构造入口。把节点统一到 `Node::new(dom, data)`。`text`、`anchor` 都改成走这条入口。元素节点也补成了独立的 `element(dom, tag, ns)`。这样节点创建入口终于收成了一套，不再在各处手搓同形字面量。
2. 接着继续收元素节点里的稀疏字段。`xmls`、`styles`、`props`、`clrs` 都改成可空。默认不建空 `Map` 和空数组。第一次真正使用时再创建。这样把常驻空结构先省掉了。
3. 中间围着这些可空字段的写法反复收了几版。先试过把 map 的创建和写回拆成泛型 helper。调用点还是显得绕。随后又试过把选择哪张 map 也抽出去。用户指出这层读起来还是不顺。
4. 最后把这块收回到 `Node::set(...)` 局部。改成 `xmls()`、`stys()`、`prps()`、`clrs()` 这几个就地 helper。每个 helper 只做一件事：已有就拿现成的，没有就创建并写回。动态属性绑定也继续直接挂在 `clrs()` 上。当前这版读起来更贴当前文件的局部语义。
5. 同一笔里把挂载点也重新收了一次。`Dom` 不再常驻假 `head/body` 节点。挂载位置改成单独的 `MountPoint` 标记。`mount` 也取消了“只能挂一个节点”的限制，直接允许挂整段 `Frag`。
6. 在这个基础上开始继续接 `domcmd`。先把目标压成最小形状：`Dom` 只负责分配 id 和发命令，`Node` 的各个操作自己决定何时发 `DomCmd`。不额外再包 runtime 专用转发层。
7. 随后写了一版正式接线。`Dom` 新增了 `emit`。`Node::new / insert / remove / set` 都开始显式吃 `dom`，并在内部发 `Create / Insert / Remove / Attr / Style / Prop`。`Dom::mount(...)` 也接到了这条路径上。挂到 `Node(parent)` 时走节点插入。挂到 `Head/Body` 时直接发根插入命令。
8. `Runtime::new(...)` 也补了一版最小批处理收集。初始化时先把本次构建发出的 `DomCmd` 收进数组，再统一交给 `on_batch`。这样 runtime 总算开始真正消费 `Dom` 发出的命令流，不再只是把 `Dom` 建出来挂在那里。
9. 这一步里还顺手把一条边界重新讲清。中间我一度把 `ui-id` 当成也要进 `domcmd`。用户当场纠正了这点。当前判断已经改正：`ui-id` 自己不该进 DOM 命令，真正进 DOM 的应该是它派生出来的 class。
10. 最后又专门讨论了 `Create / Insert` 能不能合并。当前结论先停在：它们经常连着出现，编码上后面可以继续压；但语义层暂时仍然建议分开，不急着把协议改成一条复合命令。
## 04-12 下午
1. 先把 `reactive` 继续往最小模型压，确认 `Cel / Scope` 留下，`effect` 这一层单开重做。
2. 中间围着 `ClearHooks` 和调度语义继续收。把 `Anchor`、`ElementNode`、`Eff`、`Scope` 都统一到 `HasClrs` 这条 cleanup 主路径上。
3. 随后把 `effect` 的字段重新讨论清楚。先短暂保留过 `deps` 之类旧味道很重的结构，后面确认反向解绑本质上就是 `onclr`，把 `deps` 直接删掉。
4. 然后按旧版 `reactive` 和 `IntentDoc/dev/reactive.js` 重新对齐作用模型。确认 `effect` 不该默认新建 `scope`，它只应该挂到当前 `scope` 上；`scope` 才是 ownership 宿主。
5. 接着把 `Result` 这条线来回试了一轮。最开始把 `Result` 放进 `Eff.f` 和 `effect(...)`，但调用面基本都在 `Err(_) => ()`，代码明显变长，收益很弱。
6. 后面把边界重新钉住：`effect` 不该接会抛错的函数。调用方如果有错误，应该自己在进入 `effect` 之前解决；`effect` 只负责依赖收集、重跑和 cleanup。
7. 在这个判断下，把 `Eff.f` 收回成 `() -> Unit`，`effect` 也收回成直接返回 stop 函数，不再走 `Result` 包裹；`dom.mbt` 和 `domcmd.mbt` 对应的 `match effect(...)` 残影也一起删掉。
8. 然后又把当前上下文从 `Option` 收成哨兵值。补了 `fscp / feff`，把 `cscp / ceff` 改成始终持有一个默认 `Scope / Eff`，不再走 `Some/None`。
9. 同一步里把 `Scope::run`、`Eff::run` 和 `Cel::get()` 的哨兵判断都改到新模型上。`effect` 里“当前没有 scope”这件事改成判断 `cscp.val` 是否还是 `fscp`。
10. 最后把最小依赖收集接回当前代码：`Cel` 自己持有订阅的 `Eff` 数组，`get()` 收集依赖并通过 `onclr` 注册反向解绑，`set/mutate` 触发 `notify()` 重跑订阅 effect。
## 04-12 晚上
1. 先把 `reactive` 的依赖收集主路径重新收到了 `Cel + Eff + Scope + flush`，把 `effect` 的错误模型和旧分支语义都甩掉，只保留当前这版最小模型。
2. 然后把 `Cel` 的订阅容器和调度容器分开调查了一轮，分别拿 `Set/Array`、`Queue/Set` 做了最小 benchmark。结果是调度侧 `Queue + queued` 明显更快，`Cel` 侧依赖集合用 `Set[Eff]` 更合适。
3. 中间还试过“省略稳定依赖重绑”的双向维护版本，也额外做了 benchmark。结果是 bookkeeping 成本更高，尤其依赖数上来以后明显慢于经典反向记录，所以最后回到经典反向记录。
4. 接着把 `Eff.deps` 的表达收正了。最开始一版绕成了“记录装 effect 的桶”，读起来很差，后面改回真正的依赖源语义，`Cel` 持 `Dep = Set[Eff]`，`Eff` 反向记录 `Array[Dep]`。
5. 然后把 `flush` 从空壳改成了正式的手动刷新模型。现在 `effect` 首次立即执行，后续由 `Cel::notify()` 入 `EffQueue`，只有显式 `flush()` 才会统一执行排队的 effect。
6. 为了让 `flush` 更顺，又把原来 `base.mbt` 里的通用 `Queue` 删掉，调度逻辑收进 `reactive.mbt` 自己的 `EffQueue`。`queued`、队列清空、锁状态、错误恢复都放回这个内部结构里，不再散在文件顶层。
7. 之后补了 `flush` 的错误恢复。现在 `flush` 中如果抛错，会把待执行队列取空，把这些 effect 的 `queued` 复位，再把错误继续抛出去，不会把内部状态卡脏。
8. 中间还确认了 MoonBit 的 `defer` 写法。`defer s.lock = false` 编不过，实际可用的是 `defer { s.lock = false; () }`，所以把 `EffQueue::flush` 改成了这套写法。
9. 接着把 `reactive` 测试补了起来，重点锁了：`effect` 首次立即执行、后续更新等 `flush`、同一轮去重、重复 `get()` 不重复订阅、条件分支依赖切换、`stop` 取消已排队 effect、`stop` 后解绑、单次 `flush` 继续 drain 链式触发、`flush` 出错后还能恢复。
10. `src` 包验证已经跑过：`moon check -p src` 通过，`moon test --target wasm-gc src` 10 条测试全过。
11. 之后又检查了 `Eff.clrs` 的真实使用面。确认当前 `src` 里没有地方再把 cleanup 挂到 effect 自己身上，所以把 `Eff.clrs`、`HasClrs for Eff` 和相关清理逻辑删掉了，编译和测试都还正常。
12. 现在 `src` 侧最大的功能缺口已经不在 `reactive`，而是在名字和查询系统：`ui-id` 还只是类型壳，`Node::set(..., Id(...))` 还是空实现，`h_map/h_map_dyn` 传进来的 `ui_id` 也还被忽略，`Runtime::resolve(path)` 仍然是 pending。
## 04-13 上午
1. 先把 `ui-id` 的名字查询主路径接进 `src`。`Runtime::resolve(path)` 开始真正走 `Dom::resolve(path)`，不再留 pending 壳。
2. 先做了 `name scope` 的最小实现。普通 `ui-id` 只登记名字。`scope=Name` 的节点会持有自己的 `names`。查询按 path 一段一段往下进 `names`。
3. 中间围着 `namescope` 结构来回收过几次。最开始同时留了两张表，一张存叶子节点 id，一张存子 scope 入口。后来确认这层是重复语义，改成单张 `Map[String, Node]`。
4. 同一步里把名字相关状态继续压短。`Dom` 上只保留一份根 `names`。元素节点上也统一叫 `names`。不再混用 `scope / scopes / nscope` 这几套名字。
5. 接着把名字维护入口收成 `Dom::update_names(node, bind~: Bool = true)`。`insert / remove / mount` 都改成走这一个入口，不再留 `bind_names / unbind_names` 包装。
6. 中间一度把 `update_names` 收成只更新当前节点。这样复杂度更低，但匿名包裹里的命名后代会丢查询归属。补测试以后，这个问题被直接测出来了。
7. 随后按测试把名字更新改回对子树递归。当前实现会先沿父链找最近的 `names` 宿主，再按子树往下重绑。进入新的 `Name` scope 以后，子节点改挂到该节点自己的 `names`。
8. 又继续查了 `insert / remove` 的解绑时机。最开始显式在 `insert` 和 `remove` 调用点各写一份 `update_names(..., bind=false)`。后来把解绑统一挪进 `_detach(dom, node)`，调用点里的重复解绑删掉了。
9. `_detach` 第一次只在 `parent is Some(...)` 时解绑，这样会漏掉“局部子树先泄漏到根域，再整体接进 scope”的情况。随后把解绑挪到 `_detach` 开头，保证只要节点准备脱离当前归属，就先摘掉名字。
10. 为了把语义钉住，补了几条 `runtime` 测试：普通 scope 查询、普通 `ui-id` 不开域、嵌套 scope 边界、匿名包裹里的命名后代能进父 scope、这类后代不会泄漏到根 scope、删除匿名包裹后后代名字会一起消失。
11. 现在 `src` 侧 `name scope` 的基本查询已经能用了，但 `list scope` 还没接，`h_map(ui_id)` 也还是旧壳。`UiPos.style` 也还只是挂在类型上，没接正式样式规则输出。
1. 先继续收 `name scope` 的复杂度。把 `head/body` 改成真实根节点，`mount` 统一走 `Node` 插入路径，`insert` 也加了 `fresh` 入口，先把 fresh 构建和活树移动分开。
2. 然后把名字维护从“插入后整棵重扫”往构建期前移。`child / append / Lazy` 开始显式携带名字绑定上下文，fresh 子树在创建时就直接登记名字，活树移动继续保留 `update_names`。
3. 接着发现 `Dyn` 会把旧 scope 抓进闭包。先补了一条跨 scope 移动再触发 `Dyn` 重建的测试，把“新节点回写旧域”的问题锁出来，测试先红。
4. 随后只改 `Dyn`。让它每次重跑时按当前 `anchor.parent` 重新找宿主 name scope，再生成新子树。刚补的测试转绿，现有查询测试也保持通过。
5. 中间又收了一轮局部接口。`node_names` 改成了 `Node::names`，`parent_id` 去掉，`detach` 也挂回 `Node` 自己。向上找最近 `names` 宿主的逻辑统一抽成一条 `name_host(node: Node?)`。
6. 之后开始补 `ui-id` 校验。先把明显非法的名字直接卡掉：空串、前后空白、空白字符、`/`、`:`、`\`。同时在名字绑定时补了“当前 scope 名前缀重复”的校验，像 `window/window-title` 这种会直接报错。
7. 为了把绑定逻辑收成一条主路径，又把 `bind_name` 抽成通用逻辑，随后继续收成 `Node::bind_name(host, bind~)`，避免构建期和 `update_names` 各写一份。
8. 再往下把名字遍历抽成了通用树遍历。现在 `Node::walk(enter, leave)` 只负责遍历，`update_names` 自己维护宿主栈，碰到 `Name` scope 时跳过子树。
9. 期间有一次把 `names + scope` 包成 `UiMeta`，后来用户指出这是重复概念。随后把这层删掉，改回直接传宿主 `Node`，绑定时从宿主节点现取 `names` 和当前 scope id。
10. 最后专门做了一次复审。确认 `Dyn` 的 stale scope 问题已经被测试锁住并修掉；同时把错误流盘了一遍，发现现在一批正式输入/调用错误还在走 `abort`，这件事还没收，后面得单开处理。
## 04-13 下午
1. 先把 `src/dom` 里正式错误从直接 `abort` 改到可捕获的失败路径，`Runtime::new`、`Dom::mount`、`resolve` 这条显式调用链能正常报错。
2. 同时把 `effect` 和 cleanup 收回到“不吃 raising 回调、自己也不抛错”的模型。动态子树更新和动态属性绑定里的错误改成内部 `try/catch`，不再把错误挂到 reactive 调度上。
3. 给测试补了 `assert_fail(...)`，把一批 `try? ... match Ok/Err` 的失败断言收成统一 helper。
4. 给 `Dom` 加了 `on_error/report`。原来会被吞掉的动态子树构建错误、patch 错误、删除错误、动态属性错误，先统一改成“先上报，再忽略”。
5. 随后把“子树构建失败”的处理继续往前推。不是只记日志，而是统一在 `child(...)` 这一层转成 `div.dom-error`，错误消息直接显示在界面里。
6. 把上层渲染入口一起收正。`h`、`Comp`、`Entry.view` 这些对子树构建已经不再暴露错误类型；用户传进来的 raising 渲染函数会在内部转成错误节点。
7. `Runtime` 没再自己保存错误数组，改成和 `Dom` 一样只接 `on_error` 回调。错误记录交给更外层。
8. 然后开始接 `h_map_dyn(ui_id)`。先试过“真实 wrapper + patch children”的做法，但这条路把 list scope 和真实 DOM 宿主绑死了，代码也明显变厚，方向判错了。
9. 按用户重新钉的语义，把 list scope 收回成更轻的模型：本质只是“一个可查询名字 + 一组 item scope”。最后删掉了那层真实 wrapper 和额外的 `mod_children` patch helper。
10. 当前 `h_map_dyn(ui_id=Some("todos"))` 已经能提供最小 list scope。`resolve` 现在支持 `todos/0/text` 这类路径。为此只保留了两样内部结构：每个 item 的 query host，以及 list 节点上当前 item 数组的映射。
11. 这次还顺手补了一批最小测试，锁了 `comp(...)` 真正被用到、`Runtime` 错误通过 `on_error` 往外扔、`Dyn` 错误会显示 `dom-error`、`h_map_dyn ui_id` 能打开 list scope。
12. 最后把 `resolve` 里几处 MoonBit 语法噪音一起收了一遍，包括局部递归改成 `letrec`、`try? + match` 改成 `try/catch/noraise`。
## 04-13 晚上
1. 先讨论了工作区里 `list scope` 的设计冗余。核心判断是当前实现把 query 语义和 `Dyn` 的真实动态宿主拆开了，复杂度长偏了。
2. 重新读了最近的 `devlog`、`skill` 和当前 `src/dom.mbt` / `src/domcmd.mbt`。确认用户要压掉的不是名字问题，是机制位置问题。
3. 先判断出当前 `h_map_dyn(ui_id)` 的实现太厚。它额外长了 `list_node / list_owner / list_host / ListItem { host, frag }` 这套平行状态。
4. 随后继续讨论到 `ListItem` 本身也不对。它把 query 宿主和渲染结果绑到一起，语义不干净。
5. 中间我一度把方向写错了。错误点是把 `h_map_dyn` 写成了自己管理 `anchor / effect / mod_dom / cleanup` 的特化 `Lazy`。这等于把动态主路径从 `Dyn` 里拆出去。
6. 用户随后明确指出这条路是错的。要求先别碰 `h_map(ui_id)`，先把 `Dyn` 自己改对。
7. 按这个新边界，把 `h_map_dyn` 先收回成普通 `Dyn(fn() { Lazy(...) })`，临时忽略 `ui_id`。这一步的目的只是把动态生命周期先压回 `Dyn`。
8. 之后又继续讨论，确认当前真正对不上的地方是：`Dyn` 现在没有输入 `UiMeta` 的地方，所以 list scope 想挂到 `Dyn` 自己身上时没有入口。
9. 为了把这个意图钉住，先补了一条新测试。目标不是再经由 `h_map(ui_id)`，而是直接表达“`Dyn` 本身带 `list scope`”的用法。
10. 用户随后把这条测试改成了用户想要的语义形状：`Dyn(Some(list), () => ...)`。这个版本虽然还没编过，但已经把真正缺的接口暴露出来了。
11. 当前编译不过的直接原因也已经查清：`Dyn` 现在第二个参数仍然要求返回单个 `Child`，而用户那条测试里实际返回的是 `Array[Child]`。也就是说，除了 `UiMeta` 输入口，`Dyn` 的输出口对“动态列表”也偏窄。
12. 现在真正需要后续 agent 接着做的点有两个。第一，给 `Dyn` 一个正式的 `UiMeta` 输入口，并让实现消费它。第二，重新判断 `Dyn` 的返回结果是否还应该继续限定成单个 `Child`，还是应该允许直接表达一段动态 children。
13. 当前不要接着做的事也要记清。不要再把 `h_map_dyn` 写成自己的动态宿主。不要再在 `h_map` 外面长第二套 `anchor / patch / cleanup` 生命周期。
14. 目前仓库处在“测试已经表达出目标语义，但实现接口还没跟上”的状态。这个未完成点需要明确留给后面的 agent。
1. 先读了最近 `devlog` 和相关实现，确认上一段工作的核心约束是：不要再给 `h_map_dyn` 单独长第二套动态宿主，优先把 `Dyn` 自己接上 list scope。
2. 一开始沿着这个判断，先在现有 DOM 名字模型里尝试把 `Dyn` 直接吃 `UiMeta`，再让 `Dyn(Some(list), ...)` 在自己的 anchor 上维护 list item 查询域。
3. 这一步里先后试过几版：让 anchor 挂 `UiMeta`、让 list item 根节点承载查询域、让 `NodeCtx` 进入 `Lazy/child` 的 realize 上下文。代码能逐步编起来，但模型越来越说明一个事实：list scope 和普通 name scope 不是同一种东西。
4. 随后讨论进一步收窄到一个更明确的点：`NodeCtx` 应该只是 `Lazy -> Node` 的必要上下文，字段压成 `ns / name / names` 三项，不再拿 host node 充当名字宿主。
5. 在这个方向下把 `child/Lazy` 的签名收成吃 `NodeCtx`。同时也试着让 `Dyn(list)` 给每个 item 建自己的 `NodeCtx`，把它们挂回 anchor 上。
6. 很快又发现这个方向虽然更干净，但还是有结构问题。最大的矛盾是：普通父链查 scope 的逻辑，和 `Dyn(list)` 里 frag 边界该停在哪，不是同一个机制。
7. 接着围绕“父 scope 到底怎么查”做了更细的判断。用户指出两个关键点：`ctx` 应该就是 parent ctx，不需要拆别的概念；另外 `Dyn(list)` 的 frag 顶层根节点必须带一个标记，查到这个标记时才能回到 anchor.items 取对应 item 的 ctx。
8. 基于这个判断，补过一版 `ItemMark + anchor.items[index]` 的实现，把父 ctx 查询改成先认 item 标记，再认普通父 scope。这一版能编过，也补了若干测试去覆盖 `Dyn(list)`、嵌套 `Dyn(list)` 和 list item 里的普通 `Dyn`。
9. 再往下继续讨论时，用户指出一个更大的设计反转：如果 query 关系本来就是独立语义，那与其继续让 DOM 树反推 `ui-id` 关系，不如让 `ui` 自己显式声明 scope 关系，DOM 树完全不要再承担 `ui-id` 维护。
10. 按这个新判断，先把工作区当前改动 stash 起来，切到新分支 `dev/simp-ui-id`，准备在这条线上重做。
11. 在新分支的第一步，先把现有 `ui-id/query` 整套功能从 `src` 里摘掉，回到完全没有 `ui-id`、没有 `resolve`、没有 list/name scope 的最小 DOM 基线，同时把相关测试一并清空，只保留无 `ui-id` 的最小测试。
12. 在这个干净基线之上，新建了独立的 `query.mbt`。先立最小 query 模型：`UiScope / ui(...) / Query / QueryScope / QueryBinding / QueryListNode`，再补一组只验证关系树自身的测试。
13. 接着把静态主路径接回：`Id(...)` 重新回到属性系统，静态元素创建时会把 `ui` 绑定进当前 `QueryScope`，`Runtime` 也正式挂上一份 `Query`，`Runtime::resolve(path)` 开始走 `Query::resolve(...)`。
14. 然后开始接动态部分。先把 `Dyn` 改成重新接受 `Ui?`，再让 `Dyn(Some(list), ...)` 在 query 里建立 `List` 绑定，并在每次重跑时更新 `QueryList.items`。
15. 这一阶段一度把 `QuerySlot` 当成动态挂载点的中间概念，但很快又被用户指出真正关键是 `Dyn` 接受 `ListScope`，不该先围着 slot 长一层壳。随后把这个中间概念删掉，收回成围着 `Dyn + List` 的正式模型。
16. 再往下收的时候，用户指出当前 query 模型里没有显式的 parent 声明，只是在构建时临时传当前 scope，这个前提本身就没立稳。
17. 基于这个提醒，把 `QueryParent` 补成正式状态：根域是 `Root(Head|Body)`，`Name scope` 子域是 `Scope(node_id)`，`List` item 子域是 `List(node_id, index)`。同时补了 query 层测试去锁 parent。
18. 用户随后继续指出 parent 还不够，因为真正缺的是 `ui` 声明本身没有显式 parent。于是又把 `ui` 从裸 `UiMeta` 改成了 `Ui { key, parent, id, scope, class, style }`，并让 `Query.bind/unbind` 真正按 `ui.parent` 去找父 scope。
19. 这一步也把 `h_map_dyn` 的 `ui_id` 从字符串改成了 `Ui`。这样像 `title = ui('title', parent=Some(todos_ui))` 和 `h_map_dyn(ui_id=Some(todos_ui), ...)` 才是同一个声明节点。
20. 在动态列表这条线上，又把一批测试从“路径存在即可”改成真正用 `Cel::mutate(...)` 驱动数组变化，覆盖删除、插入、重排，以及嵌套 `Dyn(list)` 的 mutate 更新。此时所有测试一度仍然是绿的。
21. 用户接着指出这种检查还不够，因为 query id 不能只看大于 0，必须锁精确 id，尤其是 `h_map` 这种有 key 复用的场景。
22. 按这个要求，新加了一条关键测试：`h_map_dyn(ui_id)` 初始时记住 `todos/0/title` 和 `todos/1/title` 的 id；随后 mutate 交换数组顺序；最后要求两个路径查到的 id 也跟着交换。
23. 这条测试第一次正式打红，说明当前虽然 DOM 层和 `Child` 层按 key 复用了内容，但 query 里的 `List.items` 还是按当前位置整轮重建，没有和缓存 entry 一起复用。
24. 为了把实现和这个测试对齐，又把 `h_map_dyn` 收成一套统一缓存主路径：缓存 entry 统一存 `index + child`，再由 `Dyn(Some(list), ...)` 自己消费 list query 语义，不再分 `ui_id` 和非 `ui_id` 两套缓存实现。
25. 现在测试状态是：`moon test --target wasm-gc src` 已经重新回到全绿，并且 `Dyn(list)`、嵌套 `Dyn(list)`、`mutate` 删除/插入/重排，以及 `h_map_dyn(ui_id)` 的 query id 检查都已经在跑。
26. 当前还没继续做的不是测试，而是后续实现深化：虽然显式 parent 的 `Ui` 模型和独立 query 树都已经立起来了，但后面如果还要继续压代码量、收 warning，或者把 component 的更复杂动态挂载进一步正规化，还需要再开下一笔。
27. 当前残留的只是几个非功能性 warning：`Node::walk` 未使用，`QueryRoot/QueryParent derive(Show)` 是过时写法。功能上目前没有未解决的红测。
## 04-14 上午
1. 先重读了 `IntentDoc/dev` 里和 parser 相关的实现与测试。确认当前主实现是 `parser.js`。它既提供 PEG 组合子，也直接做代码生成。又专门对照了 `parser-handbuilt-peg.js` 和 `sample_json.js`。前者是后续 MoonBit 版要对齐的手写模板。后者是那边 parser 性能测试在用的正式 JSON 样本。
2. 随后在 `codegen` 下新开了 `_parsergen` 包。先落了一版 `parser-handbuilt-peg.mbt`。实现先收成最小 JSON recognizer。保留 `parse_value / parse_object / parse_array / parse_pair / parse_string / parse_number` 这条主路径。暂时不做 AST 重建，先把手写 PEG 模板路线立起来。
3. 接着补了最小测试和 `moon bench`。第一版先用临时短 JSON 和放大样本把 bench 入口跑通。目的是先确认 `_parsergen` 这块的编译、测试、性能测试通路都成立。
4. 然后把 `IntentDoc/dev/test/parser/sample_json.js` 那份正式样本接进 `_parsergen`。中间先直接读取 JS 文件文本，后面确认那其实是 JS 字符串字面量，里面还是转义后的 `\r\n`。这条接法不对。随后改成先把导出的字符串真正解出来，再生成真实的 `sample_json.json`，让测试和 bench 都直接读 JSON 文件。
5. 把正式样本接进来以后，`parser-handbuilt-peg.mbt` 在这份样本上第一次跑失败。随后定位到 `parse_object` 的空白处理少了一步：逗号后没有再跳空白，一遇到换行和缩进就挂。按最小补丁补了这一步以后，正式样本测试转绿。
6. 在这个基础上，把 bench 样本固定成两档。一档直接用 `sample_json.json`。一档把同一份数组 body 拼成 `fixture x4`。目的是看相同分布输入放大后的吞吐变化，不再用前面那种临时拼出来的短样本。
7. 然后依次跑了多个后端的 bench。先跑了 `wasm-gc` 和 `wasm`，确认 `wasm-gc` 吞吐大约是 `wasm` 的两倍。接着补跑了 `js`，结果更慢。第一次跑 `native` 因为环境里缺 `windows.h` 和 `errno.h` 失败。等导入 VS 环境变量以后再跑，`native` bench 打通。
8. 当前这版 `sample_json.json` 的结果已经整理出来了。`native` 约 `26882 ops/sec`。`wasm-gc` 约 `21911 ops/sec`。`wasm` 约 `11195 ops/sec`。`js` 约 `4517 ops/sec`。排序已经比较稳定：`native > wasm-gc > wasm > js`。
9. 同一轮里也顺手收了一部分 warning。`_parsergen` 里和 `fs` 相关的未用告警已经清掉。剩下只留 `@bench.T` 触发的 MoonBit 工具链告警。试过 `test-import` 也没有真正消掉，当前判断这是工具链口径问题，不是包里还有普通未用导入。
1. 先按用户的要求停掉了对实验文件的扩读，只回到 `IntentDoc/dev/parser.js` 本体，重新确认这条生成器主路径是“grammar AST -> 拼源码 -> 生成 parser”。
2. 接着在 `codegen` 里新增了一个最小 `parser.mbt`，先只支持 `rule / chain / oneof / repeat / maybe / omit` 这几个最基本节点，目标先压到 JSON recognizer。
3. 然后把 `codegen/main.mbt` 改成直接调用这个生成器，把生成结果写进 `_parsergen`，先打通“跑生成器 -> 产出 MoonBit parser 文件”。
4. 第一版只做到能吐源码，还没把生成结果真当成包内实现跑起来。用户随后指出最重要的是先跑通，不是继续加功能。
5. 按这个要求又把生成结果从 `.txt` 改成正式的 `.mbt`，并且直接在生成文件里补了最小测试，让它能和 `_parsergen` 现有样本一起验证。
6. 这一步第一次跑的时候撞上了同包命名冲突。生成版和手写版同时定义了 `ParseResult / Parser / parse / parse_ok`，还连带把局部记录字面量的类型推断一起搞乱了。
7. 随后按最小补丁把生成版统一加了 `Gen*` / `generated_*` 前缀，只改生成器输出，不动现有手写版语义。同时给两边 `let p = { ... }` 补了明确类型标注，避免同包里两个 parser 结构撞推断。
8. 中间还出现过一次“控制台打印的新内容”和“编译器报的旧内容”对不上的假象。后面重新核对磁盘上的生成文件，确认实际文件已经更新，问题只是前一轮并发命令把旧报错混进来了。
9. 最后重新串行跑了生成、`moon check -p _parsergen` 和 `moon test -p _parsergen`，确认这条最小生成链已经真的能跑起来，`_parsergen` 当前一共 5 条测试都过了。
10. 这次同时也暴露出一个还没解决的结构问题：生成器里那串字符编码常量还是手写进去的，当前还不是从 grammar/token 的实际使用里反推出所需字符集合。这一点用户已经指出了，应该留成后续继续收的点。
1. 先给 `src/dom` 补了一轮测试，把 `Dyn`、`h_map`、`h_map_dyn` 的主路径先锁住。
2. 这轮里先补了节点稳定性、必要重渲染、动态列表重排、重复 key 复用这些白盒测试。
3. 中间测出一个真实小问题：`h_map_dyn` 复用 entry 时无条件更新 `index`，会触发不必要重渲染。随后补了 `Cel::set_eq(...)`，再把 `h_map_dyn` 收回这条通用主路径。
4. 随后又补了一条最小 fuzz。先做 `h_map_dyn` 的随机列表操作，再把重复 key 也融进同一条 fuzz，锁当前 bucket 顺序复用语义。
5. 接着补了一条 `h` 结构 fuzz，只围着 `Str / Int / Null / Arr / Dyn / div / span` 做随机组合，对拍文本展开结果，验证 `child + Dyn` 的结构主路径没有漂。
6. 然后又给 `reactive` 补了一条最小 fuzz。围着 `Cel / effect / flush / stop / 条件分支依赖` 做随机操作，对拍一个很薄的调度模型。
7. 在这个基础上开始单开 `query.mbt`。先把 query 和 DOM 彻底拆开，只保留 `ui` 声明、实例 parent 链和实例上的 query。
8. 中间先把声明层和实例层的命名重新收了一次。`UIID` 改成声明层 `UIMeta`，实例层再叫 `UIID`。同时确认这层 style 语义不是从 key 派生 class，而是独立保存输入 style，再额外生成内部 class。
9. 随后把 namescope 接进实例层。先做了 scope 的名字表、`add / del / get`，再把 query 语义改成从当前实例往下查，不再沿 parent 向上对路径。
10. 接着把这层约束收紧：`add(child)` 必须校验 parent 正确，重复 `ui-id` 直接报错，不再覆盖。相关测试也一起补上。
11. 再往下发现 `uilist` 只存 `Array[Map[String, UIID]]` 太薄，表达不出 list item 自己作为查询节点的语义。于是先试了一版并列类型，把 `UIItem` 单独立出来，让 item 自己带 names。
12. 继续往下又发现，只要考虑 `listscope` 下面再挂 `listscope`，并列类型很快会逼出统一实例树。于是把这层继续收成统一 `UIID` enum，让 `Scope / List / Item` 都变成正式实例节点，query 统一发生在这棵实例树上。
13. 同一笔里又把声明层的 scope 从 `Bool` 收成三态：`Normal / Scope / List`。`UIMeta` 负责声明创建哪种 scope，实例入口继续压到最小。
14. 之后继续把 `query` 里的“失败语义却还绕成可空”的几处接口收成直接 `raise`。`get(...)` 和 `query(...)` 都改回失败主路径，测试口径也一起跟着收了。
15. 最后又围着 parent/root 语义来回收了几版。我这边一度把 root 概念写厚了，先后试过 `Root(String)` 和 `Root(UIScope)`。用户随后指出真正想要的不是再造一层正式 root 语义，而是把“无 parent”保持成最小表达，不要把 `None` 这件事写厚。这个理解偏差现在已经明确记住，后面这层还要继续按用户真正的意图收。
## 04-14 下午
1. 先把 `query` 的测试口径对齐当前实现。`query.test` 里的旧 `inst()` / `parent=Some(...)` 调用改成 `UIID::None` 和显式 parent。路径断言也跟当前 `path()` 口径对齐。
2. 随后把 `query.mbt` 里几处 `partial_match` 补全。给 `UIID::None` 补了缺失分支，让 `query.test` 能真正编译运行。
3. 接着把 `UIID::is_scope` 删掉。确认它只有 `query` 自测在用，没有别的调用点。
4. 然后把 `path()` 的前导 `/` 收掉。根节点改成直接返回首段名字，避免 `None` 把路径拼成绝对路径样式。
5. 又补了一条新的 `ui id` 约束。父 scope 下新增子 id 时，如果子 id 以前缀形式重复父 id，就直接拒绝，并补了对应测试。
6. 后面开始把 `query` 接到 `dom/runtime`。给属性系统加了 `Id(UIMeta)`，让静态节点创建时能生成 `UIID`，并把 `Runtime::resolve(path)` 接到 query 树。
7. 中间先走歪了一次，把 `Node` 长成了 `ui + uictx` 两层状态。随后按讨论把这层收回。最终保留的是 `body.uictx` 这一份 query 根，不再让每个节点各自长期持有一份并行上下文。
8. `resolve` 这条线也跟着收过几次。先短暂写成了扫 DOM 找 `node.ui.path()` 的递归版本，后面改回 `body.uictx.query(path).node()` 这条直接路径。
9. 同一笔里把 `UIID -> Node` 的关系也收正了。现在节点和 `UIID` 的绑定在创建 `Id(meta)` 时建立一次，迁移和删除只改 query 树里的 parent 关系，不再改 node 绑定。
10. 然后继续把 `insert/remove` 的 query 逻辑压回本地。删掉了 `child_scope / rebind / unbind` 这组三层壳，直接在 `insert/remove` 里处理首次挂载、迁移重绑和删除解绑。
11. 这一步里还专门把 `fresh` 语义修正了。首次挂载只绑定当前节点，迁移时才递归处理整棵子树，避免新建子树被重复绑定两次。
12. 最后开始接 `Dyn + list scope`。普通节点现在明确拒绝 `scope=List`。`Dyn(Some(meta), ...)` 只接受 `meta.scope is List`，并把结果展开到 item scope 里，路径形状是 `todos/0/...`。
13. 为了把这几层语义锁住，又补了一批 runtime 测试。新增了首次挂载兄弟 scope、整棵子树迁移、普通节点拒绝 list scope、`Dyn` 接受 list scope 这几条。
14. 当前验证状态是 `moon test` 全绿，共 `41 / 41`。目前没有挂着的红测。
## 04-14 晚上
1. 先把 `Dyn` 的 list 入口从 `UIMeta(List)` 收成 `Dyn(Some("todos"))` 这类字符串入口，同时把 list scope 独立成 `UIID::list(...)`，不再让 list scope 依赖 `UIMeta` 本体。
2. 接着把 `h_map / h_map_dyn` 接回这条 list scope 主路径。`ui_id` 改成直接传字符串，列表查询不再走平行实现。
3. 随后把 `dyn_list` 的 item scope 维护从“每次清空 `list.items` 再重建”改成“按长度增删并复用现有槽位”，避免 query item 实例整轮换新。
4. 同一笔里补了 `h_map(ui_id)` 的白盒测试，确认 list item 槽位实例在重排后保持稳定，不只是 DOM 节点 id 稳定。
5. 然后把 `ui` 校验从“借 `ui(id)` 临时造 `UIMeta`”抽成独立检查函数，`ui(...)` 和 `UIID::list(...)` 共用这条校验逻辑。
6. 接着补回了“普通节点拒绝 list scope”这条约束，并把检查放在 `insert` 时真正挂树的地方，避免只卡某个局部入口。
7. 同时补了“一个节点不能重复设置两次 `ui`”的保护，避免同一节点在 query 树里被重新定义。
8. 之后重新梳理了 `ui / uictx` 的职责，确认 `ui` 表示节点自己的 query 身份，`uictx` 表示当前所在的 query 上下文，并继续让 `insert` 在挂树和迁移时同步更新 `uictx`。
9. 接着排查了 `Dyn` 里直接套 `Dyn` 的 query 问题。先补出嵌套 `Dyn`、`frag -> Dyn`、`list item -> frag -> Dyn` 这些测试，把旧问题重新打出来。
10. 在这一步里先定位到 plain `Dyn` 重跑时吃的是旧上下文。随后把 scope 恢复逻辑改成从当前 `anchor` 自己重新求，而不是只吃创建时闭包下来的 `q`。
11. 同时修了 `current_scope(...)` 的一层细节：沿父链查找时先保留最近祖先的 `uictx`，避免 list item scope 被更高层祖先覆盖掉。
12. 又补了一处 patch 细节：`Dyn` 更新时，新生成且还没挂树的节点在插入时要按 `fresh=true` 处理，避免它们原本已经带好的 `uictx` 被父节点上下文直接冲掉。
13. 随后重新核对了 `frag -> Dyn` 的测试口径，把之前取错 move 目标的测试改成“匿名 wrapper 承接 move，内部继续保持 `frag -> Dyn` 结构”，避免测试本身把显式 scope 一起搬走。
14. 在这个基础上确认：`Dyn` 套 `Dyn`、`frag -> Dyn`、`list item -> frag -> Dyn` 这些 query 归属问题现在都已经过测。
15. 然后把 `query` 结果不是 `Node` 的失败语义收回 `Dom::resolve`，由 `Runtime::resolve` 继续做薄包装和上报。
16. 接着把 `unbind/bind` 组合收成 `UIID::rebind(...)`，把 `insert/remove` 里那几处重复的 query 迁移逻辑压成一条 helper。
17. 之后重新审了测试归属，确认原来 `runtime.test` 里大部分都在测 `dom/query/Dyn/h_map/move`，于是整体迁到 `dom.test`，让 `runtime` 不再承载这批主逻辑测试。
18. 最后把现有 fuzz 也整理了一遍：删掉单开的 `move/query` fuzz，把 query 和跨 scope move 的随机断言并进原有 `dom: h fuzz keeps rendered text equal to spec`，不再保留平行 fuzz 入口。
19. 同一步里把测试用 RNG 汇总到 `base.mbt`，`dom/reactive` 的 fuzz 都改成共享这一套随机工具，并且每次测试运行都用当前时间派生新种子，不再固定写死一个日期种子。
1. 先从 `src` 和 `service` 的现状重新判断“真正接线”的位置。确认当前仓库里没有独立的 `browser` 包，外围正式入口主要还是 `service`。
2. 随后把 `service` 和 `src` 的当前关系重新看清。确认 `query / trigger` 这组控制面已经开始站在 `src` 的 path 解析上工作，但整体模型本身还没整理清楚。
3. 接着翻了历史里的 `src/host.mbt`。确认它过去承担过正式宿主 UI、host 子实例管理、query 入口这些职责，所以讨论开始围着 host 和 entry 语义展开。
4. 然后第一次尝试补最小 `host.mbt`。目标先压到 tray、entries、windows 这些最小宿主结构，并保持 `src` 本地测试继续通过。
5. 很快发现第一版把 `ui(...)` 直接写进 render 里不合适。于是先把这批 `ui` 往初始化位置挪，但这时错误还是用 `abort` 结束，没有进入 runtime 的错误路径。
6. 接着围着 `Entry` 的形状来回讨论。先试过拆成 `init / render` 两段，再短暂写出 `with_init`、`EntryCtx`、`HostCtx` 这类中间层，想把会抛错的 `ui` 创建和 render 分开。
7. 这一步很快暴露出结构问题。两段接口虽然能表达“先初始化再渲染”，但业务侧会被迫显式承接中间类型，模型开始变厚。这组写法随后没有保留。
8. 随后重新确认 `Entry` 的本意。`Entry` 表示一种可实例化定义，实例侧至少要分出 `data / session / runtime` 三层状态。`data` 同类 entry 之间可共享且可序列化。`session` 实例独立且可序列化。`runtime` 实例独立且临时创建。
9. 同一笔里把 `uiid` 的层级重新讲清。确认 `uiid` 属于全局定义语义，不属于实例 `data`。它会抛错，所以实际求值时机放进 `init` 闭包。这个执行时机不改变它的语义层级。
10. 接着继续把 `scope` 的来源讲清。确认普通情况下不需要手工标记 `scope`。`comp` 的 root 也不自己开 `scope`。一段 UI 的根作用域来自外部挂载边界。
11. 又继续把 host 这类宿主的特殊点补全。像 host 这种拥有自己子实例的宿主，可以显式声明挂载点来挂别的 entry 生成的 `Comp`。这个挂载点上的 `uiid` 同时承担 name scope 入口。
12. 然后把 `style` 和 `uiid` 的关系重新定义。确认 `style` 绑定在 `uiid` 上。`uiid` 会生成全局唯一 class。`style` 默认精确命中这个 ui 位置。
13. 同时又把 `list scope` 的来源讲清。列表查询语义来自动态列表主路径，主要入口是 `h_map / h_map_dyn`。列表索引不应再编码回 `uiid`。
14. 中间还顺手确认了 `h_map(ui_id)` 相关旧理解里有一部分已经不成立。重点应放在 item 复用和 list query 语义上，不应继续围着固定 wrapper 节点去组织模型。
15. 之后又回头看 `Entry::new` 的真正形状。讨论结果逐步偏向一段式创建函数，也就是直接接受一个返回 `Comp` 的创建函数。公共变量在这个函数里创建。返回的 `Comp` 闭包继续使用这些变量。
16. 这一步也顺带把“entry helper 函数”的位置重新判断了一遍。像 `host_entry()` 这种只返回一个值的包级 helper 意义偏弱，更贴近语义的做法是让 `Entry` 自己承担静态注册入口。
17. 还检查了 DOM 测试的入口层级。确认 `dom.test` 不该借 `Entry / Runtime` 壳表达主路径。DOM 相关测试应尽量直接站在 `Dom` 自己上写。这个判断已经开始落实到测试辅助入口上。
18. 同时把本地实现做过一轮整理。先把 `dom.test` 里大部分 `Entry / Runtime` 包装去掉，改成直接在 `Dom` 上挂根节点和做查询，`moon test` 保持通过。
19. 随后又把 `Entry::new` 改回一段式，去掉 `EntryCtx / with_init` 这些中间层，让 entry 定义阶段直接返回 `Comp`，`src` 本地测试继续保持通过。
20. 为了让后续 agent 不再被旧口径带偏，把 skill 文档和两份参考文档一起重写了。文档现在统一按这版语义描述 `uiid`、挂载点、name scope、list scope、`style`、`Entry` 的层级关系。
21. 当前已经完成的是：语义边界重新整理清楚，相关文档口径已经统一，`dom.test` 的入口层级也开始对齐。
22. 当前还没完成的是：`Entry / host / instance / runtime` 的代码结构还没有完全按这套边界重做，尤其 `data / session / runtime` 三层实例状态、全局 `uiid` 定义时机、挂载点赋予 root scope 这些点还要继续落到实现里。
1. 先把 `Entry` 从只存 `view` 的薄壳收成显式 `data / session / init` 三段。`init` 负责先定义 `ui(...)`，再返回 `(D, S) -> Comp`。这样 `ui` 的声明时机回到定义层，不再跟实例渲染重跑混在一起。
2. 随后把 `host` 接到这条新形状上。`HostData` 里先放 `latency / time / entries / windows` 这几份状态。`session` 先收成 `Unit`。`host.init()` 里定义宿主自己的 `ui`，再返回真正的视图函数。
3. 中间还把普通动态文本的噪音收了一下。保留原来的 `Dyn(None | Some(...))` 主路径不动，只新增了一个 `DynP` 入口，让 plain dyn 不用每次都显式写 `None`。`src` 侧测试继续通过。
4. 接着排到了 `ui.style` 这条线。先复核当前实现，确认它之前确实被错误地塞进了节点 `style` prop，这和“`uiid` 生成唯一 class，再把样式绑定到这个 class”这层语义是错位的。
5. 在这个判断下，先把样式定义和 `UIMeta` 重新接上。`query` 里新增了全局 `CssRule` 收集。`ui(...)` 创建 `UIMeta` 时，如果带 `style`，就立刻登记一条规则。当前先编成 `.u_xxx { ... }` 这种最小形状。还没接到 DOM/bridge 正式输出。
6. 为了把这条语义锁住，又补了一条 `query` 测试。现在会检查：带 `style` 的 `ui(...)` 确实会新增一条 `CssRule`，规则文本和生成出来的 class 能对上。
7. 然后开始给 `host` 补样式。最开始误用了非法的多行字符串和规则块写法，马上在 `moon test` 里炸出来。之后把 `host` 里的样式统一改成 `#|` 多行字符串，再按 MoonBit 当前语法要求外面包一层括号，把 warning 也收掉了。
8. 同一步里还把 `style` 文本里的占位改成了 `&`。目前只是先把规则文本按这个约定存进 `CssRule`。真正消费这些规则的输出链路还没接。
9. 最后又修了一处 host 自己的挂载语义。原来把 `entries.id` 直接拿去给 `h_map(ui_id=...)`，同时又想让它承接 wrapper 的样式，这两件事语义不一致。现在拆成了外层 `entries-wrap` 节点承接样式，`h_map` 里继续保留字符串 `"entries"` 作为 list scope id。
10. 当前验证状态是：`moon test --target wasm-gc src` 49 条全绿。还没继续做的是 `CssRule` 往 DOM / browser / mock 的正式输出，这条链路现在还停在 query 层全局收集。
11. 目前重构期间, 注意只要用 moon test 进行测试, 不需要任何额外参数, `--target wasm-gc src` 这些都是多余的。
## 04-15 上午
1. 先把 `ui(style)` 从 `query` 里的全局 `css_rules` 收回到 `UIMeta` 本身，样式真正改成经 `Dom` 往 `head` 注入 `style` 节点。
2. 中间把 `mount_style` 从手搓 `element/text/insert` 收回成直接走 `h('style', [], [Str(...)])`，让样式也走现有 `h -> child -> insert` 主路径。
3. 随后把测试里的节点遍历 helper 收了一轮。先加了 `Node::children / Node::child_elements`，再删掉测试里的 `child_nodes / child_elements / head_nodes / body_nodes`，统一改成节点方法。
4. 接着又补了 `Node::first_child`，测试里取第一个孩子的地方不再写数组下标，也去掉了顶层多余的 `catch panic`。
5. 然后开始补正式 query。最初先写成 `Dom::query(path, kind, value)` 这种字符串分发版本，确认最小 `node / text / attr / prop / style` 五种查询都能站在 `resolve(path)` 外面包出来。
6. 很快又判断这层位置和形状都不对：query 细节不该堆在 `dom.mbt`，字符串 `kind/value` 也太弱。于是把 query 搬到 `bridge.mbt`，并进一步收成 typed 版本。
7. 当前 query 主路径已经改成 `Node::get(query)`。`Dom::query(path, query)` 只做 `resolve(path).get(query)`，`Runtime::query` 继续做薄转发。
8. 同一步里把 query 类型收成 `NodeQuery / NodeValue`，测试也全改成 typed 用法，如 `Text`、`Attr("title")`、`Style("background")`。
9. 随后给 `bridge.mbt` 补了 `NodeQuery` 的 `FromJson` 和 `NodeValue` 的 `ToJson`，为后面接 service/headless query 做准备。
10. 在补 `NodeValue::ToJson` 时，一开始顺着旧 browser snapshot 口径带进了 `focused / visible / value / checked` 这些字段。后面明确判断这是在兼容旧 API 形状，就把它们全删掉了。
11. 现在 `NodeValue::Node` 的 JSON 快照只保留当前 headless 下真正稳定能给的最小字段：`kind / id / tag / text / attrs`。
12. 当前验证都只跑了 `moon test`，没有跑 `test-all`，现状是 `52 / 52` 全绿。
13. 现在还没往前做的是把这条 typed query 真正接到 `service` 的 headless 路径；另外 `NodeQuery` 的 `FromJson` 还没被实际调用，所以还有一条未使用的 trait warning。
## 04-15 下午
1. 先把事件系统收成 `dispatch` 主路径。明确 `Node::dispatch(dom, ev)` 是核心，`Dom::dispatch(path, ev)` 和 `Runtime::dispatch(path, ev)` 只做薄转发，不再单独保留旧 `trigger` 那套语义。
2. 随后把 `Node::dispatch` 挪到 `bridge` 层，和 `Node::get` 放在一起，避免把控制面逻辑散在 `domcmd`。
3. 中间又把事件 handler 改成允许 `raise`。派发时如果 handler 报错，会通过 `dom.report` 走现有错误通路，同时 `flush` 也继续在同一处处理。
4. 接着把事件模型继续收短。删除了 `RegisteredListener` 和 `Dom` 上那套全局 listener 注册表，让 `Listener` 自己成为节点 `prop` 里的正式实例。`Node::dispatch` 直接从节点 `props` 里取 listener 并执行，不再经过全局表查 closure。
5. 为了让桥接侧还能消费事件属性，给 `Listener` 保留了单独的 `ToJson` 视图，只输出桥接需要的事件名和配置，不输出 MoonBit 侧 handler。
6. 然后把 `Entry.init` 的签名改成直接吃 `Runtime, D, S`。这样初始化阶段可以同时拿到 runtime 能力和实例自己的 data/session，不再需要在 `host` 首帧 render 时临时把数据塞回去。
7. 同一步把实例模型收正成“无类型运行时实例壳”。删掉了泛型 `Instance[D, S]` 的中间层，只保留运行时 `Instance { id, title, view, root }`，typed 能力后续留给 action 系统承接。
8. 接着把子实例默认包上一层自己的 `React + name scope` 根节点，根实例保持原样不额外包裹。这样子实例挂进父视图以后，查询路径和响应式生命周期都有独立边界。
9. 随后把 `host` 的层级重新拆开。确认 `entries` 不是实例列表，`windows` 也不是实例本身。`windows` 挪到 `session`，`entries` 放回 `data`。
10. 之后把 `entries` 恢复成桌面 icon 定义列表，并按用户指定的形状写成 `Cel[Array[EntryDef]]`，其中 `EntryDef` 里的 `id/title` 也都是 `Cel[String]`。
11. 为了让这类带 `Cel` 的结构能直接走 `h_map`，给 `Cel` 本身补了稳定 `id`，并在 `Cel` 层实现了 `Eq/Hash`。然后把 `EntryDef` 改回直接 `derive(Eq, Hash)`。
12. 接着把窗口区也切到 `h_map`，窗口 key 明确站在 `window.id` 上，避免窗口重排或复用时退回普通 `Dyn + map`。
13. 然后把“点击桌面 entry 以后创建实例”的主路径接上。现在桌面 entry 是按钮，点击后会调用 `runtime.create_instance(...)` 创建实例，再往 `s.windows` 里追加一个新窗口，窗口 body 挂这个实例。
14. 最后又继续收了一轮约束和派生。把一批没有真实使用面的 `Eq` 约束删掉了，比如事件值和 `DomNs` 上那层冗余派生，避免类型约束继续长厚。
15. 这轮里多次暴露出几个边界判断并当场收正：`window` 和 `instance` 不是一层；`entries` 不是实例列表；类型还没稳定时不要急着补测试；`Cel[Array[T]]` 的真实更新场景优先考虑 `mutate`，不要把整值替换写成默认主路径。
16. 当前验证都只跑了 `moon test`，现状是全绿。现在还没继续做的是把 `Window` 真正构造进正式主路径，所以这一层类型虽然已经拆出来了，但实例创建到窗口状态的完整业务模型还只是最小接线版。
## 04-15 晚上
1. 先重新讨论了实例 action 的层级。确认 `Entry` 定义时保留强类型 action，实例侧真正拿到的是绑定了 `runtime / data / session` 的可执行 closure。为验证这点，先做了一版 `EntryAction / InstanceAction`，并拿 `host` 的启动 entry 当例子接通。
2. 随后发现 `InstanceAction[A, R]` 把函数形状卡成了单参数，这层太硬。于是把 action 收回 `Entry.actions`，直接返回一组已绑定函数，实例侧不再额外包单参数 action 类型。
3. 接着继续收短，判断 `Inst[A]` 也只是“`Instance + typed actions`”的临时壳。随后删掉这层，`Runtime::instance(...)` 改成直接返回 `(Instance, A)`；typed 信息继续跟着明确的 `Entry` 走，不再伪装成“typed instance”对象。
4. 再往下发现注册表里的 `RegisteredEntry` 也是同类中间壳。随后删掉这层，注册表只剩“登记创建闭包”，并给 runtime 增加了按 `entry_id` 启动实例的正式入口 `spawn(...)`。`host` 启动 entry 不再走局部假分发，而是按 `entry_id` 走统一主路径。
5. 在这个基础上，把实例 id 生成统一收到 runtime 内部一条主路径。显式传 id 时做全 runtime 唯一检查；默认 id 改成每个 entry 在当前 runtime 下各自复用 `gen_id` 生成序号。
6. 然后继续收 `Instance` 自己承担的职责。删除了实例内部的自动 wrapper 语义，`Instance` 不再保存 `root`，也不再通过 `child()` 偷偷包 scope。实例本身只保留 `id / title / view`，父侧如果要静态挂载点、样式和 scope，需要自己显式包 wrapper。
7. 接着围绕“实例 id 查询跳转点”和“父组件内部静态 scope”重新判断边界。最终确认这两种语义不是一回事：前者是 runtime 级的实例入口，后者是像 host 这种组件自己定义的静态挂载点。
8. 随后没有给 DOM 加新的挂载属性，而是试了一条更轻的实现：在 `Runtime::instance(...)` 里给实际的 `view` 包一层透明包装。利用渲染时拿到的当前 `q`，把 `instance.id -> 当前注入位置` 记进 runtime。
9. 在此基础上，把 `Runtime::resolve/query/dispatch` 接到了实例跳转主路径上。现在 path 第一段如果命中实例 id，就直接从该实例当前注入位置继续查询；否则继续走普通 path。底层 `Dom` 语义没改。
10. 最后专门测了一条更极端的组合：外层实例再挂一个内层实例，内层实例 `view` 返回多根节点。结果静态 scope 路径和实例 id 跳转路径都能正常工作，这条测试已经留在仓库里。当前确认这版透明包装不依赖实例 `view` 是单根节点。
1. 先围着实例关闭做了一轮实现，给 `Runtime` 加了 `close`，宿主窗口加了关闭动作和按钮。
2. 中间只跑 `moon check` 先过了。随后用户指出这不够，要跑 `moon test`。
3. 跑出一条真实回归：窗口标题路径把关闭按钮文本一起读进去了，`windows/0/title` 不再只返回标题。
4. 随后把窗口头部拆成独立容器，保留 `title` 路径只承载标题文本，回归消掉，`moon test` 回到全绿。
5. 接着开始重看 `service` 设计。先讨论了实例系统、bridge、service 的边界，但这一步判断偏空，没有站稳现有代码。
6. 之后回到代码本身，重新阅读了 `service/bridge.mbt`、`src/bridge.js`、`service/cli.mbt`，确认现在真正的旧壳主要在 service 协议和 CLI 命令面，不在浏览器侧底层节点操作。
7. 按“先删旧壳”的方向动过一轮 `service`，把 CLI 旧命令面和部分 bridge 旧入口砍掉了，但用户随后指出这轮删过头了，把 `cli` 里仍有价值的命令定义骨架也一起删掉了。
8. 然后改成按文件逐个重看，只从 `service/http.mbt` 开始，不再整体推演。
9. 在 `service/http.mbt` 里，先删掉了旧的 `call_at / call_service`，把只用一处的 `root_file / content_type` 并回 `serve_file`，把文件收成更纯的 HTTP 服务端骨架。
10. 随后又继续把响应接口收成 typed 入口：删掉分散的 `respond_json / respond_ok / respond_err`，改成单个 `respond(conn, HttpResp)`，同时把 `next_addr` 并回 `bind_http_server`。
11. 中间还专门澄清了 MoonBit 的 `.` 和 `..` 语义。最开始解释错了，后面查了官方文档才确认 `..` 是 cascade，不是普通跨行链式调用。
12. 最后又单独确认了 `&T` 参数语义。重点收回到：`&T` 是类型的一部分，用在“只借用读取”的参数位置；像 `write(data: &@io.Data)` 这种接口就是当场读取输入，不把它当成会被保存或转交的值。
## 04-16 上午
1. 先把 `service/runtime.mbt` 从空文件开始重立最小 `Runtime`。第一版只保留了托管 `src.Runtime`、多连接表、pending 路由、发送队列这些最小状态。目的是先把 `runtime` 从旧 browser/repl/CLI 混合物里剥出来。
2. 随后把 `Runtime` 里一批多余的 `Ref` 去掉，改成直接持有 `Map` 和计数器。又把 `conn_id / req_id` 收成和 `src` 一致的生成器写法，并把 `src/base.mbt` 里的 `gen_id` 提成了 `pub`，让 `service` 可以直接复用。
3. 接着把连接行为往 `Conn` 上收。先后补了 `send / close / flush / recv`。中间一度还加过 `recv_json`，后面判断这会把 JSON 协议层错误地沉到连接层，于是删掉了。当前 `Conn` 还是 ws 连接对象，但“读文本再解 typed 消息”这条正式主路径还没立起来。
4. HTTP 这一块重新补回来了，但没有塞回 `Runtime`，而是立了一个独立的 `HTTP` 类型。它现在负责静态文件、控制口命令入口，以及统一的 `HTTP::send / HTTP::error`。中间还做过一轮整理，把重复的 `send_response/write/end_response` 收成了 `HTTP::send`。这条边界现在比旧版短，但 websocket upgrade 还没接回去。
5. 为了让 root 入口不再在 `service` 里手写 `match "host" | "demo"`，把 `src.Runtime::new` 改成了直接吃 entry id 字符串，然后把 `service/runtime.mbt` 的 `_rt(...)` 改成直接调 `@src.Runtime::new(root, ...)`。`src/runtime.test.mbt` 里原来按 `Entry` 直接传入的测试，也跟着改成了先 `register()` 再 `Runtime::new("...")` 的主路径。
6. 接着开始补 service 生命周期控制。最初是把一大批 `state_dir / state_path / lock / write_state / read_port / detect / start / stop / restart / run` 全挂回 `Runtime::`。这一步虽然把功能补回来了，但 API 太碎，而且很多底层动作只是薄壳，读起来很乱。
7. 然后开始收生命周期辅助 API。先删掉了几层纯转发方法，接着又试图把 state/lock 这一坨抽到 `Lock` 里。中间走歪了好几次：一度把很多逻辑内联回了 `Runtime::detect/start/stop/run`，这和“把 state/lock 从 runtime 剔出去”的目标相反。后面又按用户的提醒把 `Lock` 重新补成带行为的类型。
8. 现在 `Lock` 这块已经开始成形。它目前在表达的是“service 的 lock/state 文件与目录语义”，而不是单纯的文件句柄。现在已经补了 `open / get / clear / release / write / port / held` 这组方法，并把 `Runtime::detect/start/stop/run` 重新改回只调用 `Lock`，不再自己展开那一大坨 state/lock 逻辑。
9. 但这块还没彻底做完。当前 `Lock` 虽然比前几版对很多，但还留着明显没收净的点：目录来源和默认目录语义刚从全局状态收回来，结构还需要再核一遍；`Lock::dir(dir? = "")` 这种“读和设混在一起”的形状还只是讨论结果，没有完全站稳；另外 `Lock::path_of(...)` 现在还是一个为复用字符串拼接而留的内部 helper，它是否继续存在，要看下一轮是不是还能继续收短。
10. 这轮真正还没做好的重点，不在 `Lock`，而在 `request.mbt`。我特别查了一次 `moon check --target native -p service`，当前最大的红错不是 `runtime` 这一坨，而是 `request.mbt` 还整块挂在旧 `Runtime` API 上。
11. 里面还在引用： `Runtime::parse_port` `Runtime::status_text` `Runtime::sync_browser` `Runtime::query_ui` `Runtime::trigger_ui` `Runtime::repl` 以及旧的 `start/restart/stop/roots` 命令面形状, 这些接口现在不是不存在，就是语义已经变了。所以 `request.mbt` 目前还是整个 `service` 包最主要的编译断口。
12. 除了 `request.mbt` 之外，`runtime.mbt` 这一轮也还没完成最终收口。原因有三条：`Lock` 这块虽然已经重新集中，但还需要再做一轮“删掉只是为了过渡而存在的局部 helper”的整理。
13. `Runtime::run` 现在只接了 HTTP 控制口和静态文件，还没有把 ws 服务重新接回来。`Runtime::cmd` 目前还是最小命令集合，只支持 `status / stop` 这种临时口径，还没和未来真正的请求模型对齐。
14. 还有一个没彻底解决的边界问题是：HTTP 现在已经单独成型了，但 websocket 那条线还没和它重新接上。当前 `Conn` 已经有 `recv`，但 ws 消息的 typed 解码主路径、连接注册后的消息循环、以及 HTTP upgrade 到 ws 的调度，都还没正式补回来。这意味着现在的 `Runtime` 只是把“生命周期 + HTTP + ws 连接对象”摆到了一个较干净的位置，离完整 service 仍然差一段。
13. 总结现在最需要在 devlog 里明确留下的未完成项，就是这三条：`Lock` 已经从 runtime 里抽出来，但 API 还需要再做一轮精简和稳定，避免留下过渡式 helper。
14. `request.mbt` 仍然是旧世界，当前是 `service` 包编译不过的主要来源，需要下一轮整体删薄或重写。ws 主路径还没重新接回，当前只有 `Conn` 对象和 HTTP 入口，没有正式的 ws 收发与协议循环。
15. 记录一个小问题, mbt 的 lsp 插件长时间运行后, 会出现重命名符号出现错误的情况, 重启编辑器后消失。
## 04-16 下午
1. 先重看了 `service/runtime.mbt`。确认 `Lock` 虽然已经有 `file / dir` 和一批方法，但 `Runtime` 并没有真正持有它。生命周期入口大多还在直接调静态 `Lock::...`，只有 `run()` 里临时拿了一次局部 `lock`。
2. 接着把 `Lock` 收成 `Runtime` 的正式字段。`Runtime::new(...)` 创建时就把 `state_dir` 塞进 `Lock`。`detect / status / launch / start / stop / restart / run` 全部改成经 `self.lock` 走，不再在 `untime` 外面直接展开 lock/state 细节。
3. 然后把原来裸放在文件级的端口探测函数收进了 `HTTP`，名字改成 `HTTP::boot`。`Runtime::run(...)` 改成通过 `HTTP::boot(...)` 起服务，`Lock` 继续只管 state/lock 文件，不掺进 HTTP server 构造逻辑。
4. 同时把 state 文件的 JSON 形状收成了正式 `State { pid; port }` 类型，并让 `Lock::write(...)` 和 `Lock::port(...)` 都走这一个类型。后面又继续收了一步，让 `Lock` 自己带 `state: State?` 缓存。当前对象已经能直接从字段里读 `pid/port`，只有第一次需要时才会从文件补一份。
5. 随后把 `detect()` 的逻辑改成了真正按 `pid` 判断存活，不再靠 lock+status 一起猜。这里还把原来 C stub 里过于特定的 `metaeditor_service_process_exists` 改名成了短的 `pid_exists`，MoonBit 侧声明也一起对齐。
6. 接着把 `poll_until` 收成了超时直接抛错的版本。`start()` 和 `stop()` 里原来围着 `Some/None` 或 `Bool` 写的判断都改成了直接吃异常，再在外层补具体业务报错文案。
7. 之后修了 `start()` 里一个真实逻辑问题。原来轮询拿到的是控制口响应，不是实际端口。现在改成轮询“state 里端口可读，且 `status` 可打通”，最后返回真实端口。
8. 再往下继续收 `HTTP`。先给它加了 ws 升级入口，固定挂在 `/_meta/ws`。然后在 `Runtime::run(...)` 里把 `on_ws` 真接上，最小接通了 upgrade、连接注册、接收消息、连接回收这一条线。
9. 在 ws 入口接通之后，又补了最小协议主路径。先做过一版固定 ack，后面收成了正式类型：把控制口消息、ws 入站消息、ws 出站消息和 `Runtime::serve_ws(...)` 都放进了 `protocol.mbt`。当前只支持 `bridge:hello`，成功会回 `hello_ack`，其他消息会回 `rejected`。
10. 这一步里顺手把旧 `request/response/session` 里还能参考的类型口径抄出来，但没有把旧组织方式原样带回。期间有一度把 `protocol.mbt` 删掉又补回，最后按当前判断保留成“协议类型 + `Runtime::serve_ws`”这一种组织。
11. 之后把 `service` 包缺失的最小 `main` 入口补回来了。现在只认 `--internal_boot_as_service`、`--port`、`--state-dir`，然后直接创建 `Runtime` 并调用 `run(...)`。这样 `moon.pkg.json` 里的 `is_main: true` 不再报错。
12. 同一轮里还把所有 C stub 和 FFI 声明里的 `metaeditor_service_` 前缀都去掉了。当前这些符号已经统一成短名字，比如 `get_tmp_path / current_pid / retain_state_file / release_state_file / pid_exists / terminate_process`。
13. 再往后继续收 `base.mbt`。按“当前活代码没用就删”的标准，删掉了调试计时、JSON helper、ws 接收测试 helper、进程输出收集、shell quote/join 这些不再被 service 主路径使用的东西，只保留了 `ServiceError / poll_until / wait_timeout / boot_service` 这类最小通用部分。
14. 同时把 `default_port / max_port_tries / state_file_name / lock_file_name / state_file_size / control_path` 这些和 runtime 强绑定的配置都从 `base.mbt` 挪回了 `runtime.mbt` 文件头，让 `base` 不再替 runtime 挂配置。
15. 最后又看了一次 `retain_state_file_ffi / release_state_file_ffi` 这条线。当前代码已经把直接访问 lock 文件路径的逻辑收进了 `Lock::retain()`，但用户指出这层语义和 `Lock.file` 自己的持有是重复的。现在这块已经先被用户手动注释，当前结论是：仓库里还没有测试能证明这套额外 hold 必要，后面应该继续朝“只保留一套 lock 持有语义”收。
16. 当前验证状态是：`moon check --target native -p service` 已经能过。剩下没有红错，只有少量 warning。当前最值得继续确认的不是编译，而是 `retain/release_state_file_ffi` 这层额外持有到底要不要彻底删。
## 04-16 晚上
1. 先把 `service/protocol` 从旧 `bridge:*` 口径收成新协议。请求只保留 `hello / ping / query / dispatch / spawn / close`。响应只保留 `HelloAck / Query / Spawn / Pong / Ok / Err`。
2. 随后把 HTTP 控制口里那层旧 `Response` 壳删掉。`HttpConn` 这边直接回字符串结果和 `HttpRes`。不再保留多余包一层的 `Response::send_http`。
3. 然后把 `protocol` 里的 JSON 解码重复逻辑收了一轮。最后定成 `JsonObj` + `get(key)` 这条主路径。没有继续保留临时桥函数和多余 helper。
4. 接着把 `json` 相关名字通过 `using` 解到包作用域。把活代码里的一批 `@json.from_json / @json.parse / JsonPath / JsonDecodeError` 前缀去掉，收回统一口径。
5. 之后补了 `src` 侧的协议编解码。给 `DomEvent` 写了 `FromJson`。同时把 `NodeQuery` 的 `FromJson` 也收成 `pub impl`，让 `service` 可以直接吃到 `src` 的正式类型。
6. 在这个基础上，把 `service` 的四条 ws 主路径真接到 `src.Runtime`。`query` 直接调 `rt.query`。`dispatch` 直接调 `rt.dispatch`。`spawn` 直接调 `rt.spawn`。`close` 直接调 `rt.close`。
7. 然后重写了一轮 `src/bridge.js` 的协议层。ws 地址改成 `/_meta/ws`。`query / trigger` 改成新协议。`command` 改回 HTTP 控制口。旧的 `bridge:request / bridge:response / bridge:rejected` 这一套处理被清掉。
8. 中间做了一次最小烟测。首页能直接取到 `index.html`。ws 能握手。`HelloAck` 能收到。后面又修了一处实际协议形状误判：`ResMsg.body` 的 JSON 不是对象，是数组对。修完后浏览器桥才能正确认出 `HelloAck`。
9. 还补了一刀 service 侧首帧行为。浏览器 `hello` 成功后，现在会补发一轮初始 DOM batch。否则页面会一直空白，因为连接建立前那批命令已经发完了。
10. 最后又把最小 CLI 命令面补回来了。现在 `service` 入口重新支持 `start / stop / status` 三条命令，不再只认内部启动 flag。
11. 目前仍然没彻底收好的点在生命周期检测。实测 `start` 后页面和端口都已经起来，但 `status` 这条判断有时还会回“service is not running”。说明 CLI 分发已经接上，问题还留在 `detect / status / stop` 依赖的 state/lock/pid 判断这条线上。
12. 当前明确验证过的结果有三条。`moon check --target=native -p service` 能过。`bridge.js` 的语法检查能过。最小 HTTP + ws 烟测能拿到首页、`HelloAck` 和首批 DOM batch。
## 04-17 上午
1. 先排了 `test-all` 的生命周期分支。确认最早的问题在 service CLI。`--state-dir` 被当成命令名。先把 CLI 参数解析修正了。
2. 接着继续追生命周期失败。把 `start()` 里的启动探测收成“单次探测失败继续轮询，超时再报错”。生命周期测试随后转绿。
3. 然后排了“服务启动后页面空白”。抓了 ws 首帧。确认 service 已经发了完整 DOM batch。问题在浏览器桥接把运行时根节点 id 认错了，导致插到 `body/head` 的命令全被丢掉。修完后页面能正常显示。
4. 随后把 ws 协议里的 `spawn/close` 删掉了。只保留 `hello/query/dispatch/ping` 这条桥接主路径。
5. 接着把浏览器测试整体收了一轮。旧 `e2e` 里那批依赖 `roots/sync` 和旧 fake 事件发包口径的测试都删掉了。`bridge.test.js` 重写成只测当前 `bridge.js`：真实 ws 下的 `query/dispatch`，以及 fake bridge 下的 `apply/queryById/triggerById` 和本地事件行为。
6. 在这个基础上重新跑了 `test-all`。当时 core/native/lifecycle/browser 四支都过了。
7. 后面又回头看了 `hello`。确认之前 `HelloAck` 之后直接 `self.reset(self.root)` 是错的。它不是补发现有界面，是真重建了一份 runtime。
8. 随后在 `src` 补了 `Dom::replay()` 和 `Runtime::replay()`。把 `hello` 改成 `HelloAck` 之后只给当前连接补发现有 runtime 的 `DomCmd`。不再在握手阶段重建 runtime。
9. 同时补了一条 `src/runtime.test`。锁住“dispatch 改过的当前状态能被 replay 出来”。重新跑 `test-all` 继续全绿。
10. 接着把 `runtime.mbt` 最下面那段 CLI 收成了薄 `CLI` 类型。`main` 继续保留，只把参数解析和命令分发挂到 `CLI` 上。
11. 再往下把 CLI 参数解析正式收成 `CLIArgs::parse`。现在会解析 `subcmd/rest/flags`，也会拒绝未知 flag、重复 flag、缺值 flag。因为生命周期脚本还会传 `--silent`，所以把它也加进白名单了。`test-all` 继续全绿。
12. 之后按讨论补了一版 `repl`。当前这版已经能通过 ws 连接 service，把输入命令复用到现有 `CLIArgs::parse/CLI::exec` 上执行，并且会拒绝在 repl 会话里再次执行 `repl`。同时把字符串拆分提升成了 `CLIArgs::split`，删掉了原来局部的 `split_shell_args`。这一步之后 `test-all` 仍然是全绿。
13. 目前还没收净的点有两个。`repl` 这条线上仍然有重复执行入口。`Conn.role` 被我改成了 `mut`，而 `pending` 这套机制实际上没用上。这两处只是先把语义跑通，还没进一步收短。 
## 04-17 下午
1. 先把 service 里原来走 `/_meta/command` 的控制面往 ws 收。
2. `status / stop / start` 这条生命周期控制改成通过 `Client(ws)` 发 `cli` 命令，不再走 HTTP command。
3. `service/protocol` 里把浏览器和 CLI 共用的 ws 协议继续收短，`exec` 这一类命令口径最后统一改成了 `cli`。
4. 浏览器桥接这边也一起跟着改。`bridge.js` 里的 `command` 改名成了 `cli`。`trigger` 改名成了 `dispatch`。对应测试脚本调用也一起对齐。
5. `scripts/test-browser.js` 里的停服务路径也收了。正式收尾现在优先走页面里的 `mbt_bridge.cli('stop')`，不再默认直接本地起一个 service CLI 去停。
6. 同一轮里还把 `Client` 这层的组织继续收了一下。把一些散在外面的 ws helper 收回到 `Client` 上，最后变成统一的 `Client::connect(port)`、`Client::cli(cmd)`、`Client::exec(port, cmd)` 这套形状。
7. 过程中还顺手清掉了一些我自己加出来的无关编码壳。比如一度把 query / dispatch 的 json encode/decode 临时写在 service 本地，后面已经收回去，重新走类型自己的 codec。
8. 接着开始处理 `test-all`。原来的 PowerShell 并发脚本在失败场景下会长时间挂着不退，而且看不清失败分支。这里后来直接改成了 JS 主逻辑，`test-all.ps1` 只保留一个薄 wrapper。
9. JS 版 `test-all` 里加了总的 10 秒全杀逻辑。目的是一旦整体超过 10 秒，就直接终止所有还在跑的分支，避免像之前那样失败后继续长时间挂住。
10. 当前确认的现象是：`core` 过，`native` 过，`lifecycle` 过；单独跑 `browser-test` 用户那边看到也是正常结束，耗时大约 2 秒。
11. 但挂到新的 `test-all` 并发里时，整体还是会打到 10 秒超时。说明现在真正没收清的是：到底是 `browser` 分支在并发场景下没退，还是 `test-all.js` 没把已经退出的 `browser` 子进程正确收掉。
12. 这件事目前没有彻底解决。我这边在定位上反复横跳，先后在 `test-all` 和 `browser-test` 两边都动过手，浪费了时间。最终还没把“超时根因”明确钉死。
1. 先顺着 `service/protocol` 解释了 `Req::Cli(String)` 和整条 ws 请求对象的错位。确认 `cli` 当前能跑，是靠手动 `obj.get("cmd")` 把类型错位补回来的。
2. 随后按用户的要求给 lifecycle 补了启动后的 `query` 检查。先查桌面 `entries/0/name`。结果把 `NodeQuery` 编码和解码口径不一致的问题打了出来。
3. 接着把 `NodeQuery` 收成正式派生 JSON 形状。CLI `query` 也改成先组 `raw`，再做 typed 校验，发包继续直接走 `raw`。相关测试口径一起改了。
4. 然后继续给 lifecycle 补 `dispatch` 检查。流程是启动后先 `query`，再 `dispatch entries/0/entry`，再查 `windows/0/title`。这一步把 `dispatch` CLI 里“先解事件再 `to_json` 重编码”的错位打了出来。
5. 之后把 `service/runtime` 里的 `CLI::dispatch` 收成和 `query` 一致的写法。先保留 `raw`。再做 `DomEvent` 类型校验。真正发包继续直接发 `raw`。没有再改 `src` 协议。
6. lifecycle 脚本这边也收了一轮重复。把三段相同的启动后检查压成 helper。现在 `start / start again / restart` 都共用一套 UI 验证。
7. 再往下把 `src/protocol` 里事件这组 JSON codec 继续收短。`EventKind`、`Modify`、`BaseEvent`、`MouseEvent`、`KeyEvent`、`InputEvent`、`DomEvent` 都改成直接走 `derive(FromJson, ToJson)`。`bridge.js` 和 lifecycle 里的事件 JSON 一起改成派生形状。
8. 同一笔里把 `Listener::ToJson` 也收成和派生风格一致的数组形状。`bridge.js` 的事件 prop 解析同步改成吃这套 `[kind, cfg]` 结构。
9. 然后按讨论把 JS 侧“listener 是独立命令”的残留清掉了。删掉了没在用的 `LISTEN` 命令。事件注册逻辑并回 `PROP`。命名也改成了普通 event prop 视角。
10. 最后把 `EventKind::to_string()` 改成直接给 prop 名。现在返回的是 `onclick`、`onkeydown` 这类字符串。`domcmd`、`dispatch` 查找、listener 展示都一起对齐成这套口径，不再混着用事件名和 prop 名。
11. 在这个基础上把 `bridge.js` 里的事件注册逻辑继续压回最小。删掉了事件注册表、`addEventListener/removeEventListener` 那一套，正式改成 `node.onclick = handler` 这种直接赋值。handler 里只保留 `preventDefault` 和 `stopPropagation`。
12. 最后整轮清掉了 `bridge.js` 里整块白盒和平行测试入口。删掉了 `bridgeTest`、`connectFake`、`queryById`、`triggerById`，以及它们依赖的本地 DOM 快照、fake pointer/drag/input 辅助。`e2e/bridge.test.js` 里对应的白盒段也整块删掉，只保留正式 ws bridge 的 `query/dispatch` 两条用例。
13. 这轮审 `bridge.js` 时还额外看出一个没动的遗留点：正式 `mbt_bridge.query(...)` 还在发旧 `NodeQuery` JSON 形状，当前测试没有覆盖到这条断口，所以这件事还没处理。
1. 先把 `scripts/test-browser.js` 接成最小测试框架。它现在能跑 `e2e/*.js`，支持 `describe / beforeAll / it / expect`。
2. 接着补了浏览器测试运行入口。它会优先找本机 Chrome/Edge，没有就提示先装 `chromium`。
3. 然后把 `src/bridge.js` 的公开 API 对齐。`query` 改成当前协议形状，`reset` 改成带 root 的命令，`setStatusListener` 删掉了。
4. 同步把 `service/runtime.mbt` 补成支持 `reset`。它现在会按 root 重建 `src.Runtime`。
5. 接着把 bridge 的几个主 API 都补上测试。`status / query / dispatch / cli / reset` 现在都有覆盖。
6. 之后开始看 `test-all` 和 browser runner 的计时。先加了分支时长，再加了 browser 内部阶段时长。
7. 又把 browser 的细则计时收短。普通跑只留总时间，细则改成单独的 `verboseTiming`。
8. 接着查 `browser native events` 为什么慢。最后把 `page.dblclick` 去掉，改成统一走 `dispatch`。
9. 这一步后，`browser native events` 的耗时明显降下来。
10. 然后排 `lifecycle` 变慢的原因。发现 `stop` 这条 ws 命令没有真的停到服务进程。
11. 之后把 `service/protocol.mbt` 里的 `Cli(stop)` 改成真正的停机信号。`lifecycle` 的停机等待明显缩短。
12. 再往后把 browser 和 lifecycle 的细则计时都收进单独开关。普通 `DebugTiming` 只保留总时长。
13. 期间还把 browser runner 的时间口径统一到 `performance.now()`。这样所有时间都能跟同一个起点对账。
14. 之后又补了 `beforeExit` 侧的空转计时。确认 browser 测试本体结束后，进程还会再挂一段时间。
15. 最后把 `test-all` 的分支调度和输出都理了一遍。现在分支总时长、browser 总时长、browser 细则都能分别看，且 `test-all` 保持全绿。
## 04-17 晚上
1. 把构建/测试入口从 `ps1` 迁到 `js`，根目录入口搬进 `scripts/`，并接到 `package.json`，后面统一走 `npm run`。
2. 把 `build-native`、`count-core-code`、`test-service-lifecycle` 这些名字收短，分别改成 `build`、`count-code`、`test-lifecycle`，同时删掉 `profile-startup`、`test-host` 这些临时或窄用途入口。
3. 处理了 Windows 下 `npm run test` 拉不进 VS 环境的问题，修正了 `VsDevCmd.bat` 的调用方式，让 native 分支能正常导入编译环境。
4. 在 WSL 里验证了 `npm run build` 和 `npm run test`，Linux 路径当前能跑通。
5. 把 `CMD::new` 改成可注入 `Runtime` 的形式，`serve_ws` 直接把外层 runtime 传进去，这样 `stop_local` 操作的是服务本体那份 runtime，不再额外造一层。
6. 处理了 `reset` 缺完成信号的问题，让浏览器侧 `reset` 走请求-响应，测试不再靠长轮询猜完成。
7. 把 service 侧 `flush` 语义收成“发空当前队列”，删掉了并行的 `flush_all` 概念，协议层现在统一在响应前把当前待发包清掉。
8. `Conn::flush` 里前两行阻塞取首包的逻辑已经确认是冗余的，删掉了。
1. 先给根目录补了 `run.ps1` 和 `run.sh`。约定用法统一成 `run <scripts 下脚本名去掉 .js> [...参数]`。目标是绕开 `npm run` 那层参数处理，让参数能直接穿透到 `scripts/*.js`。
2. 随后给 `service` 里的 `CMD` 补了 `help`。同时接上了 `help` 子命令和 `--help` 入口。对应 service 测试也一起补了。
3. 接着发现 `./run meta help` 没有输出。排查后确认不是参数没透传，而是 `meta` 复用了 `_build` 里的旧 `service.exe`。Windows 下可执行文件被占用后，`meta` 会继续跑旧二进制。
4. 为了把这个问题压掉，把 `scripts/meta.js` 改成单独走 `_build_meta`。这样 `meta` 自己的构建产物和常驻 service 不再抢同一个 `service.exe`。之后 `meta help` 和 `meta --help` 都能正常输出。
5. 然后把 `service` 所有 CLI 返回值末尾自带的换行收掉了。`status / start / stop / reset / query / dispatch / help` 这些命令现在都返回纯内容。真正的换行只留给 `main` 那一层打印。对应测试也补了无尾部换行检查。
6. 接着按用户的要求把脚本执行入口整理成一套。中间我先多加了几层 helper，用户指出这不对。之后把同步执行统一收成 `exec` 一个名字，旧的 `cmd / runCommandSync / readCommandSync` 都删掉了。
7. 在这一步里，又继续把 `exec` 的默认配置收短。默认改成当前工作目录加 `inherit`。只有确实要读输出、忽略输出、传自定义 `env`、限时、改 `maxBuffer` 的地方，才显式把这些非默认值写出来。
8. 同时把剩下还没对齐的脚本继续收到了同一条口径上。`mide.js`、`test-all.js`、`test-browser.js`、`test-lifecycle.js` 都改成走 `exec` 或 `exec.start`。脚本目录里不再直接散着用 `execFileSync / spawnSync / spawn`，这些只留在 `common.js` 里做底层实现。
9. 随后围着“导入 VS 环境到当前 PowerShell”做了一轮来回试。先试过把逻辑写进 `run.ps1`，用户要求撤掉。之后又试过 `import-vs-env.js` 配合 `ps1` 包装，再试过直接走官方 `Launch-VsDevShell.ps1`。这条路会把当前会话带进新的开发 shell，还会改当前目录，判断不合适。
10. 最后把这件事收成单个纯 `scripts/import-vs-env.ps1`。它现在走 `cmd /c "call VsDevCmd.bat ... && set"` 拿环境，再逐条回写到当前 PowerShell 的 `$env:`。实测确认它不会切目录，也不会进新的 shell，只会把 `VSCMD_VER / CC / METAEDITOR_VSDEV_IMPORTED` 这类变量留在当前命令行里。
1. 先看了 `e2e` 的 bridge 测试，确认当时的 `reset` 用例只测了 reset 后还能查到默认内容，没有测“页面内容确实发生变化”。
2. 接着按用户的提醒去看 `demo` 的实际内容，确认 `reset('demo')` 后真正该断言的是 `demo-body = Demo app`。
3. 随后把 `e2e/bridge.test.js` 的 reset 用例改成按 `demo` 断言，并确认 host 那套 `entries` 查询在 reset 到 `demo` 后应该消失。
4. 然后用户指出测试入口已经变成 `./run test-all`，我把 `AGENTS.md` 里的测试入口口径改成了新命令，并重新用这个入口验证。
5. 接着开始看 `host` 的实现，确认当前桌面 entry 是手写清单，窗口区和样式也都还是最小形态。
6. 之后用户指出 entry 列表不该在 `host` 里手填，应该直接从 runtime 拿真实注册表。我先把 `runtime.test.mbt` 里的 host 用例拆到了新的 `host.test.mbt`，把 host 语义从 runtime 基础测试里分出去。
7. 随后把 runtime 的 entry 注册表收成正式枚举接口，`host` 改成直接吃 runtime 的真实 entry 列表，同时把 `host` 自己也纳入桌面 entry。
8. 再往下把 `host` 的桌面布局改成桌面 icon + 窗口区的形状，并给 `host.test.mbt` 补了“桌面列出 demo 和 host”“host 能开 host 窗口”的覆盖。
9. 这一步之后用户反馈实际页面还是无法开窗。我先修过一次层级，把 `windows-wrap` 的透明覆盖层改成不吃桌面点击，窗口本体再恢复交互。
10. 但真实页面还是点不开，所以继续补了 Playwright 的真实点击测试，不再只靠 bridge 的 path dispatch。
11. 真实点击测试把问题钉出来以后，我临时抓了浏览器里的真实 DOM，确认桌面按钮其实已经画出来了，问题不在“没渲染 entry”，而在“真实浏览器事件没有走回 runtime”。
12. 接着排到 `bridge.js` 的事件桥接，确认当时浏览器原生 `onclick` 只做了 `prevent/stop`，没有把事件回发到 runtime，所以真实点击不会开窗。
13. 然后先补了一版浏览器原生事件回发，最初是把它翻成正式 `dispatch(path, event)`，让真实点击和外部 dispatch 共用一条主路径。
14. 在这条链跑通以后，又查出更深的问题：点击后 query 结果会变，但页面没有画出窗口。继续排后确认 `src.Runtime` 只有初始化时会把 `DomCmd` 发出去，后续 `dispatch` 没有把增量命令推出去。
15. 随后给 `src.Runtime` 补了待发命令队列和 `emit`，让初始化和后续 dispatch 都会真正把本轮 `DomCmd` 推出去。
16. 这一步又带出 service 侧的新断口：CLI client 也收到了 DOM batch，导致 lifecycle 脚本等响应时会先吃到数组包。我把 service 侧 DOM batch 收成只发给 Browser 连接，不再发给 Client 连接。
17. 接着又排到多开 Demo 再关时报 `windows/2/close` 的问题。确认这不是 close 本身坏了，而是窗口列表复用节点后，close listener 还挂着旧 path。
18. 为了先把这个错误压住，我把 `host` 的窗口列表改成按当前索引重建的动态列表，让 close listener path 跟着当前索引重算。
19. 同一阶段又看出 `bridge.reset()` 的顺序也有问题。它之前是等 reset 响应回来后再清 DOM，会把刚补发回来的新页面一起清掉。随后改成先清旧 DOM，再发 reset 请求。
20. 然后继续整理浏览器测试，把 `bridge.test.js` 里的 host 测试整体抽到了新的 `host.test.js`，`bridge.test.js` 只保留 bridge 自己的连接状态、CLI 和 reset 语义。
21. 再往后用户指出更深的边界问题：浏览器原生事件继续走正式 `dispatch(path, ...)` 是错的，因为这会把“已经命中真实 DOM 节点的事件”错误抬成正式 path 控制面。缺的是一条只给 bridge 用的低级 `trigger(node_id, event)`。
22. 随后按这个边界重做：`Listener` 不再带 `path`，改成带当前 `node id`；`src` 和 `service` 补了 bridge-only 的 `trigger(node_id, event)`；`bridge.js` 的原生事件改走这条低级触发，不再回翻成 `dispatch(path, ...)`。
23. 同一步也把 browser harness 的点击翻译层重做了。测试里继续写 `dispatch({ path, kind: 'click' })`，内部改成 `path -> query(node) -> node id -> 页面坐标 -> Playwright 真实点击`，去掉了靠 `class` 猜 selector 的 `pathSelector` 做法。
24. 之后用户指出 `Dom::node(id)` 每次全量遍历也不对。我把它改成 `Dom` 内部维护 `id -> Node` 的表，节点创建时注册，节点移除时整棵子树一起清理。
25. 用户随后又要求把 `register/unregister` 这种 helper 删掉，所以我把节点表维护直接内联回 `Node::new` 和 `Node::remove`。
26. 最后用户手动把 `Listener::ToJson` 收成了 tuple 版本，当前代码口径已经是 `(self.kind, self.cfg, self.id).to_json()`。
1. 先补了 `EventCfg.capture`，并把 `src/bridge.js` 的事件绑定收成支持 `setPointerCapture/releasePointerCapture`。
2. 接着加了 bridge 侧真实测试，用 `pointer-capture` 入口验证按下后移出节点，`pointermove/pointerup` 仍能回到同一目标。
3. 然后把这个测试入口从 `src/host.mbt` 挪到新文件 `src/misc_entry.mbt`，`host` 只保留桌面主逻辑。
4. 随后把 `host` 的窗口拖拽接起来。窗口位置改成响应式状态，标题栏接 `pointerdown/move/up`，拖动时更新 `x/y`。
5. 过程中把窗口测试、浏览器测试、lifecycle 脚本里写死的 entry 顺序假设都清掉了，改成按实际注册内容找目标。
6. 最后补齐并跑通了 `./run test-all`，确认 host 拖拽、bridge capture、双 browser 广播和 lifecycle 都维持全绿。
1. 先查了 `src/host` 双击 Demo 报 `duplicate ui id: title` 的根因，确认窗口区还在用普通 `Dyn + Arr`，多开时会把同名节点塞进同一作用域。
2. 顺手把桌面滚动问题一起收了。桌面改成跟随宿主窗口尺寸，不再靠页面自身滚动，窗口内容区自己滚。
3. 接着补了 `host` 的回归测试，锁住连续打开多个 Demo 窗口后仍能查询到各自标题。
4. 然后排了 service 到多个 browser 的同步延迟，确认是 DOM batch 只在当前请求连接上及时 flush，其他 browser 要等下一次自己的请求才会把积压队列发出去。
5. 先试过把“刷新所有 browser”单独做成一个入口，后面按你的要求收回，改成只保留一条 `flush`，把所有 browser 的队列一起冲掉。
6. 之后开始给拖拽铺底层能力，补了 `EventCfg.capture`，并把 `bridge.js` 事件绑定从属性赋值收成 `addEventListener / removeEventListener`，让 capture 真的有落点。
7. 你提醒还缺测试后，又补了 bridge 侧真实用例，验证 `pointerdown(capture=true)` 后鼠标移出节点，`pointermove / pointerup` 仍然能回到同一节点。
8. 你要求把那个测试入口从 `host` 挪走，于是新建了 `misc_entry.mbt`，把 `pointer_capture` 入口独立出去，`host` 文件只保留桌面主逻辑。
9. 这一步把 entry 注册顺序也扰动了，所以把 `host.test.mbt`、`e2e/host.test.js`、`scripts/test-lifecycle.js` 里写死的 `entries/0`、`entries/1` 逐个收掉，改成直接看注册表里有没有目标 id，或者直接按标题找对应路径。
10. 你指出不该为了这事再搞一层 helper，我把测试里那套扫描 path 的逻辑继续压短，最终改成直接看注册表里的 entry id，不再绕 `entries/*` 查标题。
11. 随后开始真正做窗口拖拽。先把 `Window` 增成带位置状态，再把标题栏接成拖拽手柄，窗口改成绝对定位，拖动时更新 `x/y`。
12. 你提醒写法上可以更像 JS 的 `drag(e, m, up)`，于是我把拖拽收成 helper，临时挂 `pointermove / pointerup / pointercancel`，闭包里自己持有拖拽状态和收尾逻辑。
13. 你继续指出还缺一个显式的底层能力：事件对象要有 `current_target()`，目标句柄要有 `on / off / set_pointer_capture / release_pointer_capture`。我先确认了现有 `derive(ToJson)` 的边界，再往 MBT 里补这层。
14. 然后给事件模型补了 `MouseEvent.pointer_id`，`DomEvent.current_target()`，以及 `Node::on / off / set_pointer_capture / release_pointer_capture` 这组 API，桥接侧也把 `pointerId` 带进了 `mouseDispatch`。
15. 这批改动引出了一轮编译和测试收口。我把 `dom`、`runtime`、`host` 相关测试里的旧 `Mouse(...)` 构造都补上了 `pointer_id`，再补了 `current_target()` 的最小测试，确认事件上下文能拿到当前监听节点。
16. 你后来又追问 `drag` helper 的写法是不是还不够像你那段 JS，我把 `host` 里的拖拽再收了一次，让它更接近“`pointerdown` 里起临时 `move/up/cancel` 监听”的形状。
17. 接着你要求把 `current_target` 直接用 node id 也行、函数字段序列化要和 `derive(ToJson)` 对齐，我就把事件对象和句柄的最小形状继续往前推进，避免把协议形状弄脏。
18. 这轮里还把 `PointerCancel` 也补进了事件链和测试，拖拽收尾不再只靠 `pointerup`。
19. 你让我把 `pointer_capture` 从 `host` 文件里拆出去，我把它独立成 `misc_entry.mbt`，并把注册初始化改成由这个新文件负责。
20. 最后把整套拖拽和 capture 相关测试、runtime 测试、browser 测试都跑了一遍，`test-all` 回到全绿。
## 04-18 上午
1. 解决 codex 用不了的问题, 换了个中转
2. 把昨天晚上没改完的事件系统改造做完了
## 04-18 下午
1. 创建了 text-editor.mbt, 写了基本结构
2. 发现两个 dom api 能力缺口: 一是 PointerEvent 里只有全局绝对坐标, 没有 clientX/Y; 二是没有 Focus Domcmd
3. 现在都补上了, 期间还发现一个用 pointerup 事件送到 service 来之后偶尔还会有 pointermove 事件送到的问题
4. 这说明现在的浏览器事件的发送没有强有力的顺序保证, 目前先用一个猴子补丁把报错堵住了, 但后面还要来修复这个问题
## 04-18 晚上
1. 把浏览器端的 js 也改成了 mbt 包, 公用的协议类型抽出来放在 shared 包里, 现在协议本身可以通过类型错误直接传导到 browser 包接过了主入口
2. 注意到浏览器里 js 和 mbt 的边界只能通过 json 序列化反序列化进行, 不知道是语言限制还是用法问题
## 04-19 上午
1.
## 04-19 下午
## 04-19 晚上
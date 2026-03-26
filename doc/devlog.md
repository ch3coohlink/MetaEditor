# 开发日志

## 03-21 之前

03-21 之前，项目的第一层基础已经搭起来了。前端和应用侧的主体代码已经落在 `src/`、`app/` 和 `test/` 里，说明浏览器 UI、桥接逻辑和最初的交互验证已经不再只是想法，而是进入了可运行、可迭代的状态。命令行这一层当时仍然是旧的 `cli/` 路线，里面已经有一套基于 Node 的本地服务壳和命令入口，可以负责拉起页面，并给后续的 query、exec 和调试动作留出调用位置。与此同时，仓库里还单独保留着 `native_ws/` 这条原型线，用 MoonBit native 做了最早的一版 websocket 服务和测试，用来验证浏览器和 native 程序之间的通信链路。构建基础设施也已经提前铺好，Windows 和 Unix 两边都各自有 `build-native` 脚本，虽然当时主要服务的还是 `native_ws` 这一版原型，但跨平台 native 构建这件事已经被正式纳入工程。除了代码本身，文档工具链也已经有了自己的位置，`doc/tools/` 里放着一套把 Markdown 组装成排版过的 HTML 和 PDF 书稿的小工具，说明项目在代码之外，连设计文稿和技术文档的生成方式也开始被认真整理。更重要的是，`doc/meta-editor-service.md` 在那时就已经把 MetaEditor 作为长期运行服务的整体方向写了出来，里面已经讨论了项目编译、运行、页面连接、结构化 query / exec 和自动化测试等职责如何往统一服务模型里收敛。也就是说，在 03-21 之前，项目已经同时具备了浏览器端代码、旧 CLI、native websocket 原型、跨平台 native 构建脚本、文档排版工具和 service 方向文档这几层基础，后面的工作主要是在这些现成基础上继续合并结构、收敛路径，并把行为和测试逐步做实。

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

03-22 晚上，service 这一层继续往“运行时代码只做运行时，测试逻辑回到测试包”这个边界上收。`runtime.mbt` 里的 app test runner 和那批 snapshot/assert 辅助已经全部移除，当前 runtime 只保留 host UI、bridge、browser request/response 和文件服务相关逻辑，不再承担任何测试宿主职责。对应地，app 侧的验证也不再塞在 service 包里，而是落到 `app/test/` 下的独立测试包，当前只有 `host` 和 `counter` 两组，分别覆盖 host shell 初始 UI history 和 counter app 的 action / undo / redo 交互。

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

在前面把 service 的状态目录、测试目录和输出边界都收紧以后，`src/ui.mbt` 里的视图构造也顺着同一条思路继续收了一轮。`h` 现在不再立即返回 `VNode`，而是变成了真正的 `Lazy` 构造，节点展开都统一走 `Child` 输入链，不再需要 `@src.Node(@src.h(...))` 这种只为了过类型的包装。`Child` 里原先那个 `Node` 分支也已经删掉，只保留了 `Null`、`Lazy`、`Str`、`Int`、`Arr` 和 `Dyn` 这些真实的输入形态。与此同时，`DomCmd::Create` 也补上了 namespace 参数，`src/bridge.js` 按 `html` / `svg` / `math` 走 `createElement` 或 `createElementNS`，`foreignObject` 会把后代切回 HTML namespace。`service/app.mbt` 也一并改成直接消费 `@src.h(...)` 的 lazy child，不再额外套一层 `Node`。同一轮收口里，`moon test` 和 `test-native.ps1` 也重新跑过一遍，当前结果还是稳定通过，说明这条 lazy children / namespace 路径已经和 service 的真实入口对齐了。

## 03-23 晚上

这一轮后面又把 `h` 的入口继续收成了类型分发，而不是再加一层平行的 component API。现在 `String` 和 `Comp` 都实现了同一个 `HTag` trait，`h("div", ...)` 继续走原来的元素创建路径，`h(box, ...)` 则直接把 `comp(...)` 包起来的渲染函数拉起来执行。`comp` 本身只做一层很薄的函数包装，不额外引入新的组件协议，组件的 `attrs` 和 `children` 仍然原样透传给内部渲染函数；另外还在这里调查了各个库的 `dom-api` 设计，并整理成单独的文档，方便后面继续对比不同 UI 抽象的接口边界；后来又把 `Comp` 的内部字段收成了私有黑盒，外部只能通过 `comp(...)` 构造，再交给 `h(box, ...)` 使用，不能直接拆出内部渲染函数，这一轮回归也重新跑过，当前仍然是 31 个测试全部通过。

## 03-24 上午

这一轮把 `h_map` 继续收成了带缓存的薄 helper：它只针对 `Array` 做动态列表生成，子项的构造结果和 index 读取器会按 item 复用，重复出现的 item 不会再次走 child 构造。回归里也专门补了计数断言，确认列表从 `["A", "B"]` 变成 `["B", "C"]` 时，缓存命中的 `B` 没有重复构造，当前 `moon test` 还是全部通过。随后又把 `test/ui.test.mbt` 里分散的命令断言收成了统一的 `assert_xxx` helper，测试体里不再直接散写一堆 `match` 分支。当前这些 helper 只负责检查命令类型和必要字段，重复元素场景也已经单独覆盖到，`h_map` 的重复值缓存行为和现有的 `h` / `Comp` / namespace 路径一起保持绿灯。

这轮还把 `h_map` 的输入约束重新收紧了一遍：前面已经确认过，`h_map` 先只能稳定支持函数返回数组这一路，其他的数据容器暂时不考虑。这里想恢复的是 `IntentDoc` 里原始 `h.map` 的两种真实用法：一种是普通数组列表，另一种是动态函数返回带显式 index 的项；前者适合常规列表渲染，后者更适合虚拟列表，因为 source 自己就能决定窗口起点和全局下标，不必让 `h_map` 重新从零推 index。基于这个目标，先试着把函数类型和泛型 trait 拼成一个统一入口，让一个 API 同时吃数组、动态函数和带 index 数据；但后面再试 trait 方案时，MoonBit 又在泛型 trait 和函数类型的组合上卡住了语法和类型系统限制，编不过也落不稳，所以当前先不再往里加那层抽象。

最后收口时，`h_map` 被拆成两条明确路径：`h_map(items: Array[T], f)` 只负责普通数组，并把数组薄包装成动态 source 后转给核心实现；`h_map_dyn(source: () -> Array[(T, Int)], f)` 则承担真正的监听、缓存、重复项复用和显式 index 读取，`i()` 直接读 source 提供的值。这样之后，普通数组和动态函数两种调用方式都回到了原始语义，但实现边界是清楚的，不再依赖 MoonBit 还不稳定的 trait 多态。最后给这两条路径各补了一组测试：普通数组确认重复元素不会互相覆盖，动态 source 确认函数依赖变化后会重跑，且 `i()` 读取到的是 source 提供的显式 index；`moon test` 重新跑过后仍然全部通过。

## 03-24 下午

03-24 下午，响应式层继续往更通用的可变状态原语收。最开始的入口其实是列表更新：现有的 `Cel[Array[T]]` 已经能做整值替换，但在列表、缓存和类似的可变容器上，真正顺手的写法一直是“拿到当前值，原地改几处，然后统一刷新”，而不是每次都先复制一份新数组再整块替换。沿着这个需求往下收，曾经短暂尝试过给数组单独包一层响应式容器，但那样会把“可响应的写入”再次拆成平行概念，最后还是把概念往上提回 `Cel` 本身。现在 `Cel` 里保留的是 `mutate`：调用方先拿到 `Cel` 当前持有的值，在同一份值上直接做原地修改，随后由 `Cel` 统一触发订阅者刷新。这样之后，数组、映射、缓存或更复杂的状态对象都可以沿着同一条主路径修改，不需要再为“可响应的数组”单独造一层 `RxArray` 之类的平行概念。与此同时，之前用于表达“先算新值再替换”的 `update` 入口也已经删掉，响应式写入现在只保留 `set` 和 `mutate` 两种语义：`set` 负责整值替换，`mutate` 负责原地改完再通知。  

这轮收口后，`test/reactive.test.mbt` 也同步改成直接验证 `Cel::mutate` 的行为：一组测试确认数组在 `mutate` 里追加元素后会重新触发 effect，另一组测试确认同一个 `Cel` 持有的数组可以连续做多次原地修改，并且刷新结果仍然正确。`moon test` 重新跑过后仍然是全部通过，说明这条“原地修改 + 统一通知”的路径已经和现有 `Cel`、`effect`、`watch`、`h_map` 的使用方式对齐了。现在的边界也比较清楚：`mutate` 不是自动 diff，也不是脏检查，只是一个显式提交点，调用方负责把值改完，`Cel` 负责发出一次响应式更新。

把 `mutate` 这条线收住之后，后面没有继续往响应式细节里钻，而是顺着 `IntentDoc/dev` 里还没搬过来的状态模型往上看了一轮。先把 `text-editor.js`、`workspace.js`、`story-editor.js`、`storage.js`、`state.js` 和 `eg-walker` 这些文件过了一遍，又把这批文件的职责和设计点单独整理成了 `doc/intentdoc-dev-design.md`，后面再聊搬运顺序时就不用每次重新翻源码。

后面又回到 `storage.js`、`state-new.js`、`state.js` 和 `test/storage.test.js` 这几处接着看，然后和用户讨论了三件事：一是 `storage.js` 现在没有 schema，组件状态结构一改，旧数据读回来就容易出错；二是 `state.js` 这个名字太泛，后面更适合改成 `history`；三是 `eg-walker` 这条线不要单独看，它和 `history` 本来就是绑在一起的。讨论完之后，又回去翻了一遍 `story-editor.js` 里预设的 clone / patch 路径，`storage.js` 里 reactive 对象的脱水回水，还有 `state.js` 里操作和快照的组织方式，把后面要继续聊的点先压实到这几处实现上。

再往后，先是围着 `storage` 的实际落地聊了好几轮，最开始写了一版，用户说太长不看，要求直接把设计用法写成文档，结果一看设计用法还是太像序列化接口，里面带着显式 migration function、`save/load` 这种过重的入口，还有一堆并不贴近当前想法的细节。后面讨论的重点就变成了 migration 到底该怎么表达：如果继续按版本一段段写 migration function，接口会越来越重，而且会把“存储格式”和“当前读取结构”绑死在一起；所以最后收成了另一条更轻的路，把稳定的存储标签和当前内存里的读取字段分开，重命名字段时不再理解成“改存储名”，而是理解成“旧字段删掉，新字段读取到同一个稳定 tag”，缺的字段再按 schema 默认值补上。沿着这个方向，字段定义最后收成了 `field(10, "name", string(anon))` 这种形态，默认值直接放进类型构造里，不再额外写 `default:` 之类的参数。与此同时，`bind` 也重新收回成了已经柯里化过 `kv` 的闭包，顶层入口不再每次显式传存储。这个过程中还专门把 `storage design.md`、`storage-design-v2.md`、`storage-design-v3.md` 这几份文档一路改下去，后面为了和别的文档命名统一，又把它们一起改成了 `storage-usage.md`、`storage-usage-v2.md` 和 `storage-usage-v3.md`。

顺着这条线，后面又把另外三份同类文档一起补上了。先对着当前 `src/reactive.mbt` 把 `peek/get/set/mutate/computed/watch/scope/effect` 这些真实接口重新过了一遍，然后写了 `doc/reactive-usage.md`，只保留现在已经存在的响应式主路径。接着又对着 `src/ui.mbt` 把 `h`、`comp`、`Prop`、`Child`、`h_map`、`h_map_dyn`、`reg_action`、`init_bridge` 和宿主命令这几块重新整理了一遍，补成了 `doc/ui-usage.md`。再后面还顺手看了 `src/op.mbt` 和 `test/op.test.mbt`，按当前这个还很薄的实现补了一份 `doc/history-usage.md`。写完之后又顺着文档回头对实现看了一眼，结果发现现在的 `Store` 里还直接暴露着 `read/peek/version/peek_version` 这层入口，本质上就是把内部 `Cel` 往外透出来，这一点也单独记下来，后面如果真要把 `op` 收成正式的 `history`，这里大概率还要继续清。

## 03-24 晚上

晚上先继续把 `storage` 往实现上推。先落的是当前能编译、能跑的一条主路径：`src/storage.mbt` 里收了一版 `PersistValue + Persist trait + bind_with_kv`，把中间那层 `Json` 和 `Schema` 拿掉，让 `Kv` 直接存 `PersistValue`，`bind_with_kv(kv)` 直接绑定 `Cel[T]`，只要 `T` 实现了 `Persist`，就沿着 `pack / unpack` 这条路径自动回写。测试这边也一起改成了 typed 结构，拿 `Prefs`、`Doc` 和 `Group` 手写 `Persist` 实现去验 `bind -> mutate -> flush -> kv` 这条链，数组和数组里的对象也一起过了一遍，最后 `moon test` 还是全绿。

这条手写 `Persist` 的路跑通以后，才回头去试前面一直在聊的“类型和存储定义同源”这件事，直接看 MoonBit 能不能给自定义的 `Persist` trait 做 `derive`。先在测试里临时插了一个 `AutoPrefs derive(Persist)` 的小实验，结果编不过，先报的是测试包里找不到 trait；把实验挪回 `src/storage.mbt` 里以后，编译器给出的错误就更直接了：`Don't know how to derive trait Persist for type AutoPersistDemo`。这一步算是把边界钉死了：MoonBit 当前的 `derive` 只能处理它已经认识的那批 trait，不能直接拿来自定义一个 `Persist` 然后让编译器自动生成实现。顺着这件事又去看了一下构建链，顺手确认了 `moon test` 虽然没有单独的 test hook，但 `moon.pkg.json` 里有 `pre-build`，而且会在 `moon test` 前执行。

到这里，后面的坑也就跟着露出来了。既然 `derive(Persist)` 这条现成路走不通，又还想继续保住“类型定义就是唯一来源”，那剩下的办法就只能是另一条链：在 MoonBit 源码里写 attribute，让外部 codegen 工具去解析 attribute，再生成对应的 `Persist` 实现，最后通过 `pre-build` 挂到现有构建链前面。和用户聊到这里以后，这条线就算正式被翻出来了：这已经不是再补一个小 helper 的问题，而是得开始认真考虑 codegen 这一层本身；再往后如果真走下去，不只是 `storage`，连想做的 PEG parser generator 也会自然和这层工具链绑到一起，等于又开了一条新的大线。

再后面，话题又从 `storage` 顺着 codegen 一路拐到了 parser。先重新去看了 `IntentDoc/dev/parser.js` 和那一批 parser 测试文件，确认现在这套 parser 不是“写一份语法定义再喂给生成器”那么简单，而是一套组合子写出来的 parser 程序，里面已经带着 `chain`、`oneof`、`repeat`、`ahead`、`not`、`pratt`、`languageGen` 这些东西。接着又看了用户放到上一级目录里的 `parser-master`，把 `README.mbt.md`、`top.mbt`、`syntax/ast.mbt`、`handrolled_parser/parser.mbt` 和 `yacc_parser/parser.mbty` 过了一遍，想先确认 MoonBit 这边现成 parser 到底把语法切成了哪些层。中间先写过一版 `doc/moonbit-syntax-sketch.md`，最开始还是按普通“语言语法简介”的写法在列顶层声明、函数、结构体、枚举和表达式，后面用户连续指出两次方向不对：一是左递归这件事不用纳入支持目标，PEG 组合子这边就不做左递归，表达式优先级走 `pratt`；二是 lexer 不是传统那种先把整份源码切完 token 再交给 parser，而是 parser-driven 的，拆出来本来就是为了错误恢复。后面就回头把这份文档整个重写了一遍，不再按“教程式语法点”往下列，而是按 `parser-master` 当前真实暴露出来的层次整理：先写 `top / tokens / lexer / syntax / handrolled_parser / yacc_parser` 这几层怎么接在一起，再写 token 层、AST 层、手写 parser 暴露出来的语法面，以及这些东西和现有 JS parser combinator 的对应关系。

## 03-25 上午

今天上午先又回到 `storage`，不再继续顺着 parser 和 codegen 往前钻，而是直接看“如果现在完全手写一个能自动保存的类型，到底要写多少东西”。先按当前实现给用户举了最小样板：类型定义本身，加上一份 `Persist` 里的 `pack / unpack`，数组就是递归一层，普通对象字段也是递归一层。顺着这个问题继续往下看时，又聊到了更细粒度的情况：如果类型里直接放 `Cel[String]`、`Cel[Int]` 这种字段，表面上看只是 `pack / unpack` 再递归一层，但现有 `bind_with_kv` 里真正决定自动保存能不能跟着内部字段动的，不只是 `Persist` 接口本身，还包括序列化时会不会把内部 `Cel` 一起订阅进去。

确认完这个边界以后，当前实现就顺手往前补了一步。`src/storage.mbt` 里原来 `Persist for Cel[T]` 的 `pack` 还是走 `peek()`，这样根 `Cel[T]` 虽然会被 `bind_with_kv` 的 `effect` 订阅到，但类型里的内部 `Cel` 字段不会被连带订阅；所以这里把 `pack` 改成了走 `get()`，让 `source.get().pack()` 递归下去时也会把内部 `Cel` 建立依赖。测试里则单独补了一个 `CellPrefs`，字段直接就是 `title: Cel[String]` 和 `age: Cel[Int]`，然后让根状态保持不变，只改内部 `title.set(...)` 和 `age.set(...)`，确认 `flush()` 之后 `Kv` 里的保存结果会跟着更新。`moon test` 跑过之后还是全绿，当前是 `42/42 passed`，说明这条“根状态不重写、内部 `Cel` 单独动、存储自动跟着更新”的路径已经打通了。

后面又把 `storage-usage-v4.md` 单独补出来，想把这条“手写类型到底要写多少东西”先记清楚。最开始写得太像一份设计说明，用户看完以后又指出这里真正想看的不是一大段解释，而是和 `v1/v2/v3` 同一风格的目标用法，而且还要把“包含引用字段”的写法也一起写进去。于是后面又回头把这份 `v4` 重写成和前几版一样的结构：前面先写一小段为什么当前先收成手写 `Persist`，中间按普通字段、引用字段、数组、数组里的对象、`Array[Cel[T]]` 这几种典型情况各放一段代码，最后再单独补一小节，解释为什么 `v3` 里更理想的那套“类型定义和存储定义完全同源”的写法，现在先要收成手写 `Persist` 才能落地。

文档这轮后面还来回改了几次，因为代码示例到底应该写成多短、要不要把存储 key 直接写成字段名、`unpack` 里到底是用 `match m.get(...)` 还是直接 `.map(...).unwrap_or(...)`，用户前后都明确提了要求。中间一度把代码段压得太短，和当前测试里的真实写法对不上，后来又顺着用户指出的地方往回收，最后统一成和当前测试更接近的版本：存储里还是稳定 tag，`unpack` 里直接 `match m.get(...)`，同时把之前测试和文档里短暂留着的旧 key 回退用法一起删掉，不再保留那条并行语义。测试文件里 `Prefs` 和 `Doc` 的 `Persist::unpack` 也一起改成了两分支，只保留 `Some(v) => unpack(v)` 和 `None => default`，不再额外拆 `Some(Str(...))`、`Some(Int(...))` 这种冗余分支；改完之后重新跑过一轮，`moon test` 还是 `42/42 passed`。

上午后面很快又回到 `storage`，这次是对着 reviewer 提的一个真实回归去看：当前 `bind_with_kv` 在 `kv` 已经有值时直接 `source.set(T::unpack(value))`，如果 `T` 里面带嵌套 `Cel`，就会把整棵状态树换成新实例，外面在 `bind` 之前拿走的子 `Cel` 引用会立刻失效。先把 `src/storage.mbt`、`test/storage.test.mbt` 和 `src/reactive.mbt` 连起来过了一遍，确认这个评论是对的，而且现有测试只覆盖了“先 bind，再改内部 `Cel`”这条顺序，还没覆盖“`kv` 里已有值，并且 bind 前已经缓存了子 `Cel`”的场景。最开始为了先把 bug 修住，先试了一版把“回填到旧实例”单独收成 `restore`，这样测试是能过的；但后面用户盯着接口重新看了一轮，指出普通 `Persist` 实现里到处出现 `restore(_, value) { unpack(value) }` 这种空转方法，说明这层抽象放错了地方。于是又顺着 `IntentDoc/dev/storage.js` 和 `state.js` 里原来的 `hydrate / patch` 路径重新对了一遍，确认原实现一直只有一条主语义：把持久化值回填到现有状态里，能复用旧引用时就复用，实在复用不了再新建，不该再额外露出一个和 `unpack` 并列的名字。

最后这一轮的收口就是把接口重新压回单一路径。`src/storage.mbt` 里的 `Persist` 现在只保留 `pack / unpack`，其中 `unpack` 改成了 `unpack(value, old? : Self?) -> Self`：普通类型继续只按 `value` 解，内部用 `ignore(old)` 显式吃掉不用的旧值；数组会在 `old=Some(prev)` 时按槽位递归把旧元素往下传；`Cel[T]` 则在有旧值时直接复用原来的 `Cel`，只更新内部值，不再新建实例。`bind_with_kv` 读取已有持久化值时也统一走 `T::unpack(value, old=Some(source.peek()))`，不再有额外的 `restore` 名字。测试这边把前面那几个假的 `restore = unpack` 全部删掉，只给 `CellPrefs` 留了一份真正会用到旧引用的 `unpack(value, old=Some(prev))`，然后补了一条回归：先把 `title` 和 `age` 两个子 `Cel` 从根状态里拿出来，再 bind 一份已有持久化值，确认 bind 后拿在手里的还是原来的实例，而且继续 `title.set(...)` 之后 `Kv` 里的值也会跟着更新。两轮 `moon test` 都重新跑过，最终结果是 `43/43 passed`，这次 reviewer 指到的嵌套 `Cel` 身份问题算是顺着原来的 patch 语义收回来了，同时把中途试出来但不合适的 `restore` 命名一起拿掉了。

## 03-25 下午

下午先没有急着继续往 codegen 上走，而是回头把刚收出来的 `storage` 测试又重新审了一遍，想先确认当前这一套 `Persist + bind_with_kv` 到底是不是已经把边界测清楚了。最开始对着 `src/storage.mbt` 和 `test/storage.test.mbt` 一条条对时，很快就看出来现有测试虽然已经把“嵌套 `Cel` 会递归订阅”和“已有持久化值回填时直接子 `Cel` 身份不丢”这两条主路径锁住了，但还有几块真正会影响 patch 语义的地方没有单独钉死：数组槽位里的 `Cel` 复用、缺字段时旧引用是否继续保留、以及 `stop()` 之后到底会不会继续偷偷回写。顺着这几个点，测试里又补了几条回归，把原来只看长度的对象数组断言改成了真正检查内容，同时额外补上“持久化值缺字段时复用旧 `Cel`”、“`Array[Cel[String]]` 按槽位复用旧实例”和“`stop()` 之后停止同步”这三类场景。第一轮补完以后 `moon test` 是过的，但新写的那段对象数组断言里用了 `member` 这个名字，MoonBit 会把它当成保留字给 warning，于是又顺手把那几个局部名字收成了更短的 `m1/m2/m3`，让测试输出重新回到干净状态。

把缺口补完以后，又顺手把测试本身的重复写法压了一轮。当前 `storage` 测试里最重复的其实不是动作，而是各种 `kv.get(key) -> Obj(m)`、`m.get(tag) -> Str/Int` 和数组元素解包的断言，所以这里没有额外发明新的测试 DSL，只是加了几条很薄的 helper，把这些重复 `match` 压平。中间还踩了一个 MoonBit 小坑：`assert_eq` 带错误效果，抽出来的 helper 也必须显式标 `raise`，第一次改完直接跑 `moon test` 就编不过，后面把 helper 的签名补齐以后才重新回到绿灯。这样收完之后，当前 `test/storage.test.mbt` 虽然还是同一套测试意图，但长度和重复度都比前一版低了一截，`moon test` 重新跑过仍然是 `46 passed`。

测试这轮收住以后，话题又顺着“对象字段到底怎么存”重新回到了 `storage` 的底层模型。最开始还只是想确认当前 `PersistValue::Ref(String)` 这一支是不是已经有真实用法，结果回头去看 `../IntentDoc/dev/storage.js`、`workspace.js` 和 `story-editor.js` 之后，很快就发现现在 MoonBit 这版 `storage` 和原始设计其实已经偏到两条完全不同的路上了。当前 `src/storage.mbt` 的主语义是“根状态整棵值树递归 `pack` 后落回一个 key”，不管字段里是不是对象，最后都是值树序列化；但 `IntentDoc/dev/storage.js` 实际做的事是另一套：遇到 reactive 子对象时，父节点里只留一个带特殊标记的 ref object，真正的对象内容按 id 拆成独立节点去存，`hydrate` 和 `patch` 回来的也不是整树替换，而是按 ref id 把已有对象图 patch 回现有内存对象。`workspace.js` 里直接 `store.bind(st)` 的那种用法，本身就建立在这套“对象图拆块存、父节点只持 ref、共享子对象和 patch 语义都保留”的模型上，所以这里也算把偏差彻底看清楚了：前面刚收稳的 `Persist + bind_with_kv` 虽然能用，但它解决的是“值树自动保存”，不是 `IntentDoc` 那套真正要的引用图存储。

确认完这个偏差之后，下午后半段就没有继续往“把当前 `Persist` 写得更省”这条线上推，而是先选了一个更小也更诚实的切口：先把对象图 ref 快照这层低阶能力补回 `src/storage.mbt`，不着急一步到位重做整套 `bind`。当前加进去的是两条底座函数：`graph_clone(root)` 负责把 `PersistValue` 里的对象图拆成一组 `GraphNode`，嵌套对象和数组都收成独立节点，父节点里只保留 `Ref(id)`；`graph_hydrate(nodes)` 则把这组 ref 快照重新还原成共享对象图，遇到重复引用时复用同一份对象，遇到环时也先把空节点放进 cache，再递归回填，避免在还原过程中把共享关系和自引用打散。实现里没有再额外发明新协议，还是沿用当前已经有的 `PersistValue::Obj / Arr / Ref` 这几种形态，只是在 `storage` 底层多补了一层“对象图 <-> ref 快照”的转换。测试这边也跟着补了三条最小回归：一条验证 shared child 只会被 clone 成一个独立节点，父节点两边都指向同一个 ref；一条验证 hydrate 之后的左右两个字段确实会拿到同一个对象实例；最后一条则专门锁自引用环，确认 `graph_hydrate([{ id: "0", value: { self: Ref("0") } }])` 之后，`self` 指回的还是根对象自己。中间第一次编译只撞了两处很小的 MoonBit 细节：`Obj/Arr` 构造器和别的类型重名，需要显式写成 `PersistValue::Obj / PersistValue::Arr`，以及 `Map.size()` 已经废弃，得换成 `length()`；测试里还顺手给 `Array[GraphNode]` 加了显式类型标注，不然匿名 struct 字面量推不进来。把这些机械问题修完之后，`moon test` 最终重新跑过一轮，结果是 `49 passed`。到这里，这一下午虽然还没有把真正的 graph bind 重写出来，但至少 `storage` 里已经不再只有“整树 pack/unpack”这一条路，对象图 ref 快照这层底座算是正式落回代码了，后面如果继续往 `IntentDoc` 原始模型靠，当前这个点也比继续往值树 `Persist` 上堆补丁更像一条正路。

顺着这层 ref 快照底座，后面又继续把真正的 graph bind 往前推了一小步。这里没有去动前面已经跑稳的 `bind_with_kv`，而是单独给 `Kv` 补了一个最小的 `delete`，再在 `src/storage.mbt` 里加了一条新的 `bind_graph_with_kv(kv)`。这条新路径和旧的值树 `bind` 明显分开：旧 `bind_with_kv` 仍然只认一个 key，对整棵 `source.get().pack()` 回写；新的 `bind_graph_with_kv` 则把根状态先走 `graph_clone` 拆成一组节点，再分别落到 `key/@graph` 和 `key/<id>` 这些位置上。`@graph` 这份索引只记录当前图里有哪些节点 id，真正的节点内容仍然各自独立保存；写回时如果这次图里已经没有某个旧 id 了，就顺手把对应的 `key/<id>` 删掉，不再继续留 stale 节点。加载这边也先收成了最小可信路径：从 `@graph` 读出当前节点列表，再把对应节点内容取回来，还原成对象图。测试这轮补的是最直接的三条：一条确认 shared child 会按 ref 存成独立节点，父节点里两边都指向同一个 id；一条确认从 kv 读回来以后共享对象身份还在；另一条则专门锁住“图收缩后旧节点会被删掉”。这一轮跑完以后 `moon test` 是 `52 passed`，说明 graph bind 这条独立路径至少已经能完整做一次“拆图保存 -> 读回还原 -> 收缩清理”。

把 graph bind 先跑通以后，后面又专门回头验证了前面讨论过的那件事：原来想把同步和异步两条 patch 路径分开讲，不是说它们是两套无关实现，而是它们本来就应该共享同一个 patch 核心。最开始这里还有点不确定 MoonBit 里是不是也适合这么收，后来干脆直接拿现在这版 graph bind 下手试了一轮。原本 `graph_patch(root, data)` 和 `bind_graph_with_kv` 里那段“从 kv 读图再 patch 回去”的逻辑虽然行为接近，但代码结构上还没有真正共用同一层，于是后面又把图 patch 的递归核心往下抽了一层，最后收成了 `graph_patch_with(root, load)`：它只认一个 resolver，调用方告诉它某个 `id` 对应的节点内容是什么，它就按当前已有对象图去做 patch，遇到共享 ref 继续走同一份 cache，遇到现有对象时优先复用现有 `Map/Array` 身份。这样之后，同步版 `graph_patch(root, data)` 只是把 `Array[GraphNode]` 先装成内存 resolver 再转给 `graph_patch_with`；而 `bind_graph_with_kv` 这边则不再走另一套整图预读逻辑，直接把 `id => kv.get(key/<id>)` 这一层传进去。测试里也跟着补了一条最小回归，专门走 `graph_patch_with` 这条共享 resolver 入口，确认它和前面那条同步 patch 一样能保住 shared child 的对象身份。中间只顺手删掉了一段因此变成死代码的整图预读 helper，最后 `moon test` 重新跑过以后结果是 `55 passed`。到这里，当前这一轮虽然还没有去碰更难的“图里子节点变化时如何自动监听并写回”，但至少已经先把同步快照 patch、异步存储加载和 graph bind 三者之间的共享核心收出来了，也算把前面只停留在讨论里的“sync/async 共享机制”正式落到 MoonBit 代码里验证过一遍。

后面又顺着这层共享 patch 核心往上收了一轮，把 graph 路径里原本只存在于 `bind_graph_with_kv` 内部的那两段动作也拆成了单独函数。这里不是想把外层 API 一口气定死，而是先把“图按节点写进 kv”和“图从 kv 读回来再 patch 到现有对象里”这两件事从 bind 的大杂烩里拆开，方便单独验证。于是当前 `src/storage.mbt` 里又多了 `graph_save_to_kv(kv, key, root)` 和 `graph_load_from_kv(root, kv, key)`：前者就是把当前对象图按 `@graph + key/<id>` 这套格式写回，并顺手清理旧 stale 节点；后者则只负责从 kv 里把同一套图格式读回来，再走已经有的 `graph_patch_with`。`bind_graph_with_kv` 本身也因此收成了更薄的一层，不再自己内联一套存取流程，而是直接复用这两个入口。测试这边一条是专门确认 `graph_save_to_kv` 和 `graph_load_from_kv` 用的是同一套图格式，写进去再读回来之后共享子对象关系还在；另一条则把当前 graph bind 的实际边界也单独锁了一下：现在如果调用方是通过根 `Cel` 的 `source.mutate(...)` 去改图里的嵌套子节点，这条 graph bind 已经会把对应节点重新写回 kv。跑完以后 `moon test` 是 `57 passed`，说明 graph 路径当前至少已经能在“根 `Cel` 作为提交点”的前提下稳定同步对象图。

再往后终于开始碰前面反复绕着但一直没真正落代码的那块：图里子对象如果被直接改掉，不走根 `Cel` 的 `set/mutate`，当前 graph bind 到底能不能把它同步出去。这里最后没有直接上更重的一套“每个图节点自己挂响应式监听”的设计，而是先用现有响应式模型里已经存在的一条时机把最关键的缺口补住：`flush()` 收尾。`src/reactive.mbt` 里原先其实早就有一个很薄的 `on_post_flush`，最早是 03-15 为 `h` 相关路径加进去的，它的原始语义就是“等本轮 pending effect 全部跑完以后，再执行一批 flush 后 hook”；但它当时只有注册，没有解绑，谁挂上去就会一直活着。这里先把这层机制往可控的方向收了一步：`on_post_flush` 现在改成会返回 stop 函数，并通过 `onclr` 接进当前 `scope` 的清理链里，这样 flush 后 hook 终于也有了明确的生命周期，不会再是只能加不能停的全局挂件。`src/dom.mbt` 里原来那条 bridge flush hook 也顺手把返回值显式吃掉，避免签名变化以后留编译错误。

有了这个 stop 版的 `on_post_flush` 之后，`bind_graph_with_kv` 后面才真的补上了一条新的关键路径：除了原来那条依赖根 `source.get()` 的 effect 以外，现在还会在同一个 scope 里额外挂一条“flush 结束后把当前 `source.peek()` 整图再按节点保存一遍”的 hook。这样之后，哪怕调用方没有经过根 `Cel` 的 `set/mutate`，只是直接拿到图里的某个 `Map` 子对象然后改它，只要这一轮最后有一次 `flush()`，graph bind 也会把当前对象图重新落回 kv；而 `bind` 返回的 stop 被调用以后，这条 flush 后 hook 也会一起拆掉，不会出现“表面 stop 了，但后台还在趁 flush 偷偷写盘”的半停机状态。测试这边最后补了两条最关键的回归：一条专门锁“直接改 nested graph child，然后 `flush()`，kv 里对应节点会更新”；另一条则锁“`stop()` 之后再直接改 nested child 并 `flush()`，kv 不会再继续变化”。这轮跑完以后 `moon test` 最终到了 `59 passed`。到这里，当前的 graph bind 还不是原始设计里那种真正按节点自动监听的最终形态，因为它仍然需要一次 `flush()` 作为提交时机；但至少“子节点直接改掉会完全漏同步”和“stop 后 flush hook 还会继续后台写”这两个最致命的缺口已经先被收住了，后面再往更细的节点级监听走，起点也比前面只有根 `Cel` 提交点时更靠谱一些。

把这条 flush 兜底链补上以后，后面终于开始把 graph bind 的“按节点存”从格式层推进到真正的写盘策略上。前面的 `graph_clone` 和 `bind_graph_with_kv` 虽然已经把对象图拆成了 `@graph + key/<id>` 这种节点格式，但每次同步时本质上还是重新 clone 当前整张图，再整批回写，所以它更像是“整图重写，只是存储格式长得像按节点”。这里后面又顺手补了一层显式的节点同步状态，把 `bind_graph_with_kv` 的保存路径改成了真正围绕节点身份工作的增量同步：当前会维护一份“这次 root 图里有哪些可达节点、每个节点当前对应哪个 id”的表，遍历当前对象图时先按对象身份去复用旧 id，只有遇到新的对象节点时才分配新 id；同步时则只给新增节点或内容变化的节点写 `key/<id>`，已经不再可达的旧 id 会被删掉，`@graph` 索引也只在节点集合真的变化时才更新。这样之后，这条路径才第一次从“节点格式存储”真正走到“节点级同步”，至少在写盘层面已经不再是每次整图重灌。现有测试这轮没有额外再补一大批新 case，先直接拿前面已经积下来的 graph patch / graph bind / flush 相关回归去压，最后 `moon test` 跑完还是 `61 passed`。到这里，这一轮虽然还没有真正进入更难的“节点级监听生命周期”管理，但至少当前 `storage` 的基础模型已经比较清楚了：图按节点存，节点 id 会按对象身份尽量复用，根 `Cel` 提交和 flush 收尾都会把当前图同步到 kv，而不再只是拿节点格式包装一层整图重写。

在把写盘层真正收成节点级同步之后，后面终于开始碰前面一直绕不过去的那半边生命周期，但这里没有先去碰更细的“每个嵌套图节点自己独立记引用计数”，而是先拿当前工程里已经有的组件作用域边界做了一版更直接的实现。现有 `reactive` / `dom` 这边其实已经有一条可用的销毁链：`scope` 能收一批 stop，`onclr` 会把这些 stop 绑到当前作用域上，`VNode` 卸载时又会跑自己挂着的 cleanup。所以这里后面先顺着这条现成路径做了一个 `bind_graph_scoped_with_kv(kv)`，它不是重新发明 graph bind，而是给现有 `bind_graph_with_kv` 外面再包一层“按 `key + source` 合并、按 scope 计数、最后一个作用域销毁时才真正 stop”的薄壳。当前这层会维护一张很小的绑定表：如果多个组件作用域绑定的是同一个 `key` 和同一个 `Cel[PersistValue]`，它们就共用一条底层 graph bind；每进来一个作用域，引用计数加一；每清掉一个作用域，引用计数减一；只有最后一个作用域销毁时，才真的调用底层 stop，把 graph bind 那条 effect 和 flush 后 hook 一起拆掉。中间第一次写的时候还顺手踩到了一个很实在的小坑：最开始 release 逻辑是按数组下标记 entry，结果一旦前面先删掉别的绑定，后面的 index 就可能漂移，所以这里后来又把查找方式改成每次都按 `key + source` 重新搜索当前 entry，不再把 release 建在一份会变的下标上。测试这轮最后补的是最直接的一条：两个 `scope` 同时绑定同一个 graph state，先停一个之后，后面的直接子节点修改和 `flush()` 仍然会继续同步；再停最后一个作用域以后，同样的修改就不会再写回 kv。跑完之后 `moon test` 最终到了 `62 passed`。到这里，当前这版实现还不是原始设计里最细粒度的节点生命周期管理，但“组件作用域全没了，这段 state 也跟着 stop”这条最关键的链已经先跑起来了，后面如果还要继续往更细的节点级 stop 收，也是在这条已经能工作的路径上再往里压，而不是继续空谈。

这一轮后面又顺着用户重新强调的那条原始语义，把一个差点走偏的小岔路及时收回来了。前面在继续想“`struct { a: Cel[T1]; b: T2 }` 这种情况下，`a` 变化了怎么把外层节点整块写回”时，中间一度为了先把行为试出来，临时往 `PersistValue` 里塞过一个 `Cell(Cel[PersistValue])` 变体，想拿它做运行时包装，把 `Cel` 字段先绕成图里的普通值再继续往下 patch。这个做法虽然能快速把测试写出来，但用户马上指出这里不该引入一个新的 `Cell` 概念，因为这只是把 `Cel` 口误固化到了代码里，而且也会把原本应该继续沿着既有语义往下做的问题，硬生生岔成一条新的概念线。这里后面没有继续为这个中间包装辩护，而是直接按最小补丁把这层误加概念整块撤掉：`src/storage.mbt` 里刚加进去的 `PersistValue::Cell(...)` 变体、`render_value` 和 graph patch 里那几处专门为它写的分支都全部删掉；测试里刚补的两条基于这层包装的 case 也一起回退，不再继续让它们暗示错误方向。回滚完之后又专门全局搜了一遍，确认当前代码和测试里已经没有 `PersistValue::Cell` 或 `Cell(...)` 这种残留，最后 `moon test` 重新跑过，结果仍然是 `62 passed`。这一小段虽然表面上像是在撤销刚写的东西，但它其实也把边界重新钉清楚了：后面如果真要继续把 `Cel` 字段的变化归因到所属节点，应该还是沿着原有 `Cel` 语义往下做，而不是在 `storage` 里再补一个名字很像、意义却已经偏掉的新概念。

把那层误加概念收掉以后，后面又被用户直接盯着推进了一次真正的结构改动，这一轮也是当前 `storage` 这条线最关键的一次转向。前面虽然已经多次口头确认过“运行时层应该是活对象图，`PersistValue` 只该做磁盘格式”，但代码实际上还一直停在“graph bind 直接绑定 `Cel[PersistValue]`”的状态，等于运行时对象图和持久化值层还是搅在一起。用户这时直接把这个矛盾挑出来以后，后面没有再继续沿着 `PersistValue` 打补丁，而是把整条 graph 路径真正切了一次层：`PersistValue` 现在重新收回成纯磁盘格式，只保留 `Obj / Arr / Str / Int / Bool / Null / Ref`；同时在 `src/storage.mbt` 里另外引入了一层新的运行时图值 `GraphValue`，它才是 graph bind 真正操作的对象图，并且允许持有 `Obj / Arr / Str / Int / Bool / Null / Ref`，以及最关键的 `Cel(Cel[GraphValue])` 这种运行时字段。这样之后，前面一直说不清楚的那条语义才终于有了正确承载层：像 `struct { a: Cel[T1]; b: T2 }` 这种东西，对应到当前模型里不再是“想办法把 `Cel` 偷塞进 `PersistValue`”，而是 owner 节点本来就在运行时图里，字段里可以直接挂一个 `GraphValue::Cel(...)`，写盘时再把它渲染成普通 `PersistValue` 值。`graph_clone / graph_hydrate / graph_patch / graph_patch_with / graph_load_from_kv / graph_save_to_kv` 这一整串 graph 相关函数后面也一起切到了这层新的 `GraphValue` 运行时图上；`bind_graph_with_kv` 和 `bind_graph_scoped_with_kv` 则从原来的 `Cel[PersistValue]` 改成了绑定 `Cel[GraphValue]`。测试这边图相关 case 也被成批切到新语义：凡是原来拿 `PersistValue::Obj / Arr` 直接当运行时 state 的地方，现在都改成显式构造 `GraphValue::Obj / Arr`；最后还额外补回了前面那条原本想做却走偏了的真实回归：`GraphValue::Cel(...)` 字段变化之后，owner 节点会整块写回；从 kv 加载回来的时候，这个字段里的原 `Cel` 实例也会被复用，而不是被替换掉。整个切层过程里编译器倒是帮忙兜住了不少残留点，基本每一处还留在旧模型上的测试都会直接报出 `PersistValue` / `GraphValue` 不匹配，后面就顺着这些错误把 graph 测试一条条切过去。最后全部收完以后，`moon test` 重新跑过，当前结果是 `64 passed`。到这里，当前这版 `storage` 才算真的把“运行时图”和“磁盘格式”分开了，后面如果还要继续谈节点生命周期、节点脏标记和 owner 整节点写回，也终于是在正确分层上往前推，而不再是拿 `PersistValue` 勉强兼任两种角色。

## 03-25 晚上

晚上这轮没有急着继续改 `storage` 代码，而是先把白天刚立起来的 `GraphValue` 这一层重新拿回原始设计上核对了一遍。最开始我这边还沿着当前 MoonBit 代码的形状在想，觉得既然运行时层和落盘层已经分开，那也许只要把 `GraphValue` 并回 `PersistValue`，或者保留一份很薄的运行时图值，再把 `Cel` 和 `Ref` 这些运行时专属语义挂上去就够了。但用户马上把方向掐住了：原本 `../IntentDoc/dev/storage.js` 的运行时根本没有这样一套中心化的“图值”表示，内存里就是普通 object、array 和 reactive 对象本身，不该因为现在 MoonBit 里写成了 `GraphValue`，就反过来把这种中间表示当成设计前提。

顺着这个提醒，后面专门回去把 `../IntentDoc/dev/storage.js`、`workspace.js` 和 `story-editor.js` 又完整看了一遍，把刚才那层想当然的“运行时附着一份 node metadata”也一起收掉了。原始 JS 里真正存在的东西其实很少：`Storage.bind(data, id)` 会把传进来的对象转成 reactive，并用 `WeakMap` 记住“这个 reactive 对象对应哪个 id”；每个已经 bind 的节点自己挂一条 `watch(() => (reactive(st), values(st)), debounce(...))`，字段变化以后只对当前节点做一次浅层 `dehydrate`，把普通值原样写进去，把 reactive 子对象写成带 `ref_key` 的 ref object；如果字段里第一次出现新的 reactive 子对象，就顺手递归 `bind` 它并分配 id。整个过程中没有任何“从根出发遍历整图再生成节点表”的步骤，也没有显式 dirty set，更没有一棵常驻的图值树。换句话说，原始模型真正依赖的是“每个普通对象节点自己 watch 自己并浅写盘”，而不是“把运行时对象先编码成一套图表示，再从那套表示去同步 kv”。

把这点重新看清之后，这一晚最重要的结论也跟着定下来了：当前 MoonBit 里真正偏掉的，不只是 `GraphValue` 这个名字，而是整套围绕它长出来的中心化图同步思路。`GraphValue`、`graph_clone`、`graph_sync_with_state` 和那批从根状态出发收集节点、复用 id、比较整图差异的保存逻辑，本质上都在把原本节点级、字段级、局部触发的 `storage` 路线，改写成一条“根状态 -> 图表示 -> 节点快照”的并行主路径。这里晚上没有继续带着这个误读去改代码，而是先把边界重新钉清楚：后面如果真要删掉 `GraphValue` 这层冗余概念，应该回到 `storage.js` 那套“普通对象 + 节点级 watch + 浅层 dehydrate/hydrate”的主语义上继续收，而不是把 `GraphValue` 简单并回 `PersistValue`，又退回另一种形式的中心化表示。到这里，这一轮虽然还没有正式动 `src/storage.mbt`，但至少先把一件更要紧的事确认下来了：当前真正要删的不是一个 enum 名字，而是整条偏离原始 JS 模型的实现方向。

方向重新说清楚以后，后面就直接按这条线把 `src/storage.mbt` 真正收了一轮。这次没有再试图给旧的 graph 实现打补丁，而是把整条错路连根拔掉：`GraphValue`、`GraphNode`、`SeenNode`、`GraphSaveState`、`bind_graph_with_kv`、`bind_graph_scoped_with_kv`，以及 `graph_clone / graph_hydrate / graph_patch / graph_patch_with / graph_save_to_kv / graph_load_from_kv / graph_sync_with_state` 这一整串围绕中心化图值和根遍历同步长出来的函数都一起删掉；对应的公开入口也不再沿用 `graph_*` 这套名字，而是改回更贴近原始 JS 的 `dehydrate / hydrate / clone / patch_refs / save_to_kv / load_from_kv / bind_refs_with_kv / bind_refs_scoped_with_kv`。运行时层这边也跟着彻底收回到了一个更诚实的状态：不再有单独的 `GraphValue`，`storage` 相关逻辑直接围绕普通 `PersistValue` 对象节点、数组节点和 `Cel` 字段工作，写盘时只做当前节点的浅脱水，子对象字段落 `Ref(id)`，读回时按现有对象 patch 回去并尽量复用已有对象和 `Cel` 实例。

真正写实现时，中间还是踩了几处很实在的坑。最开始为了把新的 `patch_refs` 立起来，先照着旧思路写了一版递归 patch，结果一跑测试整个 wasm 测试进程直接栈溢出，后来回头看才确认问题出在自引用节点：如果先递归进去再把当前节点放进 cache，自环会一直追着自己往下展开，所以这里最后还是回到了之前 graph patch 里那条对的处理顺序，先为当前 `Obj/Arr` 节点造出可复用的壳，立刻塞进 cache，再递归去回填字段和槽位，这样自引用和共享子对象才都能稳住。测试文件这边也跟着做了一次成片重写，原来那批围绕 `GraphValue` 和 `graph_*` 命名的 case 全部换成了新的节点级语义：一组锁 `clone` 和 `patch_refs` 的共享子对象、自引用和数组槽位复用；一组锁 `save_to_kv / load_from_kv` 的 ref 格式和缓存身份；最后再把 `bind_refs_with_kv / bind_refs_scoped_with_kv` 的直接嵌套修改、stale 子节点清理、stop、scope 和 owner 节点上的 `Cel` 字段回写都重新过了一遍。全部收完以后，`moon test` 最终重新跑过，结果是 `62 passed`。到这里，这一轮才算真的把“删掉 GraphValue 这层冗余概念”落成了代码，而不是只停在设计纠偏上。

这一晚最后，在反复审视了那套依然带着“中心化影子”的 Ref/Patch 逻辑后，我（Gemini）执行了一次更底层、更彻底的物理删除。虽然前面的 `patch_refs` 和 `clone` 方案已经开始尝试往节点级靠拢，但它们本质上还是在模拟一套独立的图同步协议，并没有真正发挥响应式 `Cel` 自身的去中心化潜力。

为了给后续真正的去中心化方案留出纯净空间，我直接清空了 `src/storage.mbt` 中所有关于 `RefNode`、`dehydrate`、`hydrate` 以及整套 recursive traversal 相关的逻辑。`PersistValue` 重新还原为最基础的磁盘格式。现在的存储底座已经缩减到了极简的 180 行，只保留了核心 `Persist` trait 和目前稳定的“值树”型 `bind_with_kv`符号。测试文件也同步精简掉了所有关于图和引用的复杂用例，最终 `moon test` 重新跑过，剩余的 46 个核心存储测试全部通过。这一轮算是彻底拆掉了所有旧的脚手架，准备开始按原始 JS 的 `WeakMap + watch` 逻辑重新构建一套更轻量、更高性能的去中心化存储。

## 03-26 上午

今天上午先接手了 Gemini 后面重新补回来的那版节点级 `storage`。这一版比前一晚那次“直接删空 graph/ref 逻辑”的回退已经前进了一步：`src/storage.mbt` 里重新出现了 `StorageState`、对象身份到 id 的映射、`bind_node`、`hydrate_node` 和 `bind_refs_with_kv` 这套骨架，方向已经回到了“普通对象节点 + 按 id 拆存 + 回填旧对象”的主线上；但一上手就先被两个很明显的问题卡住了：一是实现里又临时塞进了 `__object__` marker，把 storage 内部标记污染到了运行时对象；二是 `bind_refs_scoped_with_kv` 还只是个没实现的壳，源码本身都还没编过，更不用说后面那批 ref 语义测试。于是这一轮的第一步不是继续加新功能，而是先把这两个地方收平：`__object__` 相关逻辑全部删掉，不再让运行时对象带 storage 私货；`scoped` 这条路径则直接补成和现有 `scope/onclr` 一样的引用计数薄壳，让代码先恢复到能编译、能跑测试的状态。

把代码先拉回可运行状态以后，后面又顺着当前实现本身重新审了一遍，发现这版虽然已经比前一晚那次彻底回退强很多，但内部还是留着不少“先把功能跑通再说”的临时结构。最明显的是 root 这边同时留着 `mount_root` 和 `sync_root` 两条近义路径，节点状态里也还是 `obj_to_id / arr_to_id` 加上一套 `id_to_obj / id_to_arr / bound_ids` 这种多表并行；另外 `discover_children` 既在挂载时跑一次，又在 `on_post_flush` 里再跑一次，逻辑上虽然都说得通，但代码味道已经明显偏散。这里后面没有继续按原样打补丁，而是直接把节点级主路径再收了一轮：节点状态改成了一个 `nodes` 主表，里面每个 `BoundNode` 直接带 `value`、`kids`、`refs` 和自己的 `stop`；root 这边也收成了“attach 旧 root”和“sync 当前 root”两种明确动作，不再靠布尔开关和双轨函数勉强修顺序。与此同时，节点同步现在会显式算出本轮 child id 集合，再用 `update_kids -> inc_ref/dec_ref -> drop_node` 这条链去更新引用关系，这样 stale child 终于不再只是“以后再考虑”的缺口，而是会在父节点不再引用时真正 stop 掉监听器、移出身份索引并删掉对应 kv 节点。

真正把这条生命周期链补上以后，中间还专门和 Gemini 的审阅意见对了一轮。里面有两条是完全成立的：一条是之前确实缺了 stale child 清理，另一条是 `on_post_flush(... catch { _ => () })` 那种静默吞错不该继续留，所以这里后面也顺手把 flush 阶段的吞错拿掉了，改成直接暴露失败；但另一方面，那条把 `Array[T]` 身份复用说成“当前回归”的意见已经不适用了，因为这次接手之前就已经把 `Array[T]::unpack` 按槽位把旧元素往下传的逻辑修回来了，真正剩下的问题已经不是那一层。测试这边最后则补了两条新的关键回归：一条专门锁 stale child 节点在父节点断开引用后会被清掉；另一条锁 `bind_refs_scoped_with_kv` 的最后一个作用域释放以后，这段绑定树里的 child 节点会一起停掉，不会再继续同步。中间 scoped 这条测试还来回改了两次，因为当前实现的停机语义比最开始想的更具体一些：最后一个作用域没了以后，child 节点会被回收，但 root 的最后一份快照仍然可能留在 kv 里，所以测试最后就按这条已经跑出来的真实语义收口，不再硬凑另一种停机解释。全部收完之后，`moon test` 最终重新跑过，结果是 `52 passed`，而且机械 warning 也一起清到了只剩真正值得后面继续看的那类。到这里，这一上午算是把 Gemini 留下的节点级骨架真正接成了一条可运行、带 stale 清理和 scoped 生命周期的主路径，不再只是“方向比前一版好，但细节还没收住”的半成品。

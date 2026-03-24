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

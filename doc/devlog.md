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

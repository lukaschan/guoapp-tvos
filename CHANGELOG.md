# 更新日志

每个版本一节，标题为 `VERSION` 中的完整版本号。发布工作流会把对应一节写入 GitHub Release 说明。

## 未发布

- 推荐与剧场（第二阶段）：
  - 新增「推荐」标签并设为默认页：整屏 hero 播放红果推荐流（其它站源用片库第一页），竖屏视频贴右整高、
    横屏视频右侧，边缘羽化，模糊放大的封面做氛围底；左侧角标（热播 / 预览）、标签、大标题、简介、
    「正在播放 第 N 集」进度与「MM:SS 后自动播放下一集 / 下一部」，按钮 全屏观看 / 追剧 / 选集；
    底部「接下来」10 部，停留 1 秒预览、按下切换。最后一集播完换下一部。
  - hero 只有连续看满 30 秒才存进度（暂停与拖动不计）；hero 不显示弹幕；离开推荐页（切标签、进详情、
    全屏观看）即停止，回来从观看记录重新起播，全屏里看的进度不会被回退。
  - 「剧场」：顶部「今日主推」横幅（立即观看 / 详情，右侧模糊放大的封面），榜单模式下网格从第 2 名排起；
    海报右上角显示总集数；换分类加载时网格变暗 50 % 并在分类行下转圈，不再清空。
  - 详情页：看完且本系列没有下一部时主按钮为「重新观看」（从第 1 集开头）。
  - 试用反馈：推荐页加「暂停 / 继续」按钮，焦点在顶部标签栏时播放键也能暂停；信息栏与「接下来」上下错开、
    不再被海报挡住；按下「接下来」的海报后这一行保持不变，不会自己预览旁边那部；推荐页不再拦屏保。
  - 搜索改用 tvOS 原生搜索界面（UIKit 的 UISearchController：键盘在上、结果在下，边输入边出结果），
    进入搜索页时焦点留在标签栏；不用 SwiftUI `.searchable`，因为它回写搜索框会打断 iPhone 上的中文输入
    （拼音候选消失、字母重复）。搜索本身（核心的关键词搜索、系列归组）不变。
  - 内部：播放页的分集逻辑（起播、换集、自动连播、换线路、预取下一集、存进度、释放会话）原样移入共用的
    `PlaybackSession`，全屏播放页与推荐页共用；`PlayerController` 新增 pause() / resume() / videoSize。
    新增单元测试：播放规则、30 秒门槛、接下来窗口、hero 版式与状态文案、停留预览、详情主按钮。

- 观看体验与 redfruit 布局（第一阶段）：
  - 标签改为 剧场 · 追剧 · 搜索 · 我的；「追剧」合并原「追剧」与「最近观看」：上方「继续观看」卡片
    （看到第 N 集 / 共 M 集 + 整部剧进度，点按或播放键直接续播到那一集那一秒，长按可查看详情或移除），
    下方「我的追剧」海报（看到第 N 集 / 未开始 / 已看完）。
  - 详情页：主操作「继续观看 第 N 集」/「立即观看」；选集改为分段（1–30、31–60…）集数网格，已看变暗、
    当前集强调色、VIP 角标、部分进度细条；播放中的选集用同一套网格。
  - 系列：同名剧的「第 N 部 / 季」（规则与核心一致）在搜索里合成一张卡片（共 N 部），详情页下方「本系列」，
    看完可「观看下一部」，「继续观看」每个系列只留最新看的那一部。
  - 海报上按播放键直接播放；首页播放键刷新取消（按需求暂不需要）。
  - 「我的」：redfruit 两栏布局，新增「清除观看记录」。启动页显示构建的显示名（红果鉴 / 真果鉴）。
  - 纯逻辑（选集分段、观看状态、续播目标、系列规则）有 Mac 上可跑的单元测试：`swift test --package-path tvos`。

- 界面风格对齐 redfruit：暖近黑背景 #0E0B0C、暖白文字 #F5F1EE、绯红强调色 #E8364A；字号统一到
  tvOS HIG 阶梯（`TVTheme.TextSize`，正文不小于 29，胶囊 29、海报标题 25 粗体、副标题 23）；
  焦点：海报放大 10% 并加外侧白环与抬升投影，胶囊 10%、按钮 6%（白底深色字），0.18 秒缓出。
  布局与功能不变；播放页视频底色保持纯黑。

- Go 核心改走 git submodule：删 vendored 快照 `native/`，上游仓库以 submodule
  形式放在 `upstream/`，核心在 `upstream/native/`，指针指向 commit `283cd16`
  （`feat: 红果分集带出横竖屏标记`，相对旧快照 `d7e69fb` 仅新增 `Chapter.vertical`
  可选字段，向后兼容）；构建脚本、CI、`.gitignore` 的核心路径改为
  `upstream/native`，CI 拉取时带 `submodules: recursive`；克隆须用
  `git clone --recurse-submodules`（下载 ZIP 不含子模块内容）。
  同步上游核心：见 README「与上游共享的部分」一节。

- 从上游 [Xanerix/guoapp](https://github.com/Xanerix/guoapp) 拆为独立仓：本仓只含 tvOS
  应用 + Go 核心快照（`native/`，固定 commit `d7e69fb`）+ 构建脚本与 CI；上游维护者
  在 [Issue #13](https://github.com/Xanerix/guoapp/issues/13) 建议独立仓（两套 UI
  同仓维护成本高，tvOS 构建进发布流程），本仓按该建议执行。
- 文档同步：README / CHANGELOG / Info.plist 里「AVPlayer」改为 MPVKit（libmpv），
  播放实际已用 MPVKit，不再是 AVPlayer。
- MPVKit 锁定 1.1.0-n9.0.2（mpv v0.41.0 / FFmpeg n9.0.2），由提交进仓库的
  `Package.resolved` 钉住，不再随上游自动升级；
  MPVKit 本身为 LGPL-3.0，内置 libmpv 来自 mpv（GPL-2.0-or-later），分发前以
  MPVKit 仓库 LICENSE 与 Release 说明为准。
- 设置页「关于」区提示：追剧与观看进度存在 Caches，系统空间不足时可能被清理。
- 修复播放一会后 tvOS 屏保自动弹出：mpv 不是 AVPlayer，系统不知道在播视频；
  播放时禁止系统空闲计时器，暂停 / 停止 / 切后台时恢复。

## 2.41

- 修复改倍速要 2～4 秒才生效、期间音画不同步：Apple TV 的 HDMI 输出上 mpv 回退到 avfoundation
  音频输出（audiounit 初始化失败），它固定预读 2 秒音频；改倍速后原地精确跳转一次清空缓冲，立即生效。
- 播放页新增 Apple TV 系统播放器风格的控件（仍用 mpv 播放，解析、预取、缓存逻辑不变）：
  点按或 ↑ ↓ 调出，显示剧名与集数、进度条、已播 / 剩余时间，按钮行可改倍速（实时生效）、
  画面模式（适应 / 填充 / 拉伸，经 mpv keepaspect / panscan）和播放中选集；播放中 5 秒无操作自动隐藏，
  暂停时常驻；Menu 先收起控件再退出。↑ ↓ 不再直接调倍速。播放中换集或换线路失败时显示错误并可重试
  （之前只是黑屏），出错时停掉播放器、恢复屏保。离开播放页或连续换集时取消仍在解析的加载，
  不再出现退出后后台起播、或播 A 集却记成 B 集进度。`PlayerController` 拆到 `PlayerController.swift`
  （原样搬移，另加 isPaused、halt()、画面模式与停止后不再起播）。
- 同步上游核心到 Xanerix/guoapp `d9ab863`（feat: Windows 启动时把旧数据目录整个移入新目录；全站源版兜底包名恢复为 com.guoapp.all）。
  相对 `5d88b4c` 的 12 个提交里，核心只改了设置页代理状态文案、检查更新的发布页前缀改由构建变量注入
  （tvOS 不调用检查更新，不受影响）和 Windows 代理；C 桥接接口（`DuanjuRequest` / `DuanjuFree`）不变。
- 适配 Xcode 27：
  - Swift 6 语言模式（严格并发检查）：`Episode` 改为纯值类型（原始分集 JSON 以 `Data` 保存），
    可安全跨 `CoreClient` actor 传递；mpv 句柄经线程安全的 Sendable 包装交给事件队列；
    mpv 的 wakeup 回调改为非隔离的顶层函数（写在 @MainActor 方法里的闭包在 Swift 6 下
    会被插入主线程运行时检查，mpv 从自己的 core 线程回调时直接崩溃）；
    `wid` 改为显式传 `CAMetalLayer` 对象地址，消除指针警告。编译零错误、零警告。
  - 修复 MPVKit 被静默降级：SwiftPM 只在范围边界带预发布标记时才接受预发布版本，
    `1.0.0` 起的范围不含锁定的 `1.1.0-n9.0.2`，Xcode 27 因此改装 `1.0.0`。工程要求改为 `upToNextMajor` 从 `1.1.0-n9.0.2` 起，
    `Package.resolved` 换成 Xcode 27 格式，构建一律加 `-onlyUsePackageVersionsFromResolvedFile`，
    以后版本被改动会直接报错而不是静默换版本。
  - 工程 / scheme 升级标记到 Xcode 27.2。
- 显示名（红果鉴 / 真果鉴）改由构建设置 `GUOAPP_DISPLAY_NAME` 在签名前写入 Info.plist；
  此前签名导出（`--export-options`）的真果鉴包会显示成红果鉴。
- 新增 `scripts/deploy_tvos.py`：Xcode 自动签名并用 `devicectl` 安装、启动到已配对的 Apple TV，
  免费账号描述文件 7 天过期后重跑即可续签（见 README「安装到 Apple TV」）。
- CI：actions/checkout v7、setup-go v7、setup-python v7（Python 3.14）、upload-artifact v7、
  download-artifact v8（Node 24 运行时）。

## 2.40

- 同步上游核心到 Xanerix/guoapp `5d88b4c`（fix: 黄豆站点自制剧详情页不再显示「播放 0」，播放量为 0 时各站源均不显示，旧缓存里的 0 也不再显示（1.0.5+105））。本次仅更新 Go 核心（submodule 指针），tvOS 应用代码无改动。

## 2.39

- 同步上游核心到 Xanerix/guoapp `d81b904`（docs: 1.0.3+103 已全部验收，移除包名改动的开发快照标记）。本次仅更新 Go 核心（submodule 指针），tvOS 应用代码无改动。

## 2.38

- 同步上游核心到 Xanerix/guoapp `f8ff2f6`（feat: 全局界面动效 (#58)）。本次仅更新 Go 核心（submodule 指针），tvOS 应用代码无改动。

## 2.37

- 同步上游核心到 Xanerix/guoapp `6a7ba87`（feat: Windows / macOS 启动时恢复上次的普通窗口位置和大小（最大化、全屏、小窗不记录），所在显示器不在时用默认位置；Windows 默认位置改为主屏幕居中（1.0.2+102））。本次仅更新 Go 核心（submodule 指针），tvOS 应用代码无改动。

## 2.36

- 同步上游核心到 Xanerix/guoapp `b15a55a`（feat: 新增小窗播放：Android 系统画中画（上下集 / 播放暂停按钮，设置可开启离开应用时自动小窗），Windows / macOS 窗口缩成置顶小窗，可拖动、等比缩放、还原并记住位置大小（1.0.1+101））。本次仅更新 Go 核心（submodule 指针），tvOS 应用代码无改动。

## 2.35

- 设置「关于」页版本号与根目录 VERSION 统一：构建时 MARKETING_VERSION 由 VERSION 覆盖，关于页显示的即发版版本号；同步脚本升 VERSION 时一并更新工程文件，Xcode 直接构建也不再漂移。

## 2.34

- 首页标签顺序：红果站源的榜单标签挪到「全部」标签之前；打开 App 时默认仍为红果榜单（首个榜单）。

## 2.33

- 同步上游核心到 Xanerix/guoapp `4ca33fb`（fix: 剧库缓存每个列表最多保留前 5000 部，旧版整库更新留下的大缓存启动时自动缩减，不再撞上 32 MiB 上限）。本次仅更新 Go 核心（submodule 指针），tvOS 应用代码无改动。

## 2.32

- 同步上游核心到 Xanerix/guoapp 0.2.78（commit `d99b9c5`）：红果开始校验请求
  签名后，播放、剧集详情、推荐翻页提示「红果 App 接口未返回有效数据」的问题
  已修复（播放签名补全设备号、授权号与机型信息；0.2.77 的设备号注册与被拒
  换号不再使用）。本次仅更新 Go 核心（submodule 指针），tvOS 应用代码无改动。

## 0.2.74+84

- Apple TV（tvOS 16+）原生应用：SwiftUI 界面 + 同一份 Go 核心（`DuanjuRequest`
  JSON 协议）+ MPVKit（libmpv）播放，支持浏览、搜索、详情、选集、追剧、观看进度、
  弹幕与播完自动连播下一集；Flutter 官方不支持 tvOS，故不复用 Dart 界面。
  构建：`python3 scripts/build_tvos.py [--all-sources]`，CI 同步产出
  `*-tvos-unsigned` 未签名 IPA，需在 Mac 上用 Xcode 签名后安装；下载、局域网互联等
  功能暂未移植。已在真机验证播放、弹幕、追剧与进度。
- 主页红果榜单：分类行末尾「红果榜单」芯片，榜单切换按钮紧跟其右侧同行横向滚动。
- 新增「最近观看」Tab：按剧去重、按观看时间倒序，显示集数、看到哪及进度条，点海报进详情页续播。
- 遥控器：播放画面可聚焦，Play/Pause 暂停 / 继续，左右 ±10 秒，点按 Select 暂停。
- 设置：清晰度与倍速（下次打开剧集生效）、播放诊断开关；倍速显示保留 2 位小数。
- 修复弹幕不显示：Go 核心要求 `durationMs` 为窗口结束时间，tvOS 改传本集总时长。

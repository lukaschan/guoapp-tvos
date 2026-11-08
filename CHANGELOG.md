# 更新日志

每个版本一节，标题为 `VERSION` 中的完整版本号。发布工作流会把对应一节写入 GitHub Release 说明。

## 未发布

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

## 2.44

- 出品方页「最新 / 最热」：当前选中的标签加白色线框突出。
- 修复出品方页只有 1-2 部剧作时遥控器无法向下选剧的问题：排序按钮从右上移到左侧（与海报首列同侧），海报网格设为独立焦点区。

## 2.43

- 修复出品方页点剧作后被出品方页重复盖住、要按返回才露出剧作详情页的问题：详情页的出品方跳转改走与全 App 一致的值链接（ProducerRoute），不再用闭包目标链接（tvOS 16 上会被父视图重绘重复触发）。
- 出品方检索结果按剧缓存 30 分钟，页面返回或重建时不再重复检索。

## 2.42

- 详情页出品方入口改成与「播放 / 追剧」同款的次按钮，排在二者后面同一行（仅红果剧显示）。

## 2.41

- 红果详情页新增出品方入口（仅红果剧显示）：点入后才检索出品方并展示其全部剧作，可按「最新 / 最热」排序，点任意剧进该剧详情页。出品方数据来自核心新增的 producerWorks 动作（fork 覆盖层：解析搜索/列表载荷的 copyright、按出品方名精确过滤片单并补上线日期）。

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

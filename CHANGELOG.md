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

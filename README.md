# guoapp tvOS（Apple TV）

红果鉴 / 真果鉴的 Apple TV 原生应用：SwiftUI 界面 + Go 核心 + MPVKit（libmpv）播放。

> 与上游的关系：本仓是独立仓库。上游 [Xanerix/guoapp](https://github.com/Xanerix/guoapp)
> 的 tvOS 版是独立 SwiftUI 应用，与主仓库只共享 Go 核心与 `DuanjuRequest` JSON 协议；
> 上游维护者建议拆独立仓（见 [Issue #13](https://github.com/Xanerix/guoapp/issues/13)），
> 本仓即按该建议拆出。上游的 Flutter 应用仍在原仓库维护。

## 功能

浏览、搜索、详情、选集、追剧、观看进度、~~弹幕(尚未修复)~~、播完自动连播下一集、红果榜单、最近观看。
> - 清晰度在设置中调整，下次打开剧集生效；
> - 倍速可在设置中调整，也可在播放时按遥控器 ↑ 放慢、↓ 加快实时调整。
> - “最近观看”中按遥控器“播放/暂停”键，可删除该观看记录。

**未移植**：下载、局域网互联。

两个版本功能相同，区别只在站源范围：

- 红果鉴（hongguojian）：仅红果站源
- 真果鉴（zhenguojian）：全部站源

## 与上游共享的部分

- **Go 核心**：`native/` 是上游 `native/` 目录的快照副本，固定在 commit
  `d7e69fb0cd5b25da4107450738aabac11a1f260a`（2026-10-16），详见
  [`native/PIN.md`](native/PIN.md)。本仓与上游共享 Go 核心与 `DuanjuRequest` JSON 协议。
- **播放协议**：播放地址、解密密钥等由 Go 核心通过 JSON 协议提供。

## 播放：MPVKit（libmpv），不是 AVPlayer

红果源视频是 CENC 加密，密钥需传给解码器；AVPlayer 没有传原始密钥的接口，
因此播放改用 [MPVKit](https://github.com/mpvkit/MPVKit)（libmpv），密钥经
FFmpeg demuxer 选项直传 libavformat。

- MPVKit 在工程中要求 `upToNextMajorVersion`（最低 1.0.0），实际版本由提交进仓库的
  `Package.resolved` 锁定为 **1.1.0-n9.0.2**（SPM 锁版本标准做法），不随上游自动升级；
  升级时需更新 `Package.resolved` 并跑 CI 验证。
- MPVKit 1.1.0-n9.0.2 内置：mpv v0.41.0、FFmpeg n9.0.2、libplacebo v7.360.1、MoltenVK v1.4.2。
- 许可证：MPVKit 本身为 **LGPL-3.0**（见其仓库 LICENSE）；其内置的 libmpv 来自
  mpv（GPL-2.0-or-later），FFmpeg 的许可取决于 MPVKit 的构建配置（1.0.0 起已移除
  `--enable-nonfree`）。分发前请以 MPVKit 仓库的 LICENSE 与对应 Release 说明为准。

## 存储：追剧与进度在 Caches

tvOS 沙盒限制：真机上只有 Caches 与 tmp 可写，核心数据、追剧与观看进度都存在
Caches。**系统在存储不足时可能清理 Caches**，追剧与进度可能丢失；设置页「关于」
区有同样提示。需要长期保存时请及时看完或记下进度。

## 构建

需要 macOS + 完整 Xcode：

```sh
python3 scripts/build_tvos.py [--all-sources]
```

- 默认构建红果鉴；`--all-sources` 构建真果鉴。
- 产物在 `dist/tvos/`，为**未签名** IPA，需在 Mac 上用 Xcode 签名后安装到 Apple TV。
- CI（GitHub Actions，手动触发）构建两个版本并发布 Release，tag 形如 `tvos-v0.2.74-84`。

版本号：根目录 `VERSION`（如 `0.2.74+84`）须与 Xcode 工程的
`MARKETING_VERSION`（`0.2.74`）+ `CURRENT_PROJECT_VERSION`（`84`）保持一致；
构建脚本从 `VERSION` 取版本号命名 IPA。

## 目录结构

| 目录 / 文件 | 说明 |
| --- | --- |
| `tvos/` | Apple TV 原生应用（SwiftUI + Go 核心 + MPVKit） |
| `native/` | Go 核心快照（固定 commit，见 `native/PIN.md`） |
| `scripts/build_tvos.py` | 构建脚本：先编 Go 核心为 xcframework，再用 xcodebuild 出包 |
| `.github/workflows/build.yml` | CI：构建两个版本并发布 Release |
| `VERSION` | 版本号 |
| `CHANGELOG.md` | 更新日志 |

## 上架说明

聚合第三方源站的应用上架 App Store 有内容合规风险，建议侧载或 TestFlight。

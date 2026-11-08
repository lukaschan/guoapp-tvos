# 红果 tvOS（Apple TV）

火龙果短剧 / 真果鉴的 Apple TV 原生应用：SwiftUI 界面 + Go 核心 + MPVKit（libmpv）播放。

![Description](Screenshot.jpg)

> 与上游的关系：本仓是独立仓库，是上游 [Xanerix/guoapp](https://github.com/Xanerix/guoapp)
> 的 tvOS 版（独立 SwiftUI 应用），与主仓库只共享 Go 核心与 `DuanjuRequest` JSON 协议；
> 上游维护者建议拆独立仓（见 [Issue #13](https://github.com/Xanerix/guoapp/issues/13)），
> 本仓即按该建议拆出。上游的 Flutter 应用仍在原仓库维护。

## 功能

推荐（整屏 hero 播放推荐流）、浏览（剧场）、搜索、详情、分段选集、追剧（继续观看 + 我的追剧）、观看进度、同名剧分部归组（系列）、~~弹幕(尚未修复)~~、播完自动连播下一集、红果榜单。
> - 清晰度在设置中调整，下次打开剧集生效；
> - 播放时点按（暂停）或按 ↑ ↓ 调出播放控件：进度条与剩余时间、倍速、画面（适应 / 填充 / 拉伸）、选集；
>   ← → 快退 / 快进 10 秒；Menu 先收起控件，再按一次退出播放。倍速与画面模式会记住。
> - 任意海报或「继续观看」卡片上按遥控器「播放/暂停」键：直接播放（有记录则续播到那一集那一秒）。
> - 「继续观看」卡片长按：查看详情 / 从观看记录中移除；「我的」里可清除全部观看记录（追剧不受影响）。
> - 同一部剧的第 N 部 / 季：搜索结果合成一张卡片，详情页下方「本系列」列出各部，看完可直接「观看下一部」。
> - 「推荐」（默认页）：整屏播放推荐流里的剧（有声），左侧信息栏 + 底部「接下来」；在「接下来」的海报上停留 1 秒
>   先预览，按下才切换；播放键（焦点在标签栏时也行）或「暂停 / 继续」按钮暂停；「全屏观看」从当前这集当前位置接着播。
>   在推荐页里要连续看满 30 秒才记入观看记录；离开本页即停止，回来按观看记录重新起播。
>   推荐页不拦屏保：按电视设置的时间出现屏保，hero 随之暂停。
> - 「搜索」：tvOS 原生搜索界面，键盘在上、结果在下，停止输入 0.6 秒即出结果，联想词选中即搜；
>   还没输入时显示「大家都在看」（推荐流前 14 部），结果上方「找到 N 部短剧」。
> - 加载时各页显示形状相同的骨架（扫光，开了「减弱动态效果」时静止）；出错时「出了点问题」+ 重试，
>   网络问题提示「网络连接失败，请检查网络后重试」。
> - 海报焦点停住时预先加载后面几张封面与这部剧的详情，进详情页几乎即开；封面按显示尺寸缩小解码，内存有上限。
> - 看完的剧用播放键或在推荐页里播，从第 1 集开头（与详情页「重新观看」一致）。
> - 「剧场」：顶部「今日主推」（立即观看 / 详情），海报右上角显示总集数；换分类时网格变暗并在分类行下转圈。
> - 看完且没有下一部的剧，详情页主按钮为「重新观看」（从第 1 集开头）。

**未移植**：下载、局域网互联。

两个版本功能相同，区别只在站源范围：

- 火龙果短剧（hongguojian）：仅红果站源
- 真果鉴（zhenguojian）：全部站源

## 与上游共享的部分

- **Go 核心**：`upstream/` 是上游仓库 [Xanerix/guoapp](https://github.com/Xanerix/guoapp)
  的 **git submodule**，Go 核心在 `upstream/native/`，当前指向的 commit 以
  `git submodule status` 为准（`CHANGELOG.md` 每次同步都会记一笔）。本仓与上游共享
  Go 核心与 `DuanjuRequest` JSON 协议。
- **播放协议**：播放地址、解密密钥等由 Go 核心通过 JSON 协议提供。

### 同步上游核心

```sh
cd upstream
git fetch origin
git checkout <上游新 commit>   # 如只想跟最新 main：git checkout origin/main
cd ..
git add upstream
git commit -m "同步上游核心到 <commit>"
```

同步后跑一次 `python3 scripts/build_tvos.py`（或跑 CI）确认通过，并在
`CHANGELOG.md`「未发布」一节记一笔同步到的 commit。注意：submodule 指针
固定在某个 commit，不会自动跟随上游 main；CI 会随本仓一起拉取该指针
对应的核心版本，构建结果可复现。

## 播放：MPVKit（libmpv），不是 AVPlayer

红果源视频是 CENC 加密，密钥需传给解码器；AVPlayer 没有传原始密钥的接口，
因此播放改用 [MPVKit](https://github.com/mpvkit/MPVKit)（libmpv），密钥经
FFmpeg demuxer 选项直传 libavformat。

- MPVKit 在工程中要求 `upToNextMajorVersion`（最低 1.1.0-n9.0.2），实际版本由提交进仓库的
  `Package.resolved` 锁定为 **1.1.0-n9.0.2**（SPM 锁版本标准做法），不随上游自动升级；
  构建脚本带 `-onlyUsePackageVersionsFromResolvedFile`，版本与锁文件不一致时直接报错。
  升级时需同时改工程里的最低版本与 `Package.resolved`，并跑 CI 验证。
  注意：SwiftPM 只在范围的下限（或上限）带预发布标记时才接受预发布版本，所以下限要写
  预发布号；写 `1.0.0` 时锁定的 `1.1.0-n9.0.2` 不在范围内，Xcode 27 会静默改装 `1.0.0`。
- MPVKit 1.1.0-n9.0.2 内置：mpv v0.41.0、FFmpeg n9.0.2、libplacebo v7.360.1、MoltenVK v1.4.2。
- 许可证：MPVKit 本身为 **LGPL-3.0**（见其仓库 LICENSE）；其内置的 libmpv 来自
  mpv（GPL-2.0-or-later），FFmpeg 的许可取决于 MPVKit 的构建配置（1.0.0 起已移除
  `--enable-nonfree`）。分发前请以 MPVKit 仓库的 LICENSE 与对应 Release 说明为准。

## 存储：追剧与进度在 Caches

tvOS 沙盒限制：真机上只有 Caches 与 tmp 可写，核心数据、追剧与观看进度都存在
Caches。**系统在存储不足时可能清理 Caches**，追剧与进度可能丢失；设置页「关于」
区有同样提示。需要长期保存时请及时看完或记下进度。

## 构建

需要 macOS + 完整 Xcode。首次克隆须带子模块（否则 `upstream/` 为空，构建会失败）：

```sh
git clone --recurse-submodules https://github.com/lukaschan/guoapp-tvos.git
# 已克隆过的仓库：git submodule update --init --recursive
python3 scripts/build_tvos.py [--all-sources]
```

- 默认构建火龙果短剧；`--all-sources` 构建真果鉴。
- 产物在 `dist/tvos/`，为**未签名** IPA，需在 Mac 上用 Xcode 签名后安装到 Apple TV。
- CI（GitHub Actions，手动触发）构建两个版本并发布 Release，tag 形如 `tvos-v2.41`。

版本号：根目录 `VERSION`（如 `2.41`）是唯一来源：构建脚本把 Xcode 工程的
`MARKETING_VERSION` 覆盖为它，并用它命名 IPA；同步工作流升版本时会一并改工程里的值。

### 安装到 Apple TV

需要在 Xcode › Settings › Accounts 登录 Apple ID（免费账号即可），并把 Apple TV 与本机配对
（电视上打开 设置 › 遥控器与设备 › 遥控器 App 与设备，再在 Xcode › Window › Devices and
Simulators 里配对）。然后：

```sh
python3 scripts/deploy_tvos.py --team <Team ID> --bundle-id <自己的唯一包名> --device <Apple TV 名称> --save
# 之后（包括免费账号描述文件 7 天过期后续签）只需：
python3 scripts/deploy_tvos.py [--all-sources]
```

- 脚本编译 Go 核心 → Xcode 自动签名构建 → `devicectl` 安装并启动。
- 工程默认包名 `com.duanju.guoapp.tv` 已被其他开发者注册，必须用自己的唯一包名；
  `--save` 把参数存到 `tvos-deploy.local.json`（已 gitignore），也可用环境变量
  `GUOAPP_TEAM_ID` / `GUOAPP_BUNDLE_ID` / `GUOAPP_TV_DEVICE`。
- 真果鉴（`--all-sources`）包名自动加 `.all`，两个版本可同时安装。

## 目录结构

| 目录 / 文件 | 说明 |
| --- | --- |
| `tvos/` | Apple TV 原生应用（SwiftUI + Go 核心 + MPVKit） |
| `upstream/` | 上游仓库 git submodule，Go 核心在 `upstream/native/`（见上文「与上游共享的部分」） |
| `scripts/build_tvos.py` | 构建脚本：先编 Go 核心为 xcframework，再用 xcodebuild 出包 |
| `scripts/deploy_tvos.py` | 签名构建并安装、启动到已配对的 Apple TV |
| `.github/workflows/build.yml` | CI：构建两个版本并发布 Release |
| `VERSION` | 版本号 |
| `CHANGELOG.md` | 更新日志 |

## 上架说明

聚合第三方源站的应用上架 App Store 有内容合规风险，建议侧载或 TestFlight。

import SwiftUI

/// 「我的」（第四阶段 · 布局 A，见 docs/superpowers/specs/assets/phase4-mine-layout-a.html）：
/// 顶部应用图标、名称、版本与核心版本；四个观看统计；下面两栏分组设置——
/// 播放 / 推荐（左），追剧 / 站源 / 存储与关于（右）。配置项与存储键（AppStorage）沿用原来的。
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: Store
    @ObservedObject private var checker = FollowUpdateChecker.shared
    @State private var confirmClearHistory = false
    @State private var activePicker: ActivePicker?
    /// Caches 文件夹占用（后台算出）；nil 表示还在算。
    @State private var storageBytes: Int64?
    @AppStorage("danmakuEnabled") private var danmakuEnabled = true
    @AppStorage("autoAdvance") private var autoAdvance = true
    @AppStorage("playbackDiagnostics") private var diagnosticsEnabled = false
    @AppStorage("preferredQuality") private var preferredQuality = 0
    @AppStorage("playbackSpeed") private var playbackSpeed = 1.0
    @AppStorage("heroAutoplay") private var heroAutoplay = true

    /// 弹窗选择的类别。
    private enum ActivePicker: String, Identifiable {
        case quality, speed
        var id: String { rawValue }
    }

    /// 清晰度选项：与 iOS 端一致，0 = 自动 · 优先高清。
    private static let qualityOptions = [0, 1080, 720, 480]
    /// 倍速选项：与 iOS 端 playbackSpeeds 一致。
    private static let speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    private static func qualityLabel(_ value: Int) -> String {
        value == 0 ? "自动 · 优先高清" : "\(value)P"
    }

    /// 统计卡片里能按的两张（在追、看过的剧），焦点放大用。
    private enum StatLink: Hashable { case following, watched }
    @FocusState private var focusedStat: StatLink?
    @State private var showsHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header
                    statTiles
                    HStack(alignment: .top, spacing: 40) {
                        VStack(alignment: .leading, spacing: TVTheme.sectionSpacing) {
                            playbackGroup
                            heroGroup
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: TVTheme.sectionSpacing) {
                            followGroup
                            if appState.allSources { sourceGroup }
                            storageAboutGroup
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 40)
                .padding(.bottom, 60)
            }
            .sheet(item: $activePicker) { picker in
                pickerSheet(picker)
            }
            .confirmationDialog("清除全部观看记录？", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("清除", role: .destructive) { store.clearHistory() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("「继续观看」会被清空，追剧列表不受影响。")
            }
            .task {
                storageBytes = await Self.cachesSize()
            }
            .navigationDestination(isPresented: $showsHistory) {
                WatchHistoryView()
            }
            .onAppear {
                // 开发验证用：启动参数 -GUOAppShowHistory YES 直接打开观看记录（只对这次启动有效）。
                if UserDefaults.standard.bool(forKey: "GUOAppShowHistory") { showsHistory = true }
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 32) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(TVTheme.accentGradient)
                .frame(width: 128, height: 128)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(TVTheme.textPrimary)
                }
                .shadow(color: TVTheme.accent.opacity(0.35), radius: 30, y: 12)
            VStack(alignment: .leading, spacing: 10) {
                Text(tvAppDisplayName)
                    .font(.system(size: TVTheme.TextSize.title2, weight: .heavy))
                    .foregroundColor(TVTheme.textPrimary)
                Text("在电视上追短剧 · 版本 \(appVersion) · 核心 \(coreRevision)")
                    .font(.system(size: TVTheme.TextSize.caption))
                    .foregroundColor(TVTheme.textSecondary)
            }
        }
    }

    // MARK: - 观看统计

    private var stats: ViewingStats {
        ViewingStats.make(
            follows: store.follows.count,
            entries: store.progress.map { (dramaID: $0.drama.id, position: $0.position, duration: $0.duration) }
        )
    }

    private var statTiles: some View {
        let stats = stats
        return HStack(spacing: 24) {
            // 在追 → 追剧页；看过的剧 → 观看记录（owner 2026-11-08）；另外两张只显示数字。
            statLink(.following, value: "\(stats.following)", label: "在追") {
                NotificationCenter.default.post(name: .selectTab, object: KeepAliveTabBarController.followTabIndex)
            }
            statLink(.watched, value: "\(stats.dramasWatched)", label: "看过的剧") {
                showsHistory = true
            }
            statTile(value: "\(stats.episodesFinished)", unit: nil, label: "看完的集")
            statTile(value: String(format: "%.1f", stats.hoursWatched), unit: "小时", label: "累计观看")
        }
        .focusSection()
    }

    /// 能按的统计卡片：标签后带「›」，获得焦点时与海报一样放大、描白边。
    private func statLink(_ link: StatLink, value: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            statTile(value: value, unit: nil, label: label, opens: true)
        }
        .buttonStyle(TVPressButtonStyle())
        .focused($focusedStat, equals: link)
        .tvFocusEffect(focused: focusedStat == link, scale: 1.04, cornerRadius: 20)
    }

    private func statTile(value: String, unit: String?, label: String, opens: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: TVTheme.TextSize.title2, weight: .heavy).monospacedDigit())
                    .foregroundColor(TVTheme.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.system(size: TVTheme.TextSize.callout, weight: .semibold))
                        .foregroundColor(TVTheme.textPrimary)
                }
            }
            Text(opens ? "\(label) ›" : label)
                .font(.system(size: TVTheme.TextSize.caption))
                .foregroundColor(TVTheme.textSecondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(TVTheme.surfaceDim))
    }

    // MARK: - 播放 / 推荐

    private var playbackGroup: some View {
        TVSettingGroup(title: "播放") {
            TVToggleRow(title: "播完自动连播下一集", isOn: $autoAdvance)
            TVSettingDivider()
            TVValueRow(title: "清晰度", value: Self.qualityLabel(preferredQuality)) {
                activePicker = .quality
            }
            TVSettingDivider()
            TVValueRow(title: "播放倍速", value: String(format: "%.2fx", playbackSpeed)) {
                activePicker = .speed
            }
            TVSettingDivider()
            TVToggleRow(title: "弹幕", isOn: $danmakuEnabled)
            TVSettingDivider()
            TVToggleRow(title: "播放诊断", isOn: $diagnosticsEnabled)
            TVSettingDivider()
            note("清晰度在下一次打开剧集时生效；倍速和弹幕也可在播放时从控件里实时调整。")
        }
    }

    private var heroGroup: some View {
        TVSettingGroup(title: "推荐") {
            TVToggleRow(title: "进入推荐页自动播放", isOn: $heroAutoplay)
            TVSettingDivider()
            note(heroAutoplay ? "进入推荐页就开始播放（有声）。" : "推荐页先显示封面，按播放键或「播放」才开始。")
        }
    }

    // MARK: - 追剧

    private var followGroup: some View {
        TVSettingGroup(title: "追剧") {
            TVValueRow(title: "检查追剧更新", value: followCheckLabel) {
                checker.checkIfDue(store: store, force: true)
            }
            TVSettingDivider()
            TVValueRow(title: "清除观看记录", value: store.recentHistory.isEmpty ? "暂无记录" : "") {
                confirmClearHistory = true
            }
        }
    }

    private var followCheckLabel: String {
        if checker.isChecking { return "正在检查…" }
        let updated = store.updatedFollowCount
        if updated > 0 { return FollowUpdate.summary(updatedCount: updated) }
        return checker.lastFinished == nil ? "" : "刚刚检查"
    }

    // MARK: - 站源（全部站源的版本才有多个可选）

    private var sourceGroup: some View {
        TVSettingGroup(title: "站源") {
            let sites = SourceSite.available(allSources: appState.allSources)
            ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                if index > 0 {
                    TVSettingDivider()
                }
                TVSettingRow {
                    appState.selectedSource = site.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(site.name)
                                .font(.system(size: TVTheme.TextSize.body, weight: .medium))
                            Text(site.description)
                                .font(.system(size: TVTheme.TextSize.caption2))
                                .foregroundColor(TVTheme.textSecondary)
                        }
                        Spacer()
                        if site.id == appState.selectedSource {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: TVTheme.TextSize.body))
                                .foregroundColor(TVTheme.accent)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 存储与关于

    private var storageAboutGroup: some View {
        TVSettingGroup(title: "存储与关于") {
            infoRow("已用空间", storageBytes.map { StorageSize.label(bytes: $0) } ?? "正在计算…")
            TVSettingDivider()
            infoRow("站源", SourceSite.available(allSources: appState.allSources)
                .first { $0.id == appState.selectedSource }?.name ?? appState.selectedSource)
            TVSettingDivider()
            infoRow("版本", appVersion)
            TVSettingDivider()
            infoRow("核心", coreRevision)
            TVSettingDivider()
            note("原生 tvOS 应用 · Go 核心 · MPV 播放")
            note("在海报上按播放键直接播放；继续观看卡片长按可查看详情或移除")
            note("播放时点按或按 ↑↓ 调出控件：倍速、选集；← → 快退 / 快进 10 秒")
            note("追剧与观看进度存在 Caches，系统空间不足时可能被清理。")
        }
    }

    /// 只显示、不可操作的一行（标题 + 右侧值）。
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: TVTheme.TextSize.body, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: TVTheme.TextSize.caption))
                .foregroundColor(TVTheme.textSecondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: TVTheme.TextSize.caption2))
            .foregroundColor(TVTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
    }

    // MARK: - 选项弹窗

    @ViewBuilder
    private func pickerSheet(_ picker: ActivePicker) -> some View {
        switch picker {
        case .quality:
            TVOptionSheet(
                title: "清晰度",
                options: Self.qualityOptions.map { TVOption(value: $0, label: Self.qualityLabel($0)) },
                selection: $preferredQuality
            )
        case .speed:
            TVOptionSheet(
                title: "播放倍速",
                options: Self.speedOptions.map { TVOption(value: $0, label: String(format: "%.2fx", $0)) },
                selection: $playbackSpeed
            )
        }
    }

    // MARK: - 版本信息

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return short.isEmpty ? build : "\(short) (\(build))"
    }

    /// 构建时写进 Info.plist 的 upstream 短哈希；没有（本地调试构建）时显示「—」。
    private var coreRevision: String {
        let revision = Bundle.main.object(forInfoDictionaryKey: "GUOAppCoreRevision") as? String ?? ""
        return revision.isEmpty ? "—" : revision
    }

    /// Caches 文件夹（核心数据、封面、观看记录都在这里）占用的空间，在后台线程里算。
    private static func cachesSize() async -> Int64 {
        await Task.detached(priority: .utility) { directorySize(of: cachesDirectory) }.value
    }

    private nonisolated static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private nonisolated static func directorySize(of directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}

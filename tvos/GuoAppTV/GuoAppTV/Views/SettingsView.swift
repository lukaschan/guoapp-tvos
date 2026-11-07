import SwiftUI

/// 「我的」（redfruit 样式）：左栏应用图标与名称，右栏分组设置。
///
/// - 站源：分组行内直接选择，当前站源打勾；
/// - 播放：开关行点按即切换；清晰度 / 倍速弹出居中选项卡（默认聚焦当前值）；
/// - 观看记录：清除全部观看记录（追剧不受影响）；
/// - 关于：版本与说明信息。
/// 配置项与存储键（AppStorage）与原版完全一致。
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: Store
    @State private var confirmClearHistory = false
    @AppStorage("danmakuEnabled") private var danmakuEnabled = true
    @AppStorage("autoAdvance") private var autoAdvance = true
    @AppStorage("playbackDiagnostics") private var diagnosticsEnabled = false
    @AppStorage("preferredQuality") private var preferredQuality = 0
    @AppStorage("playbackSpeed") private var playbackSpeed = 1.0

    @State private var activePicker: ActivePicker?

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

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 80) {
                identityColumn
                ScrollView {
                    VStack(alignment: .leading, spacing: TVTheme.sectionSpacing) {
                        sourceGroup
                        playbackGroup
                        historyGroup
                        aboutGroup
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 56)
                }
            }
            .padding(.horizontal, 80)
            .sheet(item: $activePicker) { picker in
                pickerSheet(picker)
            }
            .confirmationDialog("清除全部观看记录？", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("清除", role: .destructive) { store.clearHistory() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("「继续观看」会被清空，追剧列表不受影响。")
            }
        }
    }

    // MARK: - 左栏

    private var identityColumn: some View {
        VStack(alignment: .leading, spacing: 28) {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(TVTheme.accentGradient)
                .frame(width: 320, height: 320)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 140, weight: .bold))
                        .foregroundColor(TVTheme.textPrimary)
                }
                .shadow(color: TVTheme.accent.opacity(0.35), radius: 40, y: 16)
            VStack(alignment: .leading, spacing: 10) {
                Text(tvAppDisplayName)
                    .font(.system(size: TVTheme.TextSize.title2, weight: .heavy))
                    .foregroundColor(TVTheme.textPrimary)
                Text("在电视上追短剧")
                    .font(.system(size: TVTheme.TextSize.body))
                    .foregroundColor(TVTheme.textSecondary)
            }
        }
        .frame(width: 560, alignment: .leading)
        .padding(.top, 120)
    }

    // MARK: - 观看记录

    private var historyGroup: some View {
        TVSettingGroup(title: "观看记录") {
            TVValueRow(title: "清除观看记录", value: store.recentHistory.isEmpty ? "暂无记录" : "") {
                confirmClearHistory = true
            }
        }
    }

    // MARK: - 站源

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

    // MARK: - 播放

    private var playbackGroup: some View {
        TVSettingGroup(title: "播放") {
            TVToggleRow(title: "弹幕", isOn: $danmakuEnabled)
            TVSettingDivider()
            TVToggleRow(title: "播完自动连播下一集", isOn: $autoAdvance)
            TVSettingDivider()
            TVToggleRow(title: "播放诊断", isOn: $diagnosticsEnabled)
            TVSettingDivider()
            TVValueRow(title: "清晰度", value: Self.qualityLabel(preferredQuality)) {
                activePicker = .quality
            }
            TVSettingDivider()
            TVValueRow(title: "播放倍速", value: String(format: "%.2fx", playbackSpeed)) {
                activePicker = .speed
            }
            TVSettingDivider()
            Text("清晰度在下一次打开剧集时生效；倍速也可在播放时从控件里实时调整。")
                .font(.system(size: TVTheme.TextSize.caption2))
                .foregroundColor(TVTheme.textTertiary)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
        }
    }

    // MARK: - 关于

    private var aboutGroup: some View {
        TVSettingGroup(title: "关于") {
            HStack {
                Text("版本")
                    .font(.system(size: TVTheme.TextSize.body, weight: .medium))
                Spacer()
                Text(appVersion)
                    .font(.system(size: TVTheme.TextSize.caption))
                    .foregroundColor(TVTheme.textSecondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            aboutNote("原生 tvOS 应用 · Go 核心 · MPV 播放")
            aboutNote("在海报上按播放键直接播放")
            aboutNote("继续观看卡片长按可查看详情或移除")
            aboutNote("播放时点按或按 ↑↓ 调出控件：倍速、画面、选集；← → 快退 / 快进 10 秒")
            aboutNote("追剧与观看进度存在 Caches，系统空间不足时可能被清理。")
        }
    }

    private func aboutNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: TVTheme.TextSize.caption2))
            .foregroundColor(TVTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                TVSettingDivider()
            }
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

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return short.isEmpty ? build : "\(short) (\(build))"
    }
}

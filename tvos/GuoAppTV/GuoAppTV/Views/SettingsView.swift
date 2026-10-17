import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("danmakuEnabled") private var danmakuEnabled = true
    @AppStorage("autoAdvance") private var autoAdvance = true
    @AppStorage("playbackDiagnostics") private var diagnosticsEnabled = false
    @AppStorage("preferredQuality") private var preferredQuality = 0
    @AppStorage("playbackSpeed") private var playbackSpeed = 1.0

    /// 清晰度选项：与 iOS 端一致，0 = 自动 · 优先高清。
    private static let qualityOptions = [0, 1080, 720, 480]
    /// 倍速选项：与 iOS 端 playbackSpeeds 一致。
    private static let speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    private static func qualityLabel(_ value: Int) -> String {
        value == 0 ? "自动 · 优先高清" : "\(value)P"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("站源") {
                    ForEach(SourceSite.available(allSources: appState.allSources)) { site in
                        Button {
                            appState.selectedSource = site.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(site.name)
                                    Text(site.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if site.id == appState.selectedSource {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section("播放") {
                    Toggle("弹幕", isOn: $danmakuEnabled)
                    Toggle("播完自动连播下一集", isOn: $autoAdvance)
                    Toggle("播放诊断", isOn: $diagnosticsEnabled)
                    Picker("清晰度", selection: $preferredQuality) {
                        ForEach(Self.qualityOptions, id: \.self) { value in
                            Text(Self.qualityLabel(value)).tag(value)
                        }
                    }
                    Picker("播放倍速", selection: $playbackSpeed) {
                        ForEach(Self.speedOptions, id: \.self) { value in
                            Text(String(format: "%.2fx", value)).tag(value)
                        }
                    }
                    Text("清晰度与倍速在下一次打开剧集时生效。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(appVersion).foregroundColor(.secondary)
                    }
                    Text("原生 tvOS 应用 · Go 核心 · mpv 播放")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("未签名包需在 Mac 上用 Xcode 签名后安装到 Apple TV。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("追剧与观看进度存在 Caches，系统空间不足时可能被清理。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return short.isEmpty ? build : "\(short) (\(build))"
    }
}

import SwiftUI

struct SettingsView: View {
    let playback: BookPlayback
    @Environment(\.dismiss) private var dismiss
    @State private var showingCredits = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("翻书的感觉").font(.custom("NotoSerifSC-Regular", size: 27))
                        Text("给这段时间，留一点仪式感。").foregroundStyle(PaperTheme.muted)
                    }
                    VStack(spacing: 22) {
                        Toggle(isOn: Binding(get: { playback.preferences.soundEnabled }, set: playback.setSoundEnabled)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("声音")
                                Text("翻页与合书的声音").font(.footnote).foregroundStyle(PaperTheme.muted)
                            }
                        }.accessibilityIdentifier("settings-sound")
                        Divider()
                        Toggle(isOn: Binding(get: { playback.preferences.hapticsEnabled }, set: playback.setHapticsEnabled)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("轻微震动")
                                Text("随翻书动作轻轻回应").font(.footnote).foregroundStyle(PaperTheme.muted)
                            }
                        }.accessibilityIdentifier("settings-haptics")
                    }
                    .padding(22).background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--haptics-diagnostics") {
                        Button("触觉检查（临时）") { playback.haptics.diagnosticImpact() }
                            .disabled(!playback.preferences.hapticsEnabled)
                        Text("用于对比直接触觉与翻书反馈，不修改设置或记录。")
                            .font(.footnote).foregroundStyle(PaperTheme.muted)
                    }
                    #endif
                    VStack(alignment: .leading, spacing: 14) {
                        Text("声音开启时，会暂停其他音乐。合上书或离开 App 后，其他播放器可以恢复播放。")
                        Text("系统静音时没有翻书声，但仍可能暂停音乐。在这里关闭声音后，App 不会主动打断音乐。")
                    }.font(.footnote).foregroundStyle(PaperTheme.muted).lineSpacing(5)
                    VStack(spacing: 8) {
                        Text("答案之书").font(.custom("NotoSerifSC-Regular", size: 19))
                        Text("把片刻留给自己").font(.footnote).foregroundStyle(PaperTheme.muted)
                        Button("音效来源") { showingCredits = true }.padding(.top, 14)
                    }.frame(maxWidth: .infinity).padding(.top, 20)
                }.padding(24)
            }
            .background(PaperTheme.paper).foregroundStyle(PaperTheme.ink)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PaperTheme.paper, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }.accessibilityIdentifier("settings-done")
            } }
            .sheet(isPresented: $showingCredits) { AudioCreditsView() }
        }
        .tint(PaperTheme.gold).preferredColorScheme(.light)
    }
}

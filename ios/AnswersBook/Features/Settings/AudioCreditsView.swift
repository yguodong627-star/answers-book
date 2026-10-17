import SwiftUI

struct AudioCreditsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("翻页实录") {
                    Text("Book, Flipping Through Pages, A.wav — InspectorJ (www.jshaw.co.uk)")
                    Link("原始作品 / Freesound", destination: URL(string: "https://freesound.org/people/InspectorJ/sounds/416179/")!)
                    Link("Creative Commons Attribution 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    Text("从公开HQ MP3整段原速使用，转换PCM格式、调整静态增益与端点淡化，放置到开合时间线；未变速、未循环。")
                }
                Section("微弱合拢声") {
                    Text("Closed book #1 — Joseph SARDIN / BigSoundBank，CC0")
                    Link("原始作品", destination: URL(string: "https://bigsoundbank.com/closed-book-1-s1410.html")!)
                }
            }
            .navigationTitle("音效来源")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

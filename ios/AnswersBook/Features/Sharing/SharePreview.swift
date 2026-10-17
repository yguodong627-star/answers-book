import SwiftUI
import UIKit

struct SharePreview: View {
    let content: ShareContent
    @Environment(\.dismiss) private var dismiss
    @State private var includeNote = false
    @State private var image: UIImage?
    @State private var failure: String?
    @State private var showingActivity = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel(content.label(includeNote: includeNote))
                            .accessibilityIdentifier("share-card")
                            .shadow(color: .brown.opacity(0.16), radius: 12, y: 7)
                    }
                    if content.hasNote {
                        Toggle(isOn: Binding(get: { includeNote }, set: { value in
                            includeNote = value; image = nil; regenerate()
                        })) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("包含我的问题")
                                Text(includeNote ? "分享答案及问题备注" : "当前仅分享答案")
                                    .font(.footnote).foregroundStyle(PaperTheme.muted)
                            }
                        }.accessibilityIdentifier("share-include-note")
                    }
                    if let failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("share-error") }
                    Button { showingActivity = true } label: {
                        Label("分享卡片", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent).disabled(image == nil)
                    .accessibilityIdentifier("share-export")
                    Text("选择保存图片，或分享给朋友。")
                        .font(.footnote).foregroundStyle(PaperTheme.muted)
                }.padding(24)
            }
            .background(PaperTheme.paper).foregroundStyle(PaperTheme.ink)
            .navigationTitle("分享预览").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("返回") { dismiss() }.accessibilityIdentifier("share-done")
            } }
            .onAppear { if image == nil { regenerate() } }
            .sheet(isPresented: $showingActivity) {
                if let image { ShareActivity(image: image) }
            }
        }.tint(PaperTheme.gold).preferredColorScheme(.light)
    }

    @MainActor private func regenerate() {
        image = nil; failure = nil
        let card = ShareCard(content: content, includeNote: includeNote).frame(width: 360)
        let host = UIHostingController(rootView: card)
        let size = host.sizeThatFits(in: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude))
        // 限制单张图片的内存预算，不限制或截断用户备注；超出时明确提示。
        guard size.height.isFinite, size.height > 0, size.height <= 20000 else {
            failure = "备注较长，暂时无法生成完整图片。可以关闭“包含我的问题”后分享答案。"; return
        }
        let renderer = ImageRenderer(content: card.frame(height: size.height))
        renderer.scale = min(3, sqrt(12_000_000 / (360 * size.height)))
        renderer.isOpaque = true
        guard let rendered = renderer.uiImage else {
            failure = "卡片生成失败，请重试"; return
        }
        image = rendered
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = rendered.pngData() {
            let name = includeNote ? "T16-包含问题.png" : "T16-仅答案.png"
            try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        #endif
    }
}

private struct ShareActivity: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

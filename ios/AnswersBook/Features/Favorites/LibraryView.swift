import SwiftUI

struct LibraryView: View {
    let session: DrawSession
    @Environment(\.dismiss) private var dismiss
    @State private var editingRecord: RecordSnapshot?
    @State private var sharing: ShareContent?
    @State private var historySelected = false
    private enum Removal { case record(RecordSnapshot), unfavorited }
    @State private var removal: Removal?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Button("收藏") { historySelected = false }
                            .frame(maxWidth: .infinity).padding(10)
                            .background(historySelected ? Color.clear : .white.opacity(0.8), in: Capsule())
                            .accessibilityIdentifier("library-favorites")
                        Button("历史") { historySelected = true }
                            .frame(maxWidth: .infinity).padding(10)
                            .background(historySelected ? .white.opacity(0.8) : Color.clear, in: Capsule())
                            .accessibilityIdentifier("library-history")
                    }
                    .padding(4).background(PaperTheme.gold.opacity(0.1), in: Capsule())
                    Text(historySelected ? "每一次翻阅" : "留给自己的话")
                        .font(.custom("NotoSerifSC-Regular", size: 26))
                    Text(historySelected ? "清空时会保留收藏及其问题备注" : "查看或补记自己的问题")
                        .font(.subheadline).foregroundStyle(PaperTheme.muted)
                    if let failure = session.failure {
                        Text(failure).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("library-error")
                    }
                    if historySelected {
                        HistoryList(session: session, onShare: { sharing = ShareContent(record: $0) },
                                    onDelete: { removal = .record($0) })
                    } else {
                        if session.favorites.isEmpty {
                            ContentUnavailableView("还没有收藏", systemImage: "star",
                                                   description: Text("遇到喜欢的答案时，轻点收藏，留给以后的自己。"))
                                .accessibilityIdentifier("favorites-empty")
                        }
                        ForEach(session.favorites) { entry in
                            RecordCard(entry: entry) {
                                HStack {
                                    Button(entry.note == nil ? "添加问题或备注" : "编辑问题") { editingRecord = entry }
                                        .accessibilityIdentifier("note-edit-\(entry.id)")
                                    Spacer()
                                    Button { sharing = ShareContent(record: entry) } label: {
                                        Label("分享", systemImage: "square.and.arrow.up")
                                            .frame(minWidth: 64, minHeight: 44)
                                    }
                                    .accessibilityLabel("分享答案")
                                    .accessibilityIdentifier("share-record-\(entry.id)")
                                    Button("取消收藏") { session.setFavorite(id: entry.id, value: false) }
                                        .accessibilityIdentifier("unfavorite-\(entry.id)")
                                }.font(.footnote).frame(minHeight: 44)
                            }
                        }
                    }
                }.padding(24)
            }
            .background(PaperTheme.paper).foregroundStyle(PaperTheme.ink)
            .navigationTitle("藏书").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PaperTheme.paper, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("返回") { dismiss() }.accessibilityIdentifier("library-done")
            }
                ToolbarItem(placement: .confirmationAction) {
                    if historySelected {
                        Button("清空") { removal = .unfavorited }
                            .disabled(!session.records.contains { !$0.isFavorite })
                            .accessibilityIdentifier("history-clear")
                    }
                }
            }
        }
        .alert(removalTitle, isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), presenting: removal) { request in
            Button(removalButton(request), role: .destructive) {
                switch request {
                case .record(let entry): session.deleteRecord(id: entry.id, confirmFavorite: true)
                case .unfavorited: session.clearUnfavoritedHistory()
                }
            }
            Button("取消", role: .cancel) {}
        } message: { request in
            switch request {
            case .record(let entry):
                Text(entry.isFavorite ? "这条记录已收藏。删除后，收藏和问题备注也会一起删除，无法恢复。" : "将删除这次翻阅记录和已有问题备注，无法恢复。")
            case .unfavorited:
                Text("只删除未收藏的历史记录，收藏及其问题备注会保留。")
            }
        }
        .sheet(item: $editingRecord) { entry in NoteEditor(entry: entry, session: session) }
        .sheet(item: $sharing) { SharePreview(content: $0) }
        .tint(PaperTheme.gold).preferredColorScheme(.light)
    }
    private var removalTitle: String {
        if case .record = removal { return "删除这条记录？" }
        return "清空未收藏历史？"
    }
    private func removalButton(_ request: Removal) -> String {
        if case .record = request { return "删除记录" }
        return "清空未收藏历史"
    }
}

struct RecordCard<Actions: View>: View {
    let entry: RecordSnapshot
    var timeOnly = false
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(entry.createdAt, format: timeOnly ? .dateTime.hour().minute() : .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(PaperTheme.muted)
                Spacer()
                if entry.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(PaperTheme.gold).accessibilityLabel("已收藏")
                }
            }
            VStack(spacing: 8) {
                Text(entry.zh).font(.custom("NotoSerifSC-Regular", size: 23))
                Text(entry.en).font(.custom("Georgia", size: 16)).foregroundStyle(PaperTheme.muted)
            }.frame(maxWidth: .infinity).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let note = entry.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("我的问题").font(.caption).foregroundStyle(PaperTheme.muted)
                    Text(note).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            actions()
        }
        .padding(22).background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(PaperTheme.gold.opacity(0.15), lineWidth: 0.7))
    }
}

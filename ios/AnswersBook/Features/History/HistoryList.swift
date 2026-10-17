import SwiftUI

struct HistoryList: View {
    let session: DrawSession
    let onShare: (RecordSnapshot) -> Void
    let onDelete: (RecordSnapshot) -> Void
    private var days: [Date] {
        Set(session.records.map { Calendar.current.startOfDay(for: $0.createdAt) }).sorted(by: >)
    }

    var body: some View {
        if session.records.isEmpty {
            ContentUnavailableView("还没有翻阅记录", systemImage: "clock",
                                   description: Text("带着一个小问题，翻开书页。"))
                .accessibilityIdentifier("history-empty")
        }
        ForEach(days, id: \.self) { day in
            Text(day, format: .dateTime.year().month().day())
                .font(.headline).foregroundStyle(PaperTheme.muted)
            ForEach(session.records.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }) { entry in
                RecordCard(entry: entry, timeOnly: true) {
                    HStack {
                        Spacer()
                        Button { onShare(entry) } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .frame(minWidth: 64, minHeight: 44)
                        }
                        .font(.footnote).accessibilityLabel("分享答案")
                        .accessibilityIdentifier("history-share-\(entry.id)")
                        Menu {
                            Button(entry.isFavorite ? "取消收藏" : "收藏") {
                                session.setFavorite(id: entry.id, value: !entry.isFavorite)
                            }.accessibilityIdentifier("history-favorite-\(entry.id)")
                            Button("删除记录", role: .destructive) { onDelete(entry) }
                                .accessibilityIdentifier("history-delete-\(entry.id)")
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("记录操作").accessibilityIdentifier("history-menu-\(entry.id)")
                    }
                }
            }
        }
    }
}

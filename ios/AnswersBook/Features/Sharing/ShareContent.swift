import Foundation

/// 分享只持有本次答案值快照，不更新抽取、收藏或备注。
struct ShareContent: Identifiable {
    let id: UUID
    let zh: String
    let en: String
    let note: String?

    init(record: RecordSnapshot) {
        id = record.id; zh = record.zh; en = record.en; note = record.note
    }
    init(id: UUID, answer: BookAnswer) {
        self.id = id; zh = answer.zh; en = answer.en; note = nil
    }
    var hasNote: Bool { !(note ?? "").isEmpty }
    func label(includeNote: Bool) -> String {
        [zh, en, includeNote ? note : nil, "答案之书"].compactMap { $0 }.joined(separator: "\n")
    }
}

import Foundation

/// 同一持久化记录的界面值快照，UUID始终为原抽取UUID，不另建收藏账本。
struct RecordSnapshot: Identifiable, Equatable {
    let id: UUID
    let answerID: String
    let zh: String
    let en: String
    let createdAt: Date
    var isFavorite: Bool
    var note: String?

    init(_ record: BookRecord) {
        id = record.id; answerID = record.answerID
        zh = record.chineseSnapshot; en = record.englishSnapshot
        createdAt = record.createdAt; isFavorite = record.isFavorite; note = record.note
    }
}

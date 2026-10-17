import Foundation
import SwiftData

/// 首版版本化模型；升级时增加schema与迁移阶段，不覆盖已有数据库。
enum BookSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Entry.self] }

    @Model final class Entry {
        @Attribute(.unique) var id: UUID
        var answerID: String
        var chineseSnapshot: String
        var englishSnapshot: String
        var createdAt: Date
        var isFavorite: Bool
        var note: String?

        init(id: UUID, answer: BookAnswer, createdAt: Date) {
            self.id = id
            answerID = answer.id
            chineseSnapshot = answer.zh
            englishSnapshot = answer.en
            self.createdAt = createdAt
            isFavorite = false
            note = nil
        }
    }
}

enum BookMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BookSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias BookRecord = BookSchemaV1.Entry

@MainActor final class RecordStore {
    enum Failure: LocalizedError {
        case invalidAnswer, duplicateID, missingRecord, saveFailed, favoriteNeedsConfirmation
        var errorDescription: String? {
            switch self {
            case .invalidAnswer: "答案内容无效，未保存记录"
            case .duplicateID: "记录编号重复，未覆盖已有记录"
            case .missingRecord: "未找到这条记录"
            case .favoriteNeedsConfirmation: "删除已收藏记录前，需要确认同时删除收藏和备注"
            case .saveFailed: "记录保存失败，请重试"
            }
        }
    }
    private let allowsSave: Bool
    private let container: ModelContainer
    private let context: ModelContext

    init(url: URL, allowsSave: Bool = true) throws {
        self.allowsSave = allowsSave
        let schema = Schema(versionedSchema: BookSchemaV1.self)
        let config = ModelConfiguration("AnswersBook", schema: schema, url: url,
                                        allowsSave: allowsSave, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, migrationPlan: BookMigrationPlan.self, configurations: [config])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    static func local() throws -> RecordStore {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnswersBook", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try RecordStore(url: folder.appendingPathComponent("Records.store"))
    }

    func insert(answer: BookAnswer, id: UUID = UUID(), date: Date = Date()) throws -> BookRecord {
        guard allowsSave else { throw Failure.saveFailed }
        guard !answer.id.isEmpty, !answer.zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !answer.en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidAnswer }
        guard try record(id: id) == nil else { throw Failure.duplicateID }
        let entry = BookRecord(id: id, answer: answer, createdAt: date)
        context.insert(entry)
        try save()
        return entry
    }

    func record(id: UUID) throws -> BookRecord? {
        var query = FetchDescriptor<BookRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 1
        return try context.fetch(query).first
    }

    func records() throws -> [BookRecord] {
        try context.fetch(FetchDescriptor<BookRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    func count() throws -> Int { try context.fetchCount(FetchDescriptor<BookRecord>()) }

    func update(id: UUID, isFavorite: Bool, note: String?) throws {
        guard allowsSave else { throw Failure.saveFailed }
        guard let entry = try record(id: id) else { throw Failure.missingRecord }
        entry.isFavorite = isFavorite
        entry.note = note
        try save()
    }

    func delete(id: UUID, confirmFavorite: Bool = false) throws {
        guard allowsSave else { throw Failure.saveFailed }
        guard let entry = try record(id: id) else { throw Failure.missingRecord }
        guard !entry.isFavorite || confirmFavorite else { throw Failure.favoriteNeedsConfirmation }
        context.delete(entry)
        try save()
    }

    /// 一次保存提交全部未收藏记录的删除；收藏及备注保持原记录。
    func clearUnfavorited() throws -> [UUID] {
        guard allowsSave else { throw Failure.saveFailed }
        let entries = try context.fetch(FetchDescriptor<BookRecord>(predicate: #Predicate { !$0.isFavorite }))
        let ids = entries.map(\.id)
        for entry in entries { context.delete(entry) }
        try save()
        return ids
    }

    private func save() throws {
        do { try context.save() }
        catch { context.rollback(); throw Failure.saveFailed }
    }
}

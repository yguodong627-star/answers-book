import Foundation
import Observation

/// 抽取只发生在BookPlayback接受有效开书手势时；显示使用已保存的值快照。
@MainActor @Observable final class DrawSession {
    struct DrawnAnswer {
        let recordID: UUID
        let answer: BookAnswer
        let page: Int
    }
    private let catalog: AnswerCatalog?
    private let store: RecordStore?
    private let selectIndex: (Int) -> Int
    private(set) var current: DrawnAnswer?
    private(set) var records: [RecordSnapshot] = []
    var recordCount: Int { records.count }
    var favorites: [RecordSnapshot] { records.filter(\.isFavorite) }
    var currentRecord: RecordSnapshot? { records.first { $0.id == current?.recordID } }
    private(set) var failure: String?

    init(catalog: Result<AnswerCatalog, Error>, store: Result<RecordStore, Error>,
         selectIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }) {
        self.selectIndex = selectIndex
        do {
            let loaded = try catalog.get()
            let records = try store.get()
            self.records = try records.records().map(RecordSnapshot.init)
            self.catalog = loaded
            self.store = records
        } catch {
            self.catalog = nil
            self.store = nil
            failure = "无法加载答案或本地记录，请重试；已有记录未清除"
        }
    }

    /// 保存成功后才发布当前答案；失败不播放开书，不伪造记录成功。
    func draw() -> Bool {
        guard let catalog, let store else { return false }
        let index = selectIndex(catalog.answers.count)
        guard catalog.answers.indices.contains(index) else {
            failure = "答案抽取失败，请重试"; return false
        }
        let answer = catalog.answers[index]
        do {
            let record = try store.insert(answer: answer)
            current = DrawnAnswer(recordID: record.id,
                                  answer: BookAnswer(id: record.answerID, zh: record.chineseSnapshot,
                                                     en: record.englishSnapshot, category: answer.category),
                                  page: index + 1)
            records.insert(RecordSnapshot(record), at: 0)
            failure = nil
            return true
        } catch {
            failure = "记录保存失败，未开始翻书，请重试"
            return false
        }
    }

    @discardableResult func setFavorite(id: UUID, value: Bool) -> Bool {
        guard let store, let index = records.firstIndex(where: { $0.id == id }) else {
            failure = "未找到这条记录，请重新打开藏书"; return false
        }
        do {
            guard let saved = try store.record(id: id) else { throw RecordStore.Failure.missingRecord }
            try store.update(id: id, isFavorite: value, note: saved.note)
            records[index].isFavorite = value
            failure = nil
            return true
        } catch {
            failure = "收藏修改未保存，请重试"; return false
        }
    }

    @discardableResult func saveNote(id: UUID, text: String) -> Bool {
        guard let store, let index = records.firstIndex(where: { $0.id == id }) else {
            failure = "未找到这条记录，请重新打开藏书"; return false
        }
        do {
            guard let saved = try store.record(id: id) else { throw RecordStore.Failure.missingRecord }
            let note: String? = text.isEmpty ? nil : text // 保留原文、空格与标点，只将明确清空存为nil。
            try store.update(id: id, isFavorite: saved.isFavorite, note: note)
            records[index].note = note
            failure = nil
            return true
        } catch {
            failure = "问题或备注未保存，请重试"; return false
        }
    }

    @discardableResult func deleteRecord(id: UUID, confirmFavorite: Bool = false) -> Bool {
        guard let store else { return false }
        do {
            try store.delete(id: id, confirmFavorite: confirmFavorite)
            records.removeAll { $0.id == id }
            // 当前纸面继续显示已发布的答案值，不能因历史操作在阅读中换句或重抽。
            failure = nil
            return true
        } catch {
            failure = (error as? RecordStore.Failure)?.errorDescription ?? "记录删除未保存，请重试"
            return false
        }
    }

    @discardableResult func clearUnfavoritedHistory() -> Bool {
        guard let store else { return false }
        do {
            let ids = Set(try store.clearUnfavorited())
            records.removeAll { ids.contains($0.id) }
            failure = nil
            return true
        } catch {
            failure = "历史清空未保存，请重试；已有记录仍保留"
            return false
        }
    }

    static func live() -> DrawSession {
        let store: Result<RecordStore, Error>
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-testing") {
            // 独立测试数据库，永远不重置或删除正常用户Records.store。
            let token = ProcessInfo.processInfo.environment["T10_STORE_TOKEN"] ?? UUID().uuidString
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("AnswersBook-test-\(token).store")
            store = Result {
                if args.contains("--draw-save-failure") {
                    _ = try RecordStore(url: url) // 创建空测试库后只读打开。
                    return try RecordStore(url: url, allowsSave: false)
                }
                let testStore = try RecordStore(url: url)
                if args.contains("--share-fixture"), try testStore.count() == 0 {
                    let answer = try AnswerCatalog.bundled.get().answers[44]
                    let entry = try testStore.insert(answer: answer)
                    try testStore.update(id: entry.id, isFavorite: true,
                                         note: ProcessInfo.processInfo.environment["T16_NOTE"] ?? "My private question.")
                }
                return testStore
            }
            if args.contains("--repeat-answer-045") {
                return DrawSession(catalog: AnswerCatalog.bundled, store: store, selectIndex: { _ in 44 })
            }
        } else { store = Result { try RecordStore.local() } }
        #else
        store = Result { try RecordStore.local() }
        #endif
        return DrawSession(catalog: AnswerCatalog.bundled, store: store)
    }
}

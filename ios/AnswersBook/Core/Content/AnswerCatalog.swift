import Foundation

struct BookAnswer: Decodable, Identifiable, Sendable {
    let id: String
    let zh: String
    let en: String
    let category: String
}

struct AnswerCatalog: Sendable {
    let answers: [BookAnswer]
    enum Invalid: LocalizedError {
        case resource, content
        var errorDescription: String? {
            switch self {
            case .resource: "缺少答案库，请检查安装资源"
            case .content: "答案库格式有误，暂时无法显示"
            }
        }
    }

    init(data: Data) throws {
        let decoded = try JSONDecoder().decode([BookAnswer].self, from: data)
        guard decoded.count >= 100 else { throw Invalid.content }
        var ids = Set<String>()
        for (index, answer) in decoded.enumerated() {
            let expected = String(format: "answer_%03d", index + 1)
            guard answer.id == expected, ids.insert(answer.id).inserted,
                  [answer.zh, answer.en, answer.category].allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
                  !answer.zh.contains("\n"), !answer.en.contains("\n"),
                  !"。.!！?？；;，,".contains(answer.zh.last!),
                  !"。.!！?？；;，,".contains(answer.en.last!) else { throw Invalid.content }
        }
        answers = decoded
    }

    func answer(id: String) -> BookAnswer? { answers.first { $0.id == id } }
    func page(of answer: BookAnswer) -> Int? { answers.firstIndex { $0.id == answer.id }.map { $0 + 1 } }
    var longestChinese: BookAnswer { answers.reduce(answers[0]) { $0.zh.count >= $1.zh.count ? $0 : $1 } }
    var longestEnglish: BookAnswer { answers.reduce(answers[0]) { $0.en.count >= $1.en.count ? $0 : $1 } }

    static let bundled: Result<AnswerCatalog, Error> = Result {
        guard let url = Bundle.main.url(forResource: "答案库_120条_双语_V0.2", withExtension: "json", subdirectory: "Answers/V0.2") else { throw Invalid.resource }
        return try AnswerCatalog(data: Data(contentsOf: url))
    }
}

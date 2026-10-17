import Foundation
import Observation

/// 独立本地偏好；不注册或重置数据库，不把测试首次安装用于实际用户数据。
@MainActor @Observable final class BookPreferences {
    private let defaults: UserDefaults
    private(set) var soundEnabled: Bool
    private(set) var hapticsEnabled: Bool

    init(defaults: UserDefaults) {
        self.defaults = defaults
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
    }
    func setSound(_ enabled: Bool) { defaults.set(enabled, forKey: "soundEnabled"); soundEnabled = enabled }
    func setHaptics(_ enabled: Bool) { defaults.set(enabled, forKey: "hapticsEnabled"); hapticsEnabled = enabled }

    static func live() -> BookPreferences {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let token = ProcessInfo.processInfo.environment["T10_STORE_TOKEN"] ?? UUID().uuidString
            return BookPreferences(defaults: UserDefaults(suiteName: "AnswersBook.tests.\(token)")!)
        }
        #endif
        return BookPreferences(defaults: .standard)
    }
}

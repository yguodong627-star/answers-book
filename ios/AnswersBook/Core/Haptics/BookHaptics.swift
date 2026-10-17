import Observation
import UIKit

/// T07原型：每次有效动作至多一次柔和反馈，触觉质感仍须真机确认。
@MainActor @Observable
final class BookHaptics {
    private(set) var enabled = true
    private(set) var requestCount = 0
    private var generator: UIImpactFeedbackGenerator?
    private var cue: Double?
    private var action = "none"
    private var events: [[String: String]] = []

    init(enabled: Bool = true) {
        self.enabled = enabled
        record("launch")
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if !value { cancel() }
        record(value ? "enabled" : "disabled")
        // 开启开关不补发当前动作的触觉，下一次有效开合才准备。
    }

    func begin(open: Bool) {
        cancel()
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        action = open ? "opening" : "closing"
        cue = open ? 0.80 : 1.80
        generator = UIImpactFeedbackGenerator(style: .light)
        generator?.prepare()
        record("armed")
    }

    func sync(videoTime: Double) {
        guard enabled, UIApplication.shared.applicationState == .active,
              let cue, videoTime.isFinite, videoTime >= cue else { return }
        self.cue = nil // 先消费，再请求系统；重复回调不重发。
        guard videoTime - cue <= 0.12 else {
            record("staleCueSkipped", videoTime: videoTime)
            generator = nil
            return
        }
        generator?.impactOccurred(intensity: 1)
        requestCount += 1
        record("impactRequested", videoTime: videoTime)
        generator = nil
    }

    func cancel() {
        if cue != nil { record("cancelled") }
        cue = nil; generator = nil
    }

    #if DEBUG
    /// 显式诊断模式的对照请求，不参与开合次数或正式设置。
    func diagnosticImpact() {
        guard ProcessInfo.processInfo.arguments.contains("--haptics-diagnostics"),
              enabled, UIApplication.shared.applicationState == .active else { return }
        let probe = UIImpactFeedbackGenerator(style: .light)
        probe.impactOccurred(intensity: 1)
        record("diagnosticRequested")
    }
    #endif

    private func record(_ event: String, videoTime: Double? = nil) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") ||
              ProcessInfo.processInfo.arguments.contains("--haptics-diagnostics") else { return }
        var entry = ["event": event, "uptime": String(ProcessInfo.processInfo.systemUptime),
                     "action": action, "enabled": String(enabled), "requestCount": String(requestCount)]
        if let videoTime { entry["videoTime"] = String(videoTime) }
        events.append(entry)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("T07-haptics.json")
        if let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
        #endif
    }
}

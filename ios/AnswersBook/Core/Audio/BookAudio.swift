import AVFoundation
import Observation
import UIKit

/// T06独立音轨；跟随视频媒体时间，阅读期间保留soloAmbient会话。
@MainActor @Observable
final class BookAudio {
    private(set) var enabled = true
    private(set) var sessionActive = false
    private(set) var effect: String?
    private(set) var failure: String?
    private var players: [String: AVAudioPlayer] = [:]
    private var observers: [NSObjectProtocol] = []
    private var events: [[String: String]] = []
    private var started = false
    private let session = AVAudioSession.sharedInstance()

    init(enabled: Bool = true) {
        self.enabled = enabled
        if !enabled { configureSilentPlayback() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           !ProcessInfo.processInfo.arguments.contains("--performance-probe"),
           let data = try? Data(contentsOf: Self.logURL),
           let previous = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] { events = previous }
        #endif
        loadPlayers()
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            if began { Task { @MainActor in self?.release(reason: "interruption") } }
            // 系统中断结束也不自动重播；下一次有效开合才激活。
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let unplugged = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            if unplugged { Task { @MainActor in self?.release(reason: "routeUnavailable") } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.stopEffect(); self.sessionActive = false
                self.loadPlayers(); self.record("mediaServicesReset")
            }
        })
        record("launch")
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if !value {
            release(reason: "soundOff")
            configureSilentPlayback()
        }
        record(value ? "soundEnabled" : "soundDisabled")
        // 打开设置开关不重播当前动作，也不主动打断音乐。
    }

    func begin(open: Bool) {
        stopEffect()
        guard enabled, UIApplication.shared.applicationState == .active else {
            record("activationSkipped"); return
        }
        do {
            try session.setCategory(.soloAmbient, mode: .default, options: [])
            if !sessionActive { try session.setActive(true); sessionActive = true; record("sessionActivated") }
            effect = open ? "翻书" : "合书"
            if let effect { players[effect]?.prepareToPlay() }
            failure = nil
            record("effectArmed")
        } catch {
            failure = "声音暂时无法播放，画面可继续使用"
            release(reason: "activationFailure")
            record("audioFailure")
        }
    }

    /// 无声视频也可能由系统隐式激活会话；关闭音效时必须允许其他音频混合。
    /// 这里只配置类别，不主动激活；下一次有声动作才切回soloAmbient。
    private func configureSilentPlayback() {
        do { try session.setCategory(.ambient, mode: .default, options: []) }
        catch {
            failure = "声音设置暂未生效，请重试"
            record("silentCategoryFailed")
        }
    }

    /// 从AVPlayer实际媒体时间启动，音轨自身包含已确认的前后静音。
    func sync(videoTime: Double) {
        guard enabled, sessionActive, let effect, let player = players[effect],
              videoTime.isFinite, videoTime >= 0 else { return }
        guard videoTime < player.duration else { stopEffect(); return }
        if !started {
            player.currentTime = videoTime
            if player.play() { started = true; record("effectStarted", videoTime: videoTime) }
            else { failure = "声音暂时无法播放，画面可继续使用"; release(reason: "playFailure") }
        } else if player.isPlaying, abs(player.currentTime - videoTime) > 0.08 {
            player.currentTime = videoTime
            record("driftCorrected", videoTime: videoTime)
        }
    }

    func videoPaused() {
        guard started, let effect, let player = players[effect] else { return }
        player.pause(); started = false
        record("effectPaused")
    }

    func stopEffect() {
        if effect != nil { record("effectStopped") }
        players.values.forEach { $0.stop(); $0.currentTime = 0 }
        started = false; effect = nil
    }

    func release(reason: String) {
        stopEffect()
        guard sessionActive else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
            record("sessionReleased", reason: reason)
        } catch {
            // 保留状态便于后续离开/关闭声音时重试，不伪称释放成功。
            failure = "音频会话暂未释放，请关闭声音或离开应用后重试"
            record("releaseFailed", reason: reason)
        }
    }

    private func loadPlayers() {
        players.removeAll()
        do {
            for name in ["翻书", "合书"] {
                guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Audio/V0.3/声音") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = 0
                players[name] = player
            }
        } catch { failure = "缺少声音资源，画面可继续使用"; record("resourceFailure") }
    }

    private static var logURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("T06-audio.json")
    }
    private func record(_ event: String, reason: String? = nil, videoTime: Double? = nil) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        var entry = ["event": event, "uptime": String(ProcessInfo.processInfo.systemUptime),
                     "enabled": String(enabled), "sessionActive": String(sessionActive),
                     "effect": effect ?? "none", "category": session.category.rawValue]
        if let reason { entry["reason"] = reason }
        if let videoTime { entry["videoTime"] = String(videoTime) }
        events.append(entry)
        if let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Self.logURL, options: .atomic)
        }
        #endif
    }
}

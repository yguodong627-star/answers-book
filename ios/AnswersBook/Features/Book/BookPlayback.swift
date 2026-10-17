import SwiftUI
import AVFoundation
import CoreText
import Observation
import UIKit
#if DEBUG
import os
#endif

/// 开合播放状态控制。结束以AVPlayer事件为准，不以素材时长计时切图。
@MainActor @Observable
final class BookPlayback {
    enum Phase: String { case closed, opening, reading, erasing, closing }
    private(set) var phase: Phase = .closed
    private(set) var revealStart: TimeInterval?
    private(set) var failure: String?
    private(set) var eraseID: UUID?
    private(set) var revealID: UUID?
    private(set) var inkReady = true
    private(set) var activeFrameReady = false
    private(set) var eraseStart: TimeInterval?
    private(set) var eraseInkLevel = 1.0
    private var eraseTime: TimeInterval = 0
    let preferences: BookPreferences
    let audio: BookAudio
    let haptics: BookHaptics
    private var audioTimeObserver: Any?
    private var audioPlayer: AVPlayer?
    private var audioStatus: NSKeyValueObservation?
    let opening: AVPlayer
    let closing: AVPlayer
    private var completionObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var generation = UUID()
    private var watchdog: Task<Void, Never>?
    private var triggerTime: TimeInterval = 0
    private var events: [[String: String]] = []
    #if DEBUG
    private var lastCompletion: (token: UUID, open: Bool)?
    private static let performanceLog = OSLog(subsystem: "AnswersBook.Performance", category: "BookPerformance")
    private var performanceInterval: StaticString?
    private let performanceEnabled = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        && ProcessInfo.processInfo.arguments.contains("--performance-probe")
    private var activePerformanceName: StaticString?
    private var activePerformanceID = OSSignpostID.invalid
    #endif

    static let revealDuration: TimeInterval = 1.5
    static let eraseDuration: TimeInterval = 0.75
    static let threshold: CGFloat = 64
    static func resource(_ name: String, type: String, directory: String) -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: type,
                                       subdirectory: "Book/V0.4/\(directory)") else {
            preconditionFailure("缺少已确认书本资源：\(name).\(type)")
        }
        return url
    }

    init(preferences: BookPreferences = .live()) {
        self.preferences = preferences
        audio = BookAudio(enabled: preferences.soundEnabled)
        haptics = BookHaptics(enabled: preferences.hapticsEnabled)
        if let font = Bundle.main.url(forResource: "NotoSerifSC-Regular", withExtension: "otf", subdirectory: "Fonts/V0.1") {
            CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        }
        PaperInk.prepare()
        #if DEBUG
        if performanceEnabled { _ = PaperInk.performanceOpaqueBoundary }
        #endif
        opening = AVPlayer(url: Self.resource("开书", type: "mp4", directory: "视频"))
        closing = AVPlayer(url: Self.resource("合书", type: "mp4", directory: "视频"))
        for player in [opening, closing] {
            player.isMuted = true // 视频无声，T06使用独立原速音轨。
            player.actionAtItemEnd = .pause
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), !performanceEnabled,
           let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? Data(contentsOf: folder.appendingPathComponent("T05-playback.json")),
           let previous = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            events = previous
        }
        #endif
        record("launch")
    }

    func setSoundEnabled(_ enabled: Bool) {
        preferences.setSound(enabled)
        audio.setEnabled(enabled)
    }

    func setHapticsEnabled(_ enabled: Bool) {
        preferences.setHaptics(enabled)
        haptics.setEnabled(enabled)
    }

    func swipe(_ translation: CGSize, prepareOpening: () -> Bool = { true }) {
        guard abs(translation.width) >= Self.threshold,
              abs(translation.width) > abs(translation.height) * 1.2 else { return }
        if translation.width < 0, phase == .closed {
            guard prepareOpening() else { return }
            play(open: true)
        }
        else if translation.width > 0, phase == .reading {
            invalidate()
            phase = .erasing
            eraseID = generation
            eraseTime = ProcessInfo.processInfo.systemUptime
            eraseStart = eraseTime
            eraseInkLevel = revealStart.map { min(1, (eraseTime - $0) / Self.revealDuration) } ?? 1
            record("eraseStarted")
        }
        else { record("ignoredSwipe") }
    }

    func inkErased(_ token: UUID) {
        guard phase == .erasing, generation == token else { return }
        record("eraseCompleted", elapsed: ProcessInfo.processInfo.systemUptime - eraseTime)
        play(open: false)
    }

    func inkAppeared(_ token: UUID) {
        guard phase == .reading, !inkReady, generation == token, let revealStart else { return }
        inkReady = true
        record("inkCompleted", elapsed: ProcessInfo.processInfo.systemUptime - revealStart)
    }

    private func play(open: Bool) {
        invalidate()
        let token = generation
        #if DEBUG
        lastCompletion = (token, open)
        #endif
        let player = open ? opening : closing
        guard let item = player.currentItem, item.status != .failed else {
            failure = "画面暂时无法播放，请重试"; return
        }
        failure = nil
        revealStart = nil // 合书前清空渐显状态和全部纸面叠层。
        phase = open ? .opening : .closing
        triggerTime = ProcessInfo.processInfo.systemUptime
        record("trigger")
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.complete(open: open, token: token)
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.recover(open: open)
            }
        }
        // 此计时只恢复加载/播放失败，不用它判断正常完成。
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.recover(open: open)
        }
        activeFrameReady = false
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.generation == token, finished else { return }
                self.activeFrameReady = true
                self.audio.begin(open: open)
                self.haptics.begin(open: open)
                self.audioPlayer = player
                self.audioTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] time in
                    let seconds = time.seconds
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        if self.audioPlayer?.timeControlStatus == .playing {
                            #if DEBUG
                            if self.performanceEnabled, seconds > 0 {
                                self.beginActivePerformance(open ? "BookOpeningMoving" : "BookClosingMoving")
                            }
                            #endif
                            self.audio.sync(videoTime: seconds)
                            self.haptics.sync(videoTime: seconds)
                        } else { self.audio.videoPaused() }
                    }
                }
                self.audioStatus = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                    let paused = player.timeControlStatus != .playing
                    if paused { Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.audio.videoPaused()
                    } }
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--lifecycle-testing") {
                    player.playImmediately(atRate: 0.5) // 仅测试放大动画中切后台的可观察窗口。
                } else { player.play() }
                #else
                player.play()
                #endif
            }
        }
    }

    #if DEBUG
    /// 仅自动化探针：发送重复完成通知并重复墨迹完成回调。
    func repeatCompletionForTesting() {
        for _ in 0..<2 {
            if let lastCompletion { complete(open: lastCompletion.open, token: lastCompletion.token) }
            if let revealID { inkAppeared(revealID) }
            for player in [opening, closing] {
                if let item = player.currentItem {
                    NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
                }
            }
        }
    }
    #endif

    private func complete(open: Bool, token: UUID) {
        guard generation == token, phase == (open ? .opening : .closing) else { return }
        finish(open: open)
    }

    /// inactive时就取消播放和旧回调，避免等待background期间继续启动音轨。
    func sceneChanged(_ scene: ScenePhase) {
        guard scene != .active else { return }
        suspend()
    }

    private func finish(open: Bool) {
        let elapsed = ProcessInfo.processInfo.systemUptime - triggerTime
        audio.stopEffect()
        if !open { audio.release(reason: "closed") }
        invalidate()
        phase = open ? .reading : .closed
        revealStart = open ? ProcessInfo.processInfo.systemUptime : nil
        revealID = open ? generation : nil
        inkReady = !open
        record("settled", elapsed: elapsed)
        (open ? opening : closing).pause()
    }

    private func recover(open: Bool) {
        audio.release(reason: "videoFailure")
        invalidate()
        phase = open ? .closed : .reading
        revealStart = nil
        inkReady = true
        reset(open ? opening : closing)
        failure = "画面暂时无法播放，请重试"
        record("playbackFailure")
    }

    /// 切出时落到目标静态端点；返回不重播，不留下旧渐显任务。
    func suspend() {
        audio.release(reason: "background")
        let wasMoving = phase == .opening || phase == .closing || phase == .erasing
        let target: Phase = phase == .opening ? .reading : (phase == .closing || phase == .erasing) ? .closed : phase
        invalidate()
        phase = target
        revealStart = nil
        revealID = nil
        inkReady = true
        reset(opening); reset(closing)
        if wasMoving { record("suspendedTransition") }
    }

    private func reset(_ player: AVPlayer) {
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func invalidate() {
        #if DEBUG
        endPerformanceInterval()
        endActivePerformance()
        #endif
        haptics.cancel()
        if let audioTimeObserver, let audioPlayer { audioPlayer.removeTimeObserver(audioTimeObserver) }
        audioTimeObserver = nil; audioPlayer = nil; audioStatus = nil
        generation = UUID()
        eraseID = nil
        eraseStart = nil
        activeFrameReady = false
        watchdog?.cancel(); watchdog = nil
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        completionObserver = nil; failureObserver = nil
    }

    private func record(_ event: String, elapsed: TimeInterval? = nil) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        if performanceEnabled {
            switch event {
            case "trigger": beginPerformanceInterval(phase == .opening ? "BookOpening" : "BookClosing")
            case "settled": if phase == .reading { beginPerformanceInterval("BookInk") }
            case "eraseStarted": beginPerformanceInterval("BookErasing")
            case "inkCompleted", "eraseCompleted": endPerformanceInterval(); endActivePerformance()
            default: break
            }
        }
        var entry = ["event": event, "phase": phase.rawValue,
                     "uptime": String(ProcessInfo.processInfo.systemUptime)]
        if let elapsed { entry["elapsed"] = String(elapsed) }
        if event == "launch" {
            entry["lowPowerMode"] = String(ProcessInfo.processInfo.isLowPowerModeEnabled)
            entry["thermalState"] = String(ProcessInfo.processInfo.thermalState.rawValue)
            entry["screenMaximumFPS"] = String(UIScreen.main.maximumFramesPerSecond)
            entry["serifFontNames"] = UIFont.familyNames.filter { $0.localizedCaseInsensitiveContains("song") || $0.localizedCaseInsensitiveContains("ming") || $0.localizedCaseInsensitiveContains("sung") }.flatMap { UIFont.fontNames(forFamilyName: $0) }.joined(separator: ",")
            entry["songtiAvailable"] = String(UIFont(name: "NotoSerifSC-Regular", size: 28) != nil)
            entry["georgiaAvailable"] = String(UIFont(name: "Georgia", size: 18) != nil)
        }
        events.append(entry)
        if let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]),
           let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: folder.appendingPathComponent("T05-playback.json"), options: .atomic)
        }
        #endif
    }
    /// Release中没有采样；调试诊断把完整阶段与图像变化区间分别报告。
    func performanceProgress(_ progress: Double) {
        #if DEBUG
        guard performanceEnabled else { return }
        let boundary = PaperInk.performanceOpaqueBoundary
        if phase == .reading {
            if progress > 0, progress < boundary { beginActivePerformance("BookInkChanging") }
            else if progress >= boundary { endActivePerformance() }
        } else if phase == .erasing {
            if progress > 0, progress < boundary { beginActivePerformance("BookErasingChanging") }
            else if progress <= 0 { endActivePerformance() }
        }
        #endif
    }

    #if DEBUG
    // 仅显式性能测试发出动画signpost；正常运行与Release不参与采样。
    private func beginActivePerformance(_ name: StaticString) {
        guard activePerformanceName == nil else { return }
        activePerformanceName = name
        activePerformanceID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.animationBegin, log: Self.performanceLog, name: name, signpostID: activePerformanceID)
    }

    private func endActivePerformance() {
        guard let name = activePerformanceName else { return }
        os_signpost(.end, log: Self.performanceLog, name: name, signpostID: activePerformanceID)
        activePerformanceName = nil
    }

    private func beginPerformanceInterval(_ name: StaticString) {
        endPerformanceInterval()
        performanceInterval = name
        os_signpost(.animationBegin, log: Self.performanceLog, name: name)
    }

    private func endPerformanceInterval() {
        guard let name = performanceInterval else { return }
        os_signpost(.end, log: Self.performanceLog, name: name)
        performanceInterval = nil
    }
    #endif

}

/// 保留两个预加载图层；就绪前透明，下面的静态端点持续可见，避免黑帧。
struct BookPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var readiness: NSKeyValueObservation?
        func install(_ player: AVPlayer) {
            backgroundColor = .clear
            playerLayer.videoGravity = .resizeAspect
            playerLayer.opacity = 0
            playerLayer.player = player
            readiness = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                let ready = layer.isReadyForDisplay
                Task { @MainActor [weak self] in
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self?.playerLayer.opacity = ready ? 1 : 0
                    CATransaction.commit()
                }
            }
        }
    }
    func makeUIView(context: Context) -> Surface {
        let view = Surface(); view.install(player); return view
    }
    func updateUIView(_ uiView: Surface, context: Context) {}
    static func dismantleUIView(_ uiView: Surface, coordinator: ()) { uiView.playerLayer.player = nil }

}

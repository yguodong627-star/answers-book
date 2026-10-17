import SwiftUI
import UIKit

struct BookView: View {
    // 复用原图对象，避免每次状态刷新重新读PNG并触发渲染线程解码。
    private static let closedFrame = UIImage(contentsOfFile: BookPlayback.resource(
        "合书静态", type: "png", directory: "关键帧").path)!
    private static let readingFrame = UIImage(contentsOfFile: BookPlayback.resource(
        "阅读静态", type: "png", directory: "关键帧").path)!

    #if DEBUG
    private static var offlineGateDefaults: UserDefaults? {
        guard ProcessInfo.processInfo.arguments.contains("--offline-confirmation-gate"),
              let token = ProcessInfo.processInfo.environment["T10_STORE_TOKEN"] else { return nil }
        return UserDefaults(suiteName: "AnswersBook.tests.\(token)")
    }
    @State private var offlineGateConfirmed = Self.offlineGateDefaults?.bool(forKey: "T20OfflineConfirmed") ?? false
    #endif
    @State private var previewID = "answer_045"
    private var catalog: AnswerCatalog? { try? AnswerCatalog.bundled.get() }
    @State private var draw = DrawSession.live()
    private var contentProof: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--content-proof")
        #else
        false
        #endif
    }
    private var answer: BookAnswer? { contentProof ? catalog?.answer(id: previewID) : draw.current?.answer }
    private var page: Int { contentProof ? (answer.flatMap { catalog?.page(of: $0) } ?? 0) : (draw.current?.page ?? 0) }
    private func swipe(_ translation: CGSize) {
        if contentProof {
            guard answer != nil else { return }
            playback.swipe(translation)
        } else {
            playback.swipe(translation, prepareOpening: { draw.draw() })
        }
    }
    @State private var playback = BookPlayback()
    @State private var dragConsumed = false
    @State private var showingSettings = false
    @State private var showingLibrary = false
    @State private var sharing: ShareContent?
    @GestureState private var isDragging = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // 所有纸面叠层与视频共用576×1248画布，再整体等比缩放。
            let scale = max(size.width / 576, size.height / 1248)
            ZStack {
                Color(red: 0.14, green: 0.09, blue: 0.05)
                scene
                    .frame(width: 576, height: 1248)
                    .scaleEffect(scale)
                    .frame(width: size.width, height: size.height)
                controls(in: size, safeTop: geometry.safeAreaInsets.top)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12)
                .updating($isDragging) { _, dragging, _ in dragging = true }
                .onChanged { value in
                    guard !dragConsumed,
                          abs(value.translation.width) >= BookPlayback.threshold,
                          abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                    dragConsumed = true
                    swipe(value.translation)
                }
                .onEnded { _ in dragConsumed = false })
            .accessibilityAction(named: "开书") { swipe(CGSize(width: -100, height: 0)) }
            .accessibilityAction(named: "合书") { swipe(CGSize(width: 100, height: 0)) }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingSettings) { SettingsView(playback: playback) }
        .sheet(isPresented: $showingLibrary) { LibraryView(session: draw) }
        .sheet(item: $sharing) { SharePreview(content: $0) }
        .onChange(of: isDragging) { _, dragging in
            if !dragging { dragConsumed = false }
        }
        .onChange(of: scenePhase) { _, phase in
            dragConsumed = false
            playback.sceneChanged(phase)
        }
        #if DEBUG
        .overlay {
            if Self.offlineGateDefaults != nil, !offlineGateConfirmed {
                VStack(spacing: 24) {
                    Text("T20 离线回归准备").font(.title2)
                    Text("测试程序已启动。请先开启飞行模式，并在系统设置关闭 Wi-Fi，再返回这里开始。")
                        .multilineTextAlignment(.center)
                    Text("本轮使用独立测试数据；请保持数据线连接。")
                        .font(.footnote)
                    Button("已断网，开始离线回归") {
                        Self.offlineGateDefaults?.set(true, forKey: "T20OfflineConfirmed")
                        offlineGateConfirmed = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("offline-gate-confirm")
                }
                .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.96, green: 0.93, blue: 0.87))
                .foregroundStyle(.brown)
            }
        }
        #endif
    }

    private var scene: some View {
        ZStack {
            Image(uiImage: playback.phase == .closed || playback.phase == .opening
                  ? Self.closedFrame : Self.readingFrame)
                .resizable()
                .accessibilityHidden(true)
            BookPlayerSurface(player: playback.opening)
                .opacity(playback.phase == .opening && playback.activeFrameReady ? 1 : 0)
                .accessibilityHidden(true)
            BookPlayerSurface(player: playback.closing)
                .opacity(playback.phase == .closing && playback.activeFrameReady ? 1 : 0)
                .accessibilityHidden(true)
            if let answer, playback.phase == .reading || playback.phase == .erasing {
                ReadingPaper(answer: answer, page: page, revealStart: playback.revealStart, revealID: playback.revealID,
                             eraseID: playback.eraseID, eraseStart: playback.eraseStart,
                             eraseInkLevel: playback.eraseInkLevel, inkReady: playback.inkReady,
                             onRevealed: playback.inkAppeared,
                             onErased: playback.inkErased,
                             onProgress: playback.performanceProgress)
            }
        }
    }

    private func controls(in size: CGSize, safeTop: CGFloat) -> some View {
        VStack {
            HStack {
                Button { showingLibrary = true } label: {
                    sceneControl("藏书", icon: "books.vertical")
                }.buttonStyle(.plain).accessibilityIdentifier("library-open")
                Spacer()
                Button { showingSettings = true } label: {
                    sceneControl("", icon: "gearshape")
                }.buttonStyle(.plain).accessibilityLabel("设置").accessibilityIdentifier("settings-open")
            }
            .padding(.horizontal, 23)
            .padding(.top, max(safeTop, 54) + 12)
            Spacer()
            if playback.phase == .reading {
                HStack(spacing: 18) {
                    Button {
                        if let current = draw.currentRecord {
                            draw.setFavorite(id: current.id, value: !current.isFavorite)
                        }
                    } label: {
                        sceneControl(draw.currentRecord?.isFavorite == true ? "已收藏" : "收藏",
                                     icon: draw.currentRecord?.isFavorite == true ? "star.fill" : "star")
                    }
                    .buttonStyle(.plain).disabled(contentProof || draw.currentRecord == nil)
                    .accessibilityIdentifier("favorite-current")
                    Button {
                        if let record = draw.currentRecord { sharing = ShareContent(record: record) }
                        else if let current = draw.current { sharing = ShareContent(id: current.recordID, answer: current.answer) }
                    } label: { sceneControl("分享", icon: "square.and.arrow.up") }
                    .buttonStyle(.plain).disabled(contentProof)
                    .accessibilityIdentifier("share-current")
                }
                .padding(.bottom, 22)
                Label("向右轻滑，合上书页", systemImage: "arrow.right")
                    .font(.system(size: 14)).tracking(1)
                    .accessibilityIdentifier("close-hint")
            } else if playback.phase == .closed {
                Image(systemName: "arrow.left").font(.system(size: 25, weight: .light))
                Text("默念心中的问题，向左轻滑翻开")
                    .font(.system(size: 15)).tracking(1).padding(.top, 8)
                    .accessibilityIdentifier("open-hint")
            }
            if let failure = draw.failure, !contentProof {
                Text(failure).font(.footnote).padding(.top, 8)
                    .accessibilityIdentifier("draw-error")
            }
            if let failure = playback.failure {
                Text(failure).font(.footnote).padding(.top, 8)
            }
            if let failure = playback.audio.failure {
                Text(failure).font(.footnote).padding(.top, 8)
            }
            Group {
                if contentProof, let catalog {
                    Menu("答案校对 · 第\(page)页") {
                        Button("示例第45页") { previewID = "answer_045" }
                            .accessibilityIdentifier("preview-default")
                        Button("最长中文") { previewID = catalog.longestChinese.id }
                            .accessibilityIdentifier("preview-longest-zh")
                        Button("最长英文") { previewID = catalog.longestEnglish.id }
                            .accessibilityIdentifier("preview-longest-en")
                    }
                    .accessibilityIdentifier("answer-proof-menu")
                    .disabled(playback.phase != .closed && playback.phase != .reading)
                } else if catalog == nil {
                    Text("答案库加载失败，请检查安装资源")
                        .accessibilityIdentifier("catalog-error")
                }
            }
                .font(.system(size: 10)).tracking(1)
                .foregroundStyle(.white.opacity(0.6)).padding(.top, 14)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--draw-callback-probe") {
                Button("重复回调验证") { playback.repeatCompletionForTesting() }
                    .font(.system(size: 10)).accessibilityIdentifier("draw-callback-probe")
            }
            #endif
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                Text("\(catalog?.answers.count ?? 0)|\(answer?.id ?? previewID)|\(page)")
                    .font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier("catalog-state")
                Text("\(draw.recordCount)|\(draw.current?.recordID.uuidString ?? "none")|\(draw.current?.answer.id ?? "none")")
                    .font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier("draw-state")
                Text("\(playback.phase.rawValue)|\(playback.inkReady ? "ready" : "revealing")")
                    .font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier("book-state")
                Text("\(playback.haptics.enabled ? "on" : "off")|\(playback.haptics.requestCount)")
                    .font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier("haptics-state")
                Text("\(playback.audio.enabled ? "on" : "off")|\(playback.audio.sessionActive ? "active" : "inactive")")
                    .font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier("audio-state")
            }
        }
        .foregroundStyle(Color(red: 0.96, green: 0.91, blue: 0.83))
        .shadow(color: .black.opacity(0.65), radius: 5, y: 1)
        .padding(.bottom, 46)
    }

    private func prototypeControl(_ title: String, icon: String) -> some View {
        sceneControl(title, icon: icon).accessibilityLabel("\(title)，原型占位")
    }

    private func sceneControl(_ title: String, icon: String) -> some View {
        // 保留已确认入口的版式，T05不提前实现收藏/分享/设置。
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 17, weight: .light))
            if !title.isEmpty { Text(title).font(.system(size: 15)) }
        }
        .padding(.horizontal, title.isEmpty ? 13 : 17).frame(height: 44)
        .background(Color(red: 0.13, green: 0.09, blue: 0.05).opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 0.7))

    }
}

private struct ReadingPaper: View {
    let answer: BookAnswer
    let page: Int
    let revealStart: TimeInterval?
    let revealID: UUID?
    let eraseID: UUID?
    let eraseStart: TimeInterval?
    let eraseInkLevel: Double
    let inkReady: Bool
    let onRevealed: (UUID) -> Void
    let onErased: (UUID) -> Void
    let onProgress: (Double) -> Void
    private let ink = Color(red: 0.24, green: 0.17, blue: 0.12)
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: inkReady && eraseID == nil)) { _ in
            let progress = currentProgress()
            ZStack {
                PaperOrnament().stroke(Color(red: 0.50, green: 0.38, blue: 0.24).opacity(0.56), lineWidth: 0.8)
                    .frame(width: 107, height: 22).position(x: 285, y: 320)
                VStack(spacing: 10.7) {
                    Text(answer.zh)
                        .accessibilityIdentifier("answer-zh")
                        .font(.custom("NotoSerifSC-Regular", size: 37.5))
                        .tracking(2.68).foregroundStyle(ink)
                    Text(answer.en)
                        .accessibilityIdentifier("answer-en")
                        .font(.custom("Georgia", size: 24.1))
                        .foregroundStyle(Color(red: 0.40, green: 0.32, blue: 0.23))
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 420)
                .position(x: 285, y: 625)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sample-answer")
                Path { path in
                    path.move(to: CGPoint(x: 72, y: 925)); path.addLine(to: CGPoint(x: 72, y: 944)); path.addLine(to: CGPoint(x: 96, y: 944))
                    path.move(to: CGPoint(x: 472, y: 944)); path.addLine(to: CGPoint(x: 496, y: 944)); path.addLine(to: CGPoint(x: 496, y: 925))
                }
                .stroke(Color(red: 0.50, green: 0.38, blue: 0.24).opacity(0.56), lineWidth: 0.55)
                // Georgia旧式数字高低错落；页码使用齐线数字，与正文衬线风格一致。
                Text(String(page)).font(.custom("NotoSerifSC-Regular", size: 20.1))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.46, green: 0.36, blue: 0.24))
                    .position(x: 480, y: 972).accessibilityLabel("第\(page)页")
            }
            .frame(width: 576, height: 1248)
            // 全部纸面墨迹共用一次采样、同一时钟；平铺避免把噪声拉伸成整页大块。
            .modifier(PaperInk(progress: progress, tiled: true))
            .blendMode(.multiply)
            #if DEBUG
            .onChange(of: progress) { _, value in onProgress(value) }
            #endif
            .onChange(of: progress >= 1, initial: true) { _, complete in
                if complete, eraseID == nil, let revealID { onRevealed(revealID) }
            }
            .onChange(of: progress <= 0, initial: true) { _, complete in
                if complete, let eraseID { onErased(eraseID) }
            }
        }
    }

    private func currentProgress() -> Double {
        let now = ProcessInfo.processInfo.systemUptime
        if let eraseStart {
            return eraseInkLevel * max(0, 1 - (now - eraseStart) / BookPlayback.eraseDuration)
        }
        if let revealStart {
            return min(1, max(0, (now - revealStart) / BookPlayback.revealDuration))
        }
        return 1
    }
}

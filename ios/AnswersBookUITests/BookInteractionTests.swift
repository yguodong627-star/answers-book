import XCTest

@MainActor
final class BookInteractionTests: XCTestCase {
    private let app = XCUIApplication()
    private var state: XCUIElement { app.staticTexts["book-state"] }

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app.launchArguments = ["--ui-testing", "--content-proof"]
            app.launch()
        }
    }

    private func expect(_ label: String, timeout: TimeInterval = 12) {
        if state.waitForExistence(timeout: timeout), state.label == label { return }
        let predicate = NSPredicate(format: "label == %@", label)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: state)], timeout: timeout)
        XCTAssertTrue(result == .completed || state.label == label, "期望 \(label)，实际 \(state.label)")
    }

    private func expectTransition(_ phases: [String]) {
        // 等待手势确已送达，再按Home；否则系统转场可能取消尚未送达的拖动。
        let predicate = NSPredicate { [self] _, _ in
            phases.contains { state.label.hasPrefix($0 + "|") }
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: state)], timeout: 6), .completed)
    }

    private func swipe(left: Bool, distance: CGFloat = 0.55) {
        let startX: CGFloat = left ? 0.78 : 0.22
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: startX + (left ? -distance : distance), dy: 0.55))
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testOpenCloseAndGestureGuards() {
        expect("closed|ready"); capture("01-合书")
        swipe(left: true, distance: 0.08) // 约34pt，低于64pt。
        expect("closed|ready", timeout: 2)
        swipe(left: true)
        swipe(left: true) // 动画中忽略重复开书。
        expect("reading|ready")
        XCTAssertTrue(app.staticTexts["sample-answer"].exists)
        capture("02-阅读")
        swipe(left: true) // 阅读页不能再次开书。
        expect("reading|ready", timeout: 2)
        swipe(left: false)
        swipe(left: true) // 合书中不能重新打开。
        expect("closed|ready")
        XCTAssertTrue(app.staticTexts["open-hint"].exists)
        XCTAssertFalse(app.staticTexts["sample-answer"].exists)
        capture("03-重新合书")
        swipe(left: true); expect("reading|ready")
        capture("04-第二次阅读")
    }

    func testReadingCloseAndBackground() {
        expect("closed|ready")
        swipe(left: true)
        expectTransition(["reading"]) // UI自动化可能错过1.5秒短暂显现阶段，不把它当作必达状态。
        swipe(left: false)
        expect("closed|ready")
        XCTAssertFalse(app.staticTexts["sample-answer"].exists)
        swipe(left: true)
        expectTransition(["opening", "reading"])
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        expect("reading|ready")
        capture("05-后台恢复阅读")
        swipe(left: false)
        expectTransition(["erasing", "closing"])
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        expect("closed|ready")
        XCTAssertFalse(app.staticTexts["sample-answer"].exists)
        app.terminate(); app.launch()
        expect("closed|ready")
    }
    private func expectAudio(_ label: String) {
        let state = app.staticTexts["audio-state"]
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: state)
        let result = XCTWaiter.wait(for: [wait], timeout: 10)
        XCTAssertTrue(result == .completed || state.label == label, "音频状态期望\(label)，实际\(state.label)")
    }

    func testPrototypeAudioSessionLifecycle() {
        expect("closed|ready"); expectAudio("on|inactive")
        // 声音操作通过正式设置页。
        toggleSound(); expectAudio("off|inactive")
        swipe(left: true); expect("reading|ready"); expectAudio("off|inactive")
        swipe(left: false); expect("closed|ready"); expectAudio("off|inactive")
        toggleSound(); expectAudio("on|inactive") // 开开关不激活。
        swipe(left: true); expect("reading|ready"); expectAudio("on|active")
        capture("06-T06声音开启阅读")
        toggleSound(); expectAudio("off|inactive") // 阅读中关闭，立即释放。
        toggleSound(); expectAudio("on|inactive") // 不重播或重新打断。
        swipe(left: false); expect("closed|ready"); expectAudio("on|inactive")
        swipe(left: true); expect("reading|ready"); expectAudio("on|active")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        expect("reading|ready"); expectAudio("on|inactive")
        swipe(left: false); expect("closed|ready"); expectAudio("on|inactive")
    }

    private func expectHaptics(_ label: String) {
        let state = app.staticTexts["haptics-state"]
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: state)
        let result = XCTWaiter.wait(for: [wait], timeout: 10)
        XCTAssertTrue(result == .completed || state.label == label, "触觉请求期望\(label)，实际\(state.label)")
    }

    func testPrototypeHapticsGating() {
        expect("closed|ready"); expectHaptics("on|0")
        // 触觉操作通过正式设置页。
        toggleHaptics(); expectHaptics("off|0")
        swipe(left: true); expect("reading|ready"); expectHaptics("off|0")
        swipe(left: false); expect("closed|ready"); expectHaptics("off|0")
        toggleSound() // 关声音仍可有触觉。
        expectAudio("off|inactive")
        toggleHaptics(); expectHaptics("on|0")
        swipe(left: true, distance: 0.08); expect("closed|ready"); expectHaptics("on|0")
        swipe(left: true); expect("reading|ready"); expectHaptics("on|1")
        swipe(left: true); expect("reading|ready"); expectHaptics("on|1")
        capture("07-T07触觉开关阅读")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate(); expect("reading|ready"); expectHaptics("on|1")
        swipe(left: false); expect("closed|ready"); expectHaptics("on|2")
        toggleHaptics(); expectHaptics("off|2")
        swipe(left: true); expect("reading|ready"); expectHaptics("off|2")
        toggleHaptics(); expectHaptics("on|2") // 不补发阅读中的反馈。
        swipe(left: false); expect("closed|ready"); expectHaptics("on|3")
    }

    func testAnswerCatalogProofreading() {
        expect("closed|ready")
        XCTAssertEqual(app.staticTexts["catalog-state"].label, "120|answer_045|45")
        app.buttons["answer-proof-menu"].tap()
        app.buttons["preview-longest-zh"].tap()
        XCTAssertEqual(app.staticTexts["catalog-state"].label, "120|answer_020|20")
        swipe(left: true); expect("reading|ready")
        XCTAssertTrue(app.staticTexts["sample-answer"].label.contains("你可以有不同的选择"))
        capture("08-T08最长中文")
        app.buttons["answer-proof-menu"].tap()
        app.buttons["preview-longest-en"].tap()
        XCTAssertEqual(app.staticTexts["catalog-state"].label, "120|answer_109|109")
        XCTAssertTrue(app.staticTexts["sample-answer"].label.contains("Your disappointment deserves to be heard"))
        capture("09-T08最长英文")
        swipe(left: false); expect("closed|ready")
        swipe(left: true); expect("reading|ready")
        XCTAssertEqual(app.staticTexts["catalog-state"].label, "120|answer_109|109") // 不随机。
        app.buttons["answer-proof-menu"].tap()
        app.buttons["preview-default"].tap()
        XCTAssertEqual(app.staticTexts["catalog-state"].label, "120|answer_045|45")
        XCTAssertTrue(app.staticTexts["sample-answer"].label.contains("It is okay to go slowly"))
    }

    func testTenDrawsAllowRepeatWithoutExtraRecords() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045"]
        app.launch()
        let draw = app.staticTexts["draw-state"]
        var ids = Set<String>()
        expect("closed|ready")
        XCTAssertTrue(draw.label.hasPrefix("0|none|none"))
        for count in 1...10 {
            swipe(left: true, distance: 0.08)
            XCTAssertTrue(draw.label.hasPrefix("\(count - 1)|"))
            swipe(left: true)
            swipe(left: true) // 开书过程中重复手势不新增。
            expect("reading|ready")
            let saved = draw.label
            let parts = saved.split(separator: "|")
            XCTAssertEqual(String(parts[0]), "\(count)")
            XCTAssertEqual(String(parts[2]), "answer_045")
            XCTAssertTrue(ids.insert(String(parts[1])).inserted)
            XCTAssertEqual(app.staticTexts["catalog-state"].label, "120|answer_045|45")
            swipe(left: true) // 阅读期间不重新抽取。
            toggleHaptics() // 触发View更新也不抽取。
            XCTAssertEqual(draw.label, saved)
            if count == 10 { capture("T10-十次同答案独立记录") }
            swipe(left: false)
            swipe(left: false) // 消失/合书阶段重复回调路径不新增。
            expect("closed|ready")
            XCTAssertEqual(draw.label, saved)
        }
        XCTAssertEqual(ids.count, 10)
        app.terminate(); app.launch()
        expect("closed|ready")
        XCTAssertTrue(draw.label.hasPrefix("10|none|none")) // 重启读取同库数量。
    }

    func testDrawSaveFailureStaysClosed() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--draw-save-failure"]
        app.launch()
        expect("closed|ready")
        swipe(left: true)
        expect("closed|ready")
        XCTAssertTrue(app.staticTexts["draw-error"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["draw-state"].label, "0|none|none")
        XCTAssertFalse(app.staticTexts["sample-answer"].exists)
        capture("T10-保存失败明确反馈")
    }

    func testProductionRandomAndRepeatedCompletion() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--draw-callback-probe"]
        app.launch()
        expect("closed|ready")
        XCTAssertFalse(app.buttons["answer-proof-menu"].exists)
        swipe(left: true); expect("reading|ready")
        let saved = app.staticTexts["draw-state"].label
        let parts = saved.split(separator: "|")
        XCTAssertEqual(String(parts[0]), "1")
        XCTAssertTrue(String(parts[2]).hasPrefix("answer_"))
        XCTAssertTrue(app.staticTexts["sample-answer"].exists)
        app.buttons["draw-callback-probe"].tap()
        expect("reading|ready")
        XCTAssertEqual(app.staticTexts["draw-state"].label, saved)
        capture("T10-正常随机阅读")
        swipe(left: false); expect("closed|ready")
        app.buttons["draw-callback-probe"].tap()
        expect("closed|ready")
        XCTAssertEqual(app.staticTexts["draw-state"].label, saved)
    }

    func testT11ActualDrawSurvivesTransitionsAndRestart() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045", "--lifecycle-testing", "--draw-callback-probe"]
        app.launch()
        expect("closed|ready"); expectAudio("on|inactive")
        swipe(left: true); expectTransition(["opening"])
        let saved = app.staticTexts["draw-state"].label
        XCTAssertTrue(saved.hasPrefix("1|"))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate(); expect("reading|ready"); expectAudio("on|inactive")
        XCTAssertEqual(app.staticTexts["draw-state"].label, saved)
        app.buttons["draw-callback-probe"].tap() // 故意送达上一动作的旧完成token。
        expect("reading|ready"); expectAudio("on|inactive")
        XCTAssertEqual(app.staticTexts["draw-state"].label, saved)
        capture("T11-开书后台返回同一记录")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate(); expect("reading|ready"); expectAudio("on|inactive")
        XCTAssertEqual(app.staticTexts["draw-state"].label, saved)
        swipe(left: false); expectTransition(["closing"]); expectAudio("on|active")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate(); expect("closed|ready"); expectAudio("on|inactive")
        app.buttons["draw-callback-probe"].tap()
        expect("closed|ready")
        XCTAssertEqual(app.staticTexts["draw-state"].label, saved)
        capture("T11-合书后台返回合书")
        app.terminate(); app.launch()
        expect("closed|ready"); expectAudio("on|inactive")
        XCTAssertEqual(app.staticTexts["draw-state"].label, "1|none|none")
    }

    func testT11NormalReadingReturnsWithoutAudioReplay() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045"]
        app.launch()
        swipe(left: true); expect("reading|ready"); expectAudio("on|active")
        let saved = app.staticTexts["draw-state"].label
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate(); expect("reading|ready"); expectAudio("on|inactive")
        XCTAssertEqual(app.staticTexts["draw-state"].label, saved)
        swipe(left: false); expect("closed|ready"); expectAudio("on|inactive")
        XCTAssertEqual(app.staticTexts["draw-state"].label, saved)
    }

    private func openSettings() {
        app.buttons["settings-open"].tap()
        XCTAssertTrue(app.switches["settings-sound"].waitForExistence(timeout: 4))
    }
    private func toggleSound() {
        openSettings(); app.switches["settings-sound"].tap(); app.buttons["settings-done"].tap()
    }
    private func toggleHaptics() {
        openSettings(); app.switches["settings-haptics"].tap(); app.buttons["settings-done"].tap()
    }

    func testT12IndependentSettingsPersistAcrossRelaunch() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045"]
        app.launch(); expect("closed|ready")
        openSettings()
        XCTAssertEqual(app.switches["settings-sound"].value as? String, "1")
        XCTAssertEqual(app.switches["settings-haptics"].value as? String, "1")
        capture("T12-设置默认开启")
        app.switches["settings-sound"].tap()
        XCTAssertEqual(app.switches["settings-haptics"].value as? String, "1")
        app.buttons["settings-done"].tap()
        app.terminate(); app.launch()
        expectAudio("off|inactive"); expectHaptics("on|0")
        openSettings()
        XCTAssertEqual(app.switches["settings-sound"].value as? String, "0")
        XCTAssertEqual(app.switches["settings-haptics"].value as? String, "1")
        app.switches["settings-haptics"].tap(); app.buttons["settings-done"].tap()
        app.terminate(); app.launch()
        expectAudio("off|inactive"); expectHaptics("off|0")
        swipe(left: true); expect("reading|ready")
        expectAudio("off|inactive"); expectHaptics("off|0")
        toggleSound(); expectAudio("on|inactive") // 设置开启不重播当前动作。
        expectHaptics("off|0")
        swipe(left: false); expect("closed|ready"); expectHaptics("off|0")
        app.terminate(); app.launch()
        expectAudio("on|inactive"); expectHaptics("off|0")
        openSettings()
        XCTAssertEqual(app.switches["settings-sound"].value as? String, "1")
        XCTAssertEqual(app.switches["settings-haptics"].value as? String, "0")
        capture("T12-声音与触觉独立持久化")
    }

    func testT13DuplicateFavoritesSurviveRelaunchAndUnfavorite() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045"]
        app.launch()
        swipe(left: true); expect("reading|ready")
        let first = String(app.staticTexts["draw-state"].label.split(separator: "|")[1])
        app.buttons["favorite-current"].tap()
        XCTAssertTrue(app.buttons["favorite-current"].label.contains("已收藏"))
        swipe(left: false); expect("closed|ready")
        swipe(left: true); expect("reading|ready")
        let second = String(app.staticTexts["draw-state"].label.split(separator: "|")[1])
        XCTAssertNotEqual(first, second)
        app.buttons["favorite-current"].tap()
        app.buttons["library-open"].tap()
        XCTAssertTrue(app.buttons["unfavorite-\(first)"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["unfavorite-\(second)"].exists)
        capture("T13-同一句独立收藏卡片")
        app.buttons["library-done"].tap()
        app.terminate(); app.launch(); expect("closed|ready")
        app.buttons["library-open"].tap()
        XCTAssertTrue(app.buttons["unfavorite-\(first)"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["unfavorite-\(second)"].exists)
        app.buttons["unfavorite-\(first)"].tap()
        XCTAssertFalse(app.buttons["unfavorite-\(first)"].exists)
        XCTAssertTrue(app.buttons["unfavorite-\(second)"].exists)
        capture("T13-取消其中一条收藏")
        app.buttons["library-done"].tap()
        XCTAssertEqual(app.staticTexts["draw-state"].label, "2|none|none")
        app.terminate(); app.launch()
        app.buttons["library-open"].tap()
        XCTAssertFalse(app.buttons["unfavorite-\(first)"].exists)
        XCTAssertTrue(app.buttons["unfavorite-\(second)"].waitForExistence(timeout: 4))
    }

    private func writeNote(id: String, text: String) {
        app.buttons["note-edit-\(id)"].tap()
        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        if app.buttons["note-clear"].isEnabled { app.buttons["note-clear"].tap() }
        if !text.isEmpty { editor.tap(); editor.typeText(text) }
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.buttons["library-done"].waitForExistence(timeout: 4))
    }

    func testT14NotesEditClearCancelAndPersistIndependently() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045"]
        app.launch()
        swipe(left: true); expect("reading|ready")
        let first = String(app.staticTexts["draw-state"].label.split(separator: "|")[1])
        app.buttons["favorite-current"].tap()
        swipe(left: false); expect("closed|ready")
        swipe(left: true); expect("reading|ready")
        let second = String(app.staticTexts["draw-state"].label.split(separator: "|")[1])
        app.buttons["favorite-current"].tap(); app.buttons["library-open"].tap()
        writeNote(id: first, text: "First question?")
        writeNote(id: second, text: "Second question.")
        app.buttons["library-done"].tap(); app.terminate(); app.launch()
        app.buttons["library-open"].tap()
        XCTAssertTrue(app.staticTexts["First question?"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Second question."].exists)
        capture("T14-同答案两条独立问题")
        writeNote(id: first, text: "Updated question!")
        app.buttons["note-edit-\(first)"].tap()
        app.buttons["note-clear"].tap(); app.buttons["note-cancel"].tap()
        XCTAssertTrue(app.staticTexts["Updated question!"].waitForExistence(timeout: 4))
        writeNote(id: first, text: "")
        XCTAssertFalse(app.staticTexts["Updated question!"].exists)
        XCTAssertTrue(app.staticTexts["Second question."].exists)
        capture("T14-清空其中一条问题")
        app.buttons["library-done"].tap(); app.terminate(); app.launch()
        app.buttons["library-open"].tap()
        app.buttons["note-edit-\(first)"].tap()
        XCTAssertEqual(app.textViews["note-editor"].value as? String, "")
        app.buttons["note-cancel"].tap()
        XCTAssertTrue(app.staticTexts["Second question."].exists)
    }

    func testT26LongMultilineNoteRemainsEditableAndPersists() {
        app.terminate()
        let note = (1...12).map {
            "第\($0)段：这是用于排版验证的长备注，保留中文、English、标点与换行，让每次翻阅的想法都能完整保存。"
        }.joined(separator: "\n\n") + "\n长备注末尾检查"
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchEnvironment["T16_NOTE"] = note
        app.launchArguments = ["--ui-testing", "--share-fixture"]
        app.launch(); expect("closed|ready")
        app.buttons["library-open"].tap()
        let noteLabel = app.staticTexts.matching(NSPredicate(format: "label == %@", note)).firstMatch
        XCTAssertTrue(noteLabel.waitForExistence(timeout: 6))
        capture("T26-长备注收藏卡片顶部")
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "note-edit-")).firstMatch
        for _ in 0..<12 {
            if edit.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(edit.isHittable, "长备注卡片底部编辑入口应可滚动到达")
        capture("T26-长备注末尾及操作入口")
        edit.tap()
        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        XCTAssertEqual(editor.value as? String, note)
        capture("T26-长备注编辑页面")
        editor.tap(); editor.swipeUp()
        XCTAssertTrue(app.buttons["note-save"].isHittable, "键盘出现后保存仍可操作")
        capture("T26-长备注键盘及保存入口")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.buttons["library-done"].waitForExistence(timeout: 4))
        app.buttons["library-done"].tap(); app.terminate(); app.launch()
        app.buttons["library-open"].tap()
        XCTAssertTrue(noteLabel.waitForExistence(timeout: 6))
        for _ in 0..<12 {
            if edit.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertEqual(editor.value as? String, note, "重启后换行和末尾内容必须原样保留")
        app.buttons["note-clear"].tap()
        XCTAssertEqual(editor.value as? String, "")
        app.buttons["note-cancel"].tap()
        XCTAssertTrue(noteLabel.waitForExistence(timeout: 4), "清空后取消不应覆盖原长备注")
    }

    func testT16SharePrivacyPreviewAndSystemSheet() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045", "--share-fixture"]
        app.launch()
        expect("closed|ready")
        app.buttons["library-open"].tap()
        let share = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "share-record-")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 6))
        share.tap()
        let card = app.images["share-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        XCTAssertFalse(card.label.contains("My private question."))
        XCTAssertEqual(app.switches["share-include-note"].value as? String, "0")
        capture("T16-默认隐藏问题预览")
        app.switches["share-include-note"].tap()
        XCTAssertTrue(card.label.contains("My private question."))
        capture("T16-包含问题预览")
        app.buttons["share-export"].tap()
        let activity = app.otherElements["ActivityListView"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        capture("T16-系统分享面板")
        // iOS27模拟器的ShareSheet.RemoteContainerView不暴露内部按钮；
        // 此专用iPhone15ProMax用例依据实际录屏的系统关闭按钮位置点击；
        // 远程面板不响应整个根容器的下滑，不能据此判定App无法返回。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.12)).press(forDuration: 0.1)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: activity)], timeout: 10), .completed)
        app.buttons["share-done"].tap()
        share.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        XCTAssertEqual(app.switches["share-include-note"].value as? String, "0")
        XCTAssertFalse(card.label.contains("My private question."))
        app.buttons["share-done"].tap(); app.buttons["library-done"].tap()
        XCTAssertTrue(app.staticTexts["draw-state"].label.hasPrefix("1|"))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.23, dy: 0.55))
        start.press(forDuration: 0.15, thenDragTo: end); expect("reading|ready")
        let before = app.staticTexts["draw-state"].label
        app.buttons["share-current"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        XCTAssertFalse(card.label.contains("My private question."))
        app.buttons["share-done"].tap()
        XCTAssertEqual(app.staticTexts["draw-state"].label, before)
    }

    func testT27LibraryShareEntriesIncludeUnfavoritedHistory() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchEnvironment["T16_NOTE"] = "藏书分享测试备注"
        app.launchArguments = ["--ui-testing", "--repeat-answer-045", "--share-fixture"]
        app.launch(); expect("closed|ready")
        app.buttons["library-open"].tap()
        let favoriteShare = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "share-record-")).firstMatch
        XCTAssertTrue(favoriteShare.waitForExistence(timeout: 6))
        XCTAssertTrue(favoriteShare.isHittable)
        XCTAssertTrue(favoriteShare.label.contains("分享"))
        let id = favoriteShare.identifier.replacingOccurrences(of: "share-record-", with: "")
        capture("T27-收藏卡片明确分享文字")
        favoriteShare.tap()
        let card = app.images["share-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        XCTAssertFalse(card.label.contains("藏书分享测试备注"))
        app.buttons["share-done"].tap()
        app.buttons["library-history"].tap()
        let historyShare = app.buttons["history-share-\(id)"]
        XCTAssertTrue(historyShare.isHittable)
        capture("T27-历史卡片明确分享入口")
        historyShare.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        XCTAssertEqual(app.switches["share-include-note"].value as? String, "0")
        app.switches["share-include-note"].tap()
        XCTAssertTrue(card.label.contains("藏书分享测试备注"))
        app.buttons["share-done"].tap()
        app.buttons["history-menu-\(id)"].tap()
        app.buttons["history-favorite-\(id)"].tap()
        XCTAssertTrue(historyShare.isHittable, "未收藏历史也应可以分享")
        historyShare.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        XCTAssertEqual(app.switches["share-include-note"].value as? String, "0")
        XCTAssertFalse(card.label.contains("藏书分享测试备注"))
        app.buttons["share-done"].tap()
        app.buttons["library-favorites"].tap()
        XCTAssertTrue(app.staticTexts["还没有收藏"].waitForExistence(timeout: 4))
        app.buttons["library-done"].tap()
        XCTAssertEqual(app.staticTexts["draw-state"].label, "1|none|none")
    }

    func testT27LongNoteShareExportsCompleteAndResetsPrivacy() {
        app.terminate()
        let note = (1...12).map {
            "分享验证第\($0)段：保留中文、English、标点与换行，这段长备注应在包含问题时完整导出。"
        }.joined(separator: "\n\n") + "\n分享长备注末尾检查"
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchEnvironment["T16_NOTE"] = note
        app.launchArguments = ["--ui-testing", "--repeat-answer-045", "--share-fixture"]
        app.launch(); expect("closed|ready")
        let before = app.staticTexts["draw-state"].label
        app.buttons["library-open"].tap()
        let share = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "share-record-")).firstMatch
        for _ in 0..<12 {
            if share.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(share.isHittable)
        share.tap()
        let card = app.images["share-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        XCTAssertFalse(card.label.contains(note))
        XCTAssertEqual(app.switches["share-include-note"].value as? String, "0")
        capture("T27-长备注默认不包含")
        app.switches["share-include-note"].tap()
        XCTAssertTrue(card.label.contains(note), "分享必须包含完整备注及末尾")
        XCTAssertFalse(app.staticTexts["share-error"].exists)
        let export = app.buttons["share-export"]
        for _ in 0..<12 {
            if export.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(export.isHittable, "长图底部的分享入口应可滚动到达")
        capture("T27-长备注预览末尾与分享入口")
        export.tap()
        let activity = app.otherElements["ActivityListView"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        capture("T27-长备注系统分享面板")
        // 只调起并关闭面板；此用例不选择联系人或发送。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.12)).press(forDuration: 0.1)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: activity)], timeout: 10), .completed)
        app.buttons["share-done"].tap()
        share.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        XCTAssertEqual(app.switches["share-include-note"].value as? String, "0")
        XCTAssertFalse(card.label.contains(note))
        app.buttons["share-done"].tap(); app.buttons["library-done"].tap()
        XCTAssertEqual(app.staticTexts["draw-state"].label, before)
    }

    func testT15HistoryClearKeepsFavoriteAndDeleteRequiresConfirmation() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045"]
        app.launch()
        var ids: [String] = []
        for index in 0..<3 {
            swipe(left: true); expect("reading|ready")
            let id = String(app.staticTexts["draw-state"].label.split(separator: "|")[1]); ids.append(id)
            if index == 1 {
                app.buttons["favorite-current"].tap(); app.buttons["library-open"].tap()
                writeNote(id: id, text: "Keep this question.")
                app.buttons["library-done"].tap()
            }
            swipe(left: false); expect("closed|ready")
        }
        app.buttons["library-open"].tap(); app.buttons["library-history"].tap()
        for id in ids { XCTAssertTrue(app.buttons["history-menu-\(id)"].exists) }
        XCTAssertTrue(app.staticTexts["Keep this question."].exists)
        capture("T15-三条重复答案历史")
        app.buttons["history-clear"].tap(); app.alerts.buttons["取消"].tap()
        for id in ids { XCTAssertTrue(app.buttons["history-menu-\(id)"].exists) }
        app.buttons["history-clear"].tap(); app.alerts.buttons["清空未收藏历史"].tap()
        XCTAssertFalse(app.buttons["history-menu-\(ids[0])"].exists)
        XCTAssertFalse(app.buttons["history-menu-\(ids[2])"].exists)
        let kept = ids[1]
        XCTAssertTrue(app.buttons["history-menu-\(kept)"].exists)
        XCTAssertTrue(app.staticTexts["Keep this question."].exists)
        capture("T15-清空保留收藏与问题")
        app.buttons["history-menu-\(kept)"].tap(); app.buttons["history-favorite-\(kept)"].tap()
        XCTAssertTrue(app.buttons["history-menu-\(kept)"].exists) // 取消收藏不删除历史/备注。
        XCTAssertTrue(app.staticTexts["Keep this question."].exists)
        app.buttons["history-menu-\(kept)"].tap(); app.buttons["history-favorite-\(kept)"].tap()
        app.buttons["history-menu-\(kept)"].tap(); app.buttons["history-delete-\(kept)"].tap()
        XCTAssertTrue(app.alerts.staticTexts["这条记录已收藏。删除后，收藏和问题备注也会一起删除，无法恢复。"].exists)
        capture("T15-删除收藏记录明确提示")
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["history-menu-\(kept)"].exists)
        XCTAssertTrue(app.staticTexts["Keep this question."].exists)
        app.buttons["history-menu-\(kept)"].tap(); app.buttons["history-delete-\(kept)"].tap()
        app.alerts.buttons["删除记录"].tap()
        XCTAssertTrue(app.staticTexts["还没有翻阅记录"].waitForExistence(timeout: 4))
        app.buttons["library-favorites"].tap()
        XCTAssertFalse(app.buttons["unfavorite-\(kept)"].exists)
        app.buttons["library-done"].tap()
        XCTAssertTrue(app.staticTexts["draw-state"].label.hasPrefix("0|"))
        app.terminate(); app.launch()
        XCTAssertEqual(app.staticTexts["draw-state"].label, "0|none|none")
        app.buttons["library-open"].tap(); app.buttons["library-history"].tap()
        XCTAssertFalse(app.buttons["history-menu-\(kept)"].exists)
        XCTAssertFalse(app.staticTexts["Keep this question."].exists)
    }

    // T20：需用户先开启飞行模式并在设置关闭Wi-Fi；不得把在线测试标为离线通过。
    func testT20OfflineFeatureJourney() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--offline-confirmation-gate"] // 使用真实随机选择，数据及设置独立。
        app.launch()
        let gate = app.buttons["offline-gate-confirm"]
        XCTAssertTrue(gate.waitForExistence(timeout: 10))
        capture("T20-联网启动后等待断网")
        print("T20_GATE_READY: 等待用户开启飞行模式、关闭Wi-Fi并点击开始")
        let confirmed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: gate)
        XCTAssertEqual(XCTWaiter.wait(for: [confirmed], timeout: 900), .completed,
                       "用户未确认断网，不执行离线验收")
        expect("closed|ready")
        print("T20_OFFLINE_JOURNEY_STARTED: 用户已点击断网确认")
        swipe(left: true); expect("reading|ready")
        let firstState = app.staticTexts["draw-state"].label
        let first = String(firstState.split(separator: "|")[1])
        XCTAssertTrue(firstState.hasPrefix("1|"))
        XCTAssertTrue(firstState.split(separator: "|")[2].hasPrefix("answer_"))
        app.buttons["favorite-current"].tap()
        app.buttons["library-open"].tap()
        XCTAssertTrue(app.buttons["unfavorite-\(first)"].waitForExistence(timeout: 4))
        writeNote(id: first, text: "Offline question, kept with this draw.")
        app.buttons["share-record-\(first)"].tap()
        let card = app.images["share-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["share-error"].exists)
        XCTAssertEqual(app.switches["share-include-note"].value as? String, "0")
        XCTAssertFalse(card.label.contains("Offline question"))
        capture("T20-离线生成仅答案分享图")
        app.switches["share-include-note"].tap()
        XCTAssertTrue(card.label.contains("Offline question"))
        capture("T20-离线生成含问题分享图")
        app.buttons["share-done"].tap(); app.buttons["library-done"].tap()
        XCTAssertEqual(app.staticTexts["draw-state"].label, firstState)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate(); expect("reading|ready"); expectAudio("on|inactive")
        XCTAssertEqual(app.staticTexts["draw-state"].label, firstState)
        swipe(left: false); expect("closed|ready")
        swipe(left: true); expect("reading|ready")
        let secondState = app.staticTexts["draw-state"].label
        let second = String(secondState.split(separator: "|")[1])
        XCTAssertTrue(secondState.hasPrefix("2|")); XCTAssertNotEqual(first, second)
        swipe(left: false); expect("closed|ready")
        openSettings()
        app.switches["settings-sound"].tap()
        XCTAssertEqual(app.switches["settings-haptics"].value as? String, "1")
        app.buttons["settings-done"].tap()
        app.terminate(); app.launch(); expect("closed|ready")
        expectAudio("off|inactive"); expectHaptics("on|0")
        XCTAssertEqual(app.staticTexts["draw-state"].label, "2|none|none")
        app.buttons["library-open"].tap()
        XCTAssertTrue(app.buttons["unfavorite-\(first)"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Offline question, kept with this draw."].exists)
        app.buttons["library-history"].tap()
        XCTAssertTrue(app.buttons["history-menu-\(first)"].exists)
        XCTAssertTrue(app.buttons["history-menu-\(second)"].exists)
        app.buttons["history-clear"].tap(); app.alerts.buttons["清空未收藏历史"].tap()
        XCTAssertTrue(app.buttons["history-menu-\(first)"].exists)
        XCTAssertFalse(app.buttons["history-menu-\(second)"].exists)
        XCTAssertTrue(app.staticTexts["Offline question, kept with this draw."].exists)
        capture("T20-离线清空保留收藏和备注")
        app.buttons["library-done"].tap(); app.terminate(); app.launch()
        expect("closed|ready"); expectAudio("off|inactive"); expectHaptics("on|0")
        XCTAssertEqual(app.staticTexts["draw-state"].label, "1|none|none")
        app.buttons["library-open"].tap()
        XCTAssertTrue(app.buttons["unfavorite-\(first)"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Offline question, kept with this draw."].exists)
        capture("T20-离线重启恢复收藏与问题")
        app.buttons["library-done"].tap()
        // 同一个Runner内追加动画中切后台，避免断网后重新安装/启动Runner。
        swipe(left: true); expectTransition(["opening"])
        let transitionState = app.staticTexts["draw-state"].label
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate(); expect("reading|ready"); expectAudio("off|inactive")
        XCTAssertEqual(app.staticTexts["draw-state"].label, transitionState)
        swipe(left: false); expectTransition(["erasing", "closing"])
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate(); expect("closed|ready"); expectAudio("off|inactive")
        XCTAssertEqual(app.staticTexts["draw-state"].label, transitionState)
        capture("T20-离线开合切后台恢复")
        app.terminate(); app.launch(); expect("closed|ready")
        XCTAssertEqual(app.staticTexts["draw-state"].label, "2|none|none")
    }

    // T19：必须选择实体iPhone目标运行；模拟器结果不作为真机性能证据。
    func testT19PhysicalLaunchMeasurement() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045", "--performance-probe"]
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
            app.terminate()
        }
    }

    func testT19PhysicalContinuousPlaybackMemory() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045", "--performance-probe"]
        app.launch()
        expect("closed|ready")
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTMemoryMetric(application: app), XCTCPUMetric(application: app)] + t19AnimationMetrics, options: options) {
            let initialCount = Int(app.staticTexts["draw-state"].label.split(separator: "|")[0]) ?? 0
            for count in 1...20 {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.55))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.23, dy: 0.55))
                start.press(forDuration: 0.15, thenDragTo: end)
                expect("reading|ready")
                XCTAssertTrue(app.staticTexts["sample-answer"].exists)
                XCTAssertTrue(app.staticTexts["draw-state"].label.hasPrefix("\(initialCount + count)|"))
                if count == 1 { capture("T19-首次真机阅读") }
                end.press(forDuration: 0.15, thenDragTo: start)
                expect("closed|ready")
                if count == 20 { capture("T19-连续20轮后合书") }
            }
        }
    }

    private var t19AnimationMetrics: [XCTMetric] {
        ["BookOpening", "BookClosing", "BookInk", "BookErasing"].map {
            XCTOSSignpostMetric(subsystem: "AnswersBook.Performance", category: "BookPerformance", name: $0)
        }
    }

    func testT19PhysicalFirstPlaybackFrames() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045", "--performance-probe"]
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: t19AnimationMetrics, options: options) {
            // XCTest会丢弃预热轮；每轮重启进程，保证被测动作仍是首次播放。
            app.terminate(); app.launch(); expect("closed|ready")
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.55))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.23, dy: 0.55))
            start.press(forDuration: 0.15, thenDragTo: end)
            expect("reading|ready")
            end.press(forDuration: 0.15, thenDragTo: start)
            expect("closed|ready")
        }
    }

    func testT19FocusedChangingIntervals() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045", "--performance-probe"]
        app.launch(); expect("closed|ready")
        let options = XCTMeasureOptions(); options.iterationCount = 1
        let names = ["BookOpening", "BookClosing", "BookInk", "BookErasing",
                     "BookOpeningMoving", "BookClosingMoving", "BookInkChanging", "BookErasingChanging"]
        let metrics = names.map { XCTOSSignpostMetric(subsystem: "AnswersBook.Performance", category: "BookPerformance", name: $0) }
        measure(metrics: metrics, options: options) {
            for _ in 0..<3 {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.55))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.23, dy: 0.55))
                start.press(forDuration: 0.15, thenDragTo: end); expect("reading|ready")
                end.press(forDuration: 0.15, thenDragTo: start); expect("closed|ready")
            }
        }
    }

    func testT19UnpolledChangingIntervals() {
        app.terminate()
        app.launchEnvironment["T10_STORE_TOKEN"] = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--repeat-answer-045", "--performance-probe"]
        app.launch(); expect("closed|ready")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.23, dy: 0.55))
        let names = ["BookOpening", "BookClosing", "BookInk", "BookErasing",
                     "BookOpeningMoving", "BookClosingMoving", "BookInkChanging", "BookErasingChanging"]
        let metrics = names.map { XCTOSSignpostMetric(subsystem: "AnswersBook.Performance", category: "BookPerformance", name: $0) }
        let options = XCTMeasureOptions(); options.iterationCount = 1
        measure(metrics: metrics, options: options) {
            for _ in 0..<3 {
                start.press(forDuration: 0.15, thenDragTo: end)
                // 只暂停测试Runner；不轮询App的可访问性树、不阻塞App主线程。
                Thread.sleep(forTimeInterval: 4)
                end.press(forDuration: 0.15, thenDragTo: start)
                Thread.sleep(forTimeInterval: 3.5)
            }
        }
        expect("closed|ready")
        // XCTest额外执行一轮预热，合计6轮；逐动作完成另从诊断文件核对。
        XCTAssertTrue(app.staticTexts["draw-state"].label.hasPrefix("6|"))
        capture("T19-不轮询测量后合书")
    }

}

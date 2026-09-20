import XCTest
final class JewelRingUITests:XCTestCase {
    var app:XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure=false
        app=XCUIApplication();app.launchArguments=["--ui-test"]
        app.launchEnvironment["JEWEL_TEST_ID"]=UUID().uuidString
        app.launchEnvironment["MTL_DEBUG_LAYER"]="1";app.launch()
        XCTAssertTrue(app.buttons["ring.games"].waitForExistence(timeout:15))
        XCTAssertEqual(app.staticTexts["ring.count"].label,"0 / 4")
    }
    func screenshot(_ name:String) { let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
    func pick(_ key:String) {
        let b=app.buttons["ring.games"];if !b.isHittable {app.swipeUp()};b.tap()
        let gem=app.buttons["game.pick."+key];XCTAssertTrue(gem.waitForExistence(timeout:5));gem.tap()
        XCTAssertTrue(app.buttons["mini.close"].waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["mini.error"].exists)
    }
    func abandon() {
        app.buttons["mini.close"].tap();app.buttons["報酬なしで終了"].tap()
        XCTAssertTrue(app.buttons["ring.games"].waitForExistence(timeout:8))
    }
    func testPreviewContinuousInspectionPositionAndDoubleTap() {
        screenshot("empty-ring")
        app.buttons["ring.preview"].tap()
        let diamond=app.buttons["jewel.diamond"]
        XCTAssertTrue(diamond.waitForExistence(timeout:5))
        let scene=app.otherElements["jewel.scene"]
        scene.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.83)).press(forDuration:0.05,thenDragTo:scene.coordinate(withNormalizedOffset:.init(dx:0.17,dy:0.5)))
        XCTAssertFalse(app.buttons["inspector.back"].exists)
        // Freeze the ring with a touch before taking the return-position snapshot.
        scene.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.5)).tap()
        let before=diamond.frame
        screenshot("four-jewels")
        diamond.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.5)).tap();XCTAssertTrue(app.buttons["inspector.back"].waitForExistence(timeout:5))
        app.buttons["level.3"].tap();XCTAssertTrue(app.staticTexts["inspector.atoms"].waitForExistence(timeout:5))
        XCTAssertTrue(scene.exists,"Continuous zoom retains one Metal view")
        screenshot("diamond-lattice")
        app.buttons["inspector.back"].tap();XCTAssertTrue(diamond.waitForExistence(timeout:5))
        XCTAssertEqual(before.midX,diamond.frame.midX,accuracy:2);XCTAssertEqual(before.midY,diamond.frame.midY,accuracy:2)
        app.terminate();app.launch();XCTAssertTrue(diamond.waitForExistence(timeout:10))
        XCTAssertEqual(before.midX,diamond.frame.midX,accuracy:2);XCTAssertEqual(before.midY,diamond.frame.midY,accuracy:2)
        app.buttons["jewel.ruby"].doubleTap();XCTAssertTrue(app.staticTexts["mini.traceReady"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["inspector.back"].exists)
        screenshot("grass-trace");abandon()
        XCTAssertEqual(app.staticTexts["ring.count"].label,"0 / 4")
    }
    func testKurukuruRewardPersistenceProgressAndPause() {
        pick("blackOnyx");XCTAssertFalse(app.buttons["mini.start"].exists)
        let cells=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'mini.cell.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout:5));XCTAssertEqual(cells.count,16)
        screenshot("kurukuru-4x4")
        app.buttons["mini.pause"].tap();XCTAssertTrue(app.buttons["mini.resume"].waitForExistence(timeout:3))
        let time=app.staticTexts["mini.time"].label
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for:.runningBackground,timeout:5))
        app.activate();XCTAssertTrue(app.wait(for:.runningForeground,timeout:5))
        expectation(for:NSPredicate(format:"hittable == true"),evaluatedWith:app.buttons["mini.resume"]);waitForExpectations(timeout:8)
        XCTAssertEqual(app.staticTexts["mini.time"].label,time)
        app.buttons["mini.resume"].tap();XCTAssertTrue(cells.firstMatch.waitForExistence(timeout:6))
        for direction in ["時計回り","反時計回り"] {
            let ids=cells.matching(NSPredicate(format:"value == %@",direction)).allElementsBoundByIndex.map(\.identifier)
            for id in ids {app.buttons[id].tap()}
        }
        XCTAssertTrue(app.staticTexts["reward.saved"].waitForExistence(timeout:8));screenshot("jewel-reward")
        if app.buttons["reward.back"].exists {app.buttons["reward.back"].tap()}
        XCTAssertTrue(app.buttons["ring.games"].waitForExistence(timeout:8));XCTAssertEqual(app.staticTexts["ring.count"].label,"1 / 4")
        app.terminate();app.launch();XCTAssertTrue(app.buttons["ring.games"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["ring.count"].label,"1 / 4");XCTAssertEqual(app.staticTexts["ring.selection"].label,"ブラックオニキス")
        pick("blackOnyx");XCTAssertEqual(app.staticTexts["mini.size"].label,"6×6");abandon()
        pick("emerald");XCTAssertEqual(app.staticTexts["mini.size"].label,"4×4");abandon()
    }
    func testEmptySeatStartsGameAndRTIsUnavailableInSimulator() {
        app.buttons["jewel.diamond"].tap()
        XCTAssertTrue(app.buttons["mini.close"].waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["mini.start"].exists)
        XCTAssertTrue(app.staticTexts["mini.failure"].waitForExistence(timeout:10))
        app.buttons["failure.back"].tap()
        app.buttons["jewel.settings"].tap()
        let rt=app.switches["settings.rayTracing"]
        XCTAssertTrue(rt.waitForExistence(timeout:5));XCTAssertFalse(rt.isEnabled)
        screenshot("settings-ray-unavailable")
    }
    func testGrassTraceShatterCompletion() {
        pick("ruby")
        let target=app.buttons["mini.target"];XCTAssertTrue(target.waitForExistence(timeout:20));target.tap()
        XCTAssertTrue(app.staticTexts["mini.failure"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["mini.count"].label,"ヒビ 3 / 3")
        expectation(for:NSPredicate(format:"value == %@","破砕完了"),evaluatedWith:app.staticTexts["mini.thickness"]);waitForExpectations(timeout:25)
        XCTAssertFalse(app.staticTexts["mini.error"].exists);screenshot("trace-shattered")
        app.buttons["failure.back"].tap();XCTAssertEqual(app.staticTexts["ring.count"].label,"0 / 4")
    }
    func testGrassBreakShatterCompletion() {
        pick("diamond");XCTAssertFalse(app.buttons["mini.start"].exists)
        XCTAssertTrue(app.staticTexts["mini.failure"].waitForExistence(timeout:7));screenshot("break-timeout")
        app.buttons["failure.back"].tap();XCTAssertEqual(app.staticTexts["ring.count"].label,"0 / 4")
        pick("diamond")
        let count=app.staticTexts["mini.count"].label.split(separator:"/").last!.split(separator:" ").first!
        let hits=Int(count)!
        XCTAssertTrue(app.buttons["mini.target"].waitForExistence(timeout:15))
        for _ in 0..<hits {
            let target=app.buttons["mini.target"];XCTAssertTrue(target.waitForExistence(timeout:3));target.tap()
        }
        XCTAssertTrue(app.staticTexts["reward.saved"].waitForExistence(timeout:25))
        XCTAssertEqual(app.staticTexts["mini.thickness"].value as? String,"破砕完了")
        XCTAssertFalse(app.staticTexts["mini.error"].exists);screenshot("break-reward")
        if app.buttons["reward.back"].exists {app.buttons["reward.back"].tap()}
        XCTAssertTrue(app.buttons["ring.games"].waitForExistence(timeout:8));XCTAssertEqual(app.staticTexts["ring.count"].label,"1 / 4")
    }
}

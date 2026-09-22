import XCTest
final class JewelRingUITests:XCTestCase {
    var app:XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure=false;app=XCUIApplication()
        // These tests assert Japanese copy, so pin the language regardless of the simulator setting.
        app.launchArguments=["--ui-test","-AppleLanguages","(ja)","-AppleLocale","ja_JP"]
        app.launchEnvironment["JEWEL_TEST_ID"]=UUID().uuidString;app.launchEnvironment["MTL_DEBUG_LAYER"]="1";app.launch()
        XCTAssertTrue(app.buttons["ring.games"].waitForExistence(timeout:15))
    }
    func tap(_ element:XCUIElement) {
        app.revealAndTap(element)
    }
    func pick(_ kind:String,_ depth:Int=1) {
        tap(app.buttons["ring.games"])
        let button=app.buttons["game.pick.\(kind).\(depth)"]
        tap(button)
    }
    func shot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func testSingleGemRotationAndReturnWithoutZoom() {
        tap(app.buttons["ring.preview"])
        // Return to the top after the development control scrolls below the ring.
        app.scrollContentDown();app.scrollContentDown()
        let diamond=app.buttons["jewel.diamond"];XCTAssertTrue(diamond.waitForExistence(timeout:5))
        shot("ring-before-inspection")
        // MTKView's container frame is local in iPad compatibility mode; the
        // pedestal frames are converted to screen coordinates by the view.
        let centerX=(app.buttons["jewel.ruby"].frame.midX+app.buttons["jewel.sapphire"].frame.midX)/2
        let centerY=(diamond.frame.midY+app.buttons["jewel.obsidian"].frame.midY)/2
        let before=diamond.frame;diamond.tap()
        XCTAssertTrue(app.buttons["inspector.back"].waitForExistence(timeout:5))
        let centered=NSPredicate {_,_ in abs(diamond.frame.midX-centerX)<2 && abs(diamond.frame.midY-centerY)<2}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:centered,object:nil)],timeout:5),.completed)
        XCTAssertFalse(app.buttons["level.3"].exists);XCTAssertFalse(app.sliders["inspector.zoom"].exists)
        XCTAssertFalse(app.buttons["jewel.ruby"].exists);XCTAssertFalse(app.buttons["jewel.sapphire"].exists)
        XCTAssertEqual(diamond.frame.midX,centerX,accuracy:2);XCTAssertEqual(diamond.frame.midY,centerY,accuracy:2)
        XCTAssertEqual(diamond.frame.width,before.width,accuracy:1);XCTAssertEqual(diamond.frame.height,before.height,accuracy:1)
        shot("single-gem-same-scale")
        let center=diamond.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.5))
        center.press(forDuration:0.05,thenDragTo:center.withOffset(.init(dx:90,dy:50)))
        shot("single-gem-after-swipe")
        diamond.tap() // Single tap on the spotlighted gem reverses the presentation.
        XCTAssertTrue(app.buttons["jewel.ruby"].waitForExistence(timeout:5))
        XCTAssertEqual(diamond.frame.midX,before.midX,accuracy:2);XCTAssertEqual(diamond.frame.midY,before.midY,accuracy:2)
        shot("ring-after-inspection")
        tap(app.buttons["ring.inventory"]);XCTAssertTrue(app.staticTexts["まだ宝石がありません"].waitForExistence(timeout:5));shot("empty-inventory")
        app.buttons["閉じる"].tap();app.scrollContentDown();app.scrollContentDown();app.buttons["world.next"].tap()
        XCTAssertTrue(app.staticTexts["world.comingSoon"].waitForExistence(timeout:5));shot("world-two-coming-soon")
    }
    func testKurukuruAcquisitionAndDepthUnlockSurviveRelaunch() {
        pick("sapphire")
        let cells=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'mini.cell.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout:10));XCTAssertEqual(cells.count,16)
        shot("sapphire-kurukuru")
        for direction in ["時計回り","反時計回り"] {
            let ids=cells.matching(NSPredicate(format:"value == %@",direction)).allElementsBoundByIndex.map(\.identifier)
            for id in ids {app.buttons[id].tap()}
        }
        XCTAssertTrue(app.staticTexts["reward.saved"].waitForExistence(timeout:10));shot("carat-reward")
        if app.buttons["reward.back"].exists {app.buttons["reward.back"].tap()}
        XCTAssertTrue(app.buttons["ring.games"].waitForExistence(timeout:10))
        app.terminate();app.launch();XCTAssertTrue(app.buttons["ring.inventory"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["ring.count"].label,"収集 1 / 4 種類")
        tap(app.buttons["ring.inventory"]);XCTAssertTrue(app.staticTexts["1 個"].waitForExistence(timeout:5));shot("owned-inventory")
        app.buttons["閉じる"].tap();pick("sapphire",2)
        XCTAssertTrue(app.staticTexts["mini.size"].waitForExistence(timeout:8));XCTAssertEqual(app.staticTexts["mini.size"].label,"6×6")
    }
    func testTimedCrusherAwardsAndKeepsCollection() {
        pick("obsidian")
        let glass=app.buttons["crusher.glass"]
        XCTAssertTrue(glass.waitForExistence(timeout:10))
        expectation(for:NSPredicate(format:"value == %@","0:0:active"),evaluatedWith:glass);waitForExpectations(timeout:15)
        shot("crusher-weak-point")
        for _ in 0..<3 {glass.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.5)).tap()}
        XCTAssertTrue(app.staticTexts["crusher.result"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["crusher.reward"].waitForExistence(timeout:5));shot("crusher-ten-second-result")
        XCTAssertTrue(app.staticTexts["crusher.reward"].label.contains("保存しました"))
        XCTAssertTrue(app.staticTexts["crusher.time"].label.contains("0.0"))
        app.buttons["crusher.close"].tap()
        XCTAssertTrue(app.buttons["ring.inventory"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["ring.count"].label,"収集 1 / 4 種類")
    }
    func testDiamondRendersWithoutMetalError() {
        pick("diamond")
        XCTAssertTrue(app.buttons["mini.target"].waitForExistence(timeout:15))
        XCTAssertFalse(app.staticTexts["mini.error"].exists)
        XCTAssertTrue(app.staticTexts["mini.thickness"].exists)
        shot("diamond-device-rendering")
    }
    func testRubyGuidesDoNotBlockTouch() {
        pick("ruby")
        let target=app.buttons["mini.target"]
        XCTAssertTrue(target.waitForExistence(timeout:12));shot("ruby-full-screen-guides")
        target.tap()
        XCTAssertTrue(app.staticTexts["緑の点を追いかけてください。"].waitForExistence(timeout:3))
        shot("ruby-guides-playing")
    }
    func testUnconfiguredPurchaseDoesNotUnlockAndRTIsDisabled() {
        tap(app.buttons["ring.unlock"])
        XCTAssertTrue(app.staticTexts["purchase.status"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["purchase.buy"].isEnabled);shot("purchase-setup-pending")
        app.buttons["閉じる"].tap();app.scrollContentDown();app.scrollContentDown();app.buttons["jewel.settings"].tap()
        XCTAssertTrue(app.switches["settings.rayTracing"].waitForExistence(timeout:5));XCTAssertFalse(app.switches["settings.rayTracing"].isEnabled)
    }
}

/// English launch. Run on iPhone 12 mini-class and iPad simulators and review the kept screenshots for clipping.
/// Fails if Localizable.xcstrings is not bundled in the Tamor target or a visible string has no English entry.
final class TamorEnglishUITests:XCTestCase {
    var app:XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure=false;app=XCUIApplication()
        app.launchArguments=["--ui-test","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launchEnvironment["JEWEL_TEST_ID"]=UUID().uuidString;app.launch()
        XCTAssertTrue(app.buttons["ring.games"].waitForExistence(timeout:15))
        XCTAssertFalse(app.staticTexts["最初の宝石を見つけよう"].exists,"Localizable.xcstrings is not bundled in the Tamor target; the English UI is not active.")
    }
    func tap(_ element:XCUIElement) {app.revealAndTap(element)}
    func shot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    /// Every label currently on screen must be free of kana/kanji. Call after the screen has settled.
    func assertNoJapanese(_ screen:String,file:StaticString=#filePath,line:UInt=#line) {
        // Capture once: the reward sheet dismisses automatically after four seconds.
        // Live index-based queries can otherwise resolve against different screens.
        do {
            let snapshot=try app.snapshot()
            func inspect(_ element:XCUIElementSnapshot) {
                if [.staticText,.button,.switch,.navigationBar].contains(element.elementType) {
                    let text=element.label+" "+((element.value as? String) ?? "")
                    let japanese=text.unicodeScalars.contains{(0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)}
                    XCTAssertFalse(japanese,"\(screen): untranslated text \"\(text)\"",file:file,line:line)
                }
                for child in element.children {inspect(child)}
            }
            inspect(snapshot)
        } catch {XCTFail("Cannot inspect \(screen): \(error)",file:file,line:line)}
    }

    func testEnglishHomePaywallAndSettings() {
        XCTAssertTrue(app.staticTexts["Find your first gem"].exists);shot("en-home");assertNoJapanese("home")
        XCTAssertEqual(app.staticTexts["ring.count"].label,"Collected 0 / 4 kinds")
        tap(app.buttons["ring.unlock"])
        XCTAssertTrue(app.staticTexts["Into the depths of World 1"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["purchase.restore"].exists);XCTAssertFalse(app.buttons["purchase.buy"].isEnabled);shot("en-paywall")
        // The status line is absent once a product loads, so wait for it without requiring it.
        _=app.staticTexts["purchase.status"].waitForExistence(timeout:3);assertNoJapanese("paywall")
        app.buttons["Close"].tap();app.scrollContentDown();app.scrollContentDown();app.buttons["jewel.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        shot("en-settings");assertNoJapanese("settings")
        let notice=app.staticTexts["save.localNotice"]
        for _ in 0..<6 {if notice.exists {break};app.scrollContentUp()}
        XCTAssertTrue(notice.label.hasPrefix("Your gems are saved on this device."))
        let restore=app.buttons["Restore Purchases"]
        for _ in 0..<6 {if restore.exists {break};app.scrollContentUp()}
        XCTAssertTrue(restore.exists);shot("en-settings-lower");assertNoJapanese("settings-lower")
        app.scrollContentUp();shot("en-support-links");assertNoJapanese("support-links")
    }
    func testEnglishRewardResultAndInventory() {
        tap(app.buttons["ring.games"]);shot("en-depth-picker");assertNoJapanese("depth-picker");tap(app.buttons["game.pick.sapphire.1"])
        let cells=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'mini.cell.'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout:10))
        let canvas=app.otherElements["mini.canvas"].frame
        XCTAssertEqual(canvas.width,canvas.height,accuracy:1,"The board must remain square so visible cells and tap targets align.")
        shot("en-kurukuru-board")
        for direction in ["Clockwise","Counterclockwise"] {
            let ids=cells.matching(NSPredicate(format:"value == %@",direction)).allElementsBoundByIndex.map(\.identifier)
            for id in ids {app.buttons[id].tap()}
        }
        XCTAssertTrue(app.staticTexts["reward.saved"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["reward.title"].label,"Sapphire acquired!");shot("en-reward");assertNoJapanese("reward")
        if app.buttons["reward.back"].exists {app.buttons["reward.back"].tap()}
        XCTAssertTrue(app.buttons["ring.inventory"].waitForExistence(timeout:10))
        tap(app.buttons["ring.inventory"]);XCTAssertTrue(app.staticTexts["1 gem"].waitForExistence(timeout:5));shot("en-inventory");assertNoJapanese("inventory")
    }
    func testEnglishCrusherResult() {
        tap(app.buttons["ring.games"]);tap(app.buttons["game.pick.obsidian.1"])
        let glass=app.buttons["crusher.glass"];XCTAssertTrue(glass.waitForExistence(timeout:10))
        expectation(for:NSPredicate(format:"value == %@","0:0:active"),evaluatedWith:glass);waitForExpectations(timeout:15)
        shot("en-crusher-playing")
        for _ in 0..<3 {glass.coordinate(withNormalizedOffset:.init(dx:0.5,dy:0.5)).tap()}
        XCTAssertTrue(app.staticTexts["crusher.reward"].waitForExistence(timeout:20));shot("en-crusher-result");assertNoJapanese("crusher-result")
        XCTAssertTrue(app.staticTexts["crusher.reward"].label.contains("saved"))
    }
}

// iPhone compatibility mode on iPad has a smaller app viewport. Target its
// scroll container, not the full-device application frame (which includes margins).
private extension XCUIApplication {
    func revealAndTap(_ element:XCUIElement) {
        for _ in 0..<12 {
            let frame=element.exists ? element.frame:CGRect.zero
            let navigation=navigationBars.firstMatch
            let top=navigation.exists ? navigation.frame.maxY:windows.firstMatch.frame.minY
            let bottom=windows.firstMatch.frame.maxY
            if element.isHittable && frame.midY>top+8 && frame.midY<bottom-8 {break}
            let container=contentScrollView
            let belowTop=element.exists && frame.midY<=top+8
            let start=container.coordinate(withNormalizedOffset:.init(dx:0.5,dy:belowTop ? 0.4:0.75))
            let end=container.coordinate(withNormalizedOffset:.init(dx:0.5,dy:belowTop ? 0.75:0.4))
            start.press(forDuration:0.05,thenDragTo:end)
        }
        element.tap()
    }
    var contentScrollView:XCUIElement {
        let list=collectionViews.firstMatch
        if list.exists {return list}
        let scroll=scrollViews.firstMatch
        return scroll.exists ? scroll:self
    }
    func scrollContentUp() {contentScrollView.swipeUp()}
    func scrollContentDown() {contentScrollView.swipeDown()}
}

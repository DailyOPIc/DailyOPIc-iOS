//
//  DailyOPIcUITests.swift
//  DailyOPIcUITests
//
//  Created by 이병찬 on 6/22/26.
//

import XCTest

final class DailyOPIcUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testNewUserCanEnterAndSkipGuide() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingNewUser"]
        app.launch()

        XCTAssertTrue(app.staticTexts["오픽 시험이 처음이신가요?"].waitForExistence(timeout: 5))
        app.buttons["네, 가이드를 볼게요"].tap()
        XCTAssertTrue(app.staticTexts["DailyOPIc는 AI 학습 도구예요"].waitForExistence(timeout: 2))
        app.buttons["건너뛰기"].tap()
        XCTAssertTrue(app.staticTexts["OPIc 시작 난이도를 선택해 주세요"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testOnboardingSupportsAccessibilityTextAndReduceMotion() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingNewUser",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "-UIAccessibilityReduceMotionEnabled",
            "YES"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["아니오, 난이도를 선택할게요"].waitForExistence(timeout: 5))
        app.buttons["아니오, 난이도를 선택할게요"].tap()
        XCTAssertTrue(app.staticTexts["OPIc 시작 난이도를 선택해 주세요"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

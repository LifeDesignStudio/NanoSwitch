//
//  nanoswitchUITestsLaunchTests.swift
//  nanoswitchUITests
//
//  Created by Yoshiyuki Koyama on 2026/03/01.
//

import XCTest

final class nanoswitchUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        // NanoSwitch はメニューバー常駐アプリのため UI ウィンドウは存在しない
    }
}

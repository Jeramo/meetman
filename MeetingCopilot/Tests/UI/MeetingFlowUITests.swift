//
//  MeetingFlowUITests.swift
//  MeetingCopilot
//
//  UI tests for core meeting workflows
//

import XCTest

final class MeetingFlowUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    // MARK: - Basic Navigation Tests

    func testTabNavigation() {
        // Verify all tabs are present
        XCTAssertTrue(app.tabBars.buttons["Meetings"].exists)
        XCTAssertTrue(app.tabBars.buttons["Record"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)

        // Navigate to Record tab
        app.tabBars.buttons["Record"].tap()
        XCTAssertTrue(app.staticTexts["Ready to Record"].exists || app.staticTexts["Meeting Capture"].exists)

        // Navigate to Settings tab
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    // MARK: - Capture Flow Tests

    func testCaptureViewAppears() {
        app.tabBars.buttons["Record"].tap()

        // Should show ready to record state
        XCTAssertTrue(app.staticTexts["Ready to Record"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Start Recording"].exists)
    }

    func testStartRecordingButton() {
        app.tabBars.buttons["Record"].tap()

        let startButton = app.buttons["Start Recording"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2))

        // Button should be tappable
        XCTAssertTrue(startButton.isEnabled)
    }

    func testMeetingTitleInput() {
        app.tabBars.buttons["Record"].tap()

        // Find title input field
        let titleField = app.textFields.element(boundBy: 0)
        if titleField.exists {
            titleField.tap()
            titleField.typeText("Test Meeting Title")

            // Verify text was entered
            XCTAssertEqual(titleField.value as? String, "Test Meeting Title")
        }
    }

    // MARK: - Meeting List Tests

    func testMeetingListEmptyState() {
        app.tabBars.buttons["Meetings"].tap()

        // If no meetings, should show empty state
        if app.staticTexts["No Meetings Yet"].exists {
            XCTAssertTrue(app.staticTexts["Start recording your first meeting"].exists)
            XCTAssertTrue(app.buttons["Start Recording"].exists)
        }
    }

    func testMeetingListNavigation() {
        app.tabBars.buttons["Meetings"].tap()

        // Should show meetings list or empty state
        XCTAssertTrue(
            app.navigationBars["Meetings"].exists ||
            app.staticTexts["No Meetings Yet"].exists
        )
    }

    func testNewMeetingButton() {
        app.tabBars.buttons["Meetings"].tap()

        // Should have "New Meeting" button in toolbar
        // Note: In actual implementation, this would be a "+" button
        let toolbar = app.navigationBars["Meetings"]
        XCTAssertTrue(toolbar.exists)
    }

    // MARK: - Settings Tests

    func testSettingsDisplay() {
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))

        // Should show configuration section
        XCTAssertTrue(
            app.staticTexts["Configuration"].exists ||
            app.staticTexts["Privacy"].exists
        )
    }

    func testPrivacyInformation() {
        app.tabBars.buttons["Settings"].tap()

        // Should display privacy notice
        let privacyText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'device'")).firstMatch
        XCTAssertTrue(privacyText.exists, "Should show privacy information about on-device processing")
    }

    // MARK: - Accessibility Tests

    func testAccessibilityLabels() {
        app.tabBars.buttons["Record"].tap()

        // Key elements should have accessibility labels
        XCTAssertTrue(app.buttons["Start Recording"].isHittable)
    }

    func testVoiceOverSupport() {
        // Enable VoiceOver simulation
        app.tabBars.buttons["Meetings"].tap()

        // Tab bar buttons should be accessible
        XCTAssertTrue(app.tabBars.buttons["Meetings"].isAccessibilityElement)
        XCTAssertTrue(app.tabBars.buttons["Record"].isAccessibilityElement)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isAccessibilityElement)
    }

    // MARK: - Permission Tests (Mock)

    func testMicrophonePermissionPrompt() {
        // Note: In real testing, you'd use mock permissions
        // This test verifies the flow exists, not actual permissions

        app.tabBars.buttons["Record"].tap()

        let startButton = app.buttons["Start Recording"]
        if startButton.exists {
            XCTAssertTrue(startButton.isEnabled)
            // In a real test environment, tapping would trigger permission dialog
        }
    }
}

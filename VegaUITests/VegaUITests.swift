import XCTest

final class VegaUITests: XCTestCase {

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
    func testShowsSignInForm() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-skipSessionRestore")
        app.launch()

        XCTAssertTrue(app.textFields["Instance URL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Username or email"].exists)
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.buttons["Sign in"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Sign-in form"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testShowsBasicLoggingDiary() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestBasicDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()

        assertPopulatedDiary(in: app)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Basic logging diary"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testShowsPlannedMealsDiary() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestPlannedDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()

        assertPopulatedDiary(in: app)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Planned meals diary"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func assertPopulatedDiary(in app: XCUIApplication) {
        let elements = app.descendants(matching: .any)
        XCTAssertTrue(elements["nutrition-summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(elements["diary-item-oats"].exists)
        XCTAssertTrue(elements["diary-item-blueberries"].exists)
        XCTAssertTrue(elements["diary-item-tofu"].exists)
    }

}

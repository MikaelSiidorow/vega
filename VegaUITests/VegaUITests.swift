import XCTest

class VegaUITestCase: XCTestCase {

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
    func assertPopulatedDiary(in app: XCUIApplication) {
        let elements = app.descendants(matching: .any)
        XCTAssertTrue(elements["nutrition-summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(elements["diary-item-oats"].exists)
        XCTAssertTrue(elements["diary-item-blueberries"].exists)
        XCTAssertTrue(elements["diary-item-tofu"].exists)
    }

    func normalizedWhitespace(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

final class SignInFormUITests: VegaUITestCase {
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
}

final class BasicLoggingDiaryUITests: VegaUITestCase {
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
}

final class PlannedMealsDiaryUITests: VegaUITestCase {
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
}

final class DeleteDiaryEntryUITests: VegaUITestCase {
    @MainActor
    func testDeletesDiaryEntry() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestBasicDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()

        let blueberries = app.descendants(matching: .any)["diary-item-blueberries"]
        XCTAssertTrue(blueberries.waitForExistence(timeout: 5))
        blueberries.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 2))
        app.buttons["Delete"].tap()

        XCTAssertTrue(app.buttons["Delete entry"].waitForExistence(timeout: 2))
        let confirmation = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        confirmation.name = "Delete diary entry confirmation"
        confirmation.lifetime = .keepAlways
        add(confirmation)

        app.buttons["Delete entry"].tap()
        let removed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: blueberries
        )
        wait(for: [removed], timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["diary-item-oats"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["diary-item-tofu"].exists)

        let result = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        result.name = "Diary after deleting blueberries"
        result.lifetime = .keepAlways
        add(result)
    }
}

final class EditDiaryAmountUITests: VegaUITestCase {
    @MainActor
    func testEditsDiaryAmountAndUnit() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestBasicDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()

        let tofu = app.descendants(matching: .any)["diary-item-tofu"]
        XCTAssertTrue(tofu.waitForExistence(timeout: 5))
        tofu.tap()

        let amount = app.textFields["diary-edit-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 2))
        amount.tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        amount.typeText("150")

        let unit = app.descendants(matching: .any)["diary-edit-unit"]
        XCTAssertTrue(unit.exists)
        unit.tap()
        XCTAssertTrue(app.buttons["grams"].waitForExistence(timeout: 2))
        app.buttons["grams"].tap()

        XCTAssertTrue(
            normalizedWhitespace(app.staticTexts["diary-edit-grams"].label).contains("150 g")
        )
        XCTAssertTrue(
            normalizedWhitespace(app.staticTexts["diary-edit-energy"].label).contains("240 kcal")
        )
        let editor = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editor.name = "Edit diary amount and unit"
        editor.lifetime = .keepAlways
        add(editor)

        app.buttons["save-diary-entry"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        XCTAssertTrue(tofu.waitForExistence(timeout: 5))
        XCTAssertTrue(tofu.label.contains("150 g"))

        let result = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        result.name = "Diary after changing tofu to grams"
        result.lifetime = .keepAlways
        add(result)
    }
}

final class EditDiaryMealUITests: VegaUITestCase {
    @MainActor
    func testEditsDiaryMealAssignment() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestPlannedDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()

        let tofu = app.descendants(matching: .any)["diary-item-tofu"]
        XCTAssertTrue(tofu.waitForExistence(timeout: 5))
        tofu.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["diary-edit-date-time"]
                .waitForExistence(timeout: 2)
        )
        let meal = app.descendants(matching: .any)["diary-edit-meal"]
        XCTAssertTrue(meal.exists)
        meal.tap()
        XCTAssertTrue(app.buttons["Breakfast"].waitForExistence(timeout: 2))
        app.buttons["Breakfast"].tap()

        let editor = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editor.name = "Edit diary time and meal"
        editor.lifetime = .keepAlways
        add(editor)

        app.buttons["save-diary-entry"].tap()
        XCTAssertTrue(meal.waitForNonExistence(timeout: 5))
        XCTAssertTrue(tofu.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Breakfast"].exists)
        XCTAssertTrue(app.staticTexts["Dinner"].waitForNonExistence(timeout: 2))

        let result = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        result.name = "Diary after moving tofu to breakfast"
        result.lifetime = .keepAlways
        add(result)
    }
}

final class AddDiaryEntryUITests: VegaUITestCase {
    @MainActor
    func testSearchesPreviewsAndAddsIngredient() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestBasicDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["add-diary-entry"].waitForExistence(timeout: 5))
        app.buttons["add-diary-entry"].tap()

        let search = app.searchFields["Search ingredients"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("banana")

        let banana = app.buttons["ingredient-result-4"]
        XCTAssertTrue(banana.waitForExistence(timeout: 5))
        banana.tap()

        let amount = app.textFields["diary-create-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 2))
        amount.tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        amount.typeText("2")

        XCTAssertTrue(
            normalizedWhitespace(app.staticTexts["diary-create-grams"].label).contains("236 g")
        )
        XCTAssertTrue(
            normalizedWhitespace(app.staticTexts["diary-create-energy"].label).contains("210 kcal")
        )

        let preview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        preview.name = "Add banana portion preview"
        preview.lifetime = .keepAlways
        add(preview)

        app.buttons["confirm-add-diary-entry"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        let created = app.descendants(matching: .any)["diary-item-created-1"]
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        XCTAssertTrue(created.label.contains("Banana"))
        XCTAssertTrue(created.label.contains("236 g"))

        let result = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        result.name = "Diary after adding banana"
        result.lifetime = .keepAlways
        add(result)
    }
}

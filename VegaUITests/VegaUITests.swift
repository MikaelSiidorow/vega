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
        XCTAssertTrue(elements["nutrition-goal-energy"].exists)
        XCTAssertTrue(elements["nutrition-goal-protein"].exists)
        XCTAssertTrue(elements["diary-item-oats"].exists)
        XCTAssertTrue(elements["diary-item-blueberries"].exists)
        XCTAssertTrue(elements["diary-item-tofu"].exists)
    }

    func normalizedWhitespace(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @MainActor
    func focus(_ textField: XCUIElement, in app: XCUIApplication) {
        textField.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            textField.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
    }

    @MainActor
    func replaceText(
        _ replacement: String,
        in textField: XCUIElement,
        using app: XCUIApplication,
        placeholder: String
    ) {
        let keyboard = app.keyboards.firstMatch
        var current = textFieldText(textField, placeholder: placeholder)
        while !current.isEmpty {
            let expected = String(current.dropLast())
            keyboard.keys["Delete"].tap()
            XCTAssertTrue(waitForText(expected, in: textField, placeholder: placeholder))
            current = expected
        }

        for character in replacement {
            let expected = current + String(character)
            keyboard.keys[String(character)].tap()
            XCTAssertTrue(waitForText(expected, in: textField, placeholder: placeholder))
            current = expected
        }
    }

    @MainActor
    private func waitForText(
        _ expected: String,
        in textField: XCUIElement,
        placeholder: String
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            let value = element.value as? String ?? ""
            let text = value == placeholder ? "" : value
            return text == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: textField)
        return XCTWaiter.wait(for: [expectation], timeout: 2) == .completed
    }

    @MainActor
    private func textFieldText(_ textField: XCUIElement, placeholder: String) -> String {
        let value = textField.value as? String ?? ""
        return value == placeholder ? "" : value
    }

    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    @MainActor
    func testShowsMFAChallenge() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipSessionRestore", "-uiTestMFAFixture"]
        app.launch()

        let username = app.textFields["Username or email"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.tap()
        username.typeText("test-user")
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("secret")
        app.buttons["Sign in"].tap()

        XCTAssertTrue(app.textFields["mfa-code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Passkey detected"].exists)
        XCTAssertTrue(app.buttons["verify-mfa"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "MFA verification"
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
        XCTAssertTrue(
            app.descendants(matching: .any)["nutrition-goal-energy"].label.contains("remaining")
        )

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
        XCTAssertTrue(app.staticTexts["Planned meal targets"].exists)

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
        let action = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        action.name = "Delete diary entry swipe action"
        action.lifetime = .keepAlways
        add(action)
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
        focus(amount, in: app)
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
    func testRelogsARecentPortionWithItsSavedUnit() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestBasicDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["add-diary-entry"].waitForExistence(timeout: 5))
        app.buttons["add-diary-entry"].tap()

        let suggestions = app.descendants(matching: .any)["recent-food-suggestions"]
        XCTAssertTrue(suggestions.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Around this time"].exists)
        XCTAssertTrue(app.staticTexts["Recent"].exists)

        let tofu = app.buttons["recent-food-3-31-2"]
        XCTAssertTrue(tofu.exists)
        XCTAssertTrue(normalizedWhitespace(tofu.label).contains("2 × portion = 200 g"))

        Thread.sleep(forTimeInterval: 5)
        let recentFoods = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        recentFoods.name = "Recent food suggestions"
        recentFoods.lifetime = .keepAlways
        add(recentFoods)

        tofu.tap()

        let amount = app.textFields["diary-create-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 2))
        XCTAssertEqual(amount.value as? String, "2")
        XCTAssertTrue(
            normalizedWhitespace(app.staticTexts["diary-create-grams"].label).contains("200 g")
        )
        XCTAssertTrue(
            normalizedWhitespace(app.staticTexts["diary-create-energy"].label).contains("320 kcal")
        )

        let preview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        preview.name = "Recent tofu portion preview"
        preview.lifetime = .keepAlways
        add(preview)

        app.buttons["confirm-add-diary-entry"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        let created = app.descendants(matching: .any)["diary-item-created-1"]
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        XCTAssertTrue(created.label.contains("Smoked tofu"))
        XCTAssertTrue(created.label.contains("200 g"))
        XCTAssertTrue(app.descendants(matching: .any)["diary-item-tofu"].exists)

        let result = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        result.name = "Diary after relogging tofu"
        result.lifetime = .keepAlways
        add(result)
    }

    @MainActor
    func testSearchesPreviewsAndAddsIngredient() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestBasicDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["add-diary-entry"].waitForExistence(timeout: 5))
        app.buttons["add-diary-entry"].tap()

        let search = app.searchFields["Search ingredients"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        focus(search, in: app)
        search.typeText("banana")

        let banana = app.buttons["ingredient-result-4"]
        XCTAssertTrue(banana.waitForExistence(timeout: 5))

        // Ephemeral simulator system banners can otherwise obscure visual attachments.
        Thread.sleep(forTimeInterval: 5)
        let searchResults = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        searchResults.name = "Ingredient search results"
        searchResults.lifetime = .keepAlways
        add(searchResults)

        banana.tap()

        let amount = app.textFields["diary-create-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 2))
        focus(amount, in: app)
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

final class BarcodeScannerUITests: VegaUITestCase {
    @MainActor
    func testScansBarcodeAndShowsPortionPreview() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestBasicDiaryFixture",
            "-uiTestBarcodeScannerFixture",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["add-diary-entry"].waitForExistence(timeout: 5))
        app.buttons["add-diary-entry"].tap()
        XCTAssertTrue(app.buttons["scan-barcode"].waitForExistence(timeout: 2))
        app.buttons["scan-barcode"].tap()

        XCTAssertTrue(app.buttons["simulate-barcode-scan"].waitForExistence(timeout: 2))
        let scanner = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        scanner.name = "Barcode scanner"
        scanner.lifetime = .keepAlways
        add(scanner)

        app.buttons["cancel-barcode-scanner"].tap()
        XCTAssertTrue(app.navigationBars["Scan barcode"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["recent-food-suggestions"].exists)

        app.buttons["scan-barcode"].tap()
        XCTAssertTrue(app.buttons["simulate-barcode-scan"].waitForExistence(timeout: 2))
        app.buttons["simulate-barcode-scan"].tap()

        let banana = app.buttons["ingredient-result-4"]
        XCTAssertTrue(banana.waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields["Search ingredients"].value as? String, "5901234123457")
        let results = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        results.name = "Barcode scan search results"
        results.lifetime = .keepAlways
        add(results)

        banana.tap()
        XCTAssertTrue(app.textFields["diary-create-amount"].waitForExistence(timeout: 2))
        let preview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        preview.name = "Scanned product portion preview"
        preview.lifetime = .keepAlways
        add(preview)
    }

    @MainActor
    func testEntersBarcodeWhenCameraIsUnavailable() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestBasicDiaryFixture",
            "-uiTestBarcodeScannerUnavailableFixture",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["add-diary-entry"].waitForExistence(timeout: 5))
        app.buttons["add-diary-entry"].tap()
        XCTAssertTrue(app.buttons["scan-barcode"].waitForExistence(timeout: 2))
        app.buttons["scan-barcode"].tap()

        XCTAssertTrue(app.staticTexts["Scanner unavailable"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["manual-barcode-fallback"].exists)
        let unavailable = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        unavailable.name = "Barcode scanner unavailable"
        unavailable.lifetime = .keepAlways
        add(unavailable)

        app.buttons["manual-barcode-fallback"].tap()
        let code = app.textFields["manual-barcode-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 2))
        code.tap()
        code.typeText("1234")
        XCTAssertTrue(
            app.staticTexts["Enter an 8-, 12-, 13-, or 14-digit product code."]
                .waitForExistence(timeout: 2)
        )
        let fallback = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fallback.name = "Manual barcode fallback"
        fallback.lifetime = .keepAlways
        add(fallback)

        code.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        code.typeText("5901234123457")
        XCTAssertTrue(app.buttons["submit-manual-barcode"].isEnabled)
        app.buttons["submit-manual-barcode"].tap()
        XCTAssertTrue(app.buttons["ingredient-result-4"].waitForExistence(timeout: 5))
    }
}

final class WeightHistoryUITests: VegaUITestCase {
    @MainActor
    func testShowsLatestWeightAndTimeRanges() throws {
        let app = launchWeightFixture()

        XCTAssertTrue(app.descendants(matching: .any)["latest-weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["weight-chart"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["weight-entry-14"].exists)
        capture("Weight history")

        app.buttons["All"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["latest-weight"].label.contains("-4.5 kg")
        )
        capture("All-time weight trend")
    }

    @MainActor
    func testAddsEditsAndDeletesWeight() throws {
        let app = launchWeightFixture()

        app.buttons["add-weight-entry"].tap()
        let input = app.textFields["weight-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        focus(input, in: app)
        replaceText("79.4", in: input, using: app, placeholder: "Weight")
        XCTAssertTrue(app.buttons["save-weight-entry"].isEnabled)
        capture("Add weight entry")
        app.buttons["save-weight-entry"].tap()

        let created = app.descendants(matching: .any)["weight-entry-15"]
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        XCTAssertTrue(created.label.contains("79.4 kg"))
        capture("Weight history after adding")

        created.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        focus(input, in: app)
        replaceText("79.2", in: input, using: app, placeholder: "Weight")
        capture("Edit weight entry")
        app.buttons["save-weight-entry"].tap()
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        XCTAssertTrue(created.label.contains("79.2 kg"))
        capture("Weight history after editing")

        created.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 2))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete entry"].waitForExistence(timeout: 2))
        capture("Delete weight entry confirmation")
        app.buttons["Delete entry"].tap()
        XCTAssertTrue(created.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["weight-entry-14"].exists)
        capture("Weight history after deleting")
    }

    @MainActor
    private func launchWeightFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestBasicDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Weight"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Weight"].tap()
        return app
    }
}

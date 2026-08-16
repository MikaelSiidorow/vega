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
        XCTAssertTrue(app.staticTexts["Calories remaining"].exists)
        XCTAssertTrue(app.staticTexts["Protein"].exists)
        XCTAssertTrue(elements["diary-item-oats"].exists)
        XCTAssertTrue(elements["diary-item-blueberries"].exists)
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
    func selectTab(_ name: String, in app: XCUIApplication, showing destination: XCUIElement) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
        if !destination.waitForExistence(timeout: 2) {
            tab.tap()
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
    }

    @MainActor
    func replaceText(
        _ replacement: String,
        in textField: XCUIElement,
        using app: XCUIApplication,
        placeholder: String
    ) {
        if !app.keyboards.firstMatch.exists {
            focus(textField, in: app)
        }
        let current = textFieldText(textField, placeholder: placeholder)
        if !current.isEmpty {
            textField.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
            )
            XCTAssertTrue(waitForText("", in: textField, placeholder: placeholder))
        }

        for character in replacement {
            textField.typeText(String(character))
        }
        XCTAssertTrue(waitForText(replacement, in: textField, placeholder: placeholder))
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
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
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

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Basic logging diary"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

final class SyncStatusUITests: VegaUITestCase {
    @MainActor
    func testShowsQueuedOfflineChangesInAccountMenu() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestBasicDiaryFixture", "-uiTestSyncOfflineFixture", "-AppleLocale", "en_US",
        ]
        app.launch()

        let account = app.buttons["Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ambient-sync-status"].exists)
        capture("Offline sync status")
        account.tap()

        let status = app.buttons["retry-sync"]
        XCTAssertTrue(status.waitForExistence(timeout: 2))
        XCTAssertTrue(status.label.contains("Offline — 2 changes waiting"))
        capture("Offline changes waiting to sync")
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

        let recentFoods = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        recentFoods.name = "Recent food suggestions"
        recentFoods.lifetime = .keepAlways
        add(recentFoods)

        tofu.tap()

        let amount = app.textFields["diary-create-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 2))
        XCTAssertEqual(amount.value as? String, "2")
        app.swipeUp()
        XCTAssertTrue(
            app.staticTexts["diary-create-grams"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            normalizedWhitespace(app.staticTexts["diary-create-grams"].label).contains("200 g")
        )
        XCTAssertTrue(
            app.staticTexts["diary-create-energy"].waitForExistence(timeout: 2)
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
        XCTAssertTrue(app.buttons["scan-barcode"].waitForExistence(timeout: 5))
        app.buttons["scan-barcode"].tap()

        XCTAssertTrue(app.buttons["simulate-barcode-scan"].waitForExistence(timeout: 2))
        let scanner = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        scanner.name = "Barcode scanner"
        scanner.lifetime = .keepAlways
        add(scanner)

        app.buttons["cancel-barcode-scanner"].tap()
        XCTAssertTrue(app.navigationBars["Scan barcode"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["recent-food-suggestions"].exists)

        XCTAssertTrue(app.buttons["scan-barcode"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["scan-barcode"].waitForExistence(timeout: 5))
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
        focus(code, in: app)
        code.typeText("1234")
        XCTAssertTrue(
            app.staticTexts["Enter an 8-, 12-, 13-, or 14-digit product code."]
                .waitForExistence(timeout: 2)
        )
        let fallback = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fallback.name = "Manual barcode fallback"
        fallback.lifetime = .keepAlways
        add(fallback)

        replaceText("12345678", in: code, using: app, placeholder: "EAN, UPC, or GTIN")
        XCTAssertTrue(
            app.buttons["submit-manual-barcode"]
                .waitForExistence(timeout: 2) && app.buttons["submit-manual-barcode"].isEnabled
        )
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
        XCTAssertTrue(input.waitForNonExistence(timeout: 5))

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
        XCTAssertTrue(input.waitForNonExistence(timeout: 5))
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
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Progress"].tap()
        return app
    }
}

final class AppShellUITests: VegaUITestCase {
    @MainActor
    func testNavigatesBetweenPrimaryDestinationsWithoutLosingDiary() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestBasicDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Diary"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["diary-item-oats"].waitForExistence(timeout: 5))

        selectTab(
            "Workouts",
            in: app,
            showing: app.descendants(matching: .any)["workout-dashboard"]
        )
        XCTAssertTrue(app.buttons["Account"].exists)
        capture("Workouts tab")

        selectTab(
            "Progress",
            in: app,
            showing: app.descendants(matching: .any)["weight-history"]
        )
        capture("Progress tab")

        selectTab(
            "Diary",
            in: app,
            showing: app.descendants(matching: .any)["diary-item-oats"]
        )
        capture("Diary tab after navigation")
    }
}

final class WorkoutUITests: VegaUITestCase {
    @MainActor
    func testBrowsesRoutineAndCorrectsAndDeletesSet() throws {
        let app = launchWorkoutFixture()
        XCTAssertTrue(app.descendants(matching: .any)["today-workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["workout-exercise-7"].exists)
        capture("Today's workout")

        let edited = app.descendants(matching: .any)["workout-log-fixture-log-2"]
        app.buttons["edit-workout-log-fixture-log-2"].tap()
        let repetitions = app.textFields["workout-repetitions"]
        XCTAssertTrue(repetitions.waitForExistence(timeout: 2))
        for _ in 0..<4 {
            app.buttons["Increase repetitions"].tap()
        }
        XCTAssertEqual(repetitions.value as? String, "12")
        let weight = app.textFields["workout-weight"]
        for _ in 0..<5 {
            app.buttons["Decrease weight"].tap()
        }
        XCTAssertEqual(weight.value as? String, "47.5")
        capture("Edit workout set")
        app.buttons["save-workout-set"].tap()
        XCTAssertTrue(repetitions.waitForNonExistence(timeout: 5))
        XCTAssertTrue(edited.waitForExistence(timeout: 5))
        let updated = app.staticTexts.matching(identifier: "workout-log-fixture-log-2")
            .matching(NSPredicate(format: "label CONTAINS %@", "12 Repetitions · 47.5 kg"))
            .firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5))

        let deleted = app.descendants(matching: .any)["workout-log-fixture-log-1"]
        deleted.swipeLeft()
        let deleteAction = app.buttons["delete-workout-log-fixture-log-1"]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 2))
        deleteAction.tap()
        XCTAssertTrue(app.buttons["Delete set"].waitForExistence(timeout: 2))
        capture("Delete workout set confirmation")
        app.buttons["Delete set"].tap()
        XCTAssertTrue(deleted.waitForNonExistence(timeout: 5))
        capture("Workout after deleting set")

        let routine = app.descendants(matching: .any)["workout-routine-42"]
        for _ in 0..<3 where !routine.isHittable {
            app.swipeUp()
        }
        routine.tap()
        XCTAssertTrue(app.descendants(matching: .any)["routine-plan"].waitForExistence(timeout: 2))
        capture("Workout routine plan")
    }

    @MainActor
    func testCompletesFocusedWorkout() throws {
        let app = launchWorkoutFixture()
        let start = app.buttons["start-workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        if !start.isHittable { app.swipeUp() }
        start.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["workout-session-overview"]
                .waitForExistence(timeout: 2))
        capture("Focused workout overview")
        app.buttons["begin-workout"].tap()

        XCTAssertTrue(app.textFields["workout-repetitions"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Repetitions"].exists)
        XCTAssertTrue(app.staticTexts["Weight"].exists)
        capture("Focused workout current set")

        app.buttons["workout-weight-unit"].tap()
        XCTAssertTrue(app.buttons["Body Weight"].waitForExistence(timeout: 2))
        app.buttons["Body Weight"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["workout-weight"].waitForExistence(timeout: 2))
        capture("Focused workout bodyweight shortcut")
        app.buttons["workout-weight-unit"].tap()
        app.buttons["kg"].tap()

        for setIndex in 0..<4 {
            let save = app.buttons["save-workout-set"]
            XCTAssertTrue(save.waitForExistence(timeout: 2))
            save.tap()

            if setIndex < 3 {
                XCTAssertTrue(
                    app.staticTexts["workout-rest"]
                        .waitForExistence(timeout: 5))
                if setIndex == 0 { capture("Focused workout rest timer") }
                let restAction = app.buttons["advance-workout-after-rest"]
                XCTAssertTrue(restAction.waitForExistence(timeout: 2))
                XCTAssertEqual(restAction.label, "Skip rest")
                restAction.tap()
                XCTAssertTrue(
                    app.buttons["save-workout-set"].waitForExistence(timeout: 2))
            }
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["workout-session-summary"]
                .waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["workout-summary-exercise-7"].exists)
        let firstSummarySet =
            app.descendants(matching: .any)["workout-summary-set-7-1"]
        XCTAssertTrue(firstSummarySet.exists)
        XCTAssertTrue(firstSummarySet.label.contains("8 Repetitions · 60 kg"))
        capture("Focused workout summary")
        app.buttons["finish-workout"].tap()
        XCTAssertTrue(app.buttons["start-workout"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func launchWorkoutFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestBasicDiaryFixture", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Workouts"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Workouts"].tap()
        return app
    }
}

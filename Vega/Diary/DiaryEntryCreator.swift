import Foundation
import SwiftUI

struct DiaryEntryCreator: View {
    let meals: [DiaryMeal]
    let search: (String) async throws -> [WgerIngredient]
    let loadSuggestions: () async throws -> RecentFoodSuggestions
    let save: (WgerIngredient, String, Int?, Date, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [WgerIngredient] = []
    @State private var suggestions = RecentFoodSuggestions.empty
    @State private var selectedIngredient: WgerIngredient?
    @State private var amount = "100"
    @State private var weightUnitID: Int?
    @State private var date: Date
    @State private var mealID: String?
    @State private var showsBarcodeScanner = false
    @State private var isSearching = false
    @State private var isLoadingSuggestions = true
    @State private var isSaving = false
    @State private var searchError: String?
    @State private var suggestionError: String?
    @Environment(\.barcodeScannerMode) private var barcodeScannerMode

    init(
        meals: [DiaryMeal],
        initialDate: Date,
        search: @escaping (String) async throws -> [WgerIngredient],
        loadSuggestions: @escaping () async throws -> RecentFoodSuggestions,
        save: @escaping (WgerIngredient, String, Int?, Date, String?) async -> Bool
    ) {
        self.meals = meals
        self.search = search
        self.loadSuggestions = loadSuggestions
        self.save = save
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let ingredient = selectedIngredient {
                    portionForm(ingredient)
                } else {
                    ingredientResults
                }
            }
            .navigationTitle(selectedIngredient == nil ? "Add food" : "Choose portion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedIngredient == nil ? "Cancel" : "Back") {
                        if selectedIngredient == nil {
                            dismiss()
                        } else {
                            selectedIngredient = nil
                        }
                    }
                    .disabled(isSaving)
                }
                if let ingredient = selectedIngredient {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { add(ingredient) }
                            .disabled(normalizedAmount == nil || isSaving)
                            .accessibilityIdentifier("confirm-add-diary-entry")
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Scan barcode", systemImage: "barcode.viewfinder") {
                            showsBarcodeScanner = true
                        }
                        .accessibilityIdentifier("scan-barcode")
                    }
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Adding…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .task {
                await loadRecentFoods()
            }
            .sheet(isPresented: $showsBarcodeScanner) {
                BarcodeScannerView(
                    mode: barcodeScannerMode,
                    onCancel: { showsBarcodeScanner = false }
                ) { barcode in
                    query = barcode.value
                    results = []
                    searchError = nil
                    showsBarcodeScanner = false
                }
            }
        }
    }

    private var ingredientResults: some View {
        Group {
            if isSearching && results.isEmpty {
                ProgressView("Searching…")
            } else if let searchError {
                ContentUnavailableView(
                    "Search failed",
                    systemImage: "wifi.exclamationmark",
                    description: Text(searchError)
                )
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                recentFoodResults
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results, id: \.id) { ingredient in
                    Button {
                        selectSearchResult(ingredient)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ingredient.name)
                                .foregroundStyle(.primary)
                            if let brand = ingredient.brand, !brand.isEmpty {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(ingredient.energy) kcal per 100 g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded { selectSearchResult(ingredient) }
                    )
                    .accessibilityIdentifier("ingredient-result-\(ingredient.id)")
                }
            }
        }
        .searchable(text: $query, prompt: "Search ingredients")
        .task(id: query) {
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.count >= 2 else {
                results = []
                searchError = nil
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(300))
                isSearching = true
                defer { isSearching = false }
                results = try await search(normalized)
                searchError = nil
            } catch is CancellationError {
                return
            } catch {
                results = []
                searchError =
                    (error as? LocalizedError)?.errorDescription
                    ?? "Vega could not search this server. Please try again."
            }
        }
    }

    @ViewBuilder
    private var recentFoodResults: some View {
        if isLoadingSuggestions {
            ProgressView("Loading recent foods…")
        } else if let suggestionError {
            ContentUnavailableView {
                Label("Couldn’t load recent foods", systemImage: "clock.arrow.circlepath")
            } description: {
                Text(suggestionError)
            } actions: {
                Button("Try again") {
                    Task { await loadRecentFoods() }
                }
            }
        } else if suggestions.aroundThisTime.isEmpty && suggestions.recent.isEmpty {
            ContentUnavailableView(
                "No recent foods",
                systemImage: "clock",
                description: Text("Search for an ingredient to start building your history.")
            )
        } else {
            List {
                if !suggestions.aroundThisTime.isEmpty {
                    Section("Around this time") {
                        ForEach(suggestions.aroundThisTime) { portion in
                            recentFoodButton(portion)
                        }
                    }
                }
                if !suggestions.recent.isEmpty {
                    Section("Recent") {
                        ForEach(suggestions.recent) { portion in
                            recentFoodButton(portion)
                        }
                    }
                }
            }
            .accessibilityIdentifier("recent-food-suggestions")
        }
    }

    private func recentFoodButton(_ portion: RecentFoodPortion) -> some View {
        Button {
            selectedIngredient = portion.ingredient
            amount = portion.amount
            weightUnitID = portion.weightUnitID
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(portion.ingredient.name)
                    .foregroundStyle(.primary)
                Text(portionDescription(portion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if portion.matchingTimeCount >= 2 {
                    Text("Logged \(portion.matchingTimeCount) times around this time")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(
                        "Last logged \(portion.lastLoggedAt, format: .dateTime.month(.abbreviated).day())"
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "recent-food-\(portion.id.ingredientID)-\(portion.id.weightUnitID ?? 0)-\(portion.id.amount)"
        )
    }

    private func portionDescription(_ portion: RecentFoodPortion) -> String {
        guard
            let unit = portion.ingredient.weightUnits.first(where: {
                $0.id == portion.weightUnitID
            })
        else {
            return "\(portion.amount) g"
        }
        guard
            let amount = Decimal(
                string: portion.amount,
                locale: Locale(identifier: "en_US_POSIX")
            )
        else { return "\(portion.amount) × \(unit.name)" }
        let grams = amount * Decimal(unit.grams)
        let formattedGrams = grams.formatted(.number.precision(.fractionLength(0...2)))
        return "\(portion.amount) × \(unit.name) = \(formattedGrams) g"
    }

    private func selectSearchResult(_ ingredient: WgerIngredient) {
        selectedIngredient = ingredient
        amount = ingredient.weightUnits.isEmpty ? "100" : "1"
        weightUnitID = ingredient.weightUnits.first?.id
    }

    private func loadRecentFoods() async {
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }
        do {
            suggestions = try await loadSuggestions()
            suggestionError = nil
        } catch is CancellationError {
            return
        } catch {
            suggestions = .empty
            suggestionError =
                (error as? LocalizedError)?.errorDescription
                ?? "Vega could not load your food history. You can still search for an ingredient."
        }
    }

    private func portionForm(_ ingredient: WgerIngredient) -> some View {
        Form {
            Section {
                LabeledContent("Ingredient", value: ingredient.name)
                if let brand = ingredient.brand, !brand.isEmpty {
                    LabeledContent("Brand", value: brand)
                }
            }

            Section("Amount") {
                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("diary-create-amount")
                Picker("Unit", selection: $weightUnitID) {
                    Text("grams").tag(nil as Int?)
                    ForEach(ingredient.weightUnits, id: \.id) { unit in
                        Text(unit.name).tag(Optional(unit.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("diary-create-unit")
            }

            Section("Before adding") {
                LabeledContent("Gram equivalent", value: gramDescription(ingredient))
                    .accessibilityIdentifier("diary-create-grams")
                nutritionPreview(ingredient)
            }

            Section("When and where") {
                DatePicker(
                    "Date and time",
                    selection: $date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Picker("Meal", selection: $mealID) {
                    Text("No meal").tag(nil as String?)
                    ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                        Text(mealTitle(meal, index: index)).tag(Optional(meal.id))
                    }
                }
                .pickerStyle(.menu)
            }

            if !amount.isEmpty, normalizedAmount == nil {
                Section {
                    Text("Enter a positive amount with at most two decimal places.")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func nutritionPreview(_ ingredient: WgerIngredient) -> some View {
        let nutrition = nutrition(for: ingredient)
        return Group {
            LabeledContent("Energy", value: nutrient(nutrition?.energy, unit: "kcal"))
                .accessibilityIdentifier("diary-create-energy")
            LabeledContent("Protein", value: nutrient(nutrition?.protein, unit: "g"))
            LabeledContent("Carbohydrates", value: nutrient(nutrition?.carbohydrates, unit: "g"))
            LabeledContent("Fat", value: nutrient(nutrition?.fat, unit: "g"))
        }
    }

    private var normalizedAmount: String? {
        let value = amount.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
            let whole = parts.first,
            !whole.isEmpty,
            whole.count <= 4,
            whole.allSatisfy(\.isNumber),
            parts.count == 1 || (parts[1].count <= 2 && parts[1].allSatisfy(\.isNumber)),
            let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
            decimal > 0
        else { return nil }
        return value
    }

    private func grams(for ingredient: WgerIngredient) -> Decimal? {
        guard let normalizedAmount,
            let amount = Decimal(
                string: normalizedAmount, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        let unitGrams = ingredient.weightUnits.first { $0.id == weightUnitID }?.grams ?? 1
        return amount * Decimal(unitGrams)
    }

    private func nutrition(for ingredient: WgerIngredient) -> NutritionTotals? {
        guard let grams = grams(for: ingredient) else { return nil }
        let locale = Locale(identifier: "en_US_POSIX")
        return NutritionTotals(
            energy: Decimal(ingredient.energy),
            protein: Decimal(string: ingredient.protein, locale: locale) ?? 0,
            carbohydrates: Decimal(string: ingredient.carbohydrates, locale: locale) ?? 0,
            fat: Decimal(string: ingredient.fat, locale: locale) ?? 0
        ).scaled(toGrams: grams)
    }

    private func gramDescription(_ ingredient: WgerIngredient) -> String {
        guard let grams = grams(for: ingredient) else { return "—" }
        return "\(grams.formatted(.number.precision(.fractionLength(0...2)))) g"
    }

    private func nutrient(_ value: Decimal?, unit: String) -> String {
        guard let value else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private func mealTitle(_ meal: DiaryMeal, index: Int) -> String {
        let name = meal.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name! : "Meal \(index + 1)"
    }

    private func add(_ ingredient: WgerIngredient) {
        guard let normalizedAmount else { return }
        isSaving = true
        Task {
            if await save(ingredient, normalizedAmount, weightUnitID, date, mealID) {
                dismiss()
            } else {
                isSaving = false
            }
        }
    }
}

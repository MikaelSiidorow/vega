import Foundation
import SwiftUI

struct DailyDiaryView: View {
    @Bindable var model: DiaryScreenModel
    let instanceName: String
    let signOut: () -> Void
    @State private var pendingDeletion: DiaryItem?
    @State private var pendingEdit: DiaryItem?
    @State private var showsEntryCreator = false

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView("Loading diary…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t load diary", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") {
                        Task { await model.load() }
                    }
                }
            case .loaded(let diary):
                diaryContent(diary)
            }
        }
        .navigationTitle("Diary")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            datePicker
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add food", systemImage: "plus") {
                    showsEntryCreator = true
                }
                .disabled(model.diary?.planID == nil)
                .accessibilityIdentifier("add-diary-entry")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Text(instanceName)
                    Button("Sign out", role: .destructive, action: signOut)
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
            }
        }
        .task(id: model.selectedDate) {
            await model.load()
        }
        .alert(
            "Delete \(pendingDeletion?.name ?? "entry")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button("Delete entry", role: .destructive) {
                guard let id = pendingDeletion?.remoteID else { return }
                pendingDeletion = nil
                Task { await model.deleteEntry(id: id) }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("This removes the logged ingredient from your diary.")
        }
        .alert(
            model.mutationErrorTitle ?? "Couldn’t change entry",
            isPresented: Binding(
                get: { model.mutationErrorMessage != nil },
                set: { if !$0 { model.mutationErrorMessage = nil } }
            )
        ) {
            Button("OK") { model.mutationErrorMessage = nil }
        } message: {
            Text(model.mutationErrorMessage ?? "")
        }
        .sheet(item: $pendingEdit) { item in
            DiaryEntryEditor(
                item: item,
                meals: model.diary?.meals ?? [],
                fallbackDate: model.selectedDate
            ) { amount, weightUnitID, date, mealID in
                guard let id = item.remoteID else { return false }
                return await model.updateEntry(
                    id: id,
                    amount: amount,
                    weightUnitID: weightUnitID,
                    date: date,
                    mealID: mealID
                )
            }
        }
        .sheet(isPresented: $showsEntryCreator) {
            DiaryEntryCreator(
                meals: model.diary?.meals ?? [],
                initialDate: model.suggestedEntryDate,
                search: model.searchIngredients,
                loadSuggestions: model.recentFoodSuggestions
            ) { ingredient, amount, weightUnitID, date, mealID in
                await model.createEntry(
                    ingredientID: ingredient.id,
                    amount: amount,
                    weightUnitID: weightUnitID,
                    date: date,
                    mealID: mealID
                )
            }
        }
    }

    private var datePicker: some View {
        HStack {
            Button("Previous day", systemImage: "chevron.left") {
                model.selectPreviousDay()
            }
            .labelStyle(.iconOnly)

            Spacer()

            Button {
                model.selectToday()
            } label: {
                VStack(spacing: 2) {
                    Text(model.selectedDate, format: .dateTime.weekday(.wide))
                        .font(.headline)
                    Text(model.selectedDate, format: .dateTime.day().month(.wide).year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show today")

            Spacer()

            Button("Next day", systemImage: "chevron.right") {
                model.selectNextDay()
            }
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func diaryContent(_ diary: DailyDiary) -> some View {
        List {
            Section {
                NutritionSummary(totals: diary.totals, goal: diary.nutritionGoal)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if diary.sections.isEmpty {
                ContentUnavailableView(
                    "Nothing logged",
                    systemImage: "fork.knife",
                    description: Text("This day has no nutrition diary entries.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(diary.sections.enumerated()), id: \.element.id) { index, section in
                    Section(sectionTitle(section, index: index, diary: diary)) {
                        ForEach(section.items) { item in
                            DiaryItemRow(
                                item: item,
                                isDeleting: model.deletingEntryID == item.remoteID
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard item.remoteID != nil else { return }
                                pendingEdit = item
                            }
                            .accessibilityAddTraits(item.remoteID == nil ? [] : .isButton)
                            .swipeActions {
                                if let remoteID = item.remoteID {
                                    Button(role: .destructive) {
                                        pendingDeletion = item
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityIdentifier("delete-diary-item-\(remoteID)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await model.load()
        }
    }

    private func sectionTitle(
        _ section: DiarySection,
        index: Int,
        diary: DailyDiary
    ) -> String {
        switch section.id {
        case .meal(let id):
            if let meal = diary.meals.first(where: { $0.id == id }),
                let name = meal.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty
            {
                return name
            }
            let number = diary.sections.prefix(index + 1).reduce(0) { count, section in
                if case .meal = section.id { return count + 1 }
                return count
            }
            return "Meal \(number)"
        case .timeGroup:
            let dates = section.items.compactMap(\.date)
            guard let first = dates.first, let last = dates.last else { return "Unscheduled" }
            let firstTime = first.formatted(date: .omitted, time: .shortened)
            guard first != last else { return firstTime }
            return "\(firstTime)–\(last.formatted(date: .omitted, time: .shortened))"
        case .unscheduled:
            return "Unscheduled"
        }
    }
}

private struct DiaryEntryCreator: View {
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
                    ToolbarItem(placement: .confirmationAction) {
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

private struct DiaryEntryEditor: View {
    let item: DiaryItem
    let meals: [DiaryMeal]
    let save: (String, Int?, Date, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    @State private var weightUnitID: Int?
    @State private var date: Date
    @State private var mealID: String?
    @State private var isSaving = false

    init(
        item: DiaryItem,
        meals: [DiaryMeal],
        fallbackDate: Date,
        save: @escaping (String, Int?, Date, String?) async -> Bool
    ) {
        self.item = item
        self.meals = meals
        self.save = save
        _amount = State(initialValue: NSDecimalNumber(decimal: item.loggedAmount).stringValue)
        _weightUnitID = State(initialValue: item.weightUnitID)
        _date = State(initialValue: item.date ?? fallbackDate)
        _mealID = State(initialValue: item.mealID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("diary-edit-amount")
                    Picker("Unit", selection: $weightUnitID) {
                        Text("grams").tag(nil as Int?)
                        ForEach(item.weightUnits, id: \.id) { unit in
                            Text(unit.name).tag(Optional(unit.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("diary-edit-unit")
                }

                Section("Before saving") {
                    LabeledContent("Gram equivalent") {
                        Text(gramDescription)
                            .accessibilityIdentifier("diary-edit-grams")
                    }
                    LabeledContent("Energy") {
                        Text(energyDescription)
                            .accessibilityIdentifier("diary-edit-energy")
                    }
                }

                Section("When and where") {
                    DatePicker(
                        "Date and time",
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("diary-edit-date-time")

                    Picker("Meal", selection: $mealID) {
                        Text("No meal").tag(nil as String?)
                        ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                            Text(mealTitle(meal, index: index)).tag(Optional(meal.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("diary-edit-meal")
                }

                if !amount.isEmpty, normalizedAmount == nil {
                    Section {
                        Text("Enter a positive amount with at most two decimal places.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit \(item.name)")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let normalizedAmount else { return }
                        isSaving = true
                        Task {
                            if await save(normalizedAmount, weightUnitID, date, mealID) {
                                dismiss()
                            } else {
                                isSaving = false
                            }
                        }
                    }
                    .disabled(normalizedAmount == nil || isSaving)
                    .accessibilityIdentifier("save-diary-entry")
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
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

    private var grams: Decimal? {
        guard let normalizedAmount,
            let amount = Decimal(
                string: normalizedAmount,
                locale: Locale(identifier: "en_US_POSIX")
            )
        else { return nil }
        let unitGrams = item.weightUnits.first { $0.id == weightUnitID }?.grams ?? 1
        return amount * Decimal(unitGrams)
    }

    private var gramDescription: String {
        guard let grams else { return "—" }
        return "\(grams.formatted(.number.precision(.fractionLength(0...2)))) g"
    }

    private var energyDescription: String {
        guard let grams else { return "—" }
        let energy = item.nutritionPer100Grams.scaled(toGrams: grams).energy
        return "\(energy.formatted(.number.precision(.fractionLength(0...1)))) kcal"
    }

    private func mealTitle(_ meal: DiaryMeal, index: Int) -> String {
        let name = meal.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name! : "Meal \(index + 1)"
    }
}

private struct NutritionSummary: View {
    let totals: NutritionTotals
    let goal: NutritionGoalState

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Daily progress")
                    .font(.headline)
                Spacer()
                Text(goalDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nutrition-goal-source")
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                nutrient("Energy", value: totals.energy, target: targets?.energy, unit: "kcal")
                nutrient("Protein", value: totals.protein, target: targets?.protein, unit: "g")
                nutrient(
                    "Carbs",
                    value: totals.carbohydrates,
                    target: targets?.carbohydrates,
                    unit: "g"
                )
                nutrient("Fat", value: totals.fat, target: targets?.fat, unit: "g")
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.vertical, 6)
        .accessibilityIdentifier("nutrition-summary")
    }

    private var targets: NutritionTargets? {
        guard case .available(let targets, _) = goal else { return nil }
        return targets
    }

    private var goalDescription: String {
        switch goal {
        case .missingPlan:
            "No nutrition plan"
        case .available(_, .configured):
            "Configured goals"
        case .available(_, .plannedMeals):
            "Planned meals"
        case .unavailable:
            "Targets unavailable"
        }
    }

    private func nutrient(
        _ name: String,
        value: Decimal,
        target: Decimal?,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(name)
                    .font(.caption.weight(.medium))
                Spacer(minLength: 4)
                Text(value, format: .number.precision(.fractionLength(0...1)))
                    .font(.caption.monospacedDigit())
                if let target {
                    Text("/ \(target.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: progress(value: value, target: target))
                .tint(progressTint(value: value, target: target))
            Text(status(value: value, target: target, unit: unit))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("nutrition-goal-\(name.lowercased())")
        .accessibilityLabel(
            "\(name), \(value.formatted()) \(unit), \(status(value: value, target: target, unit: unit))"
        )
    }

    private func progress(value: Decimal, target: Decimal?) -> Double {
        guard let target else { return 0 }
        guard target > 0 else { return value > 0 ? 1 : 0 }
        return min(1, NSDecimalNumber(decimal: value / target).doubleValue)
    }

    private func progressTint(value: Decimal, target: Decimal?) -> Color {
        guard let target, value > target else { return .accentColor }
        return .orange
    }

    private func status(value: Decimal, target: Decimal?, unit: String) -> String {
        guard let target else { return "No target set" }
        let difference = target - value
        if difference >= 0 {
            return
                "\(difference.formatted(.number.precision(.fractionLength(0...1)))) \(unit) remaining"
        }
        return "\((-difference).formatted(.number.precision(.fractionLength(0...1)))) \(unit) over"
    }
}

private struct DiaryItemRow: View {
    let item: DiaryItem
    let isDeleting: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.medium))
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(amountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDeleting {
                ProgressView()
                    .accessibilityLabel("Deleting \(item.name)")
            } else {
                Text(
                    "\(item.nutrition.energy.formatted(.number.precision(.fractionLength(0)))) kcal"
                )
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("diary-item-\(item.id)")
    }

    private var amountDescription: String {
        if let unitName = item.unitName {
            return "\(item.loggedAmount.formatted()) \(unitName) · \(item.grams.formatted()) g"
        }
        return "\(item.grams.formatted()) g"
    }
}

import Foundation
import SwiftUI

struct DailyDiaryView: View {
    @Bindable var model: DiaryScreenModel
    let instanceName: String
    let signOut: () -> Void
    @State private var pendingDeletion: DiaryItem?
    @State private var pendingEdit: DiaryItem?

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
        .confirmationDialog(
            "Delete \(pendingDeletion?.name ?? "entry")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
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
            DiaryAmountEditor(item: item) { amount, weightUnitID in
                guard let id = item.remoteID else { return false }
                return await model.updateEntryAmount(
                    id: id,
                    amount: amount,
                    weightUnitID: weightUnitID
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
        if diary.sections.isEmpty {
            ContentUnavailableView(
                "Nothing logged",
                systemImage: "fork.knife",
                description: Text("This day has no nutrition diary entries.")
            )
        } else {
            List {
                Section {
                    NutritionSummary(totals: diary.totals)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                ForEach(Array(diary.sections.enumerated()), id: \.element.id) { index, section in
                    Section(sectionTitle(section, index: index, sections: diary.sections)) {
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
                                    Button("Delete", role: .destructive) {
                                        pendingDeletion = item
                                    }
                                    .accessibilityIdentifier("delete-diary-item-\(remoteID)")
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
    }

    private func sectionTitle(
        _ section: DiarySection,
        index: Int,
        sections: [DiarySection]
    ) -> String {
        switch section.id {
        case .meal:
            let number = sections.prefix(index + 1).reduce(0) { count, section in
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

private struct DiaryAmountEditor: View {
    let item: DiaryItem
    let save: (String, Int?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    @State private var weightUnitID: Int?
    @State private var isSaving = false

    init(
        item: DiaryItem,
        save: @escaping (String, Int?) async -> Bool
    ) {
        self.item = item
        self.save = save
        _amount = State(initialValue: NSDecimalNumber(decimal: item.loggedAmount).stringValue)
        _weightUnitID = State(initialValue: item.weightUnitID)
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
                            if await save(normalizedAmount, weightUnitID) {
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
}

private struct NutritionSummary: View {
    let totals: NutritionTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily total")
                .font(.headline)
            HStack(spacing: 0) {
                nutrient("Energy", value: totals.energy, unit: "kcal")
                nutrient("Protein", value: totals.protein, unit: "g")
                nutrient("Carbs", value: totals.carbohydrates, unit: "g")
                nutrient("Fat", value: totals.fat, unit: "g")
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.vertical, 6)
        .accessibilityIdentifier("nutrition-summary")
    }

    private func nutrient(_ name: String, value: Decimal, unit: String) -> some View {
        VStack(spacing: 3) {
            Text(value, format: .number.precision(.fractionLength(0...1)))
                .font(.headline.monospacedDigit())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(value.formatted()) \(unit)")
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

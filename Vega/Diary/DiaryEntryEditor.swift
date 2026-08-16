import Foundation
import SwiftUI

struct DiaryEntryEditor: View {
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

import Foundation
import SwiftUI

struct DailyDiaryView: View {
    @Bindable var model: DiaryScreenModel
    let instanceName: String
    let signOut: () -> Void

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
        if diary.meals.isEmpty {
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

                ForEach(Array(diary.meals.enumerated()), id: \.element.id) { index, meal in
                    Section(mealTitle(meal, index: index)) {
                        ForEach(meal.items) { item in
                            DiaryItemRow(item: item)
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

    private func mealTitle(_ meal: DiaryMeal, index: Int) -> String {
        switch meal.id {
        case .meal:
            return "Meal \(index + 1)"
        case .unassigned:
            return "Other"
        }
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
            Text("\(item.nutrition.energy.formatted(.number.precision(.fractionLength(0)))) kcal")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
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

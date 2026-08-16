import Foundation
import SwiftUI

struct DailyDiaryView: View {
    @Bindable var model: DiaryScreenModel
    let instanceName: String
    let syncModel: SyncStatusModel?
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
                AccountMenu(
                    instanceName: instanceName,
                    syncModel: syncModel,
                    signOut: signOut
                )
            }
        }
        .task(id: model.selectedDate) {
            await model.observe()
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

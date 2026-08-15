import Charts
import SwiftUI

struct WeightHistoryView: View {
    @Bindable var model: WeightHistoryModel
    let instanceName: String
    let syncModel: SyncStatusModel?
    let signOut: () -> Void

    @State private var showsCreator = false
    @State private var editingEntry: WgerWeightEntry?
    @State private var pendingDeletion: WgerWeightEntry?

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView("Loading weight history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t load weight", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await model.load() } }
                }
            case .loaded:
                history
            }
        }
        .navigationTitle("Weight")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add weight", systemImage: "plus") { showsCreator = true }
                    .accessibilityIdentifier("add-weight-entry")
            }
            ToolbarItem(placement: .topBarTrailing) {
                AccountMenu(
                    instanceName: instanceName,
                    syncModel: syncModel,
                    signOut: signOut
                )
            }
        }
        .task { await model.observe() }
        .refreshable { await model.load() }
        .sheet(isPresented: $showsCreator) {
            WeightEntryForm(
                title: "Add weight",
                entry: nil,
                initialDate: model.suggestedDate
            ) { date, weight in
                let didCreate = await model.create(date: date, weight: weight)
                if didCreate { showsCreator = false }
                return didCreate
            }
        }
        .sheet(item: $editingEntry) { entry in
            WeightEntryForm(
                title: "Edit weight",
                entry: entry,
                initialDate: model.suggestedDate
            ) { date, weight in
                let didUpdate = await model.update(id: entry.id, date: date, weight: weight)
                if didUpdate { editingEntry = nil }
                return didUpdate
            }
        }
        .alert(
            "Delete weight entry?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button("Delete entry", role: .destructive) {
                guard let entry = pendingDeletion else { return }
                pendingDeletion = nil
                Task { await model.delete(id: entry.id) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This permanently removes the measurement from your weight history.")
        }
        .alert(
            "Couldn’t change weight",
            isPresented: Binding(
                get: { model.mutationErrorMessage != nil },
                set: { if !$0 { model.mutationErrorMessage = nil } }
            )
        ) {
            Button("OK") { model.mutationErrorMessage = nil }
        } message: {
            Text(model.mutationErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var history: some View {
        if let latest = model.latestEntry {
            List {
                Section {
                    latestCard(latest)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Trend") {
                    Picker("Time range", selection: $model.selectedRange) {
                        ForEach(WeightRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("weight-range")

                    if model.rangedEntries.isEmpty {
                        ContentUnavailableView(
                            "No measurements",
                            systemImage: "chart.xyaxis.line",
                            description: Text("There are no entries in this time range.")
                        )
                    } else {
                        weightChart
                            .frame(height: 220)
                            .padding(.vertical, 8)
                            .accessibilityIdentifier("weight-chart")
                    }
                }

                Section("History") {
                    ForEach(model.entries) { entry in
                        Button {
                            editingEntry = entry
                        } label: {
                            WeightEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("weight-entry-\(entry.id)")
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDeletion = entry
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("weight-history")
        } else {
            ContentUnavailableView {
                Label("No weight entries", systemImage: "scalemass")
            } description: {
                Text("Add your first measurement to start a trend.")
            } actions: {
                Button("Add weight") { showsCreator = true }
            }
        }
    }

    private func latestCard(_ entry: WgerWeightEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.weightText(entry.weight))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                Text("kg")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                if let change = model.changeInRange {
                    Label(
                        "\(Self.signedWeightText(change)) kg",
                        systemImage: change <= 0 ? "arrow.down.right" : "arrow.up.right"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(change <= 0 ? .green : .orange)
                }
            }
            Text(entry.date, format: .dateTime.weekday().day().month().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("latest-weight")
    }

    private var weightChart: some View {
        Chart {
            ForEach(model.rangedEntries) { entry in
                PointMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", Self.double(entry.weight))
                )
                .foregroundStyle(.secondary.opacity(0.45))
                .symbolSize(24)
            }

            ForEach(model.sevenDayTrend) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("7-day average", Self.double(point.average))
                )
                .foregroundStyle(.tint)
                .lineStyle(StrokeStyle(lineWidth: 3))
            }
        }
        .chartYScale(domain: chartYDomain)
        .chartYAxisLabel("kg")
    }

    private var chartYDomain: ClosedRange<Double> {
        let weights =
            model.rangedEntries.map { Self.double($0.weight) }
            + model.sevenDayTrend.map { Self.double($0.average) }
        guard let minimum = weights.min(), let maximum = weights.max() else { return 0...1 }
        let padding = max((maximum - minimum) * 0.15, 0.5)
        return (minimum - padding)...(maximum + padding)
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    static func weightText(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    private static func signedWeightText(_ value: Decimal) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + weightText(value)
    }
}

private struct WeightEntryRow: View {
    let entry: WgerWeightEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .foregroundStyle(.primary)
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(WeightHistoryView.weightText(entry.weight)) kg")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }
}

private struct WeightEntryForm: View {
    let title: String
    let entry: WgerWeightEntry?
    let save: (Date, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var weight: String
    @State private var isSaving = false

    init(
        title: String,
        entry: WgerWeightEntry?,
        initialDate: Date,
        save: @escaping (Date, String) async -> Bool
    ) {
        self.title = title
        self.entry = entry
        self.save = save
        _date = State(initialValue: entry?.date ?? initialDate)
        _weight = State(
            initialValue: entry.map { WeightHistoryView.weightText($0.weight) } ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Weight", text: $weight)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("weight-input")
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("Date and time", selection: $date)
                        .accessibilityIdentifier("weight-date")
                } header: {
                    Text("Measurement")
                } footer: {
                    if !weight.isEmpty, WeightInput.normalized(weight) == nil {
                        Text("Enter a weight from 30 to 600 kg with up to two decimals.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            _ = await save(date, weight)
                            isSaving = false
                        }
                    }
                    .disabled(WeightInput.normalized(weight) == nil || isSaving)
                    .accessibilityIdentifier("save-weight-entry")
                }
            }
            .overlay {
                if isSaving { ProgressView("Saving…") }
            }
        }
    }
}

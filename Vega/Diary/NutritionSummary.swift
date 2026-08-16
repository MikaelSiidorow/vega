import SwiftUI

struct NutritionSummary: View {
    let totals: NutritionTotals
    let goal: NutritionGoalState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: VegaSpacing.comfortable) {
            HStack(alignment: .firstTextBaseline) {
                Text("Daily progress")
                    .font(.title3.weight(.bold))
                Spacer()
                if let goalDescription {
                    Text(goalDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("nutrition-goal-source")
                }
            }

            energySummary

            Divider()

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: VegaSpacing.comfortable) {
                    macroSummaries
                }
            } else {
                HStack(alignment: .top, spacing: VegaSpacing.standard) {
                    macroSummaries
                }
            }
        }
        .vegaCard(padding: VegaSpacing.comfortable)
        .padding(.vertical, 6)
        .accessibilityIdentifier("nutrition-summary")
    }

    private var energySummary: some View {
        let target = targets?.energy
        let difference = target.map { $0 - totals.energy }
        let displayValue = difference.map { abs($0) } ?? totals.energy

        return VStack(alignment: .leading, spacing: VegaSpacing.small) {
            Text(energyTitle(difference: difference))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: VegaSpacing.small) {
                Text(displayValue, format: .number.precision(.fractionLength(0...1)))
                    .font(.largeTitle.bold().monospacedDigit())
                Text("kcal")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let target {
                VegaProgressBar(
                    value: progress(value: totals.energy, target: target),
                    tint: progressTint(value: totals.energy, target: target),
                    height: 10
                )

                HStack {
                    Text(
                        "\(totals.energy.formatted(.number.precision(.fractionLength(0...1)))) consumed"
                    )
                    Spacer()
                    Text(
                        "\(target.formatted(.number.precision(.fractionLength(0...1)))) goal"
                    )
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("nutrition-goal-energy")
        .accessibilityLabel(energyAccessibilityLabel(target: target))
    }

    @ViewBuilder private var macroSummaries: some View {
        macro("Protein", value: totals.protein, target: targets?.protein)
        macro("Carbs", value: totals.carbohydrates, target: targets?.carbohydrates)
        macro("Fat", value: totals.fat, target: targets?.fat)
    }

    private var targets: NutritionTargets? {
        guard case .available(let targets, _) = goal else { return nil }
        return targets
    }

    private var goalDescription: String? {
        switch goal {
        case .missingPlan:
            "No nutrition plan"
        case .available(_, .configured):
            nil
        case .available(_, .plannedMeals):
            "Planned meal targets"
        case .unavailable:
            "Targets unavailable"
        }
    }

    private func macro(
        _ name: String,
        value: Decimal,
        target: Decimal?
    ) -> some View {
        VStack(alignment: .leading, spacing: VegaSpacing.small) {
            Text(name)
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .firstTextBaseline, spacing: VegaSpacing.compact) {
                Text(value, format: .number.precision(.fractionLength(0...1)))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("g")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let target {
                Text("of \(target.formatted(.number.precision(.fractionLength(0...1)))) g")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                VegaProgressBar(
                    value: progress(value: value, target: target),
                    tint: progressTint(value: value, target: target),
                    height: 6
                )
            } else {
                Text("No target")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("nutrition-goal-\(name.lowercased())")
        .accessibilityLabel(
            "\(name), \(value.formatted()) grams, \(status(value: value, target: target, unit: "grams"))"
        )
    }

    private func energyTitle(difference: Decimal?) -> String {
        guard let difference else { return "Calories logged" }
        return difference >= 0 ? "Calories remaining" : "Calories over target"
    }

    private func energyAccessibilityLabel(target: Decimal?) -> String {
        guard let target else { return "Calories, \(totals.energy.formatted()) logged" }
        return
            "Calories, \(totals.energy.formatted()) consumed, \(status(value: totals.energy, target: target, unit: "kilocalories"))"
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

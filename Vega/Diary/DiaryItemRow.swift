import SwiftUI

struct DiaryItemRow: View {
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

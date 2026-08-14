import SwiftUI

enum VegaSpacing {
    static let compact: CGFloat = 4
    static let small: CGFloat = 8
    static let standard: CGFloat = 12
    static let comfortable: CGFloat = 16
    static let spacious: CGFloat = 24
}

enum VegaRadius {
    static let card: CGFloat = 24
}

struct VegaProgressBar: View {
    let value: Double
    var tint: Color = .accentColor
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geometry.size.width) * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

private struct VegaCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: VegaRadius.card, style: .continuous)
            )
    }
}

extension View {
    func vegaCard(padding: CGFloat = VegaSpacing.comfortable) -> some View {
        modifier(VegaCardModifier(padding: padding))
    }
}

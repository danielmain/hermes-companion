import SwiftUI

struct MetricTileView: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String

    init(
        title: String,
        value: String,
        subtitle: String? = nil,
        icon: String,
        color: Color = EditorialColor.ink
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.compact) {
            HStack {
                Image(systemName: icon)
                    .font(.body.weight(.light))
                    .accessibilityHidden(true)
                Spacer()
                Text(title)
                    .font(.editorialUtilitySmall)
                    .tracking(0.5)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }

            Text(value)
                .font(.editorialNumber)
                .foregroundStyle(EditorialColor.ink)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .editorialPanel()
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }
}


#Preview {
    LazyVGrid(
        columns: [
            GridItem(.flexible(), spacing: EditorialSpacing.compact),
            GridItem(.flexible(), spacing: EditorialSpacing.compact)
        ],
        spacing: EditorialSpacing.compact
    ) {
        MetricTileView(title: "TRANSMITTED", value: "50", subtitle: "950 queued", icon: "arrow.up.doc")
        MetricTileView(title: "CLOSED WAKES", value: "0", subtitle: "Terminated-state events", icon: "bolt")
        MetricTileView(title: "GPS ACCURACY", value: "±2.6m", subtitle: "Horizontal radius", icon: "scope")
        MetricTileView(title: "TRACKING", value: "Active", subtitle: "CoreLocation Engine", icon: "location")
    }
    .padding(EditorialSpacing.page)
    .background(EditorialColor.paper)
}

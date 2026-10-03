import SwiftUI

struct LocationRowView: View {
    let record: LocationRecord

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: EditorialSpacing.compact) {
                sourceMark
                recordCopy
                Spacer(minLength: EditorialSpacing.medium)
                timestamp
            }

            VStack(alignment: .leading, spacing: EditorialSpacing.compact) {
                HStack {
                    sourceMark
                    Spacer()
                    timestamp
                }
                recordCopy
            }
        }
        .padding(EditorialSpacing.medium)
        .foregroundStyle(EditorialColor.ink)
        .background(EditorialColor.paper)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var sourceMark: some View {
        Image(systemName: record.source.systemIcon)
            .font(.body.weight(.light))
            .frame(width: 36, height: 36)
            .overlay {
                Rectangle().stroke(EditorialColor.ink, lineWidth: EditorialBorder.hairline)
            }
            .accessibilityHidden(true)
    }

    private var recordCopy: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            HStack(spacing: EditorialSpacing.small) {
                Text(record.source.rawValue.uppercased())
                    .font(.editorialUtility)
                if record.source == .wakeFromTerminated {
                    EditorialStatusToken(text: "CLOSED WAKE", isInverted: true)
                }
            }

            Text("\(record.latitude, format: .number.precision(.fractionLength(4))), \(record.longitude, format: .number.precision(.fractionLength(4)))")
                .font(.system(.callout, design: .monospaced, weight: .regular))
                .foregroundStyle(EditorialColor.secondaryInk)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: EditorialSpacing.compact) {
                    metadata
                }
                VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                    metadata
                }
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        Label(record.formattedAccuracy, systemImage: "scope")
        if record.synced {
            Label("Filed", systemImage: "checkmark")
        }
    }

    private var timestamp: some View {
        Text(record.timestamp, format: .dateTime.hour().minute().second())
            .font(.editorialUtilitySmall)
            .foregroundStyle(EditorialColor.secondaryInk)
    }

    private var accessibilitySummary: String {
        let syncState = record.synced ? "filed" : "queued"
        return "\(record.source.rawValue), \(record.formattedAccuracy), \(syncState)"
    }
}

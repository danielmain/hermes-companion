import SwiftUI

struct StatusCardView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.large) {
            EditorialSectionHeader(index: "#00", title: "ACTIVE SESSION", trailing: trackingCode)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: EditorialSpacing.medium) {
                    statusCopy
                    Spacer(minLength: EditorialSpacing.medium)
                    trackingButton
                        .frame(maxWidth: 150)
                }

                VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
                    statusCopy
                    trackingButton
                }
            }

            EditorialRule()

            if let record = locationManager.latestRecord {
                CoordinateReadout(record: record, copied: copied, copyAction: copyCoordinates)
            } else {
                HStack(alignment: .top, spacing: EditorialSpacing.compact) {
                    Image(systemName: "location.slash")
                        .font(.title3.weight(.ultraLight))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                        Text("AWAITING FIRST FIX")
                            .font(.editorialUtility)
                        Text("Request a reading or wait for the receiver to establish a location.")
                            .font(.body)
                            .foregroundStyle(EditorialColor.secondaryInk)
                    }
                }
            }

            Button {
                locationManager.requestSingleLocationUpdate(source: .manualPing)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("REQUEST READING", systemImage: "arrow.clockwise")
            }
            .buttonStyle(EditorialButtonStyle(isPrimary: false))
        }
        .foregroundStyle(EditorialColor.ink)
        .editorialPanel(emphasized: true, cutCorner: true)
    }

    private var statusCopy: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            Text(statusTitle)
                .font(.editorialTitle)
                .foregroundStyle(EditorialColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(statusSubtitle)
                .font(.body)
                .foregroundStyle(EditorialColor.secondaryInk)
        }
    }

    private var trackingButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : EditorialMotion.quick) {
                locationManager.toggleTracking()
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Label(locationManager.isTrackingActive ? "PAUSE TRACKING" : "START TRACKING",
                  systemImage: locationManager.isTrackingActive ? "pause" : "play")
        }
        .buttonStyle(EditorialButtonStyle(isPrimary: !locationManager.isTrackingActive))
    }

    private var trackingCode: String {
        locationManager.isTrackingActive ? "RUNNING" : "PAUSED"
    }

    private var statusTitle: String {
        if !locationManager.isAuthorized {
            return "Permission required"
        }
        return locationManager.isTrackingActive ? "Receiver online" : "Receiver paused"
    }

    private var statusSubtitle: String {
        if !locationManager.isAuthorized {
            return "Always location access is required for unattended readings."
        }
        if locationManager.isTrackingActive {
            return locationManager.isAlwaysAuthorized ? "The field unit can observe movement after the app closes." : "Readings are limited to foreground use."
        }
        return "The archive is intact; new location readings are suspended."
    }

    private func copyCoordinates() {
        guard let record = locationManager.latestRecord else { return }
        UIPasteboard.general.string = "\(record.latitude), \(record.longitude)"
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        withAnimation(reduceMotion ? nil : EditorialMotion.quick) {
            copied = true
        }

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(reduceMotion ? nil : EditorialMotion.quick) {
                copied = false
            }
        }
    }
}

private struct CoordinateReadout: View {
    let record: LocationRecord
    let copied: Bool
    let copyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    coordinateCopy
                    Spacer(minLength: EditorialSpacing.medium)
                    copyButton
                }

                VStack(alignment: .leading, spacing: EditorialSpacing.compact) {
                    coordinateCopy
                    copyButton
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: EditorialSpacing.small) {
                    tokens
                }

                VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                    tokens
                }
            }
        }
    }

    private var coordinateCopy: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
            Text("CURRENT COORDINATES")
                .font(.editorialUtilitySmall)
                .foregroundStyle(EditorialColor.secondaryInk)
            Text("\(record.latitude, format: .number.precision(.fractionLength(5))), \(record.longitude, format: .number.precision(.fractionLength(5)))")
                .font(.system(.title3, design: .monospaced, weight: .regular))
                .foregroundStyle(EditorialColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var copyButton: some View {
        Button(action: copyAction) {
            Label(copied ? "COPIED" : "COPY", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(EditorialButtonStyle(isPrimary: false))
        .frame(maxWidth: 130)
    }

    @ViewBuilder
    private var tokens: some View {
        EditorialStatusToken(text: record.source.rawValue.uppercased(), isInverted: true, systemImage: record.source.systemIcon)
        EditorialStatusToken(text: record.formattedAccuracy.uppercased(), isInverted: false, systemImage: "scope")
        EditorialStatusToken(text: record.appState.uppercased(), isInverted: false, systemImage: "iphone")
    }
}

import SwiftUI

struct StatusCardView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @State private var copied: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            // Header Row: Status and Master Toggle
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.2))
                            .frame(width: 34, height: 34)
                        Circle()
                            .fill(statusColor)
                            .frame(width: 14, height: 14)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        Text(statusSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        locationManager.toggleTracking()
                    }
                }) {
                    Text(locationManager.isTrackingActive ? "Pause" : "Start")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(locationManager.isTrackingActive ? .red : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            locationManager.isTrackingActive
                                ? Color.red.opacity(0.12)
                                : Color.accentColor
                        )
                        .clipShape(Capsule())
                }
            }

            Divider()

            // Coordinates Row
            if let rec = locationManager.latestRecord {
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CURRENT COORDINATES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            Text("\(String(format: "%.5f", rec.latitude)), \(String(format: "%.5f", rec.longitude))")
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        Button(action: copyCoordinates) {
                            HStack(spacing: 4) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.caption2)
                                Text(copied ? "Copied" : "Copy")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(UIColor.tertiarySystemFill))
                            .clipShape(Capsule())
                        }
                    }

                    // Source and Accuracy Badges
                    HStack(spacing: 8) {
                        Label(rec.source.rawValue, systemImage: rec.source.systemIcon)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Label(rec.formattedAccuracy, systemImage: "scope")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundColor(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Label(rec.appState, systemImage: "iphone")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.12))
                            .foregroundColor(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Spacer()
                    }
                }
            } else {
                HStack {
                    Image(systemName: "location.slash")
                        .foregroundColor(.secondary)
                    Text("No location fix yet. Tap 'Ping Now' or wait for GPS lock.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Sub-bar with Always Mode badges and One-shot ping
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(locationManager.isSignificantMonitoringActive ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                    Text("Significant Changes: Active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    locationManager.requestSingleLocationUpdate(source: .manualPing)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                        Text("Ping Now")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.accentColor)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
        )
    }

    private var statusColor: Color {
        guard locationManager.isAuthorized else { return .orange }
        return locationManager.isTrackingActive ? .green : .gray
    }

    private var statusTitle: String {
        if !locationManager.isAuthorized {
            return "Permission Required"
        }
        return locationManager.isTrackingActive ? "Tracking Active" : "Tracking Paused"
    }

    private var statusSubtitle: String {
        if !locationManager.isAuthorized {
            return "Requires Always location"
        }
        if locationManager.isTrackingActive {
            return locationManager.isAlwaysAuthorized ? "Always-On (Even When Closed)" : "When In Use Only"
        } else {
            return "Tap Start to resume"
        }
    }

    private func copyCoordinates() {
        guard let rec = locationManager.latestRecord else { return }
        UIPasteboard.general.string = "\(rec.latitude), \(rec.longitude)"
        withAnimation {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                copied = false
            }
        }
    }
}

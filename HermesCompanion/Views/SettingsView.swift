import SwiftUI
import CloudKit

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorialSpacing.section) {
                    EditorialPageHeader(
                        index: "HERMES / CONFIGURATION 03",
                        title: "System\nParameters",
                        subtitle: "Adjust the field unit, private archive, and background observation policy."
                    )

                    TransmissionSettingsSection()
                    CloudSettingsSection()
                    TrackingSettingsSection()
                    PermissionSettingsSection()
                    AboutSettingsSection()
                }
                .padding(.horizontal, EditorialSpacing.page)
                .padding(.top, EditorialSpacing.large)
                .padding(.bottom, EditorialSpacing.hero)
            }
            .background(EditorialColor.paper)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct TransmissionSettingsSection: View {
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#01", title: "TRANSMISSION", trailing: "PRIVATE PIPELINE")

            SettingsValueRow(label: "SYNC PIPELINE", value: "Apple iCloud", systemImage: "icloud")
            EditorialRule()
            EditorialToggleRow(
                title: "Auto-sync location updates",
                detail: "File new records in the private CloudKit archive.",
                isOn: $locationManager.configuration.autoSyncEnabled
            )
            EditorialRule()
            EditorialField(
                label: "DEVICE NAME",
                prompt: "iPhone Companion",
                text: $locationManager.configuration.deviceName
            )
        }
        .editorialPanel()
    }
}

private struct CloudSettingsSection: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager

    @State private var pingMessage: String?
    @State private var pingSucceeded = false
    @State private var isPinging = false

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#02", title: "ARCHIVE", trailing: "CLOUDKIT")

            SettingsValueRow(
                label: "ACCOUNT",
                value: cloudKitSyncManager.accountStatusDescription,
                systemImage: cloudKitSyncManager.accountStatus == .available ? "checkmark" : "exclamationmark"
            )

            if cloudKitSyncManager.accountStatus != .available {
                Button(action: cloudKitSyncManager.openSettingsForAccount) {
                    Label("OPEN ACCOUNT SETTINGS", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(EditorialButtonStyle(isPrimary: false))
            }

            EditorialField(
                label: "CONTAINER IDENTIFIER",
                prompt: TrackingConfiguration.defaultContainerIdentifier,
                text: $locationManager.configuration.cloudKitContainerIdentifier
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if isPinging {
                EditorialLoadingState(message: "TESTING PRIVATE ARCHIVE")
            } else if let pingMessage {
                if pingSucceeded {
                    HStack(alignment: .top, spacing: EditorialSpacing.compact) {
                        Image(systemName: "checkmark.square")
                            .accessibilityHidden(true)
                        Text(pingMessage)
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .editorialPanel()
                    .accessibilityElement(children: .combine)
                } else {
                    EditorialErrorState(message: pingMessage)
                }
            }

            Button(action: runCloudKitTest) {
                Label("TEST CLOUDKIT CONNECTION", systemImage: "network")
            }
            .buttonStyle(EditorialButtonStyle(isPrimary: true))
            .disabled(isPinging)

            if let lastSync = cloudKitSyncManager.lastSyncDate {
                Text("LAST FILED / \(lastSync.formatted(.dateTime.year().month().day().hour().minute()))")
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }
        }
        .editorialPanel(cutCorner: true)
    }

    private func runCloudKitTest() {
        isPinging = true
        pingMessage = nil

        cloudKitSyncManager.sendTestPing(config: locationManager.configuration) { success, message in
            isPinging = false
            pingSucceeded = success
            pingMessage = message
            UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        }
    }
}

private struct TrackingSettingsSection: View {
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.large) {
            EditorialSectionHeader(index: "#03", title: "OBSERVATION", trailing: "BACKGROUND")

            VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                Text("TRACKING PROFILE")
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)

                Picker("Tracking profile", selection: $locationManager.configuration.trackingMode) {
                    ForEach(TrackingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .tint(EditorialColor.ink)

                Text(locationManager.configuration.trackingMode.subtitle)
                    .font(.footnote)
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EditorialSpacing.compact)
            .overlay {
                Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
            }

            Button {
                locationManager.toggleTracking()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Label(
                    locationManager.isTrackingActive ? "PAUSE LOCATION TRACKING" : "START LOCATION TRACKING",
                    systemImage: locationManager.isTrackingActive ? "pause" : "play"
                )
            }
            .buttonStyle(EditorialButtonStyle(isPrimary: !locationManager.isTrackingActive))

            EditorialRule()

            EditorialToggleRow(
                title: "Dynamic stationary geofence",
                detail: "Deploy a monitored region while the device is stationary.",
                isOn: $locationManager.configuration.dynamicGeofenceEnabled
            )

            EditorialSlider(
                label: "GEOFENCE RADIUS",
                value: $locationManager.configuration.geofenceRadiusMeters,
                range: 50...500,
                step: 25,
                unit: "m"
            )

            EditorialSlider(
                label: "DISTANCE FILTER",
                value: $locationManager.configuration.distanceFilterMeters,
                range: TrackingConfiguration.distanceFilterSliderMinMeters...TrackingConfiguration.distanceFilterSliderMaxMeters,
                step: TrackingConfiguration.distanceFilterSliderStepMeters,
                unit: "m"
            )

            Text("Readings inside the distance filter are discarded unless motion evidence makes a larger displacement unambiguous.")
                .font(.footnote)
                .foregroundStyle(EditorialColor.secondaryInk)

            EditorialToggleRow(
                title: "Background indicator",
                detail: "Allow iOS to show that location is active.",
                isOn: $locationManager.configuration.backgroundIndicatorEnabled
            )
        }
        .editorialPanel()
    }
}

private struct PermissionSettingsSection: View {
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#04", title: "PERMISSIONS", trailing: "IOS")

            SettingsValueRow(
                label: "LOCATION",
                value: locationManager.authorizationStatusDescription,
                systemImage: locationManager.isAlwaysAuthorized ? "checkmark" : "exclamationmark"
            )

            Button(action: openSettings) {
                Label("OPEN IOS SETTINGS", systemImage: "gearshape")
            }
            .buttonStyle(EditorialButtonStyle(isPrimary: false))
        }
        .editorialPanel()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct AboutSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#05", title: "COLOPHON", trailing: "FIELD UNIT")

            SettingsValueRow(label: "VERSION", value: "1.1.0", systemImage: "number")
            EditorialRule()
            SettingsValueRow(label: "ARCHITECTURE", value: "CoreLocation / CloudKit / HealthKit", systemImage: "cpu")
            EditorialRule()
            Text("Your data is stored on this device and synced only to your private iCloud account. Hermes does not collect analytics or send logs to us. Apple provides crash reports only if you choose to share them with developers.")
                .font(.body)
                .foregroundStyle(EditorialColor.secondaryInk)
        }
        .editorialPanel(emphasized: true, cutCorner: true)
    }
}

private struct SettingsValueRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: EditorialSpacing.compact) {
                Label(label, systemImage: systemImage)
                    .font(.editorialUtilitySmall)
                Spacer(minLength: EditorialSpacing.medium)
                Text(value)
                    .font(.body)
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                Label(label, systemImage: systemImage)
                    .font(.editorialUtilitySmall)
                Text(value)
                    .font(.body)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EditorialToggleRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }
        }
        .tint(EditorialColor.ink)
        .frame(minHeight: 44)
    }
}



private struct EditorialSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            HStack {
                Text(label)
                    .font(.editorialUtilitySmall)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(.system(.body, design: .monospaced))
            }

            Slider(value: $value, in: range, step: step) {
                Text(label)
            } minimumValueLabel: {
                Text("\(Int(range.lowerBound))")
            } maximumValueLabel: {
                Text("\(Int(range.upperBound))")
            }
            .font(.caption)
            .tint(EditorialColor.ink)
        }
    }
}

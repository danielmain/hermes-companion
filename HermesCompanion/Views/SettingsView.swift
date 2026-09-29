import SwiftUI
import CloudKit

struct SettingsView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager

    // CloudKit Ping State
    @State private var cloudKitPingMessage: String?
    @State private var cloudKitPingSuccess: Bool = false
    @State private var isCloudKitPinging: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Transmission Destination & Preferences
                Section(
                    header: Text("Transmission Pipeline"),
                    footer: Text("Transmits location securely via your private Apple iCloud account directly to macOS Hermes. Zero open ports, zero TCP, works everywhere.")
                ) {
                    HStack {
                        Label("Sync Pipeline", systemImage: "icloud.fill")
                        Spacer()
                        Text("Apple iCloud")
                            .foregroundColor(.secondary)
                    }

                    Toggle("Auto-Sync Location Updates", isOn: $locationManager.configuration.autoSyncEnabled)

                    HStack {
                        Text("Device Name")
                            .frame(width: 95, alignment: .leading)
                        TextField("Name", text: $locationManager.configuration.deviceName)
                    }
                }

                // Section 2: Apple CloudKit Private DB & Ubiquity Container
                Section(
                    header: Text("Apple CloudKit & iCloud Drive"),
                    footer: Text("Stored securely in your private iCloud database and synced to your Mac's iCloud container. Seamlessly accessed by Hermes on macOS.")
                ) {
                    HStack {
                        Text("iCloud Account")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(cloudKitSyncManager.accountStatus == .available ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(cloudKitSyncManager.accountStatusDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    if cloudKitSyncManager.accountStatus != .available {
                        Button(action: { cloudKitSyncManager.openSettingsForAccount() }) {
                            HStack {
                                Label("Sign In to iCloud (Open Settings)", systemImage: "person.crop.circle.badge.plus")
                                Spacer()
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Container ID")
                                .frame(width: 95, alignment: .leading)
                            TextField("iCloud.com.hermes.HermesCompanion", text: $locationManager.configuration.cloudKitContainerIdentifier)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .font(.footnote)
                        }
                    }

                    Button(action: runCloudKitTestPing) {
                        HStack {
                            if isCloudKitPinging {
                                ProgressView()
                                    .padding(.trailing, 6)
                            } else {
                                Image(systemName: "icloud.and.arrow.up.fill")
                            }
                            Text("Test CloudKit Sync")
                                .fontWeight(.medium)
                        }
                    }
                    .disabled(isCloudKitPinging)

                    if let msg = cloudKitPingMessage {
                        HStack {
                            Image(systemName: cloudKitPingSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(cloudKitPingSuccess ? .green : .red)
                            Text(msg)
                                .font(.footnote)
                                .foregroundColor(cloudKitPingSuccess ? .green : .red)
                        }
                    }

                    if let lastSync = cloudKitSyncManager.lastSyncDate {
                        HStack {
                            Text("Last Synced")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastSync, style: .time)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Section 4: Always-On Location & Geofence Tuning
                Section(
                    header: Text("Closed Wake & Geofence Tuning"),
                    footer: Text("When stationary, a circular geofence is deployed. When you cross it, iOS wakes up the app even if closed or terminated.")
                ) {
                    Toggle("Dynamic Stationary Geofence", isOn: $locationManager.configuration.dynamicGeofenceEnabled)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Geofence Radius")
                            Spacer()
                            Text("\(Int(locationManager.configuration.geofenceRadiusMeters)) m")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $locationManager.configuration.geofenceRadiusMeters,
                            in: 50...500,
                            step: 25
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Standard Distance Filter")
                            Spacer()
                            Text("\(Int(locationManager.configuration.distanceFilterMeters)) m")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $locationManager.configuration.distanceFilterMeters,
                            in: 0...50,
                            step: 5
                        )
                    }

                    Toggle("Show Background Indicator Bar", isOn: $locationManager.configuration.backgroundIndicatorEnabled)
                }

                // Section 5: System Permissions
                Section(header: Text("iOS Permissions & Health")) {
                    HStack {
                        Text("Location Authorization")
                        Spacer()
                        Text(locationManager.authorizationStatusDescription)
                            .font(.subheadline)
                            .foregroundColor(locationManager.isAlwaysAuthorized ? .green : .orange)
                    }

                    Button(action: openSettings) {
                        HStack {
                            Label("Open iOS Settings", systemImage: "gearshape")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Section 6: About
                Section(header: Text("About Hermes Companion")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.1.0 (CloudKit Enabled)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Core Architecture")
                        Spacer()
                        Text("CoreLocation + CloudKit + Significant + Visits")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func runCloudKitTestPing() {
        isCloudKitPinging = true
        cloudKitPingMessage = nil

        cloudKitSyncManager.sendTestPing(config: locationManager.configuration) { success, message in
            isCloudKitPinging = false
            cloudKitPingSuccess = success
            cloudKitPingMessage = message
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

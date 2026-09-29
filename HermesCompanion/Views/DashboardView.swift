import SwiftUI
import CoreLocation

struct DashboardView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var locationStore: LocationStore
    @EnvironmentObject private var syncManager: SyncManager

    @State private var showingInfoModal: Bool = false
    @State private var showingApiGuide: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Permission Banner (if not Always)
                    PermissionBannerView()

                    // iCloud Account Sign-In Banner (if CloudKit enabled and not signed in)
                    ICloudAccountBannerView()

                    // Hermes Agent Connection Status Card
                    HermesConnectionStatusCard()

                    // Main Telemetry & Location Card
                    StatusCardView()

                    // Key Metric Tiles
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        MetricTileView(
                            title: "Sent to Hermes",
                            value: "\(locationStore.records.filter { $0.synced }.count)",
                            subtitle: "\(locationStore.records.filter { !$0.synced }.count) queued",
                            icon: "icloud.and.arrow.up",
                            color: .blue
                        )

                        MetricTileView(
                            title: "Closed Wakes",
                            value: "\(wakeCount)",
                            subtitle: "Woke from closed state",
                            icon: "bolt.fill",
                            color: .orange
                        )

                        MetricTileView(
                            title: "GPS Accuracy",
                            value: latestAccuracyString,
                            subtitle: "Horizontal radius",
                            icon: "scope",
                            color: .green
                        )

                        MetricTileView(
                            title: "Battery",
                            value: currentBatteryString,
                            subtitle: UIDevice.current.batteryState == .charging ? "Charging" : "Discharging",
                            icon: "battery.100",
                            color: .indigo
                        )
                    }

                    // Tracking Profile Picker
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("TRACKING & TRANSMISSION PROFILE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        ForEach(TrackingMode.allCases) { mode in
                            Button(action: {
                                withAnimation {
                                    locationManager.configuration.trackingMode = mode
                                }
                            }) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: locationManager.configuration.trackingMode == mode ? "largecircle.fill.circle" : "circle")
                                        .font(.title3)
                                        .foregroundColor(locationManager.configuration.trackingMode == mode ? .accentColor : .secondary)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mode.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)

                                        Text(mode.subtitle)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer()
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(locationManager.configuration.trackingMode == mode ? Color.accentColor.opacity(0.08) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)

                            if mode != TrackingMode.allCases.last {
                                Divider()
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )

                    // Recent Transmissions Preview
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("RECENT TRANSMISSIONS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()

                            NavigationLink(destination: HistoryLogView()) {
                                Text("View All")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                            }
                        }

                        if locationStore.records.isEmpty {
                            Text("No locations captured yet. Tap 'Ping Now' or move around.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 16)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(locationStore.records.prefix(3)) { record in
                                    LocationRowView(record: record)
                                    if record.id != locationStore.records.prefix(3).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )

                    // Help & Architecture Cards
                    VStack(spacing: 10) {
                        Button(action: { showingApiGuide = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "cpu")
                                    .foregroundColor(.purple)
                                Text("How Hermes Agent Fetches Your Location")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                            )
                        }

                        Button(action: { showingInfoModal = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.orange)
                                Text("How iOS Wakes the App When Completely Closed")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                            )
                        }
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Hermes Transmitter")
            .sheet(isPresented: $showingInfoModal) {
                ClosedTrackingInfoSheet()
            }
            .sheet(isPresented: $showingApiGuide) {
                HermesAgentGuideSheet()
            }
        }
    }

    private var wakeCount: Int {
        locationStore.records.filter { $0.source == .wakeFromTerminated }.count
    }

    private var latestAccuracyString: String {
        guard let rec = locationManager.latestRecord else { return "--" }
        return rec.formattedAccuracy
    }

    private var currentBatteryString: String {
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "100%" }
        return "\(Int(level * 100))%"
    }
}

// MARK: - Hermes Connection Status Card
struct HermesConnectionStatusCard: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var syncManager: SyncManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(connectionColor.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: connectionIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(connectionColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(connectionTitle)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(connectionSubtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if syncManager.isSyncing || cloudKitSyncManager.isSyncing {
                ProgressView()
                    .scaleEffect(0.85)
            } else if locationManager.configuration.syncDestination.isCloudKitEnabled && cloudKitSyncManager.accountStatus == .available {
                Text("iCloud")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            } else if let code = syncManager.lastHttpCode, (200...299).contains(code) {
                Text("HTTP \(code)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private var connectionColor: Color {
        guard locationManager.configuration.autoSyncEnabled else { return .secondary }
        let dest = locationManager.configuration.syncDestination
        if dest.isCloudKitEnabled && cloudKitSyncManager.accountStatus == .available {
            return .blue
        }
        if let code = syncManager.lastHttpCode, (200...299).contains(code) {
            return .green
        }
        return .indigo
    }

    private var connectionIcon: String {
        guard locationManager.configuration.autoSyncEnabled else { return "wifi.slash" }
        let dest = locationManager.configuration.syncDestination
        if dest.isCloudKitEnabled {
            return "icloud.fill"
        }
        if let code = syncManager.lastHttpCode, (200...299).contains(code) {
            return "checkmark.icloud.fill"
        }
        return "arrow.triangle.2.circlepath.circle.fill"
    }

    private var connectionTitle: String {
        if !locationManager.configuration.autoSyncEnabled {
            return "Hermes Sync Disabled"
        }
        if syncManager.isSyncing || cloudKitSyncManager.isSyncing {
            return "Transmitting to Hermes..."
        }
        switch locationManager.configuration.syncDestination {
        case .cloudKit:
            return cloudKitSyncManager.accountStatus == .available ? "CloudKit Private DB Ready" : "iCloud Setup Needed"
        case .httpWebhook:
            if let code = syncManager.lastHttpCode, (200...299).contains(code) {
                return "Hermes Relay Connected"
            }
            return "HTTP Webhook Ready"
        case .dual:
            return "Dual Pipeline Active"
        }
    }

    private var connectionSubtitle: String {
        if !locationManager.configuration.autoSyncEnabled {
            return "Enable in Hermes Config to upload locations"
        }

        let newestSync = [cloudKitSyncManager.lastSyncDate, syncManager.lastSyncDate].compactMap { $0 }.max()
        if let lastSync = newestSync {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Last sync " + formatter.localizedString(for: lastSync, relativeTo: Date())
        }

        switch locationManager.configuration.syncDestination {
        case .cloudKit:
            return cloudKitSyncManager.accountStatusDescription
        case .httpWebhook:
            return locationManager.configuration.serverURL
        case .dual:
            return "CloudKit + Webhook"
        }
    }
}

// MARK: - Hermes Agent Guide Sheet
struct HermesAgentGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How Hermes Agent Fetches Location")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Because iOS puts apps to sleep when closed, Hermes Agent reads your location through a high-speed relay endpoint or MCP tool:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        GuideStep(
                            number: "1",
                            title: "iOS App Transmits Coordinates",
                            desc: "Whenever you move, step out of a geofence, or trigger significant cell changes (even when closed), the app wakes up and POSTs your coordinates to the Hermes relay."
                        )

                        GuideStep(
                            number: "2",
                            title: "Relay Stores Latest Position in Cache/DB",
                            desc: "The relay immediately records the location, timestamp, speed, battery, and motion state in SQLite / memory."
                        )

                        GuideStep(
                            number: "3",
                            title: "Hermes Agent Calls `get_user_location`",
                            desc: "When Hermes needs your location (e.g. for travel advice, weather, scheduling, or presence), Hermes queries `GET /api/location/latest` or calls the bundled MCP tool."
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Endpoint (for Hermes Agent)")
                            .font(.headline)

                        Text("GET /api/location/latest")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("Response JSON:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("""
                        {
                          "latitude": 52.5200,
                          "longitude": 13.4050,
                          "accuracy_meters": 4.5,
                          "recorded_at": "2026-09-28T21:40:00Z",
                          "age_seconds": 15,
                          "battery_percent": 88,
                          "trigger": "Significant Change",
                          "app_state": "resumed_terminated"
                        }
                        """)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle("Hermes Integration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct GuideStep: View {
    let number: String
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(desc)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Closed Tracking Info Sheet
struct ClosedTrackingInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Continuous Tracking Architecture")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("iOS applies strict sandbox rules to apps. To guarantee location tracking even after you force-close the app or restart your phone, Hermes Companion combines 3 Apple-native services:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        TechCard(
                            title: "1. Significant Location Service",
                            badge: "Apple Native",
                            description: "Monitors mobile cell-tower changes (~500m movements). When triggered, iOS wakes the terminated app into the background, executes AppDelegate, and passes the location fix to be transmitted.",
                            icon: "antenna.radiowaves.left.and.right",
                            color: .orange
                        )

                        TechCard(
                            title: "2. Stationary Dynamic Geofencing",
                            badge: "Zero Drift",
                            description: "When you stay stationary for more than a minute, Hermes creates an invisible 100m circular perimeter. As soon as you walk or drive outside this perimeter, iOS immediately wakes up the app even if closed!",
                            icon: "circle.dashed.rectangle",
                            color: .mint
                        )

                        TechCard(
                            title: "3. Continuous Standard GPS",
                            badge: "High Precision",
                            description: "While traveling or while active in the background, standard high-precision GPS streams updates with distance filtering.",
                            icon: "location.fill",
                            color: .blue
                        )

                        TechCard(
                            title: "4. Visits & Places Service",
                            badge: "Arrivals & Departures",
                            description: "Uses iOS CoreLocation Visits to wake the app and log exact arrival and departure timestamps at frequent destinations.",
                            icon: "figure.walk.motion",
                            color: .purple
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Important Requirement")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Text("iOS will only wake up closed apps if you have granted 'Always' permission in Settings > Privacy & Security > Location Services > Hermes Companion. If set to 'While Using', Apple blocks wakeups.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.orange.opacity(0.1))
                    )
                }
                .padding()
            }
            .navigationTitle("Always-On Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TechCard: View {
    let title: String
    let badge: String
    let description: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.15))
                        .foregroundColor(color)
                        .clipShape(Capsule())
                }

                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }
}

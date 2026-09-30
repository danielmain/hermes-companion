import SwiftUI
import CoreLocation

struct DashboardView: View {
    @EnvironmentObject private var locationStore: LocationStore
    @State private var presentedDocument: DashboardDocument?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorialSpacing.section) {
                    EditorialPageHeader(
                        index: "HERMES / FIELD UNIT 01",
                        title: "Living\nTelemetry",
                        subtitle: "A private field instrument for location, health, and the signals your Mac can retrieve through iCloud."
                    )

                    VStack(spacing: EditorialSpacing.compact) {
                        PermissionBannerView()
                        ICloudAccountBannerView()
                    }

                    DashboardConnectionSection()
                    StatusCardView()
                    DashboardMetricsSection()
                    DashboardTrackingSection()
                    DashboardRecentSection(records: Array(locationStore.records.prefix(3)))
                    DashboardReferenceSection(presentedDocument: $presentedDocument)
                }
                .padding(.horizontal, EditorialSpacing.page)
                .padding(.top, EditorialSpacing.large)
                .padding(.bottom, EditorialSpacing.hero)
            }
            .background(EditorialColor.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $presentedDocument) { document in
                EditorialDocumentSheet(document: document)
            }
        }
    }
}

private struct DashboardConnectionSection: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#01", title: "CONNECT", trailing: "PRIVATE ICLOUD")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: EditorialSpacing.medium) {
                    connectionCopy
                    Spacer(minLength: EditorialSpacing.medium)
                    token
                }

                VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
                    connectionCopy
                    token
                }
            }
        }
        .editorialPanel(emphasized: true, cutCorner: true)
    }

    private var connectionCopy: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            Text(connectionTitle)
                .font(.editorialTitle)
                .foregroundStyle(EditorialColor.ink)
                .accessibilityAddTraits(.isHeader)

            Text(connectionSubtitle)
                .font(.body)
                .foregroundStyle(EditorialColor.secondaryInk)
        }
    }

    private var token: some View {
        EditorialStatusToken(
            text: cloudKitSyncManager.isSyncing ? "SYNCING" : statusLabel,
            isInverted: cloudKitSyncManager.accountStatus == .available,
            systemImage: cloudKitSyncManager.isSyncing ? "arrow.triangle.2.circlepath" : "icloud"
        )
    }

    private var statusLabel: String {
        if !locationManager.configuration.autoSyncEnabled {
            return "DISABLED"
        }
        return cloudKitSyncManager.accountStatus == .available ? "LINK READY" : "SETUP NEEDED"
    }

    private var connectionTitle: String {
        if !locationManager.configuration.autoSyncEnabled {
            return "Signal dormant"
        }
        return cloudKitSyncManager.accountStatus == .available ? "Archive linked" : "Link incomplete"
    }

    private var connectionSubtitle: String {
        if let lastSync = cloudKitSyncManager.lastSyncDate {
            return "Last transmission \(lastSync.formatted(.relative(presentation: .named)))"
        }
        return cloudKitSyncManager.accountStatusDescription
    }
}

private struct DashboardMetricsSection: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var locationStore: LocationStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#02", title: "OBSERVE", trailing: "LIVE MEASURES")

            LazyVGrid(columns: columns, alignment: .leading, spacing: EditorialSpacing.compact) {
                MetricTileView(
                    title: "TRANSMITTED",
                    value: locationStore.records.filter(\.synced).count.formatted(),
                    subtitle: "\(locationStore.records.filter { !$0.synced }.count.formatted()) queued",
                    icon: "arrow.up.doc"
                )
                MetricTileView(
                    title: "CLOSED WAKES",
                    value: locationStore.records.filter { $0.source == .wakeFromTerminated }.count.formatted(),
                    subtitle: "Terminated-state events",
                    icon: "bolt"
                )
                MetricTileView(
                    title: "GPS ACCURACY",
                    value: locationManager.latestRecord?.formattedAccuracy ?? "—",
                    subtitle: "Horizontal radius",
                    icon: "scope"
                )
                MetricTileView(
                    title: "BATTERY",
                    value: batteryLevel,
                    subtitle: UIDevice.current.batteryState == .charging ? "Charging" : "Discharging",
                    icon: "battery.75"
                )
            }
        }
    }

    private var batteryLevel: String {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? "—" : (level * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private var columns: [GridItem] {
        let count = prefersSingleColumn ? 1 : (horizontalSizeClass == .regular ? 3 : 2)
        return Array(
            repeating: GridItem(.flexible(), spacing: EditorialSpacing.compact),
            count: count
        )
    }

    private var prefersSingleColumn: Bool {
        switch dynamicTypeSize {
        case .xxLarge, .xxxLarge,
             .accessibility1, .accessibility2, .accessibility3,
             .accessibility4, .accessibility5:
            true
        default:
            false
        }
    }
}

private struct DashboardTrackingSection: View {
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#03", title: "AUTOMATE", trailing: "TRACKING PROFILE")

            VStack(spacing: 0) {
                ForEach(Array(TrackingMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    Button {
                        withAnimation(EditorialMotion.quick) {
                            locationManager.configuration.trackingMode = mode
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        TrackingModeRow(
                            index: index + 1,
                            title: mode.rawValue,
                            subtitle: mode.subtitle,
                            isSelected: locationManager.configuration.trackingMode == mode
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(locationManager.configuration.trackingMode == mode ? "Selected" : "Not selected")

                    if mode.id != TrackingMode.allCases.last?.id {
                        EditorialRule()
                    }
                }
            }
            .overlay {
                Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
            }
        }
    }
}

private struct TrackingModeRow: View {
    let index: Int
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: EditorialSpacing.compact) {
            Text(index.formatted(.number.precision(.integerLength(2))))
                .font(.editorialNumber)
                .foregroundStyle(isSelected ? EditorialColor.paper : EditorialColor.ink)
                .frame(minWidth: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? EditorialColor.paper.opacity(0.78) : EditorialColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: EditorialSpacing.small)

            Image(systemName: isSelected ? "square.inset.filled" : "square")
                .font(.body.weight(.light))
                .accessibilityHidden(true)
        }
        .foregroundStyle(isSelected ? EditorialColor.paper : EditorialColor.ink)
        .padding(EditorialSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(isSelected ? EditorialColor.ink : EditorialColor.paper)
        .contentShape(Rectangle())
    }
}

private struct DashboardRecentSection: View {
    let records: [LocationRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#04", title: "REMEMBER", trailing: "RECENT SIGNALS")

            if records.isEmpty {
                EditorialEmptyState(
                    index: "ARCHIVE / 000",
                    title: "Nothing yet",
                    message: "Move through the world or request a manual reading. The first signal will be filed here.",
                    systemImage: "location.slash"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(records) { record in
                        LocationRowView(record: record)
                        if record.id != records.last?.id {
                            EditorialRule()
                        }
                    }
                }
                .overlay {
                    Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
                }
            }

            NavigationLink {
                HistoryLogView()
            } label: {
                Label("OPEN COMPLETE ARCHIVE", systemImage: "arrow.right")
            }
            .buttonStyle(EditorialButtonStyle(isPrimary: false))
        }
    }
}

private struct DashboardReferenceSection: View {
    @Binding var presentedDocument: DashboardDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#05", title: "REFERENCE", trailing: "SYSTEM NOTES")

            VStack(spacing: 0) {
                referenceButton(
                    title: "How Hermes retrieves a signal",
                    code: "PIPELINE / 01",
                    icon: "cpu",
                    document: .pipeline
                )
                EditorialRule()
                referenceButton(
                    title: "How iOS wakes a closed field unit",
                    code: "WAKE / 02",
                    icon: "bolt",
                    document: .wake
                )
            }
            .overlay {
                Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
            }
        }
    }

    private func referenceButton(
        title: LocalizedStringKey,
        code: LocalizedStringKey,
        icon: String,
        document: DashboardDocument
    ) -> some View {
        Button {
            presentedDocument = document
        } label: {
            HStack(spacing: EditorialSpacing.compact) {
                Image(systemName: icon)
                    .font(.body.weight(.light))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                    Text(code)
                        .font(.editorialUtilitySmall)
                        .foregroundStyle(EditorialColor.secondaryInk)
                    Text(title)
                        .font(.body)
                        .foregroundStyle(EditorialColor.ink)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.light))
                    .accessibilityHidden(true)
            }
            .padding(EditorialSpacing.medium)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum DashboardDocument: String, Identifiable {
    case pipeline
    case wake

    var id: String { rawValue }

    var index: LocalizedStringKey {
        switch self {
        case .pipeline: "TECHNICAL NOTE / 01"
        case .wake: "TECHNICAL NOTE / 02"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .pipeline: "The private\npipeline"
        case .wake: "After the\napp closes"
        }
    }

    var body: LocalizedStringKey {
        switch self {
        case .pipeline:
            "The field unit writes encrypted records to your private CloudKit database. Hermes on macOS reads the same private container. No inbound port, public endpoint, or direct device connection is required."
        case .wake:
            "iOS can relaunch the app for significant location changes, visits, and monitored-region crossings. Delivery remains system-managed and depends on authorization, movement, and available device resources."
        }
    }
}

private struct EditorialDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let document: DashboardDocument

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorialSpacing.xLarge) {
                    EditorialPageHeader(
                        index: document.index,
                        title: document.title,
                        subtitle: "FIELD MANUAL / HERMES COMPANION"
                    )

                    Text(document.body)
                        .font(.body)
                        .foregroundStyle(EditorialColor.ink)
                        .lineSpacing(6)

                    EditorialRule()

                    Text("This reference describes the operating model; iOS remains the authority for background execution.")
                        .font(.editorialUtility)
                        .foregroundStyle(EditorialColor.secondaryInk)
                }
                .padding(EditorialSpacing.page)
            }
            .background(EditorialColor.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(EditorialIconButtonStyle())
                    .accessibilityLabel("Close reference")
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(LocationManager.shared)
        .environmentObject(LocationStore.shared)
        .environmentObject(CloudKitSyncManager.shared)
        .environmentObject(HealthKitManager.shared)
}

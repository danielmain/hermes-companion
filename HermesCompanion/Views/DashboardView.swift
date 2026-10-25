import SwiftUI

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: EditorialSpacing.section) {
                    DashboardHeroHeader()

                    HealthOverviewCard()

                    VStack(spacing: EditorialSpacing.compact) {
                        PermissionBannerView()
                        ICloudAccountBannerView()
                    }

                    DashboardLocationStatusSection()
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

private struct DashboardHeroHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.compact) {
            Image("LilithHeader")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 152)
                .clipShape(CutCornerShape(cut: 18))
                .overlay {
                    CutCornerShape(cut: 18)
                        .stroke(EditorialColor.ink, lineWidth: EditorialBorder.hairline)
                }
                .accessibilityHidden(true)

            Text("HERMES / TODAY")
                .font(.editorialUtility)
                .tracking(1.2)
                .foregroundStyle(EditorialColor.secondaryInk)
                .padding(.top, EditorialSpacing.xSmall)

            Text("Daily Overview")
                .font(.editorialTitle)
                .fontWeight(.regular)
                .foregroundStyle(EditorialColor.ink)
                .accessibilityAddTraits(.isHeader)

            EditorialRule(strong: true)

            Text("A private summary of your health, activity, and location context.")
                .font(.editorialBody)
                .foregroundStyle(EditorialColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, EditorialSpacing.xSmall)
        }
    }
}

private struct DashboardLocationStatusSection: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager
    @EnvironmentObject private var syncCoordinator: SyncCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(title: "LOCATION", trailing: "CONTEXT")

            VStack(spacing: 0) {
                DashboardStatusRow(
                    label: "TRACKING",
                    value: locationManager.isTrackingActive ? "Active" : "Paused",
                    systemImage: locationManager.isTrackingActive ? "location.fill" : "location.slash"
                )
                EditorialRule()
                DashboardStatusRow(
                    label: "LAST UPDATE",
                    value: lastUpdate,
                    systemImage: "clock"
                )
                EditorialRule()
                DashboardStatusRow(
                    label: "ACCURACY",
                    value: accuracyValue,
                    systemImage: "scope"
                )
                EditorialRule()
                DashboardStatusRow(
                    label: locationManager.configuration.syncDestination == .direct ? "DIRECT SYNC" : "PRIVATE SYNC",
                    value: syncStatus,
                    systemImage: syncIcon
                )
                if locationManager.configuration.syncDestination == .direct && syncCoordinator.directOfflineQueueCount > 0 {
                    EditorialRule()
                    DashboardStatusRow(
                        label: "OFFLINE QUEUE",
                        value: "\(syncCoordinator.directOfflineQueueCount) pending",
                        systemImage: "tray.full"
                    )
                }
            }
            .overlay {
                Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
            }

            NavigationLink(destination: HistoryLogView()) {
                HStack {
                    Label("VIEW LOCATION ARCHIVE", systemImage: "archivebox")
                        .font(.editorialUtilitySmall)
                        .foregroundStyle(EditorialColor.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.editorialUtilitySmall)
                        .foregroundStyle(EditorialColor.secondaryInk)
                }
                .padding(EditorialSpacing.compact)
                .background(EditorialColor.surface)
                .overlay {
                    Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
                }
            }
            .buttonStyle(PlainButtonStyle())

            Text("Tracking modes and background behavior are managed in Settings.")
                .font(.footnote)
                .foregroundStyle(EditorialColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .editorialPanel(cutCorner: true)
    }

    private var lastUpdate: String {
        if let date = locationManager.latestRecord?.timestamp {
            return date.formatted(.relative(presentation: .named))
        }
        if let date = locationManager.currentLocation?.timestamp {
            return date.formatted(.relative(presentation: .named))
        }
        return locationManager.isTrackingActive ? "Awaiting fix" : "Paused"
    }

    private var accuracyValue: String {
        if let accuracy = locationManager.latestRecord?.formattedAccuracy {
            return accuracy
        }
        if let current = locationManager.currentLocation {
            return "±\(Int(current.horizontalAccuracy)) m"
        }
        return locationManager.isTrackingActive ? "Acquiring..." : "Unavailable"
    }

    private var syncIcon: String {
        if locationManager.configuration.syncDestination == .direct {
            if syncCoordinator.isSyncing {
                return "arrow.triangle.2.circlepath"
            }
            return "bolt.horizontal.circle"
        } else {
            return cloudKitSyncManager.isSyncing ? "arrow.triangle.2.circlepath" : "icloud"
        }
    }

    private var syncStatus: String {
        if !locationManager.configuration.autoSyncEnabled {
            return "Disabled"
        }
        if locationManager.configuration.syncDestination == .direct {
            if syncCoordinator.isSyncing {
                return "Syncing"
            }
            if let latency = syncCoordinator.directLatencyMs {
                return "Online (\(Int(latency))ms)"
            }
            if let lastSync = syncCoordinator.lastSyncDate {
                return lastSync.formatted(.relative(presentation: .named))
            }
            return syncCoordinator.lastSyncStatus
        } else {
            if cloudKitSyncManager.isSyncing {
                return "Syncing"
            }
            if let lastSync = cloudKitSyncManager.lastSyncDate {
                return lastSync.formatted(.relative(presentation: .named))
            }
            return cloudKitSyncManager.accountStatusDescription
        }
    }
}

private struct DashboardStatusRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EditorialSpacing.compact) {
            Label(label, systemImage: systemImage)
                .font(.editorialUtilitySmall)
                .foregroundStyle(EditorialColor.ink)

            Spacer(minLength: EditorialSpacing.medium)

            Text(value)
                .font(.body)
                .foregroundStyle(EditorialColor.secondaryInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(EditorialSpacing.compact)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DashboardView()
        .environmentObject(LocationManager.shared)
        .environmentObject(LocationStore.shared)
        .environmentObject(CloudKitSyncManager.shared)
        .environmentObject(HealthKitManager.shared)
        .environmentObject(SyncCoordinator.shared)
}

import SwiftUI
import CloudKit

struct ICloudAccountBannerView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager

    var body: some View {
        if cloudKitSyncManager.accountStatus != .available && cloudKitSyncManager.accountStatus != .couldNotDetermine {
            VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
                HStack(alignment: .top, spacing: EditorialSpacing.compact) {
                    Image(systemName: iconName)
                        .font(.title3.weight(.light))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                        Text("SYSTEM NOTICE / ICLOUD")
                            .font(.editorialUtilitySmall)
                        Text(bannerTitle)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(bannerMessage)
                            .font(.body)
                            .foregroundStyle(EditorialColor.secondaryInk)
                    }
                }

                Button(action: cloudKitSyncManager.openSettingsForAccount) {
                    Label("Account Settings", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(EditorialButtonStyle(isPrimary: false))
            }
            .editorialPanel(emphasized: true)
        }
    }

    private var iconName: String {
        switch cloudKitSyncManager.accountStatus {
        case .noAccount: "person.crop.circle.badge.exclamationmark"
        case .restricted: "lock.icloud"
        default: "exclamationmark.icloud"
        }
    }

    private var bannerTitle: String {
        switch cloudKitSyncManager.accountStatus {
        case .noAccount: "Sign in to iCloud"
        case .restricted: "iCloud access is restricted"
        default: "iCloud account required"
        }
    }

    private var bannerMessage: String {
        switch cloudKitSyncManager.accountStatus {
        case .noAccount:
            "Sign in with your Apple Account in iOS Settings so Hermes can sync telemetry and letters to your Mac via iCloud."
        case .restricted:
            "Screen Time or device-management policy is preventing access to private iCloud synchronization."
        default:
            "iCloud Drive access is required to sync telemetry and correspondence with your Hermes agent on macOS."
        }
    }
}

#if DEBUG
#Preview("No iCloud Account") {
    ICloudAccountBannerView()
        .environmentObject(LocationManager.shared)
        .environmentObject({
            let syncManager = CloudKitSyncManager.shared
            syncManager.setMockAccountStatus(.noAccount)
            return syncManager
        }())
        .padding()
}

#Preview("Restricted Account") {
    ICloudAccountBannerView()
        .environmentObject(LocationManager.shared)
        .environmentObject({
            let syncManager = CloudKitSyncManager.shared
            syncManager.setMockAccountStatus(.restricted)
            return syncManager
        }())
        .padding()
}
#endif

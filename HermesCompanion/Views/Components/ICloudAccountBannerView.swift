import SwiftUI
import CloudKit

struct ICloudAccountBannerView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager

    var body: some View {
        if locationManager.configuration.syncDestination.isCloudKitEnabled,
           cloudKitSyncManager.accountStatus != .available {
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
                    Label("OPEN ACCOUNT SETTINGS", systemImage: "arrow.up.forward.app")
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
            "Sign in with your Apple Account so Hermes can use your private CloudKit archive."
        case .restricted:
            "Screen Time or device-management policy is preventing access to the private archive."
        default:
            "Verify the Apple Account state and enable CloudKit before transmitting records."
        }
    }
}

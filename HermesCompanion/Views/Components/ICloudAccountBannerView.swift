import SwiftUI
import CloudKit

struct ICloudAccountBannerView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager

    var body: some View {
        if locationManager.configuration.syncDestination.isCloudKitEnabled && cloudKitSyncManager.accountStatus != .available {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundColor(accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(bannerTitle)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        Text(bannerMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button(action: openSettings) {
                        HStack(spacing: 6) {
                            Text(buttonLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(accentColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    private var accentColor: Color {
        switch cloudKitSyncManager.accountStatus {
        case .noAccount: return .blue
        case .restricted: return .orange
        default: return .indigo
        }
    }

    private var iconName: String {
        switch cloudKitSyncManager.accountStatus {
        case .noAccount: return "person.crop.circle.badge.exclamationmark"
        case .restricted: return "lock.icloud.fill"
        default: return "exclamationmark.icloud.fill"
        }
    }

    private var bannerTitle: String {
        switch cloudKitSyncManager.accountStatus {
        case .noAccount: return "Sign In to iCloud"
        case .restricted: return "iCloud Access Restricted"
        default: return "iCloud Account Required"
        }
    }

    private var bannerMessage: String {
        switch cloudKitSyncManager.accountStatus {
        case .noAccount:
            return "Sign in with your Apple ID in Settings so Hermes can store your location in your private iCloud database."
        case .restricted:
            return "iCloud access is restricted on this device by Screen Time or enterprise policy."
        default:
            return "Open Settings to verify your Apple Account status and enable CloudKit sync."
        }
    }

    private var buttonLabel: String {
        switch cloudKitSyncManager.accountStatus {
        case .noAccount: return "Sign In in Settings"
        default: return "Open Settings"
        }
    }

    private func openSettings() {
        cloudKitSyncManager.openSettingsForAccount()
    }
}

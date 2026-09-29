import SwiftUI

struct PermissionBannerView: View {
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        if !locationManager.isAlwaysAuthorized {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)

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
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    private var bannerTitle: String {
        if locationManager.authorizationStatus == .notDetermined {
            return "Background Location Access Needed"
        } else if locationManager.authorizationStatus == .authorizedWhenInUse {
            return "Upgrade to 'Always Allow'"
        } else {
            return "Location Access Disabled"
        }
    }

    private var bannerMessage: String {
        if locationManager.authorizationStatus == .notDetermined {
            return "Grant 'Always' location permission so Hermes can track and wake up even when the app is closed."
        } else if locationManager.authorizationStatus == .authorizedWhenInUse {
            return "Currently set to 'While Using App'. To receive location updates when the app is closed or killed, switch permission to 'Always'."
        } else {
            return "Hermes requires location permission to operate. Please allow location access in iOS Settings."
        }
    }

    private var buttonLabel: String {
        if locationManager.authorizationStatus == .notDetermined {
            return "Request Access"
        } else {
            return "Open Settings"
        }
    }

    private func openSettings() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermissions()
        } else {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }
    }
}

import SwiftUI

struct PermissionBannerView: View {
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        if !locationManager.isAlwaysAuthorized {
            VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
                HStack(alignment: .top, spacing: EditorialSpacing.compact) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3.weight(.light))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                        Text("SYSTEM NOTICE / LOCATION")
                            .font(.editorialUtilitySmall)
                        Text(bannerTitle)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(bannerMessage)
                            .font(.body)
                            .foregroundStyle(EditorialColor.secondaryInk)
                    }
                }

                Button(action: openSettings) {
                    Label(buttonLabel.uppercased(), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(EditorialButtonStyle(isPrimary: true))
            }
            .editorialPanel(emphasized: true)
        }
    }

    private var bannerTitle: String {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return "Background access is not established"
        case .authorizedWhenInUse:
            return "Always access is recommended"
        default:
            return "Location access is disabled"
        }
    }

    private var bannerMessage: String {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return "Grant location permission so Hermes can establish readings and respond to movement."
        case .authorizedWhenInUse:
            return "While Using limits closed-state readings. Choose Always in Settings for unattended telemetry."
        default:
            return "Hermes cannot operate without location access. Review this app’s permissions in Settings."
        }
    }

    private var buttonLabel: String {
        locationManager.authorizationStatus == .notDetermined ? "Request access" : "Open settings"
    }

    private func openSettings() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermissions()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

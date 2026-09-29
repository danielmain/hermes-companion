import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Transmitter", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(0)

            HistoryLogView()
                .tabItem {
                    Label("Transmissions", systemImage: "arrow.up.circle.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Hermes Config", systemImage: "slider.horizontal.3")
                }
                .tag(2)
        }
        .tint(Color.accentColor)
    }
}

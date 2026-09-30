import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Field", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(0)

            HistoryLogView()
                .tabItem {
                    Label("Archive", systemImage: "archivebox")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Config", systemImage: "slider.horizontal.3")
                }
                .tag(2)
        }
        .tint(EditorialColor.ink)
        .toolbarBackground(EditorialColor.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(0)

            HealthDetailView()
                .tabItem {
                    Label("Health", systemImage: "heart.text.square")
                }
                .tag(1)

            PlacesView()
                .tabItem {
                    Label("Places", systemImage: "mappin.and.ellipse")
                }
                .tag(2)

            HistoryLogView()
                .tabItem {
                    Label("Archive", systemImage: "archivebox")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(4)
        }
        .tint(EditorialColor.ink)
        .toolbarBackground(EditorialColor.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

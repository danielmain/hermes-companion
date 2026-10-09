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

            PostInboxView()
                .tabItem {
                    Label("Post", systemImage: "envelope")
                }
                .tag(1)

            HealthDetailView()
                .tabItem {
                    Label("Health", systemImage: "heart.text.square")
                }
                .tag(2)

            PlacesView()
                .tabItem {
                    Label("Places", systemImage: "mappin.and.ellipse")
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

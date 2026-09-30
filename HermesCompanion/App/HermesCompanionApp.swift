import SwiftUI

@main
struct HermesCompanionApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var locationStore = LocationStore.shared
    @StateObject private var cloudKitSyncManager = CloudKitSyncManager.shared
    @StateObject private var healthKitManager = HealthKitManager.shared

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(locationManager)
                .environmentObject(locationStore)
                .environmentObject(cloudKitSyncManager)
                .environmentObject(healthKitManager)
                .tint(EditorialColor.ink)
        }
    }
}

private struct AppRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedEditorialOnboarding") private var hasCompletedOnboarding = false
    @State private var isLoading = true

    var body: some View {
        ZStack {
            EditorialColor.paper
                .ignoresSafeArea()

            if isLoading {
                EditorialLoadingView()
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            } else if hasCompletedOnboarding {
                MainTabView()
                    .transition(.opacity)
            } else {
                EditorialOnboardingView {
                    withAnimation(reduceMotion ? nil : EditorialMotion.standard) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            }
        }
        .task {
            guard isLoading else { return }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 350 : 1450))
            withAnimation(reduceMotion ? .linear(duration: 0.15) : EditorialMotion.standard) {
                isLoading = false
            }
        }
    }
}

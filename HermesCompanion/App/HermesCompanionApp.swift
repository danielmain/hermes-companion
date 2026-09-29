import SwiftUI

@main
struct HermesCompanionApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var locationStore = LocationStore.shared
    @StateObject private var syncManager = SyncManager.shared
    @StateObject private var cloudKitSyncManager = CloudKitSyncManager.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(locationManager)
                .environmentObject(locationStore)
                .environmentObject(syncManager)
                .environmentObject(cloudKitSyncManager)
        }
    }
}

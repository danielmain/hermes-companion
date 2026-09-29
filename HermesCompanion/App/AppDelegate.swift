import UIKit
import CoreLocation

public final class AppDelegate: NSObject, UIApplicationDelegate {

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register BackgroundTasks
        BackgroundTaskManager.shared.registerBackgroundTasks()

        // Critical requirement for "Always even when closed":
        // Instantiate LocationManager immediately so CoreLocation delegate receives pending events!
        let locationManager = LocationManager.shared
        locationManager.handleAppLaunch(with: launchOptions)

        return true
    }

    public func applicationDidEnterBackground(_ application: UIApplication) {
        LocationStore.shared.logDiagnostic(
            title: "App Entered Background",
            details: "Background location tracking active",
            severity: .info
        )
        BackgroundTaskManager.shared.scheduleAppRefresh()
    }

    public func applicationWillEnterForeground(_ application: UIApplication) {
        LocationStore.shared.logDiagnostic(
            title: "App Returned to Foreground",
            severity: .info
        )
    }

    public func applicationWillTerminate(_ application: UIApplication) {
        LocationStore.shared.logDiagnostic(
            title: "App Will Terminate",
            details: "Significant location & geofence will keep listening for events",
            severity: .warning
        )
    }
}

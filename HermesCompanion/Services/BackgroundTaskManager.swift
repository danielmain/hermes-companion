import Foundation
import BackgroundTasks
import UIKit

public final class BackgroundTaskManager {
    public static let shared = BackgroundTaskManager()

    public static let refreshTaskIdentifier = "com.hermes.companion.refresh"
    public static let processingTaskIdentifier = "com.hermes.companion.sync"

    private init() {}

    public func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskManager.refreshTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(task: refreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskManager.processingTaskIdentifier,
            using: nil
        ) { task in
            guard let procTask = task as? BGProcessingTask else { return }
            self.handleBackgroundProcessing(task: procTask)
        }
    }

    public func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskManager.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 mins
        do {
            try BGTaskScheduler.shared.submit(request)
            LocationStore.shared.logDiagnostic(
                title: "Background Refresh Scheduled",
                details: "Scheduled for next 15+ minutes",
                severity: .info
            )
        } catch {
            LocationStore.shared.logDiagnostic(
                title: "Schedule Refresh Failed",
                details: error.localizedDescription,
                severity: .warning
            )
        }
    }

    public func scheduleBackgroundProcessing() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskManager.processingTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Task scheduling ignored if not permitted
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        task.expirationHandler = {
            queue.cancelAllOperations()
            LocationStore.shared.logDiagnostic(title: "Background Refresh Expired", severity: .warning)
        }

        queue.addOperation {
            LocationStore.shared.logDiagnostic(
                title: "Background Refresh Executed",
                details: "Woke in background via BGTaskScheduler",
                severity: .info
            )

            // Request one-shot location fix during background task
            DispatchQueue.main.async {
                LocationManager.shared.requestSingleLocationUpdate(source: .backgroundFetch)
            }

            task.setTaskCompleted(success: true)
        }
    }

    private func handleBackgroundProcessing(task: BGProcessingTask) {
        scheduleBackgroundProcessing()

        task.expirationHandler = {
            LocationStore.shared.logDiagnostic(title: "Background Processing Expired", severity: .warning)
        }

        DispatchQueue.main.async {
            let config = LocationManager.shared.configuration
            let records = LocationStore.shared.records
            if config.autoSyncEnabled {
                if config.syncDestination.isWebhookEnabled {
                    SyncManager.shared.syncPendingRecords(config: config, records: records)
                }
                if config.syncDestination.isCloudKitEnabled {
                    CloudKitSyncManager.shared.syncPendingRecords(config: config, records: records)
                }
            }
            task.setTaskCompleted(success: true)
        }
    }
}

import Foundation
import HealthKit
import Combine
import UIKit

public enum HealthKitAuthorizationStatus: String, Codable {
    case notDetermined = "not_determined"
    case authorized = "authorized"
    case denied = "denied"
    case unavailable = "unavailable"

    public var title: String {
        switch self {
        case .notDetermined: return "Authorization Needed"
        case .authorized: return "Authorized"
        case .denied: return "Access Denied"
        case .unavailable: return "HealthKit Unavailable"
        }
    }
}

public final class HealthKitManager: ObservableObject {
    public static let shared = HealthKitManager()

    // MARK: - Published State
    @Published public private(set) var isAvailable: Bool = false
    @Published public private(set) var authorizationStatus: HealthKitAuthorizationStatus = .notDetermined
    @Published public private(set) var latestSnapshot: HealthSnapshot?
    @Published public private(set) var isQuerying: Bool = false
    @Published public private(set) var lastRefreshedAt: Date?
    @Published public private(set) var lastErrorMessage: String?

    // MARK: - HealthKit Core
    private let healthStore = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private let healthCacheFileName = "hermes_latest_health.json"

    // MARK: - Required Read Types
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        if let rhr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(rhr)
        }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        return types
    }

    private init() {
        self.isAvailable = HKHealthStore.isHealthDataAvailable()
        loadCachedSnapshot()

        if isAvailable {
            checkCurrentAuthorization()
        }
    }

    // MARK: - Permissions & Authorization
    public func checkCurrentAuthorization() {
        guard isAvailable else {
            self.authorizationStatus = .unavailable
            return
        }

        // Check status on a representative type (e.g. workout)
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        DispatchQueue.main.async {
            switch status {
            case .notDetermined:
                self.authorizationStatus = .notDetermined
            case .sharingAuthorized:
                self.authorizationStatus = .authorized
            case .sharingDenied:
                self.authorizationStatus = .denied
            @unknown default:
                self.authorizationStatus = .notDetermined
            }
        }
    }

    public func requestAuthorization(completion: ((Bool, String?) -> Void)? = nil) {
        guard isAvailable else {
            let msg = "Apple Health is not available on this device"
            self.lastErrorMessage = msg
            LocationStore.shared.logDiagnostic(title: "HealthKit Unavailable", details: msg, severity: .warning)
            completion?(false, msg)
            return
        }

        LocationStore.shared.logDiagnostic(
            title: "Requesting Apple Health Authorization",
            details: "Types: Sleep, Workouts, Heart Rate, Resting HR, HRV, Steps, Active Energy",
            severity: .info
        )

        healthStore.requestAuthorization(toShare: nil, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.lastErrorMessage = error.localizedDescription
                    self.authorizationStatus = .denied
                    LocationStore.shared.logDiagnostic(
                        title: "HealthKit Auth Failed",
                        details: error.localizedDescription,
                        severity: .error
                    )
                    completion?(false, error.localizedDescription)
                    return
                }

                if success {
                    self.authorizationStatus = .authorized
                    LocationStore.shared.logDiagnostic(
                        title: "HealthKit Authorized",
                        details: "Permissions granted to access sleep, workouts, and vitals",
                        severity: .success
                    )
                    self.setupBackgroundObservers()
                    self.refreshHealthSnapshot { _ in }
                    completion?(true, nil)
                } else {
                    self.authorizationStatus = .notDetermined
                    completion?(false, "Authorization request was dismissed or not granted")
                }
            }
        }
    }

    // MARK: - Background Delivery & Observers
    public func setupBackgroundObservers() {
        guard isAvailable else { return }

        // Observe Workouts
        let workoutType = HKObjectType.workoutType()
        let workoutObserver = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                self?.refreshHealthSnapshot { _ in
                    completionHandler()
                }
            } else {
                completionHandler()
            }
        }
        healthStore.execute(workoutObserver)
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in }
        observerQueries.append(workoutObserver)

        // Observe Sleep
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            let sleepObserver = HKObserverQuery(sampleType: sleepType, predicate: nil) { [weak self] _, completionHandler, error in
                if error == nil {
                    self?.refreshHealthSnapshot { _ in
                        completionHandler()
                    }
                } else {
                    completionHandler()
                }
            }
            healthStore.execute(sleepObserver)
            healthStore.enableBackgroundDelivery(for: sleepType, frequency: .hourly) { _, _ in }
            observerQueries.append(sleepObserver)
        }
    }

    // MARK: - Health Snapshot Refresh Pipeline
    public func refreshHealthSnapshot(completion: @escaping (Result<HealthSnapshot, Error>) -> Void) {
        guard isAvailable else {
            let err = NSError(domain: "HermesHealth", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit not available"])
            completion(.failure(err))
            return
        }

        DispatchQueue.main.async {
            self.isQuerying = true
        }

        let group = DispatchGroup()
        var retrievedSleep: SleepRecord?
        var retrievedActiveWorkout: WorkoutRecord?
        var retrievedLatestWorkout: WorkoutRecord?
        var retrievedVitals = VitalsRecord()

        // 1. Fetch Sleep (Last 36 hours to capture previous night / morning sleep)
        group.enter()
        fetchSleepRecord { result in
            if case .success(let sleep) = result {
                retrievedSleep = sleep
            }
            group.leave()
        }

        // 2. Fetch Workouts (Recent or in-progress)
        group.enter()
        fetchWorkouts { result in
            if case .success(let (active, latest)) = result {
                retrievedActiveWorkout = active
                retrievedLatestWorkout = latest
            }
            group.leave()
        }

        // 3. Fetch Vitals (Resting HR, Current HR, HRV, Steps, Active Energy)
        group.enter()
        fetchVitals { result in
            if case .success(let vitals) = result {
                retrievedVitals = vitals
            }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isQuerying = false

            let snapshot = HealthSnapshot(
                sleep: retrievedSleep,
                activeWorkout: retrievedActiveWorkout,
                latestWorkout: retrievedLatestWorkout,
                vitals: retrievedVitals
            )

            self.latestSnapshot = snapshot
            self.lastRefreshedAt = Date()
            self.saveCachedSnapshot(snapshot)
            self.mirrorHealthToFile(snapshot: snapshot)

            LocationStore.shared.logDiagnostic(
                title: "Health Snapshot Updated",
                details: "Sleep: \(snapshot.sleep?.formattedDuration ?? "None"), Workout: \(snapshot.activeWorkout?.workoutType ?? snapshot.latestWorkout?.workoutType ?? "None"), Steps: \(snapshot.vitals.stepCountToday)",
                severity: .info
            )

            completion(.success(snapshot))
        }
    }

    // MARK: - Query 1: Sleep Analysis
    private func fetchSleepRecord(completion: @escaping (Result<SleepRecord?, Error>) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(.success(nil))
            return
        }

        let now = Date()
        let calendar = Calendar.current
        // Look back 36 hours to encompass last night's full sleep block
        let startTime = calendar.date(byAdding: .hour, value: -36, to: now) ?? now.addingTimeInterval(-129600)
        let predicate = HKQuery.predicateForSamples(withStart: startTime, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let categorySamples = samples as? [HKCategorySample], !categorySamples.isEmpty else {
                completion(.success(nil))
                return
            }

            // Pure functional sleep calculation
            let sleepRecord = HealthKitManager.computeSleepRecord(from: categorySamples, referenceDate: now)
            completion(.success(sleepRecord))
        }

        healthStore.execute(query)
    }

    public static func computeSleepRecord(from samples: [HKCategorySample], referenceDate: Date = Date()) -> SleepRecord? {
        guard !samples.isEmpty else { return nil }

        // Sort samples by endDate ascending
        let sortedSamples = samples.sorted { $0.endDate < $1.endDate }

        // Find the latest sleep sample that ended within the last 30 hours
        let recentCutoff = referenceDate.addingTimeInterval(-108000) // 30 hours
        guard let latestSample = sortedSamples.last(where: { $0.endDate > recentCutoff }) else {
            return nil
        }

        // Cluster backwards from the latest sample to capture only the current/last night's session.
        // A gap of > 4 hours between contiguous sleep stages defines a distinct previous session (nap or previous night).
        var sessionSamples: [HKCategorySample] = []
        var currentEnd = latestSample.endDate

        for sample in sortedSamples.reversed() {
            if sample.startDate > currentEnd { continue }

            let earliestSoFar = sessionSamples.map(\.startDate).min() ?? currentEnd
            if earliestSoFar.timeIntervalSince(sample.endDate) > 14400 { // 4 hours gap
                break
            }

            sessionSamples.append(sample)
        }

        guard !sessionSamples.isEmpty else { return nil }

        // Source prioritization:
        // Multiple devices (iPhone, Apple Watch, 3rd party apps) write to HealthKit.
        // Check if there are sources providing detailed sleep stages (deep, rem, core).
        let stageValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue
        ]

        let samplesBySource = Dictionary(grouping: sessionSamples, by: { $0.sourceRevision.source.bundleIdentifier })

        // Find sources that have stage data
        let sourcesWithStages = samplesBySource.filter { _, srcSamples in
            srcSamples.contains { stageValues.contains($0.value) }
        }

        let selectedSamples: [HKCategorySample]
        if !sourcesWithStages.isEmpty {
            // If Apple Watch / first-party health exists with stages, prioritize it
            if let appleHealth = sourcesWithStages.first(where: { $0.key.lowercased().contains("health") || $0.key.lowercased().contains("watch") }) {
                selectedSamples = appleHealth.value
            } else {
                // Otherwise pick the source with the most stage samples
                let best = sourcesWithStages.max(by: { a, b in
                    let countA = a.value.filter { stageValues.contains($0.value) }.count
                    let countB = b.value.filter { stageValues.contains($0.value) }.count
                    return countA < countB
                })
                selectedSamples = best?.value ?? sessionSamples
            }
        } else {
            selectedSamples = sessionSamples
        }

        // Extract intervals by category
        let deepIntervals = selectedSamples
            .filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
            .map { ($0.startDate, $0.endDate) }

        let remIntervals = selectedSamples
            .filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
            .map { ($0.startDate, $0.endDate) }

        let coreIntervals = selectedSamples
            .filter { $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue }
            .map { ($0.startDate, $0.endDate) }

        let unspecifiedIntervals = selectedSamples
            .filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
            .map { ($0.startDate, $0.endDate) }

        let awakeIntervals = selectedSamples
            .filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
            .map { ($0.startDate, $0.endDate) }

        // Merge overlapping intervals to prevent ANY double-counting
        let mergedDeep = mergeIntervals(deepIntervals)
        let mergedREM = mergeIntervals(remIntervals)
        let mergedCore = mergeIntervals(coreIntervals)
        let mergedAwake = mergeIntervals(awakeIntervals)

        let hasStages = !mergedDeep.isEmpty || !mergedREM.isEmpty || !mergedCore.isEmpty

        // For total sleep, compute the union of all asleep intervals
        let allSleepIntervals: [(Date, Date)]
        if hasStages {
            allSleepIntervals = deepIntervals + remIntervals + coreIntervals
        } else {
            allSleepIntervals = unspecifiedIntervals
        }
        let mergedTotalSleep = mergeIntervals(allSleepIntervals)

        let totalMinutes = calculateTotalMinutes(for: mergedTotalSleep)
        guard totalMinutes > 0 else { return nil }

        let deepMinutes = calculateTotalMinutes(for: mergedDeep)
        let remMinutes = calculateTotalMinutes(for: mergedREM)
        let coreMinutes = calculateTotalMinutes(for: mergedCore)
        let awakeMinutes = calculateTotalMinutes(for: mergedAwake)

        let earliestBedtime = selectedSamples.map(\.startDate).min()
        let latestWakeTime = selectedSamples.map(\.endDate).max()

        return SleepRecord(
            bedtime: earliestBedtime,
            wakeTime: latestWakeTime,
            totalSleepMinutes: totalMinutes,
            deepSleepMinutes: deepMinutes,
            remSleepMinutes: remMinutes,
            coreSleepMinutes: coreMinutes,
            awakeMinutes: awakeMinutes
        )
    }

    private static func mergeIntervals(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
        guard !intervals.isEmpty else { return [] }
        let valid = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard let first = valid.first else { return [] }

        var merged: [(Date, Date)] = [first]
        for (start, end) in valid.dropFirst() {
            let lastIdx = merged.count - 1
            let (lastStart, lastEnd) = merged[lastIdx]
            if start <= lastEnd {
                merged[lastIdx] = (lastStart, max(lastEnd, end))
            } else {
                merged.append((start, end))
            }
        }
        return merged
    }

    private static func calculateTotalMinutes(for intervals: [(Date, Date)]) -> Int {
        let totalSeconds = intervals.reduce(0.0) { acc, range in
            acc + range.1.timeIntervalSince(range.0)
        }
        return max(0, Int(round(totalSeconds / 60.0)))
    }

    // MARK: - Query 2: Workouts
    private func fetchWorkouts(completion: @escaping (Result<(WorkoutRecord?, WorkoutRecord?), Error>) -> Void) {
        let workoutType = HKObjectType.workoutType()
        let now = Date()
        let startTime = Calendar.current.date(byAdding: .hour, value: -24, to: now) ?? now.addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(withStart: startTime, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: predicate,
            limit: 5,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let workouts = samples as? [HKWorkout], let newest = workouts.first else {
                completion(.success((nil, nil)))
                return
            }

            let (active, latest) = HealthKitManager.computeWorkoutRecords(from: newest, referenceDate: now)
            completion(.success((active, latest)))
        }

        healthStore.execute(query)
    }

    public static func computeWorkoutRecords(from workout: HKWorkout, referenceDate: Date = Date()) -> (WorkoutRecord?, WorkoutRecord?) {
        let typeName = workout.workoutActivityType.displayName
        let category = workout.workoutActivityType.category
        let durationMin = max(1, Int(workout.duration / 60.0))

        let activeCal: Double = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0.0
        let totalCal: Double = activeCal

        // Check if workout is ongoing: endDate within 2 minutes of referenceDate or duration ongoing
        let elapsedSinceEnd = referenceDate.timeIntervalSince(workout.endDate)
        let isActive = elapsedSinceEnd < 120 && elapsedSinceEnd >= -60

        let record = WorkoutRecord(
            id: workout.uuid,
            workoutType: typeName,
            category: category,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationMinutes: durationMin,
            activeCalories: activeCal,
            totalCalories: totalCal,
            isCurrentlyActive: isActive,
            referenceDate: referenceDate
        )

        if isActive {
            return (record, record)
        } else {
            return (nil, record)
        }
    }

    // MARK: - Query 3: Vitals
    private func fetchVitals(completion: @escaping (Result<VitalsRecord, Error>) -> Void) {
        let group = DispatchGroup()
        var restingHR: Double?
        var currentHR: Double?
        var hrv: Double?
        var activeEnergy: Double = 0.0
        var steps: Int = 0

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        // Resting HR
        if let rhrType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            group.enter()
            fetchLatestQuantity(type: rhrType, unit: HKUnit.count().unitDivided(by: .minute())) { val in
                restingHR = val
                group.leave()
            }
        }

        // Current Heart Rate (last 2 hours)
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            group.enter()
            fetchLatestQuantity(type: hrType, unit: HKUnit.count().unitDivided(by: .minute())) { val in
                currentHR = val
                group.leave()
            }
        }

        // HRV SDNN
        if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            group.enter()
            fetchLatestQuantity(type: hrvType, unit: HKUnit.secondUnit(with: .milli)) { val in
                hrv = val
                group.leave()
            }
        }

        // Active Energy Burned Today
        if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            group.enter()
            fetchCumulativeSum(type: energyType, unit: .kilocalorie(), start: startOfDay, end: now) { val in
                activeEnergy = val
                group.leave()
            }
        }

        // Steps Today
        if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            group.enter()
            fetchCumulativeSum(type: stepType, unit: .count(), start: startOfDay, end: now) { val in
                steps = Int(val)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let vitals = VitalsRecord(
                restingHeartRateBPM: restingHR,
                currentHeartRateBPM: currentHR,
                heartRateVariabilitySDNN: hrv,
                activeEnergyBurnedKCal: activeEnergy,
                stepCountToday: steps
            )
            completion(.success(vitals))
        }
    }

    private func fetchLatestQuantity(type: HKQuantityType, unit: HKUnit, completion: @escaping (Double?) -> Void) {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else {
                completion(nil)
                return
            }
            completion(sample.quantity.doubleValue(for: unit))
        }
        healthStore.execute(query)
    }

    private func fetchCumulativeSum(type: HKQuantityType, unit: HKUnit, start: Date, end: Date, completion: @escaping (Double) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
            let sum = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0.0
            completion(sum)
        }
        healthStore.execute(query)
    }

    // MARK: - Persistence & Ubiquity Container File Mirroring
    private func saveCachedSnapshot(_ snapshot: HealthSnapshot) {
        DispatchQueue.global(qos: .utility).async {
            guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
            let fileURL = dir.appendingPathComponent(self.healthCacheFileName)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private func loadCachedSnapshot() {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let fileURL = dir.appendingPathComponent(healthCacheFileName)
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(HealthSnapshot.self, from: data) else { return }
        self.latestSnapshot = snapshot
    }

    public func mirrorHealthToFile(snapshot: HealthSnapshot) {
        DispatchQueue.global(qos: .utility).async {
            let payload = snapshot.toDictionary()
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }

            // 1. Write to /tmp/hermes_latest_health.json for local simulator / bridge fallback
            let tmpURL = URL(fileURLWithPath: "/tmp/hermes_latest_health.json")
            try? jsonData.write(to: tmpURL, options: .atomic)

            // 2. Write to ubiquitous iCloud Documents container for zero-latency macOS sync
            let config = TrackingConfiguration.default
            let containerId = config.cloudKitContainerIdentifier.trimmingCharacters(in: .whitespaces).isEmpty ? nil : config.cloudKitContainerIdentifier
            if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId) ?? FileManager.default.url(forUbiquityContainerIdentifier: nil) {
                let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
                try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)

                let cloudFileURL = documentsURL.appendingPathComponent("latest_health.json")
                try? jsonData.write(to: cloudFileURL, options: .atomic)

                let rootFileURL = containerURL.appendingPathComponent("latest_health.json")
                try? jsonData.write(to: rootFileURL, options: .atomic)
            }
        }
    }
}

// MARK: - Workout Activity Extensions
public extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining: return "Functional Training"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .highIntensityIntervalTraining: return "HIIT"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climber"
        case .coreTraining: return "Core Training"
        case .elliptical: return "Elliptical"
        case .crossTraining: return "Cross Training"
        case .hiking: return "Hiking"
        default: return "Workout"
        }
    }

    var category: WorkoutCategory {
        switch self {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining:
            return .strength
        case .running, .cycling, .swimming, .rowing, .stairClimbing, .elliptical:
            return .cardio
        case .highIntensityIntervalTraining, .crossTraining:
            return .hiit
        case .yoga, .pilates:
            return .recovery
        case .walking, .hiking:
            return .walking
        default:
            return .other
        }
    }
}

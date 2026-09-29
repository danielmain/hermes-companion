import Foundation

// MARK: - Enums & Rich Types

public enum SleepQualityRating: String, Codable, CaseIterable {
    case excellent = "excellent"     // >= 7.5h, >= 15% deep sleep
    case good = "good"               // >= 6.5h
    case fair = "fair"               // 5.0h - 6.5h
    case poor = "poor"               // < 5.0h or very fragmented
    case unknown = "unknown"

    public var title: String {
        switch self {
        case .excellent: return "Excellent Rest"
        case .good: return "Good Rest"
        case .fair: return "Fair / Short Sleep"
        case .poor: return "Poor Rest / Sleep Deprived"
        case .unknown: return "Unknown"
        }
    }

    public var emoji: String {
        switch self {
        case .excellent: return "🌟"
        case .good: return "😴"
        case .fair: return "🥱"
        case .poor: return "⚠️"
        case .unknown: return "❓"
        }
    }
}

public enum WorkoutCategory: String, Codable, CaseIterable {
    case strength = "strength"
    case cardio = "cardio"
    case hiit = "hiit"
    case recovery = "recovery"
    case walking = "walking"
    case other = "other"

    public var emoji: String {
        switch self {
        case .strength: return "🏋️"
        case .cardio: return "🏃"
        case .hiit: return "🔥"
        case .recovery: return "🧘"
        case .walking: return "🚶"
        case .other: return "⚡️"
        }
    }
}

public enum PostWorkoutPhase: String, Codable, CaseIterable {
    case inProgress = "in_progress"         // Workout currently active
    case justFinished = "just_finished"     // Finished <= 30 mins ago (prime protein/hydration window)
    case recent = "recent"                  // Finished 31 - 120 mins ago (recovery window, post-workout tiredness)
    case earlierToday = "earlier_today"     // Finished 2 - 8 hours ago
    case past = "past"                      // Finished > 8 hours ago

    public var isPostWorkoutWindow: Bool {
        self == .justFinished || self == .recent
    }
}

public enum RecoveryStatus: String, Codable, CaseIterable {
    case recovered = "recovered"
    case moderate = "moderate"
    case fatigued = "fatigued"
    case unknown = "unknown"

    public var title: String {
        switch self {
        case .recovered: return "Well Recovered"
        case .moderate: return "Moderate Recovery"
        case .fatigued: return "Elevated Fatigue"
        case .unknown: return "Unknown"
        }
    }

    public var emoji: String {
        switch self {
        case .recovered: return "🔋"
        case .moderate: return "⚡️"
        case .fatigued: return "🪫"
        case .unknown: return "⚪️"
        }
    }
}

// MARK: - Sleep Record

public struct SleepRecord: Codable, Equatable, Identifiable {
    public var id: String {
        let ts = bedtime?.timeIntervalSince1970 ?? 0
        return "sleep_\(Int(ts))"
    }

    public let bedtime: Date?
    public let wakeTime: Date?
    public let totalSleepMinutes: Int
    public let deepSleepMinutes: Int
    public let remSleepMinutes: Int
    public let coreSleepMinutes: Int
    public let awakeMinutes: Int
    public let qualityRating: SleepQualityRating

    public init(
        bedtime: Date?,
        wakeTime: Date?,
        totalSleepMinutes: Int,
        deepSleepMinutes: Int = 0,
        remSleepMinutes: Int = 0,
        coreSleepMinutes: Int = 0,
        awakeMinutes: Int = 0
    ) {
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.totalSleepMinutes = totalSleepMinutes
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.coreSleepMinutes = coreSleepMinutes
        self.awakeMinutes = awakeMinutes
        self.qualityRating = SleepRecord.calculateQuality(
            totalMinutes: totalSleepMinutes,
            deepMinutes: deepSleepMinutes,
            awakeMinutes: awakeMinutes
        )
    }

    public var totalHours: Double {
        Double(totalSleepMinutes) / 60.0
    }

    public var formattedDuration: String {
        let hours = totalSleepMinutes / 60
        let mins = totalSleepMinutes % 60
        return "\(hours)h \(mins)m"
    }

    public var deepSleepPercentage: Double {
        guard totalSleepMinutes > 0 else { return 0.0 }
        return Double(deepSleepMinutes) / Double(totalSleepMinutes) * 100.0
    }

    public var remSleepPercentage: Double {
        guard totalSleepMinutes > 0 else { return 0.0 }
        return Double(remSleepMinutes) / Double(totalSleepMinutes) * 100.0
    }

    public var summaryText: String {
        var parts: [String] = ["Slept \(formattedDuration) (\(qualityRating.title))"]
        if deepSleepMinutes > 0 {
            parts.append("\(deepSleepMinutes / 60)h \(deepSleepMinutes % 60)m deep")
        }
        if remSleepMinutes > 0 {
            parts.append("\(remSleepMinutes / 60)h \(remSleepMinutes % 60)m REM")
        }
        return parts.joined(separator: ", ")
    }

    public static func calculateQuality(totalMinutes: Int, deepMinutes: Int, awakeMinutes: Int) -> SleepQualityRating {
        guard totalMinutes > 0 else { return .unknown }
        let hours = Double(totalMinutes) / 60.0
        let deepPct = Double(deepMinutes) / Double(totalMinutes) * 100.0

        if hours >= 7.5 && deepPct >= 15.0 && awakeMinutes <= 40 {
            return .excellent
        } else if hours >= 6.5 {
            return .good
        } else if hours >= 5.0 {
            return .fair
        } else {
            return .poor
        }
    }
}

// MARK: - Workout Record

public struct WorkoutRecord: Codable, Equatable, Identifiable {
    public let id: UUID
    public let workoutType: String
    public let category: WorkoutCategory
    public let startDate: Date
    public let endDate: Date
    public let durationMinutes: Int
    public let activeCalories: Double
    public let totalCalories: Double
    public let averageHeartRateBPM: Double?
    public let maxHeartRateBPM: Double?
    public let isCurrentlyActive: Bool
    public let minutesSinceCompletion: Int?
    public let phase: PostWorkoutPhase

    public init(
        id: UUID = UUID(),
        workoutType: String,
        category: WorkoutCategory,
        startDate: Date,
        endDate: Date,
        durationMinutes: Int,
        activeCalories: Double,
        totalCalories: Double,
        averageHeartRateBPM: Double? = nil,
        maxHeartRateBPM: Double? = nil,
        isCurrentlyActive: Bool = false,
        referenceDate: Date = Date()
    ) {
        self.id = id
        self.workoutType = workoutType
        self.category = category
        self.startDate = startDate
        self.endDate = endDate
        self.durationMinutes = durationMinutes
        self.activeCalories = activeCalories
        self.totalCalories = totalCalories
        self.averageHeartRateBPM = averageHeartRateBPM
        self.maxHeartRateBPM = maxHeartRateBPM
        self.isCurrentlyActive = isCurrentlyActive

        if isCurrentlyActive {
            self.minutesSinceCompletion = nil
            self.phase = .inProgress
        } else {
            let elapsedSec = max(0, referenceDate.timeIntervalSince(endDate))
            let elapsedMin = Int(elapsedSec / 60.0)
            self.minutesSinceCompletion = elapsedMin

            if elapsedMin <= 30 {
                self.phase = .justFinished
            } else if elapsedMin <= 120 {
                self.phase = .recent
            } else if elapsedMin <= 480 {
                self.phase = .earlierToday
            } else {
                self.phase = .past
            }
        }
    }

    public var summaryText: String {
        let calStr = activeCalories > 0 ? "\(Int(activeCalories)) kcal" : ""
        let hrStr = averageHeartRateBPM != nil ? "avg \(Int(averageHeartRateBPM!)) bpm" : ""
        let details = [calStr, hrStr].filter { !$0.isEmpty }.joined(separator: ", ")

        if isCurrentlyActive {
            return "Active Workout: \(workoutType) (\(durationMinutes)m elapsed\(details.isEmpty ? "" : ", " + details))"
        } else {
            let agoStr: String
            if let mins = minutesSinceCompletion {
                agoStr = mins < 60 ? "\(mins)m ago" : "\(mins / 60)h ago"
            } else {
                agoStr = "earlier"
            }
            return "\(workoutType) (\(durationMinutes)m, \(details)) finished \(agoStr)"
        }
    }
}

// MARK: - Vitals Record

public struct VitalsRecord: Codable, Equatable {
    public let restingHeartRateBPM: Double?
    public let currentHeartRateBPM: Double?
    public let heartRateVariabilitySDNN: Double?
    public let activeEnergyBurnedKCal: Double
    public let stepCountToday: Int
    public let recoveryStatus: RecoveryStatus

    public init(
        restingHeartRateBPM: Double? = nil,
        currentHeartRateBPM: Double? = nil,
        heartRateVariabilitySDNN: Double? = nil,
        activeEnergyBurnedKCal: Double = 0.0,
        stepCountToday: Int = 0
    ) {
        self.restingHeartRateBPM = restingHeartRateBPM
        self.currentHeartRateBPM = currentHeartRateBPM
        self.heartRateVariabilitySDNN = heartRateVariabilitySDNN
        self.activeEnergyBurnedKCal = activeEnergyBurnedKCal
        self.stepCountToday = stepCountToday

        // Pure recovery calculation:
        // High HRV (e.g. > 55ms) & normal/low resting HR -> recovered.
        // Low HRV (< 35ms) or high resting HR (> 75bpm) -> fatigued.
        if let hrv = heartRateVariabilitySDNN {
            if hrv >= 55.0 {
                self.recoveryStatus = .recovered
            } else if hrv < 35.0 {
                self.recoveryStatus = .fatigued
            } else {
                self.recoveryStatus = .moderate
            }
        } else if let rhr = restingHeartRateBPM {
            if rhr <= 62.0 {
                self.recoveryStatus = .recovered
            } else if rhr > 74.0 {
                self.recoveryStatus = .fatigued
            } else {
                self.recoveryStatus = .moderate
            }
        } else {
            self.recoveryStatus = .unknown
        }
    }
}

// MARK: - Health Snapshot Model

public struct HealthSnapshot: Codable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let sleep: SleepRecord?
    public let activeWorkout: WorkoutRecord?
    public let latestWorkout: WorkoutRecord?
    public let vitals: VitalsRecord
    public let conversationalContext: HealthConversationalContext

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sleep: SleepRecord?,
        activeWorkout: WorkoutRecord?,
        latestWorkout: WorkoutRecord?,
        vitals: VitalsRecord
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sleep = sleep
        self.activeWorkout = activeWorkout
        self.latestWorkout = latestWorkout
        self.vitals = vitals
        self.conversationalContext = HealthSnapshot.buildConversationalContext(
            sleep: sleep,
            activeWorkout: activeWorkout,
            latestWorkout: latestWorkout,
            vitals: vitals
        )
    }

    public static func buildConversationalContext(
        sleep: SleepRecord?,
        activeWorkout: WorkoutRecord?,
        latestWorkout: WorkoutRecord?,
        vitals: VitalsRecord
    ) -> HealthConversationalContext {
        var prompts: [String] = []
        var sleepPrompt: String? = nil
        var workoutPrompt: String? = nil
        var nutritionPrompt: String? = nil

        // 1. Sleep insights
        if let s = sleep {
            switch s.qualityRating {
            case .excellent:
                sleepPrompt = "I saw you had a wonderful \(s.formattedDuration) of sleep last night with \(s.deepSleepMinutes)m of deep rest! Feeling fully recharged today?"
            case .good:
                sleepPrompt = "Looks like you had a solid \(s.formattedDuration) of sleep last night. Hope you're ready for the day!"
            case .fair:
                sleepPrompt = "Noticed you got about \(s.formattedDuration) of sleep last night. A bit on the shorter side, take it easy if you feel the afternoon slump."
            case .poor:
                sleepPrompt = "You only got \(s.formattedDuration) of sleep last night. Be gentle with yourself today, stay hydrated, and don't push too hard."
            case .unknown:
                sleepPrompt = nil
            }
            if let sp = sleepPrompt {
                prompts.append(sp)
            }
        }

        // 2. Active workout
        if let active = activeWorkout {
            workoutPrompt = "Daniel is in the middle of a \(active.workoutType) session (\(active.durationMinutes)m so far). Keep it encouraging and don't distract him too much!"
            prompts.append(workoutPrompt!)
        } else if let recent = latestWorkout {
            switch recent.phase {
            case .justFinished:
                workoutPrompt = "You just wrapped up your \(recent.workoutType) workout (\(recent.durationMinutes)m, \(Int(recent.activeCalories)) kcal)! How are you feeling?"
                nutritionPrompt = "Time for your post-workout protein! Make sure you get 30-40g of protein (shake, chicken, eggs) and plenty of water in to kickstart muscle repair."
                prompts.append(workoutPrompt!)
                prompts.append(nutritionPrompt!)
            case .recent:
                workoutPrompt = "Finished your \(recent.workoutType) workout about \(recent.minutesSinceCompletion ?? 45) minutes ago. Feeling that good post-workout exhaustion?"
                nutritionPrompt = "Don't forget to eat proper protein and refuel your glycogen reserves if you haven't eaten yet."
                prompts.append(workoutPrompt!)
                prompts.append(nutritionPrompt!)
            case .earlierToday:
                workoutPrompt = "Crushed a \(recent.workoutType) session earlier today (\(recent.durationMinutes)m, \(Int(recent.activeCalories)) kcal)."
                prompts.append(workoutPrompt!)
            case .inProgress, .past:
                break
            }
        }

        // 3. Recovery and fatigue
        if vitals.recoveryStatus == .fatigued {
            prompts.append("Your vitals (HRV/Resting HR) indicate your body is fatigued. Prioritize rest, good hydration, and quality food.")
        }

        return HealthConversationalContext(
            sleepInsight: sleepPrompt,
            workoutInsight: workoutPrompt,
            nutritionReminder: nutritionPrompt,
            recoverySummary: vitals.recoveryStatus.title,
            suggestedOpeners: prompts
        )
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "step_count_today": vitals.stepCountToday,
            "active_calories_today": vitals.activeEnergyBurnedKCal,
            "recovery_status": vitals.recoveryStatus.rawValue,
            "suggested_openers": conversationalContext.suggestedOpeners
        ]

        if let rhr = vitals.restingHeartRateBPM {
            dict["resting_heart_rate_bpm"] = rhr
        }
        if let chr = vitals.currentHeartRateBPM {
            dict["current_heart_rate_bpm"] = chr
        }
        if let hrv = vitals.heartRateVariabilitySDNN {
            dict["heart_rate_variability_sdnn"] = hrv
        }

        if let s = sleep {
            dict["sleep"] = [
                "total_sleep_minutes": s.totalSleepMinutes,
                "total_hours": s.totalHours,
                "formatted_duration": s.formattedDuration,
                "deep_sleep_minutes": s.deepSleepMinutes,
                "rem_sleep_minutes": s.remSleepMinutes,
                "core_sleep_minutes": s.coreSleepMinutes,
                "awake_minutes": s.awakeMinutes,
                "quality_rating": s.qualityRating.rawValue,
                "summary": s.summaryText,
                "bedtime": s.bedtime.map { ISO8601DateFormatter().string(from: $0) },
                "wake_time": s.wakeTime.map { ISO8601DateFormatter().string(from: $0) }
            ]
        }

        if let w = activeWorkout ?? latestWorkout {
            dict["workout"] = [
                "workout_type": w.workoutType,
                "category": w.category.rawValue,
                "duration_minutes": w.durationMinutes,
                "active_calories": w.activeCalories,
                "total_calories": w.totalCalories,
                "average_heart_rate": w.averageHeartRateBPM,
                "is_currently_active": w.isCurrentlyActive,
                "minutes_since_completion": w.minutesSinceCompletion,
                "phase": w.phase.rawValue,
                "summary": w.summaryText,
                "start_date": ISO8601DateFormatter().string(from: w.startDate),
                "end_date": ISO8601DateFormatter().string(from: w.endDate)
            ]
        }

        dict["conversational_context"] = [
            "sleep_insight": conversationalContext.sleepInsight,
            "workout_insight": conversationalContext.workoutInsight,
            "nutrition_reminder": conversationalContext.nutritionReminder,
            "recovery_summary": conversationalContext.recoverySummary
        ]

        return dict
    }
}

public struct HealthConversationalContext: Codable, Equatable {
    public let sleepInsight: String?
    public let workoutInsight: String?
    public let nutritionReminder: String?
    public let recoverySummary: String
    public let suggestedOpeners: [String]
}

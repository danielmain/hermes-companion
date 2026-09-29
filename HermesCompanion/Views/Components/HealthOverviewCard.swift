import SwiftUI
import HealthKit

public struct HealthOverviewCard: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("APPLE HEALTH & WELLNESS", systemImage: "heart.text.square.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.pink)

                Spacer()

                if healthKitManager.authorizationStatus == .authorized {
                    Button(action: {
                        healthKitManager.refreshHealthSnapshot { result in
                            if case .success(let snapshot) = result {
                                let config = locationManager.configuration
                                cloudKitSyncManager.syncHealthRecord(config: config, snapshot: snapshot)
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            if healthKitManager.isQuerying {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2)
                            }
                            Text(healthKitManager.isQuerying ? "Reading..." : "Refresh")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.pink.opacity(0.15))
                        .foregroundColor(.pink)
                        .clipShape(Capsule())
                    }
                    .disabled(healthKitManager.isQuerying)
                }
            }

            if healthKitManager.authorizationStatus != .authorized {
                // Authorization Request Banner
                VStack(alignment: .leading, spacing: 10) {
                    Text("Share Sleep & Workout Telemetry with Hermes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text("Allow Hermes to read your sleep quality, active workouts, and heart rate so it can ask about your rest, congratulate your training, and remind you to eat proper protein.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: {
                        healthKitManager.requestAuthorization { success, _ in
                            if success {
                                healthKitManager.refreshHealthSnapshot { _ in }
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.white)
                            Text("Connect Apple Health")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.pink)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding(12)
                .background(Color.pink.opacity(0.08))
                .cornerRadius(12)
            } else {
                // Live Health Data Display
                let snapshot = healthKitManager.latestSnapshot

                VStack(spacing: 12) {
                    // Sleep Tile
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bed.double.fill")
                            .font(.title3)
                            .foregroundColor(.indigo)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Sleep & Rest")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if let sleep = snapshot?.sleep {
                                    Text(sleep.qualityRating.title)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(sleepQualityColor(sleep.qualityRating).opacity(0.15))
                                        .foregroundColor(sleepQualityColor(sleep.qualityRating))
                                        .clipShape(Capsule())
                                }
                            }

                            if let sleep = snapshot?.sleep {
                                Text("\(sleep.formattedDuration) total")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Text(sleep.summaryText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No recent sleep recorded")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                    // Workout Tile
                    HStack(alignment: .top, spacing: 12) {
                        let workout = snapshot?.activeWorkout ?? snapshot?.latestWorkout
                        Image(systemName: workout?.isCurrentlyActive == true ? "figure.run.circle.fill" : "figure.strengthtraining.traditional")
                            .font(.title3)
                            .foregroundColor(workout?.isCurrentlyActive == true ? .green : .orange)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Workout Status")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if let w = workout {
                                    Text(w.isCurrentlyActive ? "ACTIVE NOW" : w.phase.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(w.isCurrentlyActive ? Color.green.opacity(0.2) : Color.orange.opacity(0.15))
                                        .foregroundColor(w.isCurrentlyActive ? .green : .orange)
                                        .clipShape(Capsule())
                                }
                            }

                            if let w = workout {
                                Text(w.workoutType)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Text(w.summaryText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No workouts in last 24h")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                    // Vitals & Daily Steps
                    if let vitals = snapshot?.vitals {
                        HStack(spacing: 8) {
                            vitalMetric(
                                icon: "flame.fill",
                                title: "Active Cal",
                                value: "\(Int(vitals.activeEnergyBurnedKCal)) kcal",
                                color: .orange
                            )
                            vitalMetric(
                                icon: "figure.walk",
                                title: "Steps",
                                value: "\(vitals.stepCountToday.formatted())",
                                color: .blue
                            )
                            vitalMetric(
                                icon: "heart.fill",
                                title: "Resting HR",
                                value: vitals.restingHeartRateBPM.map { "\(Int($0)) bpm" } ?? "--",
                                color: .red
                            )
                            vitalMetric(
                                icon: "waveform.path.ecg",
                                title: "HRV (Recovery)",
                                value: vitals.heartRateVariabilitySDNN.map { "\(Int($0)) ms" } ?? "--",
                                color: .purple
                            )
                        }
                    }

                    // Conversational Prompt Preview for Hermes
                    if let openers = snapshot?.conversationalContext.suggestedOpeners, !openers.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Hermes Conversational Insight", systemImage: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.pink)

                            Text("\"\(openers.first!)\"")
                                .font(.caption2)
                                .italic()
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.pink.opacity(0.06))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    private func vitalMetric(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.primary)
            Text(title)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func sleepQualityColor(_ rating: SleepQualityRating) -> Color {
        switch rating {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        case .unknown: return .gray
        }
    }
}

import SwiftUI

struct HealthDetailView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: EditorialSpacing.section) {
                    EditorialPageHeader(
                        index: "HERMES / HEALTH 02",
                        title: "Health\nArchive",
                        subtitle: "Your latest Apple Health snapshot, kept private and shared through your personal iCloud archive."
                    )

                    HealthOverviewCard()

                    if let snapshot = healthKitManager.latestSnapshot {
                        SleepDetailSection(sleep: snapshot.sleep)
                        ActivityDetailSection(snapshot: snapshot)
                        WorkoutDetailSection(
                            workout: snapshot.activeWorkout ?? snapshot.latestWorkout
                        )
                    }

                    if let refreshedAt = healthKitManager.lastRefreshedAt {
                        Text("LAST HEALTH UPDATE / \(refreshedAt.formatted(.dateTime.year().month().day().hour().minute()))")
                            .font(.editorialUtilitySmall)
                            .foregroundStyle(EditorialColor.secondaryInk)
                    }
                }
                .padding(.horizontal, EditorialSpacing.page)
                .padding(.top, EditorialSpacing.large)
                .padding(.bottom, EditorialSpacing.hero)
            }
            .background(EditorialColor.paper)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct SleepDetailSection: View {
    let sleep: SleepRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#02", title: "SLEEP", trailing: "LAST SESSION")

            if let sleep {
                VStack(spacing: 0) {
                    HealthDetailRow(label: "TOTAL SLEEP", value: sleep.formattedDuration)
                    EditorialRule()
                    HealthDetailRow(label: "DEEP", value: duration(minutes: sleep.deepSleepMinutes))
                    EditorialRule()
                    HealthDetailRow(label: "REM", value: duration(minutes: sleep.remSleepMinutes))
                    EditorialRule()
                    HealthDetailRow(label: "CORE", value: duration(minutes: sleep.coreSleepMinutes))
                    EditorialRule()
                    HealthDetailRow(label: "AWAKE", value: duration(minutes: sleep.awakeMinutes))
                    if let bedtime = sleep.bedtime {
                        EditorialRule()
                        HealthDetailRow(
                            label: "BEDTIME",
                            value: bedtime.formatted(.dateTime.weekday().hour().minute())
                        )
                    }
                    if let wakeTime = sleep.wakeTime {
                        EditorialRule()
                        HealthDetailRow(
                            label: "WAKE TIME",
                            value: wakeTime.formatted(.dateTime.weekday().hour().minute())
                        )
                    }
                }
                .overlay {
                    Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
                }
            } else {
                Text("No recent sleep session is available from Apple Health.")
                    .font(.body)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }
        }
        .editorialPanel()
    }

    private func duration(minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct ActivityDetailSection: View {
    let snapshot: HealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#03", title: "VITALS", trailing: "LATEST AVAILABLE")

            VStack(spacing: 0) {
                HealthDetailRow(
                    label: "STEPS TODAY",
                    value: snapshot.vitals.stepCountToday.formatted()
                )
                EditorialRule()
                HealthDetailRow(
                    label: "ACTIVE ENERGY",
                    value: "\(Int(snapshot.vitals.activeEnergyBurnedKCal.rounded()).formatted()) kcal"
                )
                EditorialRule()
                HealthDetailRow(
                    label: "RESTING HEART RATE",
                    value: snapshot.vitals.restingHeartRateBPM.map { "\(Int($0.rounded())) bpm" } ?? "—"
                )
                EditorialRule()
                HealthDetailRow(
                    label: "LATEST HEART RATE",
                    value: snapshot.vitals.currentHeartRateBPM.map { "\(Int($0.rounded())) bpm" } ?? "—"
                )
                EditorialRule()
                HealthDetailRow(
                    label: "HEART RATE VARIABILITY",
                    value: snapshot.vitals.heartRateVariabilitySDNN.map { "\(Int($0.rounded())) ms" } ?? "—"
                )
            }
            .overlay {
                Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
            }

            Text("Heart measurements are wellness context from Apple Health, not a medical diagnosis.")
                .font(.footnote)
                .foregroundStyle(EditorialColor.secondaryInk)
        }
        .editorialPanel()
    }
}

private struct WorkoutDetailSection: View {
    let workout: WorkoutRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#04", title: "WORKOUT", trailing: "LATEST 24 HOURS")

            if let workout {
                VStack(spacing: 0) {
                    HealthDetailRow(label: "ACTIVITY", value: workout.workoutType)
                    EditorialRule()
                    HealthDetailRow(label: "DURATION", value: "\(workout.durationMinutes) min")
                    EditorialRule()
                    HealthDetailRow(
                        label: "ACTIVE ENERGY",
                        value: "\(Int(workout.activeCalories.rounded()).formatted()) kcal"
                    )
                    if let averageHeartRate = workout.averageHeartRateBPM {
                        EditorialRule()
                        HealthDetailRow(
                            label: "AVERAGE HEART RATE",
                            value: "\(Int(averageHeartRate.rounded())) bpm"
                        )
                    }
                    EditorialRule()
                    HealthDetailRow(
                        label: "STATUS",
                        value: workout.isCurrentlyActive ? "Active now" : workout.endDate.formatted(.relative(presentation: .named))
                    )
                }
                .overlay {
                    Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
                }
            } else {
                Text("No workout has been recorded in the last 24 hours.")
                    .font(.body)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }
        }
        .editorialPanel(cutCorner: true)
    }
}

private struct HealthDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: EditorialSpacing.compact) {
                Text(label)
                    .font(.editorialUtilitySmall)
                Spacer(minLength: EditorialSpacing.medium)
                Text(value)
                    .font(.body)
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                Text(label)
                    .font(.editorialUtilitySmall)
                Text(value)
                    .font(.body)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }
        }
        .padding(EditorialSpacing.compact)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HealthDetailView()
        .environmentObject(LocationManager.shared)
        .environmentObject(CloudKitSyncManager.shared)
        .environmentObject(HealthKitManager.shared)
}

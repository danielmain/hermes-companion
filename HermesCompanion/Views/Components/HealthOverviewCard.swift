import SwiftUI
import HealthKit

public struct HealthOverviewCard: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#01", title: "TODAY'S HEALTH", trailing: authorizationLabel)

            if healthKitManager.authorizationStatus == .accessRequested {
                AuthorizedHealthContent(
                    snapshot: healthKitManager.latestSnapshot,
                    isRefreshing: healthKitManager.isQuerying,
                    refreshAction: refresh
                )
            } else {
                HealthAuthorizationContent(connectAction: requestAuthorization)
            }
        }
        .editorialPanel(cutCorner: true)
        .task(id: healthKitManager.authorizationStatus) {
            if healthKitManager.authorizationStatus == .accessRequested,
               healthKitManager.latestSnapshot == nil,
               !healthKitManager.isQuerying {
                refresh()
            }
        }
    }

    private var authorizationLabel: String {
        healthKitManager.authorizationStatus == .accessRequested ? "REQUESTED" : "OPTIONAL"
    }

    private func requestAuthorization() {
        healthKitManager.requestAuthorization { success, _ in
            if success {
                refresh()
            }
        }
    }

    private func refresh() {
        healthKitManager.refreshHealthSnapshot { result in
            if case .success(let snapshot) = result {
                cloudKitSyncManager.syncHealthRecord(
                    config: locationManager.configuration,
                    snapshot: snapshot
                )
            }
        }
    }
}

private struct HealthAuthorizationContent: View {
    let connectAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            Text("A private record of rest, movement, and recovery can accompany your location archive.")
                .font(.body)
                .foregroundStyle(EditorialColor.secondaryInk)

            Button(action: connectAction) {
                Label("CONNECT APPLE HEALTH", systemImage: "heart.text.square")
            }
            .buttonStyle(EditorialButtonStyle(isPrimary: true))
        }
    }
}

private struct AuthorizedHealthContent: View {
    let snapshot: HealthSnapshot?
    let isRefreshing: Bool
    let refreshAction: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            if isRefreshing {
                EditorialLoadingState(message: "READING HEALTH ARCHIVE")
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: EditorialSpacing.small) {
                HealthMetric(
                    index: "01",
                    label: "SLEEP",
                    value: snapshot?.sleep?.formattedDuration ?? "—",
                    detail: snapshot?.sleep?.qualityRating.title ?? "No recent record"
                )

                HealthMetric(
                    index: "02",
                    label: "STEPS",
                    value: snapshot?.vitals.stepCountToday.formatted() ?? "—",
                    detail: "Today"
                )

                HealthMetric(
                    index: "03",
                    label: "ACTIVE ENERGY",
                    value: snapshot.map { "\(Int($0.vitals.activeEnergyBurnedKCal.rounded()).formatted())" } ?? "—",
                    detail: "Kilocalories today"
                )

                HealthMetric(
                    index: "04",
                    label: "RESTING HR",
                    value: snapshot?.vitals.restingHeartRateBPM.map { "\(Int($0.rounded()))" } ?? "—",
                    detail: "Beats per minute"
                )
            }

            if let workout = snapshot?.activeWorkout ?? snapshot?.latestWorkout {
                HStack(alignment: .top, spacing: EditorialSpacing.compact) {
                    Image(systemName: workout.isCurrentlyActive ? "figure.run" : "checkmark")
                        .font(.body.weight(.light))
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                        Text(workout.isCurrentlyActive ? "WORKOUT ACTIVE" : "LATEST WORKOUT")
                            .font(.editorialUtilitySmall)
                            .foregroundStyle(EditorialColor.secondaryInk)
                        Text("\(workout.workoutType) · \(workout.durationMinutes) min")
                            .font(.body)
                            .foregroundStyle(EditorialColor.ink)
                    }

                    Spacer()
                }
                .padding(EditorialSpacing.compact)
                .overlay {
                    Rectangle().stroke(EditorialColor.faintHairline, lineWidth: EditorialBorder.hairline)
                }
                .accessibilityElement(children: .combine)
            }

            if let insight = snapshot?.conversationalContext.suggestedOpeners.first {
                VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                    Text("HERMES / CONTEXT NOTE")
                        .font(.editorialUtilitySmall)
                    Text("“\(insight)”")
                        .font(.body)
                        .italic()
                        .foregroundStyle(EditorialColor.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EditorialSpacing.compact)
                .overlay {
                    Rectangle().stroke(EditorialColor.faintHairline, lineWidth: EditorialBorder.hairline)
                }
            }

            Button(action: refreshAction) {
                Label(isRefreshing ? "READING…" : "REFRESH HEALTH ARCHIVE", systemImage: "arrow.clockwise")
            }
            .buttonStyle(EditorialButtonStyle(isPrimary: false))
            .disabled(isRefreshing)
        }
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : (horizontalSizeClass == .regular ? 3 : 2)
        return Array(
            repeating: GridItem(.flexible(), spacing: EditorialSpacing.small),
            count: count
        )
    }
}

private struct HealthMetric: View {
    let index: String
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            HStack {
                Text(index)
                Spacer()
                Text(label)
            }
            .font(.editorialUtilitySmall)
            .foregroundStyle(EditorialColor.secondaryInk)

            Text(value)
                .font(.title3)
                .foregroundStyle(EditorialColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.caption)
                .foregroundStyle(EditorialColor.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(EditorialSpacing.compact)
        .overlay {
            Rectangle().stroke(EditorialColor.faintHairline, lineWidth: EditorialBorder.hairline)
        }
        .accessibilityElement(children: .combine)
    }
}

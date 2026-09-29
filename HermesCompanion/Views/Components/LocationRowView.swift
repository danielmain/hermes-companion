import SwiftUI

struct LocationRowView: View {
    let record: LocationRecord

    var body: some View {
        HStack(spacing: 12) {
            // Source icon
            ZStack {
                Circle()
                    .fill(sourceColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: record.source.systemIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(sourceColor)
            }

            // Main Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.source.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    if record.source == .wakeFromTerminated {
                        Text("CLOSED WAKE")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer()

                    Text(timeString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text("\(String(format: "%.4f", record.latitude)), \(String(format: "%.4f", record.longitude))")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Label(record.formattedAccuracy, systemImage: "scope")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    if record.speed >= 0 {
                        Label(record.formattedSpeed, systemImage: "speedometer")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    if record.batteryLevel >= 0 {
                        Label("\(Int(record.batteryLevel * 100))%", systemImage: "battery.100")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if record.synced {
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: record.timestamp)
    }

    private var sourceColor: Color {
        switch record.source {
        case .wakeFromTerminated: return .red
        case .significantChange: return .orange
        case .visitArrival, .visitDeparture: return .purple
        case .geofenceExit, .geofenceEnter: return .mint
        case .standardGPS: return .blue
        case .manualPing: return .indigo
        case .backgroundFetch: return .teal
        }
    }
}

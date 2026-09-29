import SwiftUI

struct HistoryLogView: View {
    @EnvironmentObject private var locationStore: LocationStore
    @State private var selectedTab: Int = 0
    @State private var filterSource: LocationTriggerSource? = nil
    @State private var showingClearAlert: Bool = false
    @State private var exportURL: URL? = nil
    @State private var showingShareSheet: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segment Picker
                Picker("View", selection: $selectedTab) {
                    Text("Locations (\(filteredRecords.count))").tag(0)
                    Text("System Log (\(locationStore.diagnostics.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    // Filter Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "All", isSelected: filterSource == nil) {
                                filterSource = nil
                            }

                            ForEach(LocationTriggerSource.allCases) { source in
                                FilterChip(
                                    title: source.rawValue,
                                    icon: source.systemIcon,
                                    isSelected: filterSource == source
                                ) {
                                    filterSource = (filterSource == source) ? nil : source
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }

                    // Locations List
                    if filteredRecords.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "tray")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No location records found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(filteredRecords) { record in
                                LocationRowView(record: record)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                } else {
                    // System Diagnostic Log List
                    if locationStore.diagnostics.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "text.badge.checkmark")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No system logs yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(locationStore.diagnostics) { event in
                                DiagnosticRowView(event: event)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("History & Logs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(action: { export(format: .gpx) }) {
                            Label("Export GPX Track", systemImage: "map")
                        }
                        Button(action: { export(format: .geoJSON) }) {
                            Label("Export GeoJSON", systemImage: "curlybraces")
                        }
                        Button(action: { export(format: .csv) }) {
                            Label("Export CSV Table", systemImage: "tablecells")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive, action: { showingClearAlert = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .alert("Clear Data", isPresented: $showingClearAlert) {
                Button("Clear Locations Only", role: .destructive) {
                    locationStore.clearAllRecords()
                }
                Button("Clear System Logs Only", role: .destructive) {
                    locationStore.clearDiagnostics()
                }
                Button("Clear All", role: .destructive) {
                    locationStore.clearAllRecords()
                    locationStore.clearDiagnostics()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to clear stored location history or diagnostics?")
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    private var filteredRecords: [LocationRecord] {
        if let filter = filterSource {
            return locationStore.records.filter { $0.source == filter }
        }
        return locationStore.records
    }

    enum ExportFormat {
        case gpx, geoJSON, csv
    }

    private func export(format: ExportFormat) {
        switch format {
        case .gpx:
            exportURL = locationStore.exportGPX()
        case .geoJSON:
            exportURL = locationStore.exportGeoJSON()
        case .csv:
            exportURL = locationStore.exportCSV()
        }
        if exportURL != nil {
            showingShareSheet = true
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.04), radius: 2)
        }
    }
}

// MARK: - Diagnostic Row
struct DiagnosticRowView: View {
    let event: AppDiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.severity.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(severityColor.opacity(0.15))
                    .foregroundColor(severityColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !event.details.isEmpty {
                Text(event.details)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .short
        return formatter.string(from: event.timestamp)
    }

    private var severityColor: Color {
        switch event.severity {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - ShareSheet Helper
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

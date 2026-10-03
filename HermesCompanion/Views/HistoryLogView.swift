import SwiftUI
import MapKit

struct HistoryLogView: View {
    @EnvironmentObject private var locationStore: LocationStore
    @State private var mode: HistoryMode = .locations
    @State private var filterSource: LocationTriggerSource?
    @State private var searchText = ""
    @State private var showingClearAlert = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HistoryHeader(mode: $mode)

                if mode == .locations {
                    HistoryFilterBar(selection: $filterSource)
                    locationArchive
                } else {
                    diagnosticArchive
                }
            }
            .background(EditorialColor.paper)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search the archive")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    exportMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingClearAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(EditorialIconButtonStyle())
                    .accessibilityLabel("Clear archive")
                }
            }
            .alert("Clear Archive", isPresented: $showingClearAlert) {
                Button("Clear Locations", role: .destructive) {
                    locationStore.clearAllRecords()
                }
                Button("Clear System Log", role: .destructive) {
                    locationStore.clearDiagnostics()
                }
                Button("Clear Everything", role: .destructive) {
                    locationStore.clearAllRecords()
                    locationStore.clearDiagnostics()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose which locally stored records to remove. This cannot be undone.")
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(activityItems: [url])
            }
        }
    }

    private var locationArchive: some View {
        Group {
            if filteredRecords.isEmpty {
                ScrollView {
                    EditorialEmptyState(
                        index: "ARCHIVE / 000",
                        title: searchText.isEmpty ? "No signals" : "No match",
                        message: searchText.isEmpty
                            ? "Captured locations will be indexed here."
                            : "The archive contains no location matching this query.",
                        systemImage: "archivebox"
                    )
                    .padding(EditorialSpacing.page)
                }
            } else {
                List(filteredRecords) { record in
                    NavigationLink {
                        LocationDetailView(record: record)
                    } label: {
                        LocationRowView(record: record)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(EditorialColor.paper)
                    .listRowSeparatorTint(EditorialColor.hairline)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var diagnosticArchive: some View {
        Group {
            if filteredDiagnostics.isEmpty {
                ScrollView {
                    EditorialEmptyState(
                        index: "SYSTEM LOG / 000",
                        title: searchText.isEmpty ? "No entries" : "No match",
                        message: searchText.isEmpty
                            ? "Runtime notices and exceptions will appear here."
                            : "The system log contains no entry matching this query.",
                        systemImage: "terminal"
                    )
                    .padding(EditorialSpacing.page)
                }
            } else {
                List(filteredDiagnostics) { event in
                    DiagnosticRowView(event: event)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(EditorialColor.paper)
                        .listRowSeparatorTint(EditorialColor.hairline)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            Button {
                exportURL = locationStore.exportGPX()
            } label: {
                Label("Export GPX Track", systemImage: "map")
            }
            Button {
                exportURL = locationStore.exportGeoJSON()
            } label: {
                Label("Export GeoJSON", systemImage: "curlybraces")
            }
            Button {
                exportURL = locationStore.exportCSV()
            } label: {
                Label("Export CSV Table", systemImage: "tablecells")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(EditorialIconButtonStyle())
        .accessibilityLabel("Export archive")
    }

    private var filteredRecords: [LocationRecord] {
        locationStore.records.filter { record in
            let matchesSource = filterSource == nil || record.source == filterSource
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || record.source.rawValue.localizedCaseInsensitiveContains(query)
                || String(record.latitude).localizedCaseInsensitiveContains(query)
                || String(record.longitude).localizedCaseInsensitiveContains(query)
            return matchesSource && matchesSearch
        }
    }

    private var filteredDiagnostics: [AppDiagnosticEvent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return locationStore.diagnostics }
        return locationStore.diagnostics.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.details.localizedCaseInsensitiveContains(query)
                || $0.severity.rawValue.localizedCaseInsensitiveContains(query)
        }
    }
}

private enum HistoryMode: String, CaseIterable, Identifiable {
    case locations = "LOCATIONS"
    case system = "SYSTEM LOG"

    var id: String { rawValue }
}

private struct HistoryHeader: View {
    @Binding var mode: HistoryMode

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.large) {
            EditorialPageHeader(
                index: "HERMES / ARCHIVE 02",
                title: "Recorded\nSignals",
                subtitle: "A chronological register of field positions and system events."
            )

            HStack(spacing: 0) {
                ForEach(HistoryMode.allCases) { item in
                    Button {
                        mode = item
                    } label: {
                        Text(item.rawValue)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EditorialButtonStyle(isPrimary: mode == item))
                    .accessibilityValue(mode == item ? "Selected" : "Not selected")
                }
            }
        }
        .padding(.horizontal, EditorialSpacing.page)
        .padding(.top, EditorialSpacing.large)
        .padding(.bottom, EditorialSpacing.medium)
    }
}

private struct HistoryFilterBar: View {
    @Binding var selection: LocationTriggerSource?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: EditorialSpacing.small) {
                FilterChip(title: "ALL", isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(LocationTriggerSource.allCases) { source in
                    FilterChip(
                        title: source.rawValue.uppercased(),
                        icon: source.systemIcon,
                        isSelected: selection == source
                    ) {
                        selection = selection == source ? nil : source
                    }
                }
            }
            .padding(.horizontal, EditorialSpacing.page)
            .padding(.vertical, EditorialSpacing.small)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            EditorialRule()
        }
    }
}

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EditorialSpacing.xSmall) {
                if let icon {
                    Image(systemName: icon)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(.editorialUtilitySmall)
            .padding(.horizontal, EditorialSpacing.compact)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? EditorialColor.paper : EditorialColor.ink)
            .background(isSelected ? EditorialColor.ink : EditorialColor.paper)
            .overlay {
                Rectangle().stroke(EditorialColor.ink, lineWidth: EditorialBorder.hairline)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct DiagnosticRowView: View {
    let event: AppDiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    severity
                    Text(event.title)
                        .font(.headline)
                    Spacer()
                    timestamp
                }

                VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                    HStack {
                        severity
                        Spacer()
                        timestamp
                    }
                    Text(event.title)
                        .font(.headline)
                }
            }

            if !event.details.isEmpty {
                Text(event.details)
                    .font(.body)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }
        }
        .padding(EditorialSpacing.medium)
        .accessibilityElement(children: .combine)
    }

    private var severity: some View {
        EditorialStatusToken(
            text: event.severity.rawValue.uppercased(),
            isInverted: event.severity == .error || event.severity == .warning
        )
    }

    private var timestamp: some View {
        Text(event.timestamp, format: .dateTime.month().day().hour().minute().second())
            .font(.editorialUtilitySmall)
            .foregroundStyle(EditorialColor.secondaryInk)
    }
}

private struct LocationDetailView: View {
    let record: LocationRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorialSpacing.section) {
                EditorialPageHeader(
                    index: "FIELD RECORD / \(record.timestamp.formatted(.dateTime.year().month().day()))",
                    title: "Signal\nDetail",
                    subtitle: record.source.rawValue
                )

                DetailCoordinateSection(record: record)
                DetailMetadataSection(record: record)
            }
            .padding(EditorialSpacing.page)
        }
        .background(EditorialColor.paper)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DetailCoordinateSection: View {
    let record: LocationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            EditorialSectionHeader(index: "#01", title: "POSITION", trailing: "APPLE MAPS")

            AppleMapsPreviewFrame(record: record) {
                openInAppleMaps()
            }

            VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                Text("\(record.latitude, format: .number.precision(.fractionLength(6)))")
                    .font(.editorialNumber)
                Text("\(record.longitude, format: .number.precision(.fractionLength(6)))")
                    .font(.editorialNumber)
                Text("LATITUDE / LONGITUDE")
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }

            Button {
                openInAppleMaps()
            } label: {
                HStack(spacing: EditorialSpacing.small) {
                    Image(systemName: "map")
                    Text("OPEN IN APPLE MAPS")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.editorialUtilitySmall)
                .padding(EditorialSpacing.small)
                .background(EditorialColor.paper)
                .foregroundStyle(EditorialColor.ink)
                .overlay {
                    Rectangle().stroke(EditorialColor.ink, lineWidth: EditorialBorder.hairline)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open coordinates in Apple Maps")
        }
        .editorialPanel(emphasized: true, cutCorner: true)
    }

    private func openInAppleMaps() {
        let coordinate = record.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "\(record.source.rawValue) Signal"

        LocationStore.shared.logDiagnostic(
            title: "Apple Maps Opened",
            details: "Signal at \(record.latitude), \(record.longitude) opened in Maps.",
            severity: .info
        )

        let opened = mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
        ])

        if !opened {
            if let url = URL(string: "https://maps.apple.com/?ll=\(record.latitude),\(record.longitude)&q=\(record.latitude),\(record.longitude)") {
                UIApplication.shared.open(url)
            }
        }
    }
}

private struct AppleMapsPreviewFrame: View {
    let record: LocationRecord
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                if CLLocationCoordinate2DIsValid(record.coordinate) && (record.latitude != 0 || record.longitude != 0) {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: record.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                    ))) {
                        Marker(
                            record.source.rawValue,
                            coordinate: record.coordinate
                        )
                        .tint(EditorialColor.ink)
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .frame(height: 160)
                    .clipShape(CutCornerShape(cut: 10))
                    .overlay {
                        CutCornerShape(cut: 10)
                            .stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
                    }
                    .allowsHitTesting(false)
                } else {
                    Rectangle()
                        .fill(EditorialColor.surface)
                        .frame(height: 160)
                        .clipShape(CutCornerShape(cut: 10))
                        .overlay {
                            Text("COORDINATES UNAVAILABLE")
                                .font(.editorialUtilitySmall)
                                .foregroundStyle(EditorialColor.secondaryInk)
                        }
                }

                HStack(spacing: EditorialSpacing.xSmall) {
                    Image(systemName: "arrow.up.right.square")
                        .imageScale(.small)
                    Text("OPEN IN MAPS")
                        .font(.editorialUtilitySmall)
                }
                .padding(.horizontal, EditorialSpacing.small)
                .padding(.vertical, EditorialSpacing.xSmall)
                .background(EditorialColor.paper.opacity(0.92))
                .foregroundStyle(EditorialColor.ink)
                .overlay {
                    Rectangle().stroke(EditorialColor.ink, lineWidth: EditorialBorder.hairline)
                }
                .padding(EditorialSpacing.small)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open signal location in Apple Maps")
        .accessibilityHint("Opens Apple Maps centered at this recorded coordinate")
    }
}

private struct DetailMetadataSection: View {
    let record: LocationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSectionHeader(index: "#02", title: "INSTRUMENT DATA")
                .padding(.bottom, EditorialSpacing.medium)

            DetailRow(label: "CAPTURED", value: record.timestamp.formatted(.dateTime.year().month().day().hour().minute().second()))
            DetailRow(label: "ACCURACY", value: record.formattedAccuracy)
            DetailRow(label: "ALTITUDE", value: record.altitude.formatted(.number.precision(.fractionLength(1))) + " m")
            DetailRow(label: "APP STATE", value: record.appState)
            DetailRow(label: "ARCHIVE", value: record.synced ? "Filed in iCloud" : "Queued locally")
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
                Spacer(minLength: EditorialSpacing.medium)
                Text(value)
                    .font(.body)
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                Text(label)
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
                Text(value)
                    .font(.body)
            }
        }
        .padding(.vertical, EditorialSpacing.compact)
        .overlay(alignment: .bottom) {
            EditorialRule()
        }
        .accessibilityElement(children: .combine)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

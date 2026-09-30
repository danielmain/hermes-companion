import Foundation
import CoreLocation
import os

public final class LocationStore: ObservableObject {
    public static let shared = LocationStore()

    @Published public private(set) var records: [LocationRecord] = []
    @Published public private(set) var diagnostics: [AppDiagnosticEvent] = []

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.hermes.locationstore", qos: .utility)
    private let logger = Logger(subsystem: "com.hermes.HermesCompanion", category: "LocationStore")

    private var recordsFileURL: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("location_records.json")
    }

    private var diagnosticsFileURL: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.json")
    }

    private init() {
        loadData()
    }

    private func loadData() {
        queue.async { [weak self] in
            guard let self = self else { return }

            var loadedRecords: [LocationRecord] = []
            var loadedDiagnostics: [AppDiagnosticEvent] = []

            if let data = try? Data(contentsOf: self.recordsFileURL),
               let decoded = try? JSONDecoder().decode([LocationRecord].self, from: data) {
                loadedRecords = decoded
            }

            if let data = try? Data(contentsOf: self.diagnosticsFileURL),
               let decoded = try? JSONDecoder().decode([AppDiagnosticEvent].self, from: data) {
                loadedDiagnostics = decoded
            }

            DispatchQueue.main.async {
                self.records = loadedRecords
                self.diagnostics = loadedDiagnostics
            }
        }
    }

    /// Persists a GPS record only when the coordinate has actually moved.
    /// Returns `false` when the latest stored position is unchanged (no record appended, no file touched).
    @discardableResult
    public func saveRecord(
        _ record: LocationRecord,
        minDisplacementMeters: Double = LocationRecord.unchangedPositionThresholdMeters
    ) -> Bool {
        let persistOnMain: () -> Bool = {
            if let last = self.records.first,
               record.isUnchangedPosition(from: last, thresholdMeters: minDisplacementMeters) {
                let displacement = LocationRecord.displacementMeters(from: last.coordinate, to: record.coordinate)
                self.logger.info("Skipped GPS record persist: displacement \(displacement, format: .fixed(precision: 1))m is below \(minDisplacementMeters, format: .fixed(precision: 1))m threshold")
                return false
            }
            self.records.insert(record, at: 0)
            if self.records.count > 1000 {
                self.records.removeLast(self.records.count - 1000)
            }
            return true
        }

        let saved: Bool
        if Thread.isMainThread {
            saved = persistOnMain()
        } else {
            saved = DispatchQueue.main.sync(execute: persistOnMain)
        }
        guard saved else { return false }

        queue.async { [weak self] in
            guard let self = self else { return }
            var currentRecords: [LocationRecord] = []
            DispatchQueue.main.sync {
                currentRecords = self.records
            }
            if let data = try? JSONEncoder().encode(currentRecords) {
                try? data.write(to: self.recordsFileURL, options: .atomic)
            }
        }
        return true
    }

    public func markSynced(ids: Set<UUID>) {
        DispatchQueue.main.async {
            for i in 0..<self.records.count {
                if ids.contains(self.records[i].id) {
                    self.records[i].synced = true
                }
            }
        }
        queue.async { [weak self] in
            guard let self = self else { return }
            var currentRecords: [LocationRecord] = []
            DispatchQueue.main.sync {
                currentRecords = self.records
            }
            if let data = try? JSONEncoder().encode(currentRecords) {
                try? data.write(to: self.recordsFileURL, options: .atomic)
            }
        }
    }

    public func logDiagnostic(title: String, details: String = "", severity: DiagnosticSeverity = .info) {
        let event = AppDiagnosticEvent(title: title, details: details, severity: severity)
        DispatchQueue.main.async {
            self.diagnostics.insert(event, at: 0)
            if self.diagnostics.count > 300 {
                self.diagnostics.removeLast(self.diagnostics.count - 300)
            }
        }

        queue.async { [weak self] in
            guard let self = self else { return }
            var currentDiag: [AppDiagnosticEvent] = []
            DispatchQueue.main.sync {
                currentDiag = self.diagnostics
            }
            if let data = try? JSONEncoder().encode(currentDiag) {
                try? data.write(to: self.diagnosticsFileURL, options: .atomic)
            }
        }
    }

    public func clearAllRecords() {
        DispatchQueue.main.async {
            self.records.removeAll()
        }
        queue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.recordsFileURL)
        }
        logDiagnostic(title: "Location History Cleared", severity: .warning)
    }

    public func clearDiagnostics() {
        DispatchQueue.main.async {
            self.diagnostics.removeAll()
        }
        queue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.diagnosticsFileURL)
        }
    }

    // Export formats
    public func exportGPX() -> URL? {
        let points = records.reversed()
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Hermes Companion iOS" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Hermes Companion Track</name>
            <trkseg>

        """
        let isoFormatter = ISO8601DateFormatter()
        for p in points {
            xml += "      <trkpt lat=\"\(p.latitude)\" lon=\"\(p.longitude)\">\n"
            xml += "        <ele>\(p.altitude)</ele>\n"
            xml += "        <time>\(isoFormatter.string(from: p.timestamp))</time>\n"
            xml += "        <desc>Source: \(p.source.rawValue), Accuracy: \(p.formattedAccuracy)</desc>\n"
            xml += "      </trkpt>\n"
        }
        xml += """
            </trkseg>
          </trk>
        </gpx>
        """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("hermes_track_\(Date().timeIntervalSince1970).gpx")
        do {
            try xml.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }

    public func exportGeoJSON() -> URL? {
        let points = records.reversed()
        var features: [[String: Any]] = []

        let isoFormatter = ISO8601DateFormatter()
        for p in points {
            let feature: [String: Any] = [
                "type": "Feature",
                "geometry": [
                    "type": "Point",
                    "coordinates": [p.longitude, p.latitude, p.altitude]
                ],
                "properties": [
                    "timestamp": isoFormatter.string(from: p.timestamp),
                    "source": p.source.rawValue,
                    "accuracy": p.horizontalAccuracy,
                    "speed": p.speedKmH,
                    "battery": p.batteryLevel,
                    "appState": p.appState
                ]
            ]
            features.append(feature)
        }

        let geoJSON: [String: Any] = [
            "type": "FeatureCollection",
            "features": features
        ]

        if let data = try? JSONSerialization.data(withJSONObject: geoJSON, options: [.prettyPrinted]) {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("hermes_locations_\(Date().timeIntervalSince1970).geojson")
            try? data.write(to: tempURL)
            return tempURL
        }
        return nil
    }

    public func exportCSV() -> URL? {
        var csv = "timestamp,latitude,longitude,altitude,accuracy,speed_kmh,source,battery_percent,app_state\n"
        let isoFormatter = ISO8601DateFormatter()
        for p in records {
            let line = "\(isoFormatter.string(from: p.timestamp)),\(p.latitude),\(p.longitude),\(p.altitude),\(p.horizontalAccuracy),\(p.speedKmH),\(p.source.rawValue),\(Int(p.batteryLevel * 100)),\(p.appState)\n"
            csv += line
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("hermes_locations_\(Date().timeIntervalSince1970).csv")
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }
}

import Foundation
import CoreLocation
import os

public final class PlacesStore: ObservableObject {
    public static let shared = PlacesStore()

    @Published public private(set) var places: [Place] = []

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.hermes.placesstore", qos: .utility)
    private let logger = Logger(subsystem: "com.hermes.HermesCompanion", category: "PlacesStore")

    private var localFileURL: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("places.json")
    }

    private var iCloudPlacesURL: URL? {
        let containerId = TrackingConfiguration.defaultContainerIdentifier
        let containerURL = fileManager.url(forUbiquityContainerIdentifier: containerId) ?? fileManager.url(forUbiquityContainerIdentifier: nil)
        guard let containerURL = containerURL else { return nil }
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        return documentsURL.appendingPathComponent("places.json")
    }

    private init() {
        loadPlacesSynchronously()
    }

    private func loadPlacesSynchronously() {
        var loaded: [Place] = []

        // 1. Try reading from local Application Support
        if let data = try? Data(contentsOf: localFileURL),
           let decoded = try? JSONDecoder().decode([Place].self, from: data) {
            loaded = decoded
        }

        // 2. If empty or iCloud is present, check iCloud Documents/places.json
        if let iCloudURL = iCloudPlacesURL, fileManager.fileExists(atPath: iCloudURL.path) {
            if let data = try? Data(contentsOf: iCloudURL),
               let iCloudPlaces = try? JSONDecoder().decode([Place].self, from: data) {
                // If local was empty, use iCloud
                if loaded.isEmpty {
                    loaded = iCloudPlaces
                } else {
                    // Merge by ID
                    let existingIds = Set(loaded.map { $0.id })
                    let incomingNew = iCloudPlaces.filter { !existingIds.contains($0.id) }
                    loaded.append(contentsOf: incomingNew)
                }
            }
        }

        self.places = loaded
        logger.info("Loaded \(loaded.count) known places")
    }

    // MARK: - Functional Actions

    public func addPlace(_ place: Place) {
        let updated: [Place]
        if let index = places.firstIndex(where: { $0.id == place.id || $0.name.lowercased() == place.name.lowercased() }) {
            var mutable = places
            mutable[index] = place
            updated = mutable
        } else {
            updated = places + [place]
        }

        self.places = updated
        persistPlaces(updated)
        logger.info("Saved place: \(place.name) (\(place.category.label))")
    }

    public func deletePlace(id: String) {
        let updated = places.filter { $0.id != id }
        guard updated.count != places.count else { return }

        self.places = updated
        persistPlaces(updated)
        logger.info("Deleted place id: \(id)")
    }

    public func match(coordinate: CLLocationCoordinate2D) -> Place? {
        let matches = places.compactMap { place -> (Double, Place)? in
            let dist = place.distanceMeters(from: coordinate)
            return dist <= place.radiusMeters ? (dist, place) : nil
        }
        return matches.min(by: { $0.0 < $1.0 })?.1
    }

    private func persistPlaces(_ placesToSave: [Place]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? JSONEncoder().encode(placesToSave) else { return }

            // Write local cache
            try? data.write(to: self.localFileURL, options: .atomic)

            // Write to iCloud container Documents/places.json
            if let iCloudURL = self.iCloudPlacesURL {
                try? self.fileManager.createDirectory(at: iCloudURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: iCloudURL, options: .atomic)
            }
        }
    }
}

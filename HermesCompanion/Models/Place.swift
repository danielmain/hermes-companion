import Foundation
import CoreLocation

public struct PlaceCategory: RawRepresentable, Codable, Hashable, Identifiable, ExpressibleByStringLiteral, CustomStringConvertible, CaseIterable {
    public let rawValue: String

    public init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.rawValue = trimmed.isEmpty ? "general" : trimmed
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var id: String { rawValue }
    public var description: String { rawValue }

    public static let home = PlaceCategory(rawValue: "home")
    public static let work = PlaceCategory(rawValue: "work")
    public static let gym = PlaceCategory(rawValue: "gym")
    public static let cafe = PlaceCategory(rawValue: "cafe")
    public static let outdoors = PlaceCategory(rawValue: "outdoors")
    public static let park = PlaceCategory(rawValue: "park")
    public static let school = PlaceCategory(rawValue: "school")
    public static let shop = PlaceCategory(rawValue: "shop")
    public static let transit = PlaceCategory(rawValue: "transit")
    public static let general = PlaceCategory(rawValue: "general")

    public static let presets: [PlaceCategory] = [
        .home, .work, .gym, .cafe, .outdoors, .park, .school, .shop, .transit, .general
    ]

    public static var allCases: [PlaceCategory] { presets }

    public var label: String {
        switch rawValue {
        case "home": return "Home"
        case "work": return "Work"
        case "gym": return "Gym"
        case "cafe": return "Café"
        case "outdoors": return "Outdoors"
        case "park": return "Park"
        case "school": return "School"
        case "shop": return "Shop"
        case "transit": return "Transit"
        case "general": return "General"
        default: return rawValue.capitalized
        }
    }

    public var systemIcon: String {
        switch rawValue {
        case "home": return "house.fill"
        case "work": return "briefcase.fill"
        case "gym": return "figure.run"
        case "cafe": return "cup.and.saucer.fill"
        case "outdoors": return "tree.fill"
        case "park": return "leaf.fill"
        case "school": return "graduationcap.fill"
        case "shop": return "bag.fill"
        case "transit": return "tram.fill"
        case "general": return "mappin.circle.fill"
        default: return "tag.fill"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let val = try container.decode(String.self)
        self.init(rawValue: val)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct Place: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let category: PlaceCategory
    public let tags: [String]
    public let activity: String
    public let latitude: Double
    public let longitude: Double
    public let radiusMeters: Double
    public let notes: String

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        category: PlaceCategory = .general,
        tags: [String] = [],
        activity: String = "",
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 150.0,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.category = category
        let cleaned = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        self.tags = cleaned.isEmpty ? [category.rawValue] : Array(NSOrderedSet(array: cleaned)) as? [String] ?? [category.rawValue]
        self.activity = activity.isEmpty ? "at \(name)" : activity
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case tags
        case activity
        case latitude
        case longitude
        case radiusMeters = "radius_meters"
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        self.name = try container.decode(String.self, forKey: .name)
        let catRaw = try container.decodeIfPresent(String.self, forKey: .category) ?? "general"
        let decodedCat = PlaceCategory(rawValue: catRaw)
        self.category = decodedCat

        let decodedTags = try container.decodeIfPresent([String].self, forKey: .tags)
        if let decodedTags, !decodedTags.isEmpty {
            let cleaned = decodedTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
            self.tags = cleaned.isEmpty ? [decodedCat.rawValue] : Array(NSOrderedSet(array: cleaned)) as? [String] ?? [decodedCat.rawValue]
        } else {
            self.tags = [decodedCat.rawValue]
        }

        self.activity = try container.decodeIfPresent(String.self, forKey: .activity) ?? "at \(self.name)"
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        self.longitude = try container.decode(Double.self, forKey: .longitude)
        self.radiusMeters = try container.decodeIfPresent(Double.self, forKey: .radiusMeters) ?? 150.0
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category.rawValue, forKey: .category)
        try container.encode(tags, forKey: .tags)
        try container.encode(activity, forKey: .activity)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(radiusMeters, forKey: .radiusMeters)
        try container.encode(notes, forKey: .notes)
    }

    public func distanceMeters(from other: CLLocationCoordinate2D) -> Double {
        LocationRecord.displacementMeters(from: coordinate, to: other)
    }

    public func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        distanceMeters(from: coordinate) <= radiusMeters
    }
}

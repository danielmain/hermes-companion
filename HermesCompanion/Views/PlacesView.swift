import SwiftUI
import CoreLocation

public struct PlacesView: View {
    @ObservedObject private var store = PlacesStore.shared
    @State private var isShowingAddSheet = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorialSpacing.large) {
                    headerSection
                    actionBarSection
                    placesListSection
                }
                .padding(.horizontal, EditorialSpacing.page)
                .padding(.vertical, EditorialSpacing.large)
            }
            .background(EditorialColor.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingAddSheet) {
                AddPlaceSheetView()
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.compact) {
            Text("HERMES / PLACES 03")
                .font(.editorialUtility)
                .tracking(1.2)
                .foregroundStyle(EditorialColor.secondaryInk)

            Text("Known Places")
                .font(.editorialTitle)
                .fontWeight(.regular)
                .foregroundStyle(EditorialColor.ink)
                .accessibilityAddTraits(.isHeader)

            EditorialRule(strong: true)

            Text("Named locations and geofence perimeters recognized by your Hermes agent.")
                .font(.editorialBody)
                .foregroundStyle(EditorialColor.secondaryInk)
        }
    }

    // MARK: - Action Bar
    private var actionBarSection: some View {
        HStack {
            Spacer()
            Button {
                isShowingAddSheet = true
            } label: {
                HStack(spacing: EditorialSpacing.small) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                    Text("REGISTER PLACE")
                        .font(.editorialUtility)
                        .tracking(1.0)
                }
                .padding(.horizontal, EditorialSpacing.medium)
                .padding(.vertical, EditorialSpacing.compact)
                .background(EditorialColor.ink)
                .foregroundStyle(EditorialColor.paper)
                .clipShape(CutCornerShape(cut: 8))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Places List
    private var placesListSection: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            if store.places.isEmpty {
                emptyStateCard
            } else {
                ForEach(store.places) { place in
                    placeCard(place)
                }
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            Text("NO REGISTERED PLACES")
                .font(.editorialUtility)
                .foregroundStyle(EditorialColor.secondaryInk)
            Text("You haven't added any custom places yet. Tap 'Register Place' above or tell your Hermes agent to remember your current spot.")
                .font(.editorialBody)
                .foregroundStyle(EditorialColor.secondaryInk)
        }
        .padding(EditorialSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorialColor.surface)
        .clipShape(CutCornerShape(cut: 12))
        .overlay {
            CutCornerShape(cut: 12)
                .stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
        }
    }

    private func placeCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.compact) {
            HStack(alignment: .center, spacing: EditorialSpacing.small) {
                Image(systemName: place.category.systemIcon)
                    .font(.body.weight(.light))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Rectangle().stroke(EditorialColor.ink, lineWidth: EditorialBorder.hairline)
                    }

                Text(place.name)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(EditorialColor.ink)

                Spacer()

                Text("±\(Int(place.radiusMeters))m")
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(EditorialColor.surface)
                    .border(EditorialColor.hairline, width: EditorialBorder.hairline)
            }

            // Tags flow layout: ample space, legible tokens
            EditorialFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(place.tags, id: \.self) { tag in
                    let isPrimary = (tag == place.category.rawValue)
                    EditorialStatusToken(text: tag.uppercased(), isInverted: isPrimary)
                }
            }

            if !place.activity.isEmpty {
                Text(place.activity)
                    .font(.callout)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }

            HStack {
                Text("\(place.latitude, format: .number.precision(.fractionLength(5))), \(place.longitude, format: .number.precision(.fractionLength(5)))")
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)

                Spacer()

                Button(role: .destructive) {
                    store.deletePlace(id: place.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .foregroundStyle(EditorialColor.secondaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(place.name)")
            }
        }
        .padding(EditorialSpacing.medium)
        .background(EditorialColor.surface)
        .clipShape(CutCornerShape(cut: 12))
        .overlay {
            CutCornerShape(cut: 12)
                .stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
        }
    }
}

// MARK: - Add Place Sheet
struct AddPlaceSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PlacesStore.shared

    @State private var name: String = ""
    @State private var selectedTags: [String] = ["home"]
    @State private var availableTags: [PlaceCategory] = PlaceCategory.presets
    @State private var customTagInput: String = ""
    @State private var activity: String = ""
    @State private var latitudeString: String = ""
    @State private var longitudeString: String = ""
    @State private var radiusMeters: Double = 150.0
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorialSpacing.large) {
                    sheetHeader

                    VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
                        fieldSection(title: "NAME") {
                            TextField("e.g. Home, Office, Gym", text: $name)
                                .textFieldStyle(.plain)
                                .padding(EditorialSpacing.compact)
                                .background(EditorialColor.paper)
                                .border(EditorialColor.hairline, width: EditorialBorder.hairline)
                        }

                        categoryTagsSection

                        fieldSection(title: "ACTIVITY DESCRIPTION") {
                            TextField("e.g. at home, working out", text: $activity)
                                .textFieldStyle(.plain)
                                .padding(EditorialSpacing.compact)
                                .background(EditorialColor.paper)
                                .border(EditorialColor.hairline, width: EditorialBorder.hairline)
                        }

                        coordinatesSection

                        fieldSection(title: "RADIUS (\(Int(radiusMeters)) METERS)") {
                            Slider(value: $radiusMeters, in: 50...500, step: 25)
                                .tint(EditorialColor.ink)
                        }

                        fieldSection(title: "NOTES (OPTIONAL)") {
                            TextField("Additional context", text: $notes)
                                .textFieldStyle(.plain)
                                .padding(EditorialSpacing.compact)
                                .background(EditorialColor.paper)
                                .border(EditorialColor.hairline, width: EditorialBorder.hairline)
                        }
                    }

                    buttonsSection
                }
                .padding(EditorialSpacing.page)
            }
            .background(EditorialColor.surface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .tint(EditorialColor.ink)
                }
            }
            .onAppear {
                let existingTagStrings = store.places.flatMap { $0.tags }
                let extras = existingTagStrings
                    .map { PlaceCategory(rawValue: $0) }
                    .filter { cat in !availableTags.contains(where: { $0.rawValue == cat.rawValue }) }
                availableTags.append(contentsOf: extras)
            }
        }
    }

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
            Text("HERMES / NEW PERIMETER")
                .font(.editorialUtility)
                .tracking(1.2)
                .foregroundStyle(EditorialColor.secondaryInk)

            Text("Register Place")
                .font(.editorialTitle)
                .foregroundStyle(EditorialColor.ink)

            EditorialRule(strong: true)
        }
    }

    private func fieldSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
            Text(title)
                .font(.editorialUtilitySmall)
                .tracking(1.0)
                .foregroundStyle(EditorialColor.secondaryInk)
            content()
        }
    }

    // MARK: - Category & Tags Section
    private var categoryTagsSection: some View {
        fieldSection(title: "CATEGORY & TAGS") {
            VStack(alignment: .leading, spacing: EditorialSpacing.compact) {
                Text("Tap tags to select or deselect. The first selected tag serves as the primary category.")
                    .font(.caption)
                    .foregroundStyle(EditorialColor.secondaryInk)

                EditorialFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(availableTags) { cat in
                        let isSelected = selectedTags.contains(cat.rawValue)
                        Button {
                            toggleTag(cat.rawValue)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.systemIcon)
                                    .font(.caption)
                                Text(cat.label)
                                    .font(.editorialUtility)
                                    .tracking(0.5)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? EditorialColor.ink : EditorialColor.paper)
                            .foregroundStyle(isSelected ? EditorialColor.paper : EditorialColor.ink)
                            .overlay {
                                Rectangle()
                                    .stroke(isSelected ? EditorialColor.ink : EditorialColor.hairline, lineWidth: isSelected ? 1.5 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(cat.label) tag, \(isSelected ? "selected" : "not selected")")
                    }
                }

                // Add Custom Tag Input Row
                HStack(spacing: EditorialSpacing.small) {
                    TextField("Add custom tag (e.g. library, parents)", text: $customTagInput)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(EditorialSpacing.compact)
                        .background(EditorialColor.paper)
                        .border(EditorialColor.hairline, width: EditorialBorder.hairline)
                        .onSubmit {
                            addCustomTag()
                        }

                    Button {
                        addCustomTag()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.caption.bold())
                            Text("ADD")
                                .font(.editorialUtility)
                                .tracking(0.8)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(canAddCustomTag ? EditorialColor.ink : EditorialColor.secondaryInk.opacity(0.3))
                        .foregroundStyle(EditorialColor.paper)
                        .clipShape(CutCornerShape(cut: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAddCustomTag)
                }
                .padding(.top, EditorialSpacing.xSmall)

                if !selectedTags.isEmpty {
                    HStack(spacing: 6) {
                        Text("ACTIVE:")
                            .font(.editorialUtilitySmall)
                            .foregroundStyle(EditorialColor.secondaryInk)
                        Text(selectedTags.joined(separator: ", ").uppercased())
                            .font(.editorialUtilitySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(EditorialColor.ink)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var canAddCustomTag: Bool {
        !customTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addCustomTag() {
        let trimmed = customTagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        let newCat = PlaceCategory(rawValue: trimmed)
        if !availableTags.contains(where: { $0.rawValue == newCat.rawValue }) {
            availableTags.append(newCat)
        }
        if !selectedTags.contains(newCat.rawValue) {
            selectedTags.append(newCat.rawValue)
        }
        customTagInput = ""
    }

    private func toggleTag(_ tag: String) {
        if let idx = selectedTags.firstIndex(of: tag) {
            if selectedTags.count > 1 {
                selectedTags.remove(at: idx)
            }
        } else {
            selectedTags.append(tag)
        }
    }

    private var coordinatesSection: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
            HStack {
                Text("COORDINATES")
                    .font(.editorialUtilitySmall)
                    .tracking(1.0)
                    .foregroundStyle(EditorialColor.secondaryInk)
                Spacer()
                Button {
                    useCurrentLocation()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                        Text("USE CURRENT FIX")
                    }
                    .font(.editorialUtilitySmall)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(EditorialColor.ink)
                    .foregroundStyle(EditorialColor.paper)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: EditorialSpacing.compact) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LATITUDE")
                        .font(.caption2)
                        .foregroundStyle(EditorialColor.secondaryInk)
                    TextField("48.8150", text: $latitudeString)
                        .keyboardType(.numbersAndPunctuation)
                        .padding(EditorialSpacing.small)
                        .background(EditorialColor.paper)
                        .border(EditorialColor.hairline, width: EditorialBorder.hairline)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("LONGITUDE")
                        .font(.caption2)
                        .foregroundStyle(EditorialColor.secondaryInk)
                    TextField("9.2325", text: $longitudeString)
                        .keyboardType(.numbersAndPunctuation)
                        .padding(EditorialSpacing.small)
                        .background(EditorialColor.paper)
                        .border(EditorialColor.hairline, width: EditorialBorder.hairline)
                }
            }
        }
    }

    private var buttonsSection: some View {
        Button {
            save()
        } label: {
            HStack {
                Spacer()
                Text("SAVE PLACE")
                    .font(.editorialUtility)
                    .tracking(1.2)
                    .foregroundStyle(EditorialColor.paper)
                Spacer()
            }
            .padding(.vertical, EditorialSpacing.medium)
            .background(canSave ? EditorialColor.ink : EditorialColor.secondaryInk)
            .clipShape(CutCornerShape(cut: 8))
        }
        .disabled(!canSave)
        .buttonStyle(.plain)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !selectedTags.isEmpty &&
        Double(latitudeString.trimmingCharacters(in: .whitespaces)) != nil &&
        Double(longitudeString.trimmingCharacters(in: .whitespaces)) != nil
    }

    private func useCurrentLocation() {
        if let current = LocationManager.shared.currentLocation {
            latitudeString = String(format: "%.6f", current.coordinate.latitude)
            longitudeString = String(format: "%.6f", current.coordinate.longitude)
        } else if let record = LocationManager.shared.latestRecord {
            latitudeString = String(format: "%.6f", record.latitude)
            longitudeString = String(format: "%.6f", record.longitude)
        }
    }

    private func save() {
        guard let lat = Double(latitudeString.trimmingCharacters(in: .whitespaces)),
              let lon = Double(longitudeString.trimmingCharacters(in: .whitespaces)) else {
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let primaryCategoryRaw = selectedTags.first ?? "general"
        let primaryCategory = PlaceCategory(rawValue: primaryCategoryRaw)

        let newPlace = Place(
            name: trimmedName,
            category: primaryCategory,
            tags: selectedTags,
            activity: activity.trimmingCharacters(in: .whitespaces),
            latitude: lat,
            longitude: lon,
            radiusMeters: radiusMeters,
            notes: notes.trimmingCharacters(in: .whitespaces)
        )
        PlacesStore.shared.addPlace(newPlace)
        dismiss()
    }
}

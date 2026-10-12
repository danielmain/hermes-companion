import SwiftUI

enum EditorialColor {
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.031, green: 0.031, blue: 0.031, alpha: 1)
            : UIColor(red: 0.969, green: 0.969, blue: 0.953, alpha: 1)
    })

    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.969, green: 0.969, blue: 0.953, alpha: 1)
            : UIColor(red: 0.031, green: 0.031, blue: 0.031, alpha: 1)
    })

    static let secondaryInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.69, green: 0.69, blue: 0.67, alpha: 1)
            : UIColor(red: 0.36, green: 0.36, blue: 0.35, alpha: 1)
    })

    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.09, blue: 0.085, alpha: 1)
            : UIColor(red: 0.933, green: 0.933, blue: 0.918, alpha: 1)
    })

    static let userBubble = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
            : UIColor(red: 0.905, green: 0.905, blue: 0.885, alpha: 1)
    })

    static let agentBubble = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
            : UIColor(red: 0.99, green: 0.99, blue: 0.985, alpha: 1)
    })

    static let hairline = ink.opacity(0.24)
    static let faintHairline = ink.opacity(0.15)
}

enum EditorialSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let compact: CGFloat = 12
    static let medium: CGFloat = 16
    static let page: CGFloat = 22
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let section: CGFloat = 48
    static let hero: CGFloat = 64
}

enum EditorialBorder {
    static let hairline: CGFloat = 1
    static let strong: CGFloat = 2
    static let corner: CGFloat = 2
    static let imageCorner: CGFloat = 10
}

enum EditorialMotion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.easeInOut(duration: 0.24)
}

extension Font {
    static let editorialDisplay = Font.custom("Bodoni 72", size: 62, relativeTo: .largeTitle)
    static let editorialTitle = Font.custom("Bodoni 72", size: 42, relativeTo: .title)
    static let editorialNumber = Font.custom("Bodoni 72", size: 38, relativeTo: .title)
    static let editorialBody = Font.system(.body, design: .default, weight: .regular)
    static let editorialUtility = Font.system(.caption, design: .monospaced, weight: .medium)
    static let editorialUtilitySmall = Font.system(.caption2, design: .monospaced, weight: .medium)
}

struct CutCornerShape: Shape {
    var cut: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: rect.origin)
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct EditorialPanelModifier: ViewModifier {
    let emphasized: Bool
    let cutCorner: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if cutCorner {
            content
                .padding(EditorialSpacing.medium)
                .background(EditorialColor.surface)
                .clipShape(CutCornerShape())
                .overlay {
                    CutCornerShape()
                        .stroke(EditorialColor.hairline, lineWidth: emphasized ? EditorialBorder.strong : EditorialBorder.hairline)
                }
        } else {
            content
                .padding(EditorialSpacing.medium)
                .background(EditorialColor.surface)
                .clipShape(Rectangle())
                .overlay {
                    Rectangle()
                        .stroke(EditorialColor.hairline, lineWidth: emphasized ? EditorialBorder.strong : EditorialBorder.hairline)
                }
        }
    }
}

extension View {
    func editorialPanel(emphasized: Bool = false, cutCorner: Bool = false) -> some View {
        modifier(EditorialPanelModifier(emphasized: emphasized, cutCorner: cutCorner))
    }
}

struct EditorialRule: View {
    var strong: Bool = false

    var body: some View {
        Rectangle()
            .fill(EditorialColor.ink)
            .frame(height: strong ? EditorialBorder.strong : EditorialBorder.hairline)
            .accessibilityHidden(true)
    }
}

struct EditorialPageHeader: View {
    let index: LocalizedStringKey
    let title: LocalizedStringKey
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.compact) {
            Text(index)
                .font(.editorialUtility)
                .tracking(1.2)
                .foregroundStyle(EditorialColor.secondaryInk)

            Text(title)
                .font(.editorialDisplay)
                .fontWeight(.regular)
                .foregroundStyle(EditorialColor.ink)
                .lineSpacing(-8)
                .accessibilityAddTraits(.isHeader)

            EditorialRule(strong: true)

            Text(subtitle)
                .font(.editorialBody)
                .foregroundStyle(EditorialColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, EditorialSpacing.xSmall)
        }
    }
}

struct EditorialSectionHeader: View {
    var index: String? = nil
    let title: LocalizedStringKey
    var trailing: String?

    init(index: String? = nil, title: LocalizedStringKey, trailing: String? = nil) {
        self.index = index
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: EditorialSpacing.small) {
                label
                Spacer(minLength: EditorialSpacing.medium)
                if let trailing {
                    Text(trailing)
                        .font(.editorialUtilitySmall)
                        .foregroundStyle(EditorialColor.secondaryInk)
                }
            }

            VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                label
                if let trailing {
                    Text(trailing)
                        .font(.editorialUtilitySmall)
                        .foregroundStyle(EditorialColor.secondaryInk)
                }
            }
        }
        .padding(.bottom, EditorialSpacing.small)
        .overlay(alignment: .bottom) {
            EditorialRule()
        }
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: EditorialSpacing.small) {
            if let index, !index.isEmpty {
                Text(index)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }
            Text(title)
                .foregroundStyle(EditorialColor.ink)
        }
        .font(.editorialUtility)
        .tracking(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct EditorialStatusToken: View {
    let text: String
    let isInverted: Bool
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.editorialUtilitySmall)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(isInverted ? EditorialColor.paper : EditorialColor.ink)
        .background(isInverted ? EditorialColor.ink : EditorialColor.paper)
        .overlay {
            Rectangle().stroke(EditorialColor.ink, lineWidth: EditorialBorder.hairline)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EditorialButtonStyle: ButtonStyle {
    let isPrimary: Bool
    var isFullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.editorialUtility)
            .lineLimit(1)
            .fixedSize(horizontal: !isFullWidth, vertical: false)
            .tracking(0.6)
            .foregroundStyle(isPrimary ? EditorialColor.paper : EditorialColor.ink)
            .padding(.horizontal, EditorialSpacing.medium)
            .frame(minHeight: 44)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(configuration.isPressed ? (isPrimary ? EditorialColor.secondaryInk : EditorialColor.ink) : (isPrimary ? EditorialColor.ink : EditorialColor.paper))
            .foregroundStyle(configuration.isPressed && !isPrimary ? EditorialColor.paper : (isPrimary ? EditorialColor.paper : EditorialColor.ink))
            .overlay {
                Rectangle().stroke(EditorialColor.ink, lineWidth: EditorialBorder.hairline)
            }
            .contentShape(Rectangle())
    }
}

struct EditorialIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.regular))
            .foregroundStyle(configuration.isPressed ? EditorialColor.paper : EditorialColor.ink)
            .frame(width: 44, height: 44)
            .background(configuration.isPressed ? EditorialColor.ink : EditorialColor.paper)
            .overlay {
                Rectangle().stroke(EditorialColor.ink, lineWidth: EditorialBorder.hairline)
            }
            .contentShape(Rectangle())
    }
}

struct EditorialEmptyState: View {
    let index: LocalizedStringKey
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var systemImage: String = "archivebox"

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
            Text(index)
                .font(.editorialUtility)
                .foregroundStyle(EditorialColor.secondaryInk)

            Image(systemName: systemImage)
                .font(.title.weight(.ultraLight))
                .foregroundStyle(EditorialColor.ink)
                .accessibilityHidden(true)

            Text(title)
                .font(.editorialTitle)
                .foregroundStyle(EditorialColor.ink)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.editorialBody)
                .foregroundStyle(EditorialColor.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialPanel(emphasized: true, cutCorner: true)
    }
}

struct EditorialLoadingState: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(spacing: EditorialSpacing.compact) {
            ProgressView()
                .tint(EditorialColor.ink)
            Text(message)
                .font(.editorialUtility)
                .foregroundStyle(EditorialColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialPanel()
    }
}

struct EditorialErrorState: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: EditorialSpacing.compact) {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                Text("SYSTEM EXCEPTION")
                    .font(.editorialUtility)
                Text(message)
                    .font(.body)
            }
        }
        .foregroundStyle(EditorialColor.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialPanel(emphasized: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flow / Wrapping Layout
struct EditorialFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxAvailableWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let idealSize = subview.sizeThatFits(.unspecified)
            if currentX + idealSize.width > maxAvailableWidth && currentX > 0 {
                maxRowWidth = max(maxRowWidth, currentX - horizontalSpacing)
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }
            currentX += idealSize.width + horizontalSpacing
            rowHeight = max(rowHeight, idealSize.height)
        }
        maxRowWidth = max(maxRowWidth, currentX > 0 ? currentX - horizontalSpacing : 0)
        let totalHeight = currentY + rowHeight

        return CGSize(width: maxAvailableWidth.isFinite ? maxAvailableWidth : maxRowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let idealSize = subview.sizeThatFits(.unspecified)
            if currentX + idealSize.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(idealSize))
            currentX += idealSize.width + horizontalSpacing
            rowHeight = max(rowHeight, idealSize.height)
        }
    }
}

public struct EditorialField: View {
    let label: LocalizedStringKey
    let prompt: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    public init(label: LocalizedStringKey, prompt: String, text: Binding<String>) {
        self.label = label
        self.prompt = prompt
        self._text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            Text(label)
                .font(.editorialUtilitySmall)
                .foregroundStyle(EditorialColor.secondaryInk)

            TextField(prompt, text: $text)
                .font(.body)
                .textFieldStyle(.plain)
                .padding(EditorialSpacing.compact)
                .frame(minHeight: 48)
                .background(EditorialColor.paper)
                .overlay {
                    Rectangle()
                        .stroke(EditorialColor.ink, lineWidth: isFocused ? EditorialBorder.strong : EditorialBorder.hairline)
                }
                .focused($isFocused)
        }
    }
}

// MARK: - Date Formatting Helpers

private enum EditorialDateFormatters {
    static let calendar = Calendar.current

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM · H:mm"
        return f
    }()
}

extension Date {
    public var compactRelativeFormatted: String {
        let seconds = -self.timeIntervalSinceNow
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let m = max(1, Int(seconds / 60))
            return "\(m)m ago"
        } else if seconds < 86400 {
            let h = Int(seconds / 3600)
            return "\(h)h ago"
        } else {
            let d = Int(seconds / 86400)
            return "\(d)d ago"
        }
    }

    public var compactDateFormatted: String {
        let calendar = EditorialDateFormatters.calendar
        if calendar.isDateInToday(self) {
            return EditorialDateFormatters.timeFormatter.string(from: self)
        } else if calendar.isDateInYesterday(self) {
            return "Yest. " + EditorialDateFormatters.timeFormatter.string(from: self)
        } else {
            return EditorialDateFormatters.fullFormatter.string(from: self)
        }
    }
}


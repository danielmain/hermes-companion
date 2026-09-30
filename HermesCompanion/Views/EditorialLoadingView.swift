import SwiftUI

struct EditorialLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scanPosition: CGFloat = -1
    @State private var revealed = false

    var body: some View {
        ZStack {
            EditorialColor.paper
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: EditorialSpacing.large) {
                        LoadingMasthead()

                        LoadingArtwork(scanPosition: scanPosition)
                            .frame(height: dynamicTypeSize.isAccessibilitySize ? 190 : proxy.size.height * 0.58)

                        LoadingFooter()
                    }
                    .frame(minHeight: proxy.size.height, alignment: .center)
                    .padding(.horizontal, EditorialSpacing.page)
                    .padding(.vertical, EditorialSpacing.large)
                }
                .scrollIndicators(.hidden)
            }
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 8)
        }
        .task {
            if reduceMotion {
                revealed = true
                scanPosition = 1
            } else {
                withAnimation(EditorialMotion.standard) {
                    revealed = true
                }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    scanPosition = 1
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hermes Companion is initializing the local telemetry archive")
    }
}

private struct LoadingMasthead: View {
    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("HERMES / FIELD UNIT")
                    Spacer()
                    Text("IOS—01")
                }

                VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                    Text("HERMES / FIELD UNIT")
                    Text("IOS—01")
                }
            }
            .font(.editorialUtility)
            .tracking(1.2)
            .foregroundStyle(EditorialColor.secondaryInk)

            EditorialRule(strong: true)

            Text("Hermes")
                .font(.editorialDisplay)
                .fontWeight(.regular)
                .foregroundStyle(EditorialColor.ink)
                .lineSpacing(-8)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

private struct LoadingArtwork: View {
    let scanPosition: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Image("HermesLoading")
                    .resizable()
                    .scaledToFill()
                    .saturation(0)
                    .contrast(1.25)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                Rectangle()
                    .fill(EditorialColor.paper.opacity(0.18))
                    .frame(height: 2)
                    .offset(y: max(0, proxy.size.height * scanPosition))
                    .accessibilityHidden(true)

                Text("ARCHIVAL PLATE / 0001")
                    .font(.editorialUtilitySmall)
                    .padding(EditorialSpacing.small)
                    .foregroundStyle(EditorialColor.paper)
                    .background(EditorialColor.ink)
                    .padding(EditorialSpacing.compact)
            }
            .background(EditorialColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: EditorialBorder.imageCorner))
            .overlay {
                RoundedRectangle(cornerRadius: EditorialBorder.imageCorner)
                    .stroke(EditorialColor.ink, lineWidth: EditorialBorder.strong)
            }
        }
    }
}

private struct LoadingFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("INITIALIZING ARCHIVE")
                    Spacer()
                    Text("LOCAL / SECURE")
                }

                VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                    Text("INITIALIZING ARCHIVE")
                    Text("LOCAL / SECURE")
                }
            }
            .font(.editorialUtility)
            .foregroundStyle(EditorialColor.ink)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(EditorialColor.hairline)
                    Rectangle()
                        .fill(EditorialColor.ink)
                        .frame(width: proxy.size.width * 0.72)
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)

            Text("LOCATION · HEALTH · PRIVATE ICLOUD")
                .font(.editorialUtilitySmall)
                .tracking(0.8)
                .foregroundStyle(EditorialColor.secondaryInk)
        }
    }
}

#Preview {
    EditorialLoadingView()
}

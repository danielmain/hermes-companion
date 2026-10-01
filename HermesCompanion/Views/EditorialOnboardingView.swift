import SwiftUI

struct EditorialOnboardingView: View {
    let completion: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorialSpacing.section) {
                EditorialPageHeader(
                    index: "HERMES / ORIENTATION",
                    title: "A private\nfield archive",
                    subtitle: "Hermes Companion observes selected signals on this iPhone and files them for your personal Hermes system."
                )

                Image("HermesLoading")
                    .resizable()
                    .scaledToFill()
                    .saturation(0)
                    .contrast(1.2)
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: EditorialBorder.imageCorner))
                    .overlay {
                        RoundedRectangle(cornerRadius: EditorialBorder.imageCorner)
                            .stroke(EditorialColor.ink, lineWidth: EditorialBorder.strong)
                    }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    OnboardingModule(
                        index: "01",
                        title: "CONNECT",
                        description: "Use your private Apple iCloud account as the encrypted path between iPhone and Mac."
                    )
                    EditorialRule()
                    OnboardingModule(
                        index: "02",
                        title: "REMEMBER",
                        description: "Keep a chronological local register of location, movement, and optional health context."
                    )
                    EditorialRule()
                    OnboardingModule(
                        index: "03",
                        title: "AUTOMATE",
                        description: "Choose how iOS observes movement in the foreground, background, and after the app closes."
                    )
                }
                .overlay {
                    Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
                }

                VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
                    Text("YOUR CONSENT REMAINS THE CONTROL SURFACE")
                        .font(.editorialUtility)
                    Text("Hermes does not collect analytics or send logs to us. Your data is stored on this iPhone and synced only to your private iCloud account. You can change Location and Health access at any time in iOS Settings.")
                        .font(.body)
                        .foregroundStyle(EditorialColor.secondaryInk)

                    Button {
                        completion()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("ENTER FIELD UNIT", systemImage: "arrow.right")
                    }
                    .buttonStyle(EditorialButtonStyle(isPrimary: true))
                }
                .editorialPanel(emphasized: true, cutCorner: true)
            }
            .padding(.horizontal, EditorialSpacing.page)
            .padding(.top, EditorialSpacing.large)
            .padding(.bottom, EditorialSpacing.hero)
        }
        .background(EditorialColor.paper)
    }
}

private struct OnboardingModule: View {
    let index: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: EditorialSpacing.large) {
                numeral
                copy
            }

            VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                numeral
                copy
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EditorialSpacing.medium)
        .accessibilityElement(children: .combine)
    }

    private var numeral: some View {
        Text(index)
            .font(.editorialNumber)
            .foregroundStyle(EditorialColor.ink)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            Text(title)
                .font(.editorialUtility)
                .tracking(1)
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .font(.body)
                .foregroundStyle(EditorialColor.secondaryInk)
        }
    }
}

#Preview {
    EditorialOnboardingView(completion: {})
}

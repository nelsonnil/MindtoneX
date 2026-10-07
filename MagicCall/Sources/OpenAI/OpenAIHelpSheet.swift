import SwiftUI

/// English help: create key, billing, one-key note — used from Performance settings and pre-Perform gate.
struct OpenAIHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(OpenAIAPIKeyCopy.helpIntro)
                        .font(.subheadline)
                        .foregroundStyle(OracleTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    helpStep(
                        number: 1,
                        title: "Create an API key",
                        detail: "Sign in at OpenAI, create a secret key, and paste it into MindtoneX Performance settings."
                    ) {
                        Link(destination: OpenAIAPIKeyCopy.apiKeysURL) {
                            Label("Open API keys page", systemImage: "key.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(OracleTheme.gold)
                    }

                    helpStep(
                        number: 2,
                        title: "Add balance or billing",
                        detail: "OpenAI charges your account when Voice or Camera vision runs. Add a payment method or prepaid credits so Perform is not blocked mid-show."
                    ) {
                        Link(destination: OpenAIAPIKeyCopy.billingURL) {
                            Label("Open billing settings", systemImage: "creditcard.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(OracleTheme.gold)
                    }

                    Text(OpenAIAPIKeyCopy.singleKeyHelper)
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(OpenAIAPIKeyCopy.helpCostNote)
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(OracleTheme.bgTop)
            .navigationTitle("OpenAI setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func helpStep(
        number: Int,
        title: String,
        detail: String,
        @ViewBuilder action: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(number). \(title)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }
}

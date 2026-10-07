import SwiftUI

/// Blocks Perform on Home when OpenAI is required but Keychain has no key.
struct OpenAIMissingKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showHelpSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("OpenAI API key required")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(OracleTheme.textPrimary)

                    Text(
                        "Your current setup uses OpenAI for Voice AI and/or Camera card reading. "
                            + "Add the same key you use on platform.openai.com before starting Perform."
                    )
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(OpenAIAPIKeyCopy.singleKeyHelper)
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(OpenAIAPIKeyCopy.helpCostNote)
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: OpenAIAPIKeyCopy.apiKeysURL) {
                        Label("Create API key on OpenAI", systemImage: "key.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OracleTheme.gold)

                    Button {
                        showHelpSheet = true
                    } label: {
                        Label("Setup steps & billing", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(OracleTheme.gold)

                    Text("After saving your key under **Performance settings**, tap Perform again.")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(OracleTheme.bgTop)
            .navigationTitle("Can't start Perform")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showHelpSheet) {
                OpenAIHelpSheet()
            }
        }
        .preferredColorScheme(.dark)
    }
}

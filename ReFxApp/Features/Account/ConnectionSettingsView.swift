import SwiftUI

/// Runtime base-URL configuration (staging override / local panel-api). The
/// build-time `.xcconfig` default is shown as placeholder; overrides persist in
/// UserDefaults (non-secret origins only — never tokens).
struct ConnectionSettingsView: View {
    @EnvironmentObject private var config: AppConfig
    @Environment(\.dismiss) private var dismiss

    @State private var apiOrigin = ""
    @State private var webOrigin = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(config.apiOrigin.absoluteString, text: $apiOrigin)
                        .keyboardType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("API base URL")
                } footer: {
                    Text("The panel-api origin. Swagger is at \(config.apiOrigin.absoluteString)/docs. Must be HTTPS in production.")
                }

                Section {
                    TextField(config.webOrigin.absoluteString, text: $webOrigin)
                        .keyboardType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Web base URL")
                } footer: {
                    Text("Used for sign-up, billing and checkout link-outs.")
                }

                Section {
                    Button("Save") { save() }
                        .disabled(apiOrigin.isEmpty && webOrigin.isEmpty)
                    Button("Reset to defaults", role: .destructive) {
                        config.resetToDefaults()
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func save() {
        if !apiOrigin.isEmpty { config.setAPIOrigin(apiOrigin) }
        if !webOrigin.isEmpty { config.setWebOrigin(webOrigin) }
        dismiss()
    }
}

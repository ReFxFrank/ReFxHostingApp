import SwiftUI

struct CreateTicketView: View {
    /// Called after a successful create so the list can refresh.
    let onCreated: () async -> Void

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var message = ""
    @State private var priority: TicketPriority = .normal
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Subject") {
                    TextField("Brief summary", text: $subject)
                }
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag(TicketPriority.low)
                        Text("Normal").tag(TicketPriority.normal)
                        Text("High").tag(TicketPriority.high)
                        Text("Urgent").tag(TicketPriority.urgent)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Message") {
                    TextField("Describe your issue…", text: $message, axis: .vertical)
                        .lineLimit(4...12)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.appDestructive).font(.footnote)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("New ticket").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await submit() } }
                        .disabled(!isValid || isSubmitting)
                }
            }
        }
    }

    private var isValid: Bool {
        subject.trimmingCharacters(in: .whitespaces).count >= 3 &&
        !message.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await session.support.create(
                subject: subject.trimmingCharacters(in: .whitespaces),
                body: message.trimmingCharacters(in: .whitespaces),
                priority: priority)
            await onCreated()
            dismiss()
        } catch let error as APIError { errorMessage = error.userMessage }
        catch { errorMessage = "Couldn't create the ticket." }
    }
}

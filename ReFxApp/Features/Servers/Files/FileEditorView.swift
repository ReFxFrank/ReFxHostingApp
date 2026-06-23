import SwiftUI
import UIKit

@MainActor
final class FileEditorViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case editing
        case tooLarge
        case binary
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published var text = ""
    @Published private(set) var isSaving = false
    @Published var saveError: String?
    @Published private(set) var savedText = ""

    /// Above this we refuse to load into a TextEditor (download instead).
    private let maxEditableBytes = 1_000_000

    let serverId: String
    let entry: FileEntry
    private var service: FilesService?

    init(serverId: String, entry: FileEntry) {
        self.serverId = serverId
        self.entry = entry
    }

    var isDirty: Bool { phase == .editing && text != savedText }

    func bind(_ session: AppSession) {
        if service == nil { service = session.files }
    }

    func load() async {
        guard let service else { return }
        if entry.size > maxEditableBytes {
            phase = .tooLarge
            return
        }
        phase = .loading
        do {
            let content = try await service.read(serverId, path: entry.path)
            if content.contains("\u{0}") {       // NUL byte → binary, don't edit
                phase = .binary
                return
            }
            text = content
            savedText = content
            phase = .editing
        } catch let error as APIError {
            phase = .failed(error.userMessage)
        } catch {
            phase = .failed("Couldn't open this file.")
        }
    }

    func save() async {
        guard let service, phase == .editing else { return }
        saveError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.write(serverId, path: entry.path, content: text)
            savedText = text
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch let error as APIError {
            saveError = error.userMessage
        } catch {
            saveError = "Couldn't save. Try again."
        }
    }

    func downloadURL() async -> URL? {
        guard let service else { return nil }
        return try? await service.downloadURL(serverId, path: entry.path)
    }
}

/// View + edit a single text/config file. Large or binary files are gated to a
/// download instead of loading into the editor.
struct FileEditorView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: FileEditorViewModel
    @State private var downloadURL: URL?

    init(serverId: String, entry: FileEntry) {
        _model = StateObject(wrappedValue: FileEditorViewModel(serverId: serverId, entry: entry))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView().tint(.appPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .editing:
                editor
            case .tooLarge:
                gate(icon: "doc.badge.ellipsis",
                     message: "This file is too large to edit on device (\(model.entry.sizeDescription)).")
            case .binary:
                gate(icon: "doc.zipper",
                     message: "This looks like a binary file, so it can't be edited as text.")
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        .foregroundStyle(.appWarning)
                    Text(message).foregroundStyle(.appMuted).multilineTextAlignment(.center)
                    Button("Try again") { Task { await model.load() } }
                        .buttonStyle(.borderedProminent).tint(.appPrimary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .screenBackground()
        .navigationTitle(model.entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.phase == .editing {
                    Button {
                        Task { await model.save() }
                    } label: {
                        if model.isSaving { ProgressView() } else { Text("Save").bold() }
                    }
                    .disabled(!model.isDirty || model.isSaving)
                }
            }
        }
        .task {
            model.bind(session)
            await model.load()
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if let error = model.saveError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.appDestructive.opacity(0.12))
            }
            if model.isDirty {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.circle.fill")
                    Text("Unsaved changes").font(.caption)
                    Spacer()
                }
                .foregroundStyle(.appWarning)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.appWarning.opacity(0.1))
            }
            TextEditor(text: $model.text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.appForeground)
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.25))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    private func gate(icon: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.appMuted)
            Text(message).foregroundStyle(.appMuted).multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                Task { if let url = await model.downloadURL() { WebLink.open(url) } }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent).tint(.appPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

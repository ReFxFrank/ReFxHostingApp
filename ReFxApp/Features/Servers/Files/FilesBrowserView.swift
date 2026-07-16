import SwiftUI
import UniformTypeIdentifiers

/// File manager for one server, rooted at `path`. Directories push another
/// `FilesBrowserView` (native back gives a breadcrumb); files push the editor.
/// Pushed inside the existing navigation stack — no NavigationStack here.
struct FilesBrowserView: View {
    let serverId: String
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: FilesBrowserViewModel

    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renaming: FileEntry?
    @State private var renameText = ""
    @State private var chmodTarget: FileEntry?
    @State private var chmodText = ""
    @State private var showImporter = false
    @State private var showSftp = false

    init(serverId: String, path: String = "/") {
        self.serverId = serverId
        _model = StateObject(wrappedValue: FilesBrowserViewModel(path: path))
    }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "Empty folder",
            emptyMessage: "Nothing in this directory yet.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: {
                VStack(spacing: 8) { ForEach(0..<8, id: \.self) { _ in SkeletonBlock(height: 44) } }
                    .padding(16)
            })
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.isUploading { ProgressView() }
                Button { showSftp = true } label: { Image(systemName: "network") }
                    .accessibilityLabel("SFTP details")
                Button { showImporter = true } label: { Image(systemName: "arrow.up.doc") }
                    .accessibilityLabel("Upload file").disabled(model.isUploading)
                Button { newFolderName = ""; showNewFolder = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("New folder")
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { Task { await model.upload(fileURL: url) } }
        }
        .sheet(isPresented: $showSftp) {
            SftpDetailsView(serverId: serverId).environmentObject(session)
        }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Create") { Task { await model.makeDirectory(named: newFolderName.trimmed) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Rename") {
                if let entry = renaming { Task { await model.rename(entry, to: renameText.trimmed) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Permissions", isPresented: Binding(
            get: { chmodTarget != nil }, set: { if !$0 { chmodTarget = nil } })) {
            TextField("Mode (e.g. 0755)", text: $chmodText)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Apply") {
                if let entry = chmodTarget { Task { await model.chmod(entry, mode: chmodText) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Octal permission mode, e.g. 0644 for files or 0755 for scripts.")
        }
        .task {
            model.bind(serverId: serverId, service: session.files)
            if model.state.value == nil { await model.load() }
        }
    }

    private var list: some View {
        List {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive)
                    .listRowBackground(Color.appCard)
            }
            ForEach(model.sortedEntries) { entry in
                row(for: entry)
                    .listRowBackground(Color.appCard)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await model.delete(entry) }
                        } label: { Label("Delete", systemImage: "trash") }
                        Button {
                            renaming = entry; renameText = entry.name
                        } label: { Label("Rename", systemImage: "pencil") }
                            .tint(.appPrimary)
                    }
                    .swipeActions(edge: .leading) {
                        if isArchive(entry) {
                            Button {
                                Task { await model.decompress(entry) }
                            } label: { Label("Extract", systemImage: "archivebox") }
                                .tint(.appSuccess)
                        } else {
                            Button {
                                Task { await model.compress(entry) }
                            } label: { Label("Compress", systemImage: "archivebox") }
                                .tint(.appSecondary)
                        }
                    }
                    .contextMenu {
                        Button {
                            Task { await model.compress(entry) }
                        } label: { Label("Compress to archive", systemImage: "archivebox") }
                        if isArchive(entry) {
                            Button {
                                Task { await model.decompress(entry) }
                            } label: { Label("Extract here", systemImage: "arrow.up.bin") }
                        }
                        Button { renaming = entry; renameText = entry.name } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        if !entry.isDir {
                            Button {
                                // Prefill a sensible octal default; the agent's `mode`
                                // string isn't guaranteed octal, so don't echo it back.
                                chmodTarget = entry
                                chmodText = entry.name.lowercased().hasSuffix(".sh") ? "0755" : "0644"
                            } label: { Label("Permissions…", systemImage: "lock.rotation") }
                        }
                        Button(role: .destructive) {
                            Task { await model.delete(entry) }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private func row(for entry: FileEntry) -> some View {
        if entry.isDir {
            NavigationLink {
                FilesBrowserView(serverId: serverId, path: entry.path)
            } label: { FileRow(entry: entry) }
        } else {
            NavigationLink {
                FileEditorView(serverId: serverId, entry: entry)
            } label: { FileRow(entry: entry) }
        }
    }

    private var title: String {
        if model.path == "/" || model.path.isEmpty { return "Files" }
        return (model.path as NSString).lastPathComponent
    }

    /// Extensions the server can extract via `files/decompress`.
    private func isArchive(_ entry: FileEntry) -> Bool {
        guard !entry.isDir else { return false }
        let name = entry.name.lowercased()
        return [".zip", ".tar", ".tar.gz", ".tgz", ".gz", ".tar.bz2", ".tbz2", ".rar", ".7z"]
            .contains { name.hasSuffix($0) }
    }
}

struct FileRow: View {
    let entry: FileEntry
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(entry.isDir ? Color.appPrimary : Color.appMuted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).foregroundStyle(.appForeground).lineLimit(1)
                if !entry.isDir {
                    Text(entry.sizeDescription).font(.caption2).foregroundStyle(.appMuted)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        if entry.isDir { return "folder.fill" }
        return entry.isLikelyText ? "doc.text" : "doc"
    }
}

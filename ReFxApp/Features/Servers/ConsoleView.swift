import SwiftUI

/// Live console: streamed terminal + command input. Autoscrolls unless the user
/// scrolls up (scroll-lock), shows a reconnecting state, and the buffer persists
/// (it lives on the socket, which the detail VM owns across sub-tab switches).
struct ConsoleView: View {
    @ObservedObject var socket: ConsoleSocket
    @State private var command = ""
    @State private var scrollLocked = false

    var body: some View {
        VStack(spacing: 0) {
            if socket.connectionState == .reconnecting || socket.connectionState == .connecting {
                ReconnectingBanner()
            }
            TerminalView(lines: socket.lines, scrollLocked: $scrollLocked)
            commandBar
        }
    }

    private var commandBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right").foregroundStyle(.appMuted).font(.caption)
            TextField("Type a command…", text: $command)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout.monospaced())
                .foregroundStyle(.appForeground)
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "paperplane.fill")
            }
            .disabled(command.isEmpty || socket.connectionState != .connected)
            .foregroundStyle(command.isEmpty ? .appMuted : .appPrimary)
        }
        .padding(12)
        .background(Color.appCard)
        .overlay(Rectangle().fill(Color.appBorder).frame(height: 1), alignment: .top)
    }

    private func send() {
        let toSend = command
        guard !toSend.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        socket.sendCommand(toSend)
        command = ""
    }
}

struct ReconnectingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini).tint(.appWarning)
            Text("Reconnecting to live console…").font(.caption)
            Spacer()
        }
        .foregroundStyle(.appWarning)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.appWarning.opacity(0.12))
    }
}

/// Monospace terminal: autoscroll with scroll-lock, copyable text.
struct TerminalView: View {
    let lines: [ConsoleSocket.ConsoleLine]
    @Binding var scrollLocked: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(12)
            }
            .background(Color.black.opacity(0.35))
            .overlay(alignment: .bottomTrailing) {
                if scrollLocked {
                    Button {
                        scrollLocked = false
                        scrollToBottom(proxy)
                    } label: {
                        Label("Jump to live", systemImage: "arrow.down.to.line")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.appPrimary)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .padding(12)
                }
            }
            .onChange(of: lines.count) { _ in
                if !scrollLocked { scrollToBottom(proxy) }
            }
            // Heuristic: any drag implies the user is reading scrollback.
            .simultaneousGesture(DragGesture().onChanged { value in
                if value.translation.height > 12 { scrollLocked = true }
            })
        }
    }

    private let bottomAnchor = "terminal.bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.linear(duration: 0.1)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    private func color(for line: ConsoleSocket.ConsoleLine) -> Color {
        if line.stream == "input" { return .appPrimary }
        return line.isError ? .appDestructive : .appForeground
    }
}

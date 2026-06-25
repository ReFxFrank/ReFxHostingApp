import SwiftUI

/// Live console: streamed terminal + command input. Autoscrolls unless the user
/// scrolls up (scroll-lock), shows a reconnecting state, and the buffer persists
/// (it lives on the socket, which the detail VM owns across sub-tab switches).
struct ConsoleView: View {
    @ObservedObject var socket: ConsoleSocket
    @State private var command = ""
    @State private var scrollLocked = false
    @FocusState private var inputFocused: Bool

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
            Text(">")
                .font(.callout.weight(.bold).monospaced())
                .foregroundStyle(.appPrimary)
                .shadow(color: .appPrimary.opacity(0.6), radius: 4)
            TextField("Type a command…", text: $command)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout.monospaced())
                .foregroundStyle(.appForeground)
                .tint(.appPrimary)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.callout)
                    .foregroundStyle(canSend ? .white : .appMuted)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(canSend ? AnyShapeStyle(Theme.primaryGradient)
                                                       : AnyShapeStyle(Color.appCard)))
                    .overlay(Circle().strokeBorder(Color.appBorder, lineWidth: canSend ? 0 : 1))
                    .shadow(color: canSend ? .appPrimary.opacity(0.5) : .clear, radius: 8)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.appPopover)
        .overlay(LinearGradient(colors: [.appPrimary.opacity(0.25), .appBorder],
                                startPoint: .leading, endPoint: .trailing)
            .frame(height: 1), alignment: .top)
    }

    private var canSend: Bool {
        !command.trimmingCharacters(in: .whitespaces).isEmpty && socket.connectionState == .connected
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
            Text("Reconnecting to live console…").font(.caption.weight(.medium))
            Spacer()
        }
        .foregroundStyle(.appWarning)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.appWarning.opacity(0.12))
        .overlay(Rectangle().fill(Color.appWarning.opacity(0.3)).frame(height: 1), alignment: .bottom)
    }
}

/// Monospace terminal: autoscroll with scroll-lock, copyable text. Kept flat
/// (no glass/blur per line) so streaming stays smooth on older iPhones.
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
            .background(
                LinearGradient(colors: [Color(hex: "060a12"), Color(hex: "04070d")],
                               startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .bottomTrailing) {
                if scrollLocked {
                    Button {
                        scrollLocked = false
                        scrollToBottom(proxy)
                    } label: {
                        Label("Jump to live", systemImage: "arrow.down.to.line")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Theme.primaryGradient))
                            .foregroundStyle(.white)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: .appPrimary.opacity(0.5), radius: 8)
                    }
                    .padding(14)
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
        if line.stream == "input" { return .appAccentText }
        return line.isError ? .appDestructive : .appForeground
    }
}

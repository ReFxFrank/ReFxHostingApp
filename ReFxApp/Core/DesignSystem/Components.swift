import SwiftUI
import UIKit

/// A circular CPU/RAM/disk gauge with a label and used/total caption.
struct ResourceGauge: View {
    let title: String
    /// 0...1 fill fraction.
    let fraction: Double
    let caption: String
    var systemImage: String = "gauge"

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var tint: Color {
        switch clamped {
        case ..<0.7: return .appSuccess
        case ..<0.9: return .appWarning
        default: return .appDestructive
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.appBorder, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: clamped)
                VStack(spacing: 0) {
                    Image(systemName: systemImage).font(.caption2).foregroundStyle(Color.appMuted)
                    Text("\(Int(clamped * 100))%").font(.headline.monospacedDigit())
                        .foregroundStyle(Color.appForeground)
                }
            }
            .frame(width: 78, height: 78)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.appForeground)
            Text(caption).font(.caption2).foregroundStyle(Color.appMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(Int(clamped * 100)) percent, \(caption)")
    }
}

/// Compact labeled metric card (uptime, players, etc.).
struct StatCard: View {
    let title: String
    let value: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption).foregroundStyle(Color.appMuted)
                }
                Text(title).font(.caption).foregroundStyle(Color.appMuted)
            }
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.appForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .cardSurface()
    }
}

/// IP:port chip with one-tap copy + haptic confirmation.
struct CopyChip: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation { copied = false }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.appSuccess : Color.appPrimary)
                Text(value).font(.callout.monospaced()).foregroundStyle(Color.appForeground)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value). Tap to copy.")
    }
}

/// Standard screen background.
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Color.appBackground.ignoresSafeArea())
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}

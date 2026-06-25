import SwiftUI
import UIKit

// MARK: - GlassCard container

/// A padded ReFx glass panel. Wrap any content for a consistent module surface.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    var elevated = false
    var glow = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(elevated: elevated, glow: glow)
    }
}

// MARK: - Resource gauge

/// A circular CPU/RAM/disk gauge with a label and used/total caption.
/// Healthy reads as ReFx blue; it shifts to amber/red only under pressure.
struct ResourceGauge: View {
    let title: String
    /// 0...1 fill fraction.
    let fraction: Double
    let caption: String
    var systemImage: String = "gauge"

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var clamped: Double { min(max(fraction, 0), 1) }
    private var tint: Color {
        switch clamped {
        case ..<0.7: return .appPrimary
        case ..<0.9: return .appWarning
        default: return .appDestructive
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.06), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(colors: [tint.opacity(0.65), tint], center: .center),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: reduceTransparency ? .clear : tint.opacity(0.55), radius: 6)
                    .animation(.smooth(duration: 0.45), value: clamped)
                VStack(spacing: 1) {
                    Image(systemName: systemImage).font(.system(size: 11)).foregroundStyle(Color.appLabel)
                    Text("\(Int(clamped * 100))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.appForeground)
                }
            }
            .frame(width: 80, height: 80)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.appForeground)
            Text(caption).font(.caption2.monospacedDigit()).foregroundStyle(Color.appMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(Int(clamped * 100)) percent, \(caption)")
    }
}

// MARK: - Stat card

/// Compact labeled metric card (uptime, players, etc.).
struct StatCard: View {
    let title: String
    let value: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption).foregroundStyle(Color.appPrimary)
                }
                Eyebrow(title)
            }
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.appForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .cardSurface()
    }
}

// MARK: - Copy chip

/// IP:port chip with one-tap copy + haptic confirmation.
struct CopyChip: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.snappy) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.snappy) { copied = false }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.appSuccess : Color.appPrimary)
                Text(value).font(.callout.monospaced()).foregroundStyle(Color.appForeground)
                Spacer(minLength: 0)
                Text(copied ? "COPIED" : "COPY")
                    .font(.caption2.weight(.semibold)).tracking(1)
                    .foregroundStyle(copied ? Color.appSuccess : Color.appLabel)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassInset()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value). Tap to copy.")
    }
}

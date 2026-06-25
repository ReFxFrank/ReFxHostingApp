import SwiftUI
import UIKit

/// The four states every async screen moves through. Keeping this in one type
/// means list/detail screens render loading/empty/error/loaded consistently.
enum LoadState<Value>: Equatable where Value: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// Renders the right view for a `LoadState`: a skeleton while loading, a
/// friendly empty state, a retryable error, or the loaded content.
struct AsyncStateView<Value: Equatable, Content: View, Skeleton: View>: View {
    let state: LoadState<Value>
    let isEmpty: (Value) -> Bool
    var emptyTitle = "Nothing here yet"
    var emptyMessage = ""
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content
    @ViewBuilder let skeleton: () -> Skeleton

    var body: some View {
        switch state {
        case .idle, .loading:
            skeleton()
        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
        case .loaded(let value):
            if isEmpty(value) {
                EmptyStateView(title: emptyTitle, message: emptyMessage)
            } else {
                content(value)
            }
        }
    }
}

struct ErrorStateView: View {
    let error: APIError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.appWarning)
                .frame(width: 78, height: 78)
                .cardSurface(elevated: true)
            Text(error.userMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.appMuted)
            Button {
                retry()
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.refxPrimary(fullWidth: false))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let title: String
    var message: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.appLabel)
                .frame(width: 78, height: 78)
                .cardSurface(elevated: true)
            Text(title).font(.headline).foregroundStyle(Color.appForeground)
            if !message.isEmpty {
                Text(message).font(.subheadline).foregroundStyle(Color.appMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A shimmering placeholder block for skeleton loaders.
struct SkeletonBlock: View {
    var height: CGFloat = 16
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.appCardElevated)
            .frame(height: height)
            .opacity(shimmer ? 0.45 : 0.9)
            .onAppear {
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}

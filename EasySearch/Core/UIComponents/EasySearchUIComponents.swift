import SwiftUI

enum ESUI {
    static let bottomTabSpacing: CGFloat = 112
    static let cardCornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 16
    static let screenHorizontalPadding: CGFloat = 16

    static var appBackground: Color {
        Color(.systemGroupedBackground)
    }

    static var cardBackground: Color {
        Color(.secondarySystemGroupedBackground)
    }

    static var elevatedBackground: Color {
        Color(.secondarySystemBackground)
    }
}

extension View {
    func esScreenBackground() -> some View {
        background(ESUI.appBackground.ignoresSafeArea())
    }

    func esBottomTabPadding(_ extra: CGFloat = 0) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: ESUI.bottomTabSpacing + extra)
                .allowsHitTesting(false)
        }
    }

    func esCard(cornerRadius: CGFloat = ESUI.cardCornerRadius) -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ESUI.elevatedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

struct ESSectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
        }
    }
}

struct ESFeatureIcon: View {
    let systemName: String
    var color: Color = .accentColor
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(color.opacity(0.13))

            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ESStatusPill: View {
    enum Tone: Equatable {
        case neutral
        case accent
        case success
        case warning
        case danger

        var color: Color {
            switch self {
            case .neutral:
                return .secondary
            case .accent:
                return .accentColor
            case .success:
                return .green
            case .warning:
                return .orange
            case .danger:
                return .red
            }
        }
    }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tone.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tone.color.opacity(0.12)))
    }
}

struct ESInfoBanner: View {
    let title: String
    var message: String?
    var systemImage: String = "info.circle"
    var tone: ESStatusPill.Tone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(tone.color.opacity(0.09))
        )
    }
}

struct ESEmptyState: View {
    let title: String
    var message: String?
    var systemImage: String
    var minHeight: CGFloat = 210

    var body: some View {
        VStack(spacing: 10) {
            ESFeatureIcon(systemName: systemImage, color: .secondary, size: 52)
                .opacity(0.85)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

struct ESMediaPlaceholder: View {
    enum Mode {
        case loading(String?)
        case empty(String)
        case failure(String)
    }

    let mode: Mode
    var systemImage: String = "photo"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(Color(.tertiarySystemFill))

            VStack(spacing: 9) {
                switch mode {
                case let .loading(text):
                    ProgressView()
                        .controlSize(.regular)
                    if let text {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case let .empty(text):
                    Image(systemName: systemImage)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case let .failure(text):
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(16)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ESCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

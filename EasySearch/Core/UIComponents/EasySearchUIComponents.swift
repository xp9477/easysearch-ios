import SwiftUI

// MARK: - Design Tokens

enum ESUI {
    /// Spacing grid: 4, 8, 12, 16, 20, 24, 32, 40, 48
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
        static let huge: CGFloat = 48
    }

    static let screenHorizontalPadding: CGFloat = Space.md
    static let sectionSpacing: CGFloat = Space.xl
    static let rowSpacing: CGFloat = Space.sm
    static let cardCornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 12
    static let bottomTabSpacing: CGFloat = 88

    static var appBackground: Color { Color(.systemGroupedBackground) }
    static var surface: Color { Color(.secondarySystemGroupedBackground) }
    static var elevated: Color { Color(.secondarySystemBackground) }
    static var fill: Color { Color(.tertiarySystemFill) }
    static var elevatedBackground: Color { elevated }
    static var cardBackground: Color { surface }
}

// MARK: - Button Style

struct ESCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - View Chrome

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
        padding(ESUI.Space.md)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ESUI.surface)
            )
    }

    func esSurface(cornerRadius: CGFloat = ESUI.cardCornerRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ESUI.surface)
        )
    }
}

// MARK: - Section Header

struct ESSectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ESUI.Space.sm) {
            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: ESUI.Space.xs)

            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ESUI.Space.xs)
                    .padding(.vertical, ESUI.Space.xxs)
                    .background(Capsule().fill(ESUI.fill))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Feature Icon

struct ESFeatureIcon: View {
    let systemName: String
    var color: Color = .accentColor
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.opacity(0.14))

            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Status Badge

struct ESStatusBadge: View {
    enum Tone: Equatable {
        case neutral
        case accent
        case success
        case warning
        case danger

        var color: Color {
            switch self {
            case .neutral: return .secondary
            case .accent: return .accentColor
            case .success: return .green
            case .warning: return .orange
            case .danger: return .red
            }
        }

        static func from(kind: FeatureStatusKind) -> Tone {
            switch kind {
            case .ready: return .success
            case .needsConfiguration, .needsAuthorization: return .warning
            case .empty: return .neutral
            case .processing: return .accent
            case .offlineOrUnavailable, .recoverableFailure: return .danger
            case .attentionNeeded: return .warning
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
            .padding(.horizontal, ESUI.Space.xs)
            .padding(.vertical, ESUI.Space.xxs)
            .background(Capsule().fill(tone.color.opacity(0.12)))
            .accessibilityLabel(text)
    }
}

/// Backwards-compatible alias used by existing call sites during migration.
typealias ESStatusPill = ESStatusBadge

// MARK: - Status Banner

struct ESStatusBanner: View {
    let title: String
    var message: String?
    var systemImage: String = "info.circle"
    var tone: ESStatusBadge.Tone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: ESUI.Space.sm) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tone.color)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
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
        .padding(ESUI.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(tone.color.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
    }
}

typealias ESInfoBanner = ESStatusBanner

// MARK: - Empty / Loading / Error / Setup

struct ESEmptyState: View {
    let title: String
    var message: String?
    var systemImage: String = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: ESUI.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: ESUI.Space.xxs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ESUI.Space.xxl)
        .padding(.horizontal, ESUI.Space.md)
        .accessibilityElement(children: .combine)
    }
}

struct ESLoadingState: View {
    var message: String = "加载中…"

    var body: some View {
        VStack(spacing: ESUI.Space.sm) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ESUI.Space.xxl)
        .accessibilityElement(children: .combine)
    }
}

struct ESErrorState: View {
    let title: String
    var message: String?
    var retryTitle: String = "重试"
    var retry: (() -> Void)?

    var body: some View {
        ESEmptyState(
            title: title,
            message: message,
            systemImage: "exclamationmark.triangle",
            actionTitle: retry == nil ? nil : retryTitle,
            action: retry
        )
    }
}

struct ESNeedsSetupState: View {
    let title: String
    var message: String?
    var actionTitle: String = "去配置"
    var action: (() -> Void)?

    var body: some View {
        ESEmptyState(
            title: title,
            message: message,
            systemImage: "slider.horizontal.3",
            actionTitle: action == nil ? nil : actionTitle,
            action: action
        )
    }
}

// MARK: - Feature Entry Row

struct ESFeatureEntryRow: View {
    let title: String
    var summary: String?
    var systemImage: String
    var color: Color = .accentColor
    var status: FeatureStatusSummary?
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            ESFeatureIcon(systemName: systemImage, color: color, size: 40)

            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: ESUI.Space.xs)

            if let status {
                ESStatusBadge(text: status.text, tone: .from(kind: status.kind))
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(ESUI.Space.md)
        .esSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Settings Row

struct ESSettingsRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var iconColor: Color = .accentColor
    var statusText: String?
    var statusTone: ESStatusBadge.Tone = .neutral
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            if let systemImage {
                ESFeatureIcon(systemName: systemImage, color: iconColor, size: 36)
            }

            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: ESUI.Space.xs)

            if let statusText, !statusText.isEmpty {
                ESStatusBadge(text: statusText, tone: statusTone)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(ESUI.Space.md)
        .esSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Value Row

struct ESValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ESUI.Space.sm) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: ESUI.Space.xs)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

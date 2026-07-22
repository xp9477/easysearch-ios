import SwiftUI

// MARK: - Design Tokens (Light Studio · Gradient Bento)

enum ESUI {
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
    static let cardCornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 14
    static let tileCornerRadius: CGFloat = 20
    static let bottomTabSpacing: CGFloat = 88

    static var appBackground: Color { Color(.systemGroupedBackground) }
    static var surface: Color { Color(.secondarySystemGroupedBackground) }
    static var elevated: Color { Color(.secondarySystemBackground) }
    static var fill: Color { Color(.tertiarySystemFill) }
    static var elevatedBackground: Color { elevated }
    static var cardBackground: Color { surface }

    static let brandStart = Color(red: 0.43, green: 0.37, blue: 0.99) // #6D5EFC
    static let brandEnd = Color(red: 0.13, green: 0.83, blue: 0.93)   // #22D3EE
    static let success = Color(red: 0.20, green: 0.83, blue: 0.60)
    static let warning = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let danger = Color(red: 0.98, green: 0.44, blue: 0.52)

    enum ModuleAccent {
        static let ut = (Color(red: 0.31, green: 0.40, blue: 0.95), Color(red: 0.45, green: 0.68, blue: 1.0))
        static let expense = (Color(red: 0.98, green: 0.55, blue: 0.20), Color(red: 1.0, green: 0.72, blue: 0.30))
        static let qingLong = (Color(red: 0.10, green: 0.72, blue: 0.48), Color(red: 0.30, green: 0.88, blue: 0.65))
        static let translate = (Color(red: 0.56, green: 0.35, blue: 0.98), Color(red: 0.72, green: 0.52, blue: 1.0))
        static let email = (Color(red: 0.12, green: 0.62, blue: 0.90), Color(red: 0.35, green: 0.80, blue: 0.96))
        static let webdav = (Color(red: 0.16, green: 0.42, blue: 0.88), Color(red: 0.28, green: 0.62, blue: 0.98))
        static let utilities = (Color(red: 0.35, green: 0.40, blue: 0.48), Color(red: 0.55, green: 0.60, blue: 0.68))
        static let hidden = (Color(red: 0.48, green: 0.32, blue: 0.90), Color(red: 0.70, green: 0.45, blue: 0.98))

        static func pair(for featureID: String) -> (Color, Color) {
            switch featureID {
            case "uttracker": return ut
            case "expense-assistant": return expense
            case "qinglong-management": return qingLong
            case "image-translate": return translate
            case "email-assistant": return email
            case "webdav": return webdav
            case "utilities": return utilities
            case "hidden-space": return hidden
            default: return (ESUI.brandStart, ESUI.brandEnd)
            }
        }
    }
}

// MARK: - Brand Gradient

enum ESBrandGradient {
    static var linear: LinearGradient {
        LinearGradient(
            colors: [ESUI.brandStart, ESUI.brandEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func module(_ featureID: String) -> LinearGradient {
        let pair = ESUI.ModuleAccent.pair(for: featureID)
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func fill(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(linear)
    }
}

// MARK: - Button Style

struct ESCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: configuration.isPressed)
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
                    .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            )
    }

    func esSurface(cornerRadius: CGFloat = ESUI.cardCornerRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ESUI.surface)
                .shadow(color: Color.black.opacity(0.035), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }

    func esAppearSoft(_ delay: Double = 0) -> some View {
        modifier(ESSoftAppearModifier(delay: delay))
    }
}

private struct ESSoftAppearModifier: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.9).delay(delay)) {
                    shown = true
                }
            }
    }
}

// MARK: - Hero Header

struct ESHeroHeader: View {
    var eyebrow: String?
    let title: String
    var subtitle: String?
    var trailing: AnyView?

    init(eyebrow: String? = nil, title: String, subtitle: String? = nil, trailing: AnyView? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: ESUI.Space.sm) {
            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                if let eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ESUI.brandStart)
                        .tracking(0.6)
                }

                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: ESUI.Space.xs)

            if let trailing {
                trailing
            }
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [ESUI.brandStart.opacity(0.35), ESUI.brandEnd.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status Strip

struct ESStatusStripItem: Identifiable {
    let id: String
    let title: String
    let value: String
    var tone: ESStatusBadge.Tone = .neutral
}

struct ESStatusStrip: View {
    let items: [ESStatusStripItem]

    var body: some View {
        HStack(spacing: ESUI.Space.xs) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                    Text(item.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(item.value)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(item.tone.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ESUI.Space.sm)
                .padding(.vertical, ESUI.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .fill(ESUI.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .stroke(item.tone.color.opacity(0.18), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Module Tile (Bento)

struct ESModuleTile: View {
    let title: String
    var summary: String?
    var systemImage: String
    var featureID: String
    var status: FeatureStatusSummary?
    var isWide: Bool = false
    var customIcon: AnyView? = nil

    var body: some View {
        let pair = ESUI.ModuleAccent.pair(for: featureID)

        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(alignment: .top) {
                if let customIcon {
                    customIcon
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: pair.0.opacity(0.28), radius: 8, y: 3)

                        Image(systemName: systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
                }

                Spacer(minLength: 0)

                if let status {
                    ESStatusBadge(text: status.text, tone: .from(kind: status.kind))
                }
            }

            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text(title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isWide ? 2 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(ESUI.Space.md)
        .frame(maxWidth: .infinity, minHeight: isWide ? 112 : 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: ESUI.tileCornerRadius, style: .continuous)
                .fill(ESUI.surface)
                .shadow(color: Color.black.opacity(0.05), radius: 12, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.tileCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [pair.0.opacity(0.28), pair.1.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Module Page Chrome

struct ESModuleHero: View {
    let title: String
    var subtitle: String?
    var featureID: String
    var systemImage: String

    var body: some View {
        let pair = ESUI.ModuleAccent.pair(for: featureID)

        HStack(spacing: ESUI.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)

                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(colors: [pair.0.opacity(0.35), pair.1.opacity(0.15)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1
                )
        )
    }
}

struct ESPrimaryCTA: View {
    let title: String
    var systemImage: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ESUI.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ESUI.Space.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                    .fill(ESBrandGradient.linear)
                    .opacity(enabled ? 1 : 0.45)
            )
        }
        .buttonStyle(ESCardButtonStyle())
        .disabled(!enabled)
    }
}

struct ESActionChip: View {
    let title: String
    var systemImage: String?
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, ESUI.Space.sm)
            .padding(.vertical, ESUI.Space.xs)
            .background {
                if isSelected {
                    Capsule().fill(ESBrandGradient.linear)
                } else {
                    Capsule().fill(ESUI.fill)
                }
            }
        }
        .buttonStyle(.plain)
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
                    .font(.headline.weight(.bold))
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
    var gradient: LinearGradient? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(gradient ?? LinearGradient(colors: [color.opacity(0.18), color.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))

            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(gradient == nil ? color : .white)
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
            case .accent: return ESUI.brandStart
            case .success: return ESUI.success
            case .warning: return ESUI.warning
            case .danger: return ESUI.danger
            }
        }

        static func from(kind: FeatureStatusKind) -> Tone {
            switch kind {
            case .ready: return .success
            case .needsConfiguration, .needsAuthorization, .attentionNeeded: return .warning
            case .empty: return .neutral
            case .processing: return .accent
            case .offlineOrUnavailable, .recoverableFailure: return .danger
            }
        }
    }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tone.color.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .stroke(tone.color.opacity(0.18), lineWidth: 1)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

// MARK: - Banner

/// Compatibility alias used by module views (same as ESStatusBanner).
typealias ESInfoBanner = ESStatusBanner

/// Compatibility alias (v1 name).
typealias ESStatusPill = ESStatusBadge

struct ESStatusBanner: View {
    let title: String
    var message: String?
    var systemImage: String = "info.circle"
    var tone: ESStatusBadge.Tone = .accent

    var body: some View {
        HStack(alignment: .top, spacing: ESUI.Space.sm) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tone.color)
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
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(tone.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - Empty / Loading / Error

struct ESEmptyState: View {
    let title: String
    var message: String?
    var systemImage: String = "tray"
    var actionTitle: String?
    var action: (() -> Void)?
    var minHeight: CGFloat? = nil

    var body: some View {
        VStack(spacing: ESUI.Space.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(ESUI.brandStart.opacity(0.85))
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(ESUI.brandStart)
                    .padding(.top, ESUI.Space.xs)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
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
                    .font(.body.weight(.medium))
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

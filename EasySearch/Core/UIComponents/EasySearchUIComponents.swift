import SwiftUI
import UIKit

// MARK: - Design Tokens (Native iOS · Liquid Glass)

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
    static let cardCornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 12
    static let tileCornerRadius: CGFloat = 16

    static var appBackground: Color { Color(.systemGroupedBackground) }
    static var surface: Color { Color(.secondarySystemGroupedBackground) }
    static var elevated: Color { Color(.secondarySystemBackground) }
    static var fill: Color { Color(.tertiarySystemFill) }
    static var elevatedBackground: Color { elevated }
    static var cardBackground: Color { surface }

    static let accent = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red

    /// Single system color per module (settings-style tinted icons).
    static func moduleColor(for featureID: String) -> Color {
        switch featureID {
        case "uttracker": return .indigo
        case "training-log": return .red
        case "expense-assistant": return .orange
        case "qinglong-management": return .green
        case "image-translate": return .purple
        case "email-assistant": return .teal
        case "ai-assistant": return .purple
        case "webdav": return .blue
        case "currency": return .gray
        case "utilities": return .gray
        case "hidden-space": return Color(.systemPurple)
        default: return .blue
        }
    }
}

// MARK: - Haptics

/// 统一触觉反馈,保持轻量:选择切换用 selection,点击用 light,结果用 success/warning。
enum ESHaptics {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Motion

/// 动效 token。遵循两条硬规则:
/// 1. UI 动画一律 < 300ms,越频繁的操作动得越少;
/// 2. 开启「减弱动态效果」时降级为纯淡入淡出,绝不 spring / 位移。
enum ESMotion {
    private static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// 按压反馈:高频动作动得越少越好,固定 140ms ease-out。
    static var press: Animation {
        .easeOut(duration: 0.14)
    }

    /// 高频切换(分类、日期、状态胶囊)。
    static var quick: Animation {
        reduceMotion ? .linear(duration: 0.12) : .spring(duration: 0.24, bounce: 0)
    }

    /// 内容出现、结果切换等低频转场。
    static var content: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.32, bounce: 0.08)
    }

    /// 进度条、环形进度等数值补间。
    static var value: Animation {
        reduceMotion ? .linear(duration: 0.16) : .spring(duration: 0.45, bounce: 0)
    }

    /// 内容插入/移除的过渡:减弱动态时只做淡入淡出。
    static var appear: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .bottom))
    }

    /// 顶部横幅/toast。
    static var reduceMotionSafeTopBanner: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    /// 元素在原地出现(译文卡、气泡)。永不从 scale(0) 开始。
    static var pop: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.96))
    }
}

// MARK: - Button Style

struct ESCardButtonStyle: ButtonStyle {
    var haptics: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(ESMotion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                guard haptics, isPressed else { return }
                ESHaptics.tap()
            }
    }
}

// MARK: - View Chrome

extension View {
    func esScreenBackground() -> some View {
        background(ESUI.appBackground.ignoresSafeArea())
    }

    /// iOS 26 native TabView manages bottom safe-area automatically.
    func esBottomTabPadding(_ extra: CGFloat = 0) -> some View {
        padding(.bottom, extra)
    }

    /// Flat grouped-style card (no custom shadows / strokes).
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

// MARK: - Module Tile (Workbench)

struct ESModuleTile: View {
    let title: String
    var summary: String? = nil
    var systemImage: String
    var featureID: String
    var status: FeatureStatusSummary? = nil
    /// Compact numeric badge (e.g. overdue expense count). Preferred over status text.
    var badgeCount: Int? = nil
    var isWide: Bool = false
    var customIcon: AnyView? = nil

    var body: some View {
        let color = ESUI.moduleColor(for: featureID)

        HStack(spacing: ESUI.Space.sm) {
            if let customIcon {
                customIcon
            } else {
                ESFeatureIcon(systemName: systemImage, color: color, size: 40)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            if let badgeCount, badgeCount > 0 {
                Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(ESUI.danger))
            }
        }
        .padding(.horizontal, ESUI.Space.sm + 2)
        .padding(.vertical, ESUI.Space.sm + 2)
        .frame(maxWidth: .infinity, minHeight: isWide ? 56 : 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ESUI.tileCornerRadius, style: .continuous)
                .fill(ESUI.surface)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var accessibilityLabelText: String {
        if let badgeCount, badgeCount > 0 {
            return "\(title)，\(badgeCount)"
        }
        return title
    }
}

// MARK: - Module Hero

struct ESModuleHero: View {
    let title: String
    var subtitle: String?
    var featureID: String
    var systemImage: String

    var body: some View {
        let color = ESUI.moduleColor(for: featureID)

        HStack(spacing: ESUI.Space.sm) {
            ESFeatureIcon(systemName: systemImage, color: color, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
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
    }
}

// MARK: - Primary CTA

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
            .frame(maxWidth: .infinity)
            .padding(.vertical, ESUI.Space.xs)
        }
        .buttonStyle(.glassProminent)
        .disabled(!enabled)
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                .fill(color.opacity(0.15))

            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .medium))
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
            case .accent: return ESUI.accent
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
            .font(.caption.weight(.medium))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tone.color.opacity(0.12)))
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
                .font(.title3)
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
                .fill(tone.color.opacity(0.1))
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
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message, !message.isEmpty {
                Text(message)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
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
                    .font(.body)
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
                    .font(.footnote.weight(.semibold))
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
                ESFeatureIcon(systemName: systemImage, color: iconColor, size: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
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

            Spacer(minLength: ESUI.Space.sm)

            if let statusText, !statusText.isEmpty {
                ESStatusBadge(text: statusText, tone: statusTone)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, ESUI.Space.md)
        .padding(.vertical, ESUI.Space.sm)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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

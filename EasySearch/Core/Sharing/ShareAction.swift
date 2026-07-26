import SwiftUI

/// Protocol for share-inbox destinations. Core lists actions without owning feature UIs.
@MainActor
protocol ShareActionHandling: Identifiable {
    var id: String { get }
    var title: String { get }
    var systemImage: String { get }
    var isAvailable: Bool { get }

    /// Destination pushed when the user picks this action.
    func destination(
        items: [SharedInboxItem],
        onCompleted: @escaping () -> Void
    ) -> AnyView
}

/// Built-in reserved placeholder (not navigable).
struct ReservedShareAction: ShareActionHandling {
    let id = "reserved"
    let title = "其他功能"
    let systemImage = "ellipsis.circle"
    let isAvailable = false

    func destination(items: [SharedInboxItem], onCompleted: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }
}

/// Registry of share actions. Features register handlers at app launch.
@MainActor
enum ShareActionRegistry {
    private(set) static var actions: [any ShareActionHandling] = [
        ReservedShareAction()
    ]

    static func register(_ action: any ShareActionHandling) {
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
            return
        }
        if let reservedIndex = actions.firstIndex(where: { $0.id == "reserved" }) {
            actions.insert(action, at: reservedIndex)
        } else {
            actions.append(action)
        }
    }
}

import SwiftUI

/// Centralized navigation router for cross-feature navigation.
public class AppRouter: ObservableObject {
    @Published public var path = NavigationPath()
    
    public init(initialDestination: (any Hashable)? = nil) {
        if let destination = initialDestination {
            self.path.append(destination)
        }
    }
    
    public func navigate(to destination: any Hashable) {
        path.append(destination)
    }
    
    public func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }
    
    public func popToRoot() {
        path.removeLast(path.count)
    }
}

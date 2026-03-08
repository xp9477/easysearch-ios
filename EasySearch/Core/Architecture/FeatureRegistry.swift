import SwiftUI

/// Central registry for all available features in the app.
public class FeatureRegistry: ObservableObject {
    @Published public var features: [any AppFeature] = []
    
    public init() {
        registerDefaultFeatures()
    }
    
    private func registerDefaultFeatures() {
        features.append(EasySearchFeature())
        features.append(UTTrackerFeature())
        features.append(UtilitiesFeature())
    }
}

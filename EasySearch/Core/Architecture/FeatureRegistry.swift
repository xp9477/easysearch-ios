import SwiftUI

/// Central registry for all available features in the app.
public class FeatureRegistry: ObservableObject {
    @Published public var features: [any AppFeature] = []

    public var primaryTabFeatures: [any AppFeature] {
        features.filter { $0.placement == .primaryTab }
    }

    public var moduleListFeatures: [any AppFeature] {
        features.filter { $0.placement == .moduleList }
    }

    public var hiddenFeatures: [any AppFeature] {
        features.filter { $0.placement == .hiddenModule }
    }
    
    public init() {
        registerDefaultFeatures()
    }
    
    private func registerDefaultFeatures() {
        features.append(EasySearchFeature())
        features.append(UTTrackerFeature())
        features.append(UtilitiesFeature())
        features.append(HiddenSpaceFeature())
    }
}

public struct HiddenSpaceFeature: AppFeature {
    public var id: String = "hidden-space"
    public var title: String = "隐藏空间"
    public var summary: String = "保留给后续隐藏模块和特殊入口。"
    public var iconName: String = "eye.slash"
    public var color: Color = .purple
    public var placement: AppFeaturePlacement = .hiddenModule

    public init() {}

    public var entryView: AnyView {
        AnyView(HiddenSpaceView())
    }
}

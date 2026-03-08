# EasySearch iOS 文件结构

```text
easysearch-ios
├── EasySearch.xcodeproj
└── EasySearch
    ├── App
    │   └── EasySearchApp.swift
    ├── Core
    │   ├── Architecture
    │   │   ├── AppFeature.swift
    │   │   └── FeatureRegistry.swift
    │   ├── Navigation
    │   │   └── AppRouter.swift
    │   ├── Extensions
    │   └── UIComponents
    ├── Features
    │   ├── Dashboard
    │   │   └── Views
    │   │       └── DashboardView.swift
    │   ├── EasySearch
    │   │   ├── EasySearchFeature.swift
    │   │   ├── Models
    │   │   │   └── SearchEngine.swift
    │   │   ├── ViewModels
    │   │   │   └── SearchViewModel.swift
    │   │   └── Views
    │   │       ├── CategoryTabBar.swift
    │   │       ├── EasySearchView.swift
    │   │       ├── EngineGridView.swift
    │   │       └── SearchBar.swift
    │   ├── Settings
    │   │   └── Views
    │   │       └── SettingsView.swift
    │   ├── UTTracker
    │   │   ├── Models
    │   │   │   └── UTEntry.swift
    │   │   ├── ViewModels
    │   │   │   └── UTTrackerViewModel.swift
    │   │   ├── Views
    │   │   │   └── UTTrackerView.swift
    │   │   ├── UTNotificationManager.swift
    │   │   └── UTTrackerFeature.swift
    │   └── Utilities
    │       ├── Views
    │       │   └── UtilitiesView.swift
    │       └── UtilitiesFeature.swift
    ├── Resources
    │   └── search-engines.json
    ├── Assets.xcassets
    └── Info.plist
```

## 分层约定

- `App`: 应用入口与生命周期。
- `Core`: 跨模块基础能力（架构协议、全局路由、公共组件）。
- `Features`: 按业务模块拆分，每个模块优先采用 `Models` / `ViewModels` / `Views` 子目录。
- `Resources`: 非代码资源（JSON 配置等）。

## 新增文件建议

- 新功能优先落到对应 `Features/<FeatureName>/`。
- 跨 Feature 的可复用 UI 放在 `Core/UIComponents`。
- 公共扩展放在 `Core/Extensions`。

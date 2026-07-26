# EasySearch iOS 文件结构

```text
easysearch-ios
├── EasySearch.xcodeproj
├── EasySearchShare/                 # Share Extension → App Group 收件箱
├── EasySearchTests/
├── supabase/                        # 云端 schema 参考
└── EasySearch
    ├── App/
    │   └── EasySearchApp.swift      # Tab 壳、生命周期、注入 Registry/Cloud/Status
    ├── Core/
    │   ├── Architecture/            # AppFeature、FeatureRegistry、FeatureStatusCenter
    │   ├── AI/                      # DeepSeekClient、OCR、AIConfigurationStore
    │   ├── CloudSync/               # Coordinator、Supabase 后端、CloudSyncViewModel
    │   ├── Security/                # 共享 KeychainStore
    │   ├── Sharing/                 # Share inbox + ShareAction 协议
    │   └── UIComponents/
    ├── Features/
    │   ├── EasySearch/              # 主 Tab：多引擎搜索启动器
    │   ├── Dashboard/               # 工作台 + Hidden Space + HiddenSpaceFeature
    │   ├── UTTracker/               # UT 记录（可上云）
    │   ├── TrainingLog/             # 训练记录（仅本地）
    │   ├── ExpenseAssistant/        # 报销助手（仅本地）
    │   ├── ImageTranslate/          # 翻译（依赖 Core AI）
    │   ├── EmailAssistant/          # 邮件助手（依赖 Core AI）
    │   ├── QingLong/                # 青龙面板（profile 可上云，密钥本地）
    │   ├── WebDAV/                  # WebDAV + 分享入库动作
    │   ├── Utilities/               # 汇率等
    │   └── Settings/                # 设置壳 + 云同步/AI 设置页
    ├── Resources/
    └── Assets.xcassets
```

## 分层约定

- **App**: 入口、生命周期、全局注入。
- **Core**: 横切能力（架构协议、云同步、AI 配置、Keychain、分享协议、UI 组件）。
- **Features**: 业务模块；`*Feature.swift` 声明入口与 `statusSummary()`。
- 新功能优先落到 `Features/<Name>/`；跨模块可复用能力放 Core。

## 云同步归属

- **唯一全量同步入口**: `CloudSyncViewModel`（`Core/CloudSync`）。
- 隐藏空间 / JavDB / 4KHD ViewModel **不得**再实现独立 full-sync；仅本地突变 + 可选单条 upsert。
- 当前集合：Jav 收藏/播放点、4KHD 相册/图、UT、青龙 profile。

## 状态中心

- `FeatureStatusCenter` 通过 `registry` 调用各 `AppFeature.statusSummary()`。
- 云 / AI 的横切摘要仍由 StatusCenter 维护。

## 文档

- 数据与模块地图：`docs/architecture-module-map.md`

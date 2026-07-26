# EasySearch 模块与数据地图

瑞士军刀定位：多模块个人工具合集。不追求统一产品叙事，但横切能力归属必须清晰。

## 模块一览

| 模块 | Feature ID | 放置 | 本地存储 | 云同步 | 密钥 |
|------|------------|------|----------|--------|------|
| 搜索 | easysearch | 主 Tab | 引擎配置 UserDefaults | 否（远程 JSON 配置） | — |
| UT 记录 | uttracker | 工作台 | UserDefaults | 是 | — |
| 训练记录 | training-log | 工作台 | UserDefaults | 是（按日） | — |
| 报销助手 | expense-assistant | 工作台 | UserDefaults | 是（月度 + 出差） | — |
| 翻译 | image-translate | 工作台 | 会话文件 + 目标语言 | 否 | AI Key → Keychain |
| 邮件助手 | email-assistant | 工作台 | 内存/本地偏好 | 否 | 共用 AI Key |
| 青龙 | qinglong-management | 工作台 | profile UserDefaults | profile 是 | client secret → Keychain |
| WebDAV | webdav | 工作台 | 位置配置 + 本地文件 | **否** | 密码 → Keychain |
| 实用工具 | utilities | 工作台 | 汇率缓存 | 否 | — |
| 隐藏空间 | hidden-space | 隐藏 | 收藏 UserDefaults | 是（收藏/播放点） | 会话 → Keychain |

## 横切能力

| 能力 | 所有者 | 说明 |
|------|--------|------|
| 云同步 | `Core/CloudSync/CloudSyncViewModel` | 登录、全量 sync、增量 mutation API |
| AI 配置 | `Core/AI/AIConfigurationStore` | baseURL / API key / model；翻译另存目标语言 |
| Keychain | `Core/Security/KeychainStore` | 通用 SecItem 封装 |
| 模块状态 | 各 `AppFeature.statusSummary()` | StatusCenter 汇总 |
| 系统分享 | `ShareActionRegistry` + 各 Feature 动作 | WebDAV 入库已注册 |
| 隐藏隐私 | Dashboard 连点解锁 + 后台遮罩 | **非**加密保险箱 |

## 依赖方向（目标）

```
App → Core + Features
Features → Core
Core 不依赖具体 Feature Store（状态由 Feature 自报）
Email → Core AI（不依赖 ImageTranslate）
UT / 训练 / 报销 / 青龙 / Hidden → CloudSyncViewModel（中性 API）
```

## 安全预期

- 隐藏空间：防旁窥，不是 Face ID 保险箱。
- 勿把真实 AI Key 打进 IPA 的 Info.plist。
- 搜索远程配置失败时应回退本地缓存（SearchViewModel 行为）。

# EasySearch 外部存储与文件提供者指南 (External Storage & FileProvider)

> **重要声明与前置提示**
> 1. **免责与真机兼容性声明**：当前验证基于 Linux 环境静态结构审查、PBX 解析与 CI 自动化打包断言，**不承诺在所有物理真机与特定企业证书环境下完全通过**。实际真机运行表现取决于局域网环境、存储端协议兼容性及证书重签名权限。
> 2. **重签名硬性要求**：使用自签、企业证书或侧载工具（如 AltStore / Sideloadly / TrollStore）重签 `EasySearch-unsigned.ipa` 时，**必须完整保留 `PlugIns/EasySearchFileProvider.appex` 与 `PlugIns/EasySearchShare.appex`**，且主 App 与所有扩展必须配置相同的 App Group：`group.com.easysearch.xp9477`。缺失 App Group 或丢弃扩展将导致外部存储在系统「文件」App 中不可用、凭据同步失效。

---

## 1. 快速入门与连接格式

EasySearch 支持同时配置多个外部存储源，支持 WebDAV 与 SMB 两种主流网络存储协议。

### 1.1 WebDAV 连接格式

WebDAV 协议基于 HTTP/HTTPS，支持公网及局域网直连：

| 配置项 | 示例 / 说明 |
|---|---|
| **协议** | `http://`（明文，仅限受信任局域网）或 `https://`（推荐） |
| **服务器地址** | `https://dav.example.com` 或 `http://192.168.1.100:5005` |
| **路径前缀** | 可留空（根路径 `/`）或指定子目录，如 `/dav`、`/remote.php/webdav` |
| **认证凭据** | 用户名 + 密码或应用专用密码（App Password） |

### 1.2 SMB (Samba) 连接格式

SMB 基于 SMB2/3 协议，由底层 `AMSMB2`（封装 `libsmb2`）驱动：

| 配置项 | 示例 / 说明 |
|---|---|
| **URL 格式** | `smb://host[:port]/share[/path]` |
| **主机地址** | `192.168.1.50` 或 `nas.local`（支持 mDNS / DNS / IP） |
| **端口** | 默认 `445`（若自定义端口需在地址显式标注，如 `:1445`） |
| **共享名 (Share)** | 必填顶级共享文件夹名称，如 `data`、`shared`、`public` |
| **认证凭据** | 用户名与密码在表单中单独填写；**禁止在 URL 中内联凭据（如 `user:password@`）**，违规输入会被拒绝以防止凭据明文落盘 |

> **网络环境限制**：SMB 协议使用的 TCP 445 端口通常被蜂窝移动网络运营商及公网防火墙拦截封锁。建议通过同一局域网（Wi-Fi）或虚拟专用网（VPN / WireGuard / Tailscale）访问 SMB；实际连通性以服务器网络配置为准。

---

## 2. 功能特性与读写限制

### 2.1 多存储源管理
- 可在 EasySearch 设置中添加、重命名或删除任意数量的 WebDAV 和 SMB 节点。
- 主 App 保存配置后，会自动通过 `ExternalStorageSharedStore` 同步至 App Group 共享容器，并安全镜像凭据至共享 Keychain。

### 2.2 读写与下载机制
- **文件浏览与元数据缓存**：按需拉取目录项并缓存至本地内存与持久化注册表（`ExternalStorageItemRegistry`）。
- **读写操作**：支持普通文件的下载、预览、上传、删除、重命名与跨目录移动。
- **根目录保护约束**：在系统 Files App 中，每个存储源的根目录（Root Container）受系统安全策略保护，**严禁对根目录本身执行重命名、移动或删除操作**；尝试修改根目录将抛出 `rootOperationForbidden` 错误。

### 2.3 视频播放特殊限制
- **WebDAV**：使用 HTTP Byte-Range 在线读取，iOS 系统播放器可进行在线流式缓冲播放。
- **SMB**：由于底层 SMB 协议实现不接入 AVPlayer 原生流媒体管道，**SMB 存储中的视频文件必须先下载到本地缓存后再行播放**，不支持直接边下边播。

---

## 3. iOS 系统「文件」(Files) App 启用步骤

当 App 安装并成功配置存储源后，按以下步骤在系统级文件管理中启用：

```text
打开 iOS 系统自带「文件」App
       │
       ▼
点击底部「浏览」标签页
       │
       ▼
点击右上角「···」操作按钮 ➔ 选择「编辑」
       │
       ▼
在「位置」列表中找到「EasySearch 存储」➔ 开启右侧开关
       │
       ▼
点击右上角「完成」
```

启用后，「EasySearch 存储」将出现在侧边栏位置列表中，展开即可直接访问已配置的所有 WebDAV 与 SMB 目录。

---

## 4. 签名与安全机制

### 4.1 扩展架构与 App Group
- 主 App (`EasySearch`) 与文件提供者扩展 (`EasySearchFileProvider`) 均配置了应用组：`group.com.easysearch.xp9477`。
- 架构遵循单向数据管道与进程间文件锁（`ProcessFileLock`），保证并发访问安全性。
- 敏感账户密码存储在 Keychain 中，利用相同的访问组与主从同步机制，不向 `Info.plist` 或无保护文件明文暴露。

### 4.2 重签名注意事项
若使用企业证书重签或开发者侧载：
1. **保留所有 Targets**：签名工具不可剔除 `PlugIns/EasySearchFileProvider.appex` 和 `PlugIns/EasySearchShare.appex`。
2. **Entitlements 完整映射**：主 App 与扩展必须同时被授予相匹配的 `com.apple.security.application-groups`。
3. **动态库依赖路径**：`EasySearchFileProvider` 的 Runpath 包含 `@executable_path/../../Frameworks`，主 App 的 `Embed Frameworks` 包含唯一的 `AMSMB2.framework` 副本，重签时务必保证 Frameworks 目录完整。

---

## 5. 配置清单与静态核对记录 (Configuration Checklist)

| 检查项 | 验证内容 | 状态 |
|---|---|:---:|
| **Target 结构** | `EasySearchFileProvider` 作为 `com.apple.product-type.app-extension` 注册于 project.pbxproj | 已配置 |
| **Bundle ID** | 扩展 Bundle ID 为 `com.easysearch.xp9477.FileProvider` | 已配置 |
| **部署版本** | `IPHONEOS_DEPLOYMENT_TARGET = 26.0`，`SWIFT_VERSION = 5.0` | 已配置 |
| **版本一致性** | 扩展集成 `Dynamic Build Version` 脚本，保证主应用与扩展 build number 动态对齐 | 已配置 |
| **源码归属 (App)** | App 包含 `ExternalStorage/*.swift`、`SMBStorageClient.swift`、`WebDAVMovePickerView.swift`，以及为测试可见性引入的 `Registry`、`Item`、`Enumerator` | 已配置 |
| **源码归属 (FP)** | Extension 包含 `ExternalStorage` 共享层（Models、Error、SharedStore、ClientProtocol）、FileProvider 核心实现（Registry、Item、Enumerator、Extension），以及适配层所需的 `WebDAVModels.swift`、`WebDAVClient.swift`、`WebDAVLocalFileStore.swift`、`SMBStorageClient.swift` | 已配置 |
| **依赖与运行路径** | App Target 唯一 Embed `AMSMB2.framework`；Extension 链接 `AMSMB2` 并配置 `@executable_path/../../Frameworks` | 已配置 |
| **本地网络权限** | `EasySearch/Info.plist` 与 `EasySearchFileProvider/Info.plist` 均具备包含 SMB 用途的 `NSLocalNetworkUsageDescription` | 已配置 |
| **枚举能力支持** | `EasySearchFileProvider/Info.plist` 包含 `NSExtensionFileProviderSupportsEnumeration = true` | 已配置 |
| **第三方协议授权** | `EasySearch/Resources/ExternalStorageLicenses.txt` 完整收录 AMSMB2 4.0.3 及 libsmb2 LGPL-2.1 / BSD 许可全文 | 已配置 |
| **CI 打包断言** | GitHub Actions 包含对 `EasySearchFileProvider.appex`、`AMSMB2.framework` 及主扩展版本一致性断言 | 已配置 |
| **验证范围约束** | 本次验证在 Linux 容器环境下使用 `pbxproj` / 静态分析完成工程树与配置对齐，未执行真机运行时验证 | 已记录 |

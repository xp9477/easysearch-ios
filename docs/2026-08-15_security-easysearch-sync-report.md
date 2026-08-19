# EasySearch 云同步与发布链路安全审计报告

> 审计日期：2026-08-15
> 审计类型：白盒源代码、数据一致性、SwiftUI、CI/CD 与公开 Git 历史
> 授权状态：仓库所有者已明确授权审计与修复

## 先读结论

本轮已直接封堵三条 P0 链路：青龙凭证被云端地址变更带往新主机、Supabase refresh 在退出后复活旧会话、隐藏模块绕过账号绑定直接写云端。同时启用了 83 项既有测试的 CI 门禁，修复训练记录删除复活的第一阶段协议，并清理当前代码树中的构建产物。

仍不能宣称“多设备同步已严格收敛”。除训练记录外，多数 collection 仍使用物理删除、设备时间或无版本并集；本地数据也尚未按项目与用户分桶。后续必须遵循“先数据库 migration、再客户端协议”的发布顺序，不能只改 Swift 合并函数。

## Scope 摘要

| 项目 | 范围 |
|---|---|
| 授权 | 用户明确授权本仓库的读取、修改、CI 验证与 GitHub 推送 |
| in scope | iOS 主 App、Share Extension、Supabase 客户端、SQL bootstrap/migration、GitHub Actions、公开 Git 历史 |
| out of scope | 未取得管理凭证的线上 Supabase DDL、外部青龙/WebDAV 服务本身、第三方签名服务 |
| 网络策略 | 仅访问仓库 GitHub API/Actions；未使用 publishable key 尝试管理操作或绕过权限 |
| 工作目录 | 仓库根目录；未建立包含真实密钥的报告附件 |

## Evidence

| E-id | source_ref | repro_command | content_hash |
|---|---|---|---|
| E-01 | `EasySearch/Core/CloudSync/CloudSyncService.swift` | `rg -n "refreshSessionIfNeeded|sessionGeneration|refreshOperation|expectedUserID" EasySearch/Core/CloudSync/CloudSyncService.swift` | n/a（Git 跟踪源文件） |
| E-02 | `EasySearch/Features/QingLong/` | `rg -n "endpointIdentity|credentialsRequireReconnect|redactedURLForDisplay" EasySearch/Features/QingLong` | n/a（Git 跟踪源文件） |
| E-03 | 隐藏模块远端写入口 | `rg -n "HiddenSupabaseService\\.shared" EasySearch/Features`，预期无结果 | n/a |
| E-04 | 单元测试门禁 | `xcodebuild test -project EasySearch.xcodeproj -scheme EasySearch -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' CODE_SIGNING_ALLOWED=NO` | CI 保存 `.xcresult` |
| E-05 | Workflow 静态校验 | `actionlint -color=false .github/workflows/build-unsigned-ipa.yml` | n/a |
| E-06 | 历史残留验证 | `git rev-list --objects --all | cut -d' ' -f2- | rg '^(output/|\\.playwright-cli/|.*xcuserdata/|\\.codex-.*\\.png$)'`，历史改写后预期无结果 | n/a |
| E-07 | 第三方依赖面 | `rg -n "PBXRemoteSwiftPackageReference|XCRemoteSwiftPackageReference" EasySearch.xcodeproj/project.pbxproj`，并检查 SPM/CocoaPods/Carthage lockfile，预期无结果 | n/a |

## Findings

| F-id | severity | evidence_ids | confidence | location | status |
|---|---|---|---|---|---|
| F-01 青龙凭证与 endpoint 未绑定 | 严重 | E-02 | 高 | `Features/QingLong` | 已修复，旧凭证需重连一次 |
| F-02 refresh 可在 sign-out 后复活会话 | 严重 | E-01、E-04 | 高 | `CloudSyncService` | 已修复并加入确定性竞态测试 |
| F-03 JAV/4K mutation 绕过账号边界 | 严重 | E-01、E-03 | 高 | Dashboard ViewModel / `CloudSyncViewModel` | 已修复，统一 façade + expected user |
| F-04 未知训练单位可被误判为 tombstone | 高 | E-01、E-04 | 高 | training remote DTO | 已修复，整条 collection fail-closed |
| F-05 删除协议无法在所有设备收敛 | 高 | E-01 | 高 | JAV、4K、UT、报销、青龙 | 部分修复；训练已有 tombstone，其余需 schema-first migration |
| F-06 本地存储未按 project/user 隔离 | 高 | E-01 | 高 | UserDefaults / Keychain | 风险已用账号绑定保险丝暂停；完整分桶尚未实现 |
| F-07 公开历史含生成物与旧开发包元数据 | 高 | E-06 | 高 | Git history | 当前树已清；历史需受控改写并使旧 profile 失效 |
| F-08 PostgREST fetch 无分页 | 中 | E-01 | 高 | collection fetch API | 未修复；超过服务端上限会静默缺页 |
| F-09 月度报销无真实 updatedAt | 中 | E-01 | 高 | expense DTO / merge | 未修复；离线状态回退可能被远端覆盖 |
| F-10 CI 未跑测试且非生产分支可发布 latest | 高 | E-04、E-05 | 高 | GitHub Actions | 已修复；测试、生产并发锁、分支门禁与单调 build 已启用 |
| F-11 Actions 供应链缺少持续更新 | 中 | E-05、E-07 | 高 | GitHub Actions | 已修复；官方 action 固定 commit SHA，并由 Dependabot 每月分组检查更新 |

## Path

### P-01：青龙 confused-deputy 路径

`path_type=callflow`，关联 F-01：

1. 同账号另一设备同步新的青龙 `baseURL`。
2. 本机保存远端 profile 并发布配置变化通知。
3. 页面自动刷新，从全局 Keychain 读取旧 `client_id/client_secret`。
4. 旧实现将凭证作为 query 发送给新主机。
5. 修复后，凭证 JSON 带规范化 endpoint identity；主机、协议、端口或部署路径任一变化都 fail-closed，并清空 cached session。

### P-02：退出后会话复活路径

`path_type=callflow`，关联 F-02：

1. access token 临期，actor 发起 refresh 后在网络 `await` 处重入。
2. 用户退出，内存与 Keychain 会话被清除。
3. 旧 refresh 返回并再次持久化会话。
4. 修复后，sign-in/sign-out/账号替换都会推进 generation；refresh 单飞，所有 await 返回后校验 generation、token 与 user ID，旧操作只能失败。

### P-03：账号绑定旁路路径

`path_type=callflow`，关联 F-03、F-06：

1. 设备本地数据属于账号 A，用户登录账号 B。
2. 全局同步因 identity mismatch 被暂停，但功能 ViewModel 仅检查“已登录”。
3. 功能层直接调用 service，使用 B token 写入 A 的本地对象；RLS 会把它视为 B 的合法请求。
4. 修复后，功能层不再持有 service。所有 mutation 经 façade 校验绑定用户，并把 expected user ID 交给 actor 在构造请求前再次校验。

## 当前安全不变量

- 任何含本机 secret 的青龙请求，只能发往凭证保存时绑定的规范化 endpoint。
- Supabase 会话持久化必须满足当前 generation 与原用户一致；Keychain 写成功后才替换内存状态。
- 403 表示权限/RLS 失败，不等于会话失效；REST 401 只允许 refresh 后重试一次。
- 功能 ViewModel 只负责本地意图，不拥有云 service；账号策略集中在 `CloudSyncViewModel` 与 service actor。
- 无法完整解码的远端记录不得降级成默认值、空集合或删除标记。
- 生产 IPA 发布只允许 `master/main` push，且旧 run 不得覆盖新 run 的 `latest.json`。

## 目标架构与迁移顺序

### 立即保持的边界

1. 所有远端 operation 捕获 `(project identity, user ID, session generation)`。
2. 所有本地数据读取都经 repository，不允许 ViewModel 直接 read-modify-write UserDefaults。
3. 本地 mutation 先持久化 outbox，再更新 UI；同步按用户串行 flush，之后才 pull。
4. store 的 save 必须 `throws`，禁止编码/磁盘失败后继续报告云同步成功。

### 数据作用域

```text
anonymous/<installation-id>/<collection>
cloud/<project-ref>/<user-id>/<collection>
```

登录只切换作用域，不自动把 A 或匿名 bucket 重标为 B。首次上传匿名数据必须由用户明确选择。Keychain account 同样包含 project/user/endpoint identity。

### 数据库优先的 convergence 协议

1. 为每个可删除 collection 增加 `updated_at`、`deleted_at` 与服务端单调 `revision`。
2. 数据库 trigger/RPC 拒绝低于当前 revision 的写入；相同版本一律 deletion-wins。
3. 客户端发布支持新字段但仍能读取旧 schema 的过渡版本。
4. 完成 backfill 与旧客户端观察窗口后，再禁止 hard DELETE。
5. 没有 device acknowledgement watermark 前，不自动回收 tombstone。

训练记录的 migration 已进入仓库，但线上数据库尚未由本轮执行：当前环境只有 publishable key，没有 DDL 管理权限。部署时必须先应用 `supabase/migrations/20260815000000_training_log_tombstones.sql`，再依赖跨设备删除收敛语义。

## 验证清单

- [x] 83 项原有测试进入 GitHub Actions 门禁并通过。
- [x] refresh sign-out、并发单飞、A/B 覆盖、断网、5xx、401 retry、403 保留会话均有确定性测试。
- [x] 青龙 endpoint 等价/变化、legacy fail-closed、恶意 URL 与诊断脱敏均有测试。
- [x] mismatch mutation 在 transport 前被拒绝。
- [x] 未知训练单位不会生成空 tombstone。
- [x] unsigned IPA 必须包含主 App 与 Share Extension，且不得含签名目录或 provisioning profile。
- [x] 当前 App 无 SPM/CocoaPods/Carthage 第三方包；Actions 依赖固定到 commit SHA，并配置月度 Dependabot 更新。
- [ ] 在线 Supabase migration、RLS 双账号集成测试与 1001 条分页测试：需要数据库管理/测试环境权限后执行。
- [ ] 其他 collection 的 tombstone/revision/outbox：必须按上述 schema-first 顺序实现。

## Timeline 摘要

| 时间（UTC） | 事件 |
|---|---|
| 2026-08-15 | 推送干净基线，开始白盒审计 |
| 2026-08-15 | 当前树解除追踪 IPA、Playwright 与用户态 Xcode 产物 |
| 2026-08-15 | CI 首次实际执行完整测试，逐项修复历史测试假设 |
| 2026-08-15 | 训练记录引入 whole-day LWW、tombstone 与兼容 migration |
| 2026-08-15 | 确认青龙 endpoint confused-deputy 与诊断泄密链 |
| 2026-08-15 | 确认 Supabase refresh actor 重入与账号替换竞态 |
| 2026-08-15 | 统一隐藏模块 mutation façade 与 expected-user 校验 |
| 2026-08-15 | SwiftUI 迁移现代 Tab API、44pt 点击区与 Reduce Motion |

## 复核命令

```bash
git diff --check
rg -n "HiddenSupabaseService\\.shared" EasySearch/Features
rg -n "endpointIdentity|sessionGeneration|expectedUserID" EasySearch
actionlint -color=false .github/workflows/build-unsigned-ipa.yml
gh run list --workflow build-unsigned-ipa.yml --limit 5
```

报告不包含真实 token、Supabase URL、publishable key、设备 UDID 或 provisioning 内容。

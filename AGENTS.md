# EasySearch iOS — Agent notes

## Delivery preferences (user permanent memory)

1. **After every code change: push to GitHub and produce an unsigned IPA.** Commit the change, push to `origin` (`master`/`main`), and ensure GitHub Actions `Build unsigned IPA` runs successfully. Do not leave the change only local.
2. **Do not proactively paste IPA direct-download links in chat every time** unless the user asks. Prefer in-app “检测更新” / artifact-based update flow when available.
3. When building or generating files **locally** (IPA, zip, screenshots, exports, etc.) and the user needs them, deliver a path they can open immediately.

## Product notes

- Module name for fitness: **训练记录** (feature id `training-log`).
- Training log v1: month calendar + day multi-line workout from categorized bodyweight library. **No** "复制昨天".

### GitHub download links (private repos)

If the user does ask for a download link for a private GitHub repo, do **not** only give `https://github.com/.../releases/download/...` (often 404 without login).
Resolve an authenticated artifact/release redirect and give the **signed direct URL** when possible (e.g. `blob.core.windows.net` for Actions artifacts, or `release-assets.githubusercontent.com` / `objects.githubusercontent.com` for Releases).
Mention that signed URLs expire (typically ~1 hour) and refresh if needed.
Also include the Actions run / Release page as a stable fallback.

## Secrets / 配置

仓库是**公开**的,任何凭证都不得写进代码或 `Info.plist`。

- `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` 在 `EasySearch/Info.plist` 里是 `$(VAR)` 占位:
  - **CI**:由 GitHub Secrets 经 `xcodebuild` 命令行参数注入,打包步骤会断言其已被替换。
  - **本地**:复制 `EasySearch/Config/Supabase.xcconfig.example` 为 `Supabase.xcconfig`(已 gitignore)。
  - 两者都缺失时 App 自动降级为"仅本地保存",不会崩溃。
- Supabase 所有表已启用 RLS(`auth.uid() = user_id`),且已关闭开放注册。

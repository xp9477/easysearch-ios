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

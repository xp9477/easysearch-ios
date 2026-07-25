# EasySearch iOS — Agent notes

## Delivery preferences (user permanent memory)

1. **After every code change: push to GitHub and produce an unsigned IPA.** Commit the change, push to `origin` (`master`/`main`), wait for GitHub Actions `Build unsigned IPA`, then deliver the **direct download link** (artifact URL and/or release asset URL). Do not stop at “build succeeded” or leave the IPA only on CI.
2. When GitHub Actions / CI produces artifacts or Releases, always give the user **direct download links** in chat (artifact URL and/or release asset URL). Do not stop at "build succeeded".
3. When building or generating files **locally** (IPA, zip, screenshots, exports, etc.), deliver the finished product **into this chat window** (or a path the user can open immediately).

## Product notes

- Module name for fitness: **训练记录** (feature id `training-log`).
- Training log v1: month calendar + day multi-line workout from categorized bodyweight library. **No** "复制昨天".

### GitHub download links (private repos)

For private GitHub repos, do **not** only give `https://github.com/.../releases/download/...` (often 404 without login).
Always resolve an authenticated release-asset redirect and give the **signed direct URL** on:
`https://release-assets.githubusercontent.com/...` (or `objects.githubusercontent.com`).
Mention that signed URLs expire (typically ~1 hour) and refresh if needed.
Also include the Release page as a stable fallback.

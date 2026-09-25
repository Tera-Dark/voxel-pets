# CI 工作流（待启用）

`github-actions-ci.yml` 是完整的 GitHub Actions 配置（格式检查 → lint → 108 项测试 → Rojo 构建 → 平衡快照）。

它暂时放在这里而不是 `.github/workflows/`，因为当前推送用的 fine-grained token 没有 **Workflows: Read and write** 权限，GitHub 会拒绝创建工作流文件。

启用方式（二选一）：
1. 给 token 增加 `Workflows` 权限后，执行 `git mv ci/github-actions-ci.yml .github/workflows/ci.yml` 并推送；
2. 或在 GitHub 网页端直接新建 `.github/workflows/ci.yml`，把本文件内容粘贴进去。

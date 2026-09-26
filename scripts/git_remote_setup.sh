#!/usr/bin/env bash
# 用法: GITHUB_REPO=<user>/<repo> ./scripts/git_remote_setup.sh
# 说明: 沙盒快照不保存 .git/config，因此远端与身份信息需要用此脚本重建。
set -e
cd "$(dirname "$0")/.."
git config user.name  "${GIT_USER_NAME:-VoxelPets Dev}"
git config user.email "${GIT_USER_EMAIL:-dev@voxelpets.local}"
if [ -n "$GITHUB_REPO" ]; then
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/${GITHUB_REPO}.git"
  echo "remote origin -> https://github.com/${GITHUB_REPO}.git"
fi
git status -sb

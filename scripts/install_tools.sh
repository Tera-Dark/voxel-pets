#!/usr/bin/env bash
# 安装本项目使用的 Roblox 工具链（Linux x86_64），本地与 CI 共用。
# 用法: ./scripts/install_tools.sh [安装目录，默认 ~/bin]
set -euo pipefail
BIN="${1:-$HOME/bin}"; mkdir -p "$BIN"; cd "$(mktemp -d)"
LUNE=0.10.5; STYLUA=2.5.2; SELENE=0.31.0; ROJO=7.7.0; WALLY=0.3.2
dl() { curl -sSL -o "$2" "$1"; }
dl "https://github.com/lune-org/lune/releases/download/v${LUNE}/lune-${LUNE}-linux-x86_64.zip" lune.zip
dl "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA}/stylua-linux-x86_64.zip" stylua.zip
dl "https://github.com/Kampfkarren/selene/releases/download/${SELENE}/selene-${SELENE}-linux.zip" selene.zip
dl "https://github.com/rojo-rbx/rojo/releases/download/v${ROJO}/rojo-${ROJO}-linux-x86_64.zip" rojo.zip
dl "https://github.com/UpliftGames/wally/releases/download/v${WALLY}/wally-v${WALLY}-linux.zip" wally.zip
for z in lune stylua selene rojo wally; do
  python3 -c "import zipfile,sys; zipfile.ZipFile('$z.zip').extractall('$z')"
  f=$(find "$z" -type f -name "$z*" | head -1); install -m 755 "$f" "$BIN/$z"
done
echo "installed to $BIN:"; for t in lune stylua selene rojo wally; do printf "  %-7s %s\n" "$t" "$("$BIN/$t" --version 2>&1 | head -1)"; done

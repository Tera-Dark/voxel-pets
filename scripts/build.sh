#!/usr/bin/env bash
# Builds the place with a visible build stamp (git short hash + UTC date) so testers can tell
# builds apart in screenshots. Usage: scripts/build.sh [output.rbxl]   (default: VoxelPets.rbxl)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-VoxelPets.rbxl}"
INFO=src/shared/BuildInfo.luau
HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
if [ -n "$(git status --porcelain -- src 2>/dev/null)" ]; then
	HASH="$HASH+dirty"
fi
STAMP="$HASH $(date -u +%Y-%m-%d)"
cp "$INFO" "$INFO.bak"
trap 'mv "$INFO.bak" "$INFO"' EXIT
sed -i.tmp "s/BUILD = \"[^\"]*\"/BUILD = \"$STAMP\"/" "$INFO"
rm -f "$INFO.tmp"
rojo build default.project.json -o "$OUT"
echo "built $OUT ($STAMP)"

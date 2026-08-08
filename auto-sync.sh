#!/usr/bin/env bash
# Auto-sync: workspace/memory/ → viewer/memory/ → GitHub Pages
# Also copy state.json for daily-schedule display
# Plus: 宫磊手账数据 (life/) — food / shopping / games / technical
set -euo pipefail

SRC="/home/gong/.openclaw/workspace/memory"
DST="/home/gong/.openclaw/workspace-xiaozhushou/skills/isekai-companion/viewer/memory"
STATE="/home/gong/.openclaw/workspace/skills/isekai-companion/state.json"
DIR="/home/gong/.openclaw/workspace-xiaozhushou/skills/isekai-companion/viewer"

# 手账数据源（workspace-xiaozhushou）
LIFE_SRC="/home/gong/.openclaw/workspace-xiaozhushou"
LIFE_DST="$DIR/life"

cd "$DIR"

needed=false

# 1. Sync workspace/memory/*.md → viewer/memory/
for f in "$SRC"/*.md; do
  base=$(basename "$f")
  dst="$DST/$base"
  if [ ! -f "$dst" ] || [ "$f" -nt "$dst" ]; then
    cp "$f" "$dst"
    needed=true
  fi
done

# 2. Copy state.json to viewer root (with JSON validation)
if [ -f "$STATE" ]; then
  if [ ! -f "state.json" ] || [ "$STATE" -nt "state.json" ]; then
    if python3 -c "import json; json.load(open('$STATE'))" 2>/dev/null; then
      cp "$STATE" "state.json"
      needed=true
    else
      echo "WARNING: state.json is invalid JSON, skipping copy" >&2
    fi
  fi
fi

# 3. Sync 宫磊手账数据 → viewer/life/
mkdir -p "$LIFE_DST"
life_sync() {
  local src="$1" dst="$2"
  if [ -f "$src" ] && { [ ! -f "$dst" ] || [ "$src" -nt "$dst" ]; }; then
    cp "$src" "$dst"
    needed=true
  fi
}
life_sync "$LIFE_SRC/memory/food.md"                  "$LIFE_DST/food.md"
life_sync "$LIFE_SRC/memory/shopping/wishlist.md"     "$LIFE_DST/wishlist-shopping.md"
life_sync "$LIFE_SRC/memory/games/wishlist.md"        "$LIFE_DST/wishlist-games.md"
life_sync "$LIFE_SRC/self-evolution/patterns/technical.md" "$LIFE_DST/technical.md"

# Commit & push only if something changed
if [ "$needed" = true ]; then
  git add -A
  git commit -m "auto-sync: memory updates $(date '+%Y-%m-%d %H:%M')"
  git pull --rebase origin master 2>&1 || true
  git push origin master 2>&1
fi

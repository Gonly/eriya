#!/usr/bin/env bash
# Auto-sync: workspace/memory/ → viewer/memory/ → GitHub Pages
# Also copy state.json for daily-schedule display
set -euo pipefail

SRC="/home/gong/.openclaw/workspace/memory"
DST="/home/gong/.openclaw/workspace-xiaozhushou/skills/isekai-companion/viewer/memory"
STATE="/home/gong/.openclaw/workspace/skills/isekai-companion/state.json"
DIR="/home/gong/.openclaw/workspace-xiaozhushou/skills/isekai-companion/viewer"

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

# Commit & push only if something changed
if [ "$needed" = true ]; then
  git add memory/ state.json
  git commit -m "auto-sync: memory updates $(date '+%Y-%m-%d %H:%M')"
  git pull --rebase origin master 2>&1 || true
  git push origin master 2>&1
fi
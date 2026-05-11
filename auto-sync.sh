#!/usr/bin/env bash
# Auto-sync: workspace/memory/ → viewer/memory/ → GitHub Pages
set -euo pipefail

SRC="/home/gong/.openclaw/workspace/memory"
DST="/home/gong/.openclaw/workspace-xiaozhushou/skills/isekai-companion/viewer/memory"
DIR="/home/gong/.openclaw/workspace-xiaozhushou/skills/isekai-companion/viewer"
cd "$DIR"

# Diff workspace/memory/ against viewer/memory/
# Sync only if the source file is newer (modified timestamp or content differs)
needed=false
for f in "$SRC"/*.md; do
  base=$(basename "$f")
  dst="$DST/$base"
  if [ ! -f "$dst" ] || [ "$f" -nt "$dst" ]; then
    cp "$f" "$dst"
    needed=true
  fi
done

if [ "$needed" = true ]; then
  git add memory/
  git commit -m "auto-sync: memory updates $(date '+%Y-%m-%d %H:%M')"
  git pull --rebase origin master 2>&1
  git push origin master 2>&1
fi

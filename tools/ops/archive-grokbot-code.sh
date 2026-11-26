#!/usr/bin/env bash
# 把 incoming/grokbot 里 3 个代码副本归档到 /DATA/GameArchive，保留美术/文档/管线
# 用法: bash scripts/archive-grokbot-code.sh [--dry-run]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
DEST=/DATA/GameArchive/grokbot-$(date +%Y%m%d)
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

MOVE=(incoming/grokbot/godogen-shanhe-fe incoming/grokbot/godogen-shanhe-be incoming/grokbot/godogen-shanhe incoming/grokbot/grokbot-workspace)
KEEP=(incoming/grokbot/wuxia-team incoming/grokbot/shenyan-img3d incoming/grokbot/wuxia-delivery incoming/grokbot/shanhe-delivery incoming/grokbot/chars incoming/grokbot/perf incoming/grokbot/scratch incoming/grokbot/rv1117 incoming/grokbot/wuxia-character-references incoming/grokbot/IMPORT_MANIFEST.md incoming/grokbot/EXCLUDED_PATHS.txt)

echo "目标: $DEST"
for p in "${MOVE[@]}"; do
  [ -e "$p" ] || { echo "  跳过（不存在）$p"; continue; }
  sz=$(du -sh "$p" | cut -f1)
  if [ "$DRY" = 1 ]; then echo "  将移动 $p ($sz)"; else
    mkdir -p "$DEST/$(dirname "${p#incoming/grokbot/}")"
    mv "$p" "$DEST/" && echo "  已移动 $p ($sz)"
  fi
done

if [ "$DRY" = 0 ]; then
  git add -A
  git -c user.name=Lead -c user.email=lead@local commit -qm "chore(archive): 3 个 Grok Bot 代码副本移出工作区到 /DATA/GameArchive" || echo "无改动可提交"
  git push -q origin master || echo "推送失败"
  echo "--- 归档后 incoming 保留 ---"
  ls incoming/grokbot | head -15
  du -sh incoming/grokbot
fi

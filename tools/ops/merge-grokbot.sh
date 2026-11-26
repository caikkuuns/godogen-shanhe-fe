#!/usr/bin/env bash
# 合并 Grok Bot 推上来的工作：拉取 grokbot/main → 预览 → 合并 → 跑测试
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export PATH="$HOME/.local/bin:$PATH"
BRANCH="${1:-grokbot/main}"

echo "=== 1) 拉取 $BRANCH ==="
git fetch -q origin "$BRANCH" || { echo "!! 拉取失败（远端还没有这个分支？）"; exit 1; }
echo "远端分支: $(git rev-parse --short FETCH_HEAD)"
echo "本分支:   $(git rev-parse --short HEAD)"

echo "=== 2) 差异预览 ==="
git --no-pager diff --stat HEAD...FETCH_HEAD | tail -30
echo
git --no-pager log --oneline HEAD..FETCH_HEAD | head -10

echo "=== 3) 合并 ==="
if git merge --no-ff --no-edit FETCH_HEAD -m "merge: Grok Bot 工作 ($(git rev-parse --short FETCH_HEAD))" 2>&1 | tail -6; then
  echo "合并成功"
else
  echo "!! 有冲突，解决后再提交："
  git --no-pager diff --name-only --diff-filter=U | head -20
  echo "解决后执行： git add -A && git commit && bash tests/run_all.sh"
  exit 2
fi

echo "=== 4) 测试 ==="
TEST=$(GODOT=godot bash tests/run_all.sh 2>&1 | grep -E 'PASSED [0-9]+ /|UI PASSED|WORLD PASSED|BREATH_TEST ok|FOOT_LOCK_TEST ok|FAILED \(' | tr '\n' ' ; ')
echo "$TEST"
echo "=== 5) 推送 ==="
git push -q origin master 2>&1 | tail -1 || echo "!! 推送失败"
echo "完成：$(git rev-parse --short HEAD)"

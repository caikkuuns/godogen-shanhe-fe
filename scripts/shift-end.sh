#!/usr/bin/env bash
# 交班：跑测试 → 提交 → 写交班条目 → 释放班次 → 推送
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
NAME="${1:?用法: shift-end.sh <你的名字>}"
WHAT="${2:?用法: shift-end.sh <你的名字> \"做了什么\" \"未完成/坑\" \"下一位先做什么\"}"
TODO="${3:-无}"
NEXT="${4:-按交班条目继续}"
export PATH="$HOME/.local/bin:$PATH"

echo "=== 1) 测试 ==="
TEST_SUMMARY=$(GODOT=godot timeout 900 bash tests/run_all.sh 2>&1 \
  | grep -E 'PASSED [0-9]+ /|UI PASSED|WORLD PASSED|BREATH_TEST ok|FOOT_LOCK_TEST ok|FAILED \(' | tr '\n' ' ; ')
echo "$TEST_SUMMARY"

echo "=== 2) 提交 ==="
git add -A
git -c user.name="$NAME" -c user.email="shift@local" commit -qm "shift($NAME): $WHAT" 2>&1 | tail -2 || echo "无改动"

echo "=== 3) 写交班条目 ==="
python3 - "$NAME" "$WHAT" "$TODO" "$NEXT" "$TEST_SUMMARY" <<'PY'
import sys, datetime
name, what, todo, nxt, tests = sys.argv[1:6]
p = '.shift/handover.md'
s = open(p).read()
entry = f"""## {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')} · {name}
- 做了什么：{what}
- 测试：{tests}
- 未完成 / 坑：{todo}
- 下一位先做什么：{nxt}

"""
s = s.replace('<!-- entries -->\n', '<!-- entries -->\n\n' + entry, 1)
open(p, 'w').write(s)
import json
json.dump({"owner": None, "since": None, "note": f"{name} 已于 {datetime.datetime.now().strftime('%H:%M')} 交班"},
          open('.shift/state.json', 'w'), ensure_ascii=False, indent=2)
print("交班条目已写入")
PY

git add -A
git -c user.name="$NAME" -c user.email="shift@local" commit -qm "shift($NAME): 交班日志" 2>&1 | tail -1 || true
echo "=== 4) 推送 ==="
git push -q origin master 2>&1 | tail -2 || echo "!! 推送失败（检查 origin）"
echo "=== 交班完成，当前 HEAD: $(git rev-parse --short HEAD) ==="

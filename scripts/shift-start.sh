#!/usr/bin/env bash
# 接班：检查是否有人占班 → 拉取 → 打印上一位交班
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
NAME="${1:?用法: shift-start.sh <你的名字>}"

# 时间窗校验（.shift/policy.json）
python3 - "$NAME" <<'PYCHK'
import json, sys, datetime
name = sys.argv[1].strip().lower()
pol = json.load(open('.shift/policy.json'))
shifts = {k.lower(): v for k, v in pol['shifts'].items()}
key = 'grokbot' if 'grok' in name or 'bot' in name else ('dsh' if name in ('dsh','lead','claude','glm','kimi','deepseek') else name)
w = shifts.get(key)
if not w:
    print(f"!! 未知班次名 {name}，请在 .shift/policy.json 里登记")
    raise SystemExit(1)
now = datetime.datetime.now().strftime('%H:%M')
if not (w['start'] <= now <= w['end']):
    print(f"!! 现在 {now} 不在 {key} 的时间窗（{w['start']}-{w['end']}）内，不能接班")
    print("   用 scripts/shift-status.sh 看当前该谁上班")
    raise SystemExit(1)
print(f"时间窗 OK：{key} {w['start']}-{w['end']}（现在 {now}）")
PYCHK
[ $? -ne 0 ] && exit 1
python3 - "$NAME" <<'PY'
import json, sys, datetime, os
name = sys.argv[1]
p = '.shift/state.json'
st = json.load(open(p)) if os.path.exists(p) else {}
if st.get('owner') and st['owner'] != name:
    print(f"!! 班次被 {st['owner']} 占用（自 {st['since']}）：{st.get('note','')}")
    print("   等对方 shift-end 或与对方确认后再接手。")
    raise SystemExit(1)
st = {"owner": name, "since": datetime.datetime.now().strftime('%Y-%m-%d %H:%M'), "note": "进行中"}
json.dump(st, open(p, 'w'), ensure_ascii=False, indent=2)
print(f"班次已归 {name}（{st['since']}）")
PY
[ $? -ne 0 ] && exit 1
git pull -q --rebase origin master 2>&1 | tail -2 || true
echo "=== 上一位交班（最新条目）==="
sed -n '/<!-- entries -->/,/^## /p' .shift/handover.md | sed -n '3,18p'

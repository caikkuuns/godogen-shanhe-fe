#!/usr/bin/env bash
# 打印当前时间窗、允许的班次、当前 owner
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
python3 - <<'PY'
import json, os, datetime
pol = json.load(open('.shift/policy.json'))
st = json.load(open('.shift/state.json')) if os.path.exists('.shift/state.json') else {}
now = datetime.datetime.now().strftime('%H:%M')
def inwin(t, a, b):
    return a <= t <= b
print(f"现在 {now}（{pol.get('timezone','')}）")
for name, w in pol['shifts'].items():
    mark = '✅ 你的班次' if inwin(now, w['start'], w['end']) else '—'
    print(f"  {name:8s} {w['start']}-{w['end']}  {mark}")
print(f"当前 owner: {st.get('owner') or '空班'}" + (f"（自 {st.get('since')}）" if st.get('since') else ""))
PY

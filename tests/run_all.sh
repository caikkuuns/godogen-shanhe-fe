#!/usr/bin/env bash
# Full frontend test pass: acceptance 145, UI 3, plus IdleBreath stability.
#
# 第10轮修复（报告「测试门禁失守」）：
#   1. 之前只看 godot 的退出码，stderr 里的 "ERROR:" / "SCRIPT ERROR:" 一律不管，
#      集成日志里 103 行报错仍然算通过。现在逐条断言。
#   2. .tscn 场景测试加了 --quit-after 超时兜底，异常不退出时不会挂死 CI。
#
# 环境变量：
#   GODOT=...            指定引擎二进制（默认 godot）
#   ALLOW_ERRORS=1       临时放行（本地排查用，CI 不要设）
#   ERROR_ALLOWLIST=...  按字面量白名单放行的行（默认空）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-godot}"
LOG_DIR="${LOG_DIR:-build/testlogs}"
mkdir -p "$LOG_DIR"

FAILED=0
declare -a SUMMARY=()

run_step() {
	local name="$1"; shift
	local log="$LOG_DIR/$name.log"
	echo "── $name"
	if "$@" >"$log" 2>&1; then
		local code=0
	else
		local code=$?
	fi

	# 错误行断言：ERROR: / SCRIPT ERROR: / Parse Error / USER ERROR
	local errs
	errs=$(grep -nE '(SCRIPT ERROR|^ERROR:|USER ERROR|Parse Error)' "$log" || true)
	if [[ -n "$errs" && "${ALLOW_ERRORS:-0}" != "1" ]]; then
		if [[ -n "${ERROR_ALLOWLIST:-}" ]]; then
			errs=$(echo "$errs" | grep -vF -f <(printf '%s\n' "$ERROR_ALLOWLIST") || true)
		fi
	fi

	if [[ "$code" -ne 0 ]]; then
		echo "   ✗ 退出码 $code（日志：$log）"
		tail -20 "$log" | sed 's/^/     /'
		FAILED=1
		SUMMARY+=("✗ $name 退出码 $code")
		return
	fi
	if [[ -n "$errs" ]]; then
		echo "   ✗ 日志里有报错（退出码却是 0）："
		echo "$errs" | head -10 | sed 's/^/     /'
		FAILED=1
		SUMMARY+=("✗ $name 有 $(echo "$errs" | wc -l) 行报错")
		return
	fi
	echo "   ✓"
	SUMMARY+=("✓ $name")
}

run_step acceptance "$GODOT" --headless --path . -s tests/run_tests.gd
run_step ui "$GODOT" --headless --path . res://tests/ui_tests.tscn --quit-after 1800
run_step idle_breath "$GODOT" --headless --path . --fixed-fps 60 -s tests/test_idle_breath.gd
run_step foot_lock "$GODOT" --headless --path . --fixed-fps 60 -s tests/test_foot_lock.gd
run_step movement "$GODOT" --headless --path . --fixed-fps 60 -s tests/test_movement.gd
run_step open_world "$GODOT" --headless --path . res://tests/test_open_world.tscn --quit-after 1800

echo
echo "================ 汇总 ================"
printf '%s\n' "${SUMMARY[@]}"
echo "日志目录：$LOG_DIR"
if [[ "$FAILED" -ne 0 ]]; then
	echo "结果：未通过"
	exit 1
fi
echo "结果：全部通过"

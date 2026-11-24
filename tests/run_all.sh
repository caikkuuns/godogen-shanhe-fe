#!/usr/bin/env bash
# Full frontend test pass: acceptance 145, UI 3, plus IdleBreath stability.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . -s tests/run_tests.gd
"$GODOT" --headless --path . res://tests/ui_tests.tscn
"$GODOT" --headless --path . --fixed-fps 60 -s tests/test_idle_breath.gd
"$GODOT" --headless --path . --fixed-fps 60 -s tests/test_foot_lock.gd
"$GODOT" --headless --path . --fixed-fps 60 -s tests/test_movement.gd
"$GODOT" --headless --path . res://tests/test_open_world.tscn

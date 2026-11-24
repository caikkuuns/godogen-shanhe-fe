#!/usr/bin/env bash
# Render the three vertical-slice acceptance screenshots under Xvfb.
# The Godot side lives in scenes/main.gd (--capture=explore|dialogue|hud);
# it waits for the camera and dialogue typewriter to settle, saves a viewport
# PNG, then quits.
#
# 服务器上的 lavapipe（软件 Vulkan）在 2D/Canvas 绘制时会触发 LLVM
# "Cannot select ... load s16" 崩溃（纯 3D 场景正常）。脚本先按要求尝试
# VK_ICD_FILENAMES 指向的软件 Vulkan；若进程崩溃/没有产出，再自动回退到
# OpenGL Compatibility 软件渲染，保证验收图仍来自同一份游戏代码。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/captures"
SCREEN="${XVFB_SCREEN:-2560x1600x24}"
RESOLUTION="${CAPTURE_RESOLUTION:-1920x1080}"
mkdir -p "$OUT"

PNG_MAGIC="89504e470d0a1a0a"
GODOT="${GODOT:-godot}"

# 文档里的 lvp_icd.x86_64.json 在部分机器上不存在，回退到实际的 lvp_icd.json。
if [ -z "${VK_ICD_FILENAMES:-}" ] || [ ! -f "${VK_ICD_FILENAMES}" ]; then
	for candidate in \
		/usr/share/vulkan/icd.d/lvp_icd.x86_64.json \
		/usr/share/vulkan/icd.d/lvp_icd.json; do
		if [ -f "$candidate" ]; then
			export VK_ICD_FILENAMES="$candidate"
			break
		fi
	done
fi

validate_png() {
	local mode="$1"
	local image="$OUT/$mode.png"
	if [ ! -s "$image" ]; then
		return 1
	fi
	local magic
	magic="$(head -c 8 "$image" | od -An -tx1 | tr -d ' \n')"
	if [ "$magic" != "$PNG_MAGIC" ]; then
		return 1
	fi
	local bytes
	bytes="$(stat -c%s "$image")"
	if [ "$bytes" -lt 10000 ]; then
		return 1
	fi
	echo "CAPTURE OK $mode ${RESOLUTION} ${bytes} bytes"
	return 0
}

run_mode() {
	local mode="$1"
	shift
	local log
	log="$(mktemp)"
	local image="$OUT/$mode.png"
	rm -f "$image"
	if ! xvfb-run -a -s "-screen 0 $SCREEN" \
		"$GODOT" --path "$ROOT" --resolution "$RESOLUTION" "$@" -- "--capture=$mode" >"$log" 2>&1; then
		rm -f "$log"
		return 1
	fi
	if ! grep -q "CAPTURE_SAVED res://captures/$mode.png" "$log"; then
		rm -f "$log"
		return 1
	fi
	rm -f "$log"
	validate_png "$mode"
}

# CAPTURE_FORCE_OPENGL=1 跳过必然崩溃的 lavapipe Vulkan 尝试，直接走 OpenGL
# 软件渲染；只影响本脚本，不改 project.godot 的渲染器设置。
for mode in ${CAPTURE_MODES:-explore dialogue hud}; do
	if [ "${CAPTURE_FORCE_OPENGL:-0}" = "1" ]; then
		if ! run_mode "$mode" --rendering-method gl_compatibility --rendering-driver opengl3; then
			echo "FAILED $mode (forced OpenGL Compatibility)"
			exit 1
		fi
		echo "CAPTURE_RENDERER opengl-forced $mode"
		continue
	fi
	if run_mode "$mode"; then
		continue
	fi
	echo "CAPTURE_RETRY $mode (software Vulkan unavailable/crashed; retrying OpenGL Compatibility)"
	if ! run_mode "$mode" --rendering-method gl_compatibility --rendering-driver opengl3; then
		echo "FAILED $mode (both Vulkan and OpenGL fallback failed)"
		exit 1
	fi
	echo "CAPTURE_RENDERER opengl-compat-fallback $mode (lavapipe 2D crash workaround)"
done

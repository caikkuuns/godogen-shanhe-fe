extends Node
## FE UI acceptance cases that need the autoload globals (GameState, DialogueDB),
## which `godot -s` scripts cannot compile against. Run as a scene:
##   godot --headless --path . res://tests/ui_tests.tscn
## Prints PASSED n / n and exits 0 on success, 1 on failure.

const SAVE_PATH := "user://ui_tests_save.json"
var _failed: Array[String] = []
var _passed := 0
var _case := ""
var _case_ok := true

func _ready() -> void:
	await _fe_ui_001()
	await _fe_ui_002()
	await _fe_ui_003()
	await _fe_ui_004()
	print("\nUI PASSED %d / %d cases" % [_passed, _passed + _failed.size()])
	if not _failed.is_empty():
		print("UI FAILED: ", ", ".join(PackedStringArray(_failed)))
	get_tree().quit(0 if _failed.is_empty() else 1)

func _begin(id: String, title: String) -> void:
	_case = id
	_case_ok = true
	print("-- %s %s" % [id, title])

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_case_ok = false
		print("   FAIL ", msg)

func _end() -> void:
	if _case_ok:
		_passed += 1
		print("   ok")
	else:
		_failed.append(_case)

func _fe_ui_001() -> void:
	_begin("FE-UI-001", "reward toast only after the post-dialogue save succeeds")
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	var sm := get_node("/root/SaveManager")
	# Never write the player's real save (SaveManager.SAVE_PATH): use a scratch file.
	hud.save_path_override = SAVE_PATH
	sm.delete_save(SAVE_PATH)
	var real_before := FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH) if FileAccess.file_exists(SaveManager.SAVE_PATH) else PackedByteArray()
	GameState.reward_granted.emit("一碗粗茶")
	_expect(hud.toast.text.find("一碗粗茶") == -1, "toast before save: %s" % hud.toast.text)
	sm.test_fail_stage = "rename"
	var bad: Dictionary = hud.settle_after_dialogue(false)
	sm.test_fail_stage = ""
	_expect(not bad.get("ok", true), "failed save reported ok: %s" % bad)
	_expect(hud.toast.text.find("一碗粗茶") == -1, "reward shown after failed save: %s" % hud.toast.text)
	_expect(hud.toast.text.find("存档失败") != -1, "failure hint missing: %s" % hud.toast.text)
	_expect(hud.pending_reward_texts().is_empty(), "cache kept after failure")
	GameState.reward_granted.emit("一碗粗茶")
	var ok: Dictionary = hud.settle_after_dialogue(false)
	_expect(ok.get("ok", false), "save failed: %s" % ok)
	_expect(hud.toast.text == "奖励 · 一碗粗茶", "toast=%s" % hud.toast.text)
	_expect(FileAccess.file_exists(SAVE_PATH), "scratch save not written")
	var real_after := FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH) if FileAccess.file_exists(SaveManager.SAVE_PATH) else PackedByteArray()
	_expect(real_after == real_before, "real save file was modified")
	sm.delete_save(SAVE_PATH)
	hud.queue_free()
	await get_tree().process_frame
	_end()

func _fe_ui_002() -> void:
	_begin("FE-UI-002", "narrator fade_black covers the full viewport, text stays in the safe area")
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	var node: Dictionary = DialogueDB.get_node_data("ch2_zc_07")
	hud.dialogue_panel.show_line(node, DialogueDB.speaker_display_name(node), str(node.get("text", "")),
		DialogueDB.portrait_path(node), DialogueDB.speaker_side(node))
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect()
	var black: Rect2 = hud.dialogue_panel.black_rect()
	_expect(black.position.is_equal_approx(Vector2.ZERO), "black origin %s" % black.position)
	_expect(black.size.x >= vp.size.x - 0.5 and black.size.y >= vp.size.y - 0.5,
		"black %s smaller than viewport %s" % [black.size, vp.size])
	var narration := hud.dialogue_panel.find_child("Narration", true, false) as Control
	var safe: Rect2 = hud.safe_area.get_global_rect()
	_expect(narration != null and safe.encloses(narration.get_global_rect()),
		"narration %s outside safe area %s" % [narration.get_global_rect() if narration else Rect2(), safe])
	hud.queue_free()
	await get_tree().process_frame
	_end()

func _fe_ui_003() -> void:
	_begin("FE-UI-003", "closing the battle panel releases the 3D fighter models")
	var panel := BattlePanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.start("ch2_thug")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(panel._stage != null and panel._stage.has_fighters(), "fighters missing after start")
	panel.close_and_release(false)
	# queue_free runs at the end of the frame.
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(panel._stage != null and not panel._stage.has_fighters(), "fighters still in the stage after close")
	_expect(panel.visible == false, "panel still visible after close")
	panel.queue_free()
	await get_tree().process_frame
	_end()

func _fe_ui_004() -> void:
	_begin("FE-UI-004", "真打一场后战报各行与收剑按钮都留在金框内")
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var layer := CanvasLayer.new()
	add_child(layer)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.size = Vector2(1920, 1080)
	layer.add_child(host)
	var panel := BattlePanel.new()
	host.add_child(panel)
	await get_tree().process_frame
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.start("ch2_thug")
	await get_tree().process_frame
	# 与侧战截图同一套行动序列，但跳过 3D 演出节拍，只查排版。
	var plan: Array[String] = ["skill", "skill", "attack", "guard", "attack"]
	for action: String in plan:
		if panel.logic == null or panel.logic.call("is_over"):
			break
		var res: Dictionary = panel.logic.call("take_turn", action)
		_expect(res.get("ok", false), "take_turn %s failed: %s" % [action, res])
		panel._refresh()
	_expect(bool(panel.logic.get("won")), "fight did not end in a win")
	panel._show_result_buttons([["收剑", panel._close.bind(true)]])
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var text := panel._log_label.text
	print("   log: ", text.replace("\n", " | "))
	_expect(text.find("造成") != -1 and text.find("点伤害") != -1, "damage line missing: %s" % text)
	_expect(text.find("沈砚普攻") != -1, "finishing attack missing: %s" % text)
	_expect(text.find("倒下了") != -1, "downed line missing: %s" % text)
	var hud := panel._hud_panel
	_expect(hud != null, "hud panel missing")
	if hud != null:
		var hr := hud.get_global_rect()
		# 金框 3px，留 1px 余量避免字压线。
		var inner := hr.grow(-4.0)
		var lr := panel._log_label.get_global_rect()
		_expect(inner.encloses(lr), "log %s not inside panel %s (overflow_y=%.1f)" % [lr, hr, lr.end.y - hr.end.y])
		var font: Font = panel._log_label.get_theme_font("font")
		var fsize := panel._log_label.get_theme_font_size("font_size")
		var line_h := float(fsize)
		if font != null:
			line_h = float(font.get_height(fsize))
		var nlines := panel._log_label.text.split("\n").size()
		_expect(lr.size.y + 0.5 >= line_h * float(nlines),
			"log height %.1f too short for %d lines at %.1f px" % [lr.size.y, nlines, line_h])
		var sheath: Button = null
		for c: Node in panel._result_row.get_children():
			if c is Button and (c as Button).text == "收剑":
				sheath = c as Button
				break
		_expect(sheath != null and sheath.visible, "收剑 button missing or hidden")
		if sheath != null:
			var br := sheath.get_global_rect()
			_expect(inner.encloses(br), "收剑 %s not inside panel %s (overflow_y=%.1f)" % [br, hr, br.end.y - hr.end.y])
			# 对 1920×1080 战斗宿主判断，而不是可能在其他 canvas 缩放下的窗口矩形。
			_expect(host.get_global_rect().encloses(br), "收剑 %s outside the battle host %s" % [br, host.get_global_rect()])
			_expect(panel._action_row.visible == false, "action row still visible after victory")
		print("   hud=", hr, " log=", lr, " overflow_y=", lr.end.y - hr.end.y)
	panel.queue_free()
	layer.queue_free()
	await get_tree().process_frame
	_end()

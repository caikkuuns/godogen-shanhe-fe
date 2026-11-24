class_name BattlePanel
extends Control
## Minimal turn-based battle overlay driven by BattleLogic (be step7/9 API).
## The scene owns enter/leave: it listens to battle_closed and calls
## GameState.leave_battle(). This panel never saves.

signal battle_closed(battle_id: String, victory: bool)
## Live player stats each refresh so the HUD status bar matches the panel.
signal stats_changed(hp: int, qi: int, potions: int)

const BattleLogicScript := preload("res://scripts/battle/battle_logic.gd")
const ACTION_LABELS := {"attack": "攻击", "skill": "剑招", "guard": "守势", "potion": "服药"}

var logic: RefCounted
var battle_id := ""
var _title: Label
var _enemy_label: Label
var _player_label: Label
var _intent_label: Label
var _log_label: Label
var _action_row: HBoxContainer
var _result_row: HBoxContainer
var _buttons: Dictionary = {}
var _stage: BattleStage
var _stage_host: SubViewport
var _hud_panel: Panel
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.build_theme()
	visible = false
	_build()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.42)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var stage_box := SubViewportContainer.new()
	stage_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_box.anchor_bottom = 0.62
	stage_box.offset_bottom = 0.0
	stage_box.stretch = true
	stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage_box)
	_stage_host = SubViewport.new()
	_stage_host.size = Vector2i(1920, 670)
	_stage_host.transparent_bg = false
	# 探索时不需要渲染第二个 3D 视口；start() 才打开。
	_stage_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_stage_host.world_3d = World3D.new()
	stage_box.add_child(_stage_host)
	_stage = BattleStage.new()
	_stage.name = "BattleStage"
	_stage_host.add_child(_stage)
	var panel := Panel.new()
	panel.name = "BattleHudPanel"
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(0.86))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -640.0
	panel.offset_right = 640.0
	panel.offset_top = -430.0
	panel.offset_bottom = -24.0
	add_child(panel)
	_hud_panel = panel
	# 第八轮（自 grokbot fe 吸收）：MarginContainer 收边，字号整体收一档
	# （48/36/34/36/30 → 32/24/24/24/22），腾出的高度留给战报 4 行，
	# 修战报末行与「收剑」按钮被金框裁切。渲染策略 UPDATE_DISABLED 保持我们的。
	var margin := MarginContainer.new()
	margin.name = "BattleHudMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	# 入树后再设一次锚点，保证底部 12px 边距生效。
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.name = "BattleHudBox"
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	_title = _label(box, 32, Color("#f4e6c8"))
	_enemy_label = _label(box, 24, Color("#e9b9a6"))
	_intent_label = _label(box, 24, Color("#f0cf7a"))
	_player_label = _label(box, 24, Color("#cfe0f2"))
	_log_label = _label(box, 22, Color("#e6dccb"))
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_constant_override("line_spacing", -2)
	# 四行完整可见；高度由 _fit_log_min_height() 按真实字体行高拟合。
	_log_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_log_label.clip_text = true
	_action_row = HBoxContainer.new()
	_action_row.size_flags_vertical = Control.SIZE_SHRINK_END
	_action_row.add_theme_constant_override("separation", 24)
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_action_row)
	for action: String in ["attack", "skill", "guard", "potion"]:
		var b := _button(_action_row, ACTION_LABELS[action])
		b.pressed.connect(_on_action.bind(action))
		_buttons[action] = b
	_result_row = HBoxContainer.new()
	_result_row.size_flags_vertical = Control.SIZE_SHRINK_END
	_result_row.add_theme_constant_override("separation", 32)
	_result_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# 空结果行也占 separation 空隙，先隐藏。
	_result_row.visible = false
	box.add_child(_result_row)
	_fit_log_min_height()

## 第八轮（自 grokbot fe 吸收）：按真实字体高度给战报 4 行最小高度，
## 修战报末行与「收剑」按钮被金框裁切（原先写死 110px ≈ 2.7 行）。
func _fit_log_min_height() -> void:
	if _log_label == null:
		return
	var font: Font = _log_label.get_theme_font("font")
	var fsize := _log_label.get_theme_font_size("font_size")
	var line := 22.0
	if font != null:
		line = float(font.get_height(fsize))
	_log_label.custom_minimum_size = Vector2(0.0, line * 4.0 + 2.0)

func _label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200.0, 68.0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 38)
	b.add_theme_stylebox_override("normal", UiTheme.button_style(0.8, 0.8))
	parent.add_child(b)
	return b

func is_active() -> bool:
	return visible

func start(id: String) -> void:
	battle_id = id
	logic = BattleLogicScript.new(GameState.hp, GameState.potions)
	logic.call("set_battle_id", id)
	visible = true
	_busy = false
	if _stage_host != null:
		_stage_host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _stage != null:
		_stage.setup(id)
	_show_result_buttons([])
	_refresh()

func _on_action(action: String) -> void:
	await resolve_action(action)

func resolve_action(action: String) -> void:
	if _busy or logic == null or logic.call("is_over"):
		return
	var res: Dictionary = logic.call("take_turn", action)
	if not res.get("ok", false):
		_log_label.text = str(res.get("reason", ""))
		return
	_busy = true
	_set_actions_enabled(false)
	# Paint the new HP before the 3D beats so a killing blow already
	# shows 0 when the fall starts, not after it ends.
	_refresh()
	if _stage != null:
		await _stage.play_turn(res)
	_refresh()
	if logic.get("won"):
		_show_result_buttons([["收剑", _close.bind(true)]])
	elif logic.get("lost"):
		_show_result_buttons([["再战", _retry], ["撤退", _retreat]])
	_busy = false
	if not logic.call("is_over"):
		_set_actions_enabled(true)

func _set_actions_enabled(enabled: bool) -> void:
	for action: String in _buttons:
		(_buttons[action] as Button).disabled = not enabled

func _retry() -> void:
	logic.call("restart_from_snapshot")
	if _stage != null:
		_stage.setup(battle_id)
	_show_result_buttons([])
	_refresh()

func _retreat() -> void:
	logic.call("restore_snapshot")
	_close(false)

func close_and_release(victory: bool) -> void:
	if _stage != null:
		_stage.clear_fighters()
	if _stage_host != null:
		_stage_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	visible = false
	battle_closed.emit(battle_id, victory)

func _close(victory: bool) -> void:
	close_and_release(victory)

func _show_result_buttons(items: Array) -> void:
	for c: Node in _result_row.get_children():
		c.queue_free()
	for item: Array in items:
		var b := _button(_result_row, str(item[0]))
		b.pressed.connect(item[1])
	_action_row.visible = items.is_empty()
	_result_row.visible = not items.is_empty()

func _refresh() -> void:
	var l := logic
	_title.text = "交手 · %s" % str(l.get("enemy_name"))
	_enemy_label.text = "%s　气血 %d / %d" % [str(l.get("enemy_name")), int(l.get("enemy_hp")), int(l.get("enemy_max_hp"))]
	var next := str(l.call("enemy_next_action"))
	if next == "":
		_intent_label.text = "胜负已分" if l.call("is_over") else ""
	else:
		_intent_label.text = "敌方下一手：" + str(BattleLogicScript.enemy_action_label(next))
	_player_label.text = "沈砚　气血 %d　内力 %d　药 × %d" % [int(l.get("hp")), int(l.get("qi")), int(l.get("potions"))]
	stats_changed.emit(int(l.get("hp")), int(l.get("qi")), int(l.get("potions")))
	var lines: Array = l.get("log_lines")
	var tail := lines.slice(maxi(0, lines.size() - 4))
	_log_label.text = "\n".join(PackedStringArray(tail))
	var avail: Dictionary = l.call("available_actions")
	for action: String in _buttons:
		(_buttons[action] as Button).disabled = not avail.get(action, false)

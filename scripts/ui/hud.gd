class_name GameHUD
extends CanvasLayer
## Landscape HUD: status, quest tracker, dynamic joystick, action key,
## dialogue layer, battle layer and the three menu overlays.

signal action_pressed
signal modal_changed(open: bool)

const BTN := 132.0
const MAIN_BTN := 192.0

var safe_area: Control
var status_panel: Panel
var menu_hbox: HBoxContainer
var quest_panel: Panel
var quest_label: Label
var joystick: Control
var action_button: Button
var skill_cluster: Control
var dialogue_panel: DialoguePanel
var toast: Label
var overlay_root: Control
var map_view: Control

var player_ref: Node3D
var world_ref: Node3D

var _theme: Theme
var _explore_mode := true
var _modal := false
var _quest_collapsed := false
var _hp_bar: Control
var _qi_bar: Control
var _hp_caption: Label
var _qi_caption: Label
var _potion_label: Label
var _cult_label: Label
var _avatar: TextureRect
var _toast_tween: Tween
var _inventory_panel: Panel
var _map_panel: Panel
var _menu_panel: Panel
var _skill_buttons: Array[Button] = []
var _save_toast := ""
## DQ-05: reward texts wait here until the post-dialogue save succeeds.
var _reward_cache: Array[String] = []

func _ready() -> void:
	layer = 10
	_theme = UiTheme.build_theme()
	_build()
	GameState.changed.connect(refresh)
	GameState.reward_granted.connect(_on_reward_granted)
	refresh()

# ------------------------------------------------------------------ build

func _build() -> void:
	safe_area = Control.new()
	safe_area.name = "SafeArea"
	safe_area.set_script(load("res://scripts/ui/safe_area.gd"))
	add_child(safe_area)
	safe_area.theme = _theme

	_build_status()
	_build_quest_tracker()
	_build_menu_bar()
	_build_joystick()
	_build_action_button()
	_build_skill_cluster()
	_build_toast()
	_build_overlays()

	dialogue_panel = DialoguePanel.new()
	dialogue_panel.name = "DialogueLayer"
	safe_area.add_child(dialogue_panel)

func _build_status() -> void:
	status_panel = Panel.new()
	status_panel.name = "StatusPanel"
	status_panel.offset_left = 0.0
	status_panel.offset_top = 0.0
	status_panel.offset_right = 640.0
	status_panel.offset_bottom = 158.0
	status_panel.add_to_group("hud_persistent")
	safe_area.add_child(status_panel)

	var frame := Panel.new()
	frame.position = Vector2(20.0, 24.0)
	frame.size = Vector2(116.0, 116.0)
	frame.add_theme_stylebox_override("panel", UiTheme.button_style(0.55, 0.9))
	status_panel.add_child(frame)

	_avatar = TextureRect.new()
	_avatar.position = Vector2(4.0, 4.0)
	_avatar.size = Vector2(108.0, 108.0)
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar.clip_contents = true
	# v3 立绘不在本包内：改用现有的 docs/ref-characters/shenyan_portrait.png。
	var portrait_path := "res://docs/ref-characters-v3/shenyan_portrait_v2.png"
	if ResourceLoader.exists(portrait_path):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(portrait_path)
		# 只取头肩部分做头像，避免整幅半身像缩成小人。
		atlas.region = Rect2(90.0, 40.0, 480.0, 480.0)
		_avatar.texture = atlas
	frame.add_child(_avatar)

	var name_label := Label.new()
	name_label.text = "沈 砚"
	name_label.position = Vector2(154.0, 2.0)
	name_label.size = Vector2(300.0, 48.0)
	name_label.add_theme_font_size_override("font_size", 38)
	name_label.add_theme_color_override("font_color", Color("#ecebe6"))
	status_panel.add_child(name_label)

	var divider := ColorRect.new()
	divider.color = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.5)
	divider.position = Vector2(154.0, 45.0)
	divider.size = Vector2(460.0, 1.5)
	status_panel.add_child(divider)

	_hp_caption = _small_label("气血 100 / 100", Vector2(154.0, 48.0), UiTheme.TEXT_DIM)
	status_panel.add_child(_hp_caption)
	_hp_bar = Control.new()
	_hp_bar.set_script(load("res://scripts/ui/stat_bar.gd"))
	_hp_bar.position = Vector2(154.0, 78.0)
	_hp_bar.size = Vector2(330.0, 14.0)
	_hp_bar.set("fill_color", UiTheme.HP_COLOR)
	_hp_bar.set("display_value", false)
	status_panel.add_child(_hp_bar)

	_qi_caption = _small_label("内力 20 / 30", Vector2(154.0, 98.0), UiTheme.TEXT_DIM)
	status_panel.add_child(_qi_caption)
	_qi_bar = Control.new()
	_qi_bar.set_script(load("res://scripts/ui/stat_bar.gd"))
	_qi_bar.position = Vector2(154.0, 128.0)
	_qi_bar.size = Vector2(330.0, 10.0)
	_qi_bar.set("fill_color", UiTheme.QI_COLOR)
	_qi_bar.set("display_value", false)
	status_panel.add_child(_qi_bar)

	_potion_label = _small_label("药 × 2", Vector2(510.0, 48.0), UiTheme.TEXT_DIM)
	status_panel.add_child(_potion_label)

	_cult_label = _small_label("修为 0 · 引气", Vector2(510.0, 80.0), Color("#c9b98e"))
	_cult_label.add_theme_font_size_override("font_size", 23)
	_cult_label.size = Vector2(125.0, 40.0)
	status_panel.add_child(_cult_label)

func _small_label(text: String, pos: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _build_quest_tracker() -> void:
	quest_panel = Panel.new()
	quest_panel.name = "QuestTracker"
	quest_panel.offset_left = 0.0
	quest_panel.offset_top = 170.0
	quest_panel.offset_right = 460.0
	quest_panel.offset_bottom = 302.0
	quest_panel.add_to_group("hud_persistent")
	quest_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(0.72, 18, 0.55))
	quest_panel.visible = false
	safe_area.add_child(quest_panel)
	quest_panel.gui_input.connect(_on_quest_gui_input)

	var stripe := ColorRect.new()
	stripe.color = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.7)
	stripe.position = Vector2(16.0, 16.0)
	stripe.size = Vector2(3.0, 80.0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(stripe)

	quest_label = Label.new()
	quest_label.position = Vector2(30.0, 12.0)
	quest_label.size = Vector2(412.0, 96.0)
	quest_label.add_theme_font_size_override("font_size", 28)
	quest_label.add_theme_color_override("font_color", Color(0.92, 0.89, 0.82, 0.95))
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quest_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.add_child(quest_label)

func _build_menu_bar() -> void:
	menu_hbox = HBoxContainer.new()
	menu_hbox.name = "MenuBar"
	menu_hbox.anchor_left = 1.0
	menu_hbox.anchor_right = 1.0
	menu_hbox.offset_left = -(BTN * 4.0 + 36.0)
	menu_hbox.offset_right = 0.0
	menu_hbox.offset_top = 0.0
	menu_hbox.offset_bottom = BTN
	menu_hbox.add_theme_constant_override("separation", 12)
	menu_hbox.add_to_group("hud_persistent")
	safe_area.add_child(menu_hbox)
	var buttons: Array[String] = ["行", "图", "存", "菜"]
	var tooltips: Array[String] = ["行囊", "地图", "存档", "菜单"]
	for i in buttons.size():
		var b := _menu_button(buttons[i])
		b.tooltip_text = tooltips[i]
		menu_hbox.add_child(b)
		b.pressed.connect(_on_menu_button.bind(i))

func _menu_button(glyph: String) -> Button:
	var b := _icon_tile_button("", glyph, BTN, 88.0, 62)
	b.name = "Menu" + glyph
	return b

## 132px touch target with only a small ink disc painted inside. Supplying a
## texture draws a 72px icon; otherwise the glyph is used as a placeholder.
func _icon_tile_button(icon_path: String, glyph: String, hot: float = BTN,
		tile: float = 96.0, glyph_size: int = 58) -> Button:
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = Vector2(hot, hot)
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, UiTheme.empty_style())
	var tile_panel := Panel.new()
	tile_panel.name = "Tile"
	tile_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_panel.position = Vector2((hot - tile) * 0.5, (hot - tile) * 0.5)
	tile_panel.size = Vector2(tile, tile)
	tile_panel.add_theme_stylebox_override("panel", UiTheme.icon_tile_style(tile * 0.5, 0.55, 0.8))
	b.add_child(tile_panel)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2((tile - 72.0) * 0.5, (tile - 72.0) * 0.5)
		icon.size = Vector2(72.0, 72.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_panel.add_child(icon)
	else:
		var label := Label.new()
		label.text = glyph
		label.position = Vector2.ZERO
		label.size = Vector2(tile, tile)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", glyph_size)
		label.add_theme_color_override("font_color", UiTheme.TEXT)
		label.add_theme_constant_override("outline_size", 4)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_panel.add_child(label)
	b.mouse_entered.connect(func() -> void: tile_panel.modulate = Color(1.18, 1.12, 1.0, 1.0))
	b.mouse_exited.connect(func() -> void: tile_panel.modulate = Color.WHITE)
	return b

func _build_skill_cluster() -> void:
	skill_cluster = Control.new()
	skill_cluster.name = "ActionCluster"
	skill_cluster.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skill_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_area.add_child(skill_cluster)
	# Compact arc hugging the right edge, so the central 50% x 55% view stays clear.
	var skills := [
		{"icon": "res://assets/icons/icon_attack_r4.png", "glyph": "攻", "right": 276.0, "bottom": 48.0},
		{"icon": "res://assets/icons/icon_sword_skill_r4.png", "glyph": "剑", "right": 292.0, "bottom": 204.0},
		{"icon": "res://assets/icons/icon_guard_r4.png", "glyph": "守", "right": 308.0, "bottom": 360.0},
		{"icon": "res://assets/icons/icon_potion_r4.png", "glyph": "药", "right": 324.0, "bottom": 516.0},
	]
	for spec: Dictionary in skills:
		var b := _icon_tile_button(str(spec["icon"]), str(spec["glyph"]))
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.anchor_top = 1.0
		b.anchor_bottom = 1.0
		b.offset_left = -(float(spec["right"]) + BTN)
		b.offset_right = -float(spec["right"])
		b.offset_top = -(float(spec["bottom"]) + BTN)
		b.offset_bottom = -float(spec["bottom"])
		b.disabled = true
		b.add_to_group("hud_persistent")
		skill_cluster.add_child(b)
		_skill_buttons.append(b)

func set_skills_enabled(enabled: bool) -> void:
	for b in _skill_buttons:
		b.disabled = not enabled

func _build_joystick() -> void:
	joystick = Control.new()
	joystick.name = "JoystickArea"
	joystick.set_script(load("res://scripts/ui/virtual_joystick.gd"))
	joystick.anchor_left = 0.0
	joystick.anchor_right = 0.4
	joystick.anchor_top = 0.45
	joystick.anchor_bottom = 1.0
	joystick.offset_left = 0.0
	joystick.offset_top = 0.0
	joystick.offset_right = 0.0
	joystick.offset_bottom = 0.0
	safe_area.add_child(joystick)

func _build_action_button() -> void:
	action_button = Button.new()
	action_button.name = "ActionButton"
	action_button.text = "交谈"
	action_button.anchor_left = 1.0
	action_button.anchor_right = 1.0
	action_button.anchor_top = 1.0
	action_button.anchor_bottom = 1.0
	action_button.offset_left = -(MAIN_BTN + 48.0)
	action_button.offset_right = -48.0
	action_button.offset_top = -(MAIN_BTN + 48.0)
	action_button.offset_bottom = -48.0
	action_button.add_theme_font_size_override("font_size", 42)
	action_button.add_to_group("hud_persistent")
	action_button.focus_mode = Control.FOCUS_NONE
	action_button.pressed.connect(func() -> void: action_pressed.emit())
	safe_area.add_child(action_button)

func _build_toast() -> void:
	toast = Label.new()
	toast.name = "Toast"
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -440.0
	toast.offset_right = 440.0
	toast.offset_top = 38.0
	toast.offset_bottom = 118.0
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 40)
	toast.add_theme_color_override("font_color", Color("#f4e6c8"))
	toast.add_theme_constant_override("outline_size", 8)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.visible = false
	safe_area.add_child(toast)

func _build_overlays() -> void:
	overlay_root = Control.new()
	overlay_root.name = "Overlays"
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.visible = false
	safe_area.add_child(overlay_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.add_child(dim)

	_inventory_panel = _build_centered_panel(Vector2(900.0, 600.0), "行 囊")
	_inventory_panel.visible = false
	var inv_label := Label.new()
	inv_label.position = Vector2(54.0, 112.0)
	inv_label.size = Vector2(790.0, 350.0)
	inv_label.add_theme_font_size_override("font_size", 34)
	inv_label.add_theme_color_override("font_color", UiTheme.TEXT)
	inv_label.add_theme_constant_override("line_spacing", 20)
	inv_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_inventory_panel.add_child(inv_label)
	_inventory_panel.set_meta("content", inv_label)

	_map_panel = _build_centered_panel(Vector2(1120.0, 690.0), "山 河 图")
	_map_panel.visible = false
	map_view = Control.new()
	map_view.set_script(load("res://scripts/ui/map_view.gd"))
	map_view.position = Vector2(46.0, 106.0)
	map_view.size = Vector2(1028.0, 470.0)
	_map_panel.add_child(map_view)
	var legend := _small_label("朱点：你所在处　·　金点：途中人物", Vector2(56.0, 596.0), UiTheme.TEXT_DIM)
	legend.add_theme_font_size_override("font_size", 26)
	_map_panel.add_child(legend)

	_menu_panel = _build_centered_panel(Vector2(760.0, 600.0), "菜 单")
	_menu_panel.visible = false
	var vb := VBoxContainer.new()
	vb.position = Vector2(140.0, 130.0)
	vb.size = Vector2(480.0, 420.0)
	vb.add_theme_constant_override("separation", 24)
	_menu_panel.add_child(vb)
	for i in 3:
		var b := Button.new()
		b.text = ["继续游戏", "保存进度", "退出游戏"][i]
		b.custom_minimum_size = Vector2(480.0, 120.0)
		b.add_theme_font_size_override("font_size", 36)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_menu_action.bind(i))
		vb.add_child(b)

func _build_centered_panel(panel_size: Vector2, title: String) -> Panel:
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_bottom = panel_size.y * 0.5
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(0.9, 18, 0.9))
	overlay_root.add_child(panel)
	var title_label := Label.new()
	title_label.text = title
	title_label.position = Vector2(44.0, 22.0)
	title_label.size = Vector2(panel_size.x - 88.0, 64.0)
	title_label.add_theme_font_size_override("font_size", 50)
	title_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	panel.add_child(title_label)
	var close := Button.new()
	close.text = "关闭"
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.anchor_top = 1.0
	close.anchor_bottom = 1.0
	close.offset_left = -172.0
	close.offset_right = -40.0
	close.offset_top = -172.0
	close.offset_bottom = -40.0
	close.add_theme_font_size_override("font_size", 34)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close_overlay)
	panel.add_child(close)
	return panel

# ------------------------------------------------------------------ public API

func bind_world(world: Node3D, player: Node3D) -> void:
	world_ref = world
	player_ref = player
	if map_view != null:
		map_view.set("player_ref", player)
		map_view.set("world_ref", world)

func set_explore_mode(enabled: bool) -> void:
	_explore_mode = enabled
	joystick.visible = enabled and not _modal
	# 开放世界没有强制任务列表：不显示任务追踪面板。
	quest_panel.visible = false
	action_button.visible = enabled
	menu_hbox.visible = enabled
	skill_cluster.visible = enabled
	if not enabled:
		joystick.call("cancel_touch")

func set_interaction(prompt: String, enabled: bool = true) -> void:
	action_button.text = prompt
	action_button.disabled = not enabled

func set_status_values(hp: int, qi: int, potions: int = -1) -> void:
	_hp_bar.call("set_stat", float(hp), float(GameState.MAX_HP))
	_qi_bar.call("set_stat", float(qi), float(GameState.MAX_QI))
	_hp_caption.text = "气血 %d / %d" % [hp, GameState.MAX_HP]
	_qi_caption.text = "内力 %d / %d" % [qi, GameState.MAX_QI]
	if potions >= 0:
		_potion_label.text = "药 × %d" % potions

func refresh() -> void:
	var qi := GameState.START_QI
	if _explore_mode:
		qi = GameState.START_QI
	set_status_values(GameState.hp, qi, GameState.potions)
	quest_label.text = ""
	if _cult_label != null:
		_cult_label.text = "修为 %d · %s" % [GameState.cultivation, GameState.realm_name()]
	if _inventory_panel.visible:
		_refresh_inventory()

func show_toast(text: String) -> void:
	toast.text = text
	toast.visible = true
	toast.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(1.9)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.45)
	_toast_tween.tween_callback(func() -> void: toast.visible = false)

func hide_toast() -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	toast.visible = false

## docs/godot-ui-plan.md §10: persistent HUD must stay inside the safe area,
## keep its minimum size, and leave the central 50% x 55% view clear.
func validate_layout() -> Array[String]:
	var errors: Array[String] = []
	if safe_area == null or not safe_area.is_inside_tree():
		return ["SafeArea missing"]
	var safe_rect := safe_area.get_global_rect()
	var central := Rect2(
		safe_rect.position + safe_rect.size * Vector2(0.25, 0.225),
		safe_rect.size * Vector2(0.5, 0.55)
	)
	for node: Node in get_tree().get_nodes_in_group("hud_persistent"):
		var c := node as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		if not safe_rect.encloses(r):
			errors.append("%s outside safe area: %s" % [c.name, r])
		if r.size.x < 132.0 or r.size.y < 132.0:
			errors.append("%s below 132px touch target: %s" % [c.name, r.size])
		if r.intersects(central):
			errors.append("%s intrudes into central view: %s" % [c.name, r])
	return errors

func is_modal_open() -> bool:
	return _modal

func _set_modal(open: bool) -> void:
	_modal = open
	if open:
		joystick.visible = false
		joystick.call("cancel_touch")
	elif _explore_mode:
		joystick.visible = true
	modal_changed.emit(open)

# ------------------------------------------------------------------ overlays

func _on_menu_button(index: int) -> void:
	match index:
		0:
			_refresh_inventory()
			_open_overlay(_inventory_panel)
		1:
			_open_overlay(_map_panel)
		2:
			_save_game_and_toast()
		3:
			_open_overlay(_menu_panel)

func _open_overlay(panel: Panel) -> void:
	for p: Panel in [_inventory_panel, _map_panel, _menu_panel]:
		p.visible = p == panel
	overlay_root.visible = true
	_set_modal(true)
	if panel == _inventory_panel:
		_refresh_inventory()
	if panel == _map_panel:
		map_view.queue_redraw()

func _close_overlay() -> void:
	overlay_root.visible = false
	_set_modal(false)

func _on_menu_action(index: int) -> void:
	match index:
		0:
			_close_overlay()
		1:
			_save_game_and_toast()
		2:
			get_tree().quit()

func _on_reward_granted(text: String) -> void:
	# Never toast here: the reward only counts once the save lands (DQ-05).
	_reward_cache.append(text)

func pending_reward_texts() -> Array[String]:
	return _reward_cache.duplicate()

## Called by the scene after DialogueRunner.finished. Saves, then shows the
## cached reward toast only on success; on failure the settlement is rolled
## back by GameState and the cache is dropped with a retry hint.
## Returns the save result ({} when nothing was saved).
## Tests point this at a scratch file so they never touch the player's save.
var save_path_override := ""

func settle_after_dialogue(cancelled: bool) -> Dictionary:
	if cancelled and not GameState.has_pending_settlement():
		_reward_cache.clear()
		return {}
	var had_rewards := not _reward_cache.is_empty() or GameState.has_pending_settlement()
	var res: Dictionary = GameState.save_game(save_path_override) if save_path_override != "" \
		else GameState.save_game()
	if res.get("ok", false):
		if not _reward_cache.is_empty():
			show_toast("奖励 · " + "、".join(PackedStringArray(_reward_cache)))
		_reward_cache.clear()
		return res
	_reward_cache.clear()
	if res.get("blocked", false):
		return res
	if had_rewards:
		if GameState.has_pending_settlement():
			GameState.rollback_pending_settlement()
		show_toast("存档失败，奖励未发放，可再次对话重试")
	else:
		show_toast("存档失败：" + str(res.get("error", "")))
	refresh()
	return res

func _save_game_and_toast() -> void:
	var res := GameState.save_game()
	if res.get("ok", false):
		show_toast("已存档 · " + str(res.get("saved_at", "")))
	else:
		show_toast("存档失败：" + str(res.get("error", "")))

func _refresh_inventory() -> void:
	var label := _inventory_panel.get_meta("content") as Label
	label.text = "\n".join([
		"回复药　× %d" % GameState.potions,
		"气血　%d / %d" % [GameState.hp, GameState.MAX_HP],
		"攻击　%d　　防御　%d" % [GameState.ATTACK, GameState.DEFENSE],
		"内力　%d / %d（每场战斗重置）" % [GameState.START_QI, GameState.MAX_QI],
		"",
		"行囊里只有周伯塞来的伤药，和一把未曾出鞘的剑。",
	])

func _on_quest_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_quest_collapsed = not _quest_collapsed
			refresh()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_quest_collapsed = not _quest_collapsed
			refresh()

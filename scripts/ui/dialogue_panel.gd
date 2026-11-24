class_name DialoguePanel
extends Control
## Bottom dialogue panel: portrait on the speaker's side, typewriter body,
## choices stacked above the panel. Taps anywhere advance; Esc cancels.

signal line_done
signal choice_selected(index: int)
signal cancel_requested

const PANEL_TOP_OFFSET := -300.0
const PANEL_BOTTOM_OFFSET := -36.0
const PORTRAIT_HEIGHT := 630.0
const TYPE_SPEED := 0.033
## DialogueDB points at res://assets/portraits (asset pipeline not present yet);
## fall back to the checked-in reference art so portraits always render.
# 第八轮：v2/v3 立绘路径（文件均在本树内，已逐一验证存在）。
const PORTRAIT_FALLBACKS := {
	"shenyan": "res://docs/ref-characters-v3/shenyan_portrait_v2.png",
	"linzhaowan": "res://docs/ref-characters-v3/linzhaowan_portrait_v2.png",
	"mingcheng": "res://docs/ref-characters-v3/npc/mingcheng_portrait_v3.png",
	"zhoubo": "res://docs/ref-characters-v3/npc/zhoubo_portrait_v3.png",
	"liheng": "res://docs/ref-characters-v3/npc/liheng_portrait_v3.png",
}

var _panel: Panel
var _name_label: Label
var _text: RichTextLabel
var _hint: Label
var _choices_box: VBoxContainer
var _left_portrait: TextureRect
var _right_portrait: TextureRect
var _dimmer: ColorRect
var _typing := false
var _type_tween: Tween
var _hint_time := 0.0
var _awaiting_choice := false
var _choice_buttons: Array[Button] = []
var _last_portrait_by_side := {"left": "", "right": ""}
## Narrator lines (portrait key transition.fade_black): full-screen black card
## with centred narration; the card fades out before line_done is emitted.
const FADE_BLACK_KEY := "transition.fade_black"
const FADE_TIME := 0.45
var _black: ColorRect
var _narration: Label
var _narrating := false
var _fade_tween: Tween
var _fading_out := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()

func _build() -> void:
	_dimmer = ColorRect.new()
	_dimmer.color = Color(0.02, 0.03, 0.04, 0.16)
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dimmer)

	_left_portrait = _make_portrait(true)
	_right_portrait = _make_portrait(false)

	_panel = Panel.new()
	_panel.name = "DialoguePanel"
	_panel.anchor_left = 0.2
	_panel.anchor_right = 0.8
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = PANEL_TOP_OFFSET
	_panel.offset_bottom = PANEL_BOTTOM_OFFSET
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_name_label = Label.new()
	_name_label.anchor_right = 1.0
	_name_label.offset_left = 30.0
	_name_label.offset_top = 14.0
	_name_label.offset_right = -30.0
	_name_label.offset_bottom = 66.0
	_name_label.add_theme_font_size_override("font_size", 42)
	_name_label.add_theme_constant_override("outline_size", 6)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_name_label)

	_text = RichTextLabel.new()
	_text.anchor_right = 1.0
	_text.anchor_bottom = 1.0
	_text.offset_left = 32.0
	_text.offset_top = 70.0
	_text.offset_right = -32.0
	_text.offset_bottom = -18.0
	_text.bbcode_enabled = false
	_text.fit_content = false
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 44)
	_text.add_theme_constant_override("line_separation", 10)
	_text.add_theme_constant_override("outline_size", 3)
	_panel.add_child(_text)

	_hint = Label.new()
	_hint.text = "▼"
	_hint.add_theme_font_size_override("font_size", 28)
	_hint.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -58.0
	_hint.offset_top = -46.0
	_hint.offset_right = -22.0
	_hint.offset_bottom = -8.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_hint)

	_choices_box = VBoxContainer.new()
	_choices_box.name = "Choices"
	_choices_box.anchor_left = 0.54
	_choices_box.anchor_right = 0.8
	_choices_box.anchor_top = 0.18
	_choices_box.anchor_bottom = 1.0
	_choices_box.offset_top = 0.0
	_choices_box.offset_bottom = PANEL_TOP_OFFSET - 24.0
	_choices_box.offset_left = 0.0
	_choices_box.offset_right = 0.0
	_choices_box.alignment = BoxContainer.ALIGNMENT_END
	_choices_box.add_theme_constant_override("separation", 24)
	_choices_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_choices_box)
	_build_narration()

func _make_portrait(left: bool) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if left:
		tr.anchor_left = 0.005
		tr.anchor_right = 0.235
	else:
		tr.anchor_left = 0.765
		tr.anchor_right = 0.995
	tr.anchor_top = 1.0
	tr.anchor_bottom = 1.0
	tr.offset_top = PANEL_TOP_OFFSET - PORTRAIT_HEIGHT
	tr.offset_bottom = PANEL_TOP_OFFSET
	tr.offset_left = 0.0
	tr.offset_right = 0.0
	add_child(tr)
	return tr

func _build_narration() -> void:
	_black = ColorRect.new()
	_black.name = "FadeBlack"
	_black.color = Color(0.0, 0.0, 0.0, 1.0)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	_black.visible = false
	# The panel lives inside the HUD SafeArea; the black card must still cover
	# the whole screen (no 12 px scene leak), so it ignores the parent rect.
	_black.top_level = true
	add_child(_black)
	_narration = Label.new()
	_narration.name = "Narration"
	_narration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_narration.offset_left = 260.0
	_narration.offset_right = -260.0
	_narration.offset_top = 80.0
	_narration.offset_bottom = -80.0
	_narration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_narration.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_narration.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narration.add_theme_font_size_override("font_size", 44)
	_narration.add_theme_color_override("font_color", Color("#efe4cc"))
	_narration.add_theme_constant_override("line_spacing", 14)
	_narration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.add_child(_narration)

## Size the narration card to the full viewport (top_level ignores SafeArea padding).
func fit_black_to_viewport() -> void:
	if _black == null or not is_inside_tree():
		return
	_black.position = Vector2.ZERO
	_black.size = get_viewport_rect().size

func black_rect() -> Rect2:
	return _black.get_global_rect() if _black != null else Rect2()

func is_narrating() -> bool:
	return _narrating

func _show_narration(text: String) -> void:
	_narrating = true
	_fading_out = false
	_panel.visible = false
	_dimmer.visible = false
	_left_portrait.visible = false
	_right_portrait.visible = false
	_clear_choices()
	_narration.text = text
	_narration.visible_ratio = 0.0
	fit_black_to_viewport()
	_black.visible = true
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_typing = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(_black, "modulate:a", 1.0, FADE_TIME)
	_fade_tween.tween_property(_narration, "visible_ratio", 1.0,
		clampf(float(text.length()) * TYPE_SPEED * 1.4, 0.5, 2.2))
	_fade_tween.finished.connect(func() -> void: _typing = false)

func _end_narration_then_done() -> void:
	if _fading_out:
		return
	_fading_out = true
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_black, "modulate:a", 0.0, FADE_TIME)
	_fade_tween.finished.connect(func() -> void:
		_reset_narration()
		line_done.emit())

func _reset_narration() -> void:
	_narrating = false
	_fading_out = false
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_black.visible = false
	_black.modulate.a = 0.0
	_panel.visible = true
	_dimmer.visible = true
	_left_portrait.visible = true
	_right_portrait.visible = true

func _process(delta: float) -> void:
	if not visible:
		return
	_hint_time += delta
	_hint.modulate.a = 0.35 + 0.55 * (0.5 + 0.5 * sin(_hint_time * 4.5))
	_hint.visible = not _typing and not _awaiting_choice and not _narrating

func show_line(node: Dictionary, speaker_name: String, text: String, portrait_path: String, side: String) -> void:
	visible = true
	modulate.a = 1.0
	# 不在 UI 基类里直接引用 autoload 标识符：测试里的 FakePanel 会独立编译本脚本。
	var dialogue_db := get_node_or_null("/root/DialogueDB")
	var portrait_key := str(dialogue_db.call("portrait_key", node)) if dialogue_db != null else ""
	if portrait_key == FADE_BLACK_KEY:
		_show_narration(text)
		return
	if _narrating:
		_reset_narration()
	_awaiting_choice = false
	_clear_choices()
	_name_label.text = speaker_name
	_name_label.add_theme_color_override("font_color", UiTheme.faction_color(str(node.get("speaker", ""))))
	_text.text = text
	_text.visible_ratio = 0.0
	_typing = true
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	var duration := clampf(float(text.length()) * TYPE_SPEED, 0.35, 1.45)
	_type_tween = create_tween()
	_type_tween.tween_property(_text, "visible_ratio", 1.0, duration)
	_type_tween.finished.connect(func() -> void: _typing = false)
	_show_portrait(side, portrait_path)
	_hint_time = 0.0
	visible = true
	modulate.a = 1.0

func _resolve_portrait(path: String) -> String:
	if path != "" and ResourceLoader.exists(path):
		return path
	var file := path.get_file().to_lower()
	for key: String in PORTRAIT_FALLBACKS:
		if file.contains(key):
			return PORTRAIT_FALLBACKS[key]
	return ""

func _show_portrait(side: String, path: String) -> void:
	var resolved := _resolve_portrait(path)
	if resolved == "":
		return
	var tex: Texture2D = load(resolved)
	if tex == null:
		return
	var target := _left_portrait if side == "left" else _right_portrait
	var other := _right_portrait if side == "left" else _left_portrait
	target.texture = tex
	target.modulate = Color.WHITE
	_last_portrait_by_side[side] = path
	if other.texture != null:
		other.modulate = Color(0.55, 0.55, 0.55, 0.85)

func is_typing() -> bool:
	return _typing

func finish_typing() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_typing = false
	_text.visible_ratio = 1.0

func show_choices(options: Array) -> void:
	_awaiting_choice = true
	_clear_choices()
	for i in options.size():
		var option: Dictionary = options[i]
		var button := Button.new()
		button.text = str(option.get("text", "……"))
		button.custom_minimum_size = Vector2(0.0, 132.0)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 36)
		button.add_theme_stylebox_override("normal", UiTheme.button_style(0.8, 0.8))
		button.pressed.connect(_on_choice_pressed.bind(i))
		_choices_box.add_child(button)
		_choice_buttons.append(button)
	_choices_box.visible = true
	_hint.visible = false

func _on_choice_pressed(index: int) -> void:
	if not _awaiting_choice:
		return
	_awaiting_choice = false
	_clear_choices()
	choice_selected.emit(index)

func _clear_choices() -> void:
	for b in _choice_buttons:
		b.queue_free()
	_choice_buttons.clear()
	_choices_box.visible = false

func hide_dialogue() -> void:
	visible = false
	_reset_narration()
	_awaiting_choice = false
	_typing = false
	_clear_choices()
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_text.text = ""
	# Release portrait texture references on close (UI plan §7).
	_left_portrait.texture = null
	_right_portrait.texture = null
	_last_portrait_by_side = {"left": "", "right": ""}

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel_requested.emit()
		if _narrating:
			_reset_narration()
		if _awaiting_choice:
			_awaiting_choice = false
			_clear_choices()
			choice_selected.emit(-1)
		else:
			line_done.emit()
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_advance()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			_advance()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			get_viewport().set_input_as_handled()
			_advance()

## 供 HUD/主控在对话中主动推进（点击「交谈」键走这里）。
func advance() -> void:
	_advance()


func _advance() -> void:
	if _awaiting_choice:
		return
	if _narrating:
		if _fading_out:
			return
		if _typing:
			if _fade_tween != null and _fade_tween.is_valid():
				_fade_tween.kill()
			_black.modulate.a = 1.0
			_narration.visible_ratio = 1.0
			_typing = false
			return
		_end_narration_then_done()
		return
	if _typing:
		finish_typing()
		return
	line_done.emit()

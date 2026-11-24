class_name UiTheme
extends RefCounted
## Ink-and-gold HUD theme. All styling lives here so screens share one look.

const GOLD := Color("#B08D57")
const GOLD_BRIGHT := Color("#D8B77A")
const INK := Color("#141414")
const TEXT := Color("#F2ECE0")
const TEXT_DIM := Color("#A89F91")
const TEXT_FAINT := Color("#7C7468")
const HP_COLOR := Color("#B24A4A")
const QI_COLOR := Color("#4E7FA8")
const SHENYAN_COLOR := Color("#A9C3E2")
const LINZHAOWAN_COLOR := Color("#D98A9A")
const NPC_COLOR := Color("#C9BFAE")

const FONT_SERIF := "res://assets/fonts/shanhe_serif.otf"

static func body_font() -> Font:
	if ResourceLoader.exists(FONT_SERIF):
		var f: Font = load(FONT_SERIF)
		return f
	return ThemeDB.fallback_font

static func panel_style(alpha: float = 0.72, radius: int = 18, border_alpha: float = 0.8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK.r, INK.g, INK.b, alpha)
	var border := GOLD
	border.a = border_alpha
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(18.0)
	return sb

static func button_style(alpha: float = 0.72, border_alpha: float = 0.78) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK.r, INK.g, INK.b, alpha)
	var border := GOLD
	border.a = border_alpha
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(10.0)
	return sb

## Invisible hot area with a smaller ink tile: icon buttons keep a 132px touch
## target without painting a 132px solid block.
static func icon_tile_style(radius: float = 18.0, alpha: float = 0.55,
		border_alpha: float = 0.8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK.r, INK.g, INK.b, alpha)
	var border := GOLD
	border.a = border_alpha
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(int(radius))
	return sb

static func empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

static func build_theme() -> Theme:
	var theme := Theme.new()
	var font := body_font()
	theme.default_font = font
	theme.default_font_size = 36

	theme.set_font("font", "Button", font)
	theme.set_font_size("font_size", "Button", 36)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", GOLD_BRIGHT)
	theme.set_color("font_pressed_color", "Button", GOLD_BRIGHT)
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.52, 0.48, 0.7))
	theme.set_stylebox("normal", "Button", button_style(0.72, 0.78))
	theme.set_stylebox("hover", "Button", button_style(0.84, 1.0))
	theme.set_stylebox("pressed", "Button", button_style(0.9, 1.0))
	theme.set_stylebox("disabled", "Button", button_style(0.42, 0.3))
	theme.set_stylebox("focus", "Button", button_style(0.5, 0.95))

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.72))
	theme.set_constant("outline_size", "Label", 4)
	theme.set_font_size("font_size", "Label", 36)

	theme.set_font("normal_font", "RichTextLabel", font)
	theme.set_font_size("normal_font_size", "RichTextLabel", 44)
	theme.set_font("bold_font", "RichTextLabel", font)
	theme.set_font_size("bold_font_size", "RichTextLabel", 44)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_color("font_outline_color", "RichTextLabel", Color(0, 0, 0, 0.7))
	theme.set_constant("outline_size", "RichTextLabel", 3)
	theme.set_constant("line_separation", "RichTextLabel", 16)

	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "Panel", panel_style())
	theme.set_stylebox("panel", "PopupPanel", panel_style(0.92))

	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_color", "CheckButton", TEXT)
	return theme

static func label_settings(size: int = 36, color: Color = TEXT) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = body_font()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 5
	ls.outline_color = Color(0, 0, 0, 0.75)
	ls.line_spacing = 6
	return ls

static func faction_color(speaker: String) -> Color:
	match speaker:
		"shenyan":
			return SHENYAN_COLOR
		"linzhaowan":
			return LINZHAOWAN_COLOR
		_:
			return NPC_COLOR

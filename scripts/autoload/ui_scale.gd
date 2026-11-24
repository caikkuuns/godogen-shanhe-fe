extends Node
## dp → design-pixel conversion for the 1920×1080 canvas_items layout.
## A touch target must never fall below its dp minimum on tall/dense screens.

func dp(value: float) -> float:
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		dpi = 160.0
	var win_h := float(DisplayServer.window_get_size().y)
	if win_h <= 0.0:
		win_h = 1080.0
	return value * (dpi / 160.0) * (1080.0 / win_h)

## Design value (44dp → 132 px is the baseline used by docs/godot-ui-plan.md).
func design(value_dp: float) -> float:
	return value_dp * 3.0

func min_px(value_dp: float, base_px: float) -> float:
	return maxf(base_px, dp(value_dp))

func safe_padding() -> float:
	return dp(8.0)

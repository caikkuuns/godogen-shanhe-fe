extends Node
## 游戏内时间/天气。机缘每 24 游戏分钟刷新一次；天气按 120 分钟一段循环，
## 完全确定性（测试可直接 advance 到目标时刻）。

signal time_changed(total_minutes: float)
signal weather_changed(weather: String)

## 现实 1 秒 = 2 游戏分钟；探索一会儿就能看到光影与机缘变化。
const MINUTES_PER_SECOND := 2.0
const START_MINUTES := 8.0 * 60.0
## 每 120 游戏分钟换一次天气；顺序固定，便于截图/测试复现。
const WEATHER_STEP_MINUTES := 120.0
const WEATHER_CYCLE: Array[String] = ["clear", "mist", "clear", "rain", "clear", "clear"]

var game_minutes := START_MINUTES
var weather := "clear"
var paused := false

func _process(delta: float) -> void:
	if not paused:
		advance(delta * MINUTES_PER_SECOND)

func advance(minutes: float) -> void:
	if minutes <= 0.0:
		return
	game_minutes += minutes
	_recompute_weather()
	time_changed.emit(game_minutes)

func _recompute_weather() -> void:
	var index := int(floor(game_minutes / WEATHER_STEP_MINUTES)) % WEATHER_CYCLE.size()
	var next := WEATHER_CYCLE[index]
	if next != weather:
		weather = next
		weather_changed.emit(weather)

func hour() -> int:
	return int(floor(fposmod(game_minutes, 1440.0) / 60.0)) % 24

func time_of_day() -> String:
	var h := hour()
	if h >= 5 and h < 8:
		return "dawn"
	if h >= 8 and h < 17:
		return "day"
	if h >= 17 and h < 20:
		return "dusk"
	return "night"

func day_index() -> int:
	return int(floor(game_minutes / 1440.0))

func reset() -> void:
	game_minutes = START_MINUTES
	weather = "clear"
	paused = false
	time_changed.emit(game_minutes)

## 测试/截图用：直接设定时刻与天气。
func set_time(total_minutes: float, new_weather: String = "") -> void:
	game_minutes = maxf(0.0, total_minutes)
	if new_weather != "":
		weather = new_weather
	else:
		_recompute_weather()
	time_changed.emit(game_minutes)
	weather_changed.emit(weather)

extends Node
## 机缘数据与抽取。
## - 稀有度概率：common 70% / rare 25% / legendary 5%
## - legendary 在同一区块同时最多 1 个
## - 每 24 游戏分钟刷新一轮；已用记录按 cooldown_minutes 保留，离开区块不丢

signal refreshed

const DATA_PATH := "res://data/encounters.json"
const RARITY_WEIGHTS := {"common": 0.70, "rare": 0.25, "legendary": 0.05}
const RARITIES: Array[String] = ["common", "rare", "legendary"]
const KINDS: Array[String] = ["combat", "npc", "item", "event", "lore"]
const LEVEL_BANDS: Array[String] = ["1-10", "11-20", "21-30"]
const TRIGGERS: Array[String] = ["proximity", "interact", "time", "weather", "flag"]
const REFRESH_MINUTES := 24.0

var data: Dictionary = {}
var entries: Array[Dictionary] = []
var load_error := ""

var _by_id: Dictionary = {}
## id -> 过期游戏分钟。记录在地图管理器层，区块卸载不清空。
var _used: Dictionary = {}
## region_id -> legendary 记录 id
var _legendary_active: Dictionary = {}
var _last_refresh := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 20261121
	reload()

func reload() -> bool:
	data = {}
	entries = []
	_by_id = {}
	load_error = ""
	_used.clear()
	_legendary_active.clear()
	_last_refresh = 0.0
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		load_error = "missing %s" % DATA_PATH
		return false
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		load_error = "%s: line %d: %s" % [DATA_PATH, json.get_error_line(), json.get_error_message()]
		f.close()
		return false
	f.close()
	if typeof(json.data) != TYPE_DICTIONARY:
		load_error = "encounters.json is not an object"
		return false
	data = json.data
	if int(data.get("schemaVersion", 0)) != 1:
		load_error = "schemaVersion != 1"
		return false
	var list: Variant = data.get("encounters", [])
	if typeof(list) != TYPE_ARRAY:
		load_error = "encounters[] missing"
		return false
	for item: Variant in list:
		if typeof(item) != TYPE_DICTIONARY:
			load_error = "encounter entry is not an object"
			return false
		var e: Dictionary = item
		var id := str(e.get("id", ""))
		if id == "" or _by_id.has(id):
			load_error = "bad/duplicate encounter id: %s" % id
			return false
		_by_id[id] = e
		entries.append(e)
	return true

# ------------------------------------------------------------------ 抽取

func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value

## 单次稀有度掷骰；传入独立 RNG 时可用于无副作用测试。
func roll_rarity(rng: RandomNumberGenerator = null) -> String:
	var r := rng if rng != null else _rng
	var v := r.randf()
	if v < RARITY_WEIGHTS["common"]:
		return "common"
	if v < RARITY_WEIGHTS["common"] + RARITY_WEIGHTS["rare"]:
		return "rare"
	return "legendary"

func _weighted_pick(candidates: Array, rng: RandomNumberGenerator) -> Dictionary:
	if candidates.is_empty():
		return {}
	var total := 0.0
	for c: Variant in candidates:
		total += maxf(0.01, float((c as Dictionary).get("weight", 1.0)))
	var roll := rng.randf() * total
	for c: Variant in candidates:
		var d: Dictionary = c
		roll -= maxf(0.01, float(d.get("weight", 1.0)))
		if roll <= 0.0:
			return d
	return candidates[candidates.size() - 1]

func _matches_region(record: Dictionary, tags: Array) -> bool:
	var rec_tags: Variant = record.get("region_tags", [])
	if typeof(rec_tags) != TYPE_ARRAY:
		return false
	for tag: Variant in rec_tags:
		if str(tag) in tags or str(tag) == "":
			return true
	return false

func _candidates(tags: Array, rarity: String, now: float) -> Array:
	var out: Array = []
	for record: Dictionary in entries:
		if str(record.get("rarity", "")) != rarity:
			continue
		if not _matches_region(record, tags):
			continue
		if is_used(str(record.get("id", "")), now):
			continue
		out.append(record)
	return out

## 为一个区块抽一个机缘。forced_rarity 只用于测试；正式路径由 70/25/5 决定。
## legendary 上限：同区已有 legendary 时自动降为 rare。
func pick_for_region(region_id: String, tags: Array, now: float,
		rng: RandomNumberGenerator = null, forced_rarity: String = "") -> Dictionary:
	refresh_if_due(now)
	var r := rng if rng != null else _rng
	var wanted := forced_rarity if forced_rarity in RARITIES else roll_rarity(r)
	if wanted == "legendary" and _has_other_legendary(region_id, ""):
		wanted = "rare"
	var order: Array[String] = [wanted]
	for rarity: String in ["rare", "common", "legendary"]:
		if rarity not in order:
			order.append(rarity)
	for rarity: String in order:
		if rarity == "legendary" and _has_other_legendary(region_id, ""):
			continue
		var candidates := _candidates(tags, rarity, now)
		if candidates.is_empty():
			continue
		var picked := _weighted_pick(candidates, r)
		picked = picked.duplicate(true)
		picked["_region"] = region_id
		return picked
	return {}

func _has_other_legendary(region_id: String, exclude_id: String) -> bool:
	var current := str(_legendary_active.get(region_id, ""))
	return current != "" and current != exclude_id

## 生成一个区块的整批机缘。point_count 决定点位数；legendary 最多 1 个。
func spawn_batch(region_id: String, tags: Array, point_count: int, now: float,
		rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r := rng if rng != null else _rng
	for i in maxi(0, point_count):
		var picked := pick_for_region(region_id, tags, now, r)
		if picked.is_empty():
			continue
		picked["_index"] = i
		out.append(picked)
		mark_spawned(picked, region_id)
	return out

func mark_spawned(record: Dictionary, region_id: String) -> void:
	if str(record.get("rarity", "")) == "legendary":
		_legendary_active[region_id] = str(record.get("id", ""))

func is_used(record_id: String, now: float) -> bool:
	var expire := float(_used.get(record_id, -1.0))
	if expire <= now:
		if _used.has(record_id):
			_used.erase(record_id)
		return false
	return true

func mark_used(record_id: String, region_id: String, now: float) -> void:
	var record := get_record(record_id)
	var cooldown := maxf(REFRESH_MINUTES, float(record.get("cooldown_minutes", REFRESH_MINUTES)))
	_used[record_id] = now + cooldown
	if str(_legendary_active.get(region_id, "")) == record_id:
		_legendary_active.erase(region_id)

## 每 24 分钟一轮：清空“同区传奇占用”，并用过的记录按各自 cooldown 过期。
func refresh_if_due(now: float) -> bool:
	if now - _last_refresh < REFRESH_MINUTES:
		return false
	_last_refresh = now
	_legendary_active.clear()
	for id: String in _used.keys():
		if float(_used[id]) <= now:
			_used.erase(id)
	refreshed.emit()
	return true

func reset_cycle(now: float = 0.0) -> void:
	_used.clear()
	_legendary_active.clear()
	_last_refresh = now

func used_count() -> int:
	return _used.size()

func legendary_active(region_id: String) -> String:
	return str(_legendary_active.get(region_id, ""))

func get_record(record_id: String) -> Dictionary:
	return (_by_id.get(record_id, {}) as Dictionary).duplicate(true)

func region_encounters(tags: Array) -> Array:
	var out: Array = []
	for record: Dictionary in entries:
		if _matches_region(record, tags):
			out.append(record)
	return out

# ------------------------------------------------------------------ 校验

func validate() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for record: Dictionary in entries:
		var id := str(record.get("id", ""))
		if id == "" or seen.has(id):
			errors.append("bad/duplicate id %s" % id)
		seen[id] = true
		if str(record.get("kind", "")) not in KINDS:
			errors.append("%s: bad kind" % id)
		if str(record.get("rarity", "")) not in RARITIES:
			errors.append("%s: bad rarity" % id)
		if str(record.get("level_band", "")) not in LEVEL_BANDS:
			errors.append("%s: bad level_band" % id)
		if str(record.get("trigger", "")) not in TRIGGERS:
			errors.append("%s: bad trigger" % id)
		if float(record.get("weight", 0.0)) <= 0.0:
			errors.append("%s: weight <= 0" % id)
		if float(record.get("cooldown_minutes", 0.0)) <= 0.0:
			errors.append("%s: cooldown <= 0" % id)
		var tags: Variant = record.get("region_tags", [])
		if typeof(tags) != TYPE_ARRAY or (tags as Array).is_empty():
			errors.append("%s: region_tags missing" % id)
		if typeof(record.get("payload", null)) != TYPE_DICTIONARY:
			errors.append("%s: payload missing" % id)
	return errors

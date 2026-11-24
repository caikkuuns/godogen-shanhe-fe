extends Node
## 隐藏分支条件与台词。没有任务列表，也没有“已接取”提示：
## 命中后只返回要写入的 dlg.hidden.* flags，由对话结束时一次性提交。

const DATA_PATH := "res://data/hidden-dialogues.json"

var data: Dictionary = {}
var records: Array[Dictionary] = []
var load_error := ""

func _ready() -> void:
	reload()

func reload() -> bool:
	data = {}
	records = []
	load_error = ""
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
		load_error = "hidden-dialogues.json is not an object"
		return false
	data = json.data
	if int(data.get("schemaVersion", 0)) != 1:
		load_error = "schemaVersion != 1"
		return false
	var list: Variant = data.get("records", [])
	if typeof(list) != TYPE_ARRAY:
		load_error = "records[] missing"
		return false
	for item: Variant in list:
		if typeof(item) == TYPE_DICTIONARY:
			records.append(item)
	# 优先级高的先判定。
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)
	return true

## ctx 约定：
##   talk_count / talk_total / inventory / reputation / time_of_day / weather /
##   region / encounter_used / encounter_rarities_used / flags
## 未知条件键一律视为不命中，避免数据写错时“静默通过”。
func evaluate(record: Dictionary, ctx: Dictionary) -> bool:
	var conds: Variant = record.get("conditions", {})
	if typeof(conds) != TYPE_DICTIONARY:
		return false
	for key: String in conds:
		var expected: Variant = conds[key]
		match key:
			"talk_count_min":
				if int(ctx.get("talk_count", 0)) < int(expected):
					return false
			"talk_count_max":
				if int(ctx.get("talk_count", 0)) > int(expected):
					return false
			"talk_total_min":
				if int(ctx.get("talk_total", 0)) < int(expected):
					return false
			"has_item":
				if not _has_item(ctx, str(expected)):
					return false
			"item_min":
				var item_id := str(conds.get("has_item", ""))
				if _item_count(ctx, item_id) < int(expected):
					return false
			"reputation_min":
				if int(ctx.get("reputation", 0)) < int(expected):
					return false
			"time_of_day":
				if not _matches_any(ctx.get("time_of_day", ""), expected):
					return false
			"weather":
				if not _matches_any(ctx.get("weather", ""), expected):
					return false
			"region":
				if not _matches_any(ctx.get("region", ""), expected):
					return false
			"encounter_used":
				if bool(ctx.get("encounter_used", false)) != bool(expected):
					return false
			"encounter_rarity_used":
				if not _rarities_overlap(ctx.get("encounter_rarities_used", []), expected):
					return false
			"flags_all":
				if not _flags_all(ctx.get("flags", {}), expected):
					return false
			"flags_none":
				if not _flags_none(ctx.get("flags", {}), expected):
					return false
			_:
				push_warning("hidden dialogue: unknown condition key %s" % key)
				return false
	return true

func _has_item(ctx: Dictionary, item_id: String) -> bool:
	return _item_count(ctx, item_id) > 0

func _item_count(ctx: Dictionary, item_id: String) -> int:
	var inventory: Variant = ctx.get("inventory", {})
	if typeof(inventory) != TYPE_DICTIONARY or item_id == "":
		return 0
	return int((inventory as Dictionary).get(item_id, 0))

func _matches_any(actual: Variant, expected: Variant) -> bool:
	if typeof(expected) == TYPE_ARRAY:
		return actual in (expected as Array)
	return str(actual) == str(expected)

func _rarities_overlap(actual: Variant, expected: Variant) -> bool:
	var values: Array = actual if typeof(actual) == TYPE_ARRAY else [actual]
	if typeof(expected) == TYPE_ARRAY:
		for v: Variant in expected:
			if v in values:
				return true
		return false
	return expected in values

func _flags_all(flags: Variant, expected: Variant) -> bool:
	if typeof(flags) != TYPE_DICTIONARY or typeof(expected) != TYPE_ARRAY:
		return false
	for key: Variant in expected:
		if (flags as Dictionary).get(str(key), false) != true:
			return false
	return true

func _flags_none(flags: Variant, expected: Variant) -> bool:
	if typeof(flags) != TYPE_DICTIONARY or typeof(expected) != TYPE_ARRAY:
		return false
	for key: Variant in expected:
		if (flags as Dictionary).get(str(key), false) == true:
			return false
	return true

## 命中：身份匹配、区块匹配（record 未限定区块则任意）、条件全真、
## 且该 record 的 flags 还没有写过。返回 {} 表示没有隐藏分支。
func pick(npc_identity: String, ctx: Dictionary) -> Dictionary:
	var flags: Variant = ctx.get("flags", {})
	for record: Dictionary in records:
		var want_identity := str(record.get("identity", "*"))
		if want_identity != "*" and want_identity != npc_identity:
			continue
		var want_region := str(record.get("region", ""))
		if want_region != "" and want_region != str(ctx.get("region", "")):
			continue
		if _already_written(record, flags):
			continue
		if evaluate(record, ctx):
			return record
	return {}

func _already_written(record: Dictionary, flags: Variant) -> bool:
	var set_flags: Variant = record.get("setFlags", {})
	if typeof(set_flags) != TYPE_DICTIONARY or typeof(flags) != TYPE_DICTIONARY:
		return false
	for key: String in set_flags:
		if (flags as Dictionary).get(key, false) == true:
			return true
	return false

func record_flags(record: Dictionary) -> Dictionary:
	var out := {}
	var set_flags: Variant = record.get("setFlags", {})
	if typeof(set_flags) == TYPE_DICTIONARY:
		for key: String in set_flags:
			if key.begins_with("dlg.hidden."):
				out[key] = bool(set_flags[key])
	return out

func lines(record: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for line: Variant in record.get("lines", []):
		out.append(str(line))
	return out

func validate() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for record: Dictionary in records:
		var id := str(record.get("id", ""))
		if id == "" or seen.has(id):
			errors.append("bad/duplicate id %s" % id)
		seen[id] = true
		if str(record.get("identity", "")) == "":
			errors.append("%s: identity missing" % id)
		if lines(record).size() < 1:
			errors.append("%s: lines missing" % id)
		var flags := record_flags(record)
		if flags.is_empty():
			errors.append("%s: no dlg.hidden.* flags" % id)
		if typeof(record.get("conditions", null)) != TYPE_DICTIONARY:
			errors.append("%s: conditions not object" % id)
	return errors

func identity_coverage() -> Dictionary:
	var out := {}
	for record: Dictionary in records:
		out[str(record.get("identity", ""))] = true
	return out

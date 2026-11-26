extends Node
## Atomic local save/load. No network, no cloud.
## Current format is version 3 (adds chapter-3 quest blocks); version 1 and 2
## saves are still accepted (missing chapter-2/3 blocks default in
## GameState.apply_dict, which is the v1/v2 -> v3 migration).
##
## Write protocol: serialize -> *.tmp -> read back and compare -> rename the old
## save to *.bak -> rename *.tmp to the live path. A failed rename rolls back.

const VERSION := 3
const MIN_VERSION := 1
const SAVE_PATH := "user://save_v1.json"

## Test-only fault injection. "" = normal; "readback" = temp file read-back
## fails; "rename" = final tmp -> live rename fails. Consumed (cleared) at the start of every save_state() call.
var test_fail_stage := ""

func _tmp_path(path: String) -> String:
	return path + ".tmp"

func _bak_path(path: String) -> String:
	return path + ".bak"

func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)

func save_state(data: Dictionary, path: String = SAVE_PATH) -> Dictionary:
	# Consume the test hook first so no early return can leave it armed.
	# 第10轮修复：注入钩子只在 debug 构建里生效，正式包即使被外部设值也不会
	# 触发写失败（之前它直接活在产品代码路径上）。
	var inject := ""
	if OS.is_debug_build():
		inject = test_fail_stage
	test_fail_stage = ""
	var payload := data.duplicate(true)
	payload["version"] = VERSION
	payload["saved_at"] = Time.get_datetime_string_from_system()
	var text := JSON.stringify(payload, "\t")
	if text.is_empty():
		return {"ok": false, "error": "存档序列化失败"}

	var tmp_path := _tmp_path(path)
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "无法写入存档（%s）" % error_string(FileAccess.get_open_error())}
	f.store_string(text)
	f.flush()
	f.close()

	# Verify the bytes we just wrote before touching the live save.
	var check := FileAccess.open(tmp_path, FileAccess.READ)
	if inject == "readback" and check != null:
		check.close()
		check = null
	if check == null:
		DirAccess.remove_absolute(_abs(tmp_path))
		return {"ok": false, "error": "无法回读临时存档"}
	var reread := check.get_as_text()
	check.close()
	if reread != text:
		DirAccess.remove_absolute(_abs(tmp_path))
		return {"ok": false, "error": "临时存档校验失败"}

	var had_old := FileAccess.file_exists(path)
	var bak_path := _bak_path(path)
	if had_old:
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(_abs(bak_path))
		var bak_err := DirAccess.rename_absolute(_abs(path), _abs(bak_path))
		if bak_err != OK:
			DirAccess.remove_absolute(_abs(tmp_path))
			return {"ok": false, "error": "旧存档备份失败（%s）" % error_string(bak_err)}

	var err := DirAccess.rename_absolute(_abs(tmp_path), _abs(path)) if inject != "rename" else ERR_CANT_CREATE
	if err != OK:
		DirAccess.remove_absolute(_abs(tmp_path))
		if had_old:
			DirAccess.rename_absolute(_abs(bak_path), _abs(path))
		return {"ok": false, "error": "存档替换失败（%s）" % error_string(err)}
	return {"ok": true, "error": "", "path": path, "version": VERSION}

## 主存档不可用时降级读 .bak。
## 第10轮修复：save_state 一直在写 .bak，但 load_state 从不读它——主档坏掉
## （写一半断电、校验失败）就等于存档直接丢失。这里补上恢复路径。
func load_state(path: String = SAVE_PATH) -> Dictionary:
	var primary := _load_one(path)
	if bool(primary.get("ok", false)):
		return primary
	var backup := _load_one(_bak_path(path))
	if bool(backup.get("ok", false)):
		backup["recovered"] = true
		backup["note"] = "主存档不可用（%s），已从 .bak 备份恢复" % str(primary.get("error", ""))
		return backup
	if bool(primary.get("missing", false)) and not bool(backup.get("missing", false)):
		# 主档不存在但备份在（上次改名中途断掉），用备份的内容但如实报告
		backup["recovered"] = true
		backup["note"] = "主存档缺失，已从 .bak 备份恢复"
		return backup
	return primary


func _load_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "尚无存档", "missing": true, "data": {}}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "无法读取存档", "data": {}}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "存档不是有效 JSON（第 %d 行）" % json.get_error_line(), "data": {}}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "存档不是有效 JSON 对象", "data": {}}
	var data: Dictionary = parsed
	var version_raw: Variant = data.get("version", null)
	if not _is_number(version_raw):
		return {"ok": false, "error": "存档版本字段缺失或类型错误", "data": {}}
	var version := int(version_raw)
	if float(version_raw) != float(version):
		return {"ok": false, "error": "存档版本字段类型错误", "data": {}}
	if version < MIN_VERSION or version > VERSION:
		var reason := "不支持的存档版本：%d" % version
		if version > VERSION:
			reason = "存档版本过新：%d（当前 %d）" % [version, VERSION]
		return {"ok": false, "error": reason, "data": {}, "version": version}
	var schema_error := _validate_schema(data)
	if schema_error != "":
		return {"ok": false, "error": schema_error, "data": {}, "version": version}
	return {"ok": true, "error": "", "data": data, "version": version}

func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

## Required: flags (bool values), quests.main / quests.side. Optional: player.
func _validate_schema(data: Dictionary) -> String:
	var flags: Variant = data.get("flags", null)
	if typeof(flags) != TYPE_DICTIONARY:
		return "存档 flags 字段缺失或类型错误"
	for key: String in flags:
		if typeof((flags as Dictionary)[key]) != TYPE_BOOL:
			return "存档标记 %s 不是布尔值" % key
	var quests: Variant = data.get("quests", null)
	if typeof(quests) != TYPE_DICTIONARY:
		return "存档 quests 字段缺失或类型错误"
	var main: Variant = (quests as Dictionary).get("main.zhouCommission", null)
	if typeof(main) != TYPE_STRING:
		return "存档主线任务字段缺失或类型错误"
	var side: Variant = (quests as Dictionary).get("side", null)
	if typeof(side) != TYPE_DICTIONARY:
		return "存档支线字段缺失或类型错误"
	var side_schema: Variant = (side as Dictionary).get("schemaVersion", null)
	if not _is_number(side_schema):
		return "存档支线 schemaVersion 类型错误"
	if typeof((side as Dictionary).get("state", null)) != TYPE_STRING:
		return "存档支线状态缺失或类型错误"
	if (side as Dictionary).has("rewardReceipt"):
		var receipt: Variant = (side as Dictionary)["rewardReceipt"]
		if receipt != null and typeof(receipt) != TYPE_STRING:
			return "存档支线回执类型错误"
	if (quests as Dictionary).has("main.ch2Herbs"):
		if typeof((quests as Dictionary)["main.ch2Herbs"]) != TYPE_STRING:
			return "存档第二章主线字段类型错误"
	if (quests as Dictionary).has("main.ch3Hermitage"):
		if typeof((quests as Dictionary)["main.ch3Hermitage"]) != TYPE_STRING:
			return "存档第三章主线字段类型错误"
	for ch2_side: String in ["side.ch2Spar", "side.ch2Tea", "side.ch3Debt", "side.ch3Herb"]:
		if not (quests as Dictionary).has(ch2_side):
			continue
		var block: Variant = (quests as Dictionary)[ch2_side]
		if typeof(block) != TYPE_DICTIONARY:
			return "存档 %s 字段类型错误" % ch2_side
		if not _is_number((block as Dictionary).get("schemaVersion", null)):
			return "存档 %s schemaVersion 类型错误" % ch2_side
		if typeof((block as Dictionary).get("state", null)) != TYPE_STRING:
			return "存档 %s 状态类型错误" % ch2_side
		if (block as Dictionary).has("rewardReceipt"):
			var ch2_receipt: Variant = (block as Dictionary)["rewardReceipt"]
			if ch2_receipt != null and typeof(ch2_receipt) != TYPE_STRING:
				return "存档 %s 回执类型错误" % ch2_side
	if data.has("player"):
		var player: Variant = data["player"]
		if typeof(player) != TYPE_DICTIONARY:
			return "存档 player 字段类型错误"
		for key: String in ["hp", "potions", "facing"]:
			if (player as Dictionary).has(key) and not _is_number((player as Dictionary)[key]):
				return "存档 player.%s 类型错误" % key
		if (player as Dictionary).has("position"):
			var pos: Variant = (player as Dictionary)["position"]
			if typeof(pos) != TYPE_ARRAY or (pos as Array).size() != 3:
				return "存档 player.position 类型错误"
			for v: Variant in pos:
				if not _is_number(v):
					return "存档 player.position 类型错误"
	return ""

func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

func has_backup(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(_bak_path(path))

## Restore the previous save over the live one. Returns false if there is no backup.
func restore_backup(path: String = SAVE_PATH) -> bool:
	var bak_path := _bak_path(path)
	if not FileAccess.file_exists(bak_path):
		return false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_abs(path))
	return DirAccess.rename_absolute(_abs(bak_path), _abs(path)) == OK

func delete_save(path: String = SAVE_PATH) -> bool:
	var ok := true
	for candidate: String in [path, _tmp_path(path), _bak_path(path)]:
		if FileAccess.file_exists(candidate):
			ok = DirAccess.remove_absolute(_abs(candidate)) == OK and ok
	return ok

func save_exists_info(path: String = SAVE_PATH) -> String:
	var res := load_state(path)
	if not res.ok:
		return ""
	return str(res.data.get("saved_at", ""))

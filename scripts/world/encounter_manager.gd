class_name EncounterManager
extends Node3D
## 区块机缘的点位与结算。
## - 只有区块被加载时结点可见；区块卸载不丢已用记录（记录在 EncounterDB）。
## - 每 24 游戏分钟整体刷新；legendary 每区同时最多 1 个。
## - 全部走主键交互，没有强制弹窗/切场景；拒绝、离开零惩罚。

signal encounter_used(record: Dictionary, result: Dictionary)

var world: Node
var player: Node3D
var regions: Array[Dictionary] = []
var _batches: Dictionary = {}          # region_id -> Array[Dictionary]
var _loaded: Dictionary = {}           # region_id -> true
var _refresh_acc := 0.0

func setup(world_ref: Node, player_ref: Node3D, region_list: Array[Dictionary]) -> void:
	world = world_ref
	player = player_ref
	regions = region_list

func _process(delta: float) -> void:
	_refresh_acc += delta
	if _refresh_acc < 0.5:
		return
	_refresh_acc = 0.0
	if EncounterDB.refresh_if_due(GameClock.game_minutes):
		_clear_batches()
		for region_id: String in _loaded:
			var region := _region(region_id)
			if not region.is_empty():
				_spawn_region(region)

func _region(region_id: String) -> Dictionary:
	for region: Dictionary in regions:
		if str(region.get("id", "")) == region_id:
			return region
	return {}

func on_region_loaded(region: Dictionary) -> void:
	var region_id := str(region.get("id", ""))
	_loaded[region_id] = true
	if not _batches.has(region_id):
		_spawn_region(region)
	for entry: Dictionary in _batches.get(region_id, []):
		var node := entry.get("node") as EncounterNode
		if node != null and is_instance_valid(node):
			node.visible = true
			node.set_process(true)
			if not node.is_in_group("interactable"):
				node.add_to_group("interactable")

func on_region_unloaded(region_id: String) -> void:
	_loaded.erase(region_id)
	for entry: Dictionary in _batches.get(region_id, []):
		var node := entry.get("node") as EncounterNode
		if node != null and is_instance_valid(node):
			node.visible = false
			node.set_process(false)
			node.set_prompt_visible(false)
			if node.is_in_group("interactable"):
				node.remove_from_group("interactable")

func _clear_batches() -> void:
	for region_id: String in _batches:
		for entry: Dictionary in _batches[region_id]:
			var node := entry.get("node") as EncounterNode
			if node != null and is_instance_valid(node):
				node.queue_free()
	_batches.clear()

func _spawn_region(region: Dictionary) -> void:
	var region_id := str(region.get("id", ""))
	var tags: Array = region.get("tags", [])
	var pois: Array = region.get("pois", [])
	if pois.is_empty():
		return
	var now := GameClock.game_minutes
	var cycle := int(now / EncounterDB.REFRESH_MINUTES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region_id) ^ (cycle * 7919) ^ 20261121
	var count := mini(pois.size(), 6 if str(region.get("feature", "")) != "wild" else 2)
	var chosen: Dictionary = {}
	var spawns: Array[Dictionary] = []
	for i in count:
		var record: Dictionary = {}
		for attempt in 12:
			var candidate := EncounterDB.pick_for_region(region_id, tags, now, rng)
			if candidate.is_empty():
				break
			var cid := str(candidate.get("id", ""))
			if chosen.has(cid):
				continue
			if not _trigger_ok(candidate):
				continue
			record = candidate
			chosen[cid] = true
			EncounterDB.mark_spawned(record, region_id)
			break
		if record.is_empty():
			continue
		var raw: Variant = pois[i % pois.size()]
		var poi := Vector2.ZERO
		if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
			poi = Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
		var px := poi.x + rng.randf_range(-2.6, 2.6)
		var pz := poi.y + rng.randf_range(-2.6, 2.6)
		var py := float(world.call("ground_height_at", px, pz))
		var node := EncounterNode.new()
		node.position = Vector3(px, py, pz)
		node.visible = _loaded.has(region_id)
		node.setup(record, region_id, player)
		add_child(node)
		spawns.append({"record": record, "node": node})
		if not _loaded.has(region_id):
			node.visible = false
			node.set_process(false)
			node.remove_from_group("interactable")
	_batches[region_id] = spawns

func _trigger_ok(record: Dictionary) -> bool:
	var trigger := str(record.get("trigger", "interact"))
	var value: Variant = record.get("trigger_value", "")
	match trigger:
		"time":
			return _matches(value, GameClock.time_of_day())
		"weather":
			return _matches(value, GameClock.weather)
		"flag":
			return GameState.is_flag_true(str(value))
	return true

func _matches(expected: Variant, actual: String) -> bool:
	if typeof(expected) == TYPE_ARRAY:
		return actual in (expected as Array)
	return str(expected) == actual

func interact(node: EncounterNode) -> Dictionary:
	if node == null or not is_instance_valid(node) or node.used:
		return {}
	var record := node.record
	var payload: Dictionary = record.get("payload", {})
	var rarity := str(record.get("rarity", "common"))
	var band := str(record.get("level_band", "1-10"))
	var understood := GameState.can_understand(band)
	var cultivation := clampi(int(payload.get("cultivation", 1)), 1, 3)
	if not understood:
		# 看不懂也能拿走一点东西；等级从不阻止交互，只是收益/描述不同。
		cultivation = 1
	var result := {
		"ok": true,
		"title": str(payload.get("title", "机缘")),
		"rarity": rarity,
		"kind": str(record.get("kind", "event")),
		"understood": understood,
		"cultivation": cultivation,
		"item": "",
		"item_count": 0,
		"text": str(payload.get("text", "")),
		"level_up": {},
	}
	var level_info := GameState.add_cultivation(cultivation)
	result["level_up"] = level_info
	var item := str(payload.get("item", ""))
	var item_count := int(payload.get("item_count", 0))
	if item != "" and item_count > 0:
		GameState.gain_item(item, item_count)
		result["item"] = item
		result["item_count"] = item_count
	var hp_delta := int(payload.get("hp_delta", 0))
	if hp_delta != 0:
		GameState.hp = clampi(GameState.hp + hp_delta, 1, GameState.MAX_HP)
		GameState.changed.emit()
	if rarity in ["rare", "legendary"]:
		GameState.add_reputation(1 if rarity == "rare" else 2)
	GameState.record_encounter(rarity)
	EncounterDB.mark_used(str(record.get("id", "")), node.region_id, GameClock.game_minutes)
	node.mark_used()
	_remove_from_batch(node)
	node.queue_free()
	encounter_used.emit(record, result)
	return result

func _remove_from_batch(node: EncounterNode) -> void:
	for region_id: String in _batches:
		var entries: Array = _batches[region_id]
		for i in range(entries.size() - 1, -1, -1):
			var entry: Dictionary = entries[i]
			if entry.get("node") == node:
				entries.remove_at(i)

func active_points() -> int:
	var total := 0
	for region_id: String in _batches:
		total += (_batches[region_id] as Array).size()
	return total

func batch(region_id: String) -> Array:
	return _batches.get(region_id, [])

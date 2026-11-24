extends Node
## NPC 模板池：姓氏字典 + 名字字典 + 身份/性格/立绘映射。
## 生成是确定性的：同一个 seed 总是得到同一批名字、身份、区块与站位。

const DATA_PATH := "res://data/npcs.json"
const REGIONS_PATH := "res://data/regions.json"

var data: Dictionary = {}
var surnames: Array = []
var given_names: Array = []
var identities: Array[Dictionary] = []
var personalities: Dictionary = {}
var portrait_fallbacks: Dictionary = {}
var regions: Array[Dictionary] = []
var load_error := ""

func _ready() -> void:
	reload()

func reload() -> bool:
	data = {}
	surnames = []
	given_names = []
	identities = []
	personalities = {}
	portrait_fallbacks = {}
	regions = []
	load_error = ""
	if not _load_json(DATA_PATH, "npcs"):
		return false
	surnames = data.get("surnames", [])
	given_names = data.get("givenNames", [])
	if surnames.size() < 8 or given_names.size() < 8:
		load_error = "name dictionaries too small"
		return false
	for entry: Variant in data.get("identities", []):
		if typeof(entry) == TYPE_DICTIONARY:
			identities.append(entry)
	if identities.size() < 3:
		load_error = "need >= 3 identities"
		return false
	for entry: Variant in data.get("personalities", []):
		if typeof(entry) == TYPE_DICTIONARY:
			personalities[str(entry.get("id", ""))] = entry
	if personalities.size() < 3:
		load_error = "need >= 3 personalities"
		return false
	portrait_fallbacks = data.get("portraitFallbacks", {})
	if not _load_json(REGIONS_PATH, "regions"):
		return false
	for entry: Variant in data_regions.get("regions", []):
		if typeof(entry) == TYPE_DICTIONARY:
			regions.append(entry)
	return true

## reload() 里复用 JSON 读取，避免两个路径各写一遍。
var data_regions: Dictionary = {}
func _load_json(path: String, label: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_error = "missing %s (%s)" % [path, label]
		return false
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		load_error = "%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
		f.close()
		return false
	f.close()
	if typeof(json.data) != TYPE_DICTIONARY:
		load_error = "%s is not an object" % path
		return false
	if label == "npcs":
		data = json.data
	else:
		data_regions = json.data
	return true

func identity_by_id(identity_id: String) -> Dictionary:
	for identity: Dictionary in identities:
		if str(identity.get("id", "")) == identity_id:
			return identity
	return {}

func region_by_id(region_id: String) -> Dictionary:
	for region: Dictionary in regions:
		if str(region.get("id", "")) == region_id:
			return region
	return {}

func personalities_count() -> int:
	return personalities.size()

func identities_count() -> int:
	return identities.size()

## count < 0 用数据文件里的 generation.count。
func generate(count: int = -1, seed_value: int = 0, placement_override: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if identities.is_empty() or regions.is_empty():
		return out
	var generation: Dictionary = data.get("generation", {})
	if count < 0:
		count = int(generation.get("count", 18))
	if seed_value == 0:
		seed_value = int(generation.get("seed", 20261121))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placement: Array = placement_override if not placement_override.is_empty() else data.get("placement", [])
	var slots := _region_slots(placement, count, rng)
	out = _build_npcs(count, slots, rng)
	return out

func _region_slots(placement: Array, count: int, rng: RandomNumberGenerator) -> Array[String]:
	var slots: Array[String] = []
	for entry: Variant in placement:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var region_id := str((entry as Dictionary).get("region", ""))
		if region_by_id(region_id).is_empty():
			continue
		var n := int((entry as Dictionary).get("count", 0))
		for i in maxi(0, n):
			slots.append(region_id)
	if slots.is_empty():
		for region: Dictionary in regions:
			slots.append(str(region.get("id", "")))
	for i in range(slots.size(), count):
		slots.append(str(regions[i % regions.size()].get("id", "")))
	_shuffle(slots, rng)
	return slots

func _build_npcs(count: int, slots: Array[String], rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var used_names: Dictionary = {}
	var identity_pool: Array[Dictionary] = []
	# 先保证每个身份至少出现一次，再用随机身份补足。
	var ids: Array[Dictionary] = identities.duplicate()
	_shuffle(ids, rng)
	for i in mini(count, ids.size()):
		identity_pool.append(ids[i])
	while identity_pool.size() < count:
		identity_pool.append(identities[rng.randi_range(0, identities.size() - 1)])
	_shuffle(identity_pool, rng)
	for i in count:
		var identity: Dictionary = identity_pool[i]
		var region_id: String = slots[i]
		var region := region_by_id(region_id)
		var pois: Array = region.get("pois", [])
		var poi: Array = [0.0, 0.0]
		if not pois.is_empty():
			var raw: Variant = pois[i % pois.size()]
			if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
				poi = raw
		var home := Vector2(
			float(poi[0]) + rng.randf_range(-3.2, 3.2),
			float(poi[1]) + rng.randf_range(-3.2, 3.2)
		)
		var display := _unique_name(used_names, rng)
		var voice := str(identity.get("voice", "plain"))
		var personality: Dictionary = personalities.get(voice, {})
		var sprite := str(identity.get("sprite", "shenyan"))
		# v2/v3 立绘不在本包内：generate 的散人一律用姓名牌（portrait==""），
		# portrait_fallbacks 仅作数据记录，避免把主角立绘错套到路人身上。
		var portrait := str(identity.get("portrait", ""))
		out.append({
			"id": "npc.gen.%s.%02d" % [region_id, i],
			"name": display,
			"identity": str(identity.get("id", "")),
			"identity_label": str(identity.get("label", "路人")),
			"personality": voice,
			"personality_label": str(personality.get("label", "寡言")),
			"sprite": sprite,
			"tint": str(identity.get("tint", "#ffffff")),
			"height_m": float(identity.get("height_m", 1.68)),
			"portrait": portrait,
			"region": region_id,
			"home": [home.x, home.y],
			"radius": rng.randf_range(2.4, 4.6),
			"greetings": (personality.get("greetings", []) as Array).duplicate(),
			"idle_lines": (personality.get("idle", []) as Array).duplicate()
		})
	return out

func _unique_name(used: Dictionary, rng: RandomNumberGenerator) -> String:
	for attempt in 80:
		var name := str(surnames[rng.randi_range(0, surnames.size() - 1)]) \
			+ str(given_names[rng.randi_range(0, given_names.size() - 1)])
		if not used.has(name):
			used[name] = true
			return name
	# 池子用尽时才允许重名，并加序号保证 id 仍唯一。
	var fallback := "%s%s·%d" % [
		surnames[rng.randi_range(0, surnames.size() - 1)],
		given_names[rng.randi_range(0, given_names.size() - 1)],
		used.size()
	]
	used[fallback] = true
	return fallback

func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func validate() -> Array[String]:
	var errors: Array[String] = []
	if surnames.size() < 8:
		errors.append("surnames < 8")
	if given_names.size() < 8:
		errors.append("givenNames < 8")
	if identities.size() < 3:
		errors.append("identities < 3")
	if personalities.size() < 3:
		errors.append("personalities < 3")
	for identity: Dictionary in identities:
		for key: String in ["id", "label", "sprite", "tint", "height_m", "voice"]:
			if not identity.has(key):
				errors.append("identity %s missing %s" % [identity.get("id", "?"), key])
	for p: String in personalities:
		var block: Dictionary = personalities[p]
		if (block.get("greetings", []) as Array).size() < 3:
			errors.append("personality %s greetings < 3" % p)
		if (block.get("idle", []) as Array).size() < 3:
			errors.append("personality %s idle < 3" % p)
	return errors

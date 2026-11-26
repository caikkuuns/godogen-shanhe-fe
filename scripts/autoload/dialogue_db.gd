extends Node
## Loads and validates docs/dialogue-v1.json (schemaVersion 1).

const DB_PATH := "res://data/dialogue-v1.json"
const DB_PATHS := [
	"res://data/dialogue-v1.json",
	"res://data/chapter2-dialogue.json",
	"res://data/chapter3-dialogue.json",
]
const PORTRAITS := {
	"shenyan": "res://assets/portraits/shenyan_portrait.png",
	"linzhaowan": "res://assets/portraits/linzhaowan_portrait.png",
	"mingcheng": "res://assets/portraits/mingcheng_portrait.png",
	"zhoubo": "res://assets/portraits/zhoubo_portrait.png",
	"liheng": "res://assets/portraits/liheng_portrait.png",
}

var db: Dictionary = {}
var nodes: Dictionary = {}
var dialogues: Dictionary = {}
var load_error := ""

func _ready() -> void:
	reload()

func _reset_state() -> void:
	db = {}
	nodes = {}
	dialogues = {}
	load_error = ""

func _clear_graph() -> void:
	db = {}
	nodes = {}
	dialogues = {}

func reload() -> bool:
	return load_from_files(DB_PATHS)

func load_from_files(paths: Array) -> bool:
	_reset_state()
	var docs: Array[Dictionary] = []
	for path: String in paths:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			load_error = "missing %s" % path
			_clear_graph()
			return false
		var text := f.get_as_text()
		f.close()
		var parsed := _parse_document(text, path)
		if parsed.is_empty():
			_clear_graph()
			return false
		docs.append(parsed)
	return _merge_documents(docs)

func load_from_path(path: String) -> bool:
	return load_from_files([path])

## Test/seam entry point; the live DB is restored by reload().
func load_from_text(text: String) -> bool:
	_reset_state()
	var data := _parse_document(text, "<inline>")
	if data.is_empty():
		_clear_graph()
		return false
	return _merge_documents([data])

func _parse_document(text: String, label: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		load_error = "%s: JSON parse error at line %d: %s" % [label, json.get_error_line(), json.get_error_message()]
		return {}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		load_error = "%s: JSON is not an object" % label
		return {}
	var data: Dictionary = parsed
	if int(data.get("schemaVersion", 0)) != 1:
		load_error = "%s: schemaVersion != 1" % label
		return {}
	if typeof(data.get("nodes")) != TYPE_ARRAY or typeof(data.get("dialogues")) != TYPE_ARRAY:
		load_error = "%s: nodes/dialogues missing" % label
		return {}
	return data

func _merge_documents(docs: Array) -> bool:
	var merged := {
		"schemaVersion": 1,
		"id": "shanhe.dialogue.merged",
		"contentVersion": "",
		"language": "zh-Hans",
		"speakers": {},
		"interactionPoints": {},
		"dialogues": [],
		"nodes": [],
		"states": {},
		"flagsRead": {},
		"effectTypes": {},
	}
	var seen_nodes: Dictionary = {}
	var seen_dialogues: Dictionary = {}
	var source_ids: Array[String] = []
	for i in docs.size():
		var data: Dictionary = docs[i]
		var source_id := str(data.get("id", "<doc%d>" % i))
		source_ids.append(source_id)
		if i == 0:
			merged["id"] = data.get("id", merged["id"])
			merged["contentVersion"] = data.get("contentVersion", "")
			merged["language"] = data.get("language", "zh-Hans")
		for key: String in ["speakers", "flagsRead", "effectTypes"]:
			var block: Variant = data.get(key, {})
			if typeof(block) == TYPE_DICTIONARY:
				for k: String in block:
					(merged[key] as Dictionary)[k] = block[k]
		var states: Variant = data.get("states", {})
		if typeof(states) == TYPE_DICTIONARY:
			for quest: String in states:
				if not (merged["states"] as Dictionary).has(quest):
					(merged["states"] as Dictionary)[quest] = []
				for value: Variant in states[quest]:
					if value not in (merged["states"] as Dictionary)[quest]:
						(merged["states"] as Dictionary)[quest].append(value)
		var points: Variant = data.get("interactionPoints", {})
		if typeof(points) == TYPE_DICTIONARY:
			for point: String in points:
				# Later files replace the whole point list (chapter2 merges v1 entries itself).
				(merged["interactionPoints"] as Dictionary)[point] = (points[point] as Dictionary).duplicate(true)
		for n: Variant in data.get("nodes", []):
			if typeof(n) != TYPE_DICTIONARY:
				continue
			var node_id := str(n.get("id", ""))
			if seen_nodes.has(node_id):
				load_error = "duplicate node id %s (in %s)" % [node_id, source_id]
				_clear_graph()
				return false
			seen_nodes[node_id] = source_id
			(merged["nodes"] as Array).append(n)
		for d: Variant in data.get("dialogues", []):
			if typeof(d) != TYPE_DICTIONARY:
				continue
			var dialogue_id := str(d.get("id", ""))
			if seen_dialogues.has(dialogue_id):
				load_error = "duplicate dialogue id %s (in %s)" % [dialogue_id, source_id]
				_clear_graph()
				return false
			seen_dialogues[dialogue_id] = source_id
			(merged["dialogues"] as Array).append(d)
	merged["sources"] = source_ids
	db = merged
	for n: Variant in db["nodes"]:
		nodes[str(n.get("id", ""))] = n
	for d: Variant in db["dialogues"]:
		dialogues[str(d.get("id", ""))] = d
	var errors := validate()
	if not errors.is_empty():
		load_error = "; ".join(errors)
		# Never leave a half-built graph behind after a failed validation.
		_clear_graph()
		return false
	return true

func get_node_data(node_id: String) -> Dictionary:
	var n: Variant = nodes.get(node_id, {})
	return n if typeof(n) == TYPE_DICTIONARY else {}

func get_dialogue(dialogue_id: String) -> Dictionary:
	var d: Variant = dialogues.get(dialogue_id, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}

func speaker_id(node: Dictionary) -> String:
	return str(node.get("speaker", "shenyan"))

func speaker_display_name(node: Dictionary) -> String:
	var override := str(node.get("nameOverride", ""))
	if override != "":
		return override
	var sid := speaker_id(node)
	var speakers: Dictionary = db.get("speakers", {})
	var speaker: Variant = speakers.get(sid, {})
	if typeof(speaker) == TYPE_DICTIONARY:
		return str(speaker.get("displayName", sid))
	return sid

func speaker_side(node: Dictionary) -> String:
	var sid := speaker_id(node)
	var speakers: Dictionary = db.get("speakers", {})
	var speaker: Variant = speakers.get(sid, {})
	if typeof(speaker) == TYPE_DICTIONARY:
		return str(speaker.get("panelSide", "left"))
	return "left"

func _portrait_entry(node: Dictionary) -> Dictionary:
	var sid := speaker_id(node)
	var expression := str(node.get("expression", "default"))
	var speakers: Dictionary = db.get("speakers", {})
	var speaker: Variant = speakers.get(sid, {})
	if typeof(speaker) == TYPE_DICTIONARY:
		var portraits: Variant = (speaker as Dictionary).get("portraits", {})
		if typeof(portraits) == TYPE_DICTIONARY:
			var entry: Variant = (portraits as Dictionary).get(expression)
			if typeof(entry) != TYPE_DICTIONARY:
				entry = (portraits as Dictionary).get("default")
			if typeof(entry) == TYPE_DICTIONARY:
				return entry
	return {}

## Logical portrait key (e.g. transition.fade_black) for the UI/transition layer.
func portrait_key(node: Dictionary) -> String:
	return str(_portrait_entry(node).get("key", ""))

func portrait_path(node: Dictionary) -> String:
	var sid := speaker_id(node)
	var entry := _portrait_entry(node)
	if not entry.is_empty():
		var res_path := str(entry.get("resPath", ""))
		if res_path != "" and ResourceLoader.exists(res_path):
			return res_path
	# Fallback table used while the data file still has null resPath values.
	var fallback := str(PORTRAITS.get(sid, ""))
	return fallback if fallback != "" and ResourceLoader.exists(fallback) else ""

## First dialogue at this point whose conditions are TRUE (unknown counts as false).
## Story-state merging runs first so conditions see locked/available/ready.
func pick_dialogue(point: String) -> Dictionary:
	GameState.normalize()
	var points: Dictionary = db.get("interactionPoints", {})
	var entry: Variant = points.get(point, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	var ids: Variant = entry.get("dialogues", [])
	if typeof(ids) != TYPE_ARRAY:
		return {}
	for dialogue_id: Variant in ids:
		var dlg := get_dialogue(str(dialogue_id))
		if dlg.is_empty():
			continue
		var conds: Array = dlg.get("conditions", [])
		if GameState.conditions_ok(conds):
			return dlg
	return {}

func validate() -> Array[String]:
	var errors: Array[String] = []
	if int(db.get("schemaVersion", 0)) != 1:
		errors.append("schemaVersion must be 1")
	var quest_ids: Dictionary = {}
	var states: Variant = db.get("states", {})
	if typeof(states) == TYPE_DICTIONARY:
		for quest_id: String in states:
			quest_ids[quest_id] = true
	var speaker_ids: Dictionary = {}
	var speakers: Variant = db.get("speakers", {})
	if typeof(speakers) == TYPE_DICTIONARY:
		for sid: String in speakers:
			speaker_ids[sid] = true

	var seen: Dictionary = {}
	for n: Variant in db.get("nodes", []):
		if typeof(n) != TYPE_DICTIONARY:
			errors.append("node is not an object")
			continue
		var node_id := str(n.get("id", ""))
		if node_id == "":
			errors.append("node with empty id")
			continue
		if seen.has(node_id):
			errors.append("duplicate node id %s" % node_id)
		seen[node_id] = true
		var sid := str(n.get("speaker", ""))
		if not speaker_ids.has(sid):
			errors.append("node %s unknown speaker %s" % [node_id, sid])
		if typeof(n.get("conditions", [])) != TYPE_ARRAY:
			errors.append("node %s conditions is not an array" % node_id)
		else:
			var idx := 0
			for cond: Variant in n.get("conditions", []):
				_validate_condition(cond, "node %s condition[%d]" % [node_id, idx], quest_ids, errors)
				idx += 1
		if n.has("choices"):
			if typeof(n["choices"]) != TYPE_ARRAY:
				errors.append("node %s choices is not an array" % node_id)
			else:
				for c: Variant in n["choices"]:
					if typeof(c) != TYPE_DICTIONARY:
						errors.append("node %s has malformed choice" % node_id)
						continue
					if typeof(c.get("conditions", [])) != TYPE_ARRAY:
						errors.append("node %s choice %s conditions is not an array" % [node_id, str(c.get("id", "?"))])
					else:
						var idx := 0
						for cond: Variant in c.get("conditions", []):
							_validate_condition(cond, "node %s choice %s condition[%d]" % [node_id, str(c.get("id", "?")), idx], quest_ids, errors)
							idx += 1

	var dialogue_ids: Dictionary = {}
	for d: Variant in db.get("dialogues", []):
		if typeof(d) != TYPE_DICTIONARY:
			errors.append("dialogue is not an object")
			continue
		var did := str(d.get("id", ""))
		if did == "":
			errors.append("dialogue with empty id")
			continue
		if dialogue_ids.has(did):
			errors.append("duplicate dialogue id %s" % did)
		dialogue_ids[did] = true
		if not nodes.has(str(d.get("entry", ""))):
			errors.append("dialogue %s entry missing" % did)
		if typeof(d.get("conditions", [])) != TYPE_ARRAY:
			errors.append("dialogue %s conditions is not an array" % did)
		else:
			var idx := 0
			for cond: Variant in d.get("conditions", []):
				_validate_condition(cond, "dialogue %s condition[%d]" % [did, idx], quest_ids, errors)
				idx += 1

	for node_id: String in nodes:
		var n: Dictionary = nodes[node_id]
		var did := str(n.get("dialogue", ""))
		if not dialogue_ids.has(did):
			errors.append("node %s points to unknown dialogue %s" % [node_id, did])
		var has_next := str(n.get("next", "")) != ""
		var has_choices := typeof(n.get("choices")) == TYPE_ARRAY and not (n["choices"] as Array).is_empty()
		var is_end: bool = n.get("end", false) == true
		var branches := int(has_next) + int(has_choices) + int(is_end)
		if branches != 1:
			errors.append("node %s must have exactly one of next/choices/end" % node_id)
		if has_next:
			if not nodes.has(str(n["next"])):
				errors.append("node %s next missing" % node_id)
			elif str(get_node_data(str(n["next"])).get("dialogue", "")) != did:
				errors.append("node %s next crosses dialogue boundary" % node_id)
		if has_choices:
			for c: Variant in n["choices"]:
				if typeof(c) != TYPE_DICTIONARY:
					continue
				var target := str(c.get("next", ""))
				if not nodes.has(target):
					errors.append("node %s choice next missing" % node_id)
				elif str(get_node_data(target).get("dialogue", "")) != did:
					errors.append("node %s choice next crosses dialogue boundary" % node_id)
		if not is_end:
			var flags: Variant = n.get("setFlags", {})
			var fx: Variant = n.get("effects", [])
			var has_flags := typeof(flags) == TYPE_DICTIONARY and not (flags as Dictionary).is_empty()
			var has_fx := typeof(fx) == TYPE_ARRAY and not (fx as Array).is_empty()
			if has_flags or has_fx:
				errors.append("node %s commits flags/effects before end" % node_id)
		var flags_node: Variant = n.get("setFlags", {})
		if typeof(flags_node) != TYPE_DICTIONARY:
			errors.append("node %s setFlags is not an object" % node_id)
		else:
			for k: String in flags_node:
				if not k.begins_with("dlg."):
					errors.append("node %s flag %s outside dlg.*" % [node_id, k])
		var fx_node: Variant = n.get("effects", [])
		if typeof(fx_node) != TYPE_ARRAY:
			errors.append("node %s effects is not an array" % node_id)
			continue
		for fx: Variant in fx_node:
			if typeof(fx) != TYPE_DICTIONARY:
				errors.append("node %s malformed effect" % node_id)
				continue
			var typ := str(fx.get("type", ""))
			if typ == "questEvent":
				var q := str(fx.get("quest", ""))
				if q == "" or str(fx.get("event", "")) == "":
					errors.append("node %s questEvent missing quest/event" % node_id)
				elif not quest_ids.has(q):
					errors.append("node %s questEvent unknown quest %s" % [node_id, q])
			elif typ == "startBattle":
				if str(fx.get("battleId", "")) == "":
					errors.append("node %s startBattle missing battleId" % node_id)
			else:
				errors.append("node %s unknown effect %s" % [node_id, typ])

	# Graph must be finite: no cycles and no unreachable entry nodes.
	for did: String in dialogue_ids:
		var entry := str(get_dialogue(did).get("entry", ""))
		if nodes.has(entry):
			_check_cycles(entry, {}, [], errors)
			_check_reachable(entry, did, errors)

	# Interaction points: valid dialogue refs; a final unconditional fallback except the
	# one-shot post-battle point, which deliberately has none.
	var points: Dictionary = db.get("interactionPoints", {})
	for point: String in points:
		var p: Variant = points[point]
		if typeof(p) != TYPE_DICTIONARY:
			errors.append("point %s malformed" % point)
			continue
		var ids: Variant = p.get("dialogues", [])
		if typeof(ids) != TYPE_ARRAY:
			errors.append("point %s has no dialogue list" % point)
			continue
		var point_seen: Dictionary = {}
		for did: Variant in ids:
			if not dialogue_ids.has(str(did)):
				errors.append("point %s references unknown dialogue %s" % [point, did])
			if point_seen.has(str(did)):
				errors.append("point %s lists dialogue %s twice" % [point, did])
			point_seen[str(did)] = true
		if not point.begins_with("battle_return."):
			if ids.is_empty():
				errors.append("point %s has no fallback" % point)
			else:
				var last := get_dialogue(str(ids[ids.size() - 1]))
				if typeof(last.get("conditions", [])) != TYPE_ARRAY or not (last.get("conditions", []) as Array).is_empty():
					errors.append("point %s last dialogue is not an unconditional fallback" % point)
	return errors

func _validate_condition(cond: Variant, where: String, quest_ids: Dictionary, errors: Array[String]) -> void:
	if typeof(cond) != TYPE_DICTIONARY:
		errors.append("%s is not an object" % where)
		return
	var c: Dictionary = cond
	if c.has("all") or c.has("any"):
		var key := "all" if c.has("all") else "any"
		if c.size() != 1:
			errors.append("%s mixes %s with other keys" % [where, key])
		var arr: Variant = c[key]
		if typeof(arr) != TYPE_ARRAY:
			errors.append("%s.%s is not an array" % [where, key])
			return
		var idx := 0
		for sub: Variant in arr:
			_validate_condition(sub, "%s.%s[%d]" % [where, key, idx], quest_ids, errors)
			idx += 1
		return
	if c.has("not"):
		if c.size() != 1:
			errors.append("%s.not mixed with other keys" % where)
		_validate_condition(c["not"], where + ".not", quest_ids, errors)
		return
	if c.has("quest"):
		for k: String in c:
			if k not in ["quest", "equals", "in"]:
				errors.append("%s has unknown quest key %s" % [where, k])
		var q := str(c.get("quest", ""))
		if not quest_ids.has(q):
			errors.append("%s references unknown quest %s" % [where, q])
		if not c.has("equals") and not c.has("in"):
			errors.append("%s quest condition lacks equals/in" % where)
		if c.has("equals") and typeof(c["equals"]) != TYPE_STRING:
			errors.append("%s quest equals is not a string" % where)
		if c.has("in"):
			var opts: Variant = c["in"]
			if typeof(opts) != TYPE_ARRAY or (opts as Array).is_empty():
				errors.append("%s quest in is not a non-empty array" % where)
			else:
				for v: Variant in opts:
					if typeof(v) != TYPE_STRING:
						errors.append("%s quest in contains non-string" % where)
		return
	if c.has("flag"):
		for k: String in c:
			if k not in ["flag", "equals"]:
				errors.append("%s has unknown flag key %s" % [where, k])
		if str(c.get("flag", "")) == "":
			errors.append("%s flag name is empty" % where)
		if not c.has("equals"):
			errors.append("%s flag condition lacks equals" % where)
		return
	errors.append("%s is not a known condition" % where)

func _check_cycles(node_id: String, state: Dictionary, stack: Array[String], errors: Array[String]) -> bool:
	if int(state.get(node_id, 0)) == 1:
		errors.append("dialogue cycle at %s" % node_id)
		return true
	if int(state.get(node_id, 0)) == 2:
		return false
	state[node_id] = 1
	stack.append(node_id)
	var n := get_node_data(node_id)
	var targets: Array[String] = []
	if str(n.get("next", "")) != "":
		targets.append(str(n["next"]))
	if typeof(n.get("choices")) == TYPE_ARRAY:
		for c: Variant in n["choices"]:
			if typeof(c) == TYPE_DICTIONARY:
				targets.append(str(c.get("next", "")))
	for target: String in targets:
		if nodes.has(target) and _check_cycles(target, state, stack, errors):
			return true
	stack.pop_back()
	state[node_id] = 2
	return false

func _check_reachable(entry: String, did: String, errors: Array[String]) -> void:
	var queue: Array[String] = [entry]
	var walked: Dictionary = {}
	while not queue.is_empty():
		var node_id: String = queue.pop_front()
		if walked.has(node_id):
			continue
		walked[node_id] = true
		var n := get_node_data(node_id)
		if str(n.get("dialogue", "")) != did:
			errors.append("dialogue %s reaches node %s of %s" % [did, node_id, str(n.get("dialogue", "?"))])
			continue
		var targets: Array[String] = []
		if str(n.get("next", "")) != "":
			targets.append(str(n["next"]))
		if typeof(n.get("choices")) == TYPE_ARRAY:
			for c: Variant in n["choices"]:
				if typeof(c) == TYPE_DICTIONARY:
					targets.append(str(c.get("next", "")))
		for target: String in targets:
			if nodes.has(target) and not walked.has(target):
				queue.append(target)

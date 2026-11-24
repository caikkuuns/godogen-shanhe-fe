extends Node
## Persistent game state: flags, quest states, player resources, save snapshot.
## Story-data state machine lives here so dialogue only emits events.

signal changed
signal toast_requested(text: String)
signal reward_granted(text: String)

enum Tri { FALSE, TRUE, UNKNOWN }

const MAIN_QUEST := "main.zhouCommission"
const SIDE_QUEST := "side.bambooCompanions"
const SIDE_RECEIPT := "bambooCompanions.v1.promise"

const CH2_MAIN := "main.ch2Herbs"
const CH2_SPAR := "side.ch2Spar"
const CH2_TEA := "side.ch2Tea"
const CH2_SPAR_RECEIPT := "ch2Spar.v1.reward"
const CH2_TEA_RECEIPT := "ch2Tea.v1.reward"
const CH3_MAIN := "main.ch3Hermitage"
const CH3_DEBT := "side.ch3Debt"
const CH3_HERB := "side.ch3Herb"
const CH3_DEBT_RECEIPT := "ch3Debt.v1.reward"
const CH3_HERB_RECEIPT := "ch3Herb.v1.reward"

const MAX_HP := 100
const ATTACK := 12
const DEFENSE := 4
const MAX_QI := 30
const START_QI := 20
const START_POTIONS := 2

const MAIN_STATES: Array[String] = ["notAccepted", "accepted", "delivered", "unknown"]
const SIDE_STATES: Array[String] = [
	"locked", "available", "accepted", "girlMet", "bothMet", "ready",
	"completed", "legacyClosed", "disabled",
]
const CH2_MAIN_STATES: Array[String] = [
	"locked", "available", "accepted", "toldByLiheng", "stationCleared", "completed", "unknown",
]
const CH2_SPAR_STATES: Array[String] = ["locked", "available", "completed", "disabled"]
const CH2_TEA_STATES: Array[String] = [
	"locked", "available", "accepted", "told", "completed", "disabled",
]
const CH3_MAIN_STATES: Array[String] = [
	"locked", "available", "accepted", "stairCleared", "gateHeld", "completed", "unknown",
]
const CH3_DEBT_STATES: Array[String] = [
	"locked", "available", "accepted", "delivered", "completed", "disabled",
]
const CH3_HERB_STATES: Array[String] = ["locked", "available", "completed", "disabled"]

var flags: Dictionary = {}
var main_state := "notAccepted"
var side_state := "locked"
var side_receipt: Variant = null
var side_schema := 1

var ch2_main_state := "locked"
var ch2_spar_state := "locked"
var ch2_spar_receipt: Variant = null
var ch2_spar_schema := 1
var ch2_tea_state := "locked"
var ch2_tea_receipt: Variant = null
var ch2_tea_schema := 1
var ch3_main_state := "locked"
var ch3_debt_state := "locked"
var ch3_debt_receipt: Variant = null
var ch3_debt_schema := 1
var ch3_herb_state := "locked"
var ch3_herb_receipt: Variant = null
var ch3_herb_schema := 1

var hp := MAX_HP
var potions := START_POTIONS
var player_position := Vector3(0.0, 0.0, 18.0)
var player_facing := 0

## —— 开放世界成长（本轮新增；旧存档缺字段时按新游戏默认值迁移）——
## 修为只由机缘给 1~3 点；等级 1→20，等级只决定“看不看得懂”机缘，不锁探索。
const GROWTH_PATH := "res://data/growth.json"
var cultivation := 0
var level := 1
var inventory: Dictionary = {}
var reputation := 0
var talk_counts: Dictionary = {}
## 近处机缘状态（隐藏分支条件用；运行时记录，不锁任何东西）。
var encounter_rarities_used: Array[String] = []
var growth_levels: Array[Dictionary] = []
var growth_bands: Array[Dictionary] = []
## Scene-owned flag: while true, save_game() refuses to write mid-battle state.
var in_battle := false
## Reward settlement is only durable after save_game() succeeds (DQ-05).
var _settlement_snapshot: Variant = null
var _pending_rewards: Array[Dictionary] = []

func _ready() -> void:
	_load_growth()
	_setup_input()
	reset_new_game()

func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"interact": [KEY_E, KEY_SPACE, KEY_ENTER],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.15)
		else:
			InputMap.action_erase_events(action)
		for code: int in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)

# ---------------------------------------------------------------- growth / inventory

func _load_growth() -> void:
	growth_levels = []
	growth_bands = []
	var f := FileAccess.open(GROWTH_PATH, FileAccess.READ)
	if f == null:
		push_warning("growth data missing: " + GROWTH_PATH)
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		push_warning("growth data parse error: " + json.get_error_message())
		f.close()
		return
	f.close()
	if typeof(json.data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = json.data
	for entry: Variant in d.get("levels", []):
		if typeof(entry) == TYPE_DICTIONARY:
			growth_levels.append(entry)
	for entry: Variant in d.get("levelBands", []):
		if typeof(entry) == TYPE_DICTIONARY:
			growth_bands.append(entry)
	if growth_levels.is_empty():
		push_warning("growth data has no levels")

func max_level() -> int:
	return growth_levels.size() if not growth_levels.is_empty() else 20

func xp_to_next(lv: int) -> int:
	for entry: Dictionary in growth_levels:
		if int(entry.get("level", 0)) == lv:
			return int(entry.get("xpToNext", 0))
	return 0

func realm_name(lv: int = -1) -> String:
	if lv < 0:
		lv = level
	for entry: Dictionary in growth_levels:
		if int(entry.get("level", 0)) == lv:
			return str(entry.get("realm", "引气"))
	return "引气"

func level_band_for_level(lv: int = -1) -> String:
	if lv < 0:
		lv = level
	if lv <= 10:
		return "1-10"
	if lv <= 20:
		return "11-20"
	return "21-30"

## 单次机缘 1~3 点；满级后不再累积。
func add_cultivation(points: int) -> Dictionary:
	var gained := clampi(points, 0, 3)
	var levels_gained := 0
	if level >= max_level():
		cultivation = 0
		return {"gained": 0, "levels_gained": 0, "level": level, "realm": realm_name()}
	cultivation += gained
	while level < max_level():
		var need := xp_to_next(level)
		if need <= 0 or cultivation < need:
			break
		cultivation -= need
		level += 1
		levels_gained += 1
	if level >= max_level():
		cultivation = 0
	changed.emit()
	return {
		"gained": gained, "levels_gained": levels_gained,
		"level": level, "realm": realm_name(),
	}

func gain_item(item_id: String, amount: int = 1) -> void:
	if item_id == "" or amount <= 0:
		return
	inventory[item_id] = int(inventory.get(item_id, 0)) + amount
	changed.emit()

func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))

func has_item(item_id: String) -> bool:
	return item_count(item_id) > 0

func add_reputation(amount: int) -> void:
	reputation = maxi(0, reputation + amount)
	changed.emit()

func record_talk(npc_id: String) -> void:
	if npc_id == "":
		return
	talk_counts[npc_id] = int(talk_counts.get(npc_id, 0)) + 1
	changed.emit()

func talk_count(npc_id: String) -> int:
	return int(talk_counts.get(npc_id, 0))

func total_talks() -> int:
	var total := 0
	for key: String in talk_counts:
		total += int(talk_counts[key])
	return total

func record_encounter(rarity: String) -> void:
	if rarity != "":
		encounter_rarities_used.append(rarity)
		changed.emit()

func has_used_encounter_rarity(rarity: String) -> bool:
	return rarity in encounter_rarities_used

func has_used_any_encounter() -> bool:
	return not encounter_rarities_used.is_empty()

## 隐藏分支命中后唯一的持久化动作：写 dlg.hidden.* flag。
## 不改任何 quest 状态，也不解锁/锁定后续内容。
func set_hidden_flag(flag_name: String) -> bool:
	if not flag_name.begins_with("dlg.hidden."):
		push_warning("hidden flag must start with dlg.hidden.: " + flag_name)
		return false
	if flags.get(flag_name, false) != true:
		flags[flag_name] = true
		changed.emit()
	return true

## 机缘强度：等级只决定“看得懂/应付得来”，从不阻止交互。
func can_understand(band_id: String) -> bool:
	var mine := level_band_for_level()
	if mine == "1-10":
		return band_id == "1-10"
	if mine == "11-20":
		return band_id in ["1-10", "11-20"]
	return true

func default_flags() -> Dictionary:
	return {
		"battle.liheng.won": false,
		"dlg.liheng.postSeen": false,
		"battle.ch2_thug.won": false,
		"battle.ch2_gesancheng.won": false,
		"battle.ch2_liheng_spar.won": false,
		"dlg.ch2.thugPostSeen": false,
		"dlg.ch2.gesanchengPostSeen": false,
		"dlg.ch2.sparPostSeen": false,
		"dlg.ch2.lihengVouched": false,
		"battle.ch3_stair.won": false,
		"battle.ch3_chutie.won": false,
		"battle.ch3_herb_thief.won": false,
		"dlg.ch3.sendoffSeen": false,
		"dlg.ch3.stairPostSeen": false,
		"dlg.ch3.chutiePostSeen": false,
		"dlg.ch3.herbPostSeen": false,
	}

func _reset_ch3() -> void:
	ch3_main_state = "locked"
	ch3_debt_state = "locked"
	ch3_debt_receipt = null
	ch3_debt_schema = 1
	ch3_herb_state = "locked"
	ch3_herb_receipt = null
	ch3_herb_schema = 1

func reset_new_game() -> void:
	flags = default_flags()
	main_state = "notAccepted"
	side_state = "locked"
	side_receipt = null
	side_schema = 1
	ch2_main_state = "locked"
	ch2_spar_state = "locked"
	ch2_spar_receipt = null
	ch2_spar_schema = 1
	ch2_tea_state = "locked"
	ch2_tea_receipt = null
	ch2_tea_schema = 1
	_reset_ch3()
	_unknown_fields = {}
	hp = MAX_HP
	potions = START_POTIONS
	player_position = Vector3(0.0, 0.0, 18.0)
	player_facing = 0
	cultivation = 0
	level = 1
	inventory = {}
	reputation = 0
	talk_counts = {}
	encounter_rarities_used = []
	in_battle = false
	_settlement_snapshot = null
	_pending_rewards.clear()
	changed.emit()

# ---------------------------------------------------------------- flags / quests

func get_flag(name: String) -> Variant:
	return flags.get(name, null)

func is_flag_true(name: String) -> bool:
	return flags.get(name, false) == true

func commit_dialogue_flags(pending: Dictionary) -> void:
	var dirty := false
	for key: String in pending:
		if not key.begins_with("dlg."):
			push_warning("dialogue tried to set non-dlg flag: %s" % key)
			continue
		if flags.get(key, null) != pending[key]:
			flags[key] = pending[key]
			dirty = true
	if dirty:
		changed.emit()

func mark_battle_won(battle_id: String = "liheng") -> bool:
	var key := "battle.%s.won" % battle_id
	if is_flag_true(key):
		return false
	flags[key] = true
	changed.emit()
	return true

func battle_return_point(battle_id: String) -> String:
	return "battle_return.%s_victory" % battle_id

## Scene-facing battle exit: victory persists the flag + a normal save; defeat/
## retreat exits the in-battle state and deliberately writes nothing.
func leave_battle(battle_id: String, victory: bool, path: String = SaveManager.SAVE_PATH) -> Dictionary:
	in_battle = false
	if not victory:
		return {
			"ok": true, "saved": false, "newly_won": false,
			"return_point": "", "error": "",
		}
	var newly_won := mark_battle_won(battle_id)
	var saved := save_game(path)
	var saved_ok := bool(saved.get("ok", false))
	return {
		"ok": saved_ok,
		"saved": saved_ok,
		"newly_won": newly_won,
		"return_point": battle_return_point(battle_id),
		"save": saved,
		"error": str(saved.get("error", "")),
	}

## Scene-facing NPC visibility. The scene hides/shows the NPC node from this
## query; the dialogue DB keeps every point queryable (safe fallback).
## Every NPC interaction point is listed explicitly; an unlisted point is
## NOT visible (safe default: a typo or unknown id never spawns a duplicate NPC).
const VISIBILITY_POINTS: Array[String] = [
	"village.zhoubo", "village.mingcheng", "bamboo.liheng", "bamboo.linzhaowan",
	"gate.liheng", "gate.linzhaowan", "yiting.gesancheng", "yiting.linzhaowan",
	"stair.dashou", "stair.linzhaowan", "hermitage.chutie", "hermitage.linzhaowan",
	"hermitage.wensu",
]

## Single current location of 林照晚 / 厉横; deriving each NPC's point from one
## function makes "one place at a time" hold even for inconsistent saves.
func linzhaowan_point() -> String:
	if ch2_main_state == "completed":
		match ch3_main_state:
			"accepted":
				return "stair.linzhaowan"
			"stairCleared", "gateHeld", "completed":
				return "hermitage.linzhaowan"
		# ch3 locked / available / unknown: she waits at the gate (M1 / ch2 epilogue).
		return "gate.linzhaowan"
	match ch2_main_state:
		"accepted":
			return "gate.linzhaowan"
		"toldByLiheng", "stationCleared":
			# She leaves with 沈砚 for the station (ch2_lt_09 / ch2_sp_02).
			return "yiting.linzhaowan"
	return "bamboo.linzhaowan"

func liheng_point() -> String:
	if ch2_main_state in ["accepted", "toldByLiheng", "stationCleared", "completed"]:
		return "gate.liheng"
	if not is_flag_true("battle.liheng.won"):
		return "bamboo.liheng"
	return ""

func is_point_visible(point: String) -> bool:
	# Chapter-3 places only exist once chapter 2 is completed.
	var ch3_live := ch2_main_state == "completed"
	match point:
		"village.zhoubo", "village.mingcheng":
			return true
		"bamboo.linzhaowan", "gate.linzhaowan", "yiting.linzhaowan", "stair.linzhaowan", "hermitage.linzhaowan":
			return linzhaowan_point() == point
		"bamboo.liheng", "gate.liheng":
			return liheng_point() == point
		"yiting.gesancheng":
			return ch2_main_state == "toldByLiheng" and not is_flag_true("battle.ch2_gesancheng.won")
		"stair.dashou":
			return ch3_live and ch3_main_state == "accepted"
		"hermitage.chutie":
			return ch3_live and ch3_main_state == "stairCleared" and not is_flag_true("battle.ch3_chutie.won")
		"hermitage.wensu":
			return ch3_live and ch3_main_state in ["gateHeld", "completed"]
	push_warning("is_point_visible: unlisted point %s -> hidden" % point)
	return false

## Every NPC-bearing point, grouped by character, for scenes and tests.
const NPC_POINTS := {
	"linzhaowan": ["bamboo.linzhaowan", "gate.linzhaowan", "yiting.linzhaowan", "stair.linzhaowan", "hermitage.linzhaowan"],
	"liheng": ["bamboo.liheng", "gate.liheng"],
	"zhoubo": ["village.zhoubo"],
	"mingcheng": ["village.mingcheng"],
	"gesancheng": ["yiting.gesancheng"],
	"stair_dashou": ["stair.dashou"],
	"chutie": ["hermitage.chutie"],
	"wensu": ["hermitage.wensu"],
}

func get_quest_state(quest: String) -> String:
	if quest == MAIN_QUEST:
		return main_state if main_state in MAIN_STATES else "unknown"
	if quest == SIDE_QUEST:
		if side_schema != 1:
			return "disabled"
		return side_state if side_state in SIDE_STATES else "disabled"
	if quest == CH2_MAIN:
		# A corrupt/unreadable chapter-1 main makes chapter 2 unreadable too.
		if main_state == "unknown":
			return "unknown"
		return ch2_main_state if ch2_main_state in CH2_MAIN_STATES else "unknown"
	if quest == CH2_SPAR:
		if ch2_spar_schema != 1:
			return "disabled"
		return ch2_spar_state if ch2_spar_state in CH2_SPAR_STATES else "disabled"
	if quest == CH2_TEA:
		if ch2_tea_schema != 1:
			return "disabled"
		return ch2_tea_state if ch2_tea_state in CH2_TEA_STATES else "disabled"
	if quest == CH3_MAIN:
		# Unreadable chapter 2 makes chapter 3 unreadable too.
		if get_quest_state(CH2_MAIN) == "unknown":
			return "unknown"
		return ch3_main_state if ch3_main_state in CH3_MAIN_STATES else "unknown"
	if quest == CH3_DEBT:
		if ch3_debt_schema != 1:
			return "disabled"
		return ch3_debt_state if ch3_debt_state in CH3_DEBT_STATES else "disabled"
	if quest == CH3_HERB:
		if ch3_herb_schema != 1:
			return "disabled"
		return ch3_herb_state if ch3_herb_state in CH3_HERB_STATES else "disabled"
	return "unknown"

func normalize() -> void:
	var dirty := false
	if not (main_state in MAIN_STATES):
		main_state = "unknown"
		dirty = true
	if side_schema == 1:
		if not (side_state in SIDE_STATES):
			side_state = "disabled"
			dirty = true
		if main_state == "delivered":
			if side_state in ["locked", "available"]:
				side_state = "legacyClosed"
				dirty = true
			elif side_state == "bothMet":
				side_state = "ready"
				dirty = true
		elif main_state == "accepted" and side_state == "locked":
			side_state = "available"
			dirty = true
	elif side_state != "disabled":
		side_state = "disabled"
		dirty = true

	if not (ch2_main_state in CH2_MAIN_STATES):
		ch2_main_state = "unknown"
		dirty = true
	if ch2_spar_schema != 1:
		if ch2_spar_state != "disabled":
			ch2_spar_state = "disabled"
			dirty = true
	elif not (ch2_spar_state in CH2_SPAR_STATES):
		ch2_spar_state = "disabled"
		dirty = true
	if ch2_tea_schema != 1:
		if ch2_tea_state != "disabled":
			ch2_tea_state = "disabled"
			dirty = true
	elif not (ch2_tea_state in CH2_TEA_STATES):
		ch2_tea_state = "disabled"
		dirty = true

	if main_state == "delivered" and ch2_main_state == "locked":
		ch2_main_state = "available"
		dirty = true
	if ch2_main_state in ["toldByLiheng", "stationCleared", "completed"]:
		if ch2_spar_state == "locked":
			ch2_spar_state = "available"
			dirty = true
		if ch2_tea_state == "locked":
			ch2_tea_state = "available"
			dirty = true

	if not (ch3_main_state in CH3_MAIN_STATES):
		ch3_main_state = "unknown"
		dirty = true
	if ch3_debt_schema != 1:
		if ch3_debt_state != "disabled":
			ch3_debt_state = "disabled"
			dirty = true
	elif not (ch3_debt_state in CH3_DEBT_STATES):
		ch3_debt_state = "disabled"
		dirty = true
	if ch3_herb_schema != 1:
		if ch3_herb_state != "disabled":
			ch3_herb_state = "disabled"
			dirty = true
	elif not (ch3_herb_state in CH3_HERB_STATES):
		ch3_herb_state = "disabled"
		dirty = true
	if ch2_main_state == "completed" and ch3_main_state == "locked":
		ch3_main_state = "available"
		dirty = true
	if ch3_main_state in ["gateHeld", "completed"]:
		if ch3_debt_state == "locked":
			ch3_debt_state = "available"
			dirty = true
		if ch3_herb_state == "locked":
			ch3_herb_state = "available"
			dirty = true
	if dirty:
		changed.emit()

func _quest_snapshot() -> Dictionary:
	return {
		"main_state": main_state,
		"side_state": side_state,
		"side_receipt": side_receipt,
		"side_schema": side_schema,
		"ch2_main_state": ch2_main_state,
		"ch2_spar_state": ch2_spar_state,
		"ch2_spar_receipt": ch2_spar_receipt,
		"ch2_spar_schema": ch2_spar_schema,
		"ch2_tea_state": ch2_tea_state,
		"ch2_tea_receipt": ch2_tea_receipt,
		"ch2_tea_schema": ch2_tea_schema,
		"ch3_main_state": ch3_main_state,
		"ch3_debt_state": ch3_debt_state,
		"ch3_debt_receipt": ch3_debt_receipt,
		"ch3_debt_schema": ch3_debt_schema,
		"ch3_herb_state": ch3_herb_state,
		"ch3_herb_receipt": ch3_herb_receipt,
		"ch3_herb_schema": ch3_herb_schema,
	}

func _capture_settlement() -> void:
	if _settlement_snapshot == null:
		_settlement_snapshot = _quest_snapshot()

func has_pending_settlement() -> bool:
	return _settlement_snapshot != null

func pending_rewards() -> Array[Dictionary]:
	return _pending_rewards.duplicate(true)

## Explicit rollback, used by save_game() on failure and available to the scene.
func rollback_pending_settlement() -> bool:
	if _settlement_snapshot == null:
		return false
	var snap: Dictionary = _settlement_snapshot
	main_state = str(snap["main_state"])
	side_state = str(snap["side_state"])
	side_receipt = snap["side_receipt"]
	side_schema = int(snap["side_schema"])
	ch2_main_state = str(snap["ch2_main_state"])
	ch2_spar_state = str(snap["ch2_spar_state"])
	ch2_spar_receipt = snap["ch2_spar_receipt"]
	ch2_spar_schema = int(snap["ch2_spar_schema"])
	ch2_tea_state = str(snap["ch2_tea_state"])
	ch2_tea_receipt = snap["ch2_tea_receipt"]
	ch2_tea_schema = int(snap["ch2_tea_schema"])
	ch3_main_state = str(snap["ch3_main_state"])
	ch3_debt_state = str(snap["ch3_debt_state"])
	ch3_debt_receipt = snap["ch3_debt_receipt"]
	ch3_debt_schema = int(snap["ch3_debt_schema"])
	ch3_herb_state = str(snap["ch3_herb_state"])
	ch3_herb_receipt = snap["ch3_herb_receipt"]
	ch3_herb_schema = int(snap["ch3_herb_schema"])
	_settlement_snapshot = null
	_pending_rewards.clear()
	changed.emit()
	return true

func dispatch_quest_event(quest: String, event: String) -> Dictionary:
	var result := {"applied": false, "reward": false, "message": ""}
	if quest == MAIN_QUEST:
		if event == "accept" and main_state == "notAccepted":
			main_state = "accepted"
			normalize()
			result.applied = true
		elif event == "deliver" and main_state == "accepted" and is_flag_true("battle.liheng.won"):
			main_state = "delivered"
			normalize()
			result.applied = true
	elif quest == SIDE_QUEST:
		if event == "talkZhou":
			if side_state == "available" and main_state == "accepted":
				side_state = "accepted"
				result.applied = true
			elif side_state == "ready" and main_state == "delivered" and is_flag_true("battle.liheng.won") and side_receipt == null:
				_capture_settlement()
				side_state = "completed"
				side_receipt = SIDE_RECEIPT
				result.applied = true
				result.reward = true
				result.message = "同行之约"
				_pending_rewards.append({"quest": quest, "event": event, "message": "同行之约"})
				reward_granted.emit("同行之约")
		elif event == "talkGirl" and side_state == "accepted" and main_state in ["accepted", "delivered"]:
			side_state = "girlMet"
			result.applied = true
		elif event == "talkMonk" and side_state == "girlMet":
			side_state = "bothMet"
			normalize()
			result.applied = true
	elif quest == CH2_MAIN:
		if event == "accept" and ch2_main_state == "available":
			ch2_main_state = "accepted"
			normalize()
			result.applied = true
		elif event == "hearLiheng" and ch2_main_state == "accepted" and is_flag_true("battle.ch2_thug.won"):
			ch2_main_state = "toldByLiheng"
			normalize()
			result.applied = true
		elif event == "recoverPack" and ch2_main_state == "toldByLiheng" and is_flag_true("battle.ch2_gesancheng.won"):
			ch2_main_state = "stationCleared"
			normalize()
			result.applied = true
		elif event == "finish" and ch2_main_state == "stationCleared":
			ch2_main_state = "completed"
			normalize()
			result.applied = true
	elif quest == CH2_SPAR:
		if event == "settle" and ch2_spar_state == "available" \
				and is_flag_true("battle.ch2_liheng_spar.won") and ch2_spar_receipt == null:
			_capture_settlement()
			ch2_spar_state = "completed"
			ch2_spar_receipt = CH2_SPAR_RECEIPT
			result.applied = true
			result.reward = true
			result.message = "再领一刀"
			_pending_rewards.append({"quest": quest, "event": event, "message": "再领一刀"})
			reward_granted.emit("再领一刀")
	elif quest == CH2_TEA:
		if event == "talkMonk":
			if ch2_tea_state == "available":
				ch2_tea_state = "accepted"
				result.applied = true
			elif ch2_tea_state == "told" and ch2_tea_receipt == null:
				_capture_settlement()
				ch2_tea_state = "completed"
				ch2_tea_receipt = CH2_TEA_RECEIPT
				result.applied = true
				result.reward = true
				result.message = "一碗粗茶"
				_pending_rewards.append({"quest": quest, "event": event, "message": "一碗粗茶"})
				reward_granted.emit("一碗粗茶")
		elif event == "talkLiheng" and ch2_tea_state == "accepted":
			ch2_tea_state = "told"
			result.applied = true
	elif quest == CH3_MAIN:
		if event == "accept" and ch3_main_state == "available":
			ch3_main_state = "accepted"
			result.applied = true
		elif event == "clearStair" and ch3_main_state == "accepted" and is_flag_true("battle.ch3_stair.won"):
			ch3_main_state = "stairCleared"
			result.applied = true
		elif event == "holdGate" and ch3_main_state == "stairCleared" and is_flag_true("battle.ch3_chutie.won"):
			ch3_main_state = "gateHeld"
			normalize()  # unlock side.ch3Debt / side.ch3Herb right away
			result.applied = true
		elif event == "finish" and ch3_main_state == "gateHeld":
			ch3_main_state = "completed"
			result.applied = true
	elif quest == CH3_DEBT:
		if event == "talkLiheng":
			if ch3_debt_state == "available":
				ch3_debt_state = "accepted"
				result.applied = true
			elif ch3_debt_state == "delivered" and ch3_debt_receipt == null:
				_capture_settlement()
				ch3_debt_state = "completed"
				ch3_debt_receipt = CH3_DEBT_RECEIPT
				result.applied = true
				result.reward = true
				result.message = "另一半账"
				_pending_rewards.append({"quest": quest, "event": event, "message": "另一半账"})
				reward_granted.emit("另一半账")
		elif event == "talkWensu" and ch3_debt_state == "accepted":
			ch3_debt_state = "delivered"
			result.applied = true
	elif quest == CH3_HERB:
		if event == "settle" and ch3_herb_state == "available" \
				and is_flag_true("battle.ch3_herb_thief.won") and ch3_herb_receipt == null:
			_capture_settlement()
			ch3_herb_state = "completed"
			ch3_herb_receipt = CH3_HERB_RECEIPT
			result.applied = true
			result.reward = true
			result.message = "雪见草"
			_pending_rewards.append({"quest": quest, "event": event, "message": "雪见草"})
			reward_granted.emit("雪见草")
	if result.applied:
		changed.emit()
	return result

func quest_lines() -> Array[String]:
	var lines: Array[String] = []
	match main_state:
		"notAccepted":
			lines.append("周伯在村口等你")
		"accepted":
			if is_flag_true("battle.liheng.won"):
				lines.append("主线 · 回村口向周伯复命")
			else:
				lines.append("主线 · 前往竹林，赶走厉横")
		"delivered":
			lines.append("主线 · 已向周伯复命")
		_:
			lines.append("主线 · 情况不明")
	match side_state:
		"available":
			lines.append("支线 · 村口周伯有话说")
		"accepted":
			lines.append("支线 · 去竹林见背剑姑娘")
		"girlMet":
			lines.append("支线 · 回村口找僧人明澄")
		"bothMet":
			lines.append("支线 · 回村口找周伯")
		"ready":
			lines.append("支线 · 去村口赴约")
		"completed":
			lines.append("支线 · 同行之约")
		"legacyClosed":
			lines.append("支线 · 旧事已结")
		"disabled":
			lines.append("支线 · 暂不可用")
	match ch2_main_state:
		"available":
			lines.append("第二章 · 去村口听周伯说山门的事")
		"accepted":
			if is_flag_true("battle.ch2_thug.won"):
				lines.append("第二章 · 回山门听厉横说明")
			else:
				lines.append("第二章 · 前往山门")
		"toldByLiheng":
			if is_flag_true("battle.ch2_gesancheng.won"):
				lines.append("第二章 · 去旧驿亭取回药包")
			else:
				lines.append("第二章 · 去旧驿亭找葛三秤")
		"stationCleared":
			lines.append("第二章 · 回山门收束")
		"completed":
			lines.append("第二章 · 药包已夺回")
		"unknown":
			lines.append("第二章 · 情况不明")
	match ch2_spar_state:
		"available":
			lines.append("支线 · 山门找厉横切磋")
		"completed":
			lines.append("支线 · 再领一刀")
		"disabled":
			lines.append("支线 · 切磋暂不可用")
	match ch2_tea_state:
		"available":
			lines.append("支线 · 明澄有事托付")
		"accepted":
			lines.append("支线 · 去山门给厉横捎话")
		"told":
			lines.append("支线 · 回村口回复明澄")
		"completed":
			lines.append("支线 · 一碗粗茶")
		"disabled":
			lines.append("支线 · 捎话暂不可用")
	match ch3_main_state:
		"available":
			lines.append("第三章 · 去山门找林照晚")
		"accepted":
			if is_flag_true("battle.ch3_stair.won"):
				lines.append("第三章 · 石阶上的打手有话说")
			else:
				lines.append("第三章 · 沿后山石阶上山")
		"stairCleared":
			if is_flag_true("battle.ch3_chutie.won"):
				lines.append("第三章 · 回庵门找林照晚")
			else:
				lines.append("第三章 · 守住清溪庵门")
		"gateHeld":
			lines.append("第三章 · 进庵见闻素")
		"completed":
			lines.append("第三章 · 清溪守门")
		"unknown":
			lines.append("第三章 · 情况不明")
	match ch3_debt_state:
		"available":
			lines.append("支线 · 山门厉横有事相托")
		"accepted":
			lines.append("支线 · 把铜钱送给闻素")
		"delivered":
			lines.append("支线 · 回山门告诉厉横")
		"completed":
			lines.append("支线 · 另一半账")
		"disabled":
			lines.append("支线 · 送钱暂不可用")
	match ch3_herb_state:
		"available":
			lines.append("支线 · 庵里林照晚说药圃出事了")
		"completed":
			lines.append("支线 · 雪见草")
		"disabled":
			lines.append("支线 · 药圃暂不可用")
	return lines

# ---------------------------------------------------------------- conditions

func eval_condition(cond: Dictionary) -> int:
	if cond.has("all"):
		var val: Variant = cond["all"]
		if typeof(val) != TYPE_ARRAY:
			push_error("bad condition: all")
			return Tri.UNKNOWN
		var result := Tri.TRUE
		for sub: Variant in val:
			if typeof(sub) != TYPE_DICTIONARY:
				push_error("bad condition inside all: %s" % [sub])
				result = Tri.UNKNOWN
				continue
			var v := eval_condition(sub)
			if v == Tri.FALSE:
				return Tri.FALSE
			if v == Tri.UNKNOWN:
				result = Tri.UNKNOWN
		return result
	if cond.has("any"):
		var val: Variant = cond["any"]
		if typeof(val) != TYPE_ARRAY:
			push_error("bad condition: any")
			return Tri.UNKNOWN
		var result := Tri.FALSE
		for sub: Variant in val:
			if typeof(sub) != TYPE_DICTIONARY:
				push_error("bad condition inside any: %s" % [sub])
				result = Tri.UNKNOWN
				continue
			var v := eval_condition(sub)
			if v == Tri.TRUE:
				return Tri.TRUE
			if v == Tri.UNKNOWN:
				result = Tri.UNKNOWN
		return result
	if cond.has("not"):
		var sub: Variant = cond["not"]
		if typeof(sub) != TYPE_DICTIONARY:
			push_error("bad condition inside not: %s" % [sub])
			return Tri.UNKNOWN
		var v := eval_condition(sub)
		if v == Tri.UNKNOWN:
			return Tri.UNKNOWN
		return Tri.TRUE if v == Tri.FALSE else Tri.FALSE
	if cond.has("quest"):
		var state := get_quest_state(str(cond["quest"]))
		if state in ["unknown", "disabled"]:
			return Tri.UNKNOWN
		if cond.has("equals"):
			return Tri.TRUE if state == str(cond["equals"]) else Tri.FALSE
		if cond.has("in"):
			var opts: Variant = cond["in"]
			if typeof(opts) == TYPE_ARRAY and state in opts:
				return Tri.TRUE
			return Tri.FALSE
		return Tri.UNKNOWN
	if cond.has("flag") and cond.has("equals"):
		var actual: Variant = get_flag(str(cond["flag"]))
		return Tri.TRUE if actual == cond["equals"] else Tri.FALSE
	push_error("bad condition dictionary: %s" % JSON.stringify(cond))
	# Unknown forms behave like an unreadable state: never truthy, even under not().
	return Tri.UNKNOWN

func conditions_ok(conds: Array) -> bool:
	return eval_condition({"all": conds}) == Tri.TRUE

# ---------------------------------------------------------------- serialization

## Unknown save fields (from newer builds / tools) kept verbatim so a
## load -> save round-trip never silently drops data. Known fields always win.
const KNOWN_TOP_KEYS: Array[String] = ["flags", "quests", "player", "version", "saved_at"]
const KNOWN_QUEST_KEYS: Array[String] = [
	MAIN_QUEST, "side", CH2_MAIN, CH2_SPAR, CH2_TEA, CH3_MAIN, CH3_DEBT, CH3_HERB,
]
const QUEST_BLOCK_KEYS: Array[String] = ["side", CH2_SPAR, CH2_TEA, CH3_DEBT, CH3_HERB]
const KNOWN_BLOCK_FIELDS: Array[String] = ["schemaVersion", "state", "rewardReceipt"]
const KNOWN_PLAYER_KEYS: Array[String] = [
	"hp", "potions", "position", "facing",
	"cultivation", "level", "inventory", "reputation", "talk_counts",
]
var _unknown_fields: Dictionary = {}

func _collect_unknown(data: Dictionary) -> Dictionary:
	var out := {"top": {}, "quests": {}, "blocks": {}, "player": {}}
	for key: Variant in data:
		if not (str(key) in KNOWN_TOP_KEYS):
			(out.top as Dictionary)[key] = _deep(data[key])
	var quests: Variant = data.get("quests", null)
	if typeof(quests) == TYPE_DICTIONARY:
		for key: Variant in quests:
			if not (str(key) in KNOWN_QUEST_KEYS):
				(out.quests as Dictionary)[key] = _deep((quests as Dictionary)[key])
		for qk: String in QUEST_BLOCK_KEYS:
			var block: Variant = (quests as Dictionary).get(qk, null)
			if typeof(block) == TYPE_DICTIONARY:
				var extra := {}
				for key: Variant in block:
					if not (str(key) in KNOWN_BLOCK_FIELDS):
						extra[key] = _deep((block as Dictionary)[key])
				if not extra.is_empty():
					(out.blocks as Dictionary)[qk] = extra
	var player: Variant = data.get("player", null)
	if typeof(player) == TYPE_DICTIONARY:
		for key: Variant in player:
			if not (str(key) in KNOWN_PLAYER_KEYS):
				(out.player as Dictionary)[key] = _deep((player as Dictionary)[key])
	return out

func _deep(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
		return v.duplicate(true)
	return v

## Godot's JSON parser reads every number as float; write integral values of
## preserved unknown fields back as ints so "3" stays "3" (not "3.0").
func _restore_ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and f == floorf(f) and absf(f) <= 9007199254740992.0:
				return int(f)
			return f
		TYPE_ARRAY:
			var arr: Array = []
			for item: Variant in v:
				arr.append(_restore_ints(item))
			return arr
		TYPE_DICTIONARY:
			var d := {}
			for key: Variant in v:
				d[key] = _restore_ints((v as Dictionary)[key])
			return d
	return v

func unknown_fields() -> Dictionary:
	return _unknown_fields.duplicate(true)

func to_dict() -> Dictionary:
	var out := _known_dict()
	if _unknown_fields.is_empty():
		return out
	for key: Variant in _unknown_fields.get("top", {}):
		if not out.has(key):
			out[key] = _restore_ints(_unknown_fields.top[key])
	var quests: Dictionary = out["quests"]
	for key: Variant in _unknown_fields.get("quests", {}):
		if not quests.has(key):
			quests[key] = _restore_ints(_unknown_fields.quests[key])
	for qk: Variant in _unknown_fields.get("blocks", {}):
		var block: Variant = quests.get(qk, null)
		if typeof(block) == TYPE_DICTIONARY:
			for key: Variant in _unknown_fields.blocks[qk]:
				if not (block as Dictionary).has(key):
					(block as Dictionary)[key] = _restore_ints(_unknown_fields.blocks[qk][key])
	var player: Dictionary = out["player"]
	for key: Variant in _unknown_fields.get("player", {}):
		if not player.has(key):
			player[key] = _restore_ints(_unknown_fields.player[key])
	return out

func _known_dict() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"quests": {
			MAIN_QUEST: main_state,
			"side": {
				"schemaVersion": side_schema,
				"state": side_state,
				"rewardReceipt": side_receipt,
			},
			CH2_MAIN: ch2_main_state,
			CH2_SPAR: {
				"schemaVersion": ch2_spar_schema,
				"state": ch2_spar_state,
				"rewardReceipt": ch2_spar_receipt,
			},
			CH2_TEA: {
				"schemaVersion": ch2_tea_schema,
				"state": ch2_tea_state,
				"rewardReceipt": ch2_tea_receipt,
			},
			CH3_MAIN: ch3_main_state,
			CH3_DEBT: {
				"schemaVersion": ch3_debt_schema,
				"state": ch3_debt_state,
				"rewardReceipt": ch3_debt_receipt,
			},
			CH3_HERB: {
				"schemaVersion": ch3_herb_schema,
				"state": ch3_herb_state,
				"rewardReceipt": ch3_herb_receipt,
			},
		},
		"player": {
			"hp": hp,
			"potions": potions,
			"position": [player_position.x, player_position.y, player_position.z],
			"facing": player_facing,
			"cultivation": cultivation,
			"level": level,
			"inventory": inventory.duplicate(true),
			"reputation": reputation,
			"talk_counts": talk_counts.duplicate(true),
		},
	}

func _number_or(value: Variant, fallback: float) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return fallback

func apply_dict(data: Dictionary) -> bool:
	var ok := true
	# Loading replaces the whole state; any unsaved reward settlement is moot.
	_settlement_snapshot = null
	_pending_rewards.clear()
	_unknown_fields = _collect_unknown(data)
	# Start from defaults so flags added/removed between builds do not go stale.
	flags = default_flags()
	var flags_in: Variant = data.get("flags", null)
	if typeof(flags_in) == TYPE_DICTIONARY:
		for key: String in flags_in:
			if typeof((flags_in as Dictionary)[key]) == TYPE_BOOL:
				flags[key] = (flags_in as Dictionary)[key]
			else:
				ok = false
	else:
		ok = false
	# Chapter 2 defaults also cover v1 saves that predate these blocks.
	ch2_main_state = "locked"
	ch2_spar_state = "locked"
	ch2_spar_receipt = null
	ch2_spar_schema = 1
	ch2_tea_state = "locked"
	ch2_tea_receipt = null
	ch2_tea_schema = 1
	# Chapter 3 defaults cover v1/v2 saves (migration: blocks simply absent).
	_reset_ch3()
	var quests: Variant = data.get("quests", null)
	if typeof(quests) == TYPE_DICTIONARY:
		var main_value: Variant = (quests as Dictionary).get(MAIN_QUEST, "unknown")
		main_state = str(main_value) if typeof(main_value) == TYPE_STRING else "unknown"
		if typeof(main_value) != TYPE_STRING:
			ok = false
		var side: Variant = (quests as Dictionary).get("side", {})
		if typeof(side) == TYPE_DICTIONARY:
			side_schema = int(_number_or((side as Dictionary).get("schemaVersion", 1), 1))
			var side_value: Variant = (side as Dictionary).get("state", "locked")
			side_state = str(side_value) if typeof(side_value) == TYPE_STRING else "disabled"
			if typeof(side_value) != TYPE_STRING:
				ok = false
			side_receipt = (side as Dictionary).get("rewardReceipt", null)
			if side_receipt != null and typeof(side_receipt) != TYPE_STRING:
				side_receipt = null
				ok = false
		else:
			side_schema = -1
			ok = false
		var ch2_main: Variant = (quests as Dictionary).get(CH2_MAIN, null)
		if ch2_main != null:
			if typeof(ch2_main) == TYPE_STRING:
				ch2_main_state = str(ch2_main)
			else:
				ch2_main_state = "unknown"
				ok = false
		var ch3_main: Variant = (quests as Dictionary).get(CH3_MAIN, null)
		if ch3_main != null:
			if typeof(ch3_main) == TYPE_STRING:
				ch3_main_state = str(ch3_main)
			else:
				ch3_main_state = "unknown"
				ok = false
		for pair: Array in [[CH2_SPAR, "spar"], [CH2_TEA, "tea"], [CH3_DEBT, "debt"], [CH3_HERB, "herb"]]:
			var block: Variant = (quests as Dictionary).get(str(pair[0]), null)
			if block == null:
				continue
			if typeof(block) != TYPE_DICTIONARY:
				ok = false
				continue
			var schema := int(_number_or((block as Dictionary).get("schemaVersion", 1), 1))
			var state_value: Variant = (block as Dictionary).get("state", "locked")
			var state_str := str(state_value) if typeof(state_value) == TYPE_STRING else "disabled"
			var receipt: Variant = (block as Dictionary).get("rewardReceipt", null)
			if typeof(state_value) != TYPE_STRING or (receipt != null and typeof(receipt) != TYPE_STRING):
				ok = false
				receipt = null
			if pair[1] == "spar":
				ch2_spar_schema = schema
				ch2_spar_state = state_str
				ch2_spar_receipt = receipt
			elif pair[1] == "debt":
				ch3_debt_schema = schema
				ch3_debt_state = state_str
				ch3_debt_receipt = receipt
			elif pair[1] == "herb":
				ch3_herb_schema = schema
				ch3_herb_state = state_str
				ch3_herb_receipt = receipt
			else:
				ch2_tea_schema = schema
				ch2_tea_state = state_str
				ch2_tea_receipt = receipt
	else:
		main_state = "unknown"
		side_schema = -1
		ok = false
	# Missing player fields fall back to new-game defaults, never to stale session values.
	hp = MAX_HP
	potions = START_POTIONS
	player_position = Vector3(0.0, 0.0, 18.0)
	player_facing = 0
	cultivation = 0
	level = 1
	inventory = {}
	reputation = 0
	talk_counts = {}
	encounter_rarities_used = []
	var player: Variant = data.get("player", null)
	if typeof(player) == TYPE_DICTIONARY:
		var pd: Dictionary = player
		# Wrong-typed fields are reported (apply_dict returns false + warning)
		# instead of being silently replaced by defaults.
		for key: String in ["hp", "potions", "facing"]:
			if pd.has(key) and not (typeof(pd[key]) in [TYPE_INT, TYPE_FLOAT]):
				push_warning("apply_dict: player.%s has wrong type (%s); using default" % [key, type_string(typeof(pd[key]))])
				ok = false
		if pd.has("position"):
			var pv: Variant = pd["position"]
			var pos_ok := typeof(pv) == TYPE_ARRAY and (pv as Array).size() >= 3
			if pos_ok:
				for i in 3:
					if not (typeof((pv as Array)[i]) in [TYPE_INT, TYPE_FLOAT]):
						pos_ok = false
			if not pos_ok:
				push_warning("apply_dict: player.position has wrong type; using default")
				ok = false
		hp = clampi(int(_number_or(pd.get("hp", MAX_HP), MAX_HP)), 0, MAX_HP)
		potions = clampi(int(_number_or(pd.get("potions", START_POTIONS), START_POTIONS)), 0, 99)
		var pos: Variant = pd.get("position", null)
		if typeof(pos) == TYPE_ARRAY and (pos as Array).size() >= 3:
			player_position = Vector3(
				_number_or((pos as Array)[0], 0.0),
				_number_or((pos as Array)[1], 0.0),
				_number_or((pos as Array)[2], 18.0),
			)
		player_facing = wrapi(int(_number_or(pd.get("facing", 0), 0.0)), 0, 8)
		# 成长/行囊字段：旧存档没有就保持新游戏默认值，不报错。
		if pd.has("cultivation"):
			if typeof(pd["cultivation"]) in [TYPE_INT, TYPE_FLOAT]:
				cultivation = maxi(0, int(_number_or(pd["cultivation"], 0.0)))
			else:
				ok = false
		if pd.has("level"):
			if typeof(pd["level"]) in [TYPE_INT, TYPE_FLOAT]:
				level = clampi(int(_number_or(pd["level"], 1.0)), 1, max_level())
			else:
				ok = false
		if pd.has("inventory"):
			if typeof(pd["inventory"]) == TYPE_DICTIONARY:
				for item_id: String in pd["inventory"]:
					var amount: Variant = (pd["inventory"] as Dictionary)[item_id]
					if typeof(amount) in [TYPE_INT, TYPE_FLOAT] and int(amount) > 0:
						inventory[item_id] = int(amount)
					else:
						ok = false
			else:
				ok = false
		if pd.has("reputation"):
			if typeof(pd["reputation"]) in [TYPE_INT, TYPE_FLOAT]:
				reputation = maxi(0, int(_number_or(pd["reputation"], 0.0)))
			else:
				ok = false
		if pd.has("talk_counts"):
			if typeof(pd["talk_counts"]) == TYPE_DICTIONARY:
				for npc_id: String in pd["talk_counts"]:
					var count: Variant = (pd["talk_counts"] as Dictionary)[npc_id]
					if typeof(count) in [TYPE_INT, TYPE_FLOAT] and int(count) > 0:
						talk_counts[npc_id] = int(count)
					else:
						ok = false
			else:
				ok = false
	elif player != null:
		ok = false
	in_battle = false
	normalize()
	changed.emit()
	return ok

func set_in_battle(active: bool) -> void:
	in_battle = active

func save_game(path: String = SaveManager.SAVE_PATH) -> Dictionary:
	if in_battle:
		SaveManager.test_fail_stage = ""  # blocked saves also disarm the test hook
		return {"ok": false, "error": "战斗中不能存档", "blocked": true}
	var res: Dictionary = SaveManager.save_state(to_dict(), path)
	if res.get("ok", false):
		# Reward receipt + state are now durable: commit the settlement.
		_settlement_snapshot = null
		_pending_rewards.clear()
	else:
		# DQ-05: no durable save means no reward; restore pre-settlement quests.
		res["rolled_back"] = rollback_pending_settlement()
	return res

func load_game(path: String = SaveManager.SAVE_PATH) -> Dictionary:
	var res: Dictionary = SaveManager.load_state(path)
	if res.get("ok", false):
		apply_dict(res.get("data", {}))
		return res
	normalize()
	return res

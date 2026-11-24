extends SceneTree
## Headless acceptance tests for backend cases:
##   godot --headless -s tests/run_tests.gd
## Each automated case prints exactly one `ok <ID> ...` / `FAIL <ID> ...` line.
## Exit code is 0 only when every case passes.

const BattleData = preload("res://scripts/battle/battle_data.gd")
const DIALOGUE_RUNNER_PATH := "res://scripts/dialogue/dialogue_runner.gd"
const SAVE_TMP := "user://run_tests_save.json"
const SAVE_BAT := "user://run_tests_battle.json"
const SAVE_002 := "user://run_tests_coldstart.json"
const SAVE_FLOW := "user://run_tests_flow.json"
const SAVE_002_TOKEN := "--sav002-child"

var gs: Variant
var db: Variant
var sm: Variant

var _passed: Array[String] = []
var _failed: Array[String] = []
var _case_id := ""
var _case_desc := ""
var _case_details: Array[String] = []

# Captured from DialogueRunner signals during run_dialogue().
var _dlg_finished := false
var _dlg_cancelled := false
var _dlg_effects: Array = []
var _dlg_rewards := 0
var _dlg_battles: Array[String] = []
var _dlg_order: Array[String] = []

class FakePanel extends DialoguePanel:
	var lines: Array[String] = []
	var speakers: Array[String] = []
	var node_ids: Array[String] = []
	var choice_sets: Array = []
	var choice_plan: Array = []
	var cancel_at_line := -1

	func show_line(node: Dictionary, speaker_name: String, text: String, portrait_path: String, side: String) -> void:
		node_ids.append(str(node.get("id", "")))
		lines.append(text)
		speakers.append(speaker_name)
		if cancel_at_line >= 0 and lines.size() > cancel_at_line:
			cancel_requested.emit()
		call_deferred("_emit_line_done")

	func show_choices(options: Array) -> void:
		choice_sets.append(options.duplicate())
		var index := 0
		if not choice_plan.is_empty():
			index = int(choice_plan.pop_front())
		call_deferred("_emit_choice", index)

	func hide_dialogue() -> void:
		pass

	func _emit_line_done() -> void:
		line_done.emit()

	func _emit_choice(index: int) -> void:
		choice_selected.emit(index)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has(SAVE_002_TOKEN):
		_run_sav002_child.call_deferred()
	else:
		_run.call_deferred()

# ------------------------------------------------------------------ case DSL

func begin_case(id: String, desc: String) -> void:
	_case_id = id
	_case_desc = desc
	_case_details = []

func expect(cond: bool, detail: String) -> void:
	if not cond:
		_case_details.append(detail)

func end_case() -> void:
	if _case_details.is_empty():
		print("ok   %s %s" % [_case_id, _case_desc])
		_passed.append(_case_id)
	else:
		print("FAIL %s %s" % [_case_id, _case_desc])
		for detail: String in _case_details:
			print("     - %s" % detail)
		_failed.append(_case_id)

# ------------------------------------------------------------------ helpers

func reset_state(main: String, side: String, won: Variant = null, post: Variant = null) -> void:
	gs.reset_new_game()
	gs.main_state = main
	gs.side_state = side
	gs.side_schema = 1
	gs.side_receipt = null
	if won == null:
		gs.flags.erase("battle.liheng.won")
	else:
		gs.flags["battle.liheng.won"] = won
	if post == null:
		gs.flags.erase("dlg.liheng.postSeen")
	else:
		gs.flags["dlg.liheng.postSeen"] = post

func pick_id(point: String) -> String:
	return str(db.pick_dialogue(point).get("id", ""))

func dlg_conditions(id: String) -> Array:
	return db.get_dialogue(id).get("conditions", [])

func node(id: String) -> Dictionary:
	return db.get_node_data(id)

func quest_effect(run: Dictionary, quest: String, event: String) -> bool:
	for effect: Variant in run.effects:
		if typeof(effect) == TYPE_DICTIONARY and str(effect.get("type", "")) == "questEvent":
			if str(effect.get("quest", "")) == quest and str(effect.get("event", "")) == event:
				return true
	return false

func battle_effect(run: Dictionary, battle_id: String) -> bool:
	for effect: Variant in run.effects:
		if typeof(effect) == TYPE_DICTIONARY and str(effect.get("type", "")) == "startBattle":
			if str(effect.get("battleId", "")) == battle_id:
				return true
	return false

func has_type(run: Dictionary, typ: String) -> bool:
	for effect: Variant in run.effects:
		if typeof(effect) == TYPE_DICTIONARY and str(effect.get("type", "")) == typ:
			return true
	return false

func choice_ids(id: String) -> Array[String]:
	var out: Array[String] = []
	for c: Variant in node(id).get("choices", []):
		if typeof(c) == TYPE_DICTIONARY:
			out.append(str(c.get("id", "")))
	return out

func choice_texts(id: String) -> Array[String]:
	var out: Array[String] = []
	for c: Variant in node(id).get("choices", []):
		if typeof(c) == TYPE_DICTIONARY:
			out.append(str(c.get("text", "")))
	return out

func flags_only_allowed() -> bool:
	var defaults: Dictionary = gs.default_flags()
	for key: String in gs.flags:
		if not defaults.has(key):
			return false
	return true

## Keep chapter-2 offers out of chapter-1 acceptance scenarios.
func suppress_ch2() -> void:
	gs.ch2_main_state = "unknown"

func add_temp_dialogue(id: String, entry: String, node_list: Array) -> Dictionary:
	var dlg := {"id": id, "entry": entry, "conditions": [], "replayable": true}
	db.dialogues[id] = dlg
	for n: Dictionary in node_list:
		db.nodes[str(n.get("id", ""))] = n
	return dlg

func remove_temp_dialogue(id: String, node_list: Array) -> void:
	db.dialogues.erase(id)
	for n: Dictionary in node_list:
		db.nodes.erase(str(n.get("id", "")))

func run_dialogue(dialogue: Dictionary, plan: Array = [], cancel_at := -1) -> Dictionary:
	_dlg_finished = false
	_dlg_cancelled = false
	_dlg_effects = []
	_dlg_rewards = 0
	_dlg_battles = []
	_dlg_order = []
	var panel := FakePanel.new()
	panel.choice_plan = plan.duplicate()
	panel.cancel_at_line = cancel_at
	var runner_script: Script = load(DIALOGUE_RUNNER_PATH)
	var runner: Node = runner_script.new()
	root.add_child(runner)
	runner.bind(panel)
	runner.finished.connect(func(effects: Array, cancelled: bool, rewards: int) -> void:
		_dlg_finished = true
		_dlg_cancelled = cancelled
		_dlg_effects = effects
		_dlg_rewards = rewards
		_dlg_order.append("finished")
	)
	runner.battle_requested.connect(func(battle_id: String) -> void:
		_dlg_battles.append(battle_id)
		_dlg_order.append("battle")
	)
	runner.start(dialogue)
	var frames := 0
	while runner.is_active() and frames < 1000:
		await process_frame
		frames += 1
	var result := {
		"lines": panel.lines.duplicate(),
		"speakers": panel.speakers.duplicate(),
		"node_ids": panel.node_ids.duplicate(),
		"choices": panel.choice_sets.duplicate(),
		"cancelled": _dlg_cancelled,
		"effects": _dlg_effects.duplicate(true),
		"rewards": _dlg_rewards,
		"battles": _dlg_battles.duplicate(),
		"order": _dlg_order.duplicate(),
		"finished": _dlg_finished,
		"timed_out": frames >= 1000,
	}
	root.remove_child(runner)
	runner.free()
	panel.free()
	return result

func write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func read_raw(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(read_raw(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func write_json(path: String, data: Dictionary) -> void:
	write_raw(path, JSON.stringify(data, "\t"))

func sample_save(path: String) -> void:
	reset_state("accepted", "girlMet", true, true)
	gs.flags["dlg.liheng.postSeen"] = false
	gs.hp = 77
	gs.potions = 1
	gs.player_position = Vector3(1.5, -2.0, 3.25)
	gs.player_facing = 3
	gs.save_game(path)

func cleanup_saves() -> void:
	for path: String in [SAVE_TMP, SAVE_BAT, SAVE_002, SAVE_FLOW]:
		sm.delete_save(path)

# ------------------------------------------------------------------ runner

func _run() -> void:
	gs = root.get_node("GameState")
	db = root.get_node("DialogueDB")
	sm = root.get_node("SaveManager")
	cleanup_saves()

	print("\n== dialogue (DLG) ==")
	for fn: Callable in [
		_DLG_001, _DLG_002, _DLG_003, _DLG_004, _DLG_005, _DLG_006,
		_DLG_007, _DLG_008, _DLG_009, _DLG_010, _DLG_011,
	]:
		await fn.call()
	for fn: Callable in [
		_DLG_020, _DLG_021, _DLG_022, _DLG_023, _DLG_024, _DLG_025,
		_DLG_026, _DLG_027, _DLG_028, _DLG_029, _DLG_030, _DLG_031,
		_DLG_032, _DLG_033, _DLG_034, _DLG_035, _DLG_036, _DLG_037,
		_DLG_038, _DLG_039, _DLG_040, _DLG_041,
	]:
		await fn.call()
	for fn: Callable in [
		_DLG_050, _DLG_051, _DLG_052, _DLG_053, _DLG_054, _DLG_055,
		_DLG_056, _DLG_057, _DLG_058,
	]:
		await fn.call()
	for fn: Callable in [
		_DLG_060, _DLG_061, _DLG_062, _DLG_063, _DLG_064, _DLG_065,
		_DLG_066, _DLG_067, _DLG_068,
	]:
		await fn.call()
	for fn: Callable in [
		_DLG_080, _DLG_081, _DLG_082, _DLG_083, _DLG_084, _DLG_085,
		_DLG_086, _DLG_087,
	]:
		await fn.call()
	for fn: Callable in [_DLG_090, _DLG_091, _DLG_092, _DLG_093, _DLG_094]:
		await fn.call()
	for fn: Callable in [
		_DLG_100, _DLG_101, _DLG_102, _DLG_103, _DLG_104, _DLG_105,
	]:
		await fn.call()

	print("\n== battle (BAT) ==")
	for fn: Callable in [
		_BAT_001, _BAT_002, _BAT_003, _BAT_004, _BAT_005, _BAT_006,
		_BAT_007, _BAT_008, _BAT_009, _BAT_010, _BAT_011, _BAT_012,
		_BAT_013, _BAT_014, _BAT_015, _BAT_016, _BAT_017, _BAT_018,
		_BAT_019, _BAT_020, _BAT_021, _BAT_022,
	]:
		await fn.call()

	print("\n== save (SAV) ==")
	for fn: Callable in [
		_SAV_001, _SAV_002, _SAV_003, _SAV_004, _SAV_005, _SAV_006,
		_SAV_007, _SAV_008, _SAV_009, _SAV_010, _SAV_011, _SAV_012,
		_SAV_013, _SAV_014,
	]:
		await fn.call()

	print("\n== chapter 2 (CH2) ==")
	for fn: Callable in [
		_CH2_DLG_001, _CH2_DLG_002, _CH2_DLG_003, _CH2_DLG_004,
		_CH2_DLG_005, _CH2_DLG_006,
		_CH2_BAT_001, _CH2_BAT_002, _CH2_BAT_003,
		_CH2_QUEST_001, _CH2_QUEST_002,
		_CH2_SAVE_001, _CH2_SAVE_002, _CH2_SAVE_003,
		_CH2_FLOW_001, _CH2_FLOW_002, _CH2_FLOW_003,
	]:
		await fn.call()

	print("\n== step9 (DQ answers + dialogue v1.1) ==")
	for fn: Callable in [
		_STEP9_DLG_001, _STEP9_DQ05_001, _STEP9_DQ05_002, _STEP9_DQ05_003, _STEP9_DQ05_004,
		_STEP9_DQ07_001, _STEP9_DQ07_002, _STEP9_VIS_001,
	]:
		await fn.call()

	print("\n== chapter 3 (CH3, step10) ==")
	for fn: Callable in [
		_CH3_DLG_001, _CH3_DLG_002, _CH3_BAT_001, _CH3_BAT_002, _CH3_BAT_003, _CH3_BAT_004,
		_CH3_QUEST_001, _CH3_QUEST_002, _CH3_SAVE_001, _CH3_SAVE_002, _CH3_FLOW_001, _STEP10_VIS_001,
		_STEP10_SAVE_001, _STEP10_SAVE_002,
	]:
		await fn.call()

	cleanup_saves()
	report()

func all_case_ids() -> Array[String]:
	var ids: Array[String] = []
	for i in range(1, 12):
		ids.append("DLG-%03d" % i)
	for i in range(20, 42):
		ids.append("DLG-%03d" % i)
	for i in range(50, 59):
		ids.append("DLG-%03d" % i)
	for i in range(60, 69):
		ids.append("DLG-%03d" % i)
	for i in range(80, 88):
		ids.append("DLG-%03d" % i)
	for i in range(90, 95):
		ids.append("DLG-%03d" % i)
	for i in range(100, 106):
		ids.append("DLG-%03d" % i)
	for i in range(1, 23):
		ids.append("BAT-%03d" % i)
	for i in range(1, 15):
		ids.append("SAV-%03d" % i)
	for i in range(1, 7):
		ids.append("CH2-DLG-%03d" % i)
	for i in range(1, 4):
		ids.append("CH2-BAT-%03d" % i)
	for i in range(1, 3):
		ids.append("CH2-QUEST-%03d" % i)
	for i in range(1, 4):
		ids.append("CH2-SAVE-%03d" % i)
	for i in range(1, 4):
		ids.append("CH2-FLOW-%03d" % i)
	for id: String in ["STEP9-DLG-001", "STEP9-DQ05-001", "STEP9-DQ05-002", "STEP9-DQ05-003", "STEP9-DQ05-004",
			"STEP9-DQ07-001", "STEP9-DQ07-002", "STEP9-VIS-001",
			"CH3-DLG-001", "CH3-DLG-002", "CH3-BAT-001", "CH3-BAT-002", "CH3-BAT-003", "CH3-BAT-004",
			"CH3-QUEST-001", "CH3-QUEST-002", "CH3-SAVE-001", "CH3-SAVE-002", "CH3-FLOW-001", "STEP10-VIS-001",
			"STEP10-SAVE-001", "STEP10-SAVE-002"]:
		ids.append(id)
	return ids

func report() -> void:
	var all_ids := all_case_ids()
	var uncovered: Array[String] = []
	for id: String in all_ids:
		if not _passed.has(id):
			uncovered.append(id)
	uncovered.sort()
	print("\nPASSED %d / %d cases" % [_passed.size(), all_ids.size()])
	print("FAILED (%d): %s" % [_failed.size(), ", ".join(_failed) if not _failed.is_empty() else "-"])
	print("COVERED (%d): %s" % [_passed.size(), ", ".join(_passed)])
	print("UNCOVERED (%d): %s" % [uncovered.size(), ", ".join(uncovered) if not uncovered.is_empty() else "-"])
	if _failed.is_empty() and uncovered.is_empty():
		print("ALL ACCEPTANCE CASES PASSED")
	else:
		printerr("ACCEPTANCE TESTS FAILED")
	quit(1 if (_failed.size() > 0 or uncovered.size() > 0) else 0)

# ================================================================== DLG

func _DLG_001() -> void:
	begin_case("DLG-001", "dialogue data parse/version/references")
	expect(db.load_error == "", "load_error=%s" % db.load_error)
	expect(db.validate().is_empty(), "validate=%s" % [db.validate()])
	expect(int(db.db.get("schemaVersion", 0)) == 1, "schemaVersion")
	expect(str(db.db.get("id", "")) == "shanhe.dialogue.verticalSlice", "id")
	expect(str(db.db.get("contentVersion", "")) == "dialogue-v1", "contentVersion")
	expect(str(db.db.get("language", "")) == "zh-Hans", "language")
	expect(db.dialogues.size() == 83, "dialogues=%d" % db.dialogues.size())
	expect(db.nodes.size() == 229, "nodes=%d" % db.nodes.size())
	for did: String in db.dialogues:
		expect(db.nodes.has(str(db.dialogues[did].get("entry", ""))), "entry %s" % did)
	end_case()

func _DLG_002() -> void:
	begin_case("DLG-002", "empty conditions are true")
	reset_state("notAccepted", "locked", false)
	expect(gs.conditions_ok([]), "empty array")
	for nid: String in db.nodes:
		expect(typeof(db.nodes[nid].get("conditions", [])) == TYPE_ARRAY, "node %s type" % nid)
		expect(gs.conditions_ok(db.nodes[nid].get("conditions", [])), "node %s conds" % nid)
	for did: String in db.dialogues:
		var conds: Array = dlg_conditions(did)
		if conds.is_empty():
			expect(gs.conditions_ok(conds), "dialogue %s conds" % did)
	end_case()

func _DLG_003() -> void:
	begin_case("DLG-003", "condition arrays are AND")
	var conds := dlg_conditions("zhou_main_deliver")
	reset_state("accepted", "girlMet", true)
	var both_true: bool = gs.conditions_ok(conds)
	reset_state("accepted", "girlMet", false)
	var task_only: bool = gs.conditions_ok(conds)
	reset_state("accepted", "girlMet", null)
	var task_only_null: bool = gs.conditions_ok(conds)
	reset_state("delivered", "girlMet", true)
	var flag_only: bool = gs.conditions_ok(conds)
	reset_state("notAccepted", "girlMet", false)
	var both_false: bool = gs.conditions_ok(conds)
	expect(both_true, "both true")
	expect(not task_only, "task only false")
	expect(not task_only_null, "task only null false")
	expect(not flag_only, "flag only false")
	expect(not both_false, "both false")
	end_case()

func _DLG_004() -> void:
	begin_case("DLG-004", "unknown main state blocks quest conditions")
	reset_state("unknown", "locked", false)
	expect(pick_id("village.zhoubo") == "zhou_idle", "pick=%s" % pick_id("village.zhoubo"))
	for state: String in ["notAccepted", "accepted", "delivered"]:
		expect(not gs.conditions_ok([{"quest": "main.zhouCommission", "equals": state}]), "equals %s" % state)
	end_case()

func _DLG_005() -> void:
	begin_case("DLG-005", "disabled side state is unknown -> false")
	reset_state("accepted", "disabled", false)
	var accepted_no_win := pick_id("village.zhoubo")
	reset_state("accepted", "disabled", true)
	var accepted_win := pick_id("village.zhoubo")
	reset_state("delivered", "disabled", true)
	suppress_ch2()
	var delivered := pick_id("village.zhoubo")
	reset_state("accepted", "disabled", false)
	var girl := pick_id("bamboo.linzhaowan")
	var monk := pick_id("village.mingcheng")
	expect(accepted_no_win == "zhou_main_progress", "accepted/no-win=%s" % accepted_no_win)
	expect(accepted_win == "zhou_main_deliver", "accepted/win=%s" % accepted_win)
	expect(delivered == "zhou_idle", "delivered=%s" % delivered)
	expect(girl == "girl_stranger", "girl=%s" % girl)
	expect(monk == "monk_idle", "monk=%s" % monk)
	end_case()

func _DLG_006() -> void:
	begin_case("DLG-006", "missing flags compare as null -> false")
	gs.reset_new_game()
	gs.flags.erase("battle.liheng.won")
	gs.flags.erase("dlg.liheng.postSeen")
	expect(gs.get_flag("battle.liheng.won") == null, "battle flag not null")
	expect(gs.get_flag("dlg.liheng.postSeen") == null, "post flag not null")
	expect(not gs.conditions_ok([{"flag": "battle.liheng.won", "equals": true}]), "battle equals true")
	expect(not gs.conditions_ok([{"flag": "dlg.liheng.postSeen", "equals": true}]), "post equals true")
	end_case()

func _DLG_007() -> void:
	begin_case("DLG-007", "selection is first true, not most specific")
	reset_state("accepted", "available", true)
	expect(pick_id("village.zhoubo") == "bc_zhou_invite", "pick=%s" % pick_id("village.zhoubo"))
	end_case()

func _DLG_008() -> void:
	begin_case("DLG-008", "no matching dialogue at battle-return point")
	reset_state("accepted", "girlMet", false)
	var no_win: Dictionary = db.pick_dialogue("battle_return.liheng_victory")
	reset_state("accepted", "girlMet", true, true)
	var seen: Dictionary = db.pick_dialogue("battle_return.liheng_victory")
	expect(no_win.is_empty(), "won false pick=%s" % no_win)
	expect(seen.is_empty(), "postSeen true pick=%s" % seen)
	end_case()

func _DLG_009() -> void:
	begin_case("DLG-009", "commit only at end; cancel discards")
	reset_state("notAccepted", "locked", false)
	var dlg: Dictionary = db.pick_dialogue("village.zhoubo")
	var cancelled: Dictionary = await run_dialogue(dlg, [0], 0)
	var after_cancel: String = str(gs.main_state)
	expect(cancelled.cancelled, "not cancelled")
	expect(after_cancel == "notAccepted", "main=%s" % after_cancel)
	expect((cancelled.effects as Array).is_empty(), "cancel effects")
	reset_state("notAccepted", "locked", false)
	var complete: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"), [0])
	expect(not complete.cancelled, "complete cancelled")
	expect(quest_effect(complete, "main.zhouCommission", "accept"), "accept effect")
	expect(gs.main_state == "accepted", "main=%s" % gs.main_state)
	end_case()

func _DLG_010() -> void:
	begin_case("DLG-010", "false node condition cancels without commit")
	reset_state("notAccepted", "locked", false)
	var nodes := [
		{"id": "tmp_010_a", "dialogue": "tmp_010", "speaker": "shenyan", "text": "a", "next": "tmp_010_b", "conditions": [], "setFlags": {}, "effects": []},
		{"id": "tmp_010_b", "dialogue": "tmp_010", "speaker": "shenyan", "text": "b", "end": true,
			"conditions": [{"flag": "battle.liheng.won", "equals": true}],
			"setFlags": {"dlg.tmp010": true},
			"effects": [{"type": "questEvent", "quest": "main.zhouCommission", "event": "accept"}]},
	]
	var dlg := add_temp_dialogue("tmp_010", "tmp_010_a", nodes)
	var run: Dictionary = await run_dialogue(dlg)
	remove_temp_dialogue("tmp_010", nodes)
	expect(run.cancelled, "not cancelled")
	expect(gs.main_state == "notAccepted", "main=%s" % gs.main_state)
	expect(not gs.flags.has("dlg.tmp010"), "flag committed")
	end_case()

func _DLG_011() -> void:
	begin_case("DLG-011", "setFlags namespace is dlg.* only")
	reset_state("notAccepted", "locked", false)
	var nodes := [
		{"id": "tmp_011_a", "dialogue": "tmp_011", "speaker": "shenyan", "text": "a", "end": true,
			"conditions": [],
			"setFlags": {"battle.liheng.won": true, "dlg.tmp011.ok": true},
			"effects": []},
	]
	var dlg := add_temp_dialogue("tmp_011", "tmp_011_a", nodes)
	var run: Dictionary = await run_dialogue(dlg)
	remove_temp_dialogue("tmp_011", nodes)
	expect(not run.cancelled, "cancelled")
	expect(not gs.is_flag_true("battle.liheng.won"), "battle flag rewritten")
	expect(gs.is_flag_true("dlg.tmp011.ok"), "legal dlg flag missing")
	end_case()

func _DLG_020() -> void:
	begin_case("DLG-020", "selects zhou_main_offer and path to zmo_04")
	reset_state("notAccepted", "locked", false)
	var dlg: Dictionary = db.pick_dialogue("village.zhoubo")
	var n1 := node("zmo_01")
	expect(str(dlg.get("id", "")) == "zhou_main_offer", "pick=%s" % dlg.get("id", ""))
	expect(str(dlg.get("entry", "")) == "zmo_01", "entry=%s" % dlg.get("entry", ""))
	expect(str(n1.get("next", "")) == "zmo_02", "zmo_01 next")
	expect(str(node("zmo_02").get("next", "")) == "zmo_03", "zmo_02 next")
	expect(str(node("zmo_03").get("next", "")) == "zmo_04", "zmo_03 next")
	expect(db.speaker_id(n1) == "zhoubo" and db.speaker_id(node("zmo_02")) == "shenyan", "speakers 1")
	expect(db.speaker_id(node("zmo_03")) == "zhoubo" and db.speaker_id(node("zmo_04")) == "zhoubo", "speakers 2")
	expect(str(n1.get("text", "")) == "后生，可是要往竹林那头去？", "zmo_01 text")
	expect(choice_ids("zmo_04") == ["zmo_04_c1", "zmo_04_c2"], "choice ids=%s" % [choice_ids("zmo_04")])
	expect(choice_texts("zmo_04") == ["交给我。", "那人什么来路？"], "choice texts=%s" % [choice_texts("zmo_04")])
	end_case()

func _DLG_021() -> void:
	begin_case("DLG-021", "not zhou_main_offer when main is not notAccepted")
	reset_state("accepted", "girlMet", false)
	var accepted := pick_id("village.zhoubo")
	reset_state("delivered", "completed", true)
	var delivered := pick_id("village.zhoubo")
	expect(accepted != "zhou_main_offer", "accepted pick=%s" % accepted)
	expect(delivered != "zhou_main_offer", "delivered pick=%s" % delivered)
	end_case()

func _DLG_022() -> void:
	begin_case("DLG-022", "zmo_04_c1 merges to zmo_06 and commits accept")
	reset_state("notAccepted", "locked", false)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"), [0])
	expect(run.node_ids == ["zmo_01", "zmo_02", "zmo_03", "zmo_04", "zmo_06"], "path=%s" % [run.node_ids])
	expect(quest_effect(run, "main.zhouCommission", "accept"), "accept effect")
	expect((run.effects as Array).size() == 1, "effects=%s" % [run.effects])
	expect(gs.main_state == "accepted", "main=%s" % gs.main_state)
	expect(flags_only_allowed(), "flags=%s" % [gs.flags])
	expect(db.get_dialogue("zhou_main_offer").get("replayable", true) == false, "replayable")
	end_case()

func _DLG_023() -> void:
	begin_case("DLG-023", "zmo_04_c2 passes zmo_05 and commits same accept")
	reset_state("notAccepted", "locked", false)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"), [1])
	expect(run.node_ids == ["zmo_01", "zmo_02", "zmo_03", "zmo_04", "zmo_05", "zmo_06"], "path=%s" % [run.node_ids])
	expect(str(node("zmo_05").get("text", "")) == "他砍两刀便要蓄一回力，见他握紧刀柄，下一刀就是重的。", "zmo_05 text")
	expect(quest_effect(run, "main.zhouCommission", "accept"), "accept effect")
	expect(flags_only_allowed(), "flags=%s" % [gs.flags])
	# DLG-023-F: cancelling on zmo_05 (before zmo_06) commits nothing.
	reset_state("notAccepted", "locked", false)
	var flags_before: Dictionary = gs.flags.duplicate(true)
	var cancelled: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"), [1], 4)
	expect(cancelled.cancelled, "c2 not cancelled")
	expect(cancelled.node_ids == ["zmo_01", "zmo_02", "zmo_03", "zmo_04", "zmo_05"], "cancel path=%s" % [cancelled.node_ids])
	expect((cancelled.effects as Array).is_empty(), "cancel effects=%s" % [cancelled.effects])
	expect(gs.main_state == "notAccepted", "main after cancel=%s" % gs.main_state)
	expect(JSON.stringify(gs.flags) == JSON.stringify(flags_before), "flags changed on cancel: %s" % [gs.flags])
	end_case()

func _DLG_024() -> void:
	begin_case("DLG-024", "selects bc_zhou_invite and commits talkZhou")
	reset_state("accepted", "available", false)
	expect(pick_id("village.zhoubo") == "bc_zhou_invite", "pick=%s" % pick_id("village.zhoubo"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"))
	expect(run.node_ids == ["bzi_01", "bzi_02"], "path=%s" % [run.node_ids])
	expect(str(node("bzi_01").get("text", "")) == "竹林里有位背剑姑娘，遇见了替我问声平安。", "text")
	expect(quest_effect(run, "side.bambooCompanions", "talkZhou"), "talkZhou")
	expect(gs.side_state == "accepted", "side=%s" % gs.side_state)
	end_case()

func _DLG_025() -> void:
	begin_case("DLG-025", "bc_zhou_invite needs both conditions")
	reset_state("accepted", "accepted", false)
	var side_accepted := pick_id("village.zhoubo")
	reset_state("accepted", "girlMet", false)
	var side_girl := pick_id("village.zhoubo")
	reset_state("notAccepted", "available", false)
	var main_not_accepted := pick_id("village.zhoubo")
	reset_state("delivered", "available", false)
	var main_delivered := pick_id("village.zhoubo")
	# Normalization upgrades locked -> available first; documented divergence from DLG-025(a)'s wording.
	reset_state("accepted", "locked", false)
	var locked_normalized := pick_id("village.zhoubo")
	expect(side_accepted != "bc_zhou_invite", "side accepted -> %s" % side_accepted)
	expect(side_girl != "bc_zhou_invite", "side girlMet -> %s" % side_girl)
	expect(main_not_accepted == "zhou_main_offer", "main notAccepted -> %s" % main_not_accepted)
	expect(main_delivered != "bc_zhou_invite", "main delivered -> %s" % main_delivered)
	expect(locked_normalized == "bc_zhou_invite", "locked normalized -> %s" % locked_normalized)
	# DLG-025(a)-B named: other genuine non-available side states never pick the invite.
	for side: String in ["bothMet", "ready", "completed", "disabled"]:
		reset_state("accepted", side, false)
		var picked := pick_id("village.zhoubo")
		expect(gs.side_state == side, "side %s normalized to %s" % [side, gs.side_state])
		expect(picked != "bc_zhou_invite", "side %s -> %s" % [side, picked])
	end_case()

func _DLG_026() -> void:
	begin_case("DLG-026", "selects zhou_main_deliver and commits deliver")
	reset_state("accepted", "girlMet", true)
	expect(pick_id("village.zhoubo") == "zhou_main_deliver", "pick=%s" % pick_id("village.zhoubo"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"))
	expect(run.node_ids == ["zmd_01", "zmd_02", "zmd_03"], "path=%s" % [run.node_ids])
	expect(quest_effect(run, "main.zhouCommission", "deliver"), "deliver effect")
	expect(int(run.rewards) == 0, "rewards=%d" % run.rewards)
	expect(not has_type(run, "startBattle"), "startBattle present")
	expect(gs.main_state == "delivered", "main=%s" % gs.main_state)
	end_case()

func _DLG_027() -> void:
	begin_case("DLG-027", "accepted + not won selects zhou_main_progress")
	var ok := true
	for won: Variant in [null, false]:
		reset_state("accepted", "girlMet", won)
		var picked := pick_id("village.zhoubo")
		var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"))
		ok = ok and picked == "zhou_main_progress"
		ok = ok and run.node_ids == ["zmp_01"]
		ok = ok and (run.effects as Array).is_empty()
		ok = ok and str(node("zmp_01").get("text", "")) == "厉横还在竹林里，当心他那口重刀。"
		ok = ok and pick_id("village.zhoubo") == "zhou_main_progress"
	expect(ok, "progress loop failed")
	end_case()

func _DLG_028() -> void:
	begin_case("DLG-028", "non-accepted main never selects deliver/progress")
	reset_state("notAccepted", "locked", true)
	var a := pick_id("village.zhoubo")
	reset_state("delivered", "completed", true)
	var b := pick_id("village.zhoubo")
	expect(a not in ["zhou_main_deliver", "zhou_main_progress"], "notAccepted -> %s" % a)
	expect(b not in ["zhou_main_deliver", "zhou_main_progress"], "delivered -> %s" % b)
	end_case()

func _DLG_029() -> void:
	begin_case("DLG-029", "selects bc_finale and commits talkZhou/reward once")
	reset_state("delivered", "ready", true)
	expect(pick_id("village.zhoubo") == "bc_finale", "pick=%s" % pick_id("village.zhoubo"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"))
	expect(run.node_ids == ["bcf_01", "bcf_02", "bcf_03", "bcf_04"], "path=%s" % [run.node_ids])
	expect(run.speakers == ["周伯", "明澄", "林照晚", "沈砚"], "speakers=%s" % [run.speakers])
	expect(quest_effect(run, "side.bambooCompanions", "talkZhou"), "talkZhou")
	expect(int(run.rewards) == 1, "rewards=%d" % run.rewards)
	expect(gs.side_state == "completed" and gs.side_receipt == "bambooCompanions.v1.promise", "side=%s receipt=%s" % [gs.side_state, gs.side_receipt])
	expect(not has_type(run, "startBattle"), "startBattle present")
	expect(flags_only_allowed(), "flags=%s" % [gs.flags])
	end_case()

func _DLG_030() -> void:
	begin_case("DLG-030", "bc_finale conditions must both hold")
	reset_state("delivered", "accepted", true)
	var accepted := pick_id("village.zhoubo")
	reset_state("delivered", "completed", true)
	var completed := pick_id("village.zhoubo")
	reset_state("delivered", "legacyClosed", true)
	var legacy := pick_id("village.zhoubo")
	reset_state("accepted", "ready", false)
	var main_accepted := pick_id("village.zhoubo")
	expect(accepted != "bc_finale", "side accepted -> %s" % accepted)
	expect(completed != "bc_finale", "side completed -> %s" % completed)
	expect(legacy != "bc_finale", "side legacy -> %s" % legacy)
	expect(main_accepted != "bc_finale", "main accepted -> %s" % main_accepted)
	end_case()

func _DLG_031() -> void:
	begin_case("DLG-031", "bc_finale_replay branch c1, no reward, repeatable")
	reset_state("delivered", "completed", true)
	suppress_ch2()
	expect(pick_id("village.zhoubo") == "bc_finale_replay", "pick=%s" % pick_id("village.zhoubo"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"), [0])
	expect(run.node_ids == ["bfr_01", "bfr_02", "bfr_03", "bfr_04", "bfr_05"], "path=%s" % [run.node_ids])
	expect((run.effects as Array).is_empty(), "effects=%s" % [run.effects])
	expect(int(run.rewards) == 0, "rewards=%d" % run.rewards)
	expect(gs.side_state == "completed", "side=%s" % gs.side_state)
	expect(pick_id("village.zhoubo") == "bc_finale_replay", "second pick")
	end_case()

func _DLG_032() -> void:
	begin_case("DLG-032", "bc_finale_replay branch c2 goes to bfr_06")
	reset_state("delivered", "completed", true)
	suppress_ch2()
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"), [1])
	expect(run.node_ids == ["bfr_01", "bfr_06"], "path=%s" % [run.node_ids])
	expect(str(node("bfr_06").get("text", "")) == "去吧，山里雾大，走路看脚下。", "text")
	expect((run.effects as Array).is_empty(), "effects=%s" % [run.effects])
	expect(int(run.rewards) == 0, "rewards=%d" % run.rewards)
	end_case()

func _DLG_033() -> void:
	begin_case("DLG-033", "not completed / not delivered excludes replay")
	reset_state("delivered", "ready", true)
	var ready := pick_id("village.zhoubo")
	reset_state("accepted", "completed", false)
	var accepted := pick_id("village.zhoubo")
	expect(ready != "bc_finale_replay", "ready -> %s" % ready)
	expect(accepted != "bc_finale_replay", "accepted -> %s" % accepted)
	end_case()

func _DLG_034() -> void:
	begin_case("DLG-034", "selects zhou_side_pending_girl, repeatable")
	reset_state("delivered", "accepted", true)
	suppress_ch2()
	expect(pick_id("village.zhoubo") == "zhou_side_pending_girl", "pick=%s" % pick_id("village.zhoubo"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"))
	expect(run.node_ids == ["zsg_01"], "path=%s" % [run.node_ids])
	expect(str(node("zsg_01").get("text", "")) == "竹林里那位背剑姑娘，你见着了吗？不急，见着了再来。", "text")
	expect((run.effects as Array).is_empty(), "effects=%s" % [run.effects])
	expect(pick_id("village.zhoubo") == "zhou_side_pending_girl", "second pick")
	end_case()

func _DLG_035() -> void:
	begin_case("DLG-035", "delivered + non-accepted side excludes pending_girl")
	var ok := true
	for side: String in ["girlMet", "ready", "locked"]:
		reset_state("delivered", side, true)
		var picked := pick_id("village.zhoubo")
		ok = ok and picked != "zhou_side_pending_girl"
	expect(ok, "pending_girl selected")
	end_case()

func _DLG_036() -> void:
	begin_case("DLG-036", "selects zhou_side_pending_monk for girlMet")
	reset_state("delivered", "girlMet", true)
	suppress_ch2()
	expect(pick_id("village.zhoubo") == "zhou_side_pending_monk", "pick=%s" % pick_id("village.zhoubo"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"))
	expect(run.node_ids == ["zsm_01"], "path=%s" % [run.node_ids])
	expect(str(node("zsm_01").get("text", "")) == "明澄那孩子在村口转了半天，你去打声招呼吧。", "text")
	expect((run.effects as Array).is_empty(), "effects=%s" % [run.effects])
	end_case()

func _DLG_037() -> void:
	begin_case("DLG-037", "bothMet in-list true; normalize makes ready -> finale")
	reset_state("delivered", "bothMet", true)
	var raw_in: bool = gs.conditions_ok(dlg_conditions("zhou_side_pending_monk"))
	var picked := pick_id("village.zhoubo")
	expect(raw_in, "raw in [girlMet,bothMet] false")
	expect(picked == "bc_finale", "normalized pick=%s" % picked)
	expect(gs.side_state == "ready", "side=%s" % gs.side_state)
	end_case()

func _DLG_038() -> void:
	begin_case("DLG-038", "pending_monk not selected outside [girlMet,bothMet]")
	reset_state("delivered", "accepted", true)
	var a := pick_id("village.zhoubo")
	reset_state("delivered", "completed", true)
	var b := pick_id("village.zhoubo")
	expect(a != "zhou_side_pending_monk", "accepted -> %s" % a)
	expect(b != "zhou_side_pending_monk", "completed -> %s" % b)
	end_case()

func _DLG_039() -> void:
	begin_case("DLG-039", "selects zhou_legacy_closed, no reward")
	reset_state("delivered", "legacyClosed", true)
	suppress_ch2()
	expect(pick_id("village.zhoubo") == "zhou_legacy_closed", "pick=%s" % pick_id("village.zhoubo"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"))
	expect(run.node_ids == ["zlc_01"], "path=%s" % [run.node_ids])
	expect(str(node("zlc_01").get("text", "")) == "竹林的事早了结了，你这一路辛苦。", "text")
	expect((run.effects as Array).is_empty(), "effects=%s" % [run.effects])
	expect(int(run.rewards) == 0, "rewards=%d" % run.rewards)
	end_case()

func _DLG_040() -> void:
	begin_case("DLG-040", "legacy_closed requires delivered + legacyClosed")
	reset_state("delivered", "completed", true)
	var a := pick_id("village.zhoubo")
	reset_state("accepted", "legacyClosed", false)
	var b := pick_id("village.zhoubo")
	expect(a != "zhou_legacy_closed", "delivered/completed -> %s" % a)
	expect(b != "zhou_legacy_closed", "accepted/legacy -> %s" % b)
	end_case()

func _DLG_041() -> void:
	begin_case("DLG-041", "zhou_idle fallback")
	reset_state("unknown", "locked", false)
	var unknown := pick_id("village.zhoubo")
	reset_state("delivered", "disabled", true)
	suppress_ch2()
	var disabled := pick_id("village.zhoubo")
	reset_state("delivered", "locked", true)
	suppress_ch2()
	var legacy := pick_id("village.zhoubo")
	reset_state("notAccepted", "locked", false)
	var fresh := pick_id("village.zhoubo")
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"), [0])
	expect(unknown == "zhou_idle", "unknown -> %s" % unknown)
	expect(disabled == "zhou_idle", "disabled -> %s" % disabled)
	expect(legacy == "zhou_legacy_closed", "delivered+locked -> %s" % legacy)
	expect(fresh != "zhou_idle", "fresh -> %s" % fresh)
	expect(run.node_ids == ["zmo_01", "zmo_02", "zmo_03", "zmo_04", "zmo_06"], "fresh run path")
	end_case()

func _DLG_050() -> void:
	begin_case("DLG-050", "selects bc_girl_meet with nameOverride and choices")
	reset_state("accepted", "accepted", false)
	expect(pick_id("bamboo.linzhaowan") == "bc_girl_meet", "pick=%s" % pick_id("bamboo.linzhaowan"))
	var n := node("bgm_01")
	expect(str(n.get("nameOverride", "")) == "背剑少女", "nameOverride")
	expect(db.speaker_display_name(n) == "背剑少女", "display name")
	expect(str(n.get("text", "")) == "我在寻药包，不是在等人搭救。", "text")
	expect(choice_ids("bgm_01") == ["bgm_01_c1", "bgm_01_c2"], "choice ids=%s" % [choice_ids("bgm_01")])
	expect(choice_texts("bgm_01") == ["那便各做各的，遇事互相照应。", "周伯托我问你一声平安。"], "choice texts")
	expect(db.get_dialogue("bc_girl_meet").get("replayable", true) == false, "replayable")
	end_case()

func _DLG_051() -> void:
	begin_case("DLG-051", "non-accepted side excludes bc_girl_meet")
	var ok := true
	for side: String in ["available", "girlMet", "locked", "completed"]:
		reset_state("notAccepted", side, false)
		var picked := pick_id("bamboo.linzhaowan")
		ok = ok and picked != "bc_girl_meet"
	expect(ok, "girl_meet selected")
	end_case()

func _DLG_052() -> void:
	begin_case("DLG-052", "bgm_01_c1 reaches bgm_04 and commits talkGirl")
	reset_state("accepted", "accepted", false)
	var potions_before: int = int(gs.potions)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("bamboo.linzhaowan"), [0])
	expect(run.node_ids == ["bgm_01", "bgm_04"], "path=%s" % [run.node_ids])
	expect(quest_effect(run, "side.bambooCompanions", "talkGirl"), "talkGirl")
	expect(gs.side_state == "girlMet", "side=%s" % gs.side_state)
	expect(db.speaker_display_name(node("bgm_04")) == "林照晚", "bgm_04 name")
	expect(gs.potions == potions_before, "potions changed")
	end_case()

func _DLG_053() -> void:
	begin_case("DLG-053", "bgm_01_c2 passes bgm_02/bgm_03 to bgm_04")
	reset_state("accepted", "accepted", false)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("bamboo.linzhaowan"), [1])
	expect(run.node_ids == ["bgm_01", "bgm_02", "bgm_03", "bgm_04"], "path=%s" % [run.node_ids])
	expect(str(node("bgm_02").get("nameOverride", "")) == "背剑少女", "bgm_02 nameOverride")
	expect(str(node("bgm_03").get("speaker", "")) == "shenyan", "bgm_03 speaker")
	expect(quest_effect(run, "side.bambooCompanions", "talkGirl"), "talkGirl")
	end_case()

func _DLG_054() -> void:
	begin_case("DLG-054", "bc_girl_repeat for girlMet/bothMet/ready")
	var all_ok := true
	for side: String in ["girlMet", "bothMet", "ready"]:
		reset_state("notAccepted", side, false)
		var picked := pick_id("bamboo.linzhaowan")
		all_ok = all_ok and picked == "bc_girl_repeat"
	expect(all_ok, "repeat not selected for all states")
	reset_state("notAccepted", "girlMet", false)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("bamboo.linzhaowan"))
	expect(run.node_ids == ["bgr_01"], "path=%s" % [run.node_ids])
	expect(str(node("bgr_01").get("text", "")) == "药包的事我自己来，你忙你的。", "text")
	expect((run.effects as Array).is_empty(), "effects=%s" % [run.effects])
	end_case()

func _DLG_055() -> void:
	begin_case("DLG-055", "bc_girl_repeat excludes accepted/completed/legacy")
	reset_state("notAccepted", "accepted", false)
	var accepted := pick_id("bamboo.linzhaowan")
	reset_state("notAccepted", "completed", false)
	var completed := pick_id("bamboo.linzhaowan")
	reset_state("notAccepted", "legacyClosed", false)
	var legacy := pick_id("bamboo.linzhaowan")
	expect(accepted != "bc_girl_repeat", "accepted -> %s" % accepted)
	expect(completed != "bc_girl_repeat", "completed -> %s" % completed)
	expect(legacy != "bc_girl_repeat", "legacy -> %s" % legacy)
	end_case()

func _DLG_056() -> void:
	begin_case("DLG-056", "selects bc_girl_after for completed")
	reset_state("notAccepted", "completed", false)
	expect(pick_id("bamboo.linzhaowan") == "bc_girl_after", "pick=%s" % pick_id("bamboo.linzhaowan"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("bamboo.linzhaowan"))
	expect(run.node_ids == ["bga_01"], "path=%s" % [run.node_ids])
	expect(str(node("bga_01").get("text", "")) == "说好了的，不许替我拔剑。", "text")
	expect(db.speaker_display_name(node("bga_01")) == "林照晚", "name")
	expect((run.effects as Array).is_empty(), "effects")
	end_case()

func _DLG_057() -> void:
	begin_case("DLG-057", "non-completed excludes bc_girl_after")
	reset_state("notAccepted", "ready", false)
	var ready := pick_id("bamboo.linzhaowan")
	reset_state("notAccepted", "accepted", false)
	var accepted := pick_id("bamboo.linzhaowan")
	expect(ready != "bc_girl_after", "ready -> %s" % ready)
	expect(accepted != "bc_girl_after", "accepted -> %s" % accepted)
	end_case()

func _DLG_058() -> void:
	begin_case("DLG-058", "girl_stranger fallback keeps name hidden")
	var ok := true
	for side: String in ["locked", "available", "legacyClosed", "disabled"]:
		reset_state("notAccepted", side, false)
		ok = ok and pick_id("bamboo.linzhaowan") == "girl_stranger"
	expect(ok, "stranger not selected")
	reset_state("notAccepted", "locked", false)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("bamboo.linzhaowan"))
	expect(run.node_ids == ["gst_01"], "path=%s" % [run.node_ids])
	expect(str(node("gst_01").get("nameOverride", "")) == "背剑少女", "nameOverride")
	expect(str(node("gst_01").get("text", "")) == "竹林路窄，借过。", "text")
	expect((run.effects as Array).is_empty(), "effects")
	end_case()

func _DLG_060() -> void:
	begin_case("DLG-060", "selects bc_monk_join and commits talkMonk")
	reset_state("notAccepted", "girlMet", false)
	expect(pick_id("village.mingcheng") == "bc_monk_join", "pick=%s" % pick_id("village.mingcheng"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.mingcheng"))
	expect(run.node_ids == ["bmj_01", "bmj_02", "bmj_03"], "path=%s" % [run.node_ids])
	expect(run.speakers == ["明澄", "沈砚", "林照晚"], "speakers=%s" % [run.speakers])
	expect(quest_effect(run, "side.bambooCompanions", "talkMonk"), "talkMonk")
	expect(gs.side_state == "bothMet", "side=%s" % gs.side_state)
	expect(not has_type(run, "startBattle"), "startBattle")
	end_case()

func _DLG_061() -> void:
	begin_case("DLG-061", "non-girlMet excludes bc_monk_join")
	var ok := true
	for side: String in ["accepted", "bothMet", "ready"]:
		reset_state("notAccepted", side, false)
		ok = ok and pick_id("village.mingcheng") != "bc_monk_join"
	expect(ok, "monk_join selected")
	end_case()

func _DLG_062() -> void:
	begin_case("DLG-062", "selects bc_monk_wait for bothMet")
	reset_state("notAccepted", "bothMet", false)
	expect(pick_id("village.mingcheng") == "bc_monk_wait", "pick=%s" % pick_id("village.mingcheng"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.mingcheng"))
	expect(run.node_ids == ["bmw_01"], "path=%s" % [run.node_ids])
	expect(str(node("bmw_01").get("text", "")) == "先把周伯的事办了，我们在村口等你。", "text")
	expect((run.effects as Array).is_empty(), "effects")
	expect(pick_id("village.mingcheng") == "bc_monk_wait", "second pick")
	end_case()

func _DLG_063() -> void:
	begin_case("DLG-063", "non-bothMet excludes bc_monk_wait")
	reset_state("notAccepted", "girlMet", false)
	var girl := pick_id("village.mingcheng")
	reset_state("notAccepted", "ready", false)
	var ready := pick_id("village.mingcheng")
	expect(girl != "bc_monk_wait", "girlMet -> %s" % girl)
	expect(ready != "bc_monk_wait", "ready -> %s" % ready)
	end_case()

func _DLG_064() -> void:
	begin_case("DLG-064", "selects bc_monk_ready for ready")
	reset_state("notAccepted", "ready", false)
	expect(pick_id("village.mingcheng") == "bc_monk_ready", "pick=%s" % pick_id("village.mingcheng"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.mingcheng"))
	expect(run.node_ids == ["bmr_01"], "path=%s" % [run.node_ids])
	expect(str(node("bmr_01").get("text", "")) == "去见周伯吧，他还念叨着你呢。", "text")
	expect((run.effects as Array).is_empty(), "effects")
	expect(pick_id("village.mingcheng") == "bc_monk_ready", "second pick")
	end_case()

func _DLG_065() -> void:
	begin_case("DLG-065", "non-ready excludes bc_monk_ready")
	reset_state("notAccepted", "completed", false)
	var completed := pick_id("village.mingcheng")
	reset_state("notAccepted", "bothMet", false)
	var both := pick_id("village.mingcheng")
	expect(completed != "bc_monk_ready", "completed -> %s" % completed)
	expect(both != "bc_monk_ready", "bothMet -> %s" % both)
	end_case()

func _DLG_066() -> void:
	begin_case("DLG-066", "selects bc_monk_after for completed")
	reset_state("notAccepted", "completed", false)
	expect(pick_id("village.mingcheng") == "bc_monk_after", "pick=%s" % pick_id("village.mingcheng"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.mingcheng"))
	expect(run.node_ids == ["bma_01"], "path=%s" % [run.node_ids])
	expect(str(node("bma_01").get("text", "")) == "饭钱各付，这话我可没说笑。", "text")
	expect((run.effects as Array).is_empty(), "effects")
	expect(pick_id("village.mingcheng") == "bc_monk_after", "second pick")
	end_case()

func _DLG_067() -> void:
	begin_case("DLG-067", "ready selects monk_ready not monk_after")
	reset_state("notAccepted", "ready", false)
	var picked := pick_id("village.mingcheng")
	expect(picked == "bc_monk_ready", "pick=%s" % picked)
	expect(picked != "bc_monk_after", "after selected")
	end_case()

func _DLG_068() -> void:
	begin_case("DLG-068", "monk_idle fallback")
	var ok := true
	for side: String in ["locked", "available", "accepted", "legacyClosed", "disabled"]:
		reset_state("notAccepted", side, false)
		ok = ok and pick_id("village.mingcheng") == "monk_idle"
	expect(ok, "idle not selected")
	reset_state("notAccepted", "locked", false)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.mingcheng"))
	expect(run.node_ids == ["mid_01"], "path=%s" % [run.node_ids])
	expect(str(node("mid_01").get("text", "")) == "沈砚，要出门办事？路上当心。", "text")
	expect((run.effects as Array).is_empty(), "effects")
	end_case()

func _DLG_080() -> void:
	begin_case("DLG-080", "liheng_prebattle with null/false victory flag")
	var ok := true
	for won: Variant in [null, false]:
		reset_state("accepted", "girlMet", won)
		ok = ok and pick_id("bamboo.liheng") == "liheng_prebattle"
	var n := node("lpb_01")
	expect(ok, "prebattle not selected")
	expect(str(db.get_dialogue("liheng_prebattle").get("entry", "")) == "lpb_01", "entry")
	expect(db.speaker_id(n) == "liheng", "speaker")
	expect(str(n.get("expression", "")) == "angry", "expression")
	expect(str(n.get("text", "")) == "这条路归我管，过路的留下买路钱。", "text")
	expect(choice_ids("lpb_01") == ["lpb_01_c1", "lpb_01_c2"], "choices=%s" % [choice_ids("lpb_01")])
	expect(db.get_dialogue("liheng_prebattle").get("replayable", false) == true, "replayable")
	end_case()

func _DLG_081() -> void:
	begin_case("DLG-081", "non-accepted or won excludes liheng_prebattle")
	reset_state("notAccepted", "locked", null)
	var a := pick_id("bamboo.liheng")
	reset_state("accepted", "girlMet", true)
	var b := pick_id("bamboo.liheng")
	reset_state("delivered", "girlMet", false)
	var c := pick_id("bamboo.liheng")
	expect(a == "liheng_idle", "notAccepted -> %s" % a)
	expect(b == "liheng_defeated_idle", "accepted+won -> %s" % b)
	expect(c == "liheng_idle", "delivered -> %s" % c)
	end_case()

func _DLG_082() -> void:
	begin_case("DLG-082", "lpb_01_c1 passes lpb_02 and requests battle liheng")
	reset_state("accepted", "girlMet", false)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("bamboo.liheng"), [0])
	expect(run.node_ids == ["lpb_01", "lpb_02", "lpb_04"], "path=%s" % [run.node_ids])
	expect(str(node("lpb_02").get("text", "")) == "老东西倒会找帮手。", "text")
	expect(str(node("lpb_04").get("text", "")) == "那就手底下见真章！", "text")
	expect(battle_effect(run, "liheng"), "startBattle")
	expect(run.battles == ["liheng"], "battles=%s" % [run.battles])
	expect(not gs.is_flag_true("battle.liheng.won"), "victory flag set")
	expect(flags_only_allowed(), "flags=%s" % [gs.flags])
	end_case()

func _DLG_083() -> void:
	begin_case("DLG-083", "lpb_01_c2 passes lpb_03 and requests same battle")
	reset_state("accepted", "girlMet", false)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("bamboo.liheng"), [1])
	expect(run.node_ids == ["lpb_01", "lpb_03", "lpb_04"], "path=%s" % [run.node_ids])
	expect(str(node("lpb_03").get("text", "")) == "嘿，还是个闷葫芦。", "text")
	expect(battle_effect(run, "liheng"), "startBattle")
	expect(run.battles == ["liheng"], "battles=%s" % [run.battles])
	end_case()

func _DLG_084() -> void:
	begin_case("DLG-084", "after defeat liheng_prebattle is selectable again")
	reset_state("accepted", "girlMet", false)
	var before := pick_id("bamboo.liheng")
	var battle := BattleLogic.new()
	battle.hp = 1
	battle.take_turn("guard")
	var after := pick_id("bamboo.liheng")
	var run: Dictionary = await run_dialogue(db.pick_dialogue("bamboo.liheng"), [0])
	expect(before == "liheng_prebattle", "before=%s" % before)
	expect(battle.lost and not battle.won, "battle not lost")
	expect(not gs.is_flag_true("battle.liheng.won"), "victory flag set")
	expect(after == "liheng_prebattle", "after=%s" % after)
	expect(run.battles == ["liheng"], "battle request missing")
	end_case()

func _DLG_085() -> void:
	begin_case("DLG-085", "liheng_defeated_idle after victory")
	reset_state("accepted", "girlMet", true)
	expect(pick_id("bamboo.liheng") == "liheng_defeated_idle", "pick=%s" % pick_id("bamboo.liheng"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("bamboo.liheng"))
	expect(run.node_ids == ["ldi_01"], "path=%s" % [run.node_ids])
	expect(str(node("ldi_01").get("text", "")) == "别看了，我这就走。", "text")
	expect((run.effects as Array).is_empty(), "effects")
	expect(pick_id("bamboo.liheng") == "liheng_defeated_idle", "second pick")
	end_case()

func _DLG_086() -> void:
	begin_case("DLG-086", "defeated_idle requires won=true")
	reset_state("accepted", "girlMet", null)
	var a := pick_id("bamboo.liheng")
	reset_state("accepted", "girlMet", false)
	var b := pick_id("bamboo.liheng")
	expect(a != "liheng_defeated_idle", "null -> %s" % a)
	expect(b != "liheng_defeated_idle", "false -> %s" % b)
	end_case()

func _DLG_087() -> void:
	begin_case("DLG-087", "liheng_idle fallback does not start battle")
	reset_state("notAccepted", "locked", false)
	expect(pick_id("bamboo.liheng") == "liheng_idle", "pick=%s" % pick_id("bamboo.liheng"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("bamboo.liheng"))
	expect(run.node_ids == ["lid_01"], "path=%s" % [run.node_ids])
	expect(str(node("lid_01").get("text", "")) == "小子，没事别往这边凑。", "text")
	expect(not battle_effect(run, "liheng"), "startBattle present")
	end_case()

func _DLG_090() -> void:
	begin_case("DLG-090", "liheng_postbattle with postSeen null/false")
	var ok := true
	for post: Variant in [null, false]:
		reset_state("accepted", "girlMet", true, post)
		ok = ok and pick_id("battle_return.liheng_victory") == "liheng_postbattle"
	expect(ok, "postbattle not selected")
	expect(str(node("lpo_01").get("text", "")) == "……算你狠，这片竹林我不待了。", "text")
	expect(db.get_dialogue("liheng_postbattle").get("replayable", true) == false, "replayable")
	end_case()

func _DLG_091() -> void:
	begin_case("DLG-091", "battle-return point silent without victory")
	var ok := true
	for won: Variant in [null, false]:
		reset_state("accepted", "girlMet", won, null)
		ok = ok and db.pick_dialogue("battle_return.liheng_victory").is_empty()
		ok = ok and gs.get_flag("dlg.liheng.postSeen") == null
	expect(ok, "postbattle selected without win")
	end_case()

func _DLG_092() -> void:
	begin_case("DLG-092", "battle-return point silent after postSeen")
	reset_state("accepted", "girlMet", true, true)
	expect(db.pick_dialogue("battle_return.liheng_victory").is_empty(), "pick not empty")
	end_case()

func _DLG_093() -> void:
	begin_case("DLG-093", "postbattle commits postSeen and no questEvent")
	reset_state("accepted", "girlMet", true, false)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("battle_return.liheng_victory"))
	expect(run.node_ids == ["lpo_01", "lpo_02"], "path=%s" % [run.node_ids])
	expect(gs.is_flag_true("dlg.liheng.postSeen"), "postSeen not committed")
	expect((run.effects as Array).is_empty(), "effects=%s" % [run.effects])
	expect(gs.main_state == "accepted", "main=%s" % gs.main_state)
	expect(db.pick_dialogue("battle_return.liheng_victory").is_empty(), "still playable")
	end_case()

func _DLG_094() -> void:
	begin_case("DLG-094", "cancel before end does not write postSeen")
	reset_state("accepted", "girlMet", true, false)
	var run: Dictionary = await run_dialogue(db.pick_dialogue("battle_return.liheng_victory"), [], 0)
	expect(run.cancelled, "not cancelled")
	expect(not gs.is_flag_true("dlg.liheng.postSeen"), "postSeen committed")
	expect(pick_id("battle_return.liheng_victory") == "liheng_postbattle", "no longer selectable")
	end_case()

func _DLG_100() -> void:
	begin_case("DLG-100", "missing entry aborts without commit")
	reset_state("notAccepted", "locked", false)
	var before_state: String = JSON.stringify(gs.to_dict())
	var dlg := add_temp_dialogue("tmp_100", "tmp_100_missing", [])
	var run: Dictionary = await run_dialogue(dlg)
	db.dialogues.erase("tmp_100")
	expect(run.cancelled, "not cancelled")
	expect((run.lines as Array).is_empty(), "lines played")
	expect(JSON.stringify(gs.to_dict()) == before_state, "state changed")
	end_case()

func _DLG_101() -> void:
	begin_case("DLG-101", "missing next aborts without commit")
	reset_state("notAccepted", "locked", false)
	var nodes := [
		{"id": "tmp_101_a", "dialogue": "tmp_101", "speaker": "shenyan", "text": "a", "next": "tmp_101_missing",
			"conditions": [], "setFlags": {"dlg.tmp101": true},
			"effects": [{"type": "questEvent", "quest": "main.zhouCommission", "event": "accept"}]},
	]
	var dlg := add_temp_dialogue("tmp_101", "tmp_101_a", nodes)
	var run: Dictionary = await run_dialogue(dlg)
	remove_temp_dialogue("tmp_101", nodes)
	expect(run.cancelled, "not cancelled")
	expect(gs.main_state == "notAccepted", "main=%s" % gs.main_state)
	expect(not gs.flags.has("dlg.tmp101"), "flag committed")
	end_case()

func _DLG_102() -> void:
	begin_case("DLG-102", "cross-dialogue choice aborts before foreign effects")
	reset_state("accepted", "girlMet", false)
	var nodes := [
		{"id": "tmp_102_a", "dialogue": "tmp_102", "speaker": "shenyan", "text": "a",
			"conditions": [], "setFlags": {}, "effects": [],
			"choices": [{"id": "tmp_102_c1", "text": "go", "next": "lpb_04", "conditions": []}]},
	]
	var dlg := add_temp_dialogue("tmp_102", "tmp_102_a", nodes)
	var run: Dictionary = await run_dialogue(dlg, [0])
	remove_temp_dialogue("tmp_102", nodes)
	expect(run.cancelled, "not cancelled")
	expect((run.battles as Array).is_empty(), "battle requested: %s" % [run.battles])
	expect(not battle_effect(run, "liheng"), "foreign effect committed")
	end_case()

func _DLG_103() -> void:
	begin_case("DLG-103", "unknown interaction point returns empty")
	var picked: Dictionary = db.pick_dialogue("village.unknown")
	expect(picked.is_empty(), "pick=%s" % picked)
	end_case()

func _DLG_104() -> void:
	begin_case("DLG-104", "unrecognized condition is false")
	expect(not gs.conditions_ok([{"bogus": true}]), "unknown op true")
	expect(not gs.conditions_ok([{"all": [{"bogus": true}]}]), "all unknown op true")
	expect(not gs.conditions_ok([{"any": [{"bogus": true}]}]), "any unknown op true")
	expect(not gs.conditions_ok([{"not": {"bogus": true}}]), "not unknown op true")
	end_case()

func _DLG_105() -> void:
	begin_case("DLG-105", "missing/invalid dialogue data fails safely")
	var missing: bool = db.load_from_path("res://definitely_missing_dialogue.json")
	var empty: bool = db.load_from_text("")
	var broken: bool = db.load_from_text("{")
	var old_schema: bool = db.load_from_text('{"schemaVersion":2,"nodes":[],"dialogues":[]}')
	var empty_pick: Dictionary = db.pick_dialogue("village.zhoubo")
	var restored: bool = db.reload()
	expect(not missing, "missing file loaded")
	expect(not empty, "empty text loaded")
	expect(not broken, "broken JSON loaded")
	expect(not old_schema, "schemaVersion 2 loaded")
	expect(empty_pick.is_empty(), "pick after failure=%s" % empty_pick)
	expect(restored, "reload failed")
	expect(not db.pick_dialogue("village.zhoubo").is_empty(), "pick after reload empty")
	end_case()

# ================================================================== BAT

func _BAT_001() -> void:
	begin_case("BAT-001", "entry loads data, resets qi, records snapshot")
	var b := BattleLogic.new(65, 1)
	expect(b.hp == 65 and b.potions == 1, "snapshot=%d/%d" % [b.hp, b.potions])
	expect(b.entry_hp == 65 and b.entry_potions == 1, "entry snapshot")
	expect(b.qi == BattleData.PLAYER_START_QI, "qi=%d" % b.qi)
	expect(b.enemy_hp == BattleData.ENEMY_MAX_HP, "enemy hp")
	expect(BattleData.PLAYER_MAX_HP == 100 and BattleData.PLAYER_ATTACK == 12 and BattleData.PLAYER_DEFENSE == 4, "player stats")
	expect(BattleData.ENEMY_ATTACK == 14 and BattleData.ENEMY_DEFENSE == 2, "enemy stats")
	expect(b.round_no == 0 and not b.won and not b.lost, "initial flags")
	end_case()

func _BAT_002() -> void:
	begin_case("BAT-002", "four legal actions resolve one round each")
	var a := BattleLogic.new()
	var ra := a.take_turn("attack")
	var s := BattleLogic.new()
	var rs := s.take_turn("skill")
	var g := BattleLogic.new()
	var rg := g.take_turn("guard")
	var p := BattleLogic.new()
	p.hp = 50
	p.potions = 1
	var rp := p.take_turn("potion")
	expect(ra.ok and ra.player_damage == 10 and a.qi == 25 and a.enemy_hp == 90 and a.round_no == 1, "attack")
	expect(rs.ok and rs.player_damage == 20 and s.qi == 10 and s.enemy_hp == 80 and s.round_no == 1, "skill")
	expect(rg.ok and rg.guarded and g.qi == 28 and g.round_no == 1, "guard")
	expect(rp.ok and rp.heal == 35 and p.potions == 0 and p.round_no == 1, "potion")
	expect(ra.enemy_action == "attack" and rs.enemy_action == "attack", "enemy turn")
	end_case()

func _BAT_003() -> void:
	begin_case("BAT-003", "round flow: player -> enemy -> clear guard")
	var b := BattleLogic.new()
	var r := b.take_turn("attack")
	expect(r.ok and b.enemy_hp == 90, "enemy hp=%d" % b.enemy_hp)
	expect(b.hp == 90, "player hp=%d" % b.hp)
	expect(r.enemy_action == "attack", "enemy action=%s" % r.enemy_action)
	expect(not b.guarding, "guarding not cleared")
	expect(b.round_no == 1, "round=%d" % b.round_no)
	end_case()

func _BAT_004() -> void:
	begin_case("BAT-004", "damage check values 10/20/10/0/31/15")
	var b := BattleLogic.new()
	expect(BattleLogic.damage_formula(12, 1.0, 2) == 10, "player attack")
	expect(BattleLogic.damage_formula(12, 1.8, 2) == 20, "player skill")
	expect(BattleLogic.damage_formula(14, 1.0, 4) == 10, "enemy attack")
	expect(b.enemy_action_damage("charge") == 0, "enemy charge")
	expect(b.enemy_action_damage("heavy") == 31, "enemy heavy")
	b.guarding = true
	expect(b.enemy_action_damage("heavy") == 15, "guarded heavy")
	end_case()

func _BAT_005() -> void:
	begin_case("BAT-005", "qi is capped at 30")
	var a := BattleLogic.new()
	a.qi = 28
	a.take_turn("attack")
	var g := BattleLogic.new()
	g.qi = 26
	g.take_turn("guard")
	expect(a.qi == 30, "attack qi=%d" % a.qi)
	expect(g.qi == 30, "guard qi=%d" % g.qi)
	end_case()

func _BAT_006() -> void:
	begin_case("BAT-006", "skill with qi<10 is invalid and changes nothing")
	var b := BattleLogic.new()
	b.qi = 9
	var before := [b.hp, b.qi, b.potions, b.enemy_hp, b.enemy_step, b.round_no, b.log_lines.size()]
	var r := b.take_turn("skill")
	expect(not r.ok and r.reason == "内力不足", "result=%s" % r)
	expect([b.hp, b.qi, b.potions, b.enemy_hp, b.enemy_step, b.round_no, b.log_lines.size()] == before, "state changed")
	expect(not b.available_actions().get("skill", true), "skill shown enabled")
	end_case()

func _BAT_007() -> void:
	begin_case("BAT-007", "potion with zero stock is invalid")
	var b := BattleLogic.new()
	b.hp = 50
	b.potions = 0
	var before := [b.hp, b.qi, b.potions, b.enemy_hp, b.enemy_step, b.round_no]
	var r := b.take_turn("potion")
	expect(not r.ok and r.reason == "没有回复药", "result=%s" % r)
	expect([b.hp, b.qi, b.potions, b.enemy_hp, b.enemy_step, b.round_no] == before, "state changed")
	end_case()

func _BAT_008() -> void:
	begin_case("BAT-008", "potion at full hp is invalid")
	var b := BattleLogic.new()
	var before := [b.hp, b.potions, b.round_no, b.enemy_step]
	var r := b.take_turn("potion")
	expect(not r.ok and r.reason == "气血已满", "result=%s" % r)
	expect([b.hp, b.potions, b.round_no, b.enemy_step] == before, "state changed")
	end_case()

func _BAT_009() -> void:
	begin_case("BAT-009", "potion heals 35 and caps at 100")
	var a := BattleLogic.new()
	a.hp = 80
	a.potions = 1
	var ra := a.take_turn("potion")
	var b := BattleLogic.new()
	b.hp = 50
	b.potions = 1
	var rb := b.take_turn("potion")
	expect(ra.heal == 20 and a.potions == 0 and a.hp == 90, "80 -> heal %d, hp %d" % [ra.heal, a.hp])
	expect(rb.heal == 35 and b.potions == 0 and b.hp == 75, "50 -> heal %d, hp %d" % [rb.heal, b.hp])
	end_case()

func _BAT_010() -> void:
	begin_case("BAT-010", "guard lasts one round, no stacking")
	var b := BattleLogic.new()
	var r1 := b.take_turn("guard")
	var r2 := b.take_turn("attack")
	expect(r1.enemy_damage == 5, "guarded damage=%d" % r1.enemy_damage)
	expect(r2.enemy_damage == 10, "next damage=%d" % r2.enemy_damage)
	expect(not b.guarding, "guard persisted")
	expect(b.round_no == 2, "round=%d" % b.round_no)
	end_case()

func _BAT_011() -> void:
	begin_case("BAT-011", "enemy cycle is 普攻/普攻/蓄力/重击 twice")
	var b := BattleLogic.new()
	var actions: Array[String] = []
	var damages: Array[int] = []
	for i in 8:
		var action := "guard" if b.enemy_next_action() == "heavy" else "attack"
		var r := b.take_turn(action)
		actions.append(str(r.enemy_action))
		damages.append(int(r.enemy_damage))
	var expected_actions: Array[String] = ["attack", "attack", "charge", "heavy", "attack", "attack", "charge", "heavy"]
	expect(actions == expected_actions, "actions=%s" % [actions])
	expect(damages == [10, 10, 0, 15, 10, 10, 0, 15], "damages=%s" % [damages])
	expect(not b.is_over(), "battle ended early")
	end_case()

func _BAT_012() -> void:
	begin_case("BAT-012", "charge telegraphed with zero damage and exact log")
	var b := BattleLogic.new()
	b.take_turn("attack")
	b.take_turn("attack")
	var hp_before := b.hp
	var r := b.take_turn("attack")
	var charge_index := b.log_lines.find(BattleData.ENEMY_CHARGE_LOG)
	expect(str(r.enemy_action) == "charge", "action=%s" % r.enemy_action)
	expect(int(r.enemy_damage) == 0 and b.hp == hp_before, "damage=%d hp=%d" % [r.enemy_damage, b.hp])
	expect(b.enemy_charging, "charging flag off")
	expect(charge_index >= 0, "charge log missing: %s" % [b.log_lines])
	expect(b.log_lines[charge_index] == "厉横握紧刀柄，正在蓄力！", "log text")
	end_case()

func _BAT_013() -> void:
	begin_case("BAT-013", "heavy follows charge and clears marker")
	var b := BattleLogic.new()
	b.take_turn("attack")
	b.take_turn("attack")
	b.take_turn("attack")
	var r := b.take_turn("attack")
	expect(str(r.enemy_action) == "heavy", "action=%s" % r.enemy_action)
	expect(int(r.enemy_damage) == 31, "damage=%d" % r.enemy_damage)
	expect(not b.enemy_charging, "marker still on")
	expect(b.enemy_next_action() == "attack", "next=%s" % b.enemy_next_action())
	end_case()

func _BAT_014() -> void:
	begin_case("BAT-014", "guarding a heavy takes 15")
	var b := BattleLogic.new()
	b.take_turn("attack")
	b.take_turn("attack")
	b.take_turn("attack")
	var hp_before := b.hp
	var r := b.take_turn("guard")
	expect(int(r.enemy_damage) == 15, "damage=%d" % r.enemy_damage)
	expect(b.hp == hp_before - 15, "hp=%d" % b.hp)
	expect(not b.enemy_charging, "marker still on")
	end_case()

func _BAT_015() -> void:
	begin_case("BAT-015", "killing blow skips enemy action")
	var b := BattleLogic.new()
	b.enemy_hp = 10
	var step_before := b.enemy_step
	var r := b.take_turn("attack")
	expect(r.ok and r.enemy_dead and r.won, "result=%s" % r)
	expect(b.enemy_hp == 0 and b.enemy_step == step_before, "enemy acted")
	expect(str(r.enemy_action) == "" and int(r.enemy_damage) == 0, "enemy action=%s" % r.enemy_action)
	expect(b.won and not b.lost, "flags")
	end_case()

func _BAT_016() -> void:
	begin_case("BAT-016", "victory sets one flag, not deliver, keeps position")
	reset_state("accepted", "girlMet", false)
	gs.player_position = Vector3(4.0, 0.0, 9.0)
	var pos_before: Vector3 = gs.player_position
	var b := BattleLogic.new()
	b.enemy_hp = 10
	b.take_turn("attack")
	var first: bool = gs.mark_battle_won()
	var second: bool = gs.mark_battle_won()
	expect(b.won, "battle not won")
	expect(first and not second, "mark_battle_won not idempotent")
	expect(gs.is_flag_true("battle.liheng.won"), "flag missing")
	expect(gs.main_state == "accepted", "main=%s" % gs.main_state)
	expect(gs.player_position.is_equal_approx(pos_before), "position changed")
	expect(pick_id("battle_return.liheng_victory") == "liheng_postbattle", "postbattle not selectable")
	end_case()

func _BAT_017() -> void:
	begin_case("BAT-017", "second victory does not re-award")
	reset_state("accepted", "ready", true)
	gs.side_receipt = null
	var second: bool = gs.mark_battle_won()
	var receipt_after: Variant = gs.side_receipt
	gs.save_game(SAVE_BAT)
	reset_state("notAccepted", "locked", false)
	gs.load_game(SAVE_BAT)
	expect(not second, "second mark returned true")
	expect(receipt_after == null, "receipt changed")
	expect(gs.is_flag_true("battle.liheng.won"), "flag lost after reload")
	expect(gs.flags.get("reward.bambooCompanions", null) == null, "unexpected reward flag")
	end_case()

func _BAT_018() -> void:
	begin_case("BAT-018", "defeat when hp<=0, no victory flag")
	reset_state("accepted", "girlMet", false)
	var b := BattleLogic.new()
	b.hp = 1
	var r := b.take_turn("guard")
	expect(r.player_dead and b.lost and not b.won, "result=%s" % r)
	expect(not gs.is_flag_true("battle.liheng.won"), "victory flag set")
	end_case()

func _BAT_019() -> void:
	begin_case("BAT-019", "rematch fully restores and resets enemy")
	var b := BattleLogic.new(65, 1)
	b.hp = 1
	b.enemy_step = 0
	b.take_turn("guard")
	expect(b.lost, "not lost")
	b.restart_from_snapshot()
	expect(b.hp == 65 and b.potions == 1, "player snapshot=%d/%d" % [b.hp, b.potions])
	expect(b.qi == BattleData.PLAYER_START_QI, "qi=%d" % b.qi)
	expect(b.enemy_hp == 100 and b.enemy_step == 0, "enemy=%d step=%d" % [b.enemy_hp, b.enemy_step])
	expect(b.round_no == 0 and not b.won and not b.lost and not b.enemy_charging, "state not reset")
	expect(b.can_act("attack"), "cannot act after rematch")
	expect(not gs.is_flag_true("battle.liheng.won"), "victory flag set")
	end_case()

func _BAT_020() -> void:
	begin_case("BAT-020", "return restores snapshot and battle can retrigger")
	reset_state("accepted", "girlMet", false)
	gs.player_position = Vector3(2.0, 0.0, 7.0)
	var pos_before: Vector3 = gs.player_position
	var b := BattleLogic.new(55, 1)
	b.hp = 1
	b.take_turn("guard")
	expect(b.lost, "not lost")
	b.restore_snapshot()
	expect(b.hp == 55 and b.potions == 1 and b.qi == BattleData.PLAYER_START_QI, "snapshot not restored")
	expect(not gs.is_flag_true("battle.liheng.won"), "victory flag set")
	expect(gs.player_position.is_equal_approx(pos_before), "position changed")
	expect(pick_id("bamboo.liheng") == "liheng_prebattle", "prebattle not selectable")
	end_case()

func _BAT_021() -> void:
	begin_case("BAT-021", "no saving during battle")
	reset_state("accepted", "girlMet", false)
	sm.delete_save(SAVE_BAT)
	gs.set_in_battle(true)
	var blocked: Dictionary = gs.save_game(SAVE_BAT)
	var exists_during: bool = sm.has_save(SAVE_BAT)
	gs.set_in_battle(false)
	var allowed: Dictionary = gs.save_game(SAVE_BAT)
	expect(not blocked.get("ok", true), "save not blocked: %s" % blocked)
	expect(blocked.get("blocked", false), "blocked flag missing")
	expect(not exists_during, "file written during battle")
	expect(allowed.get("ok", false), "save after battle failed: %s" % allowed)
	end_case()

func _BAT_022() -> void:
	begin_case("BAT-022", "two scripted strategies both win (design comparison)")
	var guard_run := BattleLogic.new()
	var guard_rounds := 0
	while not guard_run.is_over() and guard_rounds < 40:
		guard_rounds += 1
		var action := "attack"
		var skill_damage := guard_run.player_attack_damage("skill")
		var attack_damage := guard_run.player_attack_damage("attack")
		# DQ-06: if this turn can kill, kill before considering guard.
		if guard_run.qi >= BattleData.SKILL_QI_COST and guard_run.enemy_hp <= skill_damage:
			action = "skill"
		elif guard_run.enemy_hp <= attack_damage:
			action = "attack"
		elif guard_run.enemy_next_action() == "heavy":
			action = "guard"
		elif guard_run.qi >= BattleData.SKILL_QI_COST:
			action = "skill"
		guard_run.take_turn(action)
	var hard_run := BattleLogic.new()
	var hard_rounds := 0
	while not hard_run.is_over() and hard_rounds < 40:
		hard_rounds += 1
		var action := "attack"
		if hard_run.qi >= BattleData.SKILL_QI_COST:
			action = "skill"
		hard_run.take_turn(action)
	print("     BAT-022 actuals: guard-style %d rounds / %d hp; hard-style %d rounds / %d hp" %
		[guard_rounds, guard_run.hp, hard_rounds, hard_run.hp])
	expect(guard_run.won, "guard strategy lost")
	expect(guard_rounds == 8 and guard_run.hp == 45, "guard strategy=%d rounds / %d hp (want 8/45)" % [guard_rounds, guard_run.hp])
	expect(hard_run.won, "hard strategy lost")
	expect(hard_rounds == 7 and hard_run.hp == 29, "hard strategy=%d rounds / %d hp (want 7/29)" % [hard_rounds, hard_run.hp])
	end_case()

# ================================================================== SAV

func _SAV_001() -> void:
	begin_case("SAV-001", "save/load roundtrip of position/quests/items/flags")
	sm.delete_save(SAVE_TMP)
	sample_save(SAVE_TMP)
	var saved: Dictionary = gs.to_dict()
	gs.reset_new_game()
	var loaded: Dictionary = gs.load_game(SAVE_TMP)
	expect(loaded.get("ok", false), "load failed: %s" % loaded)
	expect(JSON.stringify(gs.to_dict()) == JSON.stringify(saved), "state not identical")
	expect(gs.player_position.is_equal_approx(Vector3(1.5, -2.0, 3.25)), "position=%s" % gs.player_position)
	expect(gs.main_state == "accepted" and gs.side_state == "girlMet", "quests")
	expect(gs.potions == 1, "potions=%d" % gs.potions)
	expect(gs.is_flag_true("battle.liheng.won"), "victory flag")
	end_case()

func _SAV_002() -> void:
	begin_case("SAV-002", "cold start: second process reads the save")
	sm.delete_save(SAVE_002)
	sample_save(SAVE_002)
	var exe := OS.get_executable_path()
	var project_dir := ProjectSettings.globalize_path("res://")
	var output: Array = []
	var code := OS.execute(exe, [
		"--headless", "--path", project_dir,
		"-s", "res://tests/run_tests.gd", "--", SAVE_002_TOKEN,
	], output, true)
	var text := ""
	for chunk: Variant in output:
		text += str(chunk)
	expect(code == 0, "child exit=%d output=%s" % [code, text])
	expect(text.contains("SAV-002 child ok"), "child marker missing: %s" % text)
	end_case()

func _run_sav002_child() -> void:
	sm = root.get_node("SaveManager")
	gs = root.get_node("GameState")
	var res: Dictionary = sm.load_state(SAVE_002)
	var ok: bool = res.get("ok", false)
	if ok:
		gs.apply_dict(res.data)
		ok = gs.hp == 77 and gs.potions == 1
		ok = ok and gs.main_state == "accepted" and gs.side_state == "girlMet"
		ok = ok and gs.is_flag_true("battle.liheng.won")
		ok = ok and gs.player_position.is_equal_approx(Vector3(1.5, -2.0, 3.25))
	print("SAV-002 child ok" if ok else "SAV-002 child failed")
	quit(0 if ok else 1)

func _SAV_003() -> void:
	begin_case("SAV-003", "new save carries current version")
	sm.delete_save(SAVE_TMP)
	sample_save(SAVE_TMP)
	var res: Dictionary = sm.load_state(SAVE_TMP)
	var raw := read_json(SAVE_TMP)
	expect(res.get("ok", false), "load failed")
	expect(typeof(raw.get("version", null)) in [TYPE_INT, TYPE_FLOAT], "version type=%s" % typeof(raw.get("version")))
	expect(int(raw.get("version", -1)) == int(sm.VERSION), "version=%s" % raw.get("version"))
	expect(int(res.get("version", -1)) == int(sm.VERSION), "result version")
	end_case()

func _SAV_004() -> void:
	begin_case("SAV-004", "old version is rejected without crash")
	sm.delete_save(SAVE_TMP)
	sample_save(SAVE_TMP)
	var raw := read_json(SAVE_TMP)
	raw["version"] = 0
	write_json(SAVE_TMP, raw)
	var res: Dictionary = sm.load_state(SAVE_TMP)
	expect(not res.get("ok", true), "old save accepted")
	expect(str(res.get("error", "")).contains("不支持"), "error=%s" % res.get("error"))
	expect(not gs.load_game(SAVE_TMP).get("ok", true), "GameState accepted old save")
	end_case()

func _SAV_005() -> void:
	begin_case("SAV-005", "future version is rejected with explicit reason")
	sm.delete_save(SAVE_TMP)
	sample_save(SAVE_TMP)
	var raw := read_json(SAVE_TMP)
	raw["version"] = int(sm.VERSION) + 1
	write_json(SAVE_TMP, raw)
	var res: Dictionary = sm.load_state(SAVE_TMP)
	expect(not res.get("ok", true), "future save accepted")
	expect(str(res.get("error", "")).contains("过新"), "error=%s" % res.get("error"))
	end_case()

func _SAV_006() -> void:
	begin_case("SAV-006", "missing version field is rejected")
	sm.delete_save(SAVE_TMP)
	sample_save(SAVE_TMP)
	var raw := read_json(SAVE_TMP)
	raw.erase("version")
	write_json(SAVE_TMP, raw)
	var res: Dictionary = sm.load_state(SAVE_TMP)
	expect(not res.get("ok", true), "missing version accepted")
	expect(str(res.get("error", "")).contains("版本"), "error=%s" % res.get("error"))
	end_case()

func _SAV_007() -> void:
	begin_case("SAV-007", "truncated saves are rejected")
	sm.delete_save(SAVE_TMP)
	sample_save(SAVE_TMP)
	var text := read_raw(SAVE_TMP)
	var ok := true
	for cut: int in [text.length() / 2, text.length() / 4, maxi(1, text.length() - 5)]:
		write_raw(SAVE_TMP, text.substr(0, cut))
		ok = ok and not sm.load_state(SAVE_TMP).get("ok", true)
	expect(ok, "a truncated save was accepted")
	expect(gs.load_game(SAVE_TMP).get("ok", true) == false, "GameState accepted truncated save")
	end_case()

func _SAV_008() -> void:
	begin_case("SAV-008", "illegal JSON saves are rejected")
	sm.delete_save(SAVE_TMP)
	var ok := true
	for sample: String in ["{", '{"a":', "[1,2", "not-json", '"unterminated']:
		write_raw(SAVE_TMP, sample)
		ok = ok and not sm.load_state(SAVE_TMP).get("ok", true)
	expect(ok, "an illegal JSON save was accepted")
	end_case()

func _SAV_009() -> void:
	begin_case("SAV-009", "missing fields: required rejected, player defaults")
	sm.delete_save(SAVE_TMP)
	sample_save(SAVE_TMP)
	var base := read_json(SAVE_TMP)
	var ok := true

	var no_flags := base.duplicate(true)
	no_flags.erase("flags")
	write_json(SAVE_TMP, no_flags)
	ok = ok and not sm.load_state(SAVE_TMP).get("ok", true)

	var no_quests := base.duplicate(true)
	no_quests.erase("quests")
	write_json(SAVE_TMP, no_quests)
	ok = ok and not sm.load_state(SAVE_TMP).get("ok", true)

	var no_version := base.duplicate(true)
	no_version.erase("version")
	write_json(SAVE_TMP, no_version)
	ok = ok and not sm.load_state(SAVE_TMP).get("ok", true)

	var no_player := base.duplicate(true)
	no_player.erase("player")
	write_json(SAVE_TMP, no_player)
	reset_state("notAccepted", "locked", false)
	gs.player_position = Vector3(9.0, 0.0, 9.0)
	var loaded_no_player: Dictionary = gs.load_game(SAVE_TMP)
	ok = ok and loaded_no_player.get("ok", false)
	ok = ok and gs.hp == 100 and gs.potions == 2
	ok = ok and gs.player_position.is_equal_approx(Vector3(0.0, 0.0, 18.0)) and gs.player_facing == 0

	for field: String in ["hp", "potions", "position", "facing"]:
		var partial := base.duplicate(true)
		(partial["player"] as Dictionary).erase(field)
		write_json(SAVE_TMP, partial)
		reset_state("notAccepted", "locked", false)
		gs.hp = 1
		gs.potions = 0
		gs.player_position = Vector3(9.0, 0.0, 9.0)
		gs.player_facing = 5
		var r: Dictionary = gs.load_game(SAVE_TMP)
		ok = ok and r.get("ok", false)
		match field:
			"hp": ok = ok and gs.hp == 100
			"potions": ok = ok and gs.potions == 2
			"position": ok = ok and gs.player_position.is_equal_approx(Vector3(0.0, 0.0, 18.0))
			"facing": ok = ok and gs.player_facing == 0
	expect(ok, "missing-field handling failed")
	end_case()

func _SAV_010() -> void:
	begin_case("SAV-010", "type errors are rejected safely")
	sm.delete_save(SAVE_TMP)
	sample_save(SAVE_TMP)
	var base := read_json(SAVE_TMP)
	var variants: Array[Dictionary] = []
	for value: Variant in ["1", [1]]:
		var v := base.duplicate(true)
		v["version"] = value
		variants.append(v)
	var flag_bad := base.duplicate(true)
	(flag_bad["flags"] as Dictionary)["battle.liheng.won"] = "true"
	variants.append(flag_bad)
	for value: Variant in [123, {"state": "accepted"}]:
		var v := base.duplicate(true)
		(v["quests"] as Dictionary)["main.zhouCommission"] = value
		variants.append(v)
	var side_bad := base.duplicate(true)
	((side_bad["quests"] as Dictionary)["side"] as Dictionary)["state"] = 5
	variants.append(side_bad)
	var player_bad := base.duplicate(true)
	player_bad["player"] = "bad"
	variants.append(player_bad)
	for entry: Array in [["hp", "77"], ["potions", [-1]], ["position", "0,0,0"], ["facing", "north"]]:
		var v := base.duplicate(true)
		(v["player"] as Dictionary)[str(entry[0])] = entry[1]
		variants.append(v)
	var ok := true
	for v: Dictionary in variants:
		write_json(SAVE_TMP, v)
		ok = ok and not sm.load_state(SAVE_TMP).get("ok", true)
	expect(ok, "%d/%d bad-type saves accepted" % [variants.size(), variants.size()])
	expect(not gs.load_game(SAVE_TMP).get("ok", true), "GameState accepted bad-type save")
	end_case()

func _SAV_011() -> void:
	begin_case("SAV-011", "empty save file is rejected")
	sm.delete_save(SAVE_TMP)
	write_raw(SAVE_TMP, "")
	var res: Dictionary = sm.load_state(SAVE_TMP)
	expect(not res.get("ok", true), "empty file accepted")
	expect(not res.get("missing", false), "empty file treated as missing")
	end_case()

func _SAV_012() -> void:
	begin_case("SAV-012", "missing save is reported without loading")
	sm.delete_save(SAVE_TMP)
	reset_state("accepted", "girlMet", true)
	var before: Dictionary = gs.to_dict()
	var res: Dictionary = sm.load_state(SAVE_TMP)
	var game_res: Dictionary = gs.load_game(SAVE_TMP)
	expect(not res.get("ok", true), "missing save ok")
	expect(res.get("missing", false), "missing flag absent")
	expect(not game_res.get("ok", true), "GameState accepted missing save")
	expect(JSON.stringify(gs.to_dict()) == JSON.stringify(before), "state changed on missing save")
	end_case()

func _SAV_013() -> void:
	begin_case("SAV-013", "failed load leaves backup intact")
	sm.delete_save(SAVE_TMP)
	sample_save(SAVE_TMP)
	gs.hp = 55
	gs.save_game(SAVE_TMP)
	var bak := SAVE_TMP + ".bak"
	var bak_before := read_raw(bak)
	write_raw(SAVE_TMP, "{broken")
	var res: Dictionary = sm.load_state(SAVE_TMP)
	expect(not res.get("ok", true), "corrupt save accepted")
	expect(sm.has_backup(SAVE_TMP), "backup missing")
	expect(read_raw(bak) == bak_before, "backup modified")
	expect(sm.load_state(bak).get("ok", false), "backup not loadable")
	expect(str(res.get("error", "")) != "", "no perceivable error")
	end_case()

func _SAV_014() -> void:
	begin_case("SAV-014", "outside battle saves victory flag and potions")
	sm.delete_save(SAVE_BAT)
	reset_state("accepted", "girlMet", true, false)
	gs.potions = 1
	gs.set_in_battle(false)
	var saved: Dictionary = gs.save_game(SAVE_BAT)
	gs.reset_new_game()
	var loaded: Dictionary = gs.load_game(SAVE_BAT)
	expect(saved.get("ok", false), "outside save failed")
	expect(loaded.get("ok", false), "load failed")
	expect(gs.is_flag_true("battle.liheng.won"), "flag not restored")
	expect(gs.potions == 1, "potions=%d" % gs.potions)
	gs.set_in_battle(true)
	var blocked: Dictionary = gs.save_game(SAVE_BAT)
	gs.set_in_battle(false)
	expect(not blocked.get("ok", true) and blocked.get("blocked", false), "in-battle save not blocked")
	end_case()

# ================================================================== CH2

func _CH2_DLG_001() -> void:
	begin_case("CH2-DLG-001", "multi-file dialogue load merges v1 + chapter 2")
	expect(db.load_error == "", "load_error=%s" % db.load_error)
	expect(db.validate().is_empty(), "validate=%s" % [db.validate()])
	expect(db.dialogues.size() == 83, "dialogues=%d" % db.dialogues.size())
	expect(db.nodes.size() == 229, "nodes=%d" % db.nodes.size())
	expect(db.dialogues.has("zhou_main_offer") and db.dialogues.has("ch2_zhou_offer"), "dialogue ids")
	expect(db.nodes.has("zid_01") and db.nodes.has("ch2_zc_01"), "node ids")
	var chapter2_dialogues := 0
	var chapter2_nodes := 0
	for id: String in db.dialogues:
		if id.begins_with("ch2_"):
			chapter2_dialogues += 1
	for id: String in db.nodes:
		if id.begins_with("ch2_"):
			chapter2_nodes += 1
	expect(chapter2_dialogues == 32, "chapter2 dialogues=%d" % chapter2_dialogues)
	expect(chapter2_nodes == 102, "chapter2 nodes=%d" % chapter2_nodes)
	var points: Dictionary = db.db.get("interactionPoints", {})
	var zhou: Dictionary = points.get("village.zhoubo", {})
	var zhou_ids: Array = zhou.get("dialogues", [])
	var monk: Dictionary = points.get("village.mingcheng", {})
	var monk_ids: Array = monk.get("dialogues", [])
	expect(zhou_ids.has("ch2_zhou_offer_companions") and zhou_ids.has("zhou_idle"), "zhou list")
	expect(monk_ids.has("ch2_tea_offer") and monk_ids.has("monk_idle"), "monk list")
	expect(zhou_ids.find("bc_finale_replay") > zhou_ids.find("ch2_zhou_epilogue"), "replay order")
	expect(points.has("gate.liheng") and points.has("yiting.gesancheng"), "new points")
	expect(points.has("battle_return.ch2_thug_victory"), "ch2 battle-return point")
	end_case()

func _CH2_DLG_002() -> void:
	begin_case("CH2-DLG-002", "duplicate node/dialogue ids across files are errors")
	var conflict: bool = not db.load_from_files([
		"res://data/dialogue-v1.json",
		"res://data/dialogue-v1.json",
	])
	expect(conflict, "duplicate node ids were accepted")
	expect(db.load_error.contains("duplicate"), "load_error=%s" % db.load_error)
	expect(db.dialogues.is_empty() and db.nodes.is_empty(), "partial graph kept")
	var dlg_conflict: bool = not db.load_from_text(
		'{"schemaVersion":1,"nodes":[],"dialogues":[{"id":"dup","entry":""},{"id":"dup","entry":""}]}')
	expect(dlg_conflict, "duplicate dialogue ids were accepted")
	expect(db.load_error.contains("duplicate dialogue id"), "load_error=%s" % db.load_error)
	expect(db.reload(), "reload after conflict failed")
	expect(db.dialogues.size() == 83, "reload dialogues=%d" % db.dialogues.size())
	end_case()

func _CH2_DLG_003() -> void:
	begin_case("CH2-DLG-003", "all battle_return.* points skip the fallback requirement")
	expect(db.validate().is_empty(), "baseline validate=%s" % [db.validate()])
	var points: Dictionary = db.db["interactionPoints"]
	points["battle_return.ch2_test"] = {"scene": "battle_return", "dialogues": []}
	expect(db.validate().is_empty(), "battle_return empty list rejected: %s" % [db.validate()])
	points["village.ch2_test"] = {"scene": "village", "dialogues": []}
	var errors: Array[String] = db.validate()
	var rejected := false
	for err: String in errors:
		if err.contains("village.ch2_test") and err.contains("fallback"):
			rejected = true
	expect(rejected, "normal point without fallback was accepted: %s" % [errors])
	points.erase("battle_return.ch2_test")
	points.erase("village.ch2_test")
	expect(db.validate().is_empty(), "cleanup validate=%s" % [db.validate()])
	end_case()

func _CH2_DLG_004() -> void:
	begin_case("CH2-DLG-004", "chapter2 data exposes expected events/battles")
	expect(str(db.get_dialogue("ch2_zhou_offer").get("entry", "")) == "ch2_zo_01", "offer entry")
	expect(str(db.get_node_data("ch2_zc_06").get("dialogue", "")) == "ch2_zhou_offer_companions", "companions end")
	var accept := false
	var hear := false
	var recover := false
	var finish := false
	var battles: Dictionary = {}
	for nid: String in db.nodes:
		for effect: Variant in db.nodes[nid].get("effects", []):
			if typeof(effect) != TYPE_DICTIONARY:
				continue
			if str(effect.get("type", "")) == "questEvent":
				match str(effect.get("event", "")):
					"accept": accept = true
					"hearLiheng": hear = true
					"recoverPack": recover = true
					"finish": finish = true
			elif str(effect.get("type", "")) == "startBattle":
				battles[str(effect.get("battleId", ""))] = true
	expect(accept and hear and recover and finish, "quest events")
	expect(battles.has("ch2_thug") and battles.has("ch2_gesancheng") and battles.has("ch2_liheng_spar"), "battles=%s" % [battles.keys()])
	expect(db.get_node_data("ch2_fn_09").get("setFlags", {}).has("dlg.ch2.lihengVouched"), "vouch flag")
	expect(db.get_node_data("ch2_tp_02").get("setFlags", {}).has("dlg.ch2.thugPostSeen"), "thug post flag")
	end_case()

func _CH2_DLG_005() -> void:
	begin_case("CH2-DLG-005", "ch2 battle-return dialogue is one-shot")
	reset_state("delivered", "completed", true, false)
	gs.flags["battle.ch2_thug.won"] = true
	expect(pick_id("battle_return.ch2_thug_victory") == "ch2_thug_postbattle", "pick=%s" % pick_id("battle_return.ch2_thug_victory"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("battle_return.ch2_thug_victory"))
	expect(gs.is_flag_true("dlg.ch2.thugPostSeen"), "post flag not committed")
	expect((run.effects as Array).is_empty(), "effects=%s" % [run.effects])
	expect(db.pick_dialogue("battle_return.ch2_thug_victory").is_empty(), "played twice")
	reset_state("delivered", "completed", true, false)
	expect(db.pick_dialogue("battle_return.ch2_thug_victory").is_empty(), "played without win")
	expect(db.validate().is_empty(), "validate=%s" % [db.validate()])
	end_case()

func _CH2_DLG_006() -> void:
	begin_case("CH2-DLG-006", "gate prebattle requests battle ch2_thug")
	reset_state("delivered", "completed", true, false)
	gs.normalize()
	gs.dispatch_quest_event("main.ch2Herbs", "accept")
	expect(pick_id("gate.liheng") == "ch2_gate_prebattle_known", "pick=%s" % pick_id("gate.liheng"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"), [0])
	expect(battle_effect(run, "ch2_thug"), "startBattle ch2_thug missing")
	expect(run.battles == ["ch2_thug"], "battles=%s" % [run.battles])
	expect(gs.ch2_main_state == "accepted", "ch2 main=%s" % gs.ch2_main_state)
	expect(not gs.is_flag_true("battle.ch2_thug.won"), "victory flag set")
	end_case()

func _CH2_BAT_001() -> void:
	begin_case("CH2-BAT-001", "E1 ch2_thug stats, cycle and damage")
	var b := BattleLogic.new()
	expect(b.set_battle_id("ch2_thug"), "unknown battleId")
	expect(b.enemy_name == "药行打手", "name=%s" % b.enemy_name)
	expect(b.enemy_max_hp == 60 and b.enemy_attack == 12 and b.enemy_defense == 0, "stats")
	expect(b.enemy_cycle_actions() == ["attack", "attack", "charge", "heavy"], "cycle=%s" % [b.enemy_cycle_actions()])
	expect(b.player_attack_damage("attack") == 12, "player attack")
	expect(b.player_attack_damage("skill") == 22, "player skill")
	expect(b.enemy_action_damage("attack") == 8, "enemy attack")
	expect(b.enemy_action_damage("charge") == 0, "enemy charge")
	expect(b.enemy_action_damage("heavy") == 22, "enemy heavy")
	b.guarding = true
	expect(b.enemy_action_damage("heavy") == 11, "guarded heavy")
	b.guarding = false
	var actions: Array[String] = []
	for i in 4:
		var action := "guard" if b.enemy_next_action() == "heavy" else "attack"
		actions.append(str(b.take_turn(action).enemy_action))
	expect(actions == ["attack", "attack", "charge", "heavy"], "actions=%s" % [actions])
	expect(b.enemy_hp == 24, "enemy hp=%d" % b.enemy_hp)
	end_case()

func _CH2_BAT_002() -> void:
	begin_case("CH2-BAT-002", "E2 ch2_gesancheng stats, 7-beat cycle and damage")
	var b := BattleLogic.new()
	expect(b.set_battle_id("ch2_gesancheng"), "unknown battleId")
	expect(b.enemy_name == "葛三秤", "name=%s" % b.enemy_name)
	expect(b.enemy_max_hp == 120 and b.enemy_attack == 13 and b.enemy_defense == 2, "stats")
	expect(b.enemy_cycle_actions() == ["attack", "charge", "heavy", "attack", "attack", "charge", "heavy"], "cycle=%s" % [b.enemy_cycle_actions()])
	expect(b.player_attack_damage("attack") == 10, "player attack")
	expect(b.player_attack_damage("skill") == 20, "player skill")
	expect(b.enemy_action_damage("attack") == 9, "enemy attack")
	expect(b.enemy_action_damage("heavy") == 30, "enemy heavy")
	b.guarding = true
	expect(b.enemy_action_damage("heavy") == 15, "guarded heavy")
	b.guarding = false
	var actions: Array[String] = []
	for i in 7:
		var action := "guard" if b.enemy_next_action() == "heavy" else "attack"
		actions.append(str(b.take_turn(action).enemy_action))
	expect(actions == ["attack", "charge", "heavy", "attack", "attack", "charge", "heavy"], "actions=%s" % [actions])
	expect(b.enemy_hp == 70, "enemy hp=%d" % b.enemy_hp)
	end_case()

func _CH2_BAT_003() -> void:
	begin_case("CH2-BAT-003", "E3 ch2_liheng_spar stats, 3-beat cycle and damage")
	var b := BattleLogic.new()
	expect(b.set_battle_id("ch2_liheng_spar"), "unknown battleId")
	expect(b.enemy_max_hp == 100 and b.enemy_attack == 14 and b.enemy_defense == 2, "stats")
	expect(b.enemy_cycle_actions() == ["attack", "charge", "heavy"], "cycle=%s" % [b.enemy_cycle_actions()])
	expect(b.player_attack_damage("attack") == 10, "player attack")
	expect(b.player_attack_damage("skill") == 20, "player skill")
	expect(b.enemy_action_damage("attack") == 10, "enemy attack")
	expect(b.enemy_action_damage("heavy") == 31, "enemy heavy")
	expect(b.charge_log == BattleData.ENEMY_CHARGE_LOG, "spar charge log")
	b.guarding = true
	expect(b.enemy_action_damage("heavy") == 15, "guarded heavy")
	b.guarding = false
	var actions: Array[String] = []
	for i in 3:
		var action := "guard" if b.enemy_next_action() == "heavy" else "attack"
		actions.append(str(b.take_turn(action).enemy_action))
	expect(actions == ["attack", "charge", "heavy"], "actions=%s" % [actions])
	expect(not b.enemy_charging, "charge marker not cleared")
	end_case()

func _CH2_QUEST_001() -> void:
	begin_case("CH2-QUEST-001", "main.ch2Herbs state machine and guards")
	reset_state("accepted", "girlMet", true, false)
	gs.normalize()
	expect(gs.get_quest_state("main.ch2Herbs") == "locked", "unlocked before ch1 delivered")
	reset_state("delivered", "completed", true, false)
	gs.normalize()
	expect(gs.get_quest_state("main.ch2Herbs") == "available", "not available after delivery")
	expect(gs.dispatch_quest_event("main.ch2Herbs", "accept").applied, "accept not applied")
	expect(gs.ch2_main_state == "accepted", "state=%s" % gs.ch2_main_state)
	expect(not gs.dispatch_quest_event("main.ch2Herbs", "hearLiheng").applied, "hear without thug win")
	gs.flags["battle.ch2_thug.won"] = true
	expect(gs.dispatch_quest_event("main.ch2Herbs", "hearLiheng").applied, "hear not applied")
	expect(gs.ch2_main_state == "toldByLiheng", "state=%s" % gs.ch2_main_state)
	expect(gs.ch2_spar_state == "available" and gs.ch2_tea_state == "available", "sides not unlocked")
	expect(not gs.dispatch_quest_event("main.ch2Herbs", "recoverPack").applied, "recover without gesancheng win")
	gs.flags["battle.ch2_gesancheng.won"] = true
	expect(gs.dispatch_quest_event("main.ch2Herbs", "recoverPack").applied, "recover not applied")
	expect(gs.ch2_main_state == "stationCleared", "state=%s" % gs.ch2_main_state)
	expect(gs.dispatch_quest_event("main.ch2Herbs", "finish").applied, "finish not applied")
	expect(gs.ch2_main_state == "completed", "state=%s" % gs.ch2_main_state)
	reset_state("unknown", "completed", false)
	gs.normalize()
	expect(gs.get_quest_state("main.ch2Herbs") == "unknown", "unknown ch1 not propagated")
	end_case()

func _CH2_QUEST_002() -> void:
	begin_case("CH2-QUEST-002", "side.ch2Spar and side.ch2Tea transitions/rewards")
	reset_state("delivered", "completed", true, false)
	gs.normalize()
	gs.dispatch_quest_event("main.ch2Herbs", "accept")
	gs.flags["battle.ch2_thug.won"] = true
	gs.dispatch_quest_event("main.ch2Herbs", "hearLiheng")
	expect(gs.ch2_spar_state == "available" and gs.ch2_tea_state == "available", "sides not available")
	expect(not gs.dispatch_quest_event("side.ch2Spar", "settle").applied, "spar settle without win")
	gs.flags["battle.ch2_liheng_spar.won"] = true
	var spar: Dictionary = gs.dispatch_quest_event("side.ch2Spar", "settle")
	expect(spar.applied and spar.reward and gs.ch2_spar_state == "completed", "spar settle failed")
	expect(gs.ch2_spar_receipt == "ch2Spar.v1.reward", "spar receipt=%s" % gs.ch2_spar_receipt)
	expect(not gs.dispatch_quest_event("side.ch2Spar", "settle").applied, "spar settled twice")
	expect(not gs.dispatch_quest_event("side.ch2Tea", "talkLiheng").applied, "tea accepted too early")
	expect(gs.dispatch_quest_event("side.ch2Tea", "talkMonk").applied, "tea accept failed")
	expect(gs.ch2_tea_state == "accepted", "tea state=%s" % gs.ch2_tea_state)
	expect(gs.dispatch_quest_event("side.ch2Tea", "talkLiheng").applied, "tea told failed")
	expect(gs.ch2_tea_state == "told", "tea state=%s" % gs.ch2_tea_state)
	var tea: Dictionary = gs.dispatch_quest_event("side.ch2Tea", "talkMonk")
	expect(tea.applied and tea.reward and gs.ch2_tea_state == "completed", "tea complete failed")
	expect(gs.ch2_tea_receipt == "ch2Tea.v1.reward", "tea receipt=%s" % gs.ch2_tea_receipt)
	expect(not gs.dispatch_quest_event("side.ch2Tea", "talkMonk").applied, "tea completed twice")
	end_case()

func _CH2_SAVE_001() -> void:
	begin_case("CH2-SAVE-001", "version 1 save loads and gets ch2 defaults")
	sm.delete_save(SAVE_TMP)
	var v1_save := {
		"version": 1,
		"flags": {"battle.liheng.won": true, "dlg.liheng.postSeen": false},
		"quests": {
			"main.zhouCommission": "delivered",
			"side": {
				"schemaVersion": 1,
				"state": "completed",
				"rewardReceipt": "bambooCompanions.v1.promise",
			},
		},
		"player": {"hp": 80, "potions": 1, "position": [2.0, 0.0, 5.0], "facing": 2},
	}
	write_json(SAVE_TMP, v1_save)
	var res: Dictionary = sm.load_state(SAVE_TMP)
	expect(res.get("ok", false), "v1 load rejected: %s" % res)
	expect(int(res.get("version", -1)) == 1, "version=%s" % res.get("version"))
	var loaded: Dictionary = gs.load_game(SAVE_TMP)
	expect(loaded.get("ok", false), "GameState v1 load failed")
	expect(gs.main_state == "delivered" and gs.side_state == "completed", "v1 quests")
	expect(gs.hp == 80 and gs.potions == 1, "v1 player")
	expect(gs.ch2_main_state == "available", "ch2 main=%s" % gs.ch2_main_state)
	expect(gs.ch2_spar_state == "locked" and gs.ch2_tea_state == "locked", "ch2 sides")
	expect(gs.ch2_spar_receipt == null and gs.ch2_tea_receipt == null, "ch2 receipts")
	expect(not gs.is_flag_true("battle.ch2_thug.won"), "ch2 flag not default false")
	end_case()

func _CH2_SAVE_002() -> void:
	begin_case("CH2-SAVE-002", "current save roundtrips chapter2 blocks")
	sm.delete_save(SAVE_TMP)
	reset_state("delivered", "completed", true, false)
	gs.normalize()
	gs.ch2_main_state = "toldByLiheng"
	gs.ch2_spar_state = "completed"
	gs.ch2_spar_receipt = "ch2Spar.v1.reward"
	gs.ch2_tea_state = "told"
	gs.flags["battle.ch2_thug.won"] = true
	gs.flags["battle.ch2_liheng_spar.won"] = true
	var saved: Dictionary = gs.save_game(SAVE_TMP)
	var before := JSON.stringify(gs.to_dict())
	expect(saved.get("ok", false), "save failed: %s" % saved)
	expect(int(saved.get("version", 0)) == int(sm.VERSION), "saved version")
	gs.reset_new_game()
	expect(gs.load_game(SAVE_TMP).get("ok", false), "load failed")
	expect(JSON.stringify(gs.to_dict()) == before, "state not identical")
	expect(gs.ch2_main_state == "toldByLiheng", "ch2 main=%s" % gs.ch2_main_state)
	expect(gs.ch2_spar_receipt == "ch2Spar.v1.reward", "spar receipt")
	expect(gs.ch2_tea_state == "told", "tea state=%s" % gs.ch2_tea_state)
	expect(gs.is_flag_true("battle.ch2_thug.won"), "ch2 battle flag")
	end_case()

func _CH2_SAVE_003() -> void:
	begin_case("CH2-SAVE-003", "invalid chapter2 blocks are rejected safely")
	sm.delete_save(SAVE_TMP)
	reset_state("delivered", "completed", true, false)
	gs.normalize()
	gs.save_game(SAVE_TMP)
	var base := read_json(SAVE_TMP)
	var variants: Array[Dictionary] = []
	var bad_main := base.duplicate(true)
	(bad_main["quests"] as Dictionary)["main.ch2Herbs"] = 5
	variants.append(bad_main)
	var bad_block := base.duplicate(true)
	(bad_block["quests"] as Dictionary)["side.ch2Spar"] = "bad"
	variants.append(bad_block)
	var bad_state := base.duplicate(true)
	(((bad_state["quests"] as Dictionary)["side.ch2Tea"] as Dictionary))["state"] = 7
	variants.append(bad_state)
	var ok := true
	for v: Dictionary in variants:
		write_json(SAVE_TMP, v)
		ok = ok and not sm.load_state(SAVE_TMP).get("ok", true)
	expect(ok, "an invalid ch2 block was accepted")
	end_case()

func _CH2_FLOW_001() -> void:
	begin_case("CH2-FLOW-001", "battle_requested -> victory -> flag saved; main ch2 completes")
	sm.delete_save(SAVE_FLOW)
	reset_state("delivered", "completed", true, false)
	gs.normalize()
	expect(pick_id("village.zhoubo") == "ch2_zhou_offer_companions", "offer pick=%s" % pick_id("village.zhoubo"))
	var offer: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"), [0])
	expect(quest_effect(offer, "main.ch2Herbs", "accept") and gs.ch2_main_state == "accepted", "accept event")
	expect(pick_id("gate.liheng") == "ch2_gate_prebattle_known", "gate pick=%s" % pick_id("gate.liheng"))
	var pre: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"), [0])
	expect(pre.battles == ["ch2_thug"], "battle_requested=%s" % [pre.battles])
	gs.set_in_battle(true)
	var e1 := BattleLogic.new()
	e1.set_battle_id("ch2_thug")
	e1.enemy_hp = 1
	e1.take_turn("attack")
	expect(e1.won, "E1 not won")
	var exit1: Dictionary = gs.leave_battle("ch2_thug", true, SAVE_FLOW)
	expect(exit1.get("ok", false) and exit1.get("saved", false), "leave_battle failed: %s" % exit1)
	expect(exit1.get("newly_won", false), "newly_won false")
	expect(str(exit1.get("return_point", "")) == "battle_return.ch2_thug_victory", "return point=%s" % exit1.get("return_point"))
	var saved1: Dictionary = sm.load_state(SAVE_FLOW)
	expect(saved1.get("ok", false), "save missing")
	expect((saved1.data.get("flags", {}) as Dictionary).get("battle.ch2_thug.won", false) == true, "thug flag not saved")
	expect(str((saved1.data.get("quests", {}) as Dictionary).get("main.ch2Herbs", "")) == "accepted", "main changed by victory")
	expect(not gs.in_battle, "still in_battle")
	expect(pick_id("battle_return.ch2_thug_victory") == "ch2_thug_postbattle", "postbattle pick")
	var post: Dictionary = await run_dialogue(db.pick_dialogue("battle_return.ch2_thug_victory"))
	expect(gs.is_flag_true("dlg.ch2.thugPostSeen") and (post.effects as Array).is_empty(), "postbattle flags")
	expect(pick_id("gate.liheng") == "ch2_gate_liheng_tell", "tell pick=%s" % pick_id("gate.liheng"))
	var tell: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"), [0])
	expect(quest_effect(tell, "main.ch2Herbs", "hearLiheng") and gs.ch2_main_state == "toldByLiheng", "hear event")
	expect(pick_id("yiting.gesancheng") == "ch2_station_prebattle", "station pick=%s" % pick_id("yiting.gesancheng"))
	var station: Dictionary = await run_dialogue(db.pick_dialogue("yiting.gesancheng"), [0])
	expect(station.battles == ["ch2_gesancheng"], "battle_requested=%s" % [station.battles])
	gs.set_in_battle(true)
	var e2 := BattleLogic.new()
	e2.set_battle_id("ch2_gesancheng")
	e2.enemy_hp = 1
	e2.take_turn("attack")
	expect(e2.won, "E2 not won")
	var exit2: Dictionary = gs.leave_battle("ch2_gesancheng", true, SAVE_FLOW)
	expect(exit2.get("ok", false) and exit2.get("saved", false), "E2 leave failed")
	var saved2: Dictionary = sm.load_state(SAVE_FLOW)
	expect((saved2.data.get("flags", {}) as Dictionary).get("battle.ch2_gesancheng.won", false) == true, "gesancheng flag not saved")
	expect(gs.ch2_main_state == "toldByLiheng", "recover event fired before dialogue")
	expect(pick_id("yiting.linzhaowan") == "ch2_station_recover", "recover pick=%s" % pick_id("yiting.linzhaowan"))
	var recover: Dictionary = await run_dialogue(db.pick_dialogue("yiting.linzhaowan"), [0])
	expect(quest_effect(recover, "main.ch2Herbs", "recoverPack") and gs.ch2_main_state == "stationCleared", "recover event")
	expect(pick_id("gate.liheng") == "ch2_finale", "finale pick=%s" % pick_id("gate.liheng"))
	var finale: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"), [0])
	expect(quest_effect(finale, "main.ch2Herbs", "finish") and gs.ch2_main_state == "completed", "finish event")
	expect(gs.is_flag_true("dlg.ch2.lihengVouched"), "vouch flag")
	end_case()

func _CH2_FLOW_002() -> void:
	begin_case("CH2-FLOW-002", "defeat/retreat writes no save and keeps pre-battle file")
	sm.delete_save(SAVE_FLOW)
	reset_state("delivered", "completed", true, false)
	gs.normalize()
	gs.dispatch_quest_event("main.ch2Herbs", "accept")
	expect(gs.save_game(SAVE_FLOW).get("ok", false), "baseline save failed")
	var before := read_raw(SAVE_FLOW)
	var pre: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"), [0])
	expect(pre.battles == ["ch2_thug"], "battle_requested=%s" % [pre.battles])
	gs.set_in_battle(true)
	var battle := BattleLogic.new()
	battle.set_battle_id("ch2_thug")
	battle.hp = 1
	battle.take_turn("guard")
	expect(battle.lost and not battle.won, "battle not lost")
	var blocked: Dictionary = gs.save_game(SAVE_FLOW)
	expect(not blocked.get("ok", true) and blocked.get("blocked", false), "in-battle save not blocked")
	expect(read_raw(SAVE_FLOW) == before, "save changed during battle")
	var exit1: Dictionary = gs.leave_battle("ch2_thug", false, SAVE_FLOW)
	expect(not exit1.get("saved", true), "defeat wrote save")
	expect(read_raw(SAVE_FLOW) == before, "defeat changed save")
	expect(not gs.is_flag_true("battle.ch2_thug.won"), "defeat set victory flag")
	expect(not gs.in_battle, "still in_battle after defeat")
	battle.restore_snapshot()
	expect(battle.hp == battle.entry_hp, "snapshot not restored")
	var exit2: Dictionary = gs.leave_battle("ch2_thug", false, SAVE_FLOW)
	expect(not exit2.get("saved", true) and read_raw(SAVE_FLOW) == before, "retreat wrote save")
	expect(pick_id("gate.liheng") == "ch2_gate_prebattle_known", "battle not retriggerable")
	var saved: Dictionary = sm.load_state(SAVE_FLOW)
	expect((saved.data.get("flags", {}) as Dictionary).get("battle.ch2_thug.won", false) == false, "saved flag true")
	end_case()

func _CH2_FLOW_003() -> void:
	begin_case("CH2-FLOW-003", "side ch2Spar/ch2Tea dialogue+battle+reward flow")
	sm.delete_save(SAVE_FLOW)
	reset_state("delivered", "completed", true, false)
	gs.normalize()
	gs.ch2_main_state = "completed"
	gs.normalize()
	expect(gs.ch2_spar_state == "available" and gs.ch2_tea_state == "available", "sides not available")
	expect(pick_id("village.mingcheng") == "ch2_tea_offer", "tea offer pick=%s" % pick_id("village.mingcheng"))
	var tea_offer: Dictionary = await run_dialogue(db.pick_dialogue("village.mingcheng"), [1])
	expect(quest_effect(tea_offer, "side.ch2Tea", "talkMonk") and gs.ch2_tea_state == "accepted", "tea accept")
	expect(pick_id("gate.liheng") == "ch2_tea_liheng", "tea liheng pick=%s" % pick_id("gate.liheng"))
	var tea_liheng: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"))
	expect(quest_effect(tea_liheng, "side.ch2Tea", "talkLiheng") and gs.ch2_tea_state == "told", "tea told")
	expect(pick_id("village.mingcheng") == "ch2_tea_return", "tea return pick=%s" % pick_id("village.mingcheng"))
	var tea_return: Dictionary = await run_dialogue(db.pick_dialogue("village.mingcheng"))
	expect(quest_effect(tea_return, "side.ch2Tea", "talkMonk"), "tea complete event")
	expect(gs.ch2_tea_state == "completed" and gs.ch2_tea_receipt == "ch2Tea.v1.reward", "tea reward")
	expect(int(tea_return.rewards) == 1, "tea reward count=%d" % tea_return.rewards)
	expect(pick_id("gate.liheng") == "ch2_spar_offer", "spar offer pick=%s" % pick_id("gate.liheng"))
	var spar_offer: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"), [0])
	expect(spar_offer.battles == ["ch2_liheng_spar"], "spar battle_requested=%s" % [spar_offer.battles])
	gs.set_in_battle(true)
	var e3 := BattleLogic.new()
	e3.set_battle_id("ch2_liheng_spar")
	e3.enemy_hp = 1
	e3.take_turn("attack")
	expect(e3.won, "E3 not won")
	var exit_battle: Dictionary = gs.leave_battle("ch2_liheng_spar", true, SAVE_FLOW)
	expect(exit_battle.get("ok", false) and exit_battle.get("saved", false), "spar leave failed")
	var saved: Dictionary = sm.load_state(SAVE_FLOW)
	expect((saved.data.get("flags", {}) as Dictionary).get("battle.ch2_liheng_spar.won", false) == true, "spar flag not saved")
	expect(pick_id("gate.liheng") == "ch2_spar_settle", "spar settle pick=%s" % pick_id("gate.liheng"))
	var settle: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"))
	expect(quest_effect(settle, "side.ch2Spar", "settle"), "spar settle event")
	expect(gs.ch2_spar_state == "completed" and gs.ch2_spar_receipt == "ch2Spar.v1.reward", "spar reward")
	expect(int(settle.rewards) == 1, "spar reward count=%d" % settle.rewards)
	end_case()

## Drive M2→M4 from an accepted chapter-2 main. Caller guarantees side state
## satisfies ch2_gate_prebattle_known (girlMet/bothMet/ready/completed).
func finish_ch2_main_from_accepted() -> Dictionary:
	var out := {"ok": true, "reason": ""}
	var pre: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"), [0])
	if pre.battles != ["ch2_thug"]:
		out.ok = false
		out.reason = "E1 request %s" % [pre.battles]
	gs.set_in_battle(true)
	var e1 := BattleLogic.new()
	e1.set_battle_id("ch2_thug")
	e1.enemy_hp = 1
	e1.take_turn("attack")
	var exit1: Dictionary = gs.leave_battle("ch2_thug", true, SAVE_FLOW)
	if not exit1.get("ok", false):
		out.ok = false
		out.reason = "E1 save"
	var tell: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"), [0])
	if gs.ch2_main_state != "toldByLiheng":
		out.ok = false
		out.reason = "tell state=%s" % gs.ch2_main_state
	var station: Dictionary = await run_dialogue(db.pick_dialogue("yiting.gesancheng"), [0])
	if station.battles != ["ch2_gesancheng"]:
		out.ok = false
		out.reason = "E2 request %s" % [station.battles]
	gs.set_in_battle(true)
	var e2 := BattleLogic.new()
	e2.set_battle_id("ch2_gesancheng")
	e2.enemy_hp = 1
	e2.take_turn("attack")
	var exit2: Dictionary = gs.leave_battle("ch2_gesancheng", true, SAVE_FLOW)
	if not exit2.get("ok", false):
		out.ok = false
		out.reason = "E2 save"
	var recover: Dictionary = await run_dialogue(db.pick_dialogue("yiting.linzhaowan"), [0])
	if gs.ch2_main_state != "stationCleared":
		out.ok = false
		out.reason = "recover state=%s" % gs.ch2_main_state
	var finale: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"), [0])
	if gs.ch2_main_state != "completed":
		out.ok = false
		out.reason = "finale state=%s" % gs.ch2_main_state
	return out

func _STEP9_DLG_001() -> void:
	begin_case("STEP9-DLG-001", "narrator speaker and fade_black portrait key")
	var narrator: Dictionary = db.get_node_data("ch2_zc_07")
	expect(db.speaker_id(narrator) == "narrator", "speaker=%s" % db.speaker_id(narrator))
	expect(db.speaker_display_name(narrator) == "旁白", "name=%s" % db.speaker_display_name(narrator))
	expect(db.portrait_key(narrator) == "transition.fade_black", "key=%s" % db.portrait_key(narrator))
	expect(db.portrait_path(narrator) == "", "path=%s" % db.portrait_path(narrator))
	expect(db.speaker_side(narrator) == "left", "side=%s" % db.speaker_side(narrator))
	reset_state("delivered", "completed", true, false)
	gs.normalize()
	expect(pick_id("village.zhoubo") == "ch2_zhou_offer_companions", "offer pick=%s" % pick_id("village.zhoubo"))
	var run: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"), [0])
	expect((run.speakers as Array).has("旁白"), "narrator line missing: %s" % [run.speakers])
	expect((run.node_ids as Array).has("ch2_zc_07"), "narrator node missing: %s" % [run.node_ids])
	expect(quest_effect(run, "main.ch2Herbs", "accept"), "accept effect")
	end_case()

func _STEP9_DQ05_001() -> void:
	begin_case("STEP9-DQ05-001", "reward settlement saves first, then is durable")
	sm.delete_save(SAVE_FLOW)
	reset_state("delivered", "ready", true, false)
	var messages: Array[String] = []
	var cb: Callable = func(text: String) -> void: messages.append(text)
	gs.reward_granted.connect(cb)
	var res: Dictionary = gs.dispatch_quest_event("side.bambooCompanions", "talkZhou")
	gs.reward_granted.disconnect(cb)
	expect(res.get("reward", false) and gs.side_state == "completed", "settlement failed")
	expect(gs.side_receipt == "bambooCompanions.v1.promise", "receipt=%s" % gs.side_receipt)
	expect(gs.has_pending_settlement(), "no pending settlement")
	expect(gs.pending_rewards().size() == 1, "pending=%s" % [gs.pending_rewards()])
	expect(messages == ["同行之约"], "reward signal=%s" % [messages])
	var saved: Dictionary = gs.save_game(SAVE_FLOW)
	expect(saved.get("ok", false), "save failed: %s" % saved)
	expect(not gs.has_pending_settlement(), "settlement not committed")
	expect(gs.side_state == "completed", "state rolled back on success")
	var raw: Dictionary = sm.load_state(SAVE_FLOW)
	expect(str(((raw.data.get("quests", {}) as Dictionary).get("side", {}) as Dictionary).get("state", "")) == "completed", "saved state")
	expect(str(((raw.data.get("quests", {}) as Dictionary).get("side", {}) as Dictionary).get("rewardReceipt", "")) == "bambooCompanions.v1.promise", "saved receipt")
	end_case()

func _STEP9_DQ05_002() -> void:
	begin_case("STEP9-DQ05-002", "failed save rolls the settlement back")
	reset_state("delivered", "ready", true, false)
	gs.dispatch_quest_event("side.bambooCompanions", "talkZhou")
	expect(gs.side_state == "completed" and gs.has_pending_settlement(), "reward not pending")
	var bad_path := "user://__step9_missing_dir__/save.json"
	var res: Dictionary = gs.save_game(bad_path)
	expect(not res.get("ok", true), "bad save unexpectedly succeeded")
	expect(res.get("rolled_back", false), "rolled_back missing: %s" % res)
	expect(gs.side_state == "ready", "side=%s" % gs.side_state)
	expect(gs.side_receipt == null, "receipt=%s" % gs.side_receipt)
	expect(not gs.has_pending_settlement(), "pending settlement kept")
	expect(gs.pending_rewards().is_empty(), "pending rewards kept")
	expect(not FileAccess.file_exists(bad_path), "bad path file exists")
	# The snapshot covers chapter-2 rewards too: told -> completed -> told.
	reset_state("delivered", "completed", true, false)
	gs.ch2_tea_state = "told"
	gs.ch2_tea_receipt = null
	gs.dispatch_quest_event("side.ch2Tea", "talkMonk")
	expect(gs.ch2_tea_state == "completed" and gs.has_pending_settlement(), "tea reward not pending")
	var tea_res: Dictionary = gs.save_game(bad_path)
	expect(not tea_res.get("ok", true) and tea_res.get("rolled_back", false), "tea rollback missing")
	expect(gs.ch2_tea_state == "told" and gs.ch2_tea_receipt == null, "tea state=%s receipt=%s" % [gs.ch2_tea_state, gs.ch2_tea_receipt])
	end_case()

func _STEP9_DQ05_003() -> void:
	begin_case("STEP9-DQ05-003", "retry after a failed save succeeds")
	sm.delete_save(SAVE_FLOW)
	reset_state("delivered", "ready", true, false)
	gs.dispatch_quest_event("side.bambooCompanions", "talkZhou")
	var bad_path := "user://__step9_missing_dir__/save.json"
	var failed: Dictionary = gs.save_game(bad_path)
	expect(not failed.get("ok", true) and gs.side_state == "ready", "first save did not roll back")
	var retry: Dictionary = gs.dispatch_quest_event("side.bambooCompanions", "talkZhou")
	expect(retry.get("applied", false) and retry.get("reward", false), "retry settlement not applied")
	var saved: Dictionary = gs.save_game(SAVE_FLOW)
	expect(saved.get("ok", false), "retry save failed: %s" % saved)
	expect(gs.side_state == "completed" and gs.side_receipt == "bambooCompanions.v1.promise", "retry state")
	expect(not gs.has_pending_settlement(), "retry settlement pending")
	var raw: Dictionary = sm.load_state(SAVE_FLOW)
	expect(raw.get("ok", false), "retry save unreadable")
	end_case()

func _STEP9_DQ05_004() -> void:
	begin_case("STEP9-DQ05-004", "ch2Spar rollback/retry; rename and read-back failures roll back")
	sm.delete_save(SAVE_FLOW)
	var bad_path := "user://__step9_missing_dir__/save.json"
	# ch2Spar: available -> completed, failed save -> available, retry -> durable.
	reset_state("delivered", "completed", true, false)
	gs.ch2_main_state = "toldByLiheng"
	gs.ch2_spar_state = "available"
	gs.ch2_spar_receipt = null
	gs.flags["battle.ch2_liheng_spar.won"] = true
	var spar: Dictionary = gs.dispatch_quest_event("side.ch2Spar", "settle")
	expect(spar.get("reward", false) and gs.has_pending_settlement(), "spar reward not pending")
	var spar_fail: Dictionary = gs.save_game(bad_path)
	expect(not spar_fail.get("ok", true) and spar_fail.get("rolled_back", false), "spar rollback missing: %s" % spar_fail)
	expect(gs.ch2_spar_state == "available" and gs.ch2_spar_receipt == null, "spar state=%s receipt=%s" % [gs.ch2_spar_state, gs.ch2_spar_receipt])
	expect(not gs.has_pending_settlement() and gs.pending_rewards().is_empty(), "spar pending kept")
	var spar_retry: Dictionary = gs.dispatch_quest_event("side.ch2Spar", "settle")
	expect(spar_retry.get("applied", false) and spar_retry.get("reward", false), "spar retry not applied")
	var spar_saved: Dictionary = gs.save_game(SAVE_FLOW)
	expect(spar_saved.get("ok", false), "spar retry save failed: %s" % spar_saved)
	expect(gs.ch2_spar_state == "completed" and gs.ch2_spar_receipt == "ch2Spar.v1.reward", "spar retry state")
	expect(not gs.has_pending_settlement(), "spar retry pending")
	var raw: Dictionary = sm.load_state(SAVE_FLOW)
	var spar_block: Dictionary = ((raw.get("data", {}) as Dictionary).get("quests", {}) as Dictionary).get("side.ch2Spar", {})
	expect(str(spar_block.get("state", "")) == "completed" and str(spar_block.get("rewardReceipt", "")) == "ch2Spar.v1.reward", "spar saved block=%s" % [spar_block])
	# Injected failures on an existing save: live file must stay the previous one.
	for stage: String in ["rename", "readback"]:
		var before_text := read_raw(SAVE_FLOW)
		reset_state("delivered", "ready", true, false)
		gs.dispatch_quest_event("side.bambooCompanions", "talkZhou")
		expect(gs.side_state == "completed" and gs.has_pending_settlement(), "%s: reward not pending" % stage)
		sm.test_fail_stage = stage
		var res: Dictionary = gs.save_game(SAVE_FLOW)
		expect(sm.test_fail_stage == "", "%s: hook not consumed" % stage)
		expect(not res.get("ok", true), "%s: save unexpectedly ok" % stage)
		expect(res.get("rolled_back", false), "%s: rolled_back missing: %s" % [stage, res])
		expect(gs.side_state == "ready" and gs.side_receipt == null, "%s: side=%s receipt=%s" % [stage, gs.side_state, gs.side_receipt])
		expect(not gs.has_pending_settlement() and gs.pending_rewards().is_empty(), "%s: pending kept" % stage)
		expect(read_raw(SAVE_FLOW) == before_text, "%s: live save changed" % stage)
		expect(not FileAccess.file_exists(SAVE_FLOW + ".tmp"), "%s: tmp left behind" % stage)
		var retry: Dictionary = gs.dispatch_quest_event("side.bambooCompanions", "talkZhou")
		expect(retry.get("reward", false), "%s: retry not applied" % stage)
		var ok_save: Dictionary = gs.save_game(SAVE_FLOW)
		expect(ok_save.get("ok", false) and gs.side_state == "completed" and not gs.has_pending_settlement(), "%s: retry save" % stage)
		sm.test_fail_stage = ""
	# Hook armed but the save fails earlier (missing dir): hook must still be cleared.
	sm.test_fail_stage = "rename"
	var early: Dictionary = gs.save_game(bad_path)
	var left_after_missing_dir: String = sm.test_fail_stage
	sm.test_fail_stage = ""
	expect(not early.get("ok", true), "missing-dir save unexpectedly ok")
	expect(left_after_missing_dir == "", "hook left armed after missing dir: %s" % left_after_missing_dir)
	# Hook armed but blocked in battle: hook must be cleared too.
	sm.test_fail_stage = "readback"
	gs.in_battle = true
	var blocked: Dictionary = gs.save_game(SAVE_FLOW)
	gs.in_battle = false
	var left_after_block: String = sm.test_fail_stage
	sm.test_fail_stage = ""
	expect(blocked.get("blocked", false), "in-battle save not blocked")
	expect(left_after_block == "", "hook left armed after battle block: %s" % left_after_block)
	end_case()

func _STEP9_DQ07_001() -> void:
	begin_case("STEP9-DQ07-001", "side accepted: chapter 1 and chapter 2 both complete")
	sm.delete_save(SAVE_FLOW)
	reset_state("delivered", "accepted", true, false)
	gs.normalize()
	expect(pick_id("village.zhoubo") == "ch2_zhou_offer", "parallel offer pick=%s" % pick_id("village.zhoubo"))
	var offer: Dictionary = await run_dialogue(db.pick_dialogue("village.zhoubo"), [0])
	expect(quest_effect(offer, "main.ch2Herbs", "accept"), "ch2 accept")
	expect(pick_id("gate.linzhaowan") == "ch2_gate_girl_bc_meet", "gate girl pick=%s" % pick_id("gate.linzhaowan"))
	var meet: Dictionary = await run_dialogue(db.pick_dialogue("gate.linzhaowan"))
	expect(quest_effect(meet, "side.bambooCompanions", "talkGirl") and gs.side_state == "girlMet", "talkGirl")
	expect(pick_id("village.mingcheng") == "bc_monk_join", "monk pick=%s" % pick_id("village.mingcheng"))
	await run_dialogue(db.pick_dialogue("village.mingcheng"))
	expect(gs.side_state == "ready", "side state=%s" % gs.side_state)
	expect(pick_id("village.zhoubo") == "bc_finale", "finale pick=%s" % pick_id("village.zhoubo"))
	await run_dialogue(db.pick_dialogue("village.zhoubo"))
	expect(gs.side_state == "completed", "side not completed")
	var flow: Dictionary = await finish_ch2_main_from_accepted()
	expect(flow.get("ok", false), "ch2 flow: %s" % flow.get("reason", ""))
	expect(gs.ch2_main_state == "completed" and gs.side_state == "completed", "both lines")
	end_case()

func _STEP9_DQ07_002() -> void:
	begin_case("STEP9-DQ07-002", "side girlMet: widened M2 condition, both lines complete")
	sm.delete_save(SAVE_FLOW)
	reset_state("delivered", "girlMet", true, false)
	gs.normalize()
	expect(pick_id("village.zhoubo") == "ch2_zhou_offer", "offer pick=%s" % pick_id("village.zhoubo"))
	await run_dialogue(db.pick_dialogue("village.zhoubo"), [0])
	expect(gs.ch2_main_state == "accepted", "ch2 not accepted")
	expect(pick_id("gate.liheng") == "ch2_gate_prebattle_known", "M2 pick=%s" % pick_id("gate.liheng"))
	expect(pick_id("village.mingcheng") == "bc_monk_join", "monk pick=%s" % pick_id("village.mingcheng"))
	await run_dialogue(db.pick_dialogue("village.mingcheng"))
	expect(gs.side_state == "ready", "side state=%s" % gs.side_state)
	expect(pick_id("village.zhoubo") == "bc_finale", "finale pick=%s" % pick_id("village.zhoubo"))
	await run_dialogue(db.pick_dialogue("village.zhoubo"))
	expect(gs.side_state == "completed", "side not completed")
	var flow: Dictionary = await finish_ch2_main_from_accepted()
	expect(flow.get("ok", false), "ch2 flow: %s" % flow.get("reason", ""))
	expect(gs.ch2_main_state == "completed" and gs.side_state == "completed", "both lines")
	end_case()

func _STEP9_VIS_001() -> void:
	begin_case("STEP9-VIS-001", "chapter2 NPC visibility queries")
	reset_state("delivered", "completed", true, false)
	gs.normalize()
	gs.flags["battle.ch2_gesancheng.won"] = false
	gs.ch2_main_state = "locked"
	expect(gs.is_point_visible("bamboo.linzhaowan"), "bamboo hidden at locked")
	expect(not gs.is_point_visible("gate.liheng"), "gate liheng visible at locked")
	expect(not gs.is_point_visible("gate.linzhaowan"), "gate girl visible at locked")
	gs.ch2_main_state = "available"
	expect(gs.is_point_visible("bamboo.linzhaowan"), "bamboo hidden at available")
	expect(not gs.is_point_visible("yiting.gesancheng"), "gesancheng visible at available")
	gs.ch2_main_state = "accepted"
	expect(not gs.is_point_visible("bamboo.linzhaowan"), "bamboo visible at accepted")
	expect(gs.is_point_visible("gate.liheng"), "gate liheng hidden at accepted")
	expect(gs.is_point_visible("gate.linzhaowan"), "gate girl hidden at accepted")
	gs.ch2_main_state = "toldByLiheng"
	expect(gs.is_point_visible("yiting.gesancheng"), "gesancheng hidden before fight")
	expect(gs.is_point_visible("yiting.linzhaowan"), "yiting girl hidden")
	gs.flags["battle.ch2_gesancheng.won"] = true
	expect(not gs.is_point_visible("yiting.gesancheng"), "gesancheng visible after win")
	gs.ch2_main_state = "stationCleared"
	expect(gs.is_point_visible("gate.liheng"), "gate liheng hidden at station")
	expect(not gs.is_point_visible("gate.linzhaowan"), "gate girl visible at station")
	expect(gs.is_point_visible("yiting.linzhaowan"), "yiting girl hidden at station")
	gs.ch2_main_state = "completed"
	expect(gs.is_point_visible("gate.linzhaowan"), "gate girl hidden at completed")
	expect(not gs.is_point_visible("yiting.linzhaowan"), "yiting girl visible at completed")
	expect(gs.is_point_visible("village.zhoubo"), "chapter1 point hidden")
	end_case()

# ================================================================== CH3 (step10)

func reset_ch3(ch3_main: String, vouched: Variant = false) -> void:
	reset_state("delivered", "completed", true, true)
	gs.ch2_main_state = "completed"
	gs.ch2_spar_state = "completed"
	gs.ch2_spar_receipt = "ch2Spar.v1.reward"
	gs.ch2_tea_state = "completed"
	gs.ch2_tea_receipt = "ch2Tea.v1.reward"
	gs.flags["battle.ch2_thug.won"] = true
	gs.flags["battle.ch2_gesancheng.won"] = true
	if vouched == null:
		gs.flags.erase("dlg.ch2.lihengVouched")
	else:
		gs.flags["dlg.ch2.lihengVouched"] = vouched
	gs.ch3_main_state = ch3_main

func win_battle(battle_id: String) -> Dictionary:
	gs.set_in_battle(true)
	var b := BattleLogic.new()
	b.set_battle_id(battle_id)
	b.enemy_hp = 1
	b.take_turn("attack")
	return gs.leave_battle(battle_id, b.won, SAVE_FLOW)

## Strategies from chapter3.md §2.3: read (A), hard (B), old habit.
func ch3_sim(battle_id: String, mode: String) -> Dictionary:
	var b := BattleLogic.new()
	b.set_battle_id(battle_id)
	var rounds := 0
	var prev_charge := false
	var guarded_last := false
	while not b.is_over() and rounds < 60:
		rounds += 1
		var action := "attack"
		var skill_dmg := b.player_attack_damage("skill")
		var attack_dmg := b.player_attack_damage("attack")
		if b.qi >= BattleData.SKILL_QI_COST and b.enemy_hp <= skill_dmg:
			action = "skill"
		elif b.enemy_hp <= attack_dmg:
			action = "attack"
		elif mode == "read" and b.enemy_next_action() == "heavy":
			action = "guard"
		elif mode == "old" and prev_charge and not guarded_last:
			action = "guard"
		elif b.qi >= BattleData.SKILL_QI_COST:
			action = "skill"
		var r := b.take_turn(action)
		guarded_last = action == "guard"
		prev_charge = r.get("charged", false)
	return {"rounds": rounds, "hp": b.hp, "won": b.won}

func _CH3_DLG_001() -> void:
	begin_case("CH3-DLG-001", "chapter3 v1.2 loads/merges; 5 narrator nodes")
	expect(db.load_error == "" and db.validate().is_empty(), "validate=%s" % [db.validate()])
	var d3 := 0
	var n3 := 0
	for id: String in db.dialogues:
		if id.begins_with("ch3_"):
			d3 += 1
	for id: String in db.nodes:
		if id.begins_with("ch3_"):
			n3 += 1
	expect(d3 == 28 and n3 == 79, "ch3 dialogues=%d nodes=%d" % [d3, n3])
	var plan_text := FileAccess.get_file_as_string("res://data/chapter3-dialogue.json")
	var plan_doc: Variant = JSON.parse_string(plan_text)
	expect(typeof(plan_doc) == TYPE_DICTIONARY and str((plan_doc as Dictionary).get("contentVersion", "")) == "chapter3-dialogue-v1.2", "chapter3 contentVersion")
	var ch2_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/chapter2-dialogue.json"))
	expect(typeof(ch2_doc) == TYPE_DICTIONARY and str((ch2_doc as Dictionary).get("contentVersion", "")) == "chapter2-dialogue-v1.2", "chapter2 contentVersion")
	var points: Dictionary = db.db.get("interactionPoints", {})
	for p: String in ["stair.dashou", "stair.linzhaowan", "hermitage.chutie", "hermitage.linzhaowan",
			"hermitage.wensu", "battle_return.ch3_stair_victory", "battle_return.ch3_chutie_victory",
			"battle_return.ch3_herb_thief_victory"]:
		expect(points.has(p), "missing point %s" % p)
	var gate_ids: Array = (points.get("gate.liheng", {}) as Dictionary).get("dialogues", [])
	expect(gate_ids.has("ch2_gate_prebattle_known") and gate_ids.has("ch3_sendoff"), "gate.liheng merged list")
	expect(gate_ids.find("ch2_spar_offer") < gate_ids.find("ch3_liheng_progress"), "Q6 order")
	# v1.2: ch2_gate_girl_go / ch2_gg_01 deleted (girl only at yiting during toldByLiheng).
	var girl_ids: Array = (points.get("gate.linzhaowan", {}) as Dictionary).get("dialogues", [])
	expect(not db.dialogues.has("ch2_gate_girl_go") and not db.nodes.has("ch2_gg_01"), "ch2_gate_girl_go still loaded")
	expect(not girl_ids.has("ch2_gate_girl_go") and girl_ids.has("ch3_setout"), "gate.linzhaowan list=%s" % [girl_ids])
	for nid: String in ["ch3_so_06", "ch3_st_06", "ch3_cb_02", "ch3_hb_02", "ch3_wf_09"]:
		var n: Dictionary = node(nid)
		expect(db.speaker_id(n) == "narrator" and db.portrait_key(n) == "transition.fade_black", "narrator %s" % nid)
	var speakers: Dictionary = db.db.get("speakers", {})
	expect(speakers.has("wensu") and speakers.has("chutie"), "new speakers")
	end_case()

func _CH3_DLG_002() -> void:
	begin_case("CH3-DLG-002", "vouched flag true/false/missing only swaps sendoff lines")
	var picks := {}
	var effects := {}
	for v: Variant in [true, false, null]:
		reset_ch3("accepted", v)
		gs.normalize()
		var pid := pick_id("gate.liheng")
		picks[str(v)] = pid
		var run: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"))
		effects[str(v)] = run.effects
		expect(gs.ch3_main_state == "accepted", "%s: main changed" % v)
		expect(gs.is_flag_true("dlg.ch3.sendoffSeen"), "%s: sendoffSeen not set" % v)
		expect(pick_id("gate.liheng") != pid, "%s: sendoff replays" % v)
	expect(picks["true"] == "ch3_sendoff_vouched", "vouched pick=%s" % picks["true"])
	expect(picks["false"] == "ch3_sendoff" and picks["<null>"] == "ch3_sendoff", "picks=%s" % [picks])
	for k: String in effects:
		expect((effects[k] as Array).is_empty(), "%s: sendoff has effects %s" % [k, effects[k]])
	end_case()

func _CH3_BAT_001() -> void:
	begin_case("CH3-BAT-001", "E1/E2/E3 stats and damage values (§2.2)")
	var expect_table := {
		"ch3_stair": {"hp": 80, "atk": 12, "def": 1, "p_attack": 11, "p_skill": 21, "hits": [[1.0, 8, 4], [3.0, 32, 16]]},
		"ch3_chutie": {"hp": 130, "atk": 13, "def": 2, "p_attack": 10, "p_skill": 20, "hits": [[1.0, 9, 4], [2.5, 29, 14], [3.0, 35, 17]]},
		"ch3_herb_thief": {"hp": 100, "atk": 13, "def": 2, "p_attack": 10, "p_skill": 20, "hits": [[1.0, 9, 4], [3.0, 35, 17], [2.4, 27, 13]]},
	}
	for id: String in expect_table:
		var want: Dictionary = expect_table[id]
		var b := BattleLogic.new()
		expect(b.set_battle_id(id), "%s unknown" % id)
		expect(b.enemy_hp == want.hp and b.enemy_attack == want.atk and b.enemy_defense == want.def, "%s stats" % id)
		expect(b.player_attack_damage("attack") == want.p_attack and b.player_attack_damage("skill") == want.p_skill, "%s player dmg" % id)
		for hit: Array in want.hits:
			var action := "attack" if float(hit[0]) == 1.0 else "heavy"
			b.guarding = false
			var raw := b.enemy_action_damage(action, float(hit[0]))
			b.guarding = true
			var guarded := b.enemy_action_damage(action, float(hit[0]))
			b.guarding = false
			expect(raw == int(hit[1]) and guarded == int(hit[2]), "%s x%.1f -> %d/%d want %d/%d" % [id, hit[0], raw, guarded, hit[1], hit[2]])
	expect(BattleData.cycle_actions("ch3_stair") == ["attack", "charge", "charge", "heavy"], "E1 cycle")
	expect(BattleData.cycle_actions("ch3_chutie") == ["attack", "attack", "charge", "heavy", "attack", "charge", "charge", "heavy"], "E2 cycle")
	expect(BattleData.cycle_actions("ch3_herb_thief") == ["attack", "charge", "charge", "heavy", "charge", "heavy"], "E3 cycle")
	end_case()

func _CH3_BAT_002() -> void:
	begin_case("CH3-BAT-002", "double charge keeps marker, no damage, per-beat heavy mult")
	var b := BattleLogic.new()
	b.set_battle_id("ch3_stair")
	b.enemy_hp = 999
	var r1 := b.take_turn("attack")
	expect(r1.enemy_action == "attack" and r1.enemy_damage == 8, "beat1=%s" % [r1])
	var r2 := b.take_turn("attack")
	expect(r2.enemy_action == "charge" and r2.enemy_damage == 0 and b.enemy_charging, "beat2=%s" % [r2])
	var r3 := b.take_turn("attack")
	expect(r3.enemy_action == "charge" and r3.enemy_damage == 0 and b.enemy_charging, "beat3 marker lost=%s" % [r3])
	expect(b.enemy_next_action() == "heavy", "next=%s" % b.enemy_next_action())
	var r4 := b.take_turn("guard")
	expect(r4.enemy_action == "heavy" and r4.enemy_damage == 16 and not b.enemy_charging, "beat4=%s" % [r4])
	# E2: the two heavies in one cycle use their own beat multipliers (29 and 35).
	var c := BattleLogic.new()
	c.set_battle_id("ch3_chutie")
	c.enemy_hp = 999
	var heavies: Array[int] = []
	for i in 8:
		var r := c.take_turn("attack")
		if r.enemy_action == "heavy":
			heavies.append(int(r.enemy_damage))
		if c.is_over():
			break
	expect(heavies == [29, 35], "E2 heavies=%s" % [heavies])
	end_case()

func _CH3_BAT_003() -> void:
	begin_case("CH3-BAT-003", "13 per-beat logs; fallback to chargeLog/heavyLog")
	var want := {
		"ch3_stair": {1: "打手抡起短棍，劲还没攒满！", 2: "打手又攒一口劲，棍风更沉！", 3: "打手攒足两回劲，一棍砸下！"},
		"ch3_chutie": {2: "褚铁压低刀身，正在蓄力！", 3: "褚铁抡刀劈下！", 5: "褚铁横刀蓄力，刀势未满！", 6: "褚铁刀势又沉了一分！", 7: "褚铁攒足两回力，全力劈下！"},
		"ch3_herb_thief": {1: "打手举起药锄，劲还没攒满！", 2: "打手又攒一回劲，锄头高举！", 3: "打手攒足两回劲，一锄刨下！", 4: "打手举锄一顿，正在蓄力！", 5: "打手一锄头刨下！"},
	}
	var total := 0
	for id: String in want:
		var b := BattleLogic.new()
		b.set_battle_id(id)
		b.enemy_hp = 9999
		var beats: Dictionary = want[id]
		for i in BattleData.cycle_actions(id).size():
			var before := b.log_lines.size()
			b.take_turn("guard")
			var lines := b.log_lines.slice(before)
			if beats.has(i):
				total += 1
				expect(b.cycle_step_log(i) == beats[i], "%s beat %d step_log=%s" % [id, i + 1, b.cycle_step_log(i)])
				expect(lines.has(beats[i]), "%s beat %d log=%s" % [id, i + 1, lines])
				expect(str(beats[i]).length() <= 24, "%s beat %d too long" % [id, i + 1])
	expect(total == 13, "log count=%d" % total)
	var e2: Dictionary = want["ch3_chutie"]
	expect(e2[2] != e2[5] and e2[5] != e2[6] and e2[2] != e2[6], "E2 charge logs not distinct")
	expect(e2[3] != e2[7], "E2 heavy logs not distinct")
	# Ch1/ch2 profiles have no per-beat log and fall back unchanged.
	for id: String in ["liheng", "ch2_thug", "ch2_gesancheng", "ch2_liheng_spar"]:
		for step: Variant in BattleData.profile_for(id).get("cycle", []):
			expect(not (step as Dictionary).has("log"), "%s has per-beat log" % id)
	var l := BattleLogic.new()
	l.set_battle_id("liheng")
	expect(l.cycle_step_log(2) == BattleData.ENEMY_CHARGE_LOG and l.cycle_step_log(3) == BattleData.ENEMY_HEAVY_LOG, "ch1 fallback")
	l.take_turn("attack")
	l.take_turn("attack")
	l.take_turn("attack")
	expect(l.last_log() == BattleData.ENEMY_CHARGE_LOG, "ch1 runtime fallback=%s" % l.last_log())
	end_case()

func _CH3_BAT_004() -> void:
	begin_case("CH3-BAT-004", "paper sims match design (A read / B hard / old habit)")
	var design := {
		"ch3_stair": {"read": [6, 68], "hard": [5, 60], "old": [6, 52]},
		"ch3_chutie": {"read": [10, 33], "hard": [9, 9], "old": [10, 15]},
		"ch3_herb_thief": {"read": [8, 52], "hard": [7, 29], "old": [8, 34]},
	}
	var actual_lines: Array[String] = []
	for id: String in design:
		for mode: String in design[id]:
			var got := ch3_sim(id, mode)
			var exp: Array = design[id][mode]
			actual_lines.append("%s %s %d/%d" % [id, mode, got.rounds, got.hp])
			expect(got.won, "%s %s lost" % [id, mode])
			expect(got.rounds == int(exp[0]) and got.hp == int(exp[1]), "%s %s=%d r/%d hp (want %d/%d)" % [id, mode, got.rounds, got.hp, exp[0], exp[1]])
	print("     CH3 actuals: " + "; ".join(actual_lines))
	end_case()

func _CH3_QUEST_001() -> void:
	begin_case("CH3-QUEST-001", "main.ch3Hermitage state machine, guards, merge, unknown")
	reset_state("delivered", "completed", true, false)
	gs.ch2_main_state = "stationCleared"
	gs.normalize()
	expect(gs.ch3_main_state == "locked", "unlocked before ch2 completed")
	gs.ch2_main_state = "completed"
	gs.normalize()
	expect(gs.ch3_main_state == "available", "merge -> %s" % gs.ch3_main_state)
	expect(gs.ch3_debt_state == "locked" and gs.ch3_herb_state == "locked", "sides early")
	expect(not gs.dispatch_quest_event("main.ch3Hermitage", "clearStair").applied, "clearStair from available")
	expect(gs.dispatch_quest_event("main.ch3Hermitage", "accept").applied and gs.ch3_main_state == "accepted", "accept")
	expect(not gs.dispatch_quest_event("main.ch3Hermitage", "clearStair").applied, "clearStair without win")
	gs.flags["battle.ch3_stair.won"] = true
	expect(gs.dispatch_quest_event("main.ch3Hermitage", "clearStair").applied and gs.ch3_main_state == "stairCleared", "clearStair")
	expect(not gs.dispatch_quest_event("main.ch3Hermitage", "holdGate").applied, "holdGate without win")
	expect(not gs.dispatch_quest_event("main.ch3Hermitage", "finish").applied, "finish early")
	gs.flags["battle.ch3_chutie.won"] = true
	expect(gs.dispatch_quest_event("main.ch3Hermitage", "holdGate").applied and gs.ch3_main_state == "gateHeld", "holdGate")
	gs.normalize()
	expect(gs.ch3_debt_state == "available" and gs.ch3_herb_state == "available", "sides not unlocked")
	expect(gs.dispatch_quest_event("main.ch3Hermitage", "finish").applied and gs.ch3_main_state == "completed", "finish")
	expect(not gs.dispatch_quest_event("main.ch3Hermitage", "finish").applied, "finish twice")
	gs.ch2_main_state = "bogus"
	gs.normalize()
	expect(gs.get_quest_state("main.ch3Hermitage") == "unknown", "ch2 unknown -> ch3 %s" % gs.get_quest_state("main.ch3Hermitage"))
	expect(gs.eval_condition({"quest": "main.ch3Hermitage", "equals": "completed"}) == gs.Tri.UNKNOWN, "unknown not tri-unknown")
	reset_ch3("available")
	gs.ch3_debt_schema = 2
	gs.normalize()
	expect(gs.get_quest_state("side.ch3Debt") == "disabled", "bad schema not disabled")
	end_case()

func _CH3_QUEST_002() -> void:
	begin_case("CH3-QUEST-002", "ch3Debt/ch3Herb rewards once; save-fail rollback + retry")
	sm.delete_save(SAVE_FLOW)
	var bad_path := "user://__step10_missing_dir__/save.json"
	reset_ch3("gateHeld")
	gs.normalize()
	expect(gs.dispatch_quest_event("side.ch3Debt", "talkLiheng").applied and gs.ch3_debt_state == "accepted", "debt accept")
	expect(not gs.dispatch_quest_event("side.ch3Debt", "talkLiheng").applied, "debt talkLiheng at accepted")
	expect(gs.dispatch_quest_event("side.ch3Debt", "talkWensu").applied and gs.ch3_debt_state == "delivered", "debt deliver")
	var debt: Dictionary = gs.dispatch_quest_event("side.ch3Debt", "talkLiheng")
	expect(debt.reward and debt.message == "另一半账" and gs.ch3_debt_receipt == "ch3Debt.v1.reward", "debt reward=%s" % [debt])
	var fail: Dictionary = gs.save_game(bad_path)
	expect(not fail.ok and fail.get("rolled_back", false), "debt rollback=%s" % [fail])
	expect(gs.ch3_debt_state == "delivered" and gs.ch3_debt_receipt == null, "debt after rollback=%s" % gs.ch3_debt_state)
	expect(gs.dispatch_quest_event("side.ch3Debt", "talkLiheng").reward, "debt retry")
	expect(gs.save_game(SAVE_FLOW).ok and not gs.has_pending_settlement(), "debt save")
	expect(not gs.dispatch_quest_event("side.ch3Debt", "talkLiheng").applied, "debt rewarded twice")
	expect(not gs.dispatch_quest_event("side.ch3Herb", "settle").applied, "herb settle without win")
	gs.flags["battle.ch3_herb_thief.won"] = true
	var herb: Dictionary = gs.dispatch_quest_event("side.ch3Herb", "settle")
	expect(herb.reward and herb.message == "雪见草" and gs.ch3_herb_receipt == "ch3Herb.v1.reward", "herb reward")
	var hfail: Dictionary = gs.save_game(bad_path)
	expect(not hfail.ok and hfail.get("rolled_back", false), "herb rollback")
	expect(gs.ch3_herb_state == "available" and gs.ch3_herb_receipt == null, "herb after rollback")
	expect(gs.ch3_debt_state == "completed", "earlier durable debt rolled back too")
	expect(gs.dispatch_quest_event("side.ch3Herb", "settle").reward, "herb retry")
	expect(gs.save_game(SAVE_FLOW).ok, "herb save")
	expect(not gs.dispatch_quest_event("side.ch3Herb", "settle").applied, "herb rewarded twice")
	var raw: Dictionary = sm.load_state(SAVE_FLOW)
	var q: Dictionary = (raw.data as Dictionary).get("quests", {})
	expect(str((q.get("side.ch3Debt", {}) as Dictionary).get("rewardReceipt", "")) == "ch3Debt.v1.reward", "saved debt receipt")
	expect(str((q.get("side.ch3Herb", {}) as Dictionary).get("rewardReceipt", "")) == "ch3Herb.v1.reward", "saved herb receipt")
	end_case()

func _CH3_SAVE_001() -> void:
	begin_case("CH3-SAVE-001", "v2 save migrates to v3 with ch3 defaults")
	sm.delete_save(SAVE_TMP)
	expect(int(sm.VERSION) == 3, "VERSION=%d" % sm.VERSION)
	var v2_save := {
		"version": 2,
		"flags": {"battle.liheng.won": true, "battle.ch2_thug.won": true, "battle.ch2_gesancheng.won": true, "dlg.ch2.lihengVouched": true},
		"quests": {
			"main.zhouCommission": "delivered",
			"side": {"schemaVersion": 1, "state": "completed", "rewardReceipt": "bambooCompanions.v1.promise"},
			"main.ch2Herbs": "completed",
			"side.ch2Spar": {"schemaVersion": 1, "state": "available", "rewardReceipt": null},
			"side.ch2Tea": {"schemaVersion": 1, "state": "completed", "rewardReceipt": "ch2Tea.v1.reward"},
		},
		"player": {"hp": 90, "potions": 2, "position": [1.0, 0.0, -20.0], "facing": 1},
	}
	write_json(SAVE_TMP, v2_save)
	var loaded: Dictionary = gs.load_game(SAVE_TMP)
	expect(loaded.get("ok", false) and int(loaded.get("version", -1)) == 2, "v2 load=%s" % [loaded])
	expect(gs.ch2_main_state == "completed" and gs.ch2_tea_receipt == "ch2Tea.v1.reward", "ch2 kept")
	expect(gs.ch3_main_state == "available", "ch3 main=%s" % gs.ch3_main_state)
	expect(gs.ch3_debt_state == "locked" and gs.ch3_herb_state == "locked", "ch3 sides")
	expect(gs.is_flag_true("dlg.ch2.lihengVouched") and not gs.is_flag_true("battle.ch3_stair.won"), "flags")
	var saved: Dictionary = gs.save_game(SAVE_TMP)
	expect(saved.get("ok", false), "resave failed")
	var raw := read_json(SAVE_TMP)
	expect(int(raw.get("version", 0)) == 3, "resaved version=%s" % raw.get("version"))
	var q: Dictionary = raw.get("quests", {})
	expect(str(q.get("main.ch3Hermitage", "")) == "available", "ch3 main saved")
	expect((q.get("side.ch3Debt", {}) as Dictionary).get("state", "") == "locked", "ch3 debt saved")
	end_case()

func _CH3_SAVE_002() -> void:
	begin_case("CH3-SAVE-002", "v3 roundtrip and invalid ch3 blocks rejected")
	sm.delete_save(SAVE_TMP)
	reset_ch3("gateHeld")
	gs.ch3_debt_state = "delivered"
	gs.ch3_herb_state = "completed"
	gs.ch3_herb_receipt = "ch3Herb.v1.reward"
	gs.flags["battle.ch3_chutie.won"] = true
	expect(gs.save_game(SAVE_TMP).ok, "save")
	var before := JSON.stringify(gs.to_dict())
	gs.reset_new_game()
	expect(gs.load_game(SAVE_TMP).ok, "load")
	expect(JSON.stringify(gs.to_dict()) == before, "roundtrip differs")
	var base := read_json(SAVE_TMP)
	var bad_main := base.duplicate(true)
	(bad_main["quests"] as Dictionary)["main.ch3Hermitage"] = 5
	var bad_side := base.duplicate(true)
	(bad_side["quests"] as Dictionary)["side.ch3Herb"] = "bad"
	var bad_receipt := base.duplicate(true)
	((bad_receipt["quests"] as Dictionary)["side.ch3Debt"] as Dictionary)["rewardReceipt"] = 7
	var future := base.duplicate(true)
	future["version"] = 4
	for v: Dictionary in [bad_main, bad_side, bad_receipt, future]:
		write_json(SAVE_TMP, v)
		var res: Dictionary = sm.load_state(SAVE_TMP)
		expect(not res.get("ok", true), "accepted bad save %s" % [v.get("quests", {})])
	end_case()

func _CH3_FLOW_001() -> void:
	begin_case("CH3-FLOW-001", "chapter 3 main + both sides through dialogue and battles")
	sm.delete_save(SAVE_FLOW)
	reset_ch3("locked", true)
	gs.normalize()
	expect(pick_id("gate.linzhaowan") == "ch3_setout", "setout pick=%s" % pick_id("gate.linzhaowan"))
	var so: Dictionary = await run_dialogue(db.pick_dialogue("gate.linzhaowan"), [0])
	expect(quest_effect(so, "main.ch3Hermitage", "accept") and gs.ch3_main_state == "accepted", "accept")
	expect((so.speakers as Array).has("旁白"), "setout narrator")
	var pre: Dictionary = await run_dialogue(db.pick_dialogue("stair.dashou"), [0])
	expect(pre.battles == ["ch3_stair"], "E1 request=%s" % [pre.battles])
	expect(win_battle("ch3_stair").get("ok", false), "E1 exit")
	var post1: Dictionary = await run_dialogue(db.pick_dialogue("battle_return.ch3_stair_victory"))
	expect(post1.finished and gs.is_flag_true("dlg.ch3.stairPostSeen"), "E1 post")
	await run_dialogue(db.pick_dialogue("stair.dashou"), [0])
	expect(gs.ch3_main_state == "stairCleared", "after tell=%s" % gs.ch3_main_state)
	var pre2: Dictionary = await run_dialogue(db.pick_dialogue("hermitage.chutie"), [0])
	expect(pre2.battles == ["ch3_chutie"], "E2 request=%s" % [pre2.battles])
	expect(win_battle("ch3_chutie").get("ok", false), "E2 exit")
	await run_dialogue(db.pick_dialogue("battle_return.ch3_chutie_victory"))
	expect(not gs.is_point_visible("hermitage.chutie"), "chutie still visible")
	await run_dialogue(db.pick_dialogue("hermitage.linzhaowan"), [0])
	expect(gs.ch3_main_state == "gateHeld", "after held=%s" % gs.ch3_main_state)
	expect(gs.ch3_debt_state == "available" and gs.ch3_herb_state == "available", "sides")
	# Side A: liheng -> wensu -> liheng.
	expect(pick_id("gate.liheng") == "ch3_debt_offer", "debt offer pick=%s" % pick_id("gate.liheng"))
	await run_dialogue(db.pick_dialogue("gate.liheng"), [0])
	expect(gs.ch3_debt_state == "accepted", "debt=%s" % gs.ch3_debt_state)
	expect(pick_id("hermitage.wensu") == "ch3_wensu_finale", "finale first pick=%s" % pick_id("hermitage.wensu"))
	await run_dialogue(db.pick_dialogue("hermitage.wensu"), [0])
	expect(gs.ch3_main_state == "completed", "main=%s" % gs.ch3_main_state)
	await run_dialogue(db.pick_dialogue("hermitage.wensu"))
	expect(gs.ch3_debt_state == "delivered", "debt=%s" % gs.ch3_debt_state)
	var settle: Dictionary = await run_dialogue(db.pick_dialogue("gate.liheng"))
	expect(int(settle.rewards) == 1 and gs.ch3_debt_state == "completed", "debt settle rewards=%d" % settle.rewards)
	expect(gs.save_game(SAVE_FLOW).ok and not gs.has_pending_settlement(), "debt save")
	# Side B: decline once (no effect), then fight.
	var later: Dictionary = await run_dialogue(db.pick_dialogue("hermitage.linzhaowan"), [1])
	expect(later.battles.is_empty() and gs.ch3_herb_state == "available", "decline started battle")
	var offer: Dictionary = await run_dialogue(db.pick_dialogue("hermitage.linzhaowan"), [0])
	expect(offer.battles == ["ch3_herb_thief"], "E3 request=%s" % [offer.battles])
	expect(win_battle("ch3_herb_thief").get("ok", false), "E3 exit")
	await run_dialogue(db.pick_dialogue("battle_return.ch3_herb_thief_victory"))
	var hs: Dictionary = await run_dialogue(db.pick_dialogue("hermitage.linzhaowan"))
	expect(quest_effect(hs, "side.ch3Herb", "settle") and gs.ch3_herb_state == "completed", "herb settle")
	expect(gs.save_game(SAVE_FLOW).ok, "herb save")
	expect(flags_only_allowed(), "unexpected flags=%s" % [gs.flags])
	end_case()

func vis_setup(ch2: String, ch3: String, liheng_won: bool, gsc_won: bool, chutie_won: bool) -> void:
	reset_state("delivered", "completed", liheng_won, true)
	gs.ch2_main_state = ch2
	gs.ch3_main_state = ch3
	gs.flags["battle.ch2_gesancheng.won"] = gsc_won
	gs.flags["battle.ch3_chutie.won"] = chutie_won

func _STEP10_VIS_001() -> void:
	begin_case("STEP10-VIS-001", "full NPC visibility table; one place per NPC; unlisted hidden")
	var always := ["village.zhoubo", "village.mingcheng"]
	# [ch2, ch3, liheng_won, gesancheng_won, chutie_won, visible points besides villages]
	var table := [
		["locked", "locked", false, false, false, ["bamboo.liheng", "bamboo.linzhaowan"]],
		["locked", "locked", true, false, false, ["bamboo.linzhaowan"]],
		["available", "locked", true, false, false, ["bamboo.linzhaowan"]],
		["accepted", "locked", true, false, false, ["gate.liheng", "gate.linzhaowan"]],
		# 厉横 never lingers in the grove once he guards the gate, even with an odd flag.
		["accepted", "locked", false, false, false, ["gate.liheng", "gate.linzhaowan"]],
		["toldByLiheng", "locked", true, false, false, ["gate.liheng", "yiting.gesancheng", "yiting.linzhaowan"]],
		# Split flags: chutie.won must not hide 葛三秤; gesancheng.won must not hide 褚铁.
		["toldByLiheng", "locked", true, false, true, ["gate.liheng", "yiting.gesancheng", "yiting.linzhaowan"]],
		["toldByLiheng", "locked", true, true, false, ["gate.liheng", "yiting.linzhaowan"]],
		["stationCleared", "locked", true, true, false, ["gate.liheng", "yiting.linzhaowan"]],
		["stationCleared", "locked", true, false, false, ["gate.liheng", "yiting.linzhaowan"]],
		["completed", "available", true, true, false, ["gate.liheng", "gate.linzhaowan"]],
		["completed", "accepted", true, true, false, ["gate.liheng", "stair.dashou", "stair.linzhaowan"]],
		["completed", "stairCleared", true, true, false, ["gate.liheng", "hermitage.chutie", "hermitage.linzhaowan"]],
		["completed", "stairCleared", true, false, false, ["gate.liheng", "hermitage.chutie", "hermitage.linzhaowan"]],
		["completed", "stairCleared", true, true, true, ["gate.liheng", "hermitage.linzhaowan"]],
		["completed", "gateHeld", true, true, true, ["gate.liheng", "hermitage.linzhaowan", "hermitage.wensu"]],
		["completed", "completed", true, true, true, ["gate.liheng", "hermitage.linzhaowan", "hermitage.wensu"]],
	]
	for row: Array in table:
		vis_setup(row[0], row[1], row[2], row[3], row[4])
		var want: Array = always + (row[5] as Array)
		for p: String in gs.VISIBILITY_POINTS:
			var got: bool = gs.is_point_visible(p)
			expect(got == want.has(p), "%s: ch2=%s ch3=%s lw=%s gw=%s cw=%s got=%s" % [p, row[0], row[1], row[2], row[3], row[4], got])
	# Exhaustive one-place check over every stage and independent flags.
	var ch2_states := ["locked", "available", "accepted", "toldByLiheng", "stationCleared", "completed", "unknown"]
	var ch3_states := ["locked", "available", "accepted", "stairCleared", "gateHeld", "completed", "unknown"]
	var listed := {}
	for who: String in gs.NPC_POINTS:
		for p: String in gs.NPC_POINTS[who]:
			listed[p] = true
	for p: String in gs.VISIBILITY_POINTS:
		expect(listed.has(p), "point %s not owned by an NPC" % p)
	for c2: String in ch2_states:
		for c3: String in ch3_states:
			for bits in 8:
				vis_setup(c2, c3, bits & 1 != 0, bits & 2 != 0, bits & 4 != 0)
				for who: String in gs.NPC_POINTS:
					var shown: Array[String] = []
					for p: String in gs.NPC_POINTS[who]:
						if gs.is_point_visible(p):
							shown.append(p)
					expect(shown.size() <= 1, "%s at %s (ch2=%s ch3=%s bits=%d)" % [who, shown, c2, c3, bits])
	# Every NPC interaction point in the data is listed; unlisted points are hidden.
	for p: String in db.db.get("interactionPoints", {}):
		if not p.begins_with("battle_return."):
			expect(gs.VISIBILITY_POINTS.has(p), "data point %s not in VISIBILITY_POINTS" % p)
	expect(not gs.is_point_visible("nowhere.ghost"), "unlisted point visible")
	end_case()

func _STEP10_SAVE_001() -> void:
	begin_case("STEP10-SAVE-001", "unknown save fields survive load -> save unchanged")
	sm.delete_save(SAVE_TMP)
	var v2_save := {
		"version": 2,
		"mystery": {"nested": [1, 2, {"deep": true}], "note": "from the future"},
		"flags": {"battle.liheng.won": true, "dlg.future.flag": true},
		"quests": {
			"main.zhouCommission": "delivered",
			"side": {"schemaVersion": 1, "state": "completed", "rewardReceipt": "bambooCompanions.v1.promise", "unknown": "keep-me"},
			"main.ch2Herbs": "accepted",
			"side.ch2Spar": {"schemaVersion": 1, "state": "locked", "rewardReceipt": null, "note": 42},
			"side.ch4Future": {"schemaVersion": 1, "state": "locked"},
		},
		"player": {"hp": 77, "potions": 1, "position": [1.0, 0.0, 2.0], "facing": 3, "gold": 120},
	}
	write_json(SAVE_TMP, v2_save)
	var original := read_json(SAVE_TMP)
	expect(gs.load_game(SAVE_TMP).get("ok", false), "load")
	expect(gs.save_game(SAVE_TMP).get("ok", false), "save")
	var raw := read_json(SAVE_TMP)
	expect(int(raw.get("version", 0)) == 3, "version=%s" % raw.get("version"))
	expect(JSON.stringify(raw.get("mystery")) == JSON.stringify(original["mystery"]), "top-level mystery=%s" % [raw.get("mystery")])
	var q: Dictionary = raw.get("quests", {})
	expect(str((q.get("side", {}) as Dictionary).get("unknown", "")) == "keep-me", "quests.side.unknown lost")
	expect(int((q.get("side.ch2Spar", {}) as Dictionary).get("note", -1)) == 42, "ch2Spar.note lost")
	expect(JSON.stringify(q.get("side.ch4Future")) == JSON.stringify(original["quests"]["side.ch4Future"]), "unknown quest block lost")
	expect(int((raw.get("player", {}) as Dictionary).get("gold", -1)) == 120, "player.gold lost")
	expect((raw.get("flags", {}) as Dictionary).get("dlg.future.flag", false) == true, "unknown flag lost")
	# Known fields still come from live state, never from the preserved copy.
	expect(str(q.get("main.ch2Herbs", "")) == "accepted" and int((raw.get("player", {}) as Dictionary).get("hp", 0)) == 77, "known fields")
	# Unknown ints stay ints in the file text (not 120.0 / 42.0).
	var text1 := read_raw(SAVE_TMP)
	expect(text1.contains("\"gold\": 120,") or text1.contains("\"gold\": 120\n"), "gold not written as int")
	expect(text1.contains("\"note\": 42") and not text1.contains("42.0"), "note not written as int")
	var m_start := text1.find("\"mystery\"")
	var m_end := text1.find("from the future", m_start)
	var mystery_text := text1.substr(m_start, m_end - m_start) if m_start >= 0 and m_end > m_start else ""
	expect(mystery_text != "" and not mystery_text.contains(".0") and mystery_text.contains("\"deep\": true"), "nested ints changed: %s" % mystery_text)
	# Second load -> save is byte-stable (saved_at line excluded).
	expect(gs.load_game(SAVE_TMP).get("ok", false), "reload")
	expect(gs.save_game(SAVE_TMP).get("ok", false), "second save")
	var text2 := read_raw(SAVE_TMP)
	expect(strip_saved_at(text1) == strip_saved_at(text2), "second save not byte-stable")
	expect(gs.load_game(SAVE_TMP).get("ok", false) and gs.save_game(SAVE_TMP).get("ok", false), "third save")
	expect(strip_saved_at(read_raw(SAVE_TMP)) == strip_saved_at(text2), "third save not byte-stable")
	# apply_dict with a wrong-typed player field reports failure instead of silently passing.
	var bad_player := {"flags": {}, "quests": {"main.zhouCommission": "accepted", "side": {"schemaVersion": 1, "state": "available"}},
		"player": {"hp": "full", "potions": 1}}
	expect(not gs.apply_dict(bad_player), "wrong-type hp accepted silently")
	expect(gs.hp == gs.MAX_HP and gs.potions == 1, "hp/potions after wrong type")
	var bad_pos := {"flags": {}, "quests": {"main.zhouCommission": "accepted", "side": {"schemaVersion": 1, "state": "available"}},
		"player": {"hp": 50, "position": ["x", 0, 0]}}
	expect(not gs.apply_dict(bad_pos), "wrong-type position accepted silently")
	var good := {"flags": {}, "quests": {"main.zhouCommission": "accepted", "side": {"schemaVersion": 1, "state": "available"}},
		"player": {"hp": 50}}
	expect(gs.apply_dict(good) and gs.hp == 50, "valid partial player rejected")
	gs.reset_new_game()
	expect(not gs.to_dict().has("mystery") and gs.unknown_fields().is_empty(), "new game kept unknown fields")
	end_case()

func strip_saved_at(text: String) -> String:
	var out: PackedStringArray = []
	for line: String in text.split("\n"):
		if not line.contains("\"saved_at\""):
			out.append(line)
	return "\n".join(out)

func _STEP10_SAVE_002() -> void:
	begin_case("STEP10-SAVE-002", "v1 -> v3 gets ch3 defaults; v4 rejected without touching file")
	sm.delete_save(SAVE_TMP)
	var v1_save := {
		"version": 1,
		"flags": {"battle.liheng.won": true},
		"quests": {
			"main.zhouCommission": "delivered",
			"side": {"schemaVersion": 1, "state": "completed", "rewardReceipt": "bambooCompanions.v1.promise"},
		},
		"player": {"hp": 100, "potions": 2, "position": [0.0, 0.0, 10.0], "facing": 0},
	}
	write_json(SAVE_TMP, v1_save)
	expect(gs.load_game(SAVE_TMP).get("ok", false), "v1 load")
	expect(gs.ch2_main_state == "available", "ch2=%s" % gs.ch2_main_state)
	expect(gs.ch3_main_state == "locked" and gs.ch3_debt_state == "locked" and gs.ch3_herb_state == "locked", "ch3 defaults")
	expect(gs.ch3_debt_receipt == null and gs.ch3_herb_receipt == null and gs.ch3_debt_schema == 1 and gs.ch3_herb_schema == 1, "ch3 receipts/schema")
	for f: String in ["battle.ch3_stair.won", "battle.ch3_chutie.won", "battle.ch3_herb_thief.won", "dlg.ch3.sendoffSeen"]:
		expect(gs.flags.has(f) and gs.flags[f] == false, "flag %s default" % f)
	expect(gs.save_game(SAVE_TMP).get("ok", false), "resave")
	var raw := read_json(SAVE_TMP)
	var q: Dictionary = raw.get("quests", {})
	expect(int(raw.get("version", 0)) == 3 and str(q.get("main.ch3Hermitage", "")) == "locked", "v3 ch3 main")
	for qk: String in ["side.ch3Debt", "side.ch3Herb"]:
		var block: Dictionary = q.get(qk, {})
		expect(str(block.get("state", "")) == "locked" and block.get("rewardReceipt", "x") == null and int(block.get("schemaVersion", 0)) == 1, "%s=%s" % [qk, block])
	# v4: rejected, file bytes and live state untouched, no backup written.
	sm.delete_save(SAVE_TMP)
	var future := v1_save.duplicate(true)
	future["version"] = 4
	write_json(SAVE_TMP, future)
	var before_bytes := FileAccess.get_file_as_bytes(SAVE_TMP)
	reset_ch3("gateHeld")
	gs.normalize()
	var before_state: String = JSON.stringify(gs.to_dict())
	var res: Dictionary = gs.load_game(SAVE_TMP)
	expect(not res.get("ok", true) and str(res.get("error", "")).contains("过新"), "v4 res=%s" % [res])
	expect(FileAccess.get_file_as_bytes(SAVE_TMP) == before_bytes, "v4 file bytes changed")
	expect(not sm.has_backup(SAVE_TMP), "v4 load wrote a backup")
	expect(JSON.stringify(gs.to_dict()) == before_state, "v4 load changed live state")
	end_case()

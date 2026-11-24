extends Node3D
## Vertical-slice entry point: builds the village/gate/bamboo world, wires the
## HUD and the existing dialogue runner, and owns proximity interaction.

const INTERACT_RANGE := 2.7

var world: OpenWorld
var hud: GameHUD
var _runner: Node
var _focus_target: Node3D = null
var _dialogue_active := false
var _capture_mode := ""
var _battle_panel: BattlePanel
var _pending_battle_id := ""
var _in_battle := false
var _recording := false
var _rec_dir := ""
var _rec_idx := 1
var _rec_acc := 0.0
const REC_FPS := 24.0
var _rec_fps := REC_FPS

func _ready() -> void:
	_capture_mode = _read_capture_mode()

	world = OpenWorld.new()
	world.name = "World"
	add_child(world)
	world.player.set_active(true)

	hud = GameHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind_world(world, world.player)
	hud.action_pressed.connect(_on_action_pressed)

	_runner = Node.new()
	_runner.name = "DialogueRunner"
	_runner.set_script(load("res://scripts/dialogue/dialogue_runner.gd"))
	add_child(_runner)
	_runner.call("bind", hud.dialogue_panel)
	_runner.connect("finished", _on_dialogue_finished)
	_runner.connect("battle_requested", _on_battle_requested)
	hud.dialogue_panel.cancel_requested.connect(func() -> void: _flavor_cancelled = true)

	_battle_panel = BattlePanel.new()
	_battle_panel.name = "BattlePanel"
	hud.add_child(_battle_panel)
	_battle_panel.battle_closed.connect(_on_battle_closed)
	_battle_panel.stats_changed.connect(hud.set_status_values)

	world.apply_state()

	hud.set_interaction("交谈", false)
	hud.show_toast("WASD / 摇杆移动　·　E / 主键交谈")

	if _capture_mode != "":
		_setup_capture.call_deferred()

func _exit_tree() -> void:
	# 退出/重载前放掉 GLB PackedScene 缓存，避免 dummy 渲染器 teardown 报 null。
	ToonModel.clear_scene_cache()

func _process(_delta: float) -> void:
	_focus_acc += _delta
	if _recording:
		_rec_acc += _delta
		var step := 1.0 / _rec_fps
		while _rec_acc >= step:
			_rec_acc -= step
			_dump_frame()
	GameState.player_position = world.player.global_position
	GameState.player_facing = world.player.facing
	if _dialogue_active or _in_battle or hud.is_modal_open():
		return
	# 交互聚焦 10Hz 足够，避免每帧遍历全部可交互对象。
	if _focus_acc >= 0.1:
		_focus_acc = 0.0
		_update_interaction_focus()

func _update_interaction_focus() -> void:
	var nearest: Node3D = null
	var best := INTERACT_RANGE
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		var target := node as Node3D
		if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
			continue
		if not target.has_method("set_prompt_visible"):
			continue
		var offset := target.global_position - world.player.global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist < best:
			best = dist
			nearest = target
	if nearest == _focus_target:
		return
	if _focus_target != null and is_instance_valid(_focus_target):
		_focus_target.set_prompt_visible(false)
	_focus_target = nearest
	if _focus_target != null:
		_focus_target.set_prompt_visible(true)
		hud.set_interaction(_focus_label(_focus_target), true)
	else:
		hud.set_interaction("交谈", false)

func _focus_label(target: Node3D) -> String:
	if target is EncounterNode:
		return (target as EncounterNode).interact_label
	return "交谈"

func _on_action_pressed() -> void:
	# 对话进行中：主键 = 推进对话（否则手机上点「交谈」会毫无反应）
	if _dialogue_active:
		hud.dialogue_panel.advance()
		return
	if _in_battle or hud.is_modal_open():
		return
	_activate_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not _dialogue_active and not _in_battle and not hud.is_modal_open():
		if _focus_target != null and is_instance_valid(_focus_target):
			get_viewport().set_input_as_handled()
			_activate_focus()

func _activate_focus() -> void:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return
	if _focus_target is EncounterNode:
		_interact_encounter(_focus_target as EncounterNode)
	elif _focus_target is WorldNpc:
		_start_dialogue(_focus_target as WorldNpc)
	_focus_target = null

func _start_dialogue(npc: WorldNpc) -> void:
	npc.face_towards(world.player.global_position)
	if npc.is_story():
		var dialogue := DialogueDB.pick_dialogue(npc.interact_point)
		if not dialogue.is_empty():
			_begin_dialogue(dialogue)
			return
	# 没有剧情对话的散人 NPC：轻量闲谈 + 隐藏分支，不接任务、不弹强制窗。
	_start_flavor_dialogue(npc)

# ------------------------------------------------------------------ 机缘 / 闲谈

func _interact_encounter(node: EncounterNode) -> void:
	var result: Dictionary = world.encounter_manager.interact(node)
	if result.is_empty():
		return
	node.set_prompt_visible(false)
	var title := str(result.get("title", "机缘"))
	var text := "%s · 修为 +%d" % [title, int(result.get("cultivation", 1))]
	if not bool(result.get("understood", true)):
		text = "看不真切 · " + text
	var item := str(result.get("item", ""))
	if item != "":
		text += " · " + _item_name(item) + " ×%d" % int(result.get("item_count", 1))
	var level_info: Dictionary = result.get("level_up", {})
	if int(level_info.get("levels_gained", 0)) > 0:
		text += " · 境界：" + str(level_info.get("realm", ""))
	hud.show_toast(text)
	hud.refresh()
	world.apply_state()

func _item_name(item_id: String) -> String:
	var names := {
		"herb": "草药", "herb_rare": "银脉药苗", "bamboo_leaf": "竹叶青",
		"whetstone": "磨剑石", "moss": "苔花", "cypress_seed": "崖柏籽",
		"incense": "残香", "old_coin": "旧钱", "jade_slip": "青玉片",
		"page_tingyu": "听雨残页", "manual_tingyu": "听雨剑谱",
		"manual_tianlong": "田陇引", "manual_liushui": "流水诀",
		"manual_shanjing": "山经剑录", "manual_shanmen": "山门刀谱",
		"manual_wangyou": "忘忧剑录", "manual_yunhai": "云海剑影",
		"gate_token": "旧门符",
	}
	return str(names.get(item_id, item_id))

var _flavor_cancelled := false
var _focus_acc := 0.0

func _start_flavor_dialogue(npc: WorldNpc) -> void:
	_dialogue_active = true
	_flavor_cancelled = false
	_focus_target = null
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if node.has_method("set_prompt_visible"):
			node.call("set_prompt_visible", false)
	world.player.set_active(false)
	hud.hide_toast()
	hud.set_explore_mode(false)
	npc.face_towards(world.player.global_position)
	GameState.record_talk(npc.npc_id)
	var talks := GameState.talk_count(npc.npc_id)
	var lines: Array[String] = []
	if not npc.greetings.is_empty():
		lines.append(str(npc.greetings[(talks - 1) % npc.greetings.size()]))
	if not npc.idle_lines.is_empty():
		lines.append(str(npc.idle_lines[(talks - 1) % npc.idle_lines.size()]))
	var ctx := _hidden_context(npc)
	var hidden := HiddenQuestDB.pick(npc.identity, ctx)
	if not hidden.is_empty():
		for line: String in HiddenQuestDB.lines(hidden):
			lines.append(line)
	for i in lines.size():
		if _flavor_cancelled:
			break
		var node := {
			"id": "flavor.%s.%d" % [npc.npc_id, i],
			"speaker": "npc",
			"nameOverride": npc.display_name,
			"text": lines[i],
		}
		hud.dialogue_panel.show_line(node, npc.display_name, lines[i], npc.portrait, "right")
		await hud.dialogue_panel.line_done
	if not _flavor_cancelled and not hidden.is_empty():
		for flag_name: String in HiddenQuestDB.record_flags(hidden):
			GameState.set_hidden_flag(flag_name)
	hud.dialogue_panel.hide_dialogue()
	_dialogue_active = false
	world.player.set_active(true)
	hud.set_explore_mode(true)
	hud.refresh()

func _hidden_context(npc: WorldNpc) -> Dictionary:
	return {
		"talk_count": GameState.talk_count(npc.npc_id),
		"talk_total": GameState.total_talks(),
		"inventory": GameState.inventory,
		"reputation": GameState.reputation,
		"time_of_day": GameClock.time_of_day(),
		"weather": GameClock.weather,
		"region": npc.region,
		"encounter_used": GameState.has_used_any_encounter(),
		"encounter_rarities_used": GameState.encounter_rarities_used,
		"flags": GameState.flags,
	}

func _begin_dialogue(dialogue: Dictionary) -> void:
	_dialogue_active = true
	_pending_battle_id = ""
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if node.has_method("set_prompt_visible"):
			node.call("set_prompt_visible", false)
	world.player.set_active(false)
	hud.hide_toast()
	hud.set_explore_mode(false)
	_runner.call("start", dialogue)

## DialogueRunner emits battle_requested (after flags + quest events) and then
## finished; the battle starts only after the post-dialogue save below.
func _on_battle_requested(battle_id: String) -> void:
	_pending_battle_id = battle_id

func _on_dialogue_finished(_effects: Array, cancelled: bool, _reward_count: int) -> void:
	_dialogue_active = false
	_focus_target = null
	# DQ-05: save first; the HUD only toasts cached rewards when the save lands.
	var saved := hud.settle_after_dialogue(cancelled)
	if cancelled and saved.is_empty():
		hud.show_toast("对话中断")
	var battle_id := _pending_battle_id
	_pending_battle_id = ""
	if not cancelled and battle_id != "":
		_enter_battle(battle_id)
		return
	world.player.set_active(true)
	hud.set_explore_mode(true)
	hud.refresh()
	world.apply_state()

# ------------------------------------------------------------------ battle

func _enter_battle(battle_id: String) -> void:
	_in_battle = true
	GameState.set_in_battle(true)
	world.player.set_active(false)
	hud.hide_toast()
	hud.set_explore_mode(false)
	_battle_panel.start(battle_id)

func _on_battle_closed(battle_id: String, victory: bool) -> void:
	_in_battle = false
	if victory:
		GameState.potions = int(_battle_panel.logic.get("potions"))
	var exit := GameState.leave_battle(battle_id, victory)
	world.apply_state()
	hud.refresh()
	if victory:
		if not exit.get("saved", false):
			hud.show_toast("存档失败：" + str(exit.get("error", "")))
		var back := DialogueDB.pick_dialogue(str(exit.get("return_point", "")))
		if not back.is_empty():
			_begin_dialogue(back)
			return
		hud.show_toast("胜了这一阵")
	else:
		hud.show_toast("暂且退下，稍后再来")
	world.player.set_active(true)
	hud.set_explore_mode(true)

# ------------------------------------------------------------------ captures

func _read_capture_mode() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			return arg.trim_prefix("--capture=")
	return ""

## Capture-only: put the run in a chapter-3 visibility state without writing a save.
func _preview_ch3(ch3_state: String) -> void:
	GameState.ch2_main_state = "completed"
	GameState.ch3_main_state = ch3_state
	GameState.normalize()
	world.apply_state()

func _setup_capture() -> void:
	if _capture_mode == "closeup_compare":
		await _capture_closeup_compare()
		return
	if _capture_mode == "npc_variety":
		await _capture_npc_variety()
		return
	if _capture_mode == "anim_walk" or _capture_mode == "anim_walk_34":
		await _capture_anim_walk()
		return
	if _capture_mode == "anim_battle" or _capture_mode == "anim_battle_side":
		await _capture_anim_battle()
		return
	if _capture_mode == "anim_npc":
		await _capture_anim_npc()
		return
	# 截图专用出生点覆盖：--spawn-x= / --spawn-z=（与 --pitch/--dist 同类的 A/B 工具参数，
	# 仅 --capture 模式生效，不影响正常游戏）。
	var spawn_x := 0.0
	var spawn_z := 0.0
	var has_spawn := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn-x="):
			spawn_x = float(arg.trim_prefix("--spawn-x="))
			has_spawn = true
		elif arg.begins_with("--spawn-z="):
			spawn_z = float(arg.trim_prefix("--spawn-z="))
			has_spawn = true
	if has_spawn:
		world.player.teleport(Vector3(spawn_x, world.ground_height_at(spawn_x, spawn_z) + 0.05, spawn_z), 0)
		world.camera.snap()
	if _capture_mode == "breath_still":
		hud.visible = true
		hud.set_explore_mode(false)
		_enter_battle("ch2_thug")
		await get_tree().create_timer(2.0).timeout
		var image := get_viewport().get_texture().get_image()
		if image != null:
			var path := ProjectSettings.globalize_path("res://captures/anim_battle_idle.png")
			image.save_png(path)
			print("CAPTURE_SAVED res://captures/anim_battle_idle.png")
		get_tree().quit()
		return
	match _capture_mode:
		"dialogue":
			_capture_near_zhoubo()
			var zhoubo := world.get_npc("zhoubo")
			if zhoubo != null:
				_update_interaction_focus()
				var dialogue := DialogueDB.pick_dialogue(zhoubo.interact_point)
				if not dialogue.is_empty():
					_start_dialogue(zhoubo)
		"hud":
			_capture_near_zhoubo()
			_update_interaction_focus()
			# 捕获用：锁定周伯，避免邻近散人抢焦点把提示压到技能按钮下面。
			var hud_npc := world.get_npc("zhoubo")
			if hud_npc != null:
				_focus_target = hud_npc
				hud_npc.set_prompt_visible(true)
				hud.set_interaction("交谈", true)
		"narration":
			# ch2_zc_07: v1.1 narrator line (portrait key transition.fade_black).
			_capture_near_zhoubo()
			var node := DialogueDB.get_node_data("ch2_zc_07")
			_dialogue_active = true
			hud.set_explore_mode(false)
			hud.dialogue_panel.show_line(node, DialogueDB.speaker_display_name(node),
				str(node.get("text", "")), DialogueDB.portrait_path(node), DialogueDB.speaker_side(node))
		"reward":
			# Simulated settlement: the reward text is cached, then the real
			# post-dialogue save runs and only its success shows the toast.
			_capture_near_zhoubo()
			GameState.reward_granted.emit("一碗粗茶")
			var res := hud.settle_after_dialogue(false)
			print("CAPTURE_REWARD_SAVE ok=", res.get("ok", false))
			await get_tree().create_timer(0.5).timeout
		"shenyan_close", "shenyan_walk":
			# Model check: same lighting, camera pulled in to ~2.6 m and the HUD hidden.
			if _capture_mode == "shenyan_close":
				_capture_open_ground(0)
			hud.visible = false
			world.camera.offset = Vector3(0.0, 1.55, 2.7)
			world.camera.look_height = 0.9
			world.camera.snap()
			if _capture_mode == "shenyan_walk":
				Input.action_press("move_right")
				world.camera.offset = Vector3(0.6, 1.55, 2.7)
		"shenyan_back":
			# Close back view: face away from the world-space camera (+Z).
			_capture_open_ground(4)
			hud.visible = false
			world.camera.offset = Vector3(0.0, 1.50, 2.8)
			world.camera.look_height = 0.95
			world.camera.snap()
		"shenyan_back45":
			# 45° close view of the left back and the sheathed sword.
			_capture_open_ground(5)
			hud.visible = false
			world.camera.offset = Vector3(0.0, 1.50, 2.8)
			world.camera.look_height = 0.95
			world.camera.snap()
		"npc_close":
			# 近距离核对 NPC 3D 材质/描边/受光（不参与正式三张验收图）。
			var npc := world.get_npc("zhoubo")
			if npc != null:
				world.player.visible = false
				world.player.teleport(npc.global_position + Vector3(0.0, 0.0, 1.0), 4)
				world.camera.target = npc
				world.camera.offset = Vector3(0.8, 1.55, 3.0)
				world.camera.look_height = 0.95
				world.camera.snap()
			hud.visible = false
		"yiting":
			# 驿亭 at the north end of the bamboo path, with 葛三秤 / 林照晚 forced visible.
			var yt := world.get_node_or_null("Yiting") as Node3D
			if yt != null:
				for id: String in ["gesancheng", "linzhaowan_yiting"]:
					var n := world.get_npc(id)
					if n != null:
						n.set_dormant(false)
				world.player.teleport(yt.global_position + Vector3(1.2, 0.0, 4.2), 4)
				world.camera.offset = Vector3(0.0, 8.6, 10.5)
				world.camera.look_height = 0.2
				world.camera.snap()
				world.camera.look_at(yt.global_position + Vector3(0.0, 1.4, 0.0), Vector3.UP)
		"npc_linzhaowan", "npc_liheng":
			# Model check for the 3D NPC GLBs: force the NPC visible, stand the
			# player beside it and use the normal explore camera.
			var npc_id := _capture_mode.trim_prefix("npc_")
			var npc := world.get_npc(npc_id)
			if npc != null:
				npc.set_dormant(false)
				world.player.teleport(npc.global_position + Vector3(1.3, 0.0, 1.6), 0)
				world.camera.snap()
		"stair":
			# 后山石阶 with 药行打手 / 林照晚, as after accepting chapter 3.
			_preview_ch3("accepted")
			var st := world.get_node_or_null("Stair") as Node3D
			if st != null:
				var look := st.global_position + Vector3(0.0, 1.4, 0.0)
				world.player.teleport(st.global_position + Vector3(1.1, world.ground_height_at(st.global_position.x + 1.1, st.global_position.z + 2.8) - st.global_position.y, 2.8), 4)
				world.camera.offset = Vector3(0.0, 8.4, 10.2)
				world.camera.look_height = 0.2
				world.camera.snap()
				world.camera.look_at(look, Vector3.UP)
		"hermitage":
			# 清溪庵 gate with 褚铁 / 林照晚, as after clearing the stairs.
			_preview_ch3("stairCleared")
			var hm := world.get_node_or_null("Hermitage") as Node3D
			if hm != null:
				var look := hm.global_position + Vector3(0.0, 1.6, 1.0)
				world.player.teleport(hm.global_position + Vector3(1.2, 0.0, 6.4), 4)
				world.camera.offset = Vector3(0.0, 8.8, 11.0)
				world.camera.look_height = 0.3
				world.camera.snap()
				world.camera.look_at(look, Vector3.UP)
		"battle":
			_enter_battle("ch2_thug")
			_battle_panel.call("_on_action", "attack")
	var wait := 3.0
	match _capture_mode:
		"dialogue", "battle":
			wait = 2.0
		"narration":
			wait = 2.6
		"reward":
			wait = 0.4
		"shenyan_walk":
			wait = 0.55
	await get_tree().create_timer(wait).timeout
	var layout_errors := hud.validate_layout()
	if layout_errors.is_empty():
		print("HUD_LAYOUT_OK")
	else:
		for issue: String in layout_errors:
			push_warning("HUD_LAYOUT: " + issue)
	if _capture_mode == "explore":
		for node: Node in world.find_children("GateTower", "Node3D", true, false):
			var n3 := node as Node3D
			print("DBG_GATE pos=", n3.global_position, " vis=", n3.visible, " in_tree=", n3.is_inside_tree())
		var zhoubo := world.get_npc("zhoubo")
		var npc_px := zhoubo.character.screen_height_px(world.camera) if zhoubo != null and zhoubo.character != null else 0.0
		print("CAPTURE_METRICS player_px=%.1f npc_px=%.1f fov=%.1f pitch=%.1f dist=%.1f look=%.2f" % [
			world.player.screen_height_px(world.camera), npc_px,
			world.camera.fov, world.camera.pitch_deg, world.camera.distance, world.camera.look_height])
	var path := "res://captures/%s.png" % _capture_mode
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(path)
		print("CAPTURE_SAVED ", path, " ", image.get_width(), "x", image.get_height())
	get_tree().quit()

func _capture_near_zhoubo() -> void:
	var zhoubo := world.get_npc("zhoubo")
	if zhoubo != null:
		# 斜前方站位：NPC 在玩家左前方，不和玩家重叠；距离 2.56m 仍在交互内。
		world.player.teleport(zhoubo.global_position + Vector3(1.6, 0.0, 2.0), 5)

func _capture_open_ground(facing: int) -> void:
	var y := world.ground_height_at(-30.0, 44.0)
	world.player.teleport(Vector3(-30.0, y + 0.05, 44.0), facing)

func _save_capture(name: String) -> void:
	var path := "res://captures/%s.png" % name
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(path)
		print("CAPTURE_SAVED ", path, " ", image.get_width(), "x", image.get_height())

## 第四轮对比图：同一机位 2.7m 近景，旧 shenyan.glb（TripoSR）→
## 新 shenyan_script（手写干净低模 + 单 surface 合并）。
func _capture_closeup_compare() -> void:
	hud.visible = false
	# before 必须用未合并/未清理的原始 shenyan.glb，才是第三轮真实外观。
	_swap_player_model("shenyan_legacy", true)
	_capture_open_ground(0)
	world.camera.offset = Vector3(0.0, 1.55, 2.7)
	world.camera.look_height = 0.9
	world.camera.snap()
	await get_tree().create_timer(1.4).timeout
	_save_capture("closeup_before")
	_swap_player_model("shenyan")
	world.camera.offset = Vector3(0.0, 1.55, 2.7)
	world.camera.look_height = 0.9
	world.camera.snap()
	await get_tree().create_timer(1.4).timeout
	_save_capture("closeup_after")
	# render_captures.sh 按 <mode>.png 校验产物；再存一份 after 作为该模式的
	# 受控文件，避免对比图被脚本判为失败。
	_save_capture("closeup_compare")
	get_tree().quit()

## 只给截图用：重建玩家 CharacterModel，换模型/身高不变。
func _swap_player_model(model_key: String, raw: bool = false) -> void:
	var old := world.player.character
	if old != null:
		world.player.remove_child(old)
		old.queue_free()
	var cm := CharacterModel.new()
	cm.name = "Character"
	cm.setup(model_key, 1.70, Color.WHITE, 0, true, false, raw)
	cm.set_speed(2.0)
	world.player.add_child(cm)
	world.player.character = cm

## 第四轮 NPC 群像：把 8 个 NPC 排成一排，优先覆盖 6 种配饰，
## 相机拉近到 8m，正面看清斗笠/头巾/背篓/围巾/腰带/提灯与体型差异。
func _capture_npc_variety() -> void:
	hud.visible = false
	world.player.visible = false
	var all: Array[WorldNpc] = []
	for npc_id: String in world.npcs:
		var npc := world.npcs[npc_id] as WorldNpc
		if npc != null:
			all.append(npc)
	# 先按配饰种类各取一个（保证 6 种），再按基础模型补足 8 个。
	var picked: Array[WorldNpc] = []
	var seen_kinds: Dictionary = {}
	for npc: WorldNpc in all:
		var kind := npc.character.accessory_kind if npc.character != null else ""
		if kind != "" and not seen_kinds.has(kind):
			seen_kinds[kind] = true
			picked.append(npc)
	var seen_models: Dictionary = {}
	for npc: WorldNpc in picked:
		seen_models[npc.character.model_key] = true
	for npc: WorldNpc in all:
		if picked.size() >= 8:
			break
		if npc in picked:
			continue
		var model_key: String = npc.character.model_key if npc.character != null else ""
		if not seen_models.has(model_key):
			seen_models[model_key] = true
			picked.append(npc)
	for npc: WorldNpc in all:
		if picked.size() >= 8:
			break
		if npc not in picked:
			picked.append(npc)
	for npc: WorldNpc in all:
		npc.set_dormant(npc not in picked)
	# 开阔地 (-30, 44)：与 shenyan_close 同一片空地，避免被村舍挡住。
	var base_z := 44.0
	var spacing := 1.1
	var start_x := -30.0 - (float(picked.size() - 1) * spacing * 0.5)
	for i in picked.size():
		var npc := picked[i]
		var x := start_x + float(i) * spacing
		var y := world.ground_height_at(x, base_z)
		npc.set_dormant(false)
		npc.global_position = Vector3(x, y, base_z)
		npc.home = Vector2(x, base_z)
		npc.wander_radius = 0.0
		# 背篓/提灯转 20–30° 侧身，让背后的篓和手里的灯在群像里看得见。
		var kind := npc.character.accessory_kind
		var yaw := 0.0
		if kind == "basket":
			yaw = 0.55
		elif kind == "lantern":
			yaw = -0.30
		npc.character.set_direction(Vector3(sin(yaw), 0.0, cos(yaw)))
		npc.character.apply_lod(8.0, true)
		npc.set_scene_budget(true, 8.0)
	# 玩家挪到相机后面，避免被算进同屏预算/挡镜头。
	var py := world.ground_height_at(-30.0, 55.0)
	world.player.teleport(Vector3(-30.0, py, 55.0), 0)
	var gy := world.ground_height_at(-30.0, base_z)
	var focus := Node3D.new()
	focus.name = "VarietyFocus"
	world.add_child(focus)
	focus.global_position = Vector3(-30.0, gy + 1.0, base_z)
	world.camera.target = focus
	world.camera.offset = Vector3(0.0, 1.6, 7.6)
	world.camera.look_height = 0.0
	world.camera.snap()
	var kinds: Array[String] = []
	for npc: WorldNpc in picked:
		kinds.append("%s/%s" % [
			npc.display_name,
			npc.character.accessory_kind if npc.character != null else "-"])
	print("NPC_VARIETY ", ", ".join(PackedStringArray(kinds)))
	await get_tree().create_timer(1.6).timeout
	_save_capture("npc_variety")
	get_tree().quit()

func _capture_anim_walk() -> void:
	hud.visible = false
	_rec_fps = 60.0
	var three_quarter := _capture_mode == "anim_walk_34"
	# Facing 2 (90°) is a side profile; facing 1 (45°) is a 3/4 view.
	# move_right walks along +X so the side view reads as a profile walk.
	# Do not use the courtyard still (-3.9, 11.9): that point already overlaps
	# the fence collider at (~-2.89, 11.6), so the character walks in place and
	# the follow camera freezes the background.
	# Open ground at the official spawn latitude, starting left of center.
	var gy := world.ground_height_at(-30.0, 44.0)
	world.player.teleport(Vector3(-30.0, gy, 44.0), 1 if three_quarter else 2)
	if three_quarter:
		world.camera.offset = Vector3(1.4, 1.55, 2.4)
	else:
		world.camera.offset = Vector3(0.2, 1.50, 3.1)
	world.camera.look_height = 0.9
	world.camera.snap()
	await get_tree().create_timer(0.3).timeout
	var tag := "anim_walk_34" if three_quarter else "anim_walk"
	var dir := "user://%s_frames" % tag
	_start_recording(dir)
	_save_rec_still("%s_start" % tag)
	var walk_start := world.player.global_position
	print("WALK_CAPTURE start ", walk_start)
	Input.action_press("move_right")
	await get_tree().create_timer(0.35).timeout
	_save_rec_still("%s_step" % tag)
	await get_tree().create_timer(1.8).timeout
	_save_rec_still("%s_stride" % tag)
	await get_tree().create_timer(1.6).timeout
	Input.action_release("move_right")
	var walk_end := world.player.global_position
	var travel := Vector2(walk_end.x - walk_start.x, walk_end.z - walk_start.z).length()
	print("WALK_CAPTURE end ", walk_end, " travel=", snapped(travel, 0.001), "m slides=", world.player.get_slide_collision_count())
	await get_tree().create_timer(1.2).timeout
	_save_rec_still("%s_stop" % tag)
	_stop_recording()
	# Mid-clip still is a unique walking frame, not a copy of stride/stop.
	_encode_movie(dir, "res://captures/%s.mp4" % tag, "res://captures/%s.png" % tag, 90, 60.0)
	print("CAPTURE_SAVED res://captures/%s.mp4" % tag)
	get_tree().quit()

func _capture_anim_battle() -> void:
	hud.visible = true
	hud.set_explore_mode(false)
	_rec_fps = 60.0
	_enter_battle("ch2_thug")
	if _capture_mode == "anim_battle_side" and _battle_panel != null:
		var stage: BattleStage = _battle_panel._stage
		if stage != null:
			stage.set_side_camera()
	await get_tree().create_timer(1.0).timeout
	var dir := "user://%s_frames" % ("anim_battle_side" if _capture_mode == "anim_battle_side" else "anim_battle")
	_start_recording(dir)
	_save_rec_still("anim_battle_idle_side" if _capture_mode == "anim_battle_side" else "anim_battle_idle")
	# Real fight through resolve_action (not the capture-only play_demo):
	# two sword skills, a basic cut while the thug winds up, guard the heavy,
	# then a finishing cut so the enemy fall plays on a real victory.
	if _battle_panel != null:
		var plan: Array[String] = ["skill", "skill", "attack", "guard", "attack"]
		var stills: Array[String] = [
			"anim_battle_skill1",
			"anim_battle_skill2",
			"anim_battle_charge",
			"anim_battle_guard",
			"anim_battle_finish",
		]
		for i in plan.size():
			if _battle_panel.logic != null and _battle_panel.logic.call("is_over"):
				break
			print("BATTLE_ACTION ", plan[i], " frame=", _rec_idx)
			await _battle_panel.resolve_action(plan[i])
			await get_tree().create_timer(0.5).timeout
			var still_name := stills[i]
			if _capture_mode == "anim_battle_side":
				still_name = still_name + "_side"
			_save_rec_still(still_name)
	# Hold the landed pose at least 0.5 s after it freezes (plus the 0.5 s
	# wait already spent after resolve_action, which includes the fall).
	await get_tree().create_timer(1.2).timeout
	var end_name := "anim_battle_end_side" if _capture_mode == "anim_battle_side" else "anim_battle_end"
	_save_rec_still(end_name)
	_stop_recording()
	var tag := "anim_battle_side" if _capture_mode == "anim_battle_side" else "anim_battle"
	_encode_movie(dir, "res://captures/%s.mp4" % tag, "res://captures/%s.png" % tag, 180, 60.0)
	print("CAPTURE_SAVED res://captures/%s.mp4" % tag)
	get_tree().quit()

func _capture_anim_npc() -> void:
	hud.visible = false
	var dir := "user://anim_npc_frames"
	_clear_frame_dir(dir)
	# 林照晚 at the bamboo path, then 葛三秤 at the yiting.
	await _record_npc_walk("linzhaowan", Vector3(-4.2, 0.0, -12.0), 3.2, dir, 1)
	# Stage 葛三秤 on the same open path; at the yiting he starts dormant
	# and is easy to hide behind the pavilion posts.
	await _record_npc_walk("gesancheng", Vector3(-1.2, 0.0, -10.5), 3.2, dir, _rec_idx)
	_stop_recording()
	_encode_movie(dir, "res://captures/anim_npc.mp4", "res://captures/anim_npc.png", 36)
	print("CAPTURE_SAVED res://captures/anim_npc.mp4")
	get_tree().quit()

func _record_npc_walk(npc_id: String, fallback_pos: Vector3, seconds: float, dir: String, start_or_continue: int) -> void:
	var npc := world.get_npc(npc_id)
	if npc == null:
		push_warning("NPC_CAPTURE missing " + npc_id)
		return
	if npc.has_method("set_dormant"):
		npc.set_dormant(false)
	npc.visible = true
	# Stage on the provided open-ground mark so architecture does not hide them.
	npc.global_position = fallback_pos
	var model := npc.find_child("Model", true, false) as Node3D
	if model == null:
		push_warning("NPC_CAPTURE no model " + npc_id)
		return
	var anim := CharacterAnim.new()
	anim.attach(npc, model)
	# A slightly unhurried walk for the close-up; scale matches the slide.
	var walk_speed := 1.85
	anim.set_walk_move_speed(walk_speed)
	# Hide the player so the camera (which follows them) can sit on the NPC
	# without 沈砚 filling the frame.
	var saved_visible := world.player.visible
	world.player.visible = false
	world.player.teleport(npc.global_position, 0)
	world.camera.offset = Vector3(0.35, 1.45, 2.55)
	world.camera.look_height = 0.9
	# Face the camera-right so a walk to +X reads clearly.
	npc.rotation.y = 0.0
	if model != null:
		model.rotation.y = PI * 0.5
	world.camera.snap()
	await get_tree().create_timer(0.25).timeout
	if start_or_continue <= 1:
		_start_recording(dir)
	# Walk a few steps to +X, then stop into idle.
	var saved_ref := npc.player_ref
	npc.player_ref = null
	var forward := Vector3(1.0, 0.0, 0.0)
	anim.set_moving(true)
	var t := 0.0
	while t < seconds:
		var dt := 1.0 / 24.0
		npc.global_position += forward * walk_speed * dt
		world.player.global_position = npc.global_position
		world.camera.snap()
		await get_tree().create_timer(dt).timeout
		t += dt
	anim.set_moving(false)
	await get_tree().create_timer(1.4).timeout
	npc.player_ref = saved_ref
	world.player.visible = saved_visible

func _clear_frame_dir(dir: String) -> void:
	var path := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(path)
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir():
			d.remove(fn)
		fn = d.get_next()

func _start_recording(dir: String) -> void:
	_clear_frame_dir(dir)
	_rec_dir = ProjectSettings.globalize_path(dir)
	_rec_idx = 1
	_rec_acc = 0.0
	_recording = true
	_dump_frame()

func _stop_recording() -> void:
	_recording = false

func _dump_frame() -> void:
	if _rec_dir == "":
		return
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/frame_%04d.png" % [_rec_dir, _rec_idx])
		_rec_idx += 1


func _save_rec_still(name: String) -> void:
	_dump_frame()
	var src := "%s/frame_%04d.png" % [_rec_dir, _rec_idx - 1]
	var dest := ProjectSettings.globalize_path("res://captures/%s.png" % name)
	if FileAccess.file_exists(src):
		DirAccess.copy_absolute(src, dest)
		print("CAPTURE_SAVED res://captures/%s.png frame=" % name, _rec_idx - 1)

func _encode_movie(frame_dir: String, mp4: String, still: String, still_index: int, fps: float = REC_FPS) -> void:
	var frames := ProjectSettings.globalize_path(frame_dir)
	var out := ProjectSettings.globalize_path(mp4)
	var still_src := "%s/frame_%04d.png" % [frames, still_index]
	if not FileAccess.file_exists(still_src):
		var mid := maxi(1, _rec_idx / 2)
		still_src = "%s/frame_%04d.png" % [frames, mid]
	if FileAccess.file_exists(still_src):
		var st := ProjectSettings.globalize_path(still)
		DirAccess.copy_absolute(still_src, st)
		print("CAPTURE_SAVED ", still)
	var args := PackedStringArray([
		"-y", "-framerate", str(fps), "-i", frames + "/frame_%04d.png",
		"-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", out,
	])
	OS.execute("ffmpeg", args)
	if FileAccess.file_exists(out):
		print("MOVIE_OK ", mp4)
	else:
		push_warning("MOVIE_FAILED " + mp4)

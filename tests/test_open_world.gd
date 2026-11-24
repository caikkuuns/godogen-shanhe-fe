extends Node
## 开放世界/机缘/NPC/隐藏分支/成长/分块加载的 headless 验收。
## 运行：godot --headless --path . res://tests/test_open_world.tscn
## 独立于 145 个剧情/战斗用例，输出 WORLD PASSED n / n。

var _passed: Array[String] = []
var _failed: Array[String] = []
var _case_id := ""
var _details: Array[String] = []

func _ready() -> void:
	await _run()

func begin_case(id: String) -> void:
	_case_id = id
	_details = []

func expect(cond: bool, detail: String) -> void:
	if not cond:
		_details.append(detail)

func end_case() -> void:
	if _details.is_empty():
		print("ok   ", _case_id)
		_passed.append(_case_id)
	else:
		print("FAIL ", _case_id)
		for d: String in _details:
			print("     - ", d)
		_failed.append(_case_id)

func _run() -> void:
	await _test_encounter_data()
	await _test_rarity_distribution()
	await _test_legendary_cap()
	await _test_refresh_and_used()
	await _test_hidden_conditions()
	await _test_npc_pool()
	await _test_no_forced_quests()
	await _test_growth()
	await _test_sprite_assets()
	await _test_chunk_loading()
	print("\nWORLD PASSED %d / %d cases" % [_passed.size(), _passed.size() + _failed.size()])
	if not _failed.is_empty():
		print("WORLD FAILED: ", ", ".join(PackedStringArray(_failed)))
	get_tree().quit(0 if _failed.is_empty() else 1)

# ------------------------------------------------------------------ 机缘

func _test_encounter_data() -> void:
	begin_case("WORLD-ENC-001 encounter data required fields + 8 regions")
	expect(EncounterDB.load_error == "", "load_error=%s" % EncounterDB.load_error)
	var errors := EncounterDB.validate()
	expect(errors.is_empty(), "validate: %s" % ", ".join(PackedStringArray(errors)))
	for region: Dictionary in EncounterDB.region_encounters(["village"]):
		pass
	var tags_by_region := {
		"village": ["village"], "farmland": ["farmland"], "bamboo": ["bamboo"],
		"brook": ["brook"], "mountain_road": ["mountain_road"], "gate": ["gate"],
		"cliff": ["cliff"], "shrine": ["shrine"],
	}
	for region_id: String in tags_by_region:
		var records := EncounterDB.region_encounters(tags_by_region[region_id])
		expect(records.size() >= 2, "%s has %d records" % [region_id, records.size()])
		var rarities := {}
		for record: Dictionary in records:
			rarities[str(record.get("rarity", ""))] = true
		expect(rarities.has("common") and rarities.has("rare"), "%s rarity mix %s" % [region_id, rarities.keys()])
	var kinds := {}
	for record: Dictionary in EncounterDB.entries:
		kinds[str(record.get("kind", ""))] = true
	for kind: String in ["combat", "npc", "item", "event", "lore"]:
		expect(kinds.has(kind), "kind %s missing" % kind)
	# 任何机缘都不允许有强制/锁定字段。
	for record: Dictionary in EncounterDB.entries:
		expect(not record.has("required") and not record.has("forced"), "%s has forced field" % record.get("id", "?"))
	end_case()

func _test_rarity_distribution() -> void:
	begin_case("WORLD-ENC-002 rarity 70/25/5 distribution")
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var counts := {"common": 0, "rare": 0, "legendary": 0}
	var n := 20000
	for i in n:
		counts[EncounterDB.roll_rarity(rng)] += 1
	var common := float(counts["common"]) / float(n)
	var rare := float(counts["rare"]) / float(n)
	var legend := float(counts["legendary"]) / float(n)
	expect(absf(common - 0.70) < 0.02, "common=%.4f" % common)
	expect(absf(rare - 0.25) < 0.02, "rare=%.4f" % rare)
	expect(absf(legend - 0.05) < 0.01, "legendary=%.4f" % legend)
	end_case()

func _test_legendary_cap() -> void:
	begin_case("WORLD-ENC-003 one legendary per region at a time")
	var tags_by_region := {
		"village": ["village", "home"], "farmland": ["farmland", "field"],
		"bamboo": ["bamboo", "forest"], "brook": ["brook", "water"],
		"mountain_road": ["mountain_road", "mountain"], "gate": ["gate", "mountain"],
		"cliff": ["cliff", "wind"], "shrine": ["shrine", "ruin"],
	}
	for region_id: String in tags_by_region:
		EncounterDB.reset_cycle(0.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 9001 + hash(region_id)
		var first := EncounterDB.pick_for_region(region_id, tags_by_region[region_id], 0.0, rng, "legendary")
		expect(not first.is_empty(), "%s no legendary candidate" % region_id)
		if first.is_empty():
			continue
		expect(str(first.get("rarity", "")) == "legendary", "%s first=%s" % [region_id, first.get("rarity")])
		EncounterDB.mark_spawned(first, region_id)
		var second := EncounterDB.pick_for_region(region_id, tags_by_region[region_id], 0.0, rng, "legendary")
		expect(str(second.get("rarity", "")) != "legendary",
			"%s second legendary leaked: %s" % [region_id, second.get("id", "?")])
	EncounterDB.reset_cycle(0.0)
	end_case()

func _test_refresh_and_used() -> void:
	begin_case("WORLD-ENC-004 24-minute refresh keeps used records across unload")
	EncounterDB.reset_cycle(0.0)
	var record := EncounterDB.get_record("enc.village.herb")
	expect(not record.is_empty(), "fixture missing")
	EncounterDB.mark_used("enc.village.herb", "village", 0.0)
	expect(EncounterDB.is_used("enc.village.herb", 10.0), "used record not retained")
	expect(not EncounterDB.refresh_if_due(23.0), "refreshed before 24 min")
	expect(EncounterDB.is_used("enc.village.herb", 23.0), "record expired early")
	expect(EncounterDB.refresh_if_due(24.0), "refresh at 24 min missing")
	expect(not EncounterDB.is_used("enc.village.herb", 24.0), "cooldown 24 did not expire at refresh")
	# 区块卸载只是管理器层面隐藏；EncounterDB 的 used 表不会被清空。
	EncounterDB.reset_cycle(0.0)
	EncounterDB.mark_used("enc.village.herb", "village", 5.0)
	expect(EncounterDB.used_count() == 1, "used_count=%d" % EncounterDB.used_count())
	expect(EncounterDB.is_used("enc.village.herb", 6.0), "record lost after region unload simulation")
	EncounterDB.reset_cycle(0.0)
	end_case()

# ------------------------------------------------------------------ 隐藏分支

func _test_hidden_conditions() -> void:
	begin_case("WORLD-HID-001 hidden conditions hit/miss + flags namespace")
	expect(HiddenQuestDB.load_error == "", "load_error=%s" % HiddenQuestDB.load_error)
	var errors := HiddenQuestDB.validate()
	expect(errors.is_empty(), "validate: %s" % ", ".join(PackedStringArray(errors)))
	expect(HiddenQuestDB.records.size() >= 6, "records=%d" % HiddenQuestDB.records.size())
	expect(HiddenQuestDB.identity_coverage().size() >= 3,
		"identity coverage=%d" % HiddenQuestDB.identity_coverage().size())
	var dusk := {}
	for record: Dictionary in HiddenQuestDB.records:
		if str(record.get("id", "")) == "hidden.woodcutter.dusk":
			dusk = record
	expect(not dusk.is_empty(), "woodcutter.dusk missing")
	if not dusk.is_empty():
		var ctx := {
			"talk_count": 2, "talk_total": 4, "inventory": {}, "reputation": 0,
			"time_of_day": "dusk", "weather": "clear", "region": "bamboo",
			"encounter_used": false, "encounter_rarities_used": [], "flags": {},
		}
		expect(HiddenQuestDB.evaluate(dusk, ctx), "dusk condition should hit")
		var miss := ctx.duplicate(true)
		miss["time_of_day"] = "day"
		expect(not HiddenQuestDB.evaluate(dusk, miss), "day should miss dusk record")
		expect(HiddenQuestDB.pick("taoist", ctx).is_empty(), "identity mismatch should miss")
		expect(HiddenQuestDB.pick("woodcutter", ctx).get("id", "") == "hidden.woodcutter.dusk", "pick mismatch")
		var flagged := ctx.duplicate(true)
		flagged["flags"] = {"dlg.hidden.woodcutter.dusk": true}
		expect(HiddenQuestDB.pick("woodcutter", flagged).is_empty(), "already-hit record re-picked")
	# 物品 + 时段条件
	var jade := {}
	for record: Dictionary in HiddenQuestDB.records:
		if str(record.get("id", "")) == "hidden.taoist.jade":
			jade = record
	if not jade.is_empty():
		var ctx2 := {
			"talk_count": 1, "talk_total": 1, "inventory": {"jade_slip": 1}, "reputation": 0,
			"time_of_day": "night", "weather": "clear", "region": "shrine",
			"encounter_used": true, "encounter_rarities_used": ["rare"], "flags": {},
		}
		expect(HiddenQuestDB.evaluate(jade, ctx2), "jade/night should hit")
		var no_item := ctx2.duplicate(true)
		no_item["inventory"] = {}
		expect(not HiddenQuestDB.evaluate(jade, no_item), "jade missing should miss")
	# 未知条件键不能静默通过。
	var bogus := {"conditions": {"bogus_key": true}}
	expect(not HiddenQuestDB.evaluate(bogus, {}), "unknown condition accepted")
	end_case()

# ------------------------------------------------------------------ NPC / 无强制任务

func _test_npc_pool() -> void:
	begin_case("WORLD-NPC-001 deterministic unique 18-NPC pool, 8 identities, 3 voices")
	expect(NpcDB.load_error == "", "load_error=%s" % NpcDB.load_error)
	var errors := NpcDB.validate()
	expect(errors.is_empty(), "validate: %s" % ", ".join(PackedStringArray(errors)))
	var a := NpcDB.generate()
	expect(a.size() == 18, "generated=%d" % a.size())
	var ids := {}
	var names := {}
	var identities := {}
	var voices := {}
	for npc: Dictionary in a:
		ids[str(npc.get("id", ""))] = true
		names[str(npc.get("name", ""))] = true
		identities[str(npc.get("identity", ""))] = true
		voices[str(npc.get("personality", ""))] = true
		expect(str(npc.get("sprite", "")) != "", "npc without sprite")
		expect(float(npc.get("home", [0, 0])[0]) != 0.0, "npc without home")
	expect(ids.size() == 18, "ids=%d" % ids.size())
	expect(names.size() == 18, "unique names=%d" % names.size())
	expect(identities.size() >= 8, "identities=%d" % identities.size())
	expect(voices.size() >= 3, "voices=%d" % voices.size())
	var b := NpcDB.generate()
	expect(JSON.stringify(a) == JSON.stringify(b), "generation not deterministic")
	var c := NpcDB.generate(60, 7788)
	var names60 := {}
	for npc: Dictionary in c:
		names60[str(npc.get("name", ""))] = true
	expect(names60.size() == 60, "60-pool names=%d" % names60.size())
	end_case()

func _test_no_forced_quests() -> void:
	begin_case("WORLD-NPC-002 hidden branches never lock quests/flags")
	var quests := ["main_state", "side_state", "ch2_main_state", "ch2_spar_state",
		"ch2_tea_state", "ch3_main_state", "ch3_debt_state", "ch3_herb_state"]
	GameState.reset_new_game()
	var before := {}
	for key: String in quests:
		before[key] = GameState.get(key)
	var flags_before := GameState.flags.duplicate(true)
	for record: Dictionary in HiddenQuestDB.records:
		expect(not record.has("quest"), "%s has quest field" % record.get("id", "?"))
		expect(record.get("required", false) != true, "%s is required" % record.get("id", "?"))
		for key: String in HiddenQuestDB.record_flags(record):
			expect(key.begins_with("dlg.hidden."), "%s flag namespace %s" % [record.get("id", "?"), key])
		for cond: String in (record.get("conditions", {}) as Dictionary):
			expect(not cond.begins_with("quest"), "%s condition reads quest %s" % [record.get("id", "?"), cond])
	# 写隐藏 flag 不改变任何 quest 状态，也不产生“已接取”。
	expect(GameState.set_hidden_flag("dlg.hidden.test.round"), "hidden flag write failed")
	for key: String in quests:
		expect(GameState.get(key) == before[key], "%s changed to %s" % [key, GameState.get(key)])
	expect(GameState.flags["dlg.hidden.test.round"] == true, "hidden flag missing")
	for key: String in flags_before:
		expect(GameState.flags.get(key) == flags_before[key], "existing flag %s changed" % key)
	expect(not GameState.set_hidden_flag("quest.hidden.fake"), "non-dlg flag accepted")
	GameState.reset_new_game()
	end_case()

# ------------------------------------------------------------------ 成长 / 素材

func _test_growth() -> void:
	begin_case("WORLD-GROW-001 1..20 curve, 1-3 per encounter, no exploration lock")
	GameState.reset_new_game()
	expect(GameState.level == 1 and GameState.cultivation == 0, "new game growth defaults")
	var last := 0
	for lv in range(1, 20):
		var need := GameState.xp_to_next(lv)
		expect(need > last, "xp curve not increasing at %d (%d <= %d)" % [lv, need, last])
		last = need
	var guard := 0
	while GameState.level < 20 and guard < 2000:
		guard += 1
		var res := GameState.add_cultivation(3)
		expect(int(res.get("gained", 0)) <= 3, "single encounter gave >3")
	expect(GameState.level == 20, "level=%d" % GameState.level)
	expect(GameState.add_cultivation(3).get("gained", 0) == 0, "max level keeps gaining")
	expect(GameState.can_understand("1-10") and GameState.can_understand("11-20"),
		"max level should read 1-20 bands")
	expect(not GameState.can_understand("21-30"), "level 20 should not read 21-30")
	GameState.reset_new_game()
	expect(not GameState.can_understand("21-30"), "low level reads 21-30")
	expect(GameState.level_band_for_level() == "1-10", "level band")
	GameState.reset_new_game()
	end_case()

func _test_sprite_assets() -> void:
	begin_case("WORLD-ART-001 3D toon characters (cached GLB, 1.70m, shadow, outline)")
	# 所有人物 GLB 都在，且 PackedScene 缓存命中同一个资源。
	for key: String in CharacterModel.MODELS:
		var path := str(CharacterModel.MODELS[key])
		expect(ResourceLoader.exists(path), "%s GLB missing" % key)
		expect(ToonModel.scene_for(path) != null, "%s scene load failed" % key)
		expect(ToonModel.scene_for(path) == ToonModel.scene_for(path), "%s scene not cached" % key)
	# 主角：精确 1.70m、脚底 y=0、有 idle/walk、有描边、会投影。
	var probe := CharacterModel.new()
	probe.setup("shenyan", 1.70, Color.WHITE, 0)
	add_child(probe)
	await get_tree().process_frame
	await get_tree().process_frame
	expect(probe.model != null, "player 3D model missing")
	expect(probe.shadow != null, "blob shadow missing")
	expect(probe.model.find_children("*", "Sprite3D", true, false).is_empty(),
		"3D character still contains Sprite3D")
	var anim := probe.model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	expect(anim != null and anim.has_animation("idle") and anim.has_animation("walk"),
		"idle/walk animation missing")
	var body: MeshInstance3D = null
	for node: Node in probe.model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		# 精确匹配主身体，排除 "ShenyanBackSword"。
		if mi.mesh != null and mi.name == "Shenyan":
			body = mi
			break
	expect(body != null, "body mesh missing")
	if body != null:
		# 世界空间 AABB：网格节点自身可能带导入变换，不能只看 node 原点。
		var world_box := body.global_transform * body.get_aabb()
		var height := world_box.size.y
		expect(absf(height - 1.70) < 0.03, "height=%.3f" % height)
		expect(absf(world_box.position.y) < 0.04, "feet float y=%.3f" % world_box.position.y)
		expect(body.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"3D character does not cast shadow")
		# 第四轮：84 个 GLB mesh 合并成 1 个 surface。
		expect(body.mesh != null and body.mesh.get_surface_count() == 1,
			"character surfaces=%d != 1 (mesh merge failed)" % (body.mesh.get_surface_count() if body.mesh != null else -1))
		var mat := body.get_surface_override_material(0)
		expect(mat != null, "toon material missing")
		if mat != null:
			expect(mat.next_pass != null, "ink hull outline missing")
	expect(probe.shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"blob shadow must not cast real shadow")
	# NPC 轮换：4 个模型都可选，色相/明度微调有差异且幅度 ≤8%。
	var tints := {}
	for i in 8:
		var key := CharacterModel.NPC_POOL[i % CharacterModel.NPC_POOL.size()]
		expect(CharacterModel.MODELS.has(key), "NPC pool key %s missing" % key)
		var c := CharacterModel.variant_tint(Color("#d0c0a8"), 1000 + i)
		tints[c.to_html()] = true
		expect(absf(c.v - Color("#d0c0a8").v) <= 0.09, "variant value out of range")
	expect(tints.size() > 1, "NPC tint variants all identical")
	for cid: String in ["zhoubo", "mingcheng", "liheng", "linzhaowan"]:
		var path := str(OpenWorld.PORTRAITS.get(cid, ""))
		expect(path != "" and ResourceLoader.exists(path), "%s portrait missing" % cid)
	var npc_probe := WorldNpc.new()
	npc_probe.npc_id = "npc.test"
	npc_probe.display_name = "测试"
	npc_probe.height_m = 1.68
	npc_probe.sprite_tint = Color("#d0c0a8")
	add_child(npc_probe)
	await get_tree().process_frame
	await get_tree().process_frame
	expect(npc_probe.character != null and npc_probe.character.model != null, "NPC 3D model missing")
	expect(npc_probe.character.model_glb in CharacterModel.MODELS.values(), "NPC model not in pool")
	# 第四轮 NPC 差异：程序化配饰 + 体型 ±8% + 单 surface。
	expect(npc_probe.character.accessory_kind != "", "NPC procedural accessory missing")
	expect(npc_probe.character.width_scale >= 0.919 and npc_probe.character.width_scale <= 1.081,
		"NPC width_scale=%.3f out of ±8%%" % npc_probe.character.width_scale)
	# 身体 1 + 剧情随身道具最多 2（葛三秤秤杆/秤砣）+ 配饰最多 2。
	expect(npc_probe.character.model.find_children("*", "MeshInstance3D", true, false).size() <= 5,
		"NPC still has too many mesh instances")
	expect(npc_probe.find_child("NameLabel", true, false) != null, "NPC name label missing")
	var label := npc_probe.find_child("NameLabel", true, false) as Label3D
	expect(label != null and is_equal_approx(label.visibility_range_end, 12.0),
		"NPC name label visibility_range_end != 12")
	npc_probe.queue_free()
	probe.queue_free()
	end_case()

# ------------------------------------------------------------------ 分块加载

func _test_chunk_loading() -> void:
	begin_case("WORLD-CHUNK-001 3x3 streaming, 9 loaded, no node leak")
	var world := OpenWorld.new()
	world.name = "TestWorld"
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	expect(world.loaded_chunk_count() == 9, "initial chunks=%d" % world.loaded_chunk_count())
	var initial_ids := world.loaded_chunk_ids()
	var child_before := world.get_child_count()
	var chunk_nodes_before := world.find_children("Chunk_*", "Node3D", true, false).size()
	# 统计地表 MultiMesh 实例，验证同屏预算。
	# 第四轮跨区块合批后，区块里的原始 MultiMesh 已降级为数据并释放，
	# 必须从 world 全域统计（含 GlobalStaticBatches 下的合并实例）。
	var instances := 0
	for mmi: Node in world.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (mmi as MultiMeshInstance3D).multimesh
		if mm != null:
			instances += mm.instance_count
	expect(instances <= 3000, "same-screen multimesh instances=%d > 3000" % instances)
	var mesh_instances := 0
	for chunk_id: Vector2i in initial_ids:
		var chunk := world._chunks[chunk_id] as Node3D
		mesh_instances += chunk.find_children("*", "MeshInstance3D", true, false).size()
	expect(mesh_instances <= 250, "static MeshInstance3D=%d > 250 after batching" % mesh_instances)
	print("     chunk detail: multimesh_instances=%d static_meshes=%d" % [instances, mesh_instances])
	# 机缘交互：主键触发、加修为/物品、写 used，不做任何强制切场景。
	var enc_node: EncounterNode = null
	for candidate: Node in get_tree().get_nodes_in_group("interactable"):
		if candidate is EncounterNode:
			enc_node = candidate as EncounterNode
			break
	expect(enc_node != null, "no encounter node spawned")
	if enc_node != null:
		var used_before := EncounterDB.used_count()
		var res: Dictionary = world.encounter_manager.interact(enc_node)
		expect(res.get("ok", false), "encounter interact failed")
		expect(int(res.get("cultivation", 0)) >= 1, "encounter gave no cultivation")
		expect(enc_node.used, "encounter node not marked used")
		expect(EncounterDB.used_count() == used_before + 1, "used record not written")
		expect(not GameState.encounter_rarities_used.is_empty(), "encounter rarity not recorded")
		expect(GameState.hp >= 1, "encounter reduced hp below 1")
	# 移动到相邻区块中心：仍只保留 3x3，旧的区块节点被释放。
	var target_y := world.ground_height_at(30.0, 30.0)
	world.player.teleport(Vector3(30.0, target_y + 0.1, 30.0), 4)
	world.update_chunks(true)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	expect(world.loaded_chunk_count() == 9, "after move chunks=%d" % world.loaded_chunk_count())
	var after_ids := world.loaded_chunk_ids()
	var moved := false
	for id: Vector2i in after_ids:
		if id == Vector2i(2, 2):
			moved = true
	expect(moved, "target chunk (2,2) not loaded")
	# 区块节点数量不增长；旧区块（0,1）应已不在树中。
	var chunk_nodes_after := world.find_children("Chunk_*", "Node3D", true, false).size()
	expect(chunk_nodes_after == chunk_nodes_before, "chunk nodes %d -> %d" % [chunk_nodes_before, chunk_nodes_after])
	expect(world.get_child_count() <= child_before + 2, "world children leaked %d -> %d" % [child_before, world.get_child_count()])
	for id: Vector2i in after_ids:
		expect(not (id == Vector2i(0, 1)), "old chunk (0,1) still loaded")
	# 离开区块不丢已用机缘记录（管理器/DB 层）。
	EncounterDB.reset_cycle(0.0)
	var before_used := EncounterDB.used_count()
	EncounterDB.mark_used("enc.village.herb", "village", 0.0)
	world.update_chunks(true)
	expect(EncounterDB.used_count() == before_used + 1, "used record dropped on chunk update")
	EncounterDB.reset_cycle(0.0)
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	end_case()

extends SceneTree
## 探索移动手感：归一化、摇杆死区、加减速和脚步播放速率。

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _run() -> void:
	_expect(ExplorerPlayer.normalize_move_input(Vector2(0.19, 0.0)).is_zero_approx(),
		"0.19 轻推不应移动")
	_expect(ExplorerPlayer.normalize_move_input(Vector2(0.20, 0.0)).is_zero_approx(),
		"死区边界不应抖动")
	_expect(ExplorerPlayer.normalize_move_input(Vector2.ONE).length() <= 1.0001,
		"斜向输入超过全速")
	var diagonal := ExplorerPlayer.normalize_move_input(Vector2.ONE)
	_expect(absf(diagonal.x - diagonal.y) < 0.0001, "斜向输入未归一化")
	var partial := ExplorerPlayer.normalize_move_input(Vector2(0.60, 0.0))
	_expect(is_equal_approx(partial.length(), 0.5), "死区外力度未线性映射")
	_expect(CharacterModel.MOVE_XFADE >= 0.08 and CharacterModel.MOVE_XFADE <= 0.12,
		"起步/停步交叉淡化不在 0.08–0.12 秒")
	_expect(ExplorerPlayer.DECELERATION > ExplorerPlayer.ACCELERATION,
		"停步应比起步略快，但不能硬切")

	var player := ExplorerPlayer.new()
	root.add_child(player)
	await process_frame
	# 停用玩家（如对话中）：即使按住移动键，也必须停在 idle。
	# 第五轮起动画由 _physics_process 里的真实位移驱动，不能直接改 character。
	Input.action_press("move_up")
	player.set_active(false)
	await process_frame
	await process_frame
	var anim := player.character.model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_expect(anim != null and anim.current_animation == "idle", "停用玩家后没有切回 idle")
	# 重新启用：真实输入驱动位移，walk 播放速率跟随实际速度（满速 2.0 / 2.0 = 1.0）。
	player.set_active(true)
	for i in 20:
		await physics_frame
	_expect(anim != null and anim.current_animation == "walk", "起步没有切到 walk")
	_expect(anim != null and is_equal_approx(anim.speed_scale,
		ExplorerPlayer.SPEED / CharacterModel.WALK_BASE_SPEED), "walk 未按实际速度缩放")
	Input.action_release("move_up")
	for i in 20:
		await physics_frame
	_expect(anim != null and anim.current_animation == "idle", "停步没有切回 idle")
	player.queue_free()
	await process_frame
	ToonModel.clear_scene_cache()
	if _failures.is_empty():
		print("MOVEMENT_TEST ok deadzone=0.20 xfade=", CharacterModel.MOVE_XFADE,
			" diagonal_normalized=true speed_sync=true")
		quit()
	else:
		for failure in _failures:
			printerr("MOVEMENT_TEST FAIL ", failure)
		quit(1)

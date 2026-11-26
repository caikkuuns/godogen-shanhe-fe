extends Node
## Walks a dialogue graph. Flags/effects accumulate and only commit when the
## player reaches an end node; cancelling throws the whole pending batch away.

signal finished(effects: Array, cancelled: bool, reward_count: int)
## Emitted during commit, after flags and quest events, exactly once per startBattle.
signal battle_requested(battle_id: String)

var panel: DialoguePanel
var current_dialogue_id := ""
var _active := false
var _cancelled := false
var _pending_flags: Dictionary = {}
var _pending_effects: Array = []

func _ready() -> void:
	if panel != null:
		_connect_panel()

func bind(dialogue_panel: DialoguePanel) -> void:
	panel = dialogue_panel
	_connect_panel()

func _connect_panel() -> void:
	if panel == null:
		return
	if not panel.cancel_requested.is_connected(_on_cancel_requested):
		panel.cancel_requested.connect(_on_cancel_requested)

func is_active() -> bool:
	return _active

func start(dialogue: Dictionary) -> void:
	if _active:
		return
	if panel == null:
		push_error("DialogueRunner has no panel")
		return
	if dialogue.is_empty() or not GameState.conditions_ok(dialogue.get("conditions", [])):
		# Selection already filters these; a direct caller gets the same contract.
		finished.emit([], true, 0)
		return
	_active = true
	_cancelled = false
	current_dialogue_id = str(dialogue.get("id", ""))
	_pending_flags.clear()
	_pending_effects.clear()
	_run(dialogue)

func _on_cancel_requested() -> void:
	if _active:
		_cancelled = true

func _merge_node(node: Dictionary) -> void:
	var flags: Variant = node.get("setFlags", {})
	if typeof(flags) == TYPE_DICTIONARY:
		for key: String in flags:
			_pending_flags[key] = flags[key]
	var fx: Variant = node.get("effects", [])
	if typeof(fx) == TYPE_ARRAY:
		for effect: Variant in fx:
			if typeof(effect) == TYPE_DICTIONARY:
				_pending_effects.append(effect)

func _run(dialogue: Dictionary) -> void:
	var node_id := str(dialogue.get("entry", ""))
	var visited: Dictionary = {}
	while _active:
		if visited.has(node_id):
			push_error("DialogueRunner: cycle at %s" % node_id)
			_abort()
			return
		visited[node_id] = true
		var node := DialogueDB.get_node_data(node_id)
		if node.is_empty():
			_abort()
			return
		if current_dialogue_id != "" and str(node.get("dialogue", "")) != current_dialogue_id:
			push_error("DialogueRunner: node %s belongs to %s, not %s" %
				[node_id, str(node.get("dialogue", "?")), current_dialogue_id])
			_abort()
			return
		var conds: Array = node.get("conditions", [])
		if not GameState.conditions_ok(conds):
			_abort()
			return
		_merge_node(node)
		var side := DialogueDB.speaker_side(node)
		panel.show_line(node, DialogueDB.speaker_display_name(node), str(node.get("text", "")),
			DialogueDB.portrait_path(node), side)
		await panel.line_done
		if not _active or _cancelled:
			_abort()
			return
		if node.get("end", false) == true:
			break
		if node.has("choices"):
			var options: Array = []
			for choice: Variant in node.get("choices", []):
				if typeof(choice) == TYPE_DICTIONARY:
					var cconds: Array = choice.get("conditions", [])
					if GameState.conditions_ok(cconds):
						options.append(choice)
			if options.is_empty():
				# 第10轮修复：选项全被条件过滤掉时，之前直接 _abort()，把这段
				# 对话前面已经累积的剧情标记一并丢掉。改成先提交已累积的标记，
				# 再结束，避免玩家的进度被吞。
				push_warning("DialogueRunner: 节点 %s 的选项全部被条件过滤，提前收尾"
					% str(node.get("id", "?")))
				_abort(true)
				return
			panel.show_choices(options)
			var index: int = await panel.choice_selected
			# 上界也要校验：越界访问 options[index] 会直接抛错。
			if not _active or _cancelled or index < 0 or index >= options.size():
				_abort()
				return
			var choice: Dictionary = options[index]
			node_id = str(choice.get("next", ""))
		else:
			node_id = str(node.get("next", ""))
	if not _active:
		return

	# Commit order is fixed: flags -> quest events -> startBattle.
	GameState.commit_dialogue_flags(_pending_flags)
	var reward_count := 0
	for effect: Dictionary in _pending_effects:
		if str(effect.get("type", "")) == "questEvent":
			var res := GameState.dispatch_quest_event(str(effect.get("quest", "")), str(effect.get("event", "")))
			if res.get("reward", false):
				reward_count += 1
	for effect: Dictionary in _pending_effects:
		if str(effect.get("type", "")) == "startBattle":
			battle_requested.emit(str(effect.get("battleId", "")))
	panel.hide_dialogue()
	_active = false
	current_dialogue_id = ""
	var committed := _pending_effects.duplicate(true)
	_pending_flags.clear()
	_pending_effects.clear()
	finished.emit(committed, false, reward_count)

## 中止本段对话。
## commit_pending=true 时先把已经累积的 flags 落到 GameState——选项被条件
## 全部过滤掉属于"剧本设计得走不下去了"，不是玩家取消，前面读到的剧情
## 标记不该一起丢掉。
func _abort(commit_pending: bool = false) -> void:
	if not _active:
		return
	if commit_pending and not _pending_flags.is_empty():
		GameState.commit_dialogue_flags(_pending_flags)
	_active = false
	_cancelled = false
	current_dialogue_id = ""
	_pending_flags.clear()
	_pending_effects.clear()
	if panel != null:
		panel.hide_dialogue()
	finished.emit([], true, 0)

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
				_abort()
				return
			panel.show_choices(options)
			var index: int = await panel.choice_selected
			if not _active or _cancelled or index < 0:
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

func _abort() -> void:
	if not _active:
		return
	_active = false
	_cancelled = false
	current_dialogue_id = ""
	_pending_flags.clear()
	_pending_effects.clear()
	if panel != null:
		panel.hide_dialogue()
	finished.emit([], true, 0)

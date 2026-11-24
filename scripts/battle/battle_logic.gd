class_name BattleLogic
extends RefCounted
## Deterministic turn-based battle, no randomness. One player vs 厉横.
## Pure logic so it can be tested headlessly.

const D := preload("res://scripts/battle/battle_data.gd")

const ACTIONS: Array[String] = ["attack", "skill", "guard", "potion"]

var hp: int
var qi: int
var potions: int
var enemy_hp: int
var judging := false
var guarding := false
var enemy_step := 0
var enemy_charging := false
var round_no := 0
var won := false
var lost := false
## Presentation-ready combat log; the battle UI can render these lines as-is.
var log_lines: Array[String] = []

var entry_hp := D.PLAYER_MAX_HP
var entry_potions := D.PLAYER_START_POTIONS

var battle_id := D.DEFAULT_BATTLE_ID
var enemy_name := "厉横"
var enemy_max_hp := D.ENEMY_MAX_HP
var enemy_attack := D.ENEMY_ATTACK
var enemy_defense := D.ENEMY_DEFENSE
var enemy_cycle: Array = []
var charge_log := D.ENEMY_CHARGE_LOG
var heavy_log := D.ENEMY_HEAVY_LOG
var intro_log := ""

## The caller may pass the exploration HP/potion counts as the entry snapshot.
func _init(start_hp: int = D.PLAYER_MAX_HP, start_potions: int = D.PLAYER_START_POTIONS) -> void:
	entry_hp = clampi(start_hp, 1, D.PLAYER_MAX_HP)
	entry_potions = maxi(0, start_potions)
	set_battle_id(D.DEFAULT_BATTLE_ID)
	reset_fight()

## Switch to a profile before (or instead of) fighting. Returns false for unknown ids.
func set_battle_id(id: String) -> bool:
	var profile := D.profile_for(id)
	if profile.is_empty():
		push_error("BattleLogic: unknown battleId %s" % id)
		return false
	battle_id = id
	enemy_name = str(profile.get("displayName", id))
	enemy_max_hp = int(profile.get("enemyMaxHp", D.ENEMY_MAX_HP))
	enemy_attack = int(profile.get("enemyAttack", D.ENEMY_ATTACK))
	enemy_defense = int(profile.get("enemyDefense", D.ENEMY_DEFENSE))
	enemy_cycle = (profile.get("cycle", []) as Array).duplicate(true)
	charge_log = str(profile.get("chargeLog", D.ENEMY_CHARGE_LOG))
	heavy_log = str(profile.get("heavyLog", D.ENEMY_HEAVY_LOG))
	intro_log = str(profile.get("introLog", ""))
	reset_fight()
	return true

func reset_fight() -> void:
	hp = entry_hp
	qi = D.PLAYER_START_QI
	potions = entry_potions
	enemy_hp = enemy_max_hp
	guarding = false
	enemy_step = 0
	enemy_charging = false
	round_no = 0
	won = false
	lost = false
	log_lines.clear()

## Restore the entry snapshot and restart the same fight ("再战"), no dialogue replay.
func restart_from_snapshot() -> void:
	reset_fight()

## Restore only the player's persistent resources (used when returning to exploration).
func restore_snapshot() -> void:
	hp = entry_hp
	potions = entry_potions
	qi = D.PLAYER_START_QI
	guarding = false
	enemy_charging = false
	won = false
	lost = false

func is_over() -> bool:
	return won or lost

func last_log() -> String:
	return "" if log_lines.is_empty() else log_lines[log_lines.size() - 1]

static func damage_formula(attack: int, multiplier: float, defense: int) -> int:
	return maxi(1, roundi(float(attack) * multiplier - float(defense)))

func player_attack_damage(action: String) -> int:
	match action:
		"attack":
			return damage_formula(D.PLAYER_ATTACK, D.ATTACK_MULT, enemy_defense)
		"skill":
			return damage_formula(D.PLAYER_ATTACK, D.SKILL_MULT, enemy_defense)
	return 0

func _cycle_multiplier(action: String) -> float:
	for step: Variant in enemy_cycle:
		if typeof(step) == TYPE_DICTIONARY and str(step.get("type", "")) == action:
			return float(step.get("mult", 0.0))
	return 0.0

func enemy_action_damage(action: String, multiplier: float = -1.0) -> int:
	if action not in ["attack", "heavy"]:
		return 0
	var mult := multiplier
	if mult < 0.0:
		mult = _cycle_multiplier(action)
		if mult <= 0.0:
			match action:
				"attack": mult = D.ENEMY_ATTACK_MULT
				"heavy": mult = D.ENEMY_HEAVY_MULT
	var raw := damage_formula(enemy_attack, mult, D.PLAYER_DEFENSE)
	if guarding:
		return floori(float(raw) * D.GUARD_MULT)
	return raw

func can_act(action: String) -> bool:
	if won or lost:
		return false
	match action:
		"attack", "guard":
			return true
		"skill":
			return qi >= D.SKILL_QI_COST
		"potion":
			return potions > 0 and hp < D.PLAYER_MAX_HP
	return false

func invalid_reason(action: String) -> String:
	if is_over():
		return "战斗已结束"
	match action:
		"attack", "guard":
			return ""
		"skill":
			return "内力不足" if qi < D.SKILL_QI_COST else ""
		"potion":
			if potions <= 0:
				return "没有回复药"
			if hp >= D.PLAYER_MAX_HP:
				return "气血已满"
			return ""
	return "未知动作"

## All four actions with their enabled state, for the battle UI buttons.
func available_actions() -> Dictionary:
	var result := {}
	for action: String in ACTIONS:
		result[action] = can_act(action)
	return result

## The enemy action that will resolve after the player's next turn.
## "charge" is a telegraphed no-damage turn; the following one is "heavy".
func enemy_next_action() -> String:
	if is_over() or enemy_cycle.is_empty():
		return ""
	var step: Variant = enemy_cycle[enemy_step % enemy_cycle.size()]
	return str(step.get("type", "")) if typeof(step) == TYPE_DICTIONARY else ""

## Log line a given cycle beat will print (per-beat "log", else chargeLog/heavyLog).
func cycle_step_log(index: int) -> String:
	if enemy_cycle.is_empty():
		return ""
	var step: Variant = enemy_cycle[index % enemy_cycle.size()]
	if typeof(step) != TYPE_DICTIONARY:
		return ""
	var own := str(step.get("log", ""))
	if own != "":
		return own
	match str(step.get("type", "")):
		"charge": return charge_log
		"heavy": return heavy_log
	return ""

func enemy_cycle_actions() -> Array[String]:
	var out: Array[String] = []
	for step: Variant in enemy_cycle:
		if typeof(step) == TYPE_DICTIONARY:
			out.append(str(step.get("type", "")))
	return out

static func enemy_action_label(action: String) -> String:
	return str(D.ENEMY_LABELS.get(action, action))

## Resolve one full round. Invalid actions return ok=false and change nothing.
func take_turn(action: String) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "",
		"action": action,
		"player_damage": 0,
		"enemy_dead": false,
		"enemy_action": "",
		"enemy_damage": 0,
		"player_dead": false,
		"guarded": false,
		"charged": false,
		"qi_gain": 0,
		"heal": 0,
		"won": false,
		"lost": false,
	}
	if not can_act(action):
		result["reason"] = invalid_reason(action)
		return result
	result["ok"] = true
	round_no += 1

	match action:
		"attack":
			var dmg := player_attack_damage("attack")
			enemy_hp = maxi(0, enemy_hp - dmg)
			qi = mini(D.PLAYER_MAX_QI, qi + D.ATTACK_QI_GAIN)
			result["player_damage"] = dmg
			result["qi_gain"] = D.ATTACK_QI_GAIN
			log_lines.append("沈砚普攻，造成 %d 点伤害。" % dmg)
		"skill":
			var dmg := player_attack_damage("skill")
			enemy_hp = maxi(0, enemy_hp - dmg)
			qi = maxi(0, qi - D.SKILL_QI_COST)
			result["player_damage"] = dmg
			result["qi_gain"] = -D.SKILL_QI_COST
			log_lines.append("沈砚剑技，造成 %d 点伤害。" % dmg)
		"guard":
			guarding = true
			qi = mini(D.PLAYER_MAX_QI, qi + D.GUARD_QI_GAIN)
			result["guarded"] = true
			result["qi_gain"] = D.GUARD_QI_GAIN
			log_lines.append("沈砚摆出守势。")
		"potion":
			var before := hp
			hp = mini(D.PLAYER_MAX_HP, hp + D.POTION_HEAL)
			potions -= 1
			result["heal"] = hp - before
			log_lines.append("沈砚使用回复药，回复 %d 点气血。" % result["heal"])

	if enemy_hp <= 0:
		won = true
		guarding = false
		result["enemy_dead"] = true
		result["won"] = true
		log_lines.append("%s倒下了。" % enemy_name)
		return result

	var step: Variant = enemy_cycle[enemy_step % enemy_cycle.size()]
	var eaction := str(step.get("type", "")) if typeof(step) == TYPE_DICTIONARY else ""
	var emult := float(step.get("mult", 0.0)) if typeof(step) == TYPE_DICTIONARY else 0.0
	var step_log := str(step.get("log", "")) if typeof(step) == TYPE_DICTIONARY else ""
	enemy_step = (enemy_step + 1) % enemy_cycle.size()
	result["enemy_action"] = eaction
	if eaction == "charge":
		enemy_charging = true
		result["charged"] = true
		log_lines.append(step_log if step_log != "" else charge_log)
	else:
		if eaction == "heavy":
			enemy_charging = false
			# Keep the beat string itself unchanged so cycle_step_log / CH3-BAT-003
			# still match; put the damage on a following line.
			log_lines.append(step_log if step_log != "" else heavy_log)
		var edmg := enemy_action_damage(eaction, emult)
		hp = maxi(0, hp - edmg)
		result["enemy_damage"] = edmg
		if eaction == "heavy":
			log_lines.append("造成 %d 点伤害。" % edmg)
		if eaction == "attack":
			log_lines.append("%s普攻，造成 %d 点伤害。" % [enemy_name, edmg])
		if hp <= 0:
			lost = true
			result["player_dead"] = true
			log_lines.append("沈砚倒下了。")

	guarding = false
	result["won"] = won
	result["lost"] = lost
	return result

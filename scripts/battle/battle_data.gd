extends RefCounted
## Battle profiles keyed by battleId. Player numbers are shared.
## Legacy constants below stay as the "liheng" defaults so chapter-1 callers
## and tests keep working unchanged.

const PLAYER_MAX_HP := 100
const PLAYER_ATTACK := 12
const PLAYER_DEFENSE := 4
const PLAYER_MAX_QI := 30
const PLAYER_START_QI := 20
const PLAYER_START_POTIONS := 2
const POTION_HEAL := 35

const ATTACK_MULT := 1.0
const SKILL_MULT := 1.8
const SKILL_QI_COST := 10
const ATTACK_QI_GAIN := 5
const GUARD_QI_GAIN := 8
const GUARD_MULT := 0.5

const ENEMY_MAX_HP := 100
const ENEMY_ATTACK := 14
const ENEMY_DEFENSE := 2
const ENEMY_ATTACK_MULT := 1.0
const ENEMY_HEAVY_MULT := 2.5

## Fixed, no randomness: 普攻 → 普攻 → 蓄力 → 重击.
const ENEMY_CYCLE: Array[String] = ["attack", "attack", "charge", "heavy"]

## Player-facing action ids used by BattleLogic.take_turn().
const PLAYER_ACTIONS: Array[String] = ["attack", "skill", "guard", "potion"]

const ENEMY_ATTACK_NAME := "普攻"
const ENEMY_CHARGE_NAME := "蓄力"
const ENEMY_HEAVY_NAME := "重击"

## Log/marker copy owned by battle logic so the UI does not invent wording.
const ENEMY_CHARGE_LOG := "厉横握紧刀柄，正在蓄力！"
const ENEMY_HEAVY_LOG := "厉横抡起一刀，势大力沉！"
const ENEMY_LABELS := {
	"attack": ENEMY_ATTACK_NAME,
	"charge": ENEMY_CHARGE_NAME,
	"heavy": ENEMY_HEAVY_NAME,
}

const DEFAULT_BATTLE_ID := "liheng"

## Each cycle entry: {"type": attack|charge|heavy, "mult": float, "log"?: String}.
## Optional per-beat "log" (chapter 3 §2.5) overrides chargeLog/heavyLog for that beat.
const BATTLES := {
	"liheng": {
		"displayName": "厉横",
		"enemyMaxHp": ENEMY_MAX_HP,
		"enemyAttack": ENEMY_ATTACK,
		"enemyDefense": ENEMY_DEFENSE,
		"cycle": [
			{"type": "attack", "mult": 1.0},
			{"type": "attack", "mult": 1.0},
			{"type": "charge", "mult": 0.0},
			{"type": "heavy", "mult": 2.5},
		],
		"chargeLog": ENEMY_CHARGE_LOG,
		"heavyLog": ENEMY_HEAVY_LOG,
		"introLog": "",
	},
	"ch2_thug": {
		"displayName": "药行打手",
		"enemyMaxHp": 60,
		"enemyAttack": 12,
		"enemyDefense": 0,
		"cycle": [
			{"type": "attack", "mult": 1.0},
			{"type": "attack", "mult": 1.0},
			{"type": "charge", "mult": 0.0},
			{"type": "heavy", "mult": 2.2},
		],
		"chargeLog": "药行打手抡起短棍，正在蓄力！",
		"heavyLog": "药行打手抡棍横扫！",
		"introLog": "药行打手拎着短棍逼上来。",
	},
	"ch2_gesancheng": {
		"displayName": "葛三秤",
		"enemyMaxHp": 120,
		"enemyAttack": 13,
		"enemyDefense": 2,
		"cycle": [
			{"type": "attack", "mult": 1.0},
			{"type": "charge", "mult": 0.0},
			{"type": "heavy", "mult": 2.6},
			{"type": "attack", "mult": 1.0},
			{"type": "attack", "mult": 1.0},
			{"type": "charge", "mult": 0.0},
			{"type": "heavy", "mult": 2.6},
		],
		"chargeLog": "葛三秤甩开秤砣，正在蓄力！",
		"heavyLog": "葛三秤抡起秤砣横扫！",
		"introLog": "葛三秤把秤砣在掌心掂了掂。",
	},
	"ch2_liheng_spar": {
		"displayName": "厉横（切磋）",
		"enemyMaxHp": 100,
		"enemyAttack": 14,
		"enemyDefense": 2,
		"cycle": [
			{"type": "attack", "mult": 1.0},
			{"type": "charge", "mult": 0.0},
			{"type": "heavy", "mult": 2.5},
		],
		"chargeLog": ENEMY_CHARGE_LOG,
		"heavyLog": ENEMY_HEAVY_LOG,
		"introLog": "厉横横刀一立：‘这回换个砍法。’",
	},
	# ---- chapter 3 (chapter3.md v1.1 §2.2 / §2.5): double-charge beats.
	"ch3_stair": {
		"displayName": "药行打手",
		"enemyMaxHp": 80,
		"enemyAttack": 12,
		"enemyDefense": 1,
		"cycle": [
			{"type": "attack", "mult": 1.0},
			{"type": "charge", "mult": 0.0, "log": "打手抡起短棍，劲还没攒满！"},
			{"type": "charge", "mult": 0.0, "log": "打手又攒一口劲，棍风更沉！"},
			{"type": "heavy", "mult": 3.0, "log": "打手攒足两回劲，一棍砸下！"},
		],
		"chargeLog": "药行打手抡起短棍，正在蓄力！",
		"heavyLog": "药行打手攒足了劲，一棍砸下！",
		"introLog": "打手把短棍往地上一顿。",
	},
	"ch3_chutie": {
		"displayName": "褚铁",
		"enemyMaxHp": 130,
		"enemyAttack": 13,
		"enemyDefense": 2,
		"cycle": [
			{"type": "attack", "mult": 1.0},
			{"type": "attack", "mult": 1.0},
			{"type": "charge", "mult": 0.0, "log": "褚铁压低刀身，正在蓄力！"},
			{"type": "heavy", "mult": 2.5, "log": "褚铁抡刀劈下！"},
			{"type": "attack", "mult": 1.0},
			{"type": "charge", "mult": 0.0, "log": "褚铁横刀蓄力，刀势未满！"},
			{"type": "charge", "mult": 0.0, "log": "褚铁刀势又沉了一分！"},
			{"type": "heavy", "mult": 3.0, "log": "褚铁攒足两回力，全力劈下！"},
		],
		"chargeLog": "褚铁压低刀身，正在蓄力！",
		"heavyLog": "褚铁抡刀劈下！",
		"introLog": "褚铁横刀立在庵门前。",
	},
	"ch3_herb_thief": {
		"displayName": "药行打手",
		"enemyMaxHp": 100,
		"enemyAttack": 13,
		"enemyDefense": 2,
		"cycle": [
			{"type": "attack", "mult": 1.0},
			{"type": "charge", "mult": 0.0, "log": "打手举起药锄，劲还没攒满！"},
			{"type": "charge", "mult": 0.0, "log": "打手又攒一回劲，锄头高举！"},
			{"type": "heavy", "mult": 3.0, "log": "打手攒足两回劲，一锄刨下！"},
			{"type": "charge", "mult": 0.0, "log": "打手举锄一顿，正在蓄力！"},
			{"type": "heavy", "mult": 2.4, "log": "打手一锄头刨下！"},
		],
		"chargeLog": "药行打手举起药锄，正在蓄力！",
		"heavyLog": "药行打手一锄头刨下！",
		"introLog": "打手拎着药锄，从篱笆后窜出。",
	},
}

static func has_battle(battle_id: String) -> bool:
	return BATTLES.has(battle_id)

static func profile_for(battle_id: String) -> Dictionary:
	var profile: Variant = BATTLES.get(battle_id, {})
	return profile if typeof(profile) == TYPE_DICTIONARY else {}

static func cycle_actions(battle_id: String) -> Array[String]:
	var out: Array[String] = []
	for step: Variant in profile_for(battle_id).get("cycle", []):
		if typeof(step) == TYPE_DICTIONARY:
			out.append(str(step.get("type", "")))
	return out

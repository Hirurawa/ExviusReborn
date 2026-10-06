class_name Combatant
extends RefCounted

## One fighter in a BattleEngine battle, on either side. Battle state is typed and lives
## here; the unit or monster dict it was built from is kept in `source` only as
## StatCalculator input. Build one with CombatantFactory.

enum Side { PARTY, ENEMY }

## The ailments with a resistance, in the order of StatCalculator.STATUSES and of the ids
## STATUS_CURE (opcode 5) packs: 1 poison .. 8 petrify. ZOMBIE, STOP, CHARM and BERSERK
## are ailments too (see StatusBehaviorRegistry).
const AILMENTS: PackedStringArray = [
	"POISON", "BLIND", "SLEEP", "SILENCE", "PARALYSIS", "CONFUSION", "DISEASE", "PETRIFY",
]
## Keys of debuff_resist, in the order of monster_parts.debuffResists.
const DEBUFF_KEYS: PackedStringArray = ["ATK", "DEF", "MAG", "SPR", "STOP", "CHARM", "BERSERK"]
## Values of `sex`, as the unit table's `sex` column has them.
const SEX_UNKNOWN: int = 0
const SEX_MALE: int = 1
const SEX_FEMALE: int = 2
## Values of `cover_mode`.
const COVER_NONE: int = 0
const COVER_AOE: int = 1
const COVER_ST: int = 2

## Unique within a battle and never reused, so events can name a combatant after it
## has died or left with its wave.
var id: int = -1
## A Side value. Typed int: the engine's classes reference each other in a cycle, and
## GDScript fails to match enum-typed members across such a cycle.
var side: int = Side.PARTY
## Party slot (index-stable; empty slots keep their index) or formation index.
var slot: int = -1
var name: String = ""
## Unit instance_id, or the monster's 9-digit id (the id the AI tables key on).
var source_id: String = ""
## Unit id or monster dictionary id: the key for sprites.
var template_id: String = ""
var level: int = 1
var is_boss: bool = false
## A SEX_* value (units only; covers for female or male allies read it).
var sex: int = SEX_UNKNOWN
## Race ids (1 beast .. 12 reaper) for killers.
var races: PackedInt32Array = PackedInt32Array()

var hp: int = 0
var max_hp: int = 0
var mp: int = 0
var max_mp: int = 0
## Limit gauge in hundredths of a crystal, the unit of limitburst_lv.cost.
var lb: int = 0
var max_lb: int = 0
var limit_burst_id: String = ""
var limit_burst_level: int = 1
## The esper in the unit's party slot: its beastId (0 for none) and the beast skill its
## rank evokes ("" for none). The esper gauge is the party's (BattleEngine.esper_orbs).
var esper_id: int = 0
var esper_skill_id: String = ""

## HP, MP, ATK, DEF, MAG, SPR from the StatCalculator profile, before battle statuses.
var base_stats: Dictionary = {}
## The part of each stat that buffs and breaks scale: the base before equipment and
## passives (StatCalculator adds buff percentages to the same pool as passive ones,
## which only multiplies this base). Monsters have no split, so it equals base_stats.
var raw_stats: Dictionary = {}
## Percent resistances keyed FIRE .. DARK (StatCalculator.ELEMENTS).
var element_resist: Dictionary = {}
## Percent resistances keyed POISON .. PETRIFY (StatCalculator.STATUSES).
var status_resist: Dictionary = {}
## Chance percent to resist breaks, stop and charm, keyed by DEBUFF_KEYS.
var debuff_resist: Dictionary = {}
## Innate percent cut of all physical or magic damage taken (monster_parts
## physicsDmgCut / magicDmgCut; 100 is immune). Equipment has the same columns, all 0.
var physical_resist: int = 0
var magic_resist: int = 0

## Passive battle modifiers (killers, LB and skill damage) from the profile. Never null;
## empty for enemies.
var passives: CombatantPassives = CombatantPassives.new()
## Chance percent to inflict each ailment (AILMENTS keys, non-zero only) with physical
## and hybrid damage, from the weapons in hand; the higher chance when two weapons
## inflict the same one (WeaponInflict). Empty for enemies.
var weapon_inflicts: Dictionary = {}
## The elements of every weapon in hand (1-based ids), which physical and hybrid attacks
## carry: both weapons' when dual wielding. Empty for enemies.
var weapon_elements: PackedInt32Array = PackedInt32Array()
## ATK each weapon in hand adds to the ATK stat (its own ATK plus its share of the
## equipment-stat boosts), right hand first. Two entries mean the combatant dual wields
## (DualWield). Empty for enemies.
var hand_atk: PackedInt32Array = PackedInt32Array()
## Weapon variance in whole percent (dagger 110 .. 120), from the right-hand weapon, or
## the left one when the right hand holds none; a dual wielder's swings both use the
## right hand's (wiki). 100 .. 100 unarmed and for enemies.
var weapon_variance_min: int = 100
var weapon_variance_max: int = 100
## Holds a two-handed weapon: its jumps roll at least the wiki's flat variance
## (DamageFormula.weapon_variance). False unarmed and for enemies.
var two_handed: bool = false

## Active statuses; see BattleStatus. Change through add_status / remove_status.
var statuses: Array[BattleStatus] = []
## Per-skill limits by the id of the skill the command names:
## { uses_left: int (-1 unlimited), ready_turn: int }.
var skill_state: Dictionary = {}
## Skills granted for a while (op 100), by SkillGrant.key(), in grant order. Change
## through BattleEngine.grant.
var grants: Dictionary = {}
## The previous action, the stack of stacking abilities and the skills used last turn
## (ops 72, 126, 1007, 99). Never null.
var history: SkillHistory = SkillHistory.new()
## Counters each source has queued this turn (Counters.source key -> count), for the
## sources' per-turn caps; cleared when the enemy phase begins.
var counter_uses: Dictionary = {}

## The basic attack, timed by the combatant's own attackFrames.
var attack_skill: BattleSkill = null
## Enemy decision maker. Party members have none.
var brain: EnemyBrain = null

## Data the session layer keeps with the combatant (rewards, loot, display position).
## The engine never reads it.
var meta: Dictionary = {}
## The unit or monster dict this combatant was built from, and its StatCalculator profile.
var source: Dictionary = {}
var profile: Dictionary = {}

# --- Turn state ---

## Party: has started an action this turn.
var acted: bool = false
var defending: bool = false
## Party: the command execute() runs, set by queue_command. null means basic attack.
var queued_command: BattleCommand = null
## The last command this combatant executed (for the UI's repeat button).
var last_command: BattleCommand = null

# --- Cover, as the coverer (CoverTracker; reset when each phase starts) ---

## The cover this combatant triggered this turn: COVER_NONE, COVER_AOE or COVER_ST.
var cover_mode: int = COVER_NONE
## The ally an ST cover protects (combatant id).
var cover_protects: int = -1
## The attack types the triggered cover takes.
var cover_physical: bool = false
var cover_magic: bool = false
## Percent the triggered cover cuts from every hit the combatant takes, rolled when it
## triggered.
var cover_mitigation: int = 0
## KO'd this turn: no more covering until the next turn, even after a reraise.
var cover_spent: bool = false

# --- Chain tracking, as the target of hits ---

var chain_count: int = 0
## Chain multiplier in percent (130 = 1.3x); see ChainTracker.
var chain_percent: int = 100
var chain_last_frame: int = -1000000
var chain_last_source: int = -1
var chain_last_elements: PackedInt32Array = PackedInt32Array()
## How the last hit linked to the one before: a spark chain (same frame), and the
## number of elements they shared (an elemental chain when above 0).
var chain_spark: bool = false
var chain_shared_elements: int = 0


func is_alive() -> bool:
	return hp > 0


func is_party() -> bool:
	return side == Side.PARTY


func is_enemy() -> bool:
	return side == Side.ENEMY


func is_opponent_of(other: Combatant) -> bool:
	return other != null and other.side != side


## Holds two weapons: physical and hybrid abilities swing twice (DualWield).
func is_dual_wielding() -> bool:
	return hand_atk.size() >= 2


## Alive, on the field and not disabled (asleep, paralyzed, stopped, charmed or
## petrified). A berserk or confused combatant can act, though an ailment picks what it
## does. A unit in the air only lands (BattleEngine).
func can_act() -> bool:
	return is_alive() and not is_away() and control() != StatusBehavior.CONTROL_DISABLED


## Alive, on the field and free to take commands: not disabled and not berserk. A
## confused party member takes commands, which become attacks on random targets.
func can_take_commands() -> bool:
	return is_alive() and not is_away() and control() < StatusBehavior.CONTROL_BERSERK


## Has left the field (a jump; BattleStatus.AWAY): nothing targets it and it cannot act.
func is_away() -> bool:
	return away_status() != null


## The status that keeps the combatant off the field, or null.
func away_status() -> BattleStatus:
	for status in statuses:
		if status.behavior().removes_from_field():
			return status
	return null


## Alive and on the field: what skills and enemies can pick.
func is_targetable() -> bool:
	return is_alive() and not is_away()


## The most restrictive StatusBehavior.CONTROL_* value among the statuses.
func control() -> int:
	var status: BattleStatus = controlling_status()
	return status.behavior().control() if status != null else StatusBehavior.CONTROL_NORMAL


## The status behind control(), or null when the combatant is in control of itself.
func controlling_status() -> BattleStatus:
	var found: BattleStatus = null
	var highest: int = StatusBehavior.CONTROL_NORMAL
	for status in statuses:
		var level: int = status.behavior().control()
		if level > highest:
			highest = level
			found = status
	return found


## Whether a status keeps the combatant from using `skill` (silence).
func skill_blocked(skill: BattleSkill) -> bool:
	for status in statuses:
		if status.behavior().blocks_skill(skill):
			return true
	return false


## LB fill rate in percent: statuses plus passives (crystals and LB per turn use it).
func lb_fill_rate() -> int:
	return status_value(BattleStatus.LB_FILL_RATE) + passives.lb_fill_rate_pct


## The chance in percent (0 to 100) that an enemy's random single-target pick goes to
## this unit before the weighted roll: a provoke status (opcode 61) plus passive aggro.
## 0 without a provoke status, since passive aggro alone only weighs the roll (the
## user's rule, 2026-10-06).
func provoke_chance() -> int:
	var provoke: BattleStatus = find_status(BattleStatus.PROVOKE)
	if provoke == null:
		return 0
	return clampi(provoke.value + passives.aggro_pct, 0, 100)


## Whether dodge statuses and evasion passives work: paralysis, stop and charm stop them.
func can_evade() -> bool:
	for status in statuses:
		if status.behavior().prevents_evasion():
			return false
	return true


## Alive and not out of the fight for the wipe check (petrified).
func is_standing() -> bool:
	if not is_alive():
		return false
	for status in statuses:
		if status.behavior().counts_as_down():
			return false
	return true


## The status that makes HP recovery hurt and revival KO (zombie), or null.
func recovery_inverter() -> BattleStatus:
	for status in statuses:
		if status.behavior().inverts_recovery():
			return status
	return null


# --- Stats as statuses modify them ---

## A stat as the damage formula sees it: the profile value plus buffs, breaks and
## ailments (disease, berserk), each a percentage of raw_stats.
func stat(stat_name: String) -> int:
	var total: int = int(base_stats.get(stat_name, 0))
	var pct: int = status_value(BattleStatus.STAT, stat_name)
	for status in statuses:
		pct += status.behavior().stat_percent(status, stat_name)
	if pct == 0:
		return total
	var raw: int = int(raw_stats.get(stat_name, total))
	return maxi(0, total + roundi(float(raw) * float(pct) / 100.0))


## Resistance percent including resist buffs and imperils. Can exceed 100; the damage
## formula caps what it uses.
func element_resistance(element_name: String) -> int:
	return int(element_resist.get(element_name, 0)) + status_value(BattleStatus.ELEMENT_RESIST, element_name)


## Resistance percent including resist buffs and lowered resistances; 0 while a status
## has blown it away. Can exceed 100; the engine caps what it rolls against.
func ailment_resistance(ailment: String) -> int:
	if find_status(BattleStatus.NO_AILMENT_RESIST, ailment) != null:
		return 0
	return int(status_resist.get(ailment, 0)) + status_value(BattleStatus.AILMENT_RESIST, ailment)


func debuff_resistance(debuff: String) -> int:
	return int(debuff_resist.get(debuff, 0)) + status_value(BattleStatus.DEBUFF_RESIST, debuff)


## The innate damage cut for `side` ("physical" or "magic"); 0 for anything else.
func damage_resistance(side: String) -> int:
	match side:
		"physical":
			return physical_resist
		"magic":
			return magic_resist
	return 0


# --- Statuses ---

## Sum of the values of every status of `kind` and `key`: a stat's buff and break add up.
func status_value(kind: StringName, key: String = "") -> int:
	var total: int = 0
	for status in statuses:
		if status.kind == kind and status.key == key:
			total += status.value
	return total


func statuses_of(kind: StringName) -> Array[BattleStatus]:
	var out: Array[BattleStatus] = []
	for status in statuses:
		if status.kind == kind:
			out.append(status)
	return out


## The first status of `kind` and `key`, or null.
func find_status(kind: StringName, key: String = "") -> BattleStatus:
	for status in statuses:
		if status.kind == kind and status.key == key:
			return status
	return null


func has_ailment(ailment: String) -> bool:
	return find_status(BattleStatus.AILMENT, ailment) != null


## Adds `status`, replacing the one with the same stack key. With `keep_stronger`, a
## weaker status does not replace a stronger one; returns false when it was refused.
func add_status(status: BattleStatus, keep_stronger: bool = false) -> bool:
	var stack: String = status.stack_key()
	for i in range(statuses.size()):
		if statuses[i].stack_key() != stack:
			continue
		if keep_stronger and absi(statuses[i].value) > absi(status.value):
			return false
		statuses[i] = status
		return true
	statuses.append(status)
	return true


func remove_status(status: BattleStatus) -> void:
	statuses.erase(status)


# --- Pools ---

## Removes up to `amount` HP and returns how much was actually removed.
func take_damage(amount: int) -> int:
	var applied: int = clampi(amount, 0, hp)
	hp -= applied
	return applied


## Adds up to `amount` HP (not past max) and returns how much was actually added.
func restore_hp(amount: int) -> int:
	if not is_alive():
		return 0
	var applied: int = clampi(amount, 0, max_hp - hp)
	hp += applied
	return applied


## Adds up to `amount` MP (not past max; a negative amount drains) and returns the change.
func restore_mp(amount: int) -> int:
	var before: int = mp
	mp = clampi(mp + amount, 0, max_mp)
	return mp - before


## Adds to the limit gauge, clamped to its maximum. Returns the change.
func add_lb(amount: int) -> int:
	var before: int = lb
	lb = clampi(lb + amount, 0, max_lb)
	return lb - before


func hp_percent() -> float:
	if max_hp <= 0:
		return 0.0
	return float(hp) / float(max_hp) * 100.0


## Ends the cover this combatant triggered; the KO flag stays (CoverTracker.reset clears it).
func clear_cover() -> void:
	cover_mode = COVER_NONE
	cover_protects = -1
	cover_physical = false
	cover_magic = false
	cover_mitigation = 0


func reset_chain() -> void:
	chain_count = 0
	chain_percent = 100
	chain_last_frame = -1000000
	chain_last_source = -1
	chain_last_elements = PackedInt32Array()
	chain_spark = false
	chain_shared_elements = 0


func describe() -> String:
	return "%s#%d(%s %d/%d)" % [name, id, "P" if is_party() else "E", hp, max_hp]

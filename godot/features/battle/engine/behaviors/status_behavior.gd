class_name StatusBehavior
extends RefCounted

## What a status does while it lasts. Effect handlers put statuses on combatants; a
## behaviour answers the engine's questions about one kind of status at its hook points
## (can the bearer act, does its attack miss, what happens at the end of the turn, ...).
## StatusBehaviorRegistry maps ailment keys to behaviours; every other status gets this
## base class, whose answers change nothing. Behaviours are stateless and shared, so
## anything per status lives on the BattleStatus.
##
## The ailments follow the wiki, split as it does:
##   status ailments  poison, blind, sleep, silence, paralysis, confusion, disease,
##                    petrify, zombie: permanent on the party (sleep: 3 turns); enemies
##                    shake them off with a roll at the start of their turns
##   lasting effects  stop, charm, berserk: the turns their skill gives, on both sides

## How much say the bearer has over its actions. Combatant.control() takes the highest
## value among its statuses.
const CONTROL_NORMAL: int = 0
## Confusion: acts when told to, but attacks a random target instead.
const CONTROL_CONFUSED: int = 1
## Berserk: attacks a random opponent on its own every turn and takes no commands.
const CONTROL_BERSERK: int = 2
## Sleep, paralysis, stop, charm, petrify: does nothing.
const CONTROL_DISABLED: int = 3


## The ailment keys this behaviour serves (empty for the base class).
func keys() -> PackedStringArray:
	return PackedStringArray()


# --- Queries (Combatant asks these; no engine needed) ---

## A CONTROL_* value.
func control() -> int:
	return CONTROL_NORMAL


## Whether the bearer is kept from using `skill` (silence).
func blocks_skill(_skill: BattleSkill) -> bool:
	return false


## Whether the bearer's dodge statuses stop working.
func prevents_evasion() -> bool:
	return false


## Percent of the raw base added to `stat_name` (negative lowers it).
func stat_percent(_status: BattleStatus, _stat_name: String) -> int:
	return 0


## Whether the bearer counts as out of the fight when the engine checks for a wipe,
## though alive (petrify).
func counts_as_down() -> bool:
	return false


## Whether a physical or hybrid damage hit ends the status (sleep, confusion).
func ends_on_physical_damage() -> bool:
	return false


## Whether the bearer has left the field (a jump): nothing targets it and it cannot act
## (Combatant.is_away).
func removes_from_field() -> bool:
	return false


## Whether HP recovery hurts the bearer and revival KOs it (zombie).
func inverts_recovery() -> bool:
	return false


## Rolled once per target when the bearer casts a damage effect of `attack_type` (a
## BattleSkill.ATTACK_* value): the miss reason when every hit on that target misses,
## &"" otherwise (blind).
func cast_miss(_engine: BattleEngine, _attack_type: int) -> StringName:
	return &""


# --- Durations ---

## Turns the status lasts on `target`, given the turns its effect says; -1 lasts until
## removed.
func turns_on(_engine: BattleEngine, _target: Combatant, data_turns: int) -> int:
	return data_turns


## Whether an enemy can shake the status off at the start of its turn
## (BattleRules.enemy_ailment_recovery_pct).
func recovers_by_roll() -> bool:
	return false


## Whether the status stays on a party member when a wave is cleared. Buffs and
## debuffs carry over with their turns left (the user's rule, 2026-09-30); the wiki
## lists sleep, paralysis, confusion and zombie as ending with the battle.
func persists_after_battle() -> bool:
	return true


# --- Hooks (the engine calls these) ---

## Before the status is added to `target`: fills in values that come from the rules.
func prepare(_engine: BattleEngine, _target: Combatant, _status: BattleStatus) -> void:
	pass


## Right after the status was added. `hit` is null for a debug edit.
func on_added(_engine: BattleEngine, _target: Combatant, _status: BattleStatus, _hit: ScheduledHit) -> void:
	pass


## At the end of each turn, after regens and before statuses count down.
func on_turn_end(_engine: BattleEngine, _bearer: Combatant, _status: BattleStatus) -> void:
	pass


## The combatants a bearer under CONFUSED or BERSERK control picks its target from.
func forced_targets(_engine: BattleEngine, _bearer: Combatant) -> Array[Combatant]:
	return []

class_name RewardLedger
extends RefCounted

## What a battle has earned, kept from its events: each defeated enemy's unit EXP and
## gil (Combatant.meta exp and gil, from its monster parts row) and a roll for one drop
## from its loot (a DROP_CHANCE chance of one random item of meta.loot.drops), the kills
## (for PlayerProfile.record_monster_kill, which BattleDirector calls, so this stays
## testable) and the items used. Ported from the old BattleManager's _roll_enemy_drops,
## _accumulate_enemy_rewards and used_items count.
##
## The rolls use their own RNG seeded from the battle seed, so a seed replays the drops
## too. BattleDirector hands the totals to MissionService on victory only, so a defeat
## forfeits them, as before.

## An enemy died: `template_id` is its monster dictionary id (what the old engine
## recorded).
signal monster_killed(template_id: String)
## A defeated enemy dropped an item (the screen shows a drop icon on it).
signal item_dropped(enemy_id: int, item_id: String)

## The old engine's chance that a defeated enemy drops anything.
const DROP_CHANCE: float = 0.5

var unit_exp: int = 0
var gil: int = 0
## Item ids dropped, in order (one entry per drop).
var drops: Array[String] = []
## Item id -> how many were used (ITEM_USED events).
var used_items: Dictionary = {}

var _rng := RandomNumberGenerator.new()
## Enemy ids already rewarded: an enemy that comes back and dies again pays once.
var _rewarded: Dictionary = {}


func _init(battle_seed: int = 0) -> void:
	_rng.seed = hash("drops:%d" % battle_seed)


## Takes one batch of `engine`'s events (BattleSession.events_emitted).
func record(engine: BattleEngine, events: Array) -> void:
	for event in events:
		match event["type"]:
			BattleEventLog.COMBATANT_DEFEATED:
				var foe: Combatant = engine.combatant(int(event.get("target", -1)))
				if foe != null and foe.is_enemy():
					_reward(foe)
			BattleEventLog.ITEM_USED:
				var item_id: String = str(event.get("item_id", ""))
				if item_id != "":
					used_items[item_id] = int(used_items.get(item_id, 0)) + 1


func _reward(foe: Combatant) -> void:
	if _rewarded.has(foe.id):
		return
	_rewarded[foe.id] = true
	_roll_drop(foe)
	unit_exp += maxi(0, int(foe.meta.get("exp", 0)))
	gil += maxi(0, int(foe.meta.get("gil", 0)))
	monster_killed.emit(foe.template_id)


func _roll_drop(foe: Combatant) -> void:
	var loot: Variant = foe.meta.get("loot", {})
	var pool: Variant = (loot as Dictionary).get("drops", []) if loot is Dictionary else []
	if not pool is Array or (pool as Array).is_empty():
		return
	if _rng.randf() > DROP_CHANCE:
		return
	var item_id: String = str(pool[_rng.randi_range(0, pool.size() - 1)])
	drops.append(item_id)
	item_dropped.emit(foe.id, item_id)

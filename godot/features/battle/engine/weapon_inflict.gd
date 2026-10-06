class_name WeaponInflict
extends RefCounted

## Ailments a party member's weapons inflict with damage (equip_item.ailmentInflict, as
## Combatant.weapon_inflicts). The user's rules (2026-10-02):
##   - Physical and hybrid hits carry them, whatever the skill: basic attacks (forced ones
##     and op 100 replacements included), abilities and limit bursts. Magic does not.
##     "Physical" is the hit's attack type, the same test that wakes a sleeper.
##   - Each target rolls each ailment once per swing, against its resistance like a
##     skill's inflict, when the swing's last such hit on it is done and at least one
##     of them landed. So the swing's own later hits cannot wake a sleep or clear a
##     confusion it put on, and a target that dodged or was missed every time is spared.
##   - With two weapons, the higher chance per ailment (CombatantFactory), and both swings
##     roll it (wiki: "Status effect from one weapon will also affect both hands"), each
##     after its own last hit; the left swing's hits can wake a sleep the right one put on.
## Whoever the hits went to rolls: a coverer takes the inflicts of an attack it covers.
## Static, like CoverTracker; the counts live on each action (weapon_inflict_targets).


## Whether `actor`'s hits of `attack_type` carry its weapon inflicts.
static func carries(actor: Combatant, attack_type: int) -> bool:
	return actor != null and not actor.weapon_inflicts.is_empty() and BattleSkill.is_weapon_attack(attack_type)


## DamageHandler calls it for each hit it schedules, once the hit's attack type is set.
static func track(actor: Combatant, hit: ScheduledHit) -> void:
	if not carries(actor, hit.attack_type):
		return
	hit.weapon_inflicts = true
	var key: Vector2i = _key(hit)
	var entry: Dictionary = hit.action.weapon_inflict_targets.get(key, {"pending": 0, "landed": false})
	entry["pending"] = int(entry["pending"]) + 1
	hit.action.weapon_inflict_targets[key] = entry


## DamageHandler calls it after each hit resolves. Rolls when it was the swing's last
## tracked hit on its target. A hit that KO'd the target inflicts nothing, even when an
## auto-revive brought it back.
static func after_hit(engine: BattleEngine, hit: ScheduledHit) -> void:
	if not hit.weapon_inflicts:
		return
	var key: Vector2i = _key(hit)
	var entry: Dictionary = hit.action.weapon_inflict_targets.get(key, {})
	if entry.is_empty():
		return
	entry["pending"] = int(entry["pending"]) - 1
	if hit.landed and not hit.killed:
		entry["landed"] = true
	if int(entry["pending"]) > 0:
		return
	hit.action.weapon_inflict_targets.erase(key)
	var actor: Combatant = engine.combatant(hit.actor_id)
	var target: Combatant = engine.combatant(hit.target_id)
	if not bool(entry["landed"]) or hit.killed or actor == null or target == null:
		return
	for ailment in Combatant.AILMENTS:
		var chance: int = int(actor.weapon_inflicts.get(ailment, 0))
		# An ailment can KO the target (petrify on an enemy); the rest do not land.
		if chance <= 0 or not target.is_alive():
			continue
		# The status ailments' behaviours set their own durations.
		engine.apply_status(hit, target, BattleStatus.make(BattleStatus.AILMENT, ailment, 0, -1), chance)


## A hit's entry in weapon_inflict_targets: its target and its swing.
static func _key(hit: ScheduledHit) -> Vector2i:
	return Vector2i(hit.target_id, hit.swing)

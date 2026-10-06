class_name BattleEventsBridge
extends RefCounted

## Turns engine events into the BattleEvents autoload's signals, with the payload shapes
## the old BattleManager emitted, which ChallengeFactory's trackers and the colosseum
## read:
##   HIT_LANDED on an enemy           enemy_damaged(template_id, hit)
##   COMBATANT_DEFEATED, enemy        enemy_defeated(template_id, hit): the last hit it took
##   COMBATANT_DEFEATED, party        ally_defeated() (a petrified member is not defeated)
##   ITEM_USED                        item_used(item_id)
##   ACTION_STARTED from a party      magic_used(spell) / ability_used(spell) for a skill,
##     command, not forced            limitburst_used(limit_burst_id), esper_evoked(esper_id)
##   victory (mission_completed())    mission_completed(party, total_turns)
## `hit` is { element: [1-based element ids], amount }; `spell` is { source_type
## ("magic" or "ability"), resolved_action_id, resolved_action_data (the skill record) }.
## The old engine never emitted limitburst_used or esper_evoked, so the LB and esper
## challenges start to count here. ChallengeFactory's own bugs (KNOWN-BUGS #2, #9) are
## left as they are, so their fixes apply unchanged.

## Enemy id -> the payload of the last hit it took, for enemy_defeated.
var _last_hits: Dictionary = {}


## Relays one batch of `engine`'s events (BattleSession.events_emitted).
func relay(engine: BattleEngine, events: Array) -> void:
	for event in events:
		match event["type"]:
			BattleEventLog.HIT_LANDED:
				_on_hit(engine, event)
			BattleEventLog.COMBATANT_DEFEATED:
				_on_defeated(engine, event)
			BattleEventLog.ITEM_USED:
				BattleEvents.item_used.emit(str(event.get("item_id", "")))
			BattleEventLog.ACTION_STARTED:
				_on_action(engine, event)


## Emits mission_completed for a won battle: every party slot's owned-unit dict
## (Combatant.source, {} for an empty slot) and the turns across every wave (the old
## engine's mission-wide turn_count, which "Clear within N turns" reads).
func mission_completed(engine: BattleEngine) -> void:
	BattleEvents.mission_completed.emit(party_sources(engine), engine.total_turns)


## The owned-unit dict of each party slot ({} for an empty one), at least `slot_count`
## entries: the engine keeps no trailing empty slots, the result screen wants one entry
## per slot.
static func party_sources(engine: BattleEngine, slot_count: int = 0) -> Array:
	var out: Array = []
	for member in engine.party:
		out.append(member.source if member != null else {})
	while out.size() < slot_count:
		out.append({})
	return out


func _on_hit(engine: BattleEngine, event: Dictionary) -> void:
	var target: Combatant = engine.combatant(int(event.get("target", -1)))
	if target == null or not target.is_enemy():
		return
	var hit: Dictionary = {
		"element": Array(event.get("elements", PackedInt32Array())),
		"amount": int(event.get("amount", 0)),
	}
	_last_hits[target.id] = hit
	BattleEvents.enemy_damaged.emit(target.template_id, hit)


func _on_defeated(engine: BattleEngine, event: Dictionary) -> void:
	var target: Combatant = engine.combatant(int(event.get("target", -1)))
	if target == null:
		return
	if target.is_party():
		BattleEvents.ally_defeated.emit()
		return
	var hit: Dictionary = _last_hits.get(target.id, {"element": [], "amount": 0})
	BattleEvents.enemy_defeated.emit(target.template_id, hit)


func _on_action(engine: BattleEngine, event: Dictionary) -> void:
	if int(event.get("origin", -1)) != BattleAction.Origin.COMMAND or str(event.get("forced_by", "")) != "":
		return
	var actor: Combatant = engine.combatant(int(event.get("actor", -1)))
	if actor == null or not actor.is_party():
		return
	var skill_kind: StringName = StringName(event.get("skill_kind", &""))
	var skill_id: String = str(event.get("skill_id", ""))
	match int(event.get("kind", -1)):
		BattleCommand.Kind.SKILL:
			var skill: BattleSkill = engine.catalog.get_skill(skill_kind, skill_id)
			var spell: Dictionary = {
				"source_type": str(skill_kind),
				"resolved_action_id": skill_id,
				"resolved_action_data": skill.record if skill != null else {},
			}
			if skill_kind == BattleSkill.KIND_MAGIC:
				BattleEvents.magic_used.emit(spell)
			elif skill_kind == BattleSkill.KIND_ABILITY:
				BattleEvents.ability_used.emit(spell)
		BattleCommand.Kind.LIMIT_BURST:
			BattleEvents.limitburst_used.emit(skill_id)
		BattleCommand.Kind.EVOKE:
			BattleEvents.esper_evoked.emit(int(event.get("esper_id", 0)))

class_name Counters
extends RefCounted

## Counters: a combatant answering an attack it took with an action of its own. The
## wiki's rules (pasted by the user, 2026-10-06) and the readings of REACTIONS-PLAN.md.
## Static, like CoverTracker; the state lives on the actions (BattleAction.sustained),
## the combatants (Combatant.counter_uses) and the engine's reaction queue.
##
## Sources, each answering physical or magic attacks:
##   passive 12 (physical) and 41 (magic): the normal attack, at the passive's modifier;
##   passive 49 (physical) and 50 (magic): the skill the passive names, which can be a
##     buff for the party as well as an attack;
##   COUNTER statuses (CombatantPassives has the passives, StatusHandler builds the
##     statuses): "self" (opcode 119) for physical attacks on the bearer, "ally" (123)
##     for physical attacks on its other allies, with the normal attack.
## Passive 20 raises every source's chance relatively (100 doubles it).
## Only party members counter for now: monster passives are not read, and the one monster
## skill with a counter status (Spiked Turrets 901166) waits with them (REACTIONS-PLAN.md
## section 7).
##
## 1. An attack is an opponent's action that deals physical, magic or hybrid damage (its
##    hits' attack type; hybrid counts as both). A counter or another reaction is never
##    one: counters are not countered. A jump landing on its own is (the wiki: a unit
##    that has just landed "cannot evade counters"). Effects without damage are not
##    attacks.
## 2. A combatant sustains it when one of its damage hits comes while the combatant is
##    alive, whether the hit lands or misses (dodged, evaded, blinded, the skill's own
##    miss chance): the wiki says evading still counts. A covered attack lands on the
##    coverer, so the coverer sustained it. One the attack KO'd does not counter it, even
##    when a reraise brings it back before the attack ends.
## 3. When the attack ends, each living party member that can act rolls once (wiki: one
##    counter per attack sustained), from its sources that answer what
##    it sustained and, when another ally sustained a physical attack, its "ally"
##    statuses. One roll against bands as wide as each source's chance, in order
##    (passives in passive order, then statuses oldest first): the band the roll falls in
##    answers, so chances add up (wiki: they raise the chance of a counter, not the
##    number of counters). Over 100 in total, the bands are scaled to fit.
## 4. A source counters at most its `max` times a turn (0: no cap), counted when a
##    counter is queued; the counts reset when the enemy phase begins.
## 5. A success queues a Reaction aimed at the attacker (COUNTER_QUEUED). The engine runs
##    it in the next turn's opening phase, so the 1-turn effects counters cast reach the
##    player phase; a counter whose unit is KO'd before then is dropped, even if the unit
##    comes back.

## Bits of BattleAction.sustained.
const PHYSICAL: int = 1
const MAGIC: int = 2
## The attack KO'd the combatant (rule 2).
const KNOCKED_OUT: int = 4

const KEY_SELF: String = "self"
const KEY_ALLY: String = "ally"


## The sustained bits of a hit with `attack_type`: physical, magic, both for hybrid, 0
## for typeless damage.
static func kinds_of(attack_type: int) -> int:
	match attack_type:
		BattleSkill.ATTACK_PHYSICAL:
			return PHYSICAL
		BattleSkill.ATTACK_MAGIC:
			return MAGIC
		BattleSkill.ATTACK_HYBRID:
			return PHYSICAL | MAGIC
	return 0


## Rule 2: notes on the hit's action that its target sustained the attack. BattleEngine
## calls it for every damage hit that comes while its target is alive, before it lands
## or misses.
static func note_sustained(engine: BattleEngine, hit: ScheduledHit) -> void:
	var reaction: Reaction = hit.action.reaction
	if hit.action.origin == BattleAction.Origin.REACTION and (reaction == null or reaction.kind != Reaction.LANDING):
		return
	var actor: Combatant = engine.combatant(hit.actor_id)
	var target: Combatant = engine.combatant(hit.target_id)
	if actor == null or target == null or not target.is_party() or not actor.is_opponent_of(target):
		return
	var kinds: int = kinds_of(hit.attack_type)
	if kinds != 0:
		hit.action.sustained[target.id] = int(hit.action.sustained.get(target.id, 0)) | kinds


## Rule 2: the attack KO'd the target of `hit`, which therefore will not counter it.
## BattleEngine calls it when a damage hit KOs its target, before any reraise.
static func note_knocked_out(hit: ScheduledHit) -> void:
	if hit.action.sustained.has(hit.target_id):
		hit.action.sustained[hit.target_id] = int(hit.action.sustained[hit.target_id]) | KNOCKED_OUT


## Rule 3: the rolls once `action`'s attack is over. BattleEngine calls it when any
## action ends; one that sustained nothing does nothing.
static func on_attack_ended(engine: BattleEngine, action: BattleAction) -> void:
	if action.sustained.is_empty():
		return
	for fighter in engine.party_members():
		if not fighter.can_act():
			continue
		var own: int = int(action.sustained.get(fighter.id, 0))
		if (own & KNOCKED_OUT) != 0:
			continue
		var ally_physical: bool = false
		for target_id in action.sustained:
			if int(target_id) != fighter.id and (int(action.sustained[target_id]) & PHYSICAL) != 0:
				ally_physical = true
		var options: Array[Dictionary] = sources(fighter, own, ally_physical)
		if not options.is_empty():
			_roll(engine, action, fighter, options)


## The sources `fighter` can counter with, having sustained `own` (bits; 0 for none),
## while another ally sustained a physical attack when `ally_physical`: [{ key, chance
## (with op 20), max, skill_kind, skill_id, modifier, source_skill_id }]. Sources whose
## cap is used up this turn are left out.
static func sources(fighter: Combatant, own: int, ally_physical: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var boost: int = fighter.passives.counter_chance_pct
	for i in range(fighter.passives.counters.size()):
		var counter: Dictionary = fighter.passives.counters[i]
		var bit: int = PHYSICAL if str(counter["trigger"]) == "physical" else MAGIC
		if (own & bit) == 0:
			continue
		_add_source(out, fighter, "passive:%d" % i, int(counter["chance"]), boost, int(counter["max"]), counter["skill_kind"],
			str(counter["skill_id"]), int(counter["modifier"]), str(counter["source_skill_id"]))
	var statuses: Array[BattleStatus] = fighter.statuses_of(BattleStatus.COUNTER)
	statuses.sort_custom(func(a: BattleStatus, b: BattleStatus) -> bool: return a.added_order < b.added_order)
	for status in statuses:
		var answers: bool = (own & PHYSICAL) != 0 if status.key == KEY_SELF else (status.key == KEY_ALLY and ally_physical)
		if not answers:
			continue
		_add_source(out, fighter, "status:%s:%d" % [status.key, status.added_order], status.value, boost,
			int(status.params.get("max", 0)), BattleSkill.KIND_ATTACK, "", int(status.params.get("modifier", 0)), status.skill_id)
	return out


static func _add_source(out: Array[Dictionary], fighter: Combatant, key: String, chance: int, boost: int, cap: int,
		skill_kind: StringName, skill_id: String, modifier: int, source_skill_id: String) -> void:
	var boosted: int = floori(float(chance) * float(100 + boost) / 100.0)
	if boosted <= 0:
		return
	if cap > 0 and int(fighter.counter_uses.get(key, 0)) >= cap:
		return
	out.append({
		"key": key, "chance": boosted, "max": cap, "skill_kind": skill_kind, "skill_id": skill_id,
		"modifier": modifier, "source_skill_id": source_skill_id,
	})


## Rules 3 to 5 for one combatant: one roll picks the source, or none.
static func _roll(engine: BattleEngine, action: BattleAction, fighter: Combatant, options: Array[Dictionary]) -> void:
	var total: int = 0
	for option in options:
		total += int(option["chance"])
	var scale: float = 100.0 / float(total) if total > 100 else 1.0
	var roll: int = engine.rng.randi_range(0, 99)
	var edge: float = 0.0
	for option in options:
		edge += float(option["chance"]) * scale
		if float(roll) < edge:
			_queue(engine, action, fighter, option, mini(total, 100))
			return


static func _queue(engine: BattleEngine, action: BattleAction, fighter: Combatant, source: Dictionary, chance: int) -> void:
	var key: String = str(source["key"])
	fighter.counter_uses[key] = int(fighter.counter_uses.get(key, 0)) + 1
	var queued: Reaction = Reaction.counter(fighter, source, action)
	engine.queue_reaction(queued)
	engine.events.append(BattleEventLog.COUNTER_QUEUED, engine.frame, {
		"actor": fighter.id,
		"attacker": action.actor_id,
		"action": action.id,
		"skill_kind": queued.skill_kind,
		"skill_id": queued.skill_id,
		"modifier": queued.modifier,
		"source_skill_id": queued.source_skill_id,
		"chance": chance,
	})


## A new turn's counting: every source may counter its `max` times again.
static func reset_caps(engine: BattleEngine) -> void:
	var everyone: Array[Combatant] = engine.party_members()
	everyone.append_array(engine.enemies)
	for fighter in everyone:
		fighter.counter_uses.clear()

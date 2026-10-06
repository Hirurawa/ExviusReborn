class_name ChainTracker
extends RefCounted

## Chain bookkeeping. A chain belongs to the target: every damaging hit on it either
## continues the chain (lands within the window, from a different source than the
## previous hit) or starts a new one. Only damage hits are registered; heals and
## buffs never touch a chain. Sources are compared by combatant id, so a party slot
## and an enemy slot with the same index are different sources.
##
## The multiplier is a whole percentage. It starts at 100 and each continuing hit adds
## a step (the wiki's chaining page):
##   normal    rules.chain_step_pct, when the hit lands 1 to chain_window_frames frames
##             after the previous one
##   spark     rules.chain_spark_step_pct instead, when it lands on the same frame
##   elemental rules.chain_element_step_pct per element shared with the previous hit,
##             added to either
## The target's chain grows up to rules.chain_cap_ceiling_pct whoever hits. Each hit
## takes it up to its own attacker's cap (attacker_cap: rules.chain_cap_pct plus the
## attacker's chain cap passives), plus the attacker's chain modifier boost on a hit
## that continues the chain (the unit's own hits only, the user's rule, 2026-09-30).
## The count keeps rising past the cap, for display. The target also keeps how the last
## hit linked (chain_spark, chain_shared_elements), for events and the UI's labels.


## Registers a damaging hit and returns the chain multiplier it gets, in percent. Hits
## that do not build chains (enemy hits unless rules.enemy_hits_chain) get 100 and
## leave the target's chain alone.
static func register_hit(target: Combatant, source: Combatant, frame: int, elements: PackedInt32Array, rules: BattleRules) -> int:
	if not builds_chain(source, rules):
		return 100

	var chained: bool = continues_chain(target, source, frame, rules)
	if chained:
		target.chain_count += 1
		target.chain_spark = frame == target.chain_last_frame
		target.chain_shared_elements = shared_elements(elements, target.chain_last_elements)
		var step: int = rules.chain_spark_step_pct if target.chain_spark else rules.chain_step_pct
		step += rules.chain_element_step_pct * target.chain_shared_elements
		target.chain_percent = mini(ceiling(rules), target.chain_percent + step)
	else:
		target.chain_count = 0
		target.chain_percent = 100
		target.chain_spark = false
		target.chain_shared_elements = 0

	target.chain_last_frame = frame
	target.chain_last_source = source.id
	target.chain_last_elements = elements
	var percent: int = target.chain_percent
	if chained:
		percent += source.passives.chain_boost_pct
	return mini(percent, attacker_cap(source, rules))


## The most one of `source`'s hits takes from a chain, in percent: rules.chain_cap_pct
## raised by its chain cap passives, at most the ceiling.
static func attacker_cap(source: Combatant, rules: BattleRules) -> int:
	return mini(ceiling(rules), rules.chain_cap_pct + source.passives.chain_cap_raise)


## How far a chain can grow: rules.chain_cap_ceiling_pct, or chain_cap_pct if a test
## set that higher.
static func ceiling(rules: BattleRules) -> int:
	return maxi(rules.chain_cap_ceiling_pct, rules.chain_cap_pct)


static func builds_chain(source: Combatant, rules: BattleRules) -> bool:
	return source.is_party() or rules.enemy_hits_chain


static func continues_chain(target: Combatant, source: Combatant, frame: int, rules: BattleRules) -> bool:
	if frame - target.chain_last_frame > rules.chain_window_frames:
		return false
	if rules.chain_same_source_breaks and source.id == target.chain_last_source:
		return false
	return true


static func shared_elements(a: PackedInt32Array, b: PackedInt32Array) -> int:
	var shared: int = 0
	for element in a:
		if b.has(element):
			shared += 1
	return shared

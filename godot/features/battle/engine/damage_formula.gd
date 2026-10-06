class_name DamageFormula
extends RefCounted

## The one formula for stat-based damage. compute() runs when the action is cast and
## returns the amount for one target before it is split across hits; the engine
## applies the hit-time terms (mitigation and damage resistance, defend, chain,
## barrier) as each hit lands.
##
## amount = stat term x modifier x level x element x killer x boost x jump x weapon
##          variance x variance
##   stat term  physical ATK^2 / DEF, magic MAG^2 / SPR, DEF-based DEF^2 / DEF,
##              SPR-based SPR^2 / SPR, hybrid the mean of physical and magic. Stats
##              include buffs and breaks; piercing lowers the defending stat. A dual
##              wielder's ATK leaves out the weapon that is not swinging (DualWield).
##   level      1 + the attacker's level / 100, for both sides (rules.level_correction)
##   element    1 - (mean resistance to the attack's elements) / 100, each resistance
##              (imperils included) capped at 100 first; see element_multiplier
##   killer     1 + killer percent against the target's races (physical killers for
##              physical and DEF-based damage, magic ones for magic and SPR-based):
##              per race, the passive killers capped at rules.passive_killer_cap_pct
##              plus the race's passive raise, then the active killer buffs on top
##   boost      element boost x skill boost x LB boost, each 1 + its percent; passive
##              skill and LB damage add to the matching buffs
##   jump       1 + the attacker's jump damage% (passive 17), capped at
##              rules.jump_damage_cap_pct, on a jump's landing (opcodes 52, 134) only: its
##              own multiplier (the user's rule, 2026-10-06)
##   weapon variance  a whole percent between the attacker's weapon's dmgVariance
##              values (Combatant.weapon_variance_min/max; 1.0 unarmed, for enemies and
##              with rules.weapon_variance off), for every kind, evoke included; a
##              two-handed jumper's landing keeps the higher of that and a roll of the
##              wiki's flat 2.50 to 2.80
##   variance   the final variance, in steps of 0.01 (rules.damage_variance_min/max)
## Crits are not modelled yet (BATTLE-ENGINE-HANDOVER.md section 10).
##
## Evoke damage (EVOKE, the wiki's formula, 2026-10-02) has its own terms:
##   amount = (MAG^2 x MAG ratio x MAG modifier + SPR^2 x SPR ratio x SPR modifier)
##            / target SPR x EVO MAG x level x element x evoke boost x weapon variance
##            x variance
##   EVO MAG      1 + the attacker's EVO MAG percent, capped at rules.evo_mag_cap_pct
##   evoke boost  1 + the evoke damage boost passives, capped at rules.evoke_boost_cap_pct
## No killers and no skill or LB boosts (the wiki lists chain, element and the evoke
## boost as its multipliers). The wiki has one modifier; the data carries one per stat,
## set exactly where that stat's ratio is (equal on mixed ratios), so the two readings
## give the same numbers.

## Which stats the formula compares. Percent and fixed damage do not use the formula
## and are not kinds.
enum Kind { PHYSICAL, MAGIC, HYBRID, DEF_BASED, SPR_BASED, EVOKE }

## Element names by 1-based element id (1 fire .. 8 dark), matching
## StatCalculator.ELEMENTS and the resistance keys on Combatant.
const ELEMENT_NAMES: PackedStringArray = [
	"FIRE", "ICE", "LIGHTNING", "WATER", "WIND", "EARTH", "LIGHT", "DARK",
]
## Resistance that stops all damage of an element. Higher values only matter against
## imperils; see element_multiplier.
const MAX_EFFECTIVE_RESISTANCE: int = 100
## The jump opcodes (52 JUMP, 134 JUMP_ACTIVATED): what passive 17 and the two-handed jump
## variance apply to.
const JUMP_OPCODES: Array[int] = [52, 134]


## What to compute: who hits whom, how, and what the attacker's boosts should match.
class Request:
	extends RefCounted
	var attacker: Combatant = null
	var target: Combatant = null
	## A DamageFormula.Kind value.
	var kind: int = 0
	## The skill modifier as a fraction (200% = 2.0); a hybrid's physical part, evoke
	## damage's MAG part.
	var modifier: float = 1.0
	## A hybrid's magic part.
	var magic_modifier: float = 1.0
	## Evoke damage: the SPR part's modifier, and each stat's share as a fraction
	## (50:50 is 0.5 and 0.5).
	var spr_modifier: float = 1.0
	var mag_ratio: float = 0.5
	var spr_ratio: float = 0.5
	## 1-based element ids.
	var elements: PackedInt32Array = PackedInt32Array()
	## Share of the defending stat the attack ignores (0.5 = half of DEF).
	var defense_ignore: float = 0.0
	## ATK the swing leaves out: a dual wielder's other weapon (DualWield.atk_left_out).
	var atk_left_out: int = 0
	## Ids the attacker's skill boosts are matched against (the chosen skill and the
	## skill that actually runs, which differ for wrappers).
	var skill_ids: PackedStringArray = PackedStringArray()
	## The effect's opcode, for skill boosts limited to some opcodes.
	var opcode: int = 0
	var is_limit_burst: bool = false


## The pieces of one damage computation, kept so tests and logs can see each term.
class Roll:
	extends RefCounted
	## A DamageFormula.Kind value.
	var kind: int = 0
	var stat_term: float = 0.0
	var modifier: float = 1.0
	var level_correction: float = 1.0
	var element_multiplier: float = 1.0
	var killer_multiplier: float = 1.0
	var boost_multiplier: float = 1.0
	## 1 + EVO MAG for evoke damage, 1.0 otherwise.
	var evo_multiplier: float = 1.0
	## 1 + the capped jump damage% on a landing, 1.0 otherwise.
	var jump_multiplier: float = 1.0
	var weapon_variance: float = 1.0
	var variance: float = 1.0
	## Total for this target, before the per-hit split and hit-time terms.
	var amount: float = 0.0


## A request with the common fields set. `kind` is a Kind value.
static func request(attacker: Combatant, target: Combatant, kind: int, modifier: float, elements: PackedInt32Array = PackedInt32Array()) -> Request:
	var made := Request.new()
	made.attacker = attacker
	made.target = target
	made.kind = kind
	made.modifier = modifier
	made.elements = elements
	return made


static func compute(req: Request, rules: BattleRules, rng: RandomNumberGenerator) -> Roll:
	var attacker: Combatant = req.attacker
	var target: Combatant = req.target
	var guard: float = maxf(0.0, 1.0 - req.defense_ignore)
	var roll := Roll.new()
	roll.kind = req.kind
	roll.modifier = req.modifier
	var atk: int = maxi(0, attacker.stat("ATK") - req.atk_left_out)
	match req.kind:
		Kind.PHYSICAL:
			roll.stat_term = stat_term(atk, target.stat("DEF") * guard)
			roll.killer_multiplier = killer_multiplier(attacker, target, "physical", rules)
		Kind.MAGIC:
			roll.stat_term = stat_term(attacker.stat("MAG"), target.stat("SPR") * guard)
			roll.killer_multiplier = killer_multiplier(attacker, target, "magic", rules)
		Kind.DEF_BASED:
			roll.stat_term = stat_term(attacker.stat("DEF"), target.stat("DEF") * guard)
			roll.killer_multiplier = killer_multiplier(attacker, target, "physical", rules)
		Kind.SPR_BASED:
			roll.stat_term = stat_term(attacker.stat("SPR"), target.stat("SPR") * guard)
			roll.killer_multiplier = killer_multiplier(attacker, target, "magic", rules)
		Kind.HYBRID:
			# Each half takes its own modifier and its own killers.
			var physical: float = stat_term(atk, target.stat("DEF") * guard) \
				* req.modifier * killer_multiplier(attacker, target, "physical", rules)
			var magical: float = stat_term(attacker.stat("MAG"), target.stat("SPR") * guard) \
				* req.magic_modifier * killer_multiplier(attacker, target, "magic", rules)
			roll.stat_term = (physical + magical) / 2.0
			roll.modifier = 1.0
		Kind.EVOKE:
			# Each stat takes its own share and modifier, so the modifier is in the term.
			var mag: float = float(attacker.stat("MAG"))
			var spr: float = float(attacker.stat("SPR"))
			roll.stat_term = (mag * mag * req.mag_ratio * req.modifier + spr * spr * req.spr_ratio * req.spr_modifier) \
				/ maxf(1.0, target.stat("SPR") * guard)
			roll.modifier = 1.0
			roll.evo_multiplier = evo_multiplier(attacker, rules)
	roll.level_correction = level_correction(attacker, rules)
	roll.element_multiplier = element_multiplier(target, req.elements)
	roll.boost_multiplier = evoke_boost_multiplier(attacker, rules) if req.kind == Kind.EVOKE else boost_multiplier(req)
	roll.jump_multiplier = jump_multiplier(attacker, req.opcode, rules)
	roll.weapon_variance = weapon_variance(attacker, rules, rng, req.opcode)
	roll.variance = _variance(rules, rng)
	roll.amount = maxf(0.0, roll.stat_term * roll.modifier * roll.evo_multiplier * roll.level_correction
		* roll.element_multiplier * roll.killer_multiplier * roll.boost_multiplier * roll.jump_multiplier
		* roll.weapon_variance * roll.variance)
	return roll


## 1 + the attacker's EVO MAG percent (passives), capped at rules.evo_mag_cap_pct.
static func evo_multiplier(attacker: Combatant, rules: BattleRules) -> float:
	return 1.0 + float(clampi(attacker.passives.evo_mag_pct, 0, rules.evo_mag_cap_pct)) / 100.0


## 1 + the attacker's jump damage% (passive 17, summed), capped at rules.jump_damage_cap_pct,
## for a landing (`opcode` 52 or 134); 1.0 for anything else.
static func jump_multiplier(attacker: Combatant, opcode: int, rules: BattleRules) -> float:
	if not JUMP_OPCODES.has(opcode):
		return 1.0
	return 1.0 + float(clampi(attacker.passives.jump_damage_pct, 0, rules.jump_damage_cap_pct)) / 100.0


## 1 + the attacker's evoke damage boost percent (passives that name no esper), capped at
## rules.evoke_boost_cap_pct.
static func evoke_boost_multiplier(attacker: Combatant, rules: BattleRules) -> float:
	return 1.0 + float(clampi(attacker.passives.evoke_damage_pct, 0, rules.evoke_boost_cap_pct)) / 100.0


static func stat_term(attack_stat: float, defense_stat: float) -> float:
	return attack_stat * attack_stat / maxf(1.0, defense_stat)


## 1 + the attacker's level / 100 (level 99 is 1.99), or 1.0 with the rule off.
static func level_correction(attacker: Combatant, rules: BattleRules) -> float:
	if not rules.level_correction:
		return 1.0
	return 1.0 + float(attacker.level) / 100.0


## 1 - mean resistance / 100 over the attack's elements; 1.0 for a non-elemental
## attack. A resistance above 100 (170 and 200 occur in the data) is headroom against
## imperils rather than absorption: 120 imperiled by 70 is 50. So each element's
## resistance, after its modifiers, counts as at most 100 (no damage) before the mean
## is taken. Absorbing comes from passives, not resistances. Weaknesses are not floored.
static func element_multiplier(target: Combatant, elements: PackedInt32Array) -> float:
	if elements.is_empty():
		return 1.0
	var total: float = 0.0
	for element in elements:
		total += float(mini(target.element_resistance(element_name(element)), MAX_EFFECTIVE_RESISTANCE))
	return 1.0 - total / float(elements.size()) / 100.0


## 1 + the attacker's killer percent against the target's races, averaged when the
## target has several. Per race, the passive killers count up to
## rules.passive_killer_cap_pct plus the attacker's passive raise for that race, and
## the active killer buffs add on top. `side` is "physical" or "magic".
static func killer_multiplier(attacker: Combatant, target: Combatant, side: String, rules: BattleRules) -> float:
	if target.races.is_empty():
		return 1.0
	var total: int = 0
	for race in target.races:
		var cap: int = rules.passive_killer_cap_pct + attacker.passives.killer_cap_bonus(race)
		total += mini(attacker.passives.killer_pct(side, race), cap)
		total += attacker.status_value(BattleStatus.KILLER, "%s:%d" % [side, race])
	return 1.0 + float(total) / float(target.races.size()) / 100.0


## Element boost (mean over the attack's elements), skill boosts and LB boosts (each
## summed across their sources, statuses and passives alike) multiply; each is 1 + its
## percent.
static func boost_multiplier(req: Request) -> float:
	var attacker: Combatant = req.attacker
	var element_pct: float = 0.0
	if not req.elements.is_empty():
		for element in req.elements:
			element_pct += float(attacker.status_value(BattleStatus.ELEMENT_BOOST, element_name(element)))
		element_pct /= float(req.elements.size())
	var skill_pct: int = 0
	for boost in attacker.statuses_of(BattleStatus.SKILL_BOOST):
		if _boost_applies(boost.params, req):
			skill_pct += boost.value
	for boost in attacker.passives.skill_boosts:
		if _boost_applies(boost, req):
			skill_pct += int(boost["pct"])
	var lb_pct: int = 0
	if req.is_limit_burst:
		for boost in attacker.statuses_of(BattleStatus.LB_BOOST):
			lb_pct += boost.value
		lb_pct += attacker.passives.lb_damage_pct
	return (1.0 + element_pct / 100.0) * (1.0 + float(skill_pct) / 100.0) * (1.0 + float(lb_pct) / 100.0)


## "FIRE" for 1 .. "DARK" for 8; "" outside that range.
static func element_name(element_id: int) -> String:
	if element_id < 1 or element_id > ELEMENT_NAMES.size():
		return ""
	return ELEMENT_NAMES[element_id - 1]


## Whether a skill boost (a SKILL_BOOST status's params, or one of
## CombatantPassives.skill_boosts) covers the request: its opcode filter, if any, holds
## the effect's opcode, and it lists one of the request's skill ids. `damage_type`
## (passive 73: 1 physical, 2 magic, 3 both) boosts every attack of that type when no
## skill ids are listed, and limits the listed ones otherwise. An opcode filter with no
## skill ids boosts every effect with those opcodes (passive 73's `52&134` rows: the jump
## abilities).
static func _boost_applies(params: Dictionary, req: Request) -> bool:
	var opcodes: Array = params.get("opcodes", [])
	if not opcodes.is_empty() and not opcodes.has(req.opcode):
		return false
	var damage_type: int = int(params.get("damage_type", 0))
	if damage_type != 0 and (damage_type & _damage_type_bits(req.kind)) == 0:
		return false
	var boosted: PackedStringArray = params.get("skill_ids", PackedStringArray())
	if boosted.is_empty():
		return damage_type != 0 or not opcodes.is_empty()
	for skill_id in req.skill_ids:
		if boosted.has(skill_id):
			return true
	return false


## 1 for physical and DEF-based damage, 2 for magic and SPR-based, 3 for hybrid (both
## halves), matching passive 73's damage_type and the killer sides.
static func _damage_type_bits(kind: int) -> int:
	match kind:
		Kind.PHYSICAL, Kind.DEF_BASED:
			return 1
		Kind.MAGIC, Kind.SPR_BASED:
			return 2
		Kind.HYBRID:
			return 3
	return 0


## A whole percent between the attacker's weapon variance bounds (110 .. 120 gives one of
## 11 values), as a fraction. 1.0 with rules.weapon_variance off; equal bounds (fists'
## 115 .. 115) skip the roll. A jump's landing (`opcode` 52 or 134) by a two-handed
## attacker also rolls rules.jump_two_handed_variance_min .. _max and keeps the higher of
## the two (the wiki; only Fixed Dice's 120 .. 560 can beat it).
static func weapon_variance(attacker: Combatant, rules: BattleRules, rng: RandomNumberGenerator, opcode: int = 0) -> float:
	if not rules.weapon_variance:
		return 1.0
	var pct: int = _roll_pct(attacker.weapon_variance_min, attacker.weapon_variance_max, rng)
	if attacker.two_handed and JUMP_OPCODES.has(opcode):
		pct = maxi(pct, _roll_pct(rules.jump_two_handed_variance_min, rules.jump_two_handed_variance_max, rng))
	return float(pct) / 100.0


## A whole percent between `low` and `high`; `low` without a roll when they are equal (or
## the wrong way round).
static func _roll_pct(low: int, high: int, rng: RandomNumberGenerator) -> int:
	return low if high <= low else rng.randi_range(low, high)


## A whole number of hundredths between the rule's bounds, so 0.85 .. 1.0 gives one of
## 16 values.
static func _variance(rules: BattleRules, rng: RandomNumberGenerator) -> float:
	var low: int = roundi(rules.damage_variance_min * 100.0)
	var high: int = roundi(rules.damage_variance_max * 100.0)
	if high <= low:
		return rules.damage_variance_min
	return float(rng.randi_range(low, high)) / 100.0

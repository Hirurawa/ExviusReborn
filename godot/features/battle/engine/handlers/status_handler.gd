class_name StatusHandler
extends EffectHandler

## Effects that put timed statuses (BattleStatus) on their targets. Each target takes
## one hit, on the effect's first frame, that applies what the effect builds; the
## engine rolls chances and resistances and replaces statuses with the same stack key.
##
##   3 STAT_BOOST_PCT, 24 STAT_BREAK         STAT per stat (breaks are negative)
##   33 ELEMENT_RESISTANCE                   ELEMENT_RESIST per element (imperils negative)
##   7 STATUS_RESIST                         AILMENT_RESIST per ailment
##   140 STATUS_RESIST_DOWN                  NO_AILMENT_RESIST per flagged ailment (1, or
##                                           -100 in two rows): resistance counts as 0
##   146 STATUS_RESIST_DOWN_V2               AILMENT_RESIST lowered by each percent
##   89 BREAK_RESISTANCE                     DEBUFF_RESIST per stat, STOP, CHARM
##   101 / 18 / 19 damage reduction          MITIGATION all / physical / magic
##   92 / 93 killers                         KILLER per race
##   153 / 154 race mitigation               RACE_MITIGATION per race
##   149 ELEMENT_DAMAGE_BOOST                ELEMENT_BOOST per element
##   136 SKILL_DAMAGE_BOOST                  SKILL_BOOST per stack group
##   120 LB_DAMAGE                           LB_BOOST
##   171 LB_DAMAGE_BOOST_SPECIFIC            LB_BOOST, or SKILL_BOOST for the listed LBs
##   95 PHYS_ELEMENT                         IMBUE per element
##   54 DODGE, 127 SHIELD                    evasions left, barrier HP
##   8 REGEN, 30 MP_REGEN                    amount per turn from the caster's stats at cast
##   27 AUTO_REVIVE, 63 LB_FILLRATE          HP percent on revival, gauge fill boost
##   61 AGGRO_INCREASE                       PROVOKE: chance to draw an enemy's random
##                                           single-target pick
##   119 PHYS_COUNTER, 123 ALLY_COUNTER      COUNTER "self" / "ally": chance to counter
##                                           physical attacks on the bearer / on its
##                                           other allies (Counters)
##   6 STATUS_INFLICT, 88 STOP               AILMENT, each with its own chance
##   34 RANDOM_STATUS_INFLICT                AILMENT: `amount` of the listed ailments,
##                                           picked per target, each with its chance
##   60 CHARM, 68 BERSERK, 144 ZOMBIE_INFLICT AILMENT (berserk always lands unless
##                                           resisted; its value is the ATK boost)
##
## Durations come from turn_count: -1 lasts until removed, and 0 (27% of breaks, mostly
## on monster skills; its meaning is unconfirmed) lasts BattleRules.zero_turn_status_turns.
## An ailment's behaviour then decides how long it really lasts: the status ailments
## ignore the data (permanent, or the party's sleep turns), while stop, charm and berserk
## keep it. Charm's duration is its unnamed first slot (1-3 in most rows), a reading
## that is unconfirmed.

const STATS: PackedStringArray = ["ATK", "DEF", "MAG", "SPR"]
## Param keys of the per-element opcodes, in element order.
const ELEMENT_KEYS: PackedStringArray = ["fire", "ice", "lightning", "water", "wind", "earth", "light", "dark"]
## Param keys of the per-ailment opcodes (6, 7), in Combatant.AILMENTS order.
const AILMENT_KEYS: PackedStringArray = ["poison", "blind", "sleep", "silence", "paralyze", "confusion", "disease", "petrify"]
const MITIGATION_KEYS: Dictionary = {
	"DAMAGE_REDUCE": "all", "PHYS_DAMAGE_REDUCE": "physical", "MAG_DAMAGE_REDUCE": "magic",
}


func handled_types() -> PackedStringArray:
	return PackedStringArray([
		"STAT_BOOST_PCT", "STAT_BREAK", "ELEMENT_RESISTANCE", "STATUS_RESIST", "STATUS_RESIST_DOWN", "STATUS_RESIST_DOWN_V2", "BREAK_RESISTANCE",
		"DAMAGE_REDUCE", "PHYS_DAMAGE_REDUCE", "MAG_DAMAGE_REDUCE",
		"PHYS_KILLER_BUFF", "MAG_KILLER_BUFF", "PHYS_RACE_MITIGATION", "MAG_RACE_MITIGATION",
		"ELEMENT_DAMAGE_BOOST", "SKILL_DAMAGE_BOOST", "LB_DAMAGE", "LB_DAMAGE_BOOST_SPECIFIC", "PHYS_ELEMENT",
		"DODGE", "SHIELD", "REGEN", "MP_REGEN", "AUTO_REVIVE", "LB_FILLRATE", "AGGRO_INCREASE", "PHYS_COUNTER", "ALLY_COUNTER",
		"STATUS_INFLICT", "STOP", "RANDOM_STATUS_INFLICT", "CHARM", "BERSERK", "ZOMBIE_INFLICT",
	])


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, targets: Array[Combatant]) -> void:
	var actor: Combatant = engine.combatant(action.actor_id)
	if actor == null:
		return
	for target in targets:
		var hit: ScheduledHit = new_hit(action, effect, target)
		# Built per target: every target needs its own status objects to count down.
		hit.payload = {"statuses": build(engine, effect, actor)}
		engine.schedule_hit(hit, effect.hit_frames[0])


func resolve(engine: BattleEngine, hit: ScheduledHit) -> void:
	var target: Combatant = engine.combatant(hit.target_id)
	if target == null or not target.is_alive():
		return
	for entry in hit.payload["statuses"]:
		# A status can KO the target (petrify on an enemy); the rest do not land.
		if not target.is_alive():
			return
		engine.apply_status(hit, target, entry["status"], int(entry["chance"]))


## [{ status: BattleStatus, chance: int }] for one target. Chance is 100 except for
## ailments.
func build(engine: BattleEngine, effect: SkillEffect, actor: Combatant) -> Array:
	var turns: int = _turns(engine, effect)
	var out: Array = []
	match effect.type:
		"STAT_BOOST_PCT", "STAT_BREAK":
			for stat_name in STATS:
				_add(out, BattleStatus.STAT, stat_name, int(effect.param_float(stat_name)), turns)
		"ELEMENT_RESISTANCE":
			for i in range(ELEMENT_KEYS.size()):
				_add(out, BattleStatus.ELEMENT_RESIST, DamageFormula.ELEMENT_NAMES[i], int(effect.param_float(ELEMENT_KEYS[i])), turns)
		"STATUS_RESIST":
			for i in range(AILMENT_KEYS.size()):
				_add(out, BattleStatus.AILMENT_RESIST, Combatant.AILMENTS[i], int(effect.param_float(AILMENT_KEYS[i])), turns)
		"STATUS_RESIST_DOWN":
			for i in range(AILMENT_KEYS.size()):
				if effect.param_float(AILMENT_KEYS[i]) != 0.0:
					out.append({"status": BattleStatus.make(BattleStatus.NO_AILMENT_RESIST, Combatant.AILMENTS[i], 0, turns), "chance": 100})
		"STATUS_RESIST_DOWN_V2":
			var pcts: Variant = effect.params.get("ailments", [])
			if pcts is Array:
				for i in range(mini((pcts as Array).size(), Combatant.AILMENTS.size())):
					_add(out, BattleStatus.AILMENT_RESIST, Combatant.AILMENTS[i], -absi(_int(pcts[i])), turns)
		"BREAK_RESISTANCE":
			for key in ["ATK", "DEF", "MAG", "SPR", "STOP", "CHARM"]:
				_add(out, BattleStatus.DEBUFF_RESIST, key, int(effect.param_float(key)), turns)
		"DAMAGE_REDUCE", "PHYS_DAMAGE_REDUCE", "MAG_DAMAGE_REDUCE":
			_add(out, BattleStatus.MITIGATION, MITIGATION_KEYS[effect.type], int(effect.param_float("pct")), turns)
		"PHYS_KILLER_BUFF", "MAG_KILLER_BUFF":
			_add_races(out, effect, BattleStatus.KILLER, "physical" if effect.type == "PHYS_KILLER_BUFF" else "magic", 8, turns)
		"PHYS_RACE_MITIGATION", "MAG_RACE_MITIGATION":
			_add_races(out, effect, BattleStatus.RACE_MITIGATION, "physical" if effect.type == "PHYS_RACE_MITIGATION" else "magic", 6, turns)
		"ELEMENT_DAMAGE_BOOST":
			var pcts: Variant = effect.params.get("elements", [])
			if pcts is Array:
				for i in range(mini((pcts as Array).size(), DamageFormula.ELEMENT_NAMES.size())):
					_add(out, BattleStatus.ELEMENT_BOOST, DamageFormula.ELEMENT_NAMES[i], _int(pcts[i]), turns)
		"SKILL_DAMAGE_BOOST":
			var boost: BattleStatus = BattleStatus.make(BattleStatus.SKILL_BOOST, str(effect.params.get("stack_id", 0)),
				int(effect.param_float("pct")), turns, {
					"skill_ids": _id_list(effect.params.get("skill_ids", [])),
					"opcodes": _int_list(effect.params.get("opcode_filter", [])),
				})
			out.append({"status": boost, "chance": 100})
		"LB_DAMAGE":
			_add(out, BattleStatus.LB_BOOST, "", int(effect.param_float("pct")), turns)
		"LB_DAMAGE_BOOST_SPECIFIC":
			# lb_ids is 0 in 78% of rows: then it boosts every limit burst.
			var lb_ids: PackedStringArray = _id_list(effect.params.get("lb_ids", []))
			var stack: String = "171:%s" % str(effect.params.get("stack_id", 0))
			var pct: int = int(effect.param_float("pct"))
			if lb_ids.is_empty():
				_add(out, BattleStatus.LB_BOOST, stack, pct, turns)
			elif pct != 0:
				out.append({"status": BattleStatus.make(BattleStatus.SKILL_BOOST, stack, pct, turns, {
					"skill_ids": lb_ids, "opcodes": _int_list(effect.params.get("opcode_filter", [])),
				}), "chance": 100})
		"PHYS_ELEMENT":
			for i in range(ELEMENT_KEYS.size()):
				if effect.param_float(ELEMENT_KEYS[i]) != 0.0:
					_add(out, BattleStatus.IMBUE, DamageFormula.ELEMENT_NAMES[i], 1, turns)
		"DODGE":
			_add(out, BattleStatus.DODGE, "", int(effect.param_float("amount")), turns)
		"SHIELD":
			_add(out, BattleStatus.SHIELD, "", int(effect.param_float("HP")), turns)
		"REGEN":
			_add(out, BattleStatus.REGEN, "", floori(RestoreHandler.heal_amount(actor, effect.param_float("amount"), effect.param_float("modifier"))), turns)
		"MP_REGEN":
			_add(out, BattleStatus.MP_REGEN, "", floori(RestoreHandler.heal_amount(actor, effect.param_float("MP_amount"), effect.param_float("modifier"))), turns)
		"AUTO_REVIVE":
			_add(out, BattleStatus.AUTO_REVIVE, "", int(effect.param_float("HP_pct")), turns)
		"LB_FILLRATE":
			_add(out, BattleStatus.LB_FILL_RATE, "", int(effect.param_float("pct")), turns)
		"AGGRO_INCREASE":
			_add(out, BattleStatus.PROVOKE, "", int(effect.param_float("pct")), turns)
		"PHYS_COUNTER", "ALLY_COUNTER":
			var chance: int = int(effect.param_float("counter_chance"))
			if chance > 0:
				out.append({"status": BattleStatus.make(BattleStatus.COUNTER, "self" if effect.type == "PHYS_COUNTER" else "ally", chance, turns, {
					"modifier": int(effect.param_float("modifier")), "max": int(effect.param_float("max")),
				}), "chance": 100})
		"STATUS_INFLICT":
			for i in range(AILMENT_KEYS.size()):
				_add_ailment(out, Combatant.AILMENTS[i], int(effect.param_float(AILMENT_KEYS[i])), turns)
		"STOP":
			_add_ailment(out, "STOP", int(effect.param_float("chance_pct")), turns)
		"RANDOM_STATUS_INFLICT":
			var listed: Array = []
			for i in range(AILMENT_KEYS.size()):
				if effect.param_float(AILMENT_KEYS[i]) > 0.0:
					listed.append(i)
			var picks: int = mini(maxi(1, int(effect.param_float("amount", 1.0))), listed.size())
			for _n in range(picks):
				var index: int = listed.pop_at(engine.rng.randi_range(0, listed.size() - 1))
				_add_ailment(out, Combatant.AILMENTS[index], int(effect.param_float(AILMENT_KEYS[index])), turns)
		"CHARM":
			var charm_turns: int = _int(effect.raw_params[0]) if not effect.raw_params.is_empty() else 0
			_add_ailment(out, "CHARM", int(effect.param_float("pct")), charm_turns if charm_turns != 0 else engine.rules.zero_turn_status_turns)
		"BERSERK":
			out.append({"status": BattleStatus.make(BattleStatus.AILMENT, "BERSERK", int(effect.param_float("atk_pct")), turns), "chance": 100})
		"ZOMBIE_INFLICT":
			_add_ailment(out, "ZOMBIE", int(effect.param_float("chance_pct")), turns)
	return out


static func _add(out: Array, kind: StringName, key: String, value: int, turns: int) -> void:
	if value != 0:
		out.append({"status": BattleStatus.make(kind, key, value, turns), "chance": 100})


static func _add_ailment(out: Array, key: String, chance: int, turns: int) -> void:
	if chance > 0:
		out.append({"status": BattleStatus.make(BattleStatus.AILMENT, key, 0, turns), "chance": chance})


## Race slots hold [race_id, pct] or -1.
static func _add_races(out: Array, effect: SkillEffect, kind: StringName, side: String, slots: int, turns: int) -> void:
	for i in range(1, slots + 1):
		var slot: Variant = effect.params.get("race_%d" % i)
		if slot is Array and (slot as Array).size() >= 2:
			_add(out, kind, "%s:%d" % [side, _int(slot[0])], _int(slot[1]), turns)


## -1 lasts until removed; 0 (unconfirmed meaning) and a missing turn_count last
## BattleRules.zero_turn_status_turns.
static func _turns(engine: BattleEngine, effect: SkillEffect) -> int:
	var turns: int = int(effect.param_float("turn_count"))
	if turns < 0:
		return -1
	return turns if turns > 0 else engine.rules.zero_turn_status_turns


static func _int(value: Variant) -> int:
	return int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else 0


## A slot holding one id or a list of ids, as strings.
static func _id_list(value: Variant) -> PackedStringArray:
	var ids := PackedStringArray()
	for item in (value if value is Array else [value]):
		if typeof(item) in [TYPE_INT, TYPE_FLOAT] and int(item) > 0:
			ids.append(str(int(item)))
	return ids


static func _int_list(value: Variant) -> Array:
	var out: Array = []
	for item in (value if value is Array else [value]):
		if typeof(item) in [TYPE_INT, TYPE_FLOAT] and int(item) > 0:
			out.append(int(item))
	return out

class_name PassiveAggregator
extends RefCounted

## The one place that knows what each passive opcode means for a unit's profile. Sums
## the parsed effects of a unit's active passives into totals: stats, equipment-stat
## boosts and resistances, which StatCalculator applies, and battle modifiers (killers,
## LB and skill damage),
## which CombatantPassives carries into the engine. Static and free of autoloads, so
## tests pass hand-written effects and loadouts.
##
## Each handled type is one row of SPECS:
##   pool     where its values go (the POOL_* totals below); the effect's other keys are
##            matched against that pool's names, and keys it does not name are ignored
##   handler  instead of a pool, a HANDLER_* that reads the params listed in `reads`
##   when     a condition on the loadout or esper (WHEN_*), read from param `key`
##   key      the param holding the condition's ids
## A type without a row goes to `unconsumed` untouched, with its source, for later
## work (fatal-prevent, HP triggers, espers...).
##
## Rules (the user's, 2026-09-30): the same passive from two sources counts twice;
## equip-conditional stat boosts share op 1's percent pool, which StatCalculator caps at
## 400%; ESPER_STAT multiplies the esper's contribution, and one naming an esper applies
## only with that esper; killers are summed here and capped per race in DamageFormula;
## LB and skill damage passives add to the matching buffs; the equipment-stat boosts
## (doublehand, true doublehand, true dual wield, single weapon, unarmed) share one
## pool per stat, capped at 400%, applied to every equipped item's stat; chain modifier
## boosts apply to the unit's own hits only (ChainTracker).

const STATS: PackedStringArray = ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]
## Resistance keys in data order, as StatCalculator.ELEMENTS and STATUSES.
const ELEMENTS: PackedStringArray = ["FIRE", "ICE", "LIGHTNING", "WATER", "WIND", "EARTH", "LIGHT", "DARK"]
const STATUSES: PackedStringArray = ["POISON", "BLIND", "SLEEP", "SILENCE", "PARALYSIS", "CONFUSION", "DISEASE", "PETRIFY"]
## Break, stop and charm resistance, keyed as Combatant.DEBUFF_KEYS (which adds BERSERK,
## a monster-only column).
const DEBUFFS: PackedStringArray = ["ATK", "DEF", "MAG", "SPR", "STOP", "CHARM"]

const POOL_STAT_PCT: String = "stat_pct"
const POOL_STAT_FLAT: String = "stat_flat"
const POOL_ELEMENT: String = "element_resist"
const POOL_STATUS: String = "status_resist"
const POOL_DEBUFF: String = "debuff_resist"
const POOL_ESPER_PCT: String = "esper_stat_pct"
## Percent boosts to the equipment's own stats (doublehand, true doublehand, true dual
## wield, single-weapon and unarmed boosts), one pool per stat that StatCalculator caps
## at 400% and applies to every equipped item's stat.
const POOL_EQUIPMENT_PCT: String = "equipment_stat_pct"

## Killer percent per race: race_id, phys_pct and mag_pct are each a value or a list,
## lists running in parallel ("5&6" with "50&50"); a single percent covers every race.
const HANDLER_KILLER: String = "killer"
## Op 105: raises the killer cap for a race by pct, and adds pct to its physical and
## magic killers ("Boost physical and magic damage and parameter limit ... by 10%", the
## skill's only effect).
const HANDLER_KILLER_LIMIT: String = "killer_limit"
## Adds the row's `param` (times `sign`, default 1) to the scalar total named `total`.
const HANDLER_TOTAL: String = "total"
const HANDLER_SKILL_BOOST: String = "skill_boost"
## Op 72: the limit burst that replaces the unit's own (the last one wins).
const HANDLER_LB_CHANGE: String = "lb_change"
## Op 100: the ability that replaces the normal attack (the last one wins; no unit has
## two at once in the data).
const HANDLER_ATTACK_REPLACE: String = "attack_replace"
## `pct` into POOL_EQUIPMENT_PCT for the row's `stat`, or for the stat its `stat_key`
## param names (1 ATK, 2 DEF, 3 MAG, 4 SPR).
const HANDLER_EQUIPMENT_STAT: String = "equipment_stat"
## Raises the unit's chain cap by `pct`, or by the row's `fixed_pct` for the opcodes
## that carry no value (81, 106).
const HANDLER_CHAIN_CAP: String = "chain_cap"
## Adds `pct` to the chain modifier of the unit's own chained hits. 84 and 85 appear
## together with the same value in 200 of their 205 skills, and each alone reads the
## same ("boost damage for various chains by 100%"), so a skill counts the larger of
## the two once.
const HANDLER_CHAIN_BOOST: String = "chain_boost"
## Ops 8 and 59: a single-target cover of any ally into `covers`, physical or magic by
## the row's `physical` / `magic` (CoverTracker reads them).
const HANDLER_COVER: String = "cover"
## Ops 52 and 53: the multicast command (an active ability, Multicast) the passive puts in
## the unit's skill list for the whole battle, named by the row's `param`, into
## `multicast_commands`; the passive's pick count (the row's `count` param) and ability
## list (`list`) into `multicast_picks` under the command's id. They decide what the
## command picks: no unit learns the active itself, and where the two differ the
## passive's copy is the kept one (Triple Strongest Attack's active says 2 casts, its
## passive and both texts 3; passive lists hold enhanced abilities their actives miss).
const HANDLER_MULTICAST_COMMAND: String = "multicast_command"
## Ops 12, 41, 49 and 50: a chance to counter attacks of the row's `trigger` (physical or
## magic) into `counters` (the engine's Counters reads them). 12 and 41 answer with the
## normal attack at their `modifier`; 49 and 50 with the skill their `cast_type` and
## `skill_id` name (COUNTER_CAST_KINDS).
const HANDLER_COUNTER: String = "counter"
## Ops 103, 35, 56 and 66: a skill the passive casts on its own, into `auto_casts`: at
## the battle start, after a revive and at each turn start, as the row's flags say.
const HANDLER_AUTO_CAST: String = "auto_cast"

## The skill kind a counter casts, by 49 and 50's cast_type (the data's tables: 1 the
## normal attack, 2 magic, 3 ability, 4 monster skill), as BattleSkill.KIND_* values.
const COUNTER_CAST_KINDS: Dictionary = {1: "attack", 2: "magic", 3: "ability", 4: "monster_skill"}

## Op 81's raise while dual wielding: "Increase chain modifier cap (200%) when dual
## wielding" (the user, 2026-09-30); op 106's text gives the same 200%.
const DUAL_WIELD_CHAIN_CAP_RAISE: int = 200

## The loadout's categories hold one of the ids (equipCategory: weapon types, armor...).
const WHEN_CATEGORY: String = "category"
## As WHEN_CATEGORY, but a missing param means no restriction.
const WHEN_CATEGORY_IF_SET: String = "category_if_set"
## The loadout's equipment holds one of the item ids.
const WHEN_ITEM: String = "item"
## A weapon in either hand has the element (1 fire .. 8 dark).
const WHEN_WEAPON_ELEMENT: String = "weapon_element"
## The unit has an esper, and it is the one named (a missing id means any esper).
const WHEN_ESPER: String = "esper"
## The param is a wield mode: 0 (or missing) needs one one-handed weapon with the other
## hand empty (doublehand), 1 or 2 one weapon of either kind with the other hand empty
## (true doublehand). A shield is not an empty hand.
const WHEN_SINGLE_WIELD: String = "single_wield"
## Two weapons in the hands.
const WHEN_DUAL_WIELD: String = "dual_wield"
## One weapon, one- or two-handed, with nothing else in the hands, of one of the listed
## categories (a missing list means any weapon).
const WHEN_SINGLE_WEAPON_OF: String = "single_weapon_of"
## No weapon in either hand.
const WHEN_UNARMED: String = "unarmed"
## The param names no esper (missing or 0): the evoke damage boost counts only then (wiki).
const WHEN_NO_ESPER_NAMED: String = "no_esper_named"

const _KILLER_READS: Array = ["race_id", "phys_pct", "mag_pct"]
const _COVER_READS: Array = ["condition", "hp_below_pct", "dmg_reduce_min", "dmg_reduce_max", "chance_pct"]
const _WIELD_READS: Array = ["pct", "wield_mode"]
## Stat ids of 69 and 99.
const _STAT_IDS: Dictionary = {1: "ATK", 2: "DEF", 3: "MAG", 4: "SPR"}

const SPECS: Dictionary = {
	"STAT_BOOST_PCT": {"pool": POOL_STAT_PCT},
	"FIX_STAT": {"pool": POOL_STAT_FLAT},
	"ELEMENT_RESIST": {"pool": POOL_ELEMENT},
	"STATUS_RESIST": {"pool": POOL_STATUS},
	"SPECIAL_STATUS_RESIST": {"pool": POOL_DEBUFF},
	"EQUIP_CONDITIONAL_BOOST": {"pool": POOL_STAT_PCT, "when": WHEN_CATEGORY, "key": "equip_id"},
	"EQUIP_SET_BOOST": {"pool": POOL_STAT_PCT, "when": WHEN_ITEM, "key": "equip_ids"},
	"WEAPON_ELEMENT_RESIST": {"pool": POOL_ELEMENT, "when": WHEN_CATEGORY, "key": "equip_type"},
	"ELEMENT_WEAPON_STAT_BOOST": {"pool": POOL_STAT_PCT, "when": WHEN_WEAPON_ELEMENT, "key": "element"},
	"ESPER_STAT": {"pool": POOL_ESPER_PCT, "when": WHEN_ESPER, "key": "esper_id"},
	"KILLER": {"handler": HANDLER_KILLER, "reads": _KILLER_READS},
	"EQUIP_CONDITIONAL_KILLER": {"handler": HANDLER_KILLER, "reads": _KILLER_READS, "when": WHEN_CATEGORY, "key": "equip_type"},
	"KILLER_LIMIT_BOOST": {"handler": HANDLER_KILLER_LIMIT, "reads": ["race_id", "pct"]},
	"LB_DAMAGE": {"handler": HANDLER_TOTAL, "total": "lb_damage_pct", "param": "pct", "reads": ["pct"]},
	# Gauges, evasion, targeting and costs (the user's rules, 2026-10-01).
	"LB_FILLRATE": {"handler": HANDLER_TOTAL, "total": "lb_fill_rate_pct", "param": "pct", "reads": ["pct"]},
	"MP_PER_TURN": {"handler": HANDLER_TOTAL, "total": "mp_regen_pct", "param": "pct", "reads": ["pct"]},
	"LB_GAUGE_INCREASE": {"handler": HANDLER_TOTAL, "total": "lb_per_turn", "param": "amount", "reads": ["amount"]},
	"EVASION": {"handler": HANDLER_TOTAL, "total": "evade_physical_pct", "param": "pct", "reads": ["pct"]},
	"MAGIC_EVASION": {"handler": HANDLER_TOTAL, "total": "evade_magic_pct", "param": "pct", "reads": ["pct"]},
	"AGGRO_INCREASE": {"handler": HANDLER_TOTAL, "total": "aggro_pct", "param": "pct", "reads": ["pct"]},
	"AGGRO_DECREASE": {"handler": HANDLER_TOTAL, "total": "aggro_pct", "param": "pct", "sign": -1, "reads": ["pct"]},
	"MP_REDUCTION": {"handler": HANDLER_TOTAL, "total": "ability_mp_cut_pct", "param": "pct", "reads": ["pct"]},
	# Evocation (the wiki's evoke damage formula, 2026-10-02): EVO MAG, and the evoke damage
	# boost, which counts only when it names no esper (45 of op 64's 183 rows name one).
	"ESPER_DAMAGE": {"handler": HANDLER_TOTAL, "total": "evo_mag_pct", "param": "pct", "reads": ["pct"]},
	"EVOKE_DAMAGE_BOOST": {"handler": HANDLER_TOTAL, "total": "evoke_damage_pct", "param": "pct", "reads": ["pct"], "when": WHEN_NO_ESPER_NAMED, "key": "esper_id"},
	# Jump damage% (the wiki: stacks additively, capped at 800% in DamageFormula).
	"JUMP": {"handler": HANDLER_TOTAL, "total": "jump_damage_pct", "param": "pct", "reads": ["pct"]},
	"LB_CHANGE": {"handler": HANDLER_LB_CHANGE, "reads": ["lb_id"]},
	"NORMAL_ATTACK_REPLACE": {"handler": HANDLER_ATTACK_REPLACE, "reads": ["skill_id"], "when": WHEN_CATEGORY_IF_SET, "key": "equip_type"},
	"SKILL_DAMAGE_BOOST": {"handler": HANDLER_SKILL_BOOST, "reads": ["skill_ids", "damage_type", "opcode_filter", "pct"]},
	# Equipment-stat boosts. Doublehand's accuracy slot (13 and 70) is not read yet.
	"EQUIPMENT_ATK": {"handler": HANDLER_EQUIPMENT_STAT, "stat": "ATK", "reads": _WIELD_READS, "when": WHEN_SINGLE_WIELD, "key": "wield_mode"},
	"EQUIPMENT_MAG": {"handler": HANDLER_EQUIPMENT_STAT, "stat": "MAG", "reads": _WIELD_READS, "when": WHEN_SINGLE_WIELD, "key": "wield_mode"},
	"EQUIP_STATS_SINGLE_WEAPON": {"pool": POOL_EQUIPMENT_PCT, "when": WHEN_SINGLE_WIELD, "key": "wield_mode"},
	"DUAL_WIELD_EQUIPMENT_STAT": {"handler": HANDLER_EQUIPMENT_STAT, "stat_key": "stat_id", "reads": ["stat_id", "pct"], "when": WHEN_DUAL_WIELD},
	"EQUIP_STAT_SINGLE_WEAPON": {"handler": HANDLER_EQUIPMENT_STAT, "stat_key": "stat_id", "reads": ["stat_id", "pct", "weapon_types"], "when": WHEN_SINGLE_WEAPON_OF, "key": "weapon_types"},
	"UNARMED_ATK": {"handler": HANDLER_EQUIPMENT_STAT, "stat": "ATK", "reads": ["pct"], "when": WHEN_UNARMED},
	# Chain passives.
	"CHAIN_DAMAGE_LIMIT_BOOST": {"handler": HANDLER_CHAIN_CAP, "reads": ["pct"]},
	"DUAL_WIELD_CHAIN_LIMIT": {"handler": HANDLER_CHAIN_CAP, "fixed_pct": DUAL_WIELD_CHAIN_CAP_RAISE, "reads": [], "when": WHEN_DUAL_WIELD},
	"DUAL_WIELD_CHAIN_LIMIT_FIXED": {"handler": HANDLER_CHAIN_CAP, "fixed_pct": DUAL_WIELD_CHAIN_CAP_RAISE, "reads": [], "when": WHEN_DUAL_WIELD},
	"CHAIN_DAMAGE_BOOST": {"handler": HANDLER_CHAIN_BOOST, "reads": ["pct"]},
	"CHAIN_DAMAGE_BOOST_2": {"handler": HANDLER_CHAIN_BOOST, "reads": ["pct"]},
	# Covers (the wiki's rules and the user's, 2026-10-01; CoverTracker).
	"INTERCEPT": {"handler": HANDLER_COVER, "physical": true, "reads": _COVER_READS},
	"ST_MAGIC_COVER": {"handler": HANDLER_COVER, "magic": true, "reads": _COVER_READS},
	# Multicast commands (the user's go-ahead, 2026-10-05). 102 waits for its skill types.
	# 52's magic type always matches its command's, so only its count is read.
	"MULTICAST": {"handler": HANDLER_MULTICAST_COMMAND, "param": "ability_id", "count": "cast_amount", "reads": ["ability_id", "magic_type", "cast_amount"]},
	"MULTICAST_SKILLS": {"handler": HANDLER_MULTICAST_COMMAND, "param": "skill_id", "count": "cast_count", "list": "skill_ids", "reads": ["skill_id", "cast_count", "skill_ids"]},
	# Counters (the wiki's rules, 2026-10-06; REACTIONS-PLAN.md). 20 multiplies every
	# counter chance (100 doubles it).
	"COUNTER": {"handler": HANDLER_COUNTER, "trigger": "physical", "reads": ["chance_pct", "modifier", "max"]},
	"COUNTER_MAGIC_ATTACK": {"handler": HANDLER_COUNTER, "trigger": "magic", "reads": ["chance_pct", "modifier", "max"]},
	"PHYS_COUNTER_ABILITY": {"handler": HANDLER_COUNTER, "trigger": "physical", "cast": true, "reads": ["chance_pct", "cast_type", "skill_id", "max"]},
	"MAG_COUNTER_ABILITY": {"handler": HANDLER_COUNTER, "trigger": "magic", "cast": true, "reads": ["chance_pct", "cast_type", "skill_id", "max"]},
	"COUNTER_CHANCE": {"handler": HANDLER_TOTAL, "total": "counter_chance_pct", "param": "pct", "reads": ["pct"]},
	# Skills cast on their own. 56 casts after a revive too, including the older rows
	# whose text names only the battle start (a reading).
	"BATTLE_START_CAST": {"handler": HANDLER_AUTO_CAST, "param": "skill_id", "kind": "ability", "battle_start": true, "reads": ["skill_id"]},
	"START_OF_BATTLE_OR_REVIVE": {"handler": HANDLER_AUTO_CAST, "param": "ability_id", "kind": "magic", "battle_start": true, "revive": true, "reads": ["ability_id"]},
	"REVIVE_AUTO_ABILITY": {"handler": HANDLER_AUTO_CAST, "param": "ability_id", "kind": "ability", "battle_start": true, "revive": true, "reads": ["ability_id"]},
	"TURN_START_CAST": {"handler": HANDLER_AUTO_CAST, "param": "skill_id", "kind": "ability", "turn_start": true, "chance": "pct", "reads": ["skill_id", "pct"]},
}

## Param names that differ from a pool's key (the schema's names are lower case or
## carry a suffix); the rest are upper-cased.
const _KEY_ALIASES: Dictionary = {
	"PARALYZE": "PARALYSIS",
	"PETRIFICATION": "PETRIFY",
	"ATK_BREAK": "ATK",
	"DEF_BREAK": "DEF",
	"MAG_BREAK": "MAG",
	"SPR_BREAK": "SPR",
}


## Totals for a unit's active passives. `sources` holds one entry per passive:
## { skill_id, source ("Trait", "Equip", "Esper"), effects (OpcodeParser.parse_passive's
## list) }. `loadout` is PassiveSources.build_loadout's and `esper`
## StatCalculator.resolve_party_esper's ({} for none). Returns:
##   stat_pct, stat_flat, esper_stat_pct,
##   equipment_stat_pct                    { HP, MP, ATK, DEF, MAG, SPR }, summed, not
##                                         capped
##   element_resist                        { FIRE .. DARK }
##   status_resist                         { POISON .. PETRIFY }
##   debuff_resist                         { ATK, DEF, MAG, SPR, STOP, CHARM }
##   killers                               { "physical:<race>" / "magic:<race>": pct },
##                                         summed, not capped (the engine's KILLER keys)
##   killer_cap_bonus                      { "<race>": pct } (op 105)
##   lb_damage_pct                         summed LB damage percent
##   skill_boosts                          [{ skill_ids: [String], opcodes: [int],
##                                         damage_type (0, 1 physical, 2 magic, 3 both),
##                                         pct }]
##   chain_cap_raise                       summed raise of the chain cap (98, 81, 106);
##                                         BattleRules caps the cap itself
##   chain_boost_pct                       summed chain modifier boost (84 / 85)
##   lb_fill_rate_pct (31), mp_regen_pct (32, percent of max MP per turn), lb_per_turn
##   (33, hundredths of a crystal), evade_physical_pct (22), evade_magic_pct (54),
##   aggro_pct (24 minus 25), ability_mp_cut_pct (77), evo_mag_pct (21),
##   evoke_damage_pct (64 naming no esper), jump_damage_pct (17)   summed, not capped
##   lb_change_id                          op 72's limit burst, "" for none
##   attack_replace_id                     op 100's ability for the normal attack, ""
##                                         for none
##   covers                                [{ physical, magic, chance, mit_min, mit_max,
##                                         condition, hp_below_pct }], one per passive
##                                         cover (8, 59), as CombatantPassives.covers
##   multicast_commands                    [ability id] the passives put in the skill
##                                         list (52, 53), each once, in passive order
##   multicast_picks                       { ability id: { count, skill_ids: [String] } }
##                                         what those passives let each command pick (two
##                                         naming one command: the larger count, both
##                                         lists)
##   counters                              [{ trigger (physical, magic), chance, modifier,
##                                         max, skill_kind, skill_id, source_skill_id }],
##                                         one per counter effect (12, 41, 49, 50), as
##                                         CombatantPassives.counters
##   counter_chance_pct                    summed op 20 boost of every counter chance
##   auto_casts                            [{ skill_kind, skill_id, battle_start, revive,
##                                         turn_start, chance, source_skill_id }], one per
##                                         cast effect (103, 35, 56, 66)
##   unconsumed                            [{ type, opcode, effect, skill_id, source }]
## A handled effect whose condition fails adds nothing but is not unconsumed.
static func aggregate(sources: Array, loadout: Dictionary, esper: Dictionary) -> Dictionary:
	var totals: Dictionary = empty_totals()
	for source in sources:
		var chain_boost: int = 0
		for effect in source.get("effects", []):
			var effect_type: String = str(effect.get("type", ""))
			if not SPECS.has(effect_type):
				totals["unconsumed"].append({
					"type": effect_type,
					"opcode": effect.get("opcode", 0),
					"effect": effect.get("effect", {}),
					"skill_id": str(source.get("skill_id", "")),
					"source": str(source.get("source", "")),
				})
				continue
			var spec: Dictionary = SPECS[effect_type]
			var payload: Dictionary = effect.get("effect", {})
			if not _condition_holds(spec, payload, loadout, esper):
				continue
			if str(spec.get("handler", "")) == HANDLER_CHAIN_BOOST:
				chain_boost = maxi(chain_boost, _number(payload.get("pct")))
				continue
			if spec.has("handler"):
				_apply_handler(spec, payload, totals, str(source.get("skill_id", "")))
				continue
			var pool: Dictionary = totals[spec["pool"]]
			for key in payload.keys():
				var pool_key: String = pool_key_for(key)
				if pool.has(pool_key) and str(key) != str(spec.get("key", "")):
					pool[pool_key] += _number(payload[key])
		totals["chain_boost_pct"] += chain_boost
	return totals


## The totals that go into battle: StatCalculator copies them to profile["passives"]
## for CombatantPassives.from_profile. The other totals are settled in the profile.
const BATTLE_KEYS: PackedStringArray = [
	"killers", "killer_cap_bonus", "lb_damage_pct", "skill_boosts", "chain_cap_raise", "chain_boost_pct",
	"lb_fill_rate_pct", "mp_regen_pct", "lb_per_turn", "evade_physical_pct", "evade_magic_pct", "aggro_pct",
	"ability_mp_cut_pct", "evo_mag_pct", "evoke_damage_pct", "jump_damage_pct", "lb_change_id", "attack_replace_id", "covers",
	"multicast_commands", "multicast_picks", "counters", "counter_chance_pct", "auto_casts", "unconsumed",
]


## Every pool zeroed and no modifiers or unconsumed effects.
static func empty_totals() -> Dictionary:
	return {
		POOL_STAT_PCT: _zeroed(STATS),
		POOL_STAT_FLAT: _zeroed(STATS),
		POOL_ESPER_PCT: _zeroed(STATS),
		POOL_ELEMENT: _zeroed(ELEMENTS),
		POOL_STATUS: _zeroed(STATUSES),
		POOL_DEBUFF: _zeroed(DEBUFFS),
		POOL_EQUIPMENT_PCT: _zeroed(STATS),
		"killers": {},
		"killer_cap_bonus": {},
		"lb_damage_pct": 0,
		"skill_boosts": [],
		"chain_cap_raise": 0,
		"chain_boost_pct": 0,
		"lb_fill_rate_pct": 0,
		"mp_regen_pct": 0,
		"lb_per_turn": 0,
		"evade_physical_pct": 0,
		"evade_magic_pct": 0,
		"aggro_pct": 0,
		"ability_mp_cut_pct": 0,
		"evo_mag_pct": 0,
		"evoke_damage_pct": 0,
		"jump_damage_pct": 0,
		"lb_change_id": "",
		"attack_replace_id": "",
		"covers": [],
		"multicast_commands": [],
		"multicast_picks": {},
		"counters": [],
		"counter_chance_pct": 0,
		"auto_casts": [],
		"unconsumed": [],
	}


## True when a handler exists for the type.
static func handles(effect_type: String) -> bool:
	return SPECS.has(effect_type)


## The keys of a handled effect's payload that feed nothing: neither the condition's
## param nor a name its pool or handler reads (op 1's crit_rate, or a key the schema
## renamed). For the coverage report; [] for an unhandled type.
static func ignored_keys(effect_type: String, payload: Dictionary) -> PackedStringArray:
	var ignored := PackedStringArray()
	if not SPECS.has(effect_type):
		return ignored
	var spec: Dictionary = SPECS[effect_type]
	var reads: Array = spec.get("reads", [])
	var pool_keys: PackedStringArray = _pool_keys(str(spec.get("pool", "")))
	for key in payload.keys():
		var name: String = str(key)
		if name == str(spec.get("key", "")):
			continue
		if spec.has("handler") and not reads.has(name):
			ignored.append(name)
		elif not spec.has("handler") and not pool_keys.has(pool_key_for(key)):
			ignored.append(name)
	return ignored


## A param name as a pool key: "atk" -> "ATK", "paralysis" -> "PARALYSIS",
## "atk_break" -> "ATK".
static func pool_key_for(param_name: Variant) -> String:
	var upper: String = str(param_name).strip_edges().to_upper()
	return str(_KEY_ALIASES.get(upper, upper))


## `passive_id` is the passive the effect belongs to.
static func _apply_handler(spec: Dictionary, payload: Dictionary, totals: Dictionary, passive_id: String = "") -> void:
	match str(spec["handler"]):
		HANDLER_COUNTER:
			# Zeros are dropped from payloads: a missing modifier is the plain attack, a
			# missing cap is no cap.
			var cast_kind: String = "attack"
			var cast_id: int = 0
			if bool(spec.get("cast", false)):
				cast_kind = str(COUNTER_CAST_KINDS.get(_number(payload.get("cast_type")), ""))
				cast_id = _number(payload.get("skill_id"))
				if cast_kind == "" or (cast_kind != "attack" and cast_id <= 0):
					return
			totals["counters"].append({
				"trigger": str(spec["trigger"]),
				"chance": _number(payload.get("chance_pct")),
				"modifier": _number(payload.get("modifier")),
				"max": _number(payload.get("max")),
				"skill_kind": cast_kind,
				"skill_id": str(cast_id) if cast_kind != "attack" else "",
				"source_skill_id": passive_id,
			})
		HANDLER_AUTO_CAST:
			var cast_id: int = _number(payload.get(str(spec["param"])))
			if cast_id <= 0:
				return
			totals["auto_casts"].append({
				"skill_kind": str(spec["kind"]),
				"skill_id": str(cast_id),
				"battle_start": bool(spec.get("battle_start", false)),
				"revive": bool(spec.get("revive", false)),
				"turn_start": bool(spec.get("turn_start", false)),
				"chance": _number(payload.get(str(spec["chance"]))) if spec.has("chance") else 100,
				"source_skill_id": passive_id,
			})
		HANDLER_CHAIN_CAP:
			totals["chain_cap_raise"] += int(spec["fixed_pct"]) if spec.has("fixed_pct") else _number(payload.get("pct"))
		HANDLER_EQUIPMENT_STAT:
			var stat: String = str(spec.get("stat", ""))
			if spec.has("stat_key"):
				stat = str(_STAT_IDS.get(_number(payload.get(str(spec["stat_key"]))), ""))
			if stat != "":
				totals[POOL_EQUIPMENT_PCT][stat] += _number(payload.get("pct"))
		HANDLER_KILLER:
			var races: Array[int] = _ids(payload.get("race_id"))
			for i in range(races.size()):
				_bump(totals["killers"], "physical:%d" % races[i], _nth(payload.get("phys_pct"), i))
				_bump(totals["killers"], "magic:%d" % races[i], _nth(payload.get("mag_pct"), i))
		HANDLER_KILLER_LIMIT:
			var pct: int = _number(payload.get("pct"))
			for race in _ids(payload.get("race_id")):
				_bump(totals["killer_cap_bonus"], str(race), pct)
				_bump(totals["killers"], "physical:%d" % race, pct)
				_bump(totals["killers"], "magic:%d" % race, pct)
		HANDLER_TOTAL:
			totals[str(spec["total"])] += _number(payload.get(str(spec["param"]))) * int(spec.get("sign", 1))
		HANDLER_LB_CHANGE:
			var lb_id: int = _number(payload.get("lb_id"))
			if lb_id > 0:
				totals["lb_change_id"] = str(lb_id)
		HANDLER_ATTACK_REPLACE:
			var skill_id: int = _number(payload.get("skill_id"))
			if skill_id > 0:
				totals["attack_replace_id"] = str(skill_id)
		HANDLER_MULTICAST_COMMAND:
			var command_id: int = _number(payload.get(str(spec["param"])))
			if command_id <= 0:
				return
			var key: String = str(command_id)
			if not totals["multicast_commands"].has(key):
				totals["multicast_commands"].append(key)
			var picks: Dictionary = totals["multicast_picks"].get_or_add(key, {"count": 0, "skill_ids": []})
			picks["count"] = maxi(int(picks["count"]), _number(payload.get(str(spec["count"]))))
			if spec.has("list"):
				for skill_id in _ids(payload.get(str(spec["list"]))):
					if skill_id > 0 and not (picks["skill_ids"] as Array).has(str(skill_id)):
						(picks["skill_ids"] as Array).append(str(skill_id))
		HANDLER_COVER:
			# Zeros are dropped from payloads: a missing gate means none, a missing chance
			# (Valorous Defense's four params) never covers.
			var gate: int = _number(payload.get("hp_below_pct"))
			totals["covers"].append({
				"physical": bool(spec.get("physical", false)),
				"magic": bool(spec.get("magic", false)),
				"chance": _number(payload.get("chance_pct")),
				"mit_min": _number(payload.get("dmg_reduce_min")),
				"mit_max": _number(payload.get("dmg_reduce_max")),
				"condition": _number(payload.get("condition")),
				"hp_below_pct": gate if gate > 0 else 100,
			})
		HANDLER_SKILL_BOOST:
			var pct: int = _number(payload.get("pct"))
			if pct == 0:
				return
			var skill_ids: Array[String] = []
			for skill_id in _ids(payload.get("skill_ids")):
				if skill_id > 0:
					skill_ids.append(str(skill_id))
			totals["skill_boosts"].append({
				"skill_ids": skill_ids,
				"opcodes": _ids(payload.get("opcode_filter")),
				"damage_type": _number(payload.get("damage_type")),
				"pct": pct,
			})


static func _condition_holds(spec: Dictionary, payload: Dictionary, loadout: Dictionary, esper: Dictionary) -> bool:
	var ids: Array[int] = _ids(payload.get(str(spec.get("key", "")), null))
	match str(spec.get("when", "")):
		"":
			return true
		WHEN_CATEGORY:
			return _any_in(ids, loadout.get("categories", []))
		WHEN_CATEGORY_IF_SET:
			return ids.is_empty() or _any_in(ids, loadout.get("categories", []))
		WHEN_ITEM:
			return _any_in(ids, loadout.get("item_ids", []))
		WHEN_WEAPON_ELEMENT:
			for hand in loadout.get("hands", []):
				if str(hand.get("kind", "")) == PassiveSources.HAND_WEAPON and _any_in(ids, hand.get("elements", [])):
					return true
			return false
		WHEN_ESPER:
			if esper.is_empty():
				return false
			return ids.is_empty() or ids.has(int(esper.get("summon_id", 0)))
		WHEN_SINGLE_WIELD:
			var mode: int = ids[0] if not ids.is_empty() else 0
			return bool(loadout.get("single_weapon", false)) if mode != 0 else bool(loadout.get("single_one_handed", false))
		WHEN_DUAL_WIELD:
			return bool(loadout.get("dual_wielding", false))
		WHEN_SINGLE_WEAPON_OF:
			if not bool(loadout.get("single_weapon", false)):
				return false
			if ids.is_empty():
				return true
			for hand in loadout.get("hands", []):
				if str(hand.get("kind", "")) == PassiveSources.HAND_WEAPON and ids.has(int(hand.get("category", 0))):
					return true
			return false
		WHEN_UNARMED:
			return bool(loadout.get("unarmed", false))
		WHEN_NO_ESPER_NAMED:
			return ids.all(func(id: int) -> bool: return id == 0)
	return false


## A param as ids: an int, or a list of them ("3&4" decodes to [3, 4]).
static func _ids(value: Variant) -> Array[int]:
	var ids: Array[int] = []
	if value is Array:
		for item in value:
			if item is int or item is float:
				ids.append(int(item))
	elif value is int or value is float:
		ids.append(int(value))
	return ids


## The i-th value of a list param, or the param itself when it is a single number.
static func _nth(value: Variant, i: int) -> int:
	if value is Array:
		return _number((value as Array)[i]) if i < (value as Array).size() else 0
	return _number(value)


static func _bump(table: Dictionary, key: String, amount: int) -> void:
	if amount != 0:
		table[key] = int(table.get(key, 0)) + amount


static func _any_in(ids: Array[int], haystack: Array) -> bool:
	for id in ids:
		if haystack.has(id):
			return true
	return false


## A percent or amount; 0 for anything that is not a number.
static func _number(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	return 0


static func _zeroed(keys: PackedStringArray) -> Dictionary:
	var table: Dictionary = {}
	for key in keys:
		table[key] = 0
	return table


static func _pool_keys(pool: String) -> PackedStringArray:
	match pool:
		POOL_ELEMENT:
			return ELEMENTS
		POOL_STATUS:
			return STATUSES
		POOL_DEBUFF:
			return DEBUFFS
	return STATS

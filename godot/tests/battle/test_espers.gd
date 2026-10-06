extends "res://tests/test_case.gd"

## Espers: the party's shared esper gauge (orbs from party hits, skills that fill it),
## evoking a unit's esper only while the gauge is full, evoke damage (the wiki's formula,
## for opcode 124 and the espers' own attacks), orb costs, and esper skills, the builder
## and the sandbox against the real database. Writes no save.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

const ESPER_SKILL: String = "90101"
const SIREN: int = 1
const IFRIT: int = 2
const GARUDA: int = 20  # one rank only


func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()


## A catalog holding a fixture esper skill: magic damage (opcode 15) to all enemies on
## frame 10, with attack type none like every esper skill in the data.
static func _catalog() -> SkillCatalog:
	var catalog: SkillCatalog = Fixtures.catalog()
	catalog.add_record(BattleSkill.KIND_ESPER, ESPER_SKILL, Fixtures.record("Test Esper",
		[[SkillEffect.AREA_ALL, SkillEffect.TARGET_OPPONENT, 15, Fixtures.magic_params(100)]],
		"10:100", {"attack_type": BattleSkill.ATTACK_NONE}))
	return catalog


static func _summoner(unit_name: String = "Summoner") -> Combatant:
	return Fixtures.unit(unit_name, {"esper_id": SIREN, "esper_skill_id": ESPER_SKILL})


static func _foe(spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"brain": IdleEnemyBrain.new()}
	full.merge(spec, true)
	return Fixtures.monster("Foe", full)


static func _battle(party: Array, rules: BattleRules = null, catalog: SkillCatalog = null) -> BattleEngine:
	var battle: BattleEngine = Fixtures.engine(party, [_foe()], rules, catalog if catalog != null else _catalog())
	battle.start()
	return battle


# === Evoking ===

func test_evoking_needs_an_esper() -> void:
	var plain: Combatant = Fixtures.unit("Plain")
	var battle: BattleEngine = _battle([plain])
	battle.esper_orbs = battle.rules.esper_gauge_max
	assert_eq(battle.can_execute(plain.id, BattleCommand.evoke()), BattleEngine.REJECT_NO_ESPER)
	assert_eq(battle.execute(plain.id, BattleCommand.evoke()), BattleEngine.REJECT_NO_ESPER)
	assert_eq(battle.esper_orbs, battle.rules.esper_gauge_max, "nothing spent")


func test_evoking_needs_a_full_gauge_and_empties_it() -> void:
	var summoner: Combatant = _summoner()
	var battle: BattleEngine = _battle([summoner])
	var foe: Combatant = battle.enemies[0]
	battle.esper_orbs = battle.rules.esper_gauge_max - 1
	assert_false(battle.esper_gauge_full())
	assert_eq(battle.can_execute(summoner.id, BattleCommand.evoke()), BattleEngine.REJECT_ESPER_GAUGE_NOT_FULL)
	battle.esper_orbs = battle.rules.esper_gauge_max
	assert_true(battle.esper_gauge_full())
	assert_eq(battle.execute(summoner.id, BattleCommand.evoke()), BattleEngine.OK)
	assert_eq(battle.esper_orbs, 0)

	var started: Dictionary = battle.events.last_of_type(BattleEventLog.ACTION_STARTED)
	assert_eq(int(started["kind"]), BattleCommand.Kind.EVOKE)
	assert_eq(started["skill_kind"], BattleSkill.KIND_ESPER)
	assert_eq(started["skill_id"], ESPER_SKILL)
	assert_eq(int(started["esper_id"]), SIREN, "for the 'evoke <esper>' challenges")
	var paid: Dictionary = battle.events.last_of_type(BattleEventLog.COST_PAID)
	assert_eq(int(paid["orb_cost"]), battle.rules.esper_gauge_max)
	assert_eq(int(paid["orbs"]), 0)
	assert_eq(int(paid["mp_cost"]), 0)
	assert_true(battle.format_event(started).contains("Test Esper"), battle.format_event(started))
	assert_eq(battle.can_execute(summoner.id, BattleCommand.evoke()), BattleEngine.REJECT_ALREADY_ACTED, "it was the unit's action")

	battle.advance(10)
	var landed: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(landed.size(), 1, "the esper's skill runs")
	assert_eq(int(landed[0]["attack_type"]), BattleSkill.ATTACK_NONE)
	assert_eq(battle.turn, 2)
	assert_eq(battle.can_execute(summoner.id, BattleCommand.evoke()), BattleEngine.REJECT_ESPER_GAUGE_NOT_FULL, "next turn, the gauge is still empty")


func test_the_party_shares_one_gauge() -> void:
	var first: Combatant = _summoner("First")
	var second: Combatant = _summoner("Second")
	var battle: BattleEngine = _battle([first, second])
	battle.esper_orbs = battle.rules.esper_gauge_max
	assert_eq(battle.can_execute(second.id, BattleCommand.evoke()), BattleEngine.OK)
	assert_eq(battle.execute(first.id, BattleCommand.evoke()), BattleEngine.OK)
	assert_eq(battle.execute(second.id, BattleCommand.evoke()), BattleEngine.REJECT_ESPER_GAUGE_NOT_FULL, "the first evocation emptied it")


func test_a_confused_summoner_attacks_instead_and_keeps_the_orbs() -> void:
	var summoner: Combatant = _summoner()
	var battle: BattleEngine = _battle([summoner])
	battle.esper_orbs = battle.rules.esper_gauge_max
	battle.debug_edit(summoner.id, &"ailment", 3, "CONFUSION")
	assert_eq(battle.execute(summoner.id, BattleCommand.evoke()), BattleEngine.OK)
	var started: Dictionary = battle.events.last_of_type(BattleEventLog.ACTION_STARTED)
	assert_eq(started["forced_by"], "CONFUSION")
	assert_eq(int(started["esper_id"]), 0)
	assert_eq(battle.esper_orbs, battle.rules.esper_gauge_max)


func test_esper_attacks_use_the_evoke_formula_at_50_50() -> void:
	var catalog: SkillCatalog = _catalog()
	catalog.add_record(BattleSkill.KIND_ESPER, "90201", Fixtures.record("Hellfire",
		[[SkillEffect.AREA_ALL, SkillEffect.TARGET_OPPONENT, 79, [0, 0, 0, 0, 0, 0, 1, 7000]]], "110:100",
		{"attack_type": BattleSkill.ATTACK_NONE}))
	var spec: Dictionary = {"esper_id": IFRIT, "esper_skill_id": "90201", "mag": 200, "spr": 100}
	var battle: BattleEngine = _battle([Fixtures.unit("Summoner", spec)], null, catalog)
	battle.esper_orbs = battle.rules.esper_gauge_max
	assert_eq(battle.execute(battle.party_members()[0].id, BattleCommand.evoke()), BattleEngine.OK)
	battle.advance(110)
	assert_eq(battle.events.count_of_type(BattleEventLog.EFFECT_UNSUPPORTED), 0)
	# (200^2 x 0.5 + 100^2 x 0.5) / 100 SPR x 7000%
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, battle.enemies[0].id)), [17500])

	var mag_only: BattleRules = Fixtures.rules()
	mag_only.esper_attack_mag_ratio_pct = 100
	battle = _battle([Fixtures.unit("Summoner", spec)], mag_only, catalog)
	battle.esper_orbs = battle.rules.esper_gauge_max
	battle.execute(battle.party_members()[0].id, BattleCommand.evoke())
	battle.advance(110)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, battle.enemies[0].id)), [28000], "the ratio is a rule")


# === Evoke damage ===

## Adds an ability dealing evoke damage (opcode 124) to one enemy on frame 10: the MAG
## and SPR modifiers and the [MAG, SPR] ratio as the data has them.
static func _add_evoke_ability(catalog: SkillCatalog, id: String, mag_modifier: int, spr_modifier: int, ratio: Array, extra: Dictionary = {}) -> void:
	var data: Dictionary = {"attack_type": BattleSkill.ATTACK_NONE}
	data.merge(extra, true)
	catalog.add_record(BattleSkill.KIND_ABILITY, id, Fixtures.record("Evoke " + id,
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_OPPONENT, 124, [0, 0, 0, 0, 0, 0, 0, mag_modifier, spr_modifier, ratio]]],
		"10:100", data))


## An evoker with MAG 200 and SPR 100: 250 against SPR 100 at 50:50 and 100%.
static func _evoker(unit_name: String, passives: Dictionary = {}) -> Combatant:
	return Fixtures.unit(unit_name, {"mag": 200, "spr": 100, "passives": passives})


## Each evoker uses `ability_ids[i]` on `foes[i]` on the same frame; returns the damage
## each foe took.
static func _evoke_each(catalog: SkillCatalog, ability_ids: Array, foes: Array) -> Array[int]:
	var evokers: Array = []
	for i in range(ability_ids.size()):
		evokers.append(_evoker("Evoker %d" % i))
	var battle: BattleEngine = Fixtures.engine(evokers, foes, null, catalog)
	battle.start()
	for i in range(ability_ids.size()):
		battle.execute(evokers[i].id, BattleCommand.skill(BattleSkill.KIND_ABILITY, ability_ids[i], foes[i].id))
	battle.advance(10)
	var out: Array[int] = []
	for foe in foes:
		var landed: Array[int] = Fixtures.amounts(Fixtures.hits(battle, foe.id))
		out.append(landed[0] if not landed.is_empty() else -1)
	return out


static func _evoke_roll(attacker: Combatant, target: Combatant, rules: BattleRules = null, elements: PackedInt32Array = PackedInt32Array()) -> DamageFormula.Roll:
	var req: DamageFormula.Request = DamageFormula.request(attacker, target, DamageFormula.Kind.EVOKE, 1.0, elements)
	return DamageFormula.compute(req, rules if rules != null else Fixtures.rules(), RandomNumberGenerator.new())


func test_evoke_damage_weighs_mag_and_spr_by_the_ratio() -> void:
	var catalog: SkillCatalog = Fixtures.catalog()
	_add_evoke_ability(catalog, "even", 100, 100, [50, 50])
	_add_evoke_ability(catalog, "mag", 300, 0, [100, 0])
	_add_evoke_ability(catalog, "spr", 0, 200, [0, 100])
	_add_evoke_ability(catalog, "tilted", 100, 100, [60, 40])
	# 200^2 and 100^2 over SPR 100: 400 x 0.5 + 100 x 0.5, 400 x 3, 100 x 2, 400 x 0.6 + 100 x 0.4
	assert_eq(_evoke_each(catalog, ["even", "mag", "spr", "tilted"], [_foe(), _foe(), _foe(), _foe()]), [250, 1200, 200, 280])


func test_evoke_damage_is_a_fixed_attack_with_general_mitigation_only() -> void:
	var catalog: SkillCatalog = Fixtures.catalog()
	_add_evoke_ability(catalog, "even", 100, 100, [50, 50])
	var shielded: Combatant = _foe({"magic_resist": 50, "physical_resist": 50, "passives": {"evade_magic_pct": 100, "evade_physical_pct": 100}})
	shielded.add_status(BattleStatus.make(BattleStatus.MITIGATION, "magic", 50, 3))
	shielded.add_status(BattleStatus.make(BattleStatus.DODGE, "", 5, 3))
	var guarded: Combatant = _foe()
	guarded.add_status(BattleStatus.make(BattleStatus.MITIGATION, "all", 50, 3))
	assert_eq(_evoke_each(catalog, ["even", "even"], [shielded, guarded]), [250, 125],
		"magic mitigation, innate cuts, evasion and dodge do not apply; general mitigation does")


func test_evoke_damage_takes_evo_mag_and_the_evoke_boost_up_to_their_caps() -> void:
	var foe: Combatant = _foe()
	assert_almost_eq(_evoke_roll(_evoker("Plain"), foe).amount, 250.0, 0.001)
	assert_almost_eq(_evoke_roll(_evoker("EVO", {"evo_mag_pct": 100}), foe).amount, 500.0, 0.001, "EVO MAG +100% doubles it")
	assert_almost_eq(_evoke_roll(_evoker("Both", {"evo_mag_pct": 100, "evoke_damage_pct": 50}), foe).amount, 750.0, 0.001,
		"the boost is a separate multiplier")
	var capped: DamageFormula.Roll = _evoke_roll(_evoker("Capped", {"evo_mag_pct": 500, "evoke_damage_pct": 900}), foe)
	assert_almost_eq(capped.evo_multiplier, 4.0, 0.001, "EVO MAG caps at 300%")
	assert_almost_eq(capped.boost_multiplier, 4.0, 0.001, "the boost caps at 4x")


func test_evoke_damage_ignores_killers_and_skill_boosts_but_not_elements_or_level() -> void:
	var boosted: Combatant = _evoker("Boosted", {
		"killers": {"physical:7": 100, "magic:7": 100},
		"skill_boosts": [{"damage_type": 3, "pct": 100}],
		"lb_damage_pct": 100,
	})
	boosted.add_status(BattleStatus.make(BattleStatus.KILLER, "magic:7", 100, 3))
	var bird: Combatant = _foe({"races": [7], "element_resist": {"FIRE": 50}})
	assert_almost_eq(_evoke_roll(boosted, bird).amount, 250.0, 0.001)
	assert_almost_eq(_evoke_roll(boosted, bird, null, PackedInt32Array([1])).amount, 125.0, 0.001, "fire against 50% fire resistance")
	var leveled: BattleRules = Fixtures.rules()
	leveled.level_correction = true
	boosted.level = 50
	assert_almost_eq(_evoke_roll(boosted, bird, leveled).amount, 375.0, 0.001)


func test_skills_that_consume_the_gauge_need_their_orbs_and_their_mp() -> void:
	var catalog: SkillCatalog = Fixtures.catalog()
	_add_evoke_ability(catalog, "costly", 100, 100, [50, 50], {"cost": {"MP": 10}, "alternate_cost": {"type": 1, "amount": 2}})
	var evoker: Combatant = _evoker("Evoker")
	var battle: BattleEngine = Fixtures.engine([evoker], [_foe()], null, catalog)
	battle.start()
	var command: BattleCommand = BattleCommand.skill(BattleSkill.KIND_ABILITY, "costly")
	assert_eq(catalog.get_skill(BattleSkill.KIND_ABILITY, "costly").orb_cost, 2)
	battle.esper_orbs = 1
	assert_eq(battle.can_execute(evoker.id, command), BattleEngine.REJECT_NOT_ENOUGH_ORBS)
	battle.esper_orbs = 3
	evoker.mp = 5
	assert_eq(battle.can_execute(evoker.id, command), BattleEngine.REJECT_NOT_ENOUGH_MP)
	evoker.mp = 100
	assert_eq(battle.execute(evoker.id, command), BattleEngine.OK)
	assert_eq([evoker.mp, battle.esper_orbs], [90, 1], "both are paid")
	var paid: Dictionary = battle.events.last_of_type(BattleEventLog.COST_PAID)
	assert_eq([int(paid["mp_cost"]), int(paid["orb_cost"]), int(paid["orbs"])], [10, 2, 1])


# === Filling the gauge ===

func test_damaging_party_hits_on_enemies_drop_orbs() -> void:
	var rules: BattleRules = Fixtures.rules()
	rules.esper_orb_drop_chance = 1.0
	rules.esper_gauge_max = 2
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:34-8:33-12:33"})
	var battle: BattleEngine = _battle([hero], rules)
	var foe: Combatant = battle.enemies[0]
	battle.execute(hero.id)
	battle.advance(12)
	var drops: Array[Dictionary] = battle.events.of_type(BattleEventLog.ESPER_ORB_DROPPED)
	assert_eq(drops.size(), 3, "one roll per damaging hit")
	assert_eq(int(drops[0]["source"]), foe.id)
	assert_eq(int(drops[0]["actor"]), hero.id)
	assert_eq(drops.map(func(event: Dictionary) -> int: return int(event["amount"])), [1, 1, 0], "the third finds the gauge full")
	assert_eq(battle.esper_orbs, 2)
	assert_true(battle.format_event(drops[0]).contains("gauge 1/2"), battle.format_event(drops[0]))


func test_enemy_hits_and_harmless_hits_drop_no_orbs() -> void:
	var rules: BattleRules = Fixtures.rules()
	rules.esper_orb_drop_chance = 1.0
	var weakling: Combatant = Fixtures.unit("Weakling", {"atk": 0, "hp": 100000})
	var foe: Combatant = Fixtures.monster("Foe", {"atk": 100})
	var battle: BattleEngine = Fixtures.engine([weakling], [foe], rules, _catalog())
	battle.start()
	battle.execute(weakling.id)
	assert_true(Fixtures.run_until(battle, func() -> bool: return not Fixtures.hits(battle, weakling.id).is_empty()), "the foe hits back")
	assert_eq(int(Fixtures.hits(battle, foe.id)[0]["amount"]), 0, "the weakling's hit does no damage")
	assert_eq(battle.events.count_of_type(BattleEventLog.ESPER_ORB_DROPPED), 0)
	assert_eq(battle.esper_orbs, 0)


func test_the_default_rules_drop_an_orb_one_hit_in_ten() -> void:
	var rules := BattleRules.new()
	assert_eq(rules.esper_gauge_max, 10)
	assert_almost_eq(rules.esper_orb_drop_chance, 0.1, 0.0001)


func test_fill_evocation_gauge_fills_the_party_gauge_once() -> void:
	var catalog: SkillCatalog = _catalog()
	catalog.add_record(BattleSkill.KIND_ABILITY, "fill", Fixtures.record("Shared Power",
		[[SkillEffect.AREA_ALL, SkillEffect.TARGET_ALLY, 32, [2, 2]]], "5:100"))
	catalog.add_record(BattleSkill.KIND_ABILITY, "roll", Fixtures.record("Prayer",
		[[SkillEffect.AREA_SELF, SkillEffect.TARGET_SELF, 32, [1, 3]]], "5:100"))
	var singer: Combatant = Fixtures.unit("Singer")
	var other: Combatant = Fixtures.unit("Other")
	var battle: BattleEngine = Fixtures.engine([singer, other], [_foe()], null, catalog)
	battle.start()
	battle.execute(singer.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "fill"))
	battle.advance(5)
	assert_eq(battle.esper_orbs, 2, "once for the party, not once per ally")
	var changed: Dictionary = battle.events.last_of_type(BattleEventLog.ESPER_GAUGE_CHANGED)
	assert_eq(int(changed["amount"]), 2)
	assert_eq(changed["reason"], &"fill")
	assert_eq(int(changed["actor"]), singer.id)
	battle.execute(other.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "roll"))
	battle.advance(5)
	assert_true(battle.esper_orbs >= 3 and battle.esper_orbs <= 5, "2 plus 1 to 3: %d" % battle.esper_orbs)


func test_the_gauge_carries_into_the_next_wave() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"atk": 1000, "attack_frames": "4:100"})
	var battle: BattleEngine = Fixtures.engine([hero], [_foe({"hp": 100})], null, _catalog())
	var next: Array[Combatant] = [_foe({"hp": 100})]
	battle.queue_wave(func() -> Array[Combatant]: return next)
	battle.start()
	battle.esper_orbs = 7
	battle.execute(hero.id)
	assert_true(Fixtures.run_until_phase(battle, BattleEngine.Phase.WAVE_CLEARED), "wave 1 cleared")
	assert_eq(battle.begin_next_wave(), BattleEngine.OK)
	assert_eq(battle.esper_orbs, 7)


func test_debug_edit_sets_the_party_gauge() -> void:
	var summoner: Combatant = _summoner()
	var battle: BattleEngine = _battle([summoner])
	assert_eq(battle.debug_edit(summoner.id, &"orbs", 99), BattleEngine.OK)
	assert_eq(battle.esper_orbs, battle.rules.esper_gauge_max, "clamped to the gauge")
	var edited: Dictionary = battle.events.last_of_type(BattleEventLog.DEBUG_EDITED)
	assert_eq(int(edited["old"]), 0)
	assert_eq(int(edited["value"]), battle.rules.esper_gauge_max)
	assert_eq(battle.can_execute(summoner.id, BattleCommand.evoke()), BattleEngine.OK)


# === Real data ===

func test_the_database_catalog_builds_esper_skills() -> void:
	var siren: BattleSkill = DatabaseSkillCatalog.new().get_skill(BattleSkill.KIND_ESPER, "10101")
	assert_not_null(siren)
	assert_eq(siren.name, "Lunatic Voice")
	assert_eq(siren.kind, BattleSkill.KIND_ESPER)
	assert_eq(siren.attack_type, BattleSkill.ATTACK_NONE)
	assert_eq(Array(siren.elements), [4], "water")
	assert_eq(siren.mp_cost, 0)
	assert_eq(siren.effects.map(func(effect: SkillEffect) -> String: return effect.type), ["ESPER_MAG_DAMAGE", "STATUS_INFLICT"])
	assert_eq(Array(siren.effects[0].hit_frames), [170])
	assert_eq(siren.effects[1].target_area, SkillEffect.AREA_ALL)
	assert_eq(int(siren.record["esper_id"]), SIREN)
	assert_eq(int(siren.record["rank"]), 1)
	assert_null(DatabaseSkillCatalog.new().get_skill(BattleSkill.KIND_ESPER, "99999"))


func test_the_database_reads_evoke_damage_and_orb_costs() -> void:
	var catalog := DatabaseSkillCatalog.new()
	var kick: BattleSkill = catalog.get_skill(BattleSkill.KIND_ABILITY, "223400")
	assert_eq(kick.name, "Eidolon Chocobo Kick")
	assert_eq(kick.orb_cost, 1, "alternateCost 1:1")
	assert_eq(kick.mp_cost, 0)
	assert_eq(kick.attack_type, BattleSkill.ATTACK_NONE)
	var effect: SkillEffect = kick.effects[0]
	assert_eq(effect.type, "EVOKE_DAMAGE")
	assert_eq([effect.params.get("modifier"), effect.params.get("modifier_2"), effect.params.get("stat_ratio")], [500, 500, [50, 50]])
	var tackle: BattleSkill = catalog.get_skill(BattleSkill.KIND_ABILITY, "230575")
	assert_eq([tackle.mp_cost, tackle.orb_cost], [34, 1], "Vengeful Tackle costs both")
	assert_eq(catalog.get_skill(BattleSkill.KIND_ABILITY, "220230").orb_cost, 0, "2:N is not an orb cost")


func test_the_builder_gives_a_unit_its_esper_at_its_rank() -> void:
	var builder := BattleBuilder.new(Fixtures.rules(), null, 42)
	var member: Combatant = builder.party_member(builder.unit_from_database("100000202"))
	assert_eq(member.esper_skill_id, "", "not in the active party: no esper")
	assert_true(builder.assign_esper(member, IFRIT, 3))
	assert_eq(member.esper_id, IFRIT)
	assert_eq(member.esper_skill_id, "10203")
	assert_false(builder.assign_esper(member, GARUDA, 3), "Garuda has one rank")
	assert_eq(member.esper_skill_id, "", "a failed assignment leaves no esper")
	assert_false(builder.assign_esper(member, 0, 1))


func test_evoking_siren_on_real_data() -> void:
	var builder := BattleBuilder.new(Fixtures.rules(), null, 42)
	var battle: BattleEngine = builder.build({})
	var lasswell: Combatant = battle.party_members()[0]
	assert_true(builder.assign_esper(lasswell, SIREN, 1))
	battle.start()
	# The test battle's giant stats would KO Zu before the sleep half rolls.
	battle.debug_edit(battle.enemies[0].id, &"max_hp", 999999999)
	battle.debug_edit(battle.enemies[0].id, &"hp", 999999999)
	battle.esper_orbs = battle.rules.esper_gauge_max
	assert_eq(battle.execute(lasswell.id, BattleCommand.evoke()), BattleEngine.OK)
	battle.advance(170)
	var started: Dictionary = battle.events.last_of_type(BattleEventLog.ACTION_STARTED)
	assert_eq(started["skill_name"], "Lunatic Voice")
	assert_eq(battle.events.count_of_type(BattleEventLog.EFFECT_UNSUPPORTED), 0)
	var zu: Combatant = battle.enemies[0]
	var landed: Array[Dictionary] = Fixtures.hits(battle, zu.id)
	assert_eq(landed.size(), 1)
	assert_true(int(landed[0]["amount"]) > 0, "Lunatic Voice deals evoke damage")
	assert_eq(int(landed[0]["damage_kind"]), DamageFormula.Kind.EVOKE)
	var sleep_rolls: int = Fixtures.events_on(battle, BattleEventLog.STATUS_ADDED, zu.id).size() \
		+ Fixtures.events_on(battle, BattleEventLog.STATUS_RESISTED, zu.id).size()
	assert_eq(sleep_rolls, 1, "the sleep half runs")


func test_sandbox_slots_take_an_esper_and_offer_its_evocation() -> void:
	var setup: Dictionary = SandboxBattleFactory.test_setup()
	setup["party"][0]["esper"] = IFRIT
	setup["party"][0]["esper_rank"] = 2
	setup["party"][1]["esper"] = GARUDA
	setup["party"][1]["esper_rank"] = 3
	var factory := SandboxBattleFactory.new()
	var battle: BattleEngine = factory.build(setup, 1, Fixtures.rules())
	assert_eq(factory.problems, ["slot 2: esper 20 has no rank 3"])
	var lasswell: Combatant = battle.party[0]
	assert_eq(lasswell.esper_skill_id, "10202")
	assert_eq(battle.party[1].esper_skill_id, "")
	var options: Array[Dictionary] = SandboxBattleFactory.command_options(battle, lasswell)
	assert_true(str(options[3]["label"]).begins_with("Evoke: Hellfire (rank 2"), str(options[3]["label"]))
	assert_eq((options[3]["command"] as BattleCommand).kind, BattleCommand.Kind.EVOKE)
	assert_eq(int(options[3]["unsupported"]), 0, "esper damage runs through the evoke formula")
	var choices: Array[Dictionary] = SandboxBattleFactory.esper_choices()
	assert_eq(choices.size(), 20)
	assert_eq(choices[0], {"id": SIREN, "name": "Siren"})

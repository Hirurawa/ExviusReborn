extends "res://tests/test_case.gd"

## Ailments: what each one does while it lasts (engine/behaviors/), how long it lasts
## on either side, and the opcodes that inflict and cure the newer ones. Enemy recovery
## rolls are off unless a test turns them on, so results do not depend on the seed.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var catalog: SkillCatalog


## Returns the same decision once per turn.
class FixedBrain:
	extends EnemyBrain
	var decision: Dictionary = {}

	func next_action(_ctx: Dictionary) -> Dictionary:
		if _attacks_left <= 0:
			return turn_over("done")
		_attacks_left -= 1
		return decision


func before_each() -> void:
	catalog = Fixtures.catalog()
	catalog.add_record(BattleSkill.KIND_MAGIC, "15", Fixtures.skill_record("Blast", 15, Fixtures.magic_params(100), "10:100"))
	catalog.add_record(BattleSkill.KIND_MONSTER, "700", Fixtures.record("Flare", [[1, 1, 15, Fixtures.magic_params(100)]], "20:100", {"attack_type": BattleSkill.ATTACK_MAGIC}))


func _rules(recovery_pct: int = 0) -> BattleRules:
	var rules: BattleRules = Fixtures.rules()
	rules.enemy_ailment_recovery_pct = recovery_pct
	return rules


func _engine(party: Array, foes: Array, rules: BattleRules = null, seed_value: int = 7) -> BattleEngine:
	return Fixtures.engine(party, foes, rules if rules != null else _rules(), catalog, seed_value)


## An enemy that passes its turns.
func _idle(monster_name: String, spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"brain": IdleEnemyBrain.new()}
	full.merge(spec, true)
	return Fixtures.monster(monster_name, full)


## Inflicts `key` as a skill would, without a roll (the sandbox's debug edit).
func _inflict(battle: BattleEngine, fighter: Combatant, key: String, turns: int = 3) -> void:
	assert_eq(battle.debug_edit(fighter.id, &"ailment", turns, key), BattleEngine.OK, "inflict %s" % key)


func _cast(battle: BattleEngine, actor: Combatant, skill_id: String, target: Combatant) -> StringName:
	return battle.execute(actor.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, skill_id, target.id))


func _status_damage(battle: BattleEngine, target_id: int) -> Array[int]:
	var out: Array[int] = []
	for event in Fixtures.events_on(battle, BattleEventLog.STATUS_DAMAGE, target_id):
		out.append(int(event["amount"]))
	return out


func _removal_reasons(battle: BattleEngine, target_id: int) -> Array:
	var out: Array = []
	for event in Fixtures.events_on(battle, BattleEventLog.STATUS_REMOVED, target_id):
		out.append([event["key"], event["reason"]])
	return out


# --- Poison ---

func test_poison_takes_a_tenth_of_max_hp_at_the_end_of_each_turn() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	_inflict(battle, hero, "POISON")
	_inflict(battle, foe, "POISON")
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(_status_damage(battle, hero.id), [100])
	assert_eq(_status_damage(battle, foe.id), [10000])
	assert_eq(hero.hp, 900)
	assert_eq(foe.hp, 100000 - 100 - 10000)
	assert_true(hero.has_ailment("POISON"), "permanent on the party")
	assert_eq(hero.find_status(BattleStatus.AILMENT, "POISON").turns_left, -1)


func test_poison_can_ko_and_end_the_battle_before_the_next_turn() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	hero.hp = 50
	var battle: BattleEngine = _engine([hero], [_idle("Foe")])
	_inflict(battle, hero, "POISON")
	battle.start()
	battle.execute(hero.id)
	assert_true(Fixtures.run_until_ended(battle))
	assert_eq(battle.outcome, BattleEngine.OUTCOME_DEFEAT)
	assert_eq(battle.turn, 1, "no new turn starts")
	assert_eq(Fixtures.events_on(battle, BattleEventLog.COMBATANT_DEFEATED, hero.id).size(), 1)


# --- Blind ---

func test_blind_makes_physical_and_hybrid_attacks_miss() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "41", Fixtures.record("Hybrid Slash", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", {"attack_type": BattleSkill.ATTACK_HYBRID}))
	var rules: BattleRules = _rules()
	rules.blind_miss_pct = 100
	var knight: Combatant = Fixtures.unit("Knight")
	var mage: Combatant = Fixtures.unit("Mage")
	var lancer: Combatant = Fixtures.unit("Lancer")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([knight, mage, lancer], [foe], rules)
	for member in [knight, mage, lancer]:
		_inflict(battle, member, "BLIND")
	battle.start()
	battle.execute(knight.id, BattleCommand.attack(foe.id))
	battle.execute(mage.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "15", foe.id))
	_cast(battle, lancer, "41", foe)
	battle.advance(12)
	var missed: Array = []
	for event in Fixtures.events_on(battle, BattleEventLog.HIT_MISSED, foe.id):
		missed.append([int(event["actor"]), event["reason"]])
	assert_eq(missed, [[knight.id, &"blinded"], [lancer.id, &"blinded"]])
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [100], "magic still hits")


# --- Sleep and confusion ---

func test_physical_hits_end_sleep_and_confusion_and_magic_does_not() -> void:
	var knights: Array = [Fixtures.unit("Knight 1"), Fixtures.unit("Knight 2")]
	var mages: Array = [Fixtures.unit("Mage 1"), Fixtures.unit("Mage 2")]
	var slept_hit: Combatant = _idle("Slept, hit")
	var slept_spared: Combatant = _idle("Slept, spared")
	var confused_hit: Combatant = _idle("Confused, hit")
	var confused_spared: Combatant = _idle("Confused, spared")
	var battle: BattleEngine = _engine(knights + mages, [slept_hit, slept_spared, confused_hit, confused_spared])
	_inflict(battle, slept_hit, "SLEEP")
	_inflict(battle, slept_spared, "SLEEP")
	_inflict(battle, confused_hit, "CONFUSION")
	_inflict(battle, confused_spared, "CONFUSION")
	battle.start()
	battle.execute(knights[0].id, BattleCommand.attack(slept_hit.id))
	battle.execute(mages[0].id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "15", slept_spared.id))
	battle.execute(knights[1].id, BattleCommand.attack(confused_hit.id))
	battle.execute(mages[1].id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "15", confused_spared.id))
	battle.advance(12)
	assert_false(slept_hit.has_ailment("SLEEP"))
	assert_eq(_removal_reasons(battle, slept_hit.id), [["SLEEP", &"damaged"]])
	assert_true(slept_spared.has_ailment("SLEEP"))
	assert_false(confused_hit.has_ailment("CONFUSION"))
	assert_true(confused_spared.has_ailment("CONFUSION"))


func test_party_sleep_lasts_three_turns() -> void:
	var sleeper: Combatant = Fixtures.unit("Sleeper")
	var awake: Combatant = Fixtures.unit("Awake", {"attack_frames": "4:100"})
	var battle: BattleEngine = _engine([sleeper, awake], [_idle("Foe")])
	_inflict(battle, sleeper, "SLEEP", 1)
	assert_eq(sleeper.find_status(BattleStatus.AILMENT, "SLEEP").turns_left, 3, "the data's turns do not matter")
	battle.start()
	for current in [1, 2, 3]:
		assert_eq(battle.units_to_act(), [awake], "asleep on turn %d" % current)
		battle.execute(awake.id)
		Fixtures.run_until(battle, func() -> bool: return battle.turn == current + 1)
	assert_false(sleeper.has_ailment("SLEEP"))
	assert_eq(battle.units_to_act().size(), 2)


func test_a_confused_unit_attacks_a_random_combatant_whatever_it_was_told() -> void:
	var hit_names: Dictionary = {}
	for seed_value in range(1, 25):
		var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
		var ally: Combatant = Fixtures.unit("Ally")
		var foe: Combatant = _idle("Foe")
		var battle: BattleEngine = _engine([hero, ally], [foe], null, seed_value)
		_inflict(battle, hero, "CONFUSION")
		battle.start()
		var spell: BattleCommand = BattleCommand.skill(BattleSkill.KIND_MAGIC, "15", foe.id)
		assert_eq(battle.execute(hero.id, spell), BattleEngine.OK)
		var started: Dictionary = Fixtures.actions_by(battle, hero.id)[0]
		assert_eq(started["forced_by"], "CONFUSION")
		assert_eq(int(started["origin"]), BattleAction.Origin.FORCED)
		assert_eq(int(started["kind"]), BattleCommand.Kind.ATTACK)
		assert_eq(hero.last_command.skill_id, "15", "repeat still offers what was chosen")
		battle.advance(4)
		for event in Fixtures.hits(battle):
			if int(event["actor"]) == hero.id:
				hit_names[battle.combatant(int(event["target"])).name] = true
	assert_true(hit_names.has("Ally") and hit_names.has("Foe"), "friend and foe: %s" % [hit_names.keys()])
	assert_false(hit_names.has("Hero"), "never itself")


func test_a_confused_enemy_attacks_in_place_of_its_turn() -> void:
	var hit_names: Dictionary = {}
	for seed_value in range(1, 25):
		var hero: Combatant = Fixtures.unit("Hero")
		var confused: Combatant = Fixtures.monster("Confused")
		var other: Combatant = _idle("Other")
		var battle: BattleEngine = _engine([hero], [confused, other], null, seed_value)
		_inflict(battle, confused, "CONFUSION")
		battle.start()
		battle.execute(hero.id, BattleCommand.defend())
		Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
		var actions: Array[Dictionary] = Fixtures.actions_by(battle, confused.id)
		assert_eq(actions.size(), 1)
		assert_eq(actions[0]["forced_by"], "CONFUSION")
		for event in Fixtures.hits(battle):
			if int(event["actor"]) == confused.id:
				hit_names[battle.combatant(int(event["target"])).name] = true
	assert_true(hit_names.has("Hero") and hit_names.has("Other"), "friend and foe: %s" % [hit_names.keys()])


# --- Silence, paralysis, disease ---

func test_a_silenced_monster_uses_a_basic_attack_instead_of_magic() -> void:
	var brain := FixedBrain.new()
	brain.decision = EnemyBrain.action(EnemyBrain.KIND_SKILL, "700")
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = Fixtures.monster("Caster", {"brain": brain})
	var battle: BattleEngine = _engine([hero], [foe])
	_inflict(battle, foe, "SILENCE")
	battle.start()
	battle.execute(hero.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	var actions: Array[Dictionary] = Fixtures.actions_by(battle, foe.id)
	assert_eq(actions.size(), 1)
	assert_eq(int(actions[0]["kind"]), BattleCommand.Kind.ATTACK)


func test_paralysis_disables_and_stops_dodging() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	hero.add_status(BattleStatus.make(BattleStatus.DODGE, "", 2, 3))
	var battle: BattleEngine = _engine([hero], [Fixtures.monster("Foe", {"attack_frames": "10:100"})])
	_inflict(battle, hero, "PARALYSIS")
	battle.start()
	assert_eq(battle.execute(hero.id), BattleEngine.REJECT_CANNOT_ACT)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, hero.id)), [100], "not dodged")
	assert_eq(hero.status_value(BattleStatus.DODGE), 2, "no charge used")


func test_disease_lowers_stats_and_adds_up_with_breaks() -> void:
	var unit: Combatant = Fixtures.unit("Unit", {"atk": 200, "raw_stats": {"ATK": 100}})
	var battle: BattleEngine = _engine([unit], [_idle("Foe")])
	_inflict(battle, unit, "DISEASE")
	assert_eq(unit.find_status(BattleStatus.AILMENT, "DISEASE").value, -10)
	assert_eq(unit.stat("ATK"), 190, "-10% of the raw 100")
	assert_eq(unit.stat("DEF"), 90)
	unit.add_status(BattleStatus.make(BattleStatus.STAT, "ATK", -50, 3))
	assert_eq(unit.stat("ATK"), 140, "-60% of the raw 100")
	assert_eq(unit.max_hp, 1000, "HP is left alone")


# --- Berserk ---

func test_a_berserk_party_member_attacks_on_its_own_with_more_atk() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "68", Fixtures.record("Berserk", [[1, 2, 68, [3, 100]]], "4:100"))
	var caster: Combatant = Fixtures.unit("Caster")
	var brute: Combatant = Fixtures.unit("Brute", {"attack_frames": "10:100"})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([caster, brute], [foe])
	battle.start()
	_cast(battle, caster, "68", brute)
	battle.advance(4)
	var berserk: BattleStatus = brute.find_status(BattleStatus.AILMENT, "BERSERK")
	assert_not_null(berserk)
	assert_eq([berserk.value, berserk.turns_left], [100, 3])
	var actions: Array[Dictionary] = Fixtures.actions_by(battle, brute.id)
	assert_eq(actions.size(), 1, "it attacked as soon as berserk landed")
	assert_eq(actions[0]["forced_by"], "BERSERK")
	assert_eq(battle.execute(brute.id), BattleEngine.REJECT_ALREADY_ACTED)
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [400], "ATK +100%: 200^2 / 100")
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	battle.tick()
	assert_eq(Fixtures.actions_by(battle, brute.id).size(), 2, "and again at the start of the next turn")
	assert_eq(battle.units_to_act(), [caster])


func test_a_berserk_enemy_attacks_the_party_instead_of_following_its_script() -> void:
	var brain := FixedBrain.new()
	brain.decision = EnemyBrain.action(EnemyBrain.KIND_SKILL, "700")
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = Fixtures.monster("Caster", {"brain": brain})
	var battle: BattleEngine = _engine([hero], [foe])
	_inflict(battle, foe, "BERSERK")
	battle.start()
	battle.execute(hero.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	var actions: Array[Dictionary] = Fixtures.actions_by(battle, foe.id)
	assert_eq(actions.size(), 1)
	assert_eq([int(actions[0]["kind"]), actions[0]["forced_by"]], [BattleCommand.Kind.ATTACK, "BERSERK"])
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, hero.id)), [50], "a basic attack on the defending hero")


# --- Petrify ---

func test_petrify_kos_an_enemy_as_a_kill() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "6", Fixtures.record("Stone Gaze", [[1, 1, 6, [0, 0, 0, 0, 0, 0, 0, 100, 1]]], "4:100"))
	var caster: Combatant = Fixtures.unit("Caster")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([caster], [foe])
	battle.start()
	_cast(battle, caster, "6", foe)
	assert_true(Fixtures.run_until_ended(battle))
	assert_eq(battle.outcome, BattleEngine.OUTCOME_VICTORY)
	var defeats: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.COMBATANT_DEFEATED, foe.id)
	assert_eq(defeats.size(), 1)
	assert_eq(int(defeats[0]["by"]), caster.id)


func test_a_petrified_unit_can_be_hit_and_a_petrified_party_loses() -> void:
	var brain := FixedBrain.new()
	brain.decision = EnemyBrain.action(EnemyBrain.KIND_ATTACK, "", "disp_order", 0)
	var stone: Combatant = Fixtures.unit("Stone")
	var other: Combatant = Fixtures.unit("Other")
	var battle: BattleEngine = _engine([stone, other], [Fixtures.monster("Foe", {"brain": brain})])
	_inflict(battle, stone, "PETRIFY")
	battle.start()
	assert_eq(battle.units_to_act(), [other])
	battle.execute(other.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, stone.id)), [100], "enemies can still hurt it")
	_inflict(battle, other, "PETRIFY")
	battle.tick()
	assert_eq(battle.outcome, BattleEngine.OUTCOME_DEFEAT)
	assert_true(stone.is_alive() and other.is_alive(), "nobody is KO'd")
	assert_eq(Fixtures.events_on(battle, BattleEventLog.COMBATANT_DEFEATED, stone.id).size(), 0)


# --- Zombie ---

func test_healing_hurts_a_zombie_and_a_revive_kos_it() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "16", Fixtures.record("Potion", [[1, 2, 16, [200]]], "4:100"))
	catalog.add_record(BattleSkill.KIND_ABILITY, "4", Fixtures.record("Raise", [[1, 2, 4, [50]]], "4:100"))
	var healer: Combatant = Fixtures.unit("Healer")
	var raiser: Combatant = Fixtures.unit("Raiser")
	var zombie: Combatant = Fixtures.unit("Zombie")
	var battle: BattleEngine = _engine([healer, raiser, zombie], [_idle("Foe")])
	_inflict(battle, zombie, "ZOMBIE")
	battle.start()
	_cast(battle, healer, "16", zombie)
	battle.advance(4)
	assert_eq(zombie.hp, 800)
	assert_eq(_status_damage(battle, zombie.id), [200])
	assert_eq(Fixtures.events_on(battle, BattleEventLog.RESTORED, zombie.id).size(), 0)
	_cast(battle, raiser, "4", zombie)
	battle.advance(4)
	assert_false(zombie.is_alive())
	assert_eq(int(Fixtures.events_on(battle, BattleEventLog.COMBATANT_DEFEATED, zombie.id)[0]["by"]), raiser.id)


func test_auto_revive_kos_a_zombie_and_never_brings_one_back() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "27", Fixtures.record("Reraise", [[1, 2, 27, [50, 3, 0]]], "4:100"))
	var cleric: Combatant = Fixtures.unit("Cleric")
	var zombie: Combatant = Fixtures.unit("Zombie")
	var doomed: Combatant = Fixtures.unit("Doomed")
	doomed.add_status(BattleStatus.make(BattleStatus.AUTO_REVIVE, "", 50, 3))
	var battle: BattleEngine = _engine([cleric, zombie, doomed], [_idle("Foe")])
	_inflict(battle, zombie, "ZOMBIE")
	_inflict(battle, doomed, "ZOMBIE")
	battle.start()
	_cast(battle, cleric, "27", zombie)
	battle.advance(4)
	assert_false(zombie.is_alive(), "reraise put on a zombie KOs it")
	battle.debug_edit(doomed.id, &"hp", 0)
	assert_false(doomed.is_alive(), "a zombie's reraise does not bring it back")
	assert_eq(battle.events.count_of_type(BattleEventLog.REVIVED), 0)


func test_zombie_inflict_and_the_extended_cure() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "144", Fixtures.record("Zombie Virus", [[1, 1, 144, [0, 100, 0, 0, 0, 0, 0, 0, 1]]], "4:100"))
	catalog.add_record(BattleSkill.KIND_ABILITY, "148", Fixtures.record("Holy Water", [[1, 2, 148, [[1, 0, 0, 0, 0, 0, 0, 0], 1]]], "4:100"))
	var infector: Combatant = Fixtures.unit("Infector")
	var cleric: Combatant = Fixtures.unit("Cleric")
	var patient: Combatant = Fixtures.unit("Patient")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([infector, cleric, patient], [foe])
	for key in ["ZOMBIE", "POISON", "BLIND"]:
		_inflict(battle, patient, key)
	battle.start()
	_cast(battle, infector, "144", foe)
	_cast(battle, cleric, "148", patient)
	battle.advance(4)
	assert_true(foe.has_ailment("ZOMBIE"))
	assert_false(patient.has_ailment("ZOMBIE"), "the zombie flag")
	assert_false(patient.has_ailment("POISON"), "the poison flag")
	assert_true(patient.has_ailment("BLIND"), "not flagged")


# --- Lasting effects, durations, inflicting ---

func test_charm_disables_for_its_first_slot_in_turns_unless_resisted() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "60", Fixtures.record("Allure", [[2, 1, 60, [2, 100, "MSG"]]], "4:100"))
	var caster: Combatant = Fixtures.unit("Caster")
	var charmed: Combatant = Fixtures.monster("Charmed")
	var immune: Combatant = Fixtures.monster("Immune", {"debuff_resist": {"CHARM": 100}})
	var battle: BattleEngine = _engine([caster], [charmed, immune])
	battle.start()
	_cast(battle, caster, "60", charmed)
	battle.advance(4)
	assert_eq(charmed.find_status(BattleStatus.AILMENT, "CHARM").turns_left, 2)
	assert_eq(Fixtures.events_on(battle, BattleEventLog.STATUS_RESISTED, immune.id).size(), 1)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(Fixtures.actions_by(battle, charmed.id).size(), 0, "charmed: no turn")
	assert_eq(Fixtures.actions_by(battle, immune.id).size(), 1)


func test_enemies_shake_status_ailments_off_at_the_start_of_their_turn() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var sleeper: Combatant = Fixtures.monster("Sleeper")
	var stopped: Combatant = Fixtures.monster("Stopped")
	var battle: BattleEngine = _engine([hero], [sleeper, stopped], _rules(100))
	_inflict(battle, sleeper, "SLEEP")
	_inflict(battle, stopped, "STOP", 3)
	_inflict(battle, hero, "POISON")
	battle.start()
	battle.execute(hero.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(_removal_reasons(battle, sleeper.id), [["SLEEP", &"recovered"]])
	assert_eq(Fixtures.actions_by(battle, sleeper.id).size(), 1, "awake in time to act")
	assert_eq(Fixtures.actions_by(battle, stopped.id).size(), 0)
	assert_eq(stopped.find_status(BattleStatus.AILMENT, "STOP").turns_left, 2, "stop runs out instead")
	assert_true(hero.has_ailment("POISON"), "the party does not roll")


func test_status_ailments_ignore_the_data_turns() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "6", Fixtures.record("Bio", [[1, 1, 6, [100, 0, 0, 0, 0, 0, 0, 0, 1]]], "4:100"))
	var caster: Combatant = Fixtures.unit("Caster")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([caster], [foe])
	battle.start()
	_cast(battle, caster, "6", foe)
	battle.advance(4)
	assert_eq(foe.find_status(BattleStatus.AILMENT, "POISON").turns_left, -1)


func test_random_status_inflict_rolls_amount_of_the_listed_ailments() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "34", Fixtures.record("Pandora", [[1, 1, 34, [100, 100, 100, 0, 0, 0, 0, 0, 1, 2]]], "4:100"))
	var caster: Combatant = Fixtures.unit("Caster")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([caster], [foe])
	battle.start()
	_cast(battle, caster, "34", foe)
	battle.advance(4)
	var landed: Array = []
	for status in foe.statuses_of(BattleStatus.AILMENT):
		landed.append(status.key)
	assert_eq(landed.size(), 2)
	for key in landed:
		assert_has(["POISON", "BLIND", "SLEEP"], key)


func test_debug_edit_inflicts_and_removes_ailments() -> void:
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([Fixtures.unit("Hero")], [foe])
	assert_eq(battle.debug_edit(foe.id, &"ailment", 1, "SILENCE"), BattleEngine.OK)
	assert_true(foe.has_ailment("SILENCE"))
	assert_eq(battle.debug_edit(foe.id, &"ailment", 0, "SILENCE"), BattleEngine.OK)
	assert_false(foe.has_ailment("SILENCE"))
	assert_eq(_removal_reasons(battle, foe.id), [["SILENCE", &"debug"]])
	var edits: Array = []
	for event in battle.events.of_type(BattleEventLog.DEBUG_EDITED):
		edits.append([int(event["old"]), int(event["value"])])
	assert_eq(edits, [[0, 1], [1, 0]])
	assert_eq(battle.debug_edit(foe.id, &"ailment", 1, "DOOM"), BattleEngine.REJECT_UNKNOWN_FIELD)


# --- Resistance down ---

func test_blown_away_resistance_counts_as_zero_and_resist_down_lowers_it() -> void:
	# Pernicious Breath's pattern: 140 and 146 in one skill, then an inflict.
	catalog.add_record(BattleSkill.KIND_ABILITY, "140", Fixtures.record("Breath", [
		[1, 1, 140, [1, 0, 0, 0, 0, 0, 0, 0, 1, 3]],
		[1, 1, 146, [[30, 30, 30, 30, 30, 30, 30, 30], 0, 0, 0, 0, 0, 0, 0, 1, 2]],
		[1, 1, 6, [100, 0, 0, 0, 0, 0, 0, 0, 1]],
	], "4:100"))
	var caster: Combatant = Fixtures.unit("Caster")
	var foe: Combatant = _idle("Foe", {"ailment_resist": {"POISON": 100, "BLIND": 100}})
	foe.add_status(BattleStatus.make(BattleStatus.AILMENT_RESIST, "POISON", 50, 5))
	# A second unit that has not acted keeps the turn from ending (and counting down).
	var battle: BattleEngine = _engine([caster, Fixtures.unit("Waiting")], [foe])
	battle.start()
	_cast(battle, caster, "140", foe)
	battle.advance(4)
	assert_eq(foe.find_status(BattleStatus.NO_AILMENT_RESIST, "POISON").turns_left, 3)
	assert_eq(foe.ailment_resistance("POISON"), 0, "blown away, whatever the base and buffs say")
	assert_eq(foe.status_value(BattleStatus.AILMENT_RESIST, "BLIND"), -30, "146 kept alongside 140")
	assert_eq(foe.ailment_resistance("BLIND"), 70)
	assert_true(foe.has_ailment("POISON"), "the inflict after it lands")


func test_dispel_removes_lowered_resistances() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "140", Fixtures.record("Blow Away", [[1, 1, 140, [0, 0, 0, 0, 0, 0, 0, -100, 1, 3]]], "4:100"))
	catalog.add_record(BattleSkill.KIND_ABILITY, "59", Fixtures.record("Purify", [[1, 1, 59, [2, 0]]], "4:100"))
	var caster: Combatant = Fixtures.unit("Caster")
	var cleaner: Combatant = Fixtures.unit("Cleaner", {"attack_frames": "10:100"})
	var foe: Combatant = _idle("Foe", {"ailment_resist": {"PETRIFY": 100}})
	var battle: BattleEngine = _engine([caster, cleaner], [foe])
	battle.start()
	_cast(battle, caster, "140", foe)
	battle.advance(4)
	assert_eq(foe.ailment_resistance("PETRIFY"), 0, "-100 reads as blown away too")
	_cast(battle, cleaner, "59", foe)
	battle.advance(4)
	assert_eq(foe.ailment_resistance("PETRIFY"), 100)

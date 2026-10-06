extends "res://tests/test_case.gd"

## BattleCommandMenu: the skill menu's options in the old order, each disabled reason the
## Skill button shows, the item menu, whom each kind of skill lets the player pick
## (following cooldown wrappers to the ability they run), and what Reload and Repeat
## restore. Fixture skills only; writes no save.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

const FIRE: String = "1001"
const CURE: String = "1002"
const CURAJA: String = "1003"
const RAISE: String = "1004"
const PROTECT_OTHER: String = "1005"
const GUARD: String = "1006"
const STRIKE: String = "2001"
const STRIKE_CD: String = "2002"
const HEAL_CD: String = "2003"
const HEAL: String = "2004"
const ORB_STRIKE: String = "2005"
const LIMIT: String = "3001"
const ESPER_SKILL: String = "10101"
const POTION: String = "101000100"
const ETHER: String = "101001100"
const THUNDER: String = "1011"
const HOLY_CURE: String = "1012"
const DUALCAST: String = "2101"
const STRIKE_TWICE: String = "2102"
const KILLER_SHOT: String = "2201"
const FINISHING_BLOW: String = "2202"


func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()


static func _catalog() -> SkillCatalog:
	var catalog: SkillCatalog = Fixtures.catalog()
	var single_ally_heal: Array = [[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_ALLY, 16, [200]]]
	catalog.add_record(BattleSkill.KIND_MAGIC, FIRE, Fixtures.record("Fire",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_OPPONENT, 15, Fixtures.magic_params(100)]], "10:100", {"cost": {"MP": 10}}))
	catalog.add_record(BattleSkill.KIND_MAGIC, CURE, Fixtures.record("Cure", single_ally_heal, "10:100", {"cost": {"MP": 5}}))
	catalog.add_record(BattleSkill.KIND_MAGIC, CURAJA, Fixtures.record("Curaja",
		[[SkillEffect.AREA_ALL, SkillEffect.TARGET_ALLY, 16, [200]]]))
	catalog.add_record(BattleSkill.KIND_MAGIC, RAISE, Fixtures.record("Raise",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_ALLY_ALT, 4, [30]]], "10:100", {"targetType": 7}))
	catalog.add_record(BattleSkill.KIND_ABILITY, PROTECT_OTHER, Fixtures.record("Protect Other",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_ALLY_EXCEPT_SELF, 16, [100]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, GUARD, Fixtures.record("Guard",
		[[SkillEffect.AREA_SELF, SkillEffect.TARGET_SELF, 16, [100]]]))
	catalog.add_record(BattleSkill.KIND_ABILITY, STRIKE, Fixtures.record("Strike",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_OPPONENT, 1, Fixtures.physical_params(150)]]))
	# "One use every 3 turns", first ready on turn 3.
	catalog.add_record(BattleSkill.KIND_ABILITY, STRIKE_CD, Fixtures.record("Strike (CD)", [[1, 1, 130, [int(STRIKE), 1, [2, 0], 0]]], ""))
	catalog.add_record(BattleSkill.KIND_ABILITY, HEAL, Fixtures.record("Heal", single_ally_heal))
	# Ready at once. Its own entry aims at an enemy; the ability it runs heals one ally.
	catalog.add_record(BattleSkill.KIND_ABILITY, HEAL_CD, Fixtures.record("Heal (CD)", [[1, 1, 130, [int(HEAL), 1, [2, 2], 0]]], ""))
	catalog.add_record(BattleSkill.KIND_ABILITY, ORB_STRIKE, Fixtures.record("Orb Strike",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_OPPONENT, 1, Fixtures.physical_params(150)]], "10:100",
		{"alternate_cost": {"type": 1, "amount": 2}}))
	catalog.add_record(BattleSkill.KIND_LIMIT_BURST, LIMIT, {
		"name": "Blade Flash",
		"levels": [[8, [[1, 1, 1, Fixtures.physical_params(180)]]]],
		"attack_frames": [[60]],
		"attack_damage": [[100]],
	})
	catalog.add_record(BattleSkill.KIND_ESPER, ESPER_SKILL, Fixtures.record("Lunatic Voice",
		[[SkillEffect.AREA_ALL, SkillEffect.TARGET_OPPONENT, 15, Fixtures.magic_params(100)]], "10:100",
		{"attack_type": BattleSkill.ATTACK_NONE}))
	catalog.add_record(BattleSkill.KIND_ITEM, POTION, Fixtures.record("Potion", single_ally_heal))
	catalog.add_record(BattleSkill.KIND_ITEM, ETHER, Fixtures.record("Ether",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_ALLY, 17, [50]]]))
	catalog.add_record(BattleSkill.KIND_MAGIC, THUNDER, Fixtures.record("Thunder",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_OPPONENT, 15, Fixtures.magic_params(100)]], "10:100",
		{"cost": {"MP": 10}, "magic_type": "Black"}))
	catalog.add_record(BattleSkill.KIND_MAGIC, HOLY_CURE, Fixtures.record("White Cure", single_ally_heal, "10:100",
		{"cost": {"MP": 5}, "magic_type": "White"}))
	catalog.add_record(BattleSkill.KIND_ABILITY, DUALCAST, Fixtures.record("Dualcast", [[0, 3, 45, ["none"]]], ""))
	# An op 53 command, as passive 53 gives one: Strike twice.
	catalog.add_record(BattleSkill.KIND_ABILITY, STRIKE_TWICE, Fixtures.record("Double Strike",
		[[0, 3, 53, [2, int(STRIKE_TWICE), -1, [int(STRIKE)], 1, 0]]], ""))
	# Killer Shot 209240: damage, then Finishing Blow for one turn, one use.
	catalog.add_record(BattleSkill.KIND_ABILITY, KILLER_SHOT, Fixtures.record("Killer Shot", [
		[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_OPPONENT, 1, Fixtures.physical_params(100)],
		[SkillEffect.AREA_SELF, SkillEffect.TARGET_SELF, 100, [2, int(FINISHING_BLOW), 1, 2, 1, 0]],
	]))
	catalog.add_record(BattleSkill.KIND_ABILITY, FINISHING_BLOW, Fixtures.record("Finishing Blow",
		[[SkillEffect.AREA_SINGLE, SkillEffect.TARGET_OPPONENT, 1, Fixtures.physical_params(300)]]))
	return catalog


## A unit with a limit burst, an esper and the profile skills `magic` and `abilities`
## (profile entries { id, source, awaken_level }).
static func _unit(unit_name: String, magic: Array = [], abilities: Array = [], spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"limit_burst_id": LIMIT, "max_lb": 800, "esper_id": 1, "esper_skill_id": ESPER_SKILL}
	full.merge(spec, true)
	var unit: Combatant = Fixtures.unit(unit_name, full)
	unit.profile = {"skills": {"magic": magic, "ability": abilities}}
	return unit


static func _foe(foe_name: String = "Foe") -> Combatant:
	return Fixtures.monster(foe_name, {"brain": IdleEnemyBrain.new()})


static func _battle(party: Array, foes: Array = []) -> BattleEngine:
	var battle: BattleEngine = Fixtures.engine(party, foes if not foes.is_empty() else [_foe()], null, _catalog())
	battle.start()
	return battle


static func _named(options: Array[Dictionary], option_name: String) -> Dictionary:
	for option in options:
		if option["name"] == option_name:
			return option
	return {}


## Plays out the turn with basic attacks for whoever has not acted, a unit revived
## during the turn included.
static func _finish_turn(battle: BattleEngine) -> void:
	var next_turn: int = battle.turn + 1
	Fixtures.run_until(battle, func() -> bool:
		if battle.turn == next_turn:
			return true
		if battle.phase == BattleEngine.Phase.PLAYER:
			var ids: Array = []
			for unit in battle.units_to_act():
				ids.append(unit.id)
			battle.execute_many(ids)
		return false)


# === Options ===

func test_options_list_the_limit_burst_the_esper_then_magic_and_abilities() -> void:
	var hero: Combatant = _unit("Hero",
		[{"id": int(FIRE), "source": "Trait"}, {"id": 9999, "source": "Trait"}, {"id": int(CURE), "source": "Equip"}],
		[{"id": int(STRIKE), "source": "Trait", "awaken_level": 2}])
	var battle: BattleEngine = _battle([hero])
	var options: Array[Dictionary] = BattleCommandMenu.options(battle, hero)

	var names: Array = options.map(func(option: Dictionary) -> String: return option["name"])
	assert_eq(names, ["Blade Flash", "Lunatic Voice", "Fire", "Cure", "Strike"], "the unknown magic 9999 is left out")
	var limit_burst: Dictionary = options[0]
	assert_eq(limit_burst["command"].kind, BattleCommand.Kind.LIMIT_BURST)
	assert_eq(limit_burst["command"].skill_id, LIMIT)
	assert_eq([limit_burst["role_style"], limit_burst["source"]], [BattleCommandMenu.ROLE_LIMITBURST, ""])
	var esper: Dictionary = options[1]
	assert_eq(esper["command"].kind, BattleCommand.Kind.EVOKE)
	assert_eq([esper["role_style"], esper["source"]], [BattleCommandMenu.ROLE_ESPER, "Esper"])
	assert_eq(options[3]["command"].skill_kind, BattleSkill.KIND_MAGIC)
	assert_eq([options[3]["source"], options[3]["role_style"]], ["Equip", BattleCommandMenu.ROLE_STANDARD])
	var strike: Dictionary = options[4]
	assert_eq([strike["command"].skill_kind, strike["command"].skill_id], [BattleSkill.KIND_ABILITY, STRIKE])
	assert_eq(strike["awaken_level"], 2)
	assert_eq(strike["skill"].record["name"], "Strike", "the record the Skill button draws")
	assert_eq(strike["limits"], {})


func test_a_unit_without_a_limit_burst_or_esper_has_neither_option() -> void:
	var plain: Combatant = _unit("Plain", [{"id": int(FIRE)}], [], {"limit_burst_id": "", "esper_id": 0, "esper_skill_id": ""})
	var battle: BattleEngine = _battle([plain])
	var names: Array = BattleCommandMenu.options(battle, plain).map(func(option: Dictionary) -> String: return option["name"])
	assert_eq(names, ["Fire"])


func test_each_disabled_reason() -> void:
	var hero: Combatant = _unit("Hero", [{"id": int(FIRE)}, {"id": int(CURE)}],
		[{"id": int(STRIKE)}, {"id": int(STRIKE_CD)}, {"id": int(ORB_STRIKE)}], {"mp": 7, "lb": 700})
	var battle: BattleEngine = _battle([hero])
	var options: Array[Dictionary] = BattleCommandMenu.options(battle, hero)
	assert_eq(_named(options, "Blade Flash")["disabled_reason"], BattleCommandMenu.REASON_LACK_LIMIT, "7 of 8 crystals")
	assert_eq(_named(options, "Lunatic Voice")["disabled_reason"], BattleCommandMenu.REASON_LACK_SUMMON, "the gauge is empty")
	assert_eq(_named(options, "Fire")["disabled_reason"], BattleCommandMenu.REASON_LACK_MP, "10 MP, has 7")
	assert_eq(_named(options, "Cure")["disabled_reason"], BattleCommandMenu.REASON_NONE)
	assert_eq(_named(options, "Strike")["disabled_reason"], BattleCommandMenu.REASON_NONE)
	assert_eq(_named(options, "Strike (CD)")["disabled_reason"], BattleCommandMenu.REASON_UNAVAILABLE, "not ready before turn 3")
	assert_eq(_named(options, "Strike (CD)")["limits"], {"uses_left": -1, "ready_turn": 3})
	assert_eq(_named(options, "Orb Strike")["disabled_reason"], BattleCommandMenu.REASON_LACK_SUMMON, "needs 2 orbs")

	hero.lb = 800
	battle.esper_orbs = battle.rules.esper_gauge_max
	options = BattleCommandMenu.options(battle, hero)
	assert_eq(_named(options, "Blade Flash")["disabled_reason"], BattleCommandMenu.REASON_NONE)
	assert_eq(_named(options, "Lunatic Voice")["disabled_reason"], BattleCommandMenu.REASON_NONE)
	assert_eq(_named(options, "Orb Strike")["disabled_reason"], BattleCommandMenu.REASON_NONE)

	assert_eq(battle.debug_edit(hero.id, &"ailment", 3, "SILENCE"), BattleEngine.OK)
	options = BattleCommandMenu.options(battle, hero)
	assert_eq(_named(options, "Cure")["disabled_reason"], BattleCommandMenu.REASON_UNAVAILABLE, "silenced")
	assert_eq(_named(options, "Strike")["disabled_reason"], BattleCommandMenu.REASON_NONE, "silence blocks magic only")

	assert_eq(battle.execute(hero.id), BattleEngine.OK)
	options = BattleCommandMenu.options(battle, hero)
	assert_eq(_named(options, "Strike")["disabled_reason"], BattleCommandMenu.REASON_UNAVAILABLE, "already acted")


func test_the_disabled_reason_of_each_refusal() -> void:
	assert_eq(BattleCommandMenu.disabled_reason(BattleEngine.OK), BattleCommandMenu.REASON_NONE)
	assert_eq(BattleCommandMenu.disabled_reason(BattleEngine.REJECT_NOT_ENOUGH_MP), BattleCommandMenu.REASON_LACK_MP)
	assert_eq(BattleCommandMenu.disabled_reason(BattleEngine.REJECT_LIMIT_NOT_FULL), BattleCommandMenu.REASON_LACK_LIMIT)
	assert_eq(BattleCommandMenu.disabled_reason(BattleEngine.REJECT_ESPER_GAUGE_NOT_FULL), BattleCommandMenu.REASON_LACK_SUMMON)
	assert_eq(BattleCommandMenu.disabled_reason(BattleEngine.REJECT_NOT_ENOUGH_ORBS), BattleCommandMenu.REASON_LACK_SUMMON)
	for reason in [BattleEngine.REJECT_SILENCED, BattleEngine.REJECT_SKILL_NOT_READY, BattleEngine.REJECT_NO_USES_LEFT,
			BattleEngine.REJECT_ALREADY_ACTED, BattleEngine.REJECT_CANNOT_ACT, BattleEngine.REJECT_NOT_PLAYER_PHASE,
			BattleEngine.REJECT_UNIT_DOWN, BattleEngine.REJECT_NO_ITEMS_LEFT]:
		assert_eq(BattleCommandMenu.disabled_reason(reason), BattleCommandMenu.REASON_UNAVAILABLE, str(reason))


# === Items ===

func test_item_options_show_what_the_unit_can_still_pick() -> void:
	var first: Combatant = _unit("First")
	var second: Combatant = _unit("Second")
	var battle: BattleEngine = _battle([first, second])
	battle.item_stock = {POTION: 1, ETHER: 2}

	var options: Array[Dictionary] = BattleCommandMenu.item_options(battle, second)
	assert_eq(options.map(func(option: Dictionary) -> Array: return [option["name"], option["count"]]),
		[["Potion", 1], ["Ether", 2]], "the combat item bar's order")
	assert_eq(options[0]["command"].kind, BattleCommand.Kind.ITEM)
	assert_eq([options[0]["item_id"], options[0]["disabled_reason"]], [POTION, BattleCommandMenu.REASON_NONE])
	assert_true(options[0]["targeting"]["needs_ally_pick"], "a Potion picks an ally")

	assert_eq(battle.queue_command(first.id, BattleCommand.item(POTION, first.id)), BattleEngine.OK)
	options = BattleCommandMenu.item_options(battle, second)
	assert_eq(options.map(func(option: Dictionary) -> String: return option["name"]), ["Ether"],
		"the last Potion is held for First")
	assert_eq(BattleCommandMenu.item_options(battle, first).size(), 2, "First still sees the Potion it holds")


# === Targeting ===

func test_targeting_by_kind_of_skill() -> void:
	var catalog: SkillCatalog = _catalog()
	var fire: Dictionary = BattleCommandMenu.targeting(catalog.get_skill(BattleSkill.KIND_MAGIC, FIRE))
	assert_eq(fire, {"needs_ally_pick": false, "targets_fallen": false, "targets_opponent": true, "others_only": false})
	var cure: Dictionary = BattleCommandMenu.targeting(catalog.get_skill(BattleSkill.KIND_MAGIC, CURE))
	assert_eq([cure["needs_ally_pick"], cure["targets_fallen"], cure["targets_opponent"]], [true, false, false])
	var curaja: Dictionary = BattleCommandMenu.targeting(catalog.get_skill(BattleSkill.KIND_MAGIC, CURAJA))
	assert_false(curaja["needs_ally_pick"], "an area heal picks nobody")
	var raise: Dictionary = BattleCommandMenu.targeting(catalog.get_skill(BattleSkill.KIND_MAGIC, RAISE))
	assert_eq([raise["needs_ally_pick"], raise["targets_fallen"]], [true, true])
	var protect: Dictionary = BattleCommandMenu.targeting(catalog.get_skill(BattleSkill.KIND_ABILITY, PROTECT_OTHER))
	assert_eq([protect["needs_ally_pick"], protect["others_only"]], [true, true])
	var guard: Dictionary = BattleCommandMenu.targeting(catalog.get_skill(BattleSkill.KIND_ABILITY, GUARD))
	assert_eq([guard["needs_ally_pick"], guard["targets_opponent"]], [false, false], "a self effect picks nobody")
	assert_false(BattleCommandMenu.targeting(null)["needs_ally_pick"])


func test_a_wrapper_targets_like_the_ability_it_runs() -> void:
	var healer: Combatant = _unit("Healer", [], [{"id": int(HEAL_CD)}])
	var battle: BattleEngine = _battle([healer])
	var wrapper: BattleSkill = battle.catalog.get_skill(BattleSkill.KIND_ABILITY, HEAL_CD)
	assert_false(BattleCommandMenu.targeting(wrapper)["needs_ally_pick"], "the wrapper's own entry picks nobody")
	var option: Dictionary = _named(BattleCommandMenu.options(battle, healer), "Heal (CD)")
	assert_eq([option["targeting"]["needs_ally_pick"], option["targeting"]["targets_opponent"]], [true, false],
		"the menu reads the healing ability the wrapper runs")


func test_valid_ally_picks() -> void:
	var caster: Combatant = _unit("Caster")
	var living: Combatant = _unit("Living")
	var fallen: Combatant = _unit("Fallen")
	var foe: Combatant = _foe()
	var battle: BattleEngine = _battle([caster, living, fallen], [foe])
	battle.debug_edit(fallen.id, &"hp", 0)
	var cure: Dictionary = BattleCommandMenu.targeting(battle.catalog.get_skill(BattleSkill.KIND_MAGIC, CURE))
	var raise: Dictionary = BattleCommandMenu.targeting(battle.catalog.get_skill(BattleSkill.KIND_MAGIC, RAISE))
	var protect: Dictionary = BattleCommandMenu.targeting(battle.catalog.get_skill(BattleSkill.KIND_ABILITY, PROTECT_OTHER))

	assert_true(BattleCommandMenu.valid_ally(cure, living, caster))
	assert_true(BattleCommandMenu.valid_ally(cure, caster, caster), "a heal may pick its caster")
	assert_false(BattleCommandMenu.valid_ally(cure, fallen, caster), "a heal needs a living ally")
	assert_true(BattleCommandMenu.valid_ally(raise, fallen, caster))
	assert_false(BattleCommandMenu.valid_ally(raise, living, caster), "a revive needs a KO'd ally")
	assert_false(BattleCommandMenu.valid_ally(protect, caster, caster), "target 5 reaches the others only")
	assert_true(BattleCommandMenu.valid_ally(protect, living, caster))
	assert_false(BattleCommandMenu.valid_ally(cure, foe, caster), "an enemy is never an ally pick")
	assert_false(BattleCommandMenu.valid_ally(cure, null, caster))


# === Reload and Repeat ===

func test_restore_returns_a_copy_of_the_last_command_when_it_is_still_allowed() -> void:
	var hero: Combatant = _unit("Hero", [{"id": int(FIRE)}])
	var foe: Combatant = _foe()
	var battle: BattleEngine = _battle([hero], [foe])
	assert_null(BattleCommandMenu.restore_command(battle, hero), "nothing executed yet")

	assert_eq(battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, FIRE, foe.id)), BattleEngine.OK)
	assert_null(BattleCommandMenu.restore_command(battle, hero), "already acted this turn")
	_finish_turn(battle)
	var restored: BattleCommand = BattleCommandMenu.restore_command(battle, hero)
	assert_not_null(restored)
	assert_eq([restored.kind, restored.skill_kind, restored.skill_id, restored.target_id],
		[BattleCommand.Kind.SKILL, BattleSkill.KIND_MAGIC, FIRE, foe.id])
	assert_true(restored != hero.last_command, "a copy, not the engine's own command")

	hero.mp = 5
	assert_null(BattleCommandMenu.restore_command(battle, hero), "Fire costs 10 MP")


func test_restore_checks_the_ally_pick_and_the_items_left() -> void:
	var healer: Combatant = _unit("Healer", [{"id": int(CURE)}, {"id": int(RAISE)}])
	var friend: Combatant = _unit("Friend")
	var battle: BattleEngine = _battle([healer, friend])
	battle.item_stock = {POTION: 1}

	assert_eq(battle.execute(healer.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, CURE, friend.id)), BattleEngine.OK)
	_finish_turn(battle)
	assert_not_null(BattleCommandMenu.restore_command(battle, healer), "Friend is still alive")
	battle.debug_edit(friend.id, &"hp", 0)
	assert_null(BattleCommandMenu.restore_command(battle, healer), "Cure cannot pick a KO'd ally")

	assert_eq(battle.execute(healer.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, RAISE, friend.id)), BattleEngine.OK)
	_finish_turn(battle)
	assert_eq(friend.is_alive(), true, "Raise brought Friend back")
	assert_null(BattleCommandMenu.restore_command(battle, healer), "Raise needs a KO'd ally")

	assert_eq(battle.execute(healer.id, BattleCommand.item(POTION, healer.id)), BattleEngine.OK)
	_finish_turn(battle)
	assert_null(BattleCommandMenu.restore_command(battle, healer), "no Potion left")


func test_a_granted_skill_is_listed_while_the_grant_lasts_and_repeat_follows_it() -> void:
	var hero: Combatant = _unit("Hero", [], [{"id": int(KILLER_SHOT)}])
	var battle: BattleEngine = _battle([hero])
	var names: Callable = func() -> Array:
		return BattleCommandMenu.options(battle, hero).map(func(option: Dictionary) -> String: return option["name"])
	assert_eq(names.call(), ["Blade Flash", "Lunatic Voice", "Killer Shot"])

	assert_eq(battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, KILLER_SHOT)), BattleEngine.OK)
	_finish_turn(battle)
	assert_eq(names.call(), ["Blade Flash", "Lunatic Voice", "Killer Shot", "Finishing Blow"], "after the unit's own skills")
	var granted: Dictionary = _named(BattleCommandMenu.options(battle, hero), "Finishing Blow")
	assert_eq([granted["source"], granted["disabled_reason"]], ["Granted", BattleCommandMenu.REASON_NONE])
	assert_eq(granted["limits"], {"grant_turns_left": 1, "grant_uses_left": 1})

	assert_eq(battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, FINISHING_BLOW)), BattleEngine.OK)
	assert_eq(names.call(), ["Blade Flash", "Lunatic Voice", "Killer Shot"], "its one use is spent")
	_finish_turn(battle)
	assert_true(battle.can_execute(hero.id, hero.last_command) == BattleEngine.OK, "the engine itself does not check grants")
	assert_null(BattleCommandMenu.restore_command(battle, hero), "Repeat does: the grant is gone")


# === Multicast ===

func test_a_command_option_carries_its_pick_count_and_passive_commands_join_the_list() -> void:
	var hero: Combatant = _unit("Hero", [{"id": int(THUNDER), "source": "Trait"}],
		[{"id": int(DUALCAST), "source": "Trait"}, {"id": int(STRIKE), "source": "Trait"}],
		{"passives": {"multicast_commands": [STRIKE_TWICE, STRIKE]}})
	var battle: BattleEngine = _battle([hero])
	var options: Array[Dictionary] = BattleCommandMenu.options(battle, hero)
	var names: Array = options.map(func(option: Dictionary) -> String: return option["name"])
	assert_eq(names, ["Blade Flash", "Lunatic Voice", "Thunder", "Dualcast", "Strike", "Double Strike"],
		"the passive's command after the profile's skills, Strike once")
	var dualcast: Dictionary = _named(options, "Dualcast")
	assert_eq([int(dualcast["multicast_count"]), dualcast["disabled_reason"]], [2, BattleCommandMenu.REASON_NONE],
		"a command with no picks yet can be started")
	assert_eq(int(_named(options, "Strike")["multicast_count"]), 0)
	var passive_command: Dictionary = _named(options, "Double Strike")
	assert_eq([int(passive_command["multicast_count"]), passive_command["source"]], [2, "Trait"])

	var no_magic: Combatant = _unit("Fighter", [], [{"id": int(DUALCAST)}])
	battle = _battle([no_magic])
	assert_eq(_named(BattleCommandMenu.options(battle, no_magic), "Dualcast")["disabled_reason"], BattleCommandMenu.REASON_UNAVAILABLE,
		"nothing to pick")


func test_multicast_options_grey_what_the_next_pick_cannot_be() -> void:
	var hero: Combatant = _unit("Hero", [{"id": int(THUNDER)}, {"id": int(HOLY_CURE)}],
		[{"id": int(DUALCAST)}, {"id": int(STRIKE)}], {"mp": 15, "lb": 800})
	var battle: BattleEngine = _battle([hero])
	var none: Array[BattleCommand] = []
	var command := BattleCommand.multicast(DUALCAST, none)
	var options: Array[Dictionary] = BattleCommandMenu.multicast_options(battle, hero, command, none)
	assert_eq(_named(options, "Thunder")["disabled_reason"], BattleCommandMenu.REASON_NONE)
	assert_eq(_named(options, "White Cure")["disabled_reason"], BattleCommandMenu.REASON_NONE)
	for option_name in ["Blade Flash", "Lunatic Voice", "Dualcast", "Strike"]:
		assert_eq(_named(options, option_name)["disabled_reason"], BattleCommandMenu.REASON_UNAVAILABLE, option_name)

	var picks: Array[BattleCommand] = [BattleCommand.skill(BattleSkill.KIND_MAGIC, THUNDER)]
	options = BattleCommandMenu.multicast_options(battle, hero, command, picks)
	assert_eq([_named(options, "Thunder")["disabled_reason"], int(_named(options, "Thunder")["picked"])],
		[BattleCommandMenu.REASON_LACK_MP, 1], "20 MP for two, the unit has 15")
	assert_eq(_named(options, "White Cure")["disabled_reason"], BattleCommandMenu.REASON_NONE, "15 MP for both")
	assert_eq(int(_named(options, "White Cure")["picked"]), 0)


func test_restore_brings_a_multicast_back_while_its_ally_pick_holds() -> void:
	var hero: Combatant = _unit("Hero", [{"id": int(THUNDER)}, {"id": int(HOLY_CURE)}], [{"id": int(DUALCAST)}])
	var friend: Combatant = _unit("Friend")
	var foe: Combatant = _foe()
	var battle: BattleEngine = _battle([hero, friend], [foe])
	var picks: Array[BattleCommand] = [
		BattleCommand.skill(BattleSkill.KIND_MAGIC, HOLY_CURE, friend.id), BattleCommand.skill(BattleSkill.KIND_MAGIC, THUNDER),
	]
	var multicast := BattleCommand.multicast(DUALCAST, picks, foe.id)
	assert_true(BattleCommandMenu.aims_at_opponents(battle, hero, multicast), "Thunder has no target of its own")
	var heal_only: Array[BattleCommand] = [
		BattleCommand.skill(BattleSkill.KIND_MAGIC, HOLY_CURE, friend.id), BattleCommand.skill(BattleSkill.KIND_MAGIC, HOLY_CURE, hero.id),
	]
	assert_false(BattleCommandMenu.aims_at_opponents(battle, hero, BattleCommand.multicast(DUALCAST, heal_only)))
	assert_eq(battle.execute(hero.id, multicast), BattleEngine.OK)
	_finish_turn(battle)

	var restored: BattleCommand = BattleCommandMenu.restore_command(battle, hero)
	assert_not_null(restored)
	assert_eq([restored.picks.size(), restored.picks[0].target_id], [2, friend.id])
	battle.debug_edit(friend.id, &"hp", 0)
	assert_null(BattleCommandMenu.restore_command(battle, hero), "the Cure pick cannot reach a KO'd ally")


func test_restore_keeps_attack_and_defend() -> void:
	var hero: Combatant = _unit("Hero")
	var guard: Combatant = _unit("Guard")
	var battle: BattleEngine = _battle([hero, guard])
	battle.execute(hero.id, BattleCommand.attack())
	battle.execute(guard.id, BattleCommand.defend())
	_finish_turn(battle)
	assert_eq(BattleCommandMenu.restore_command(battle, hero).kind, BattleCommand.Kind.ATTACK)
	assert_eq(BattleCommandMenu.restore_command(battle, guard).kind, BattleCommand.Kind.DEFEND)

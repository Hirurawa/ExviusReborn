class_name BattleBuilder
extends RefCounted

## Builds a BattleEngine from game data and the player's roster. One builder replaces
## the old BattleManager's three entry points (initialize_battle, initialize_bg,
## initialize_test_battle). build() takes the params UIManager.push("combat_ui", ...)
## hands to BattleUI:
##   { "mission_id": id }    a mission: the active party against every wave of its plan
##   { "battle_group": id }  the active party against one formation (colosseum)
##   {}                      the debug test battle
## Session-layer code: it reads GameDatabase, StatCalculator, PartyService and
## UnitService. Rewards and dialogue belong to the session (milestone 4).

const TEST_BATTLE_GROUP: String = "111050313"
## Lasswell and Rain, the starter units the old test battle used.
const TEST_PARTY_UNIT_IDS: Array[String] = ["100000202", "100000102"]
## The old test battle's stat override.
const TEST_STATS: Dictionary = {"HP": 100000, "MP": 500000, "ATK": 1000, "DEF": 1000, "MAG": 1000, "SPR": 1000}

var rules: BattleRules
var catalog: SkillCatalog
var battle_seed: int = 0


## A negative seed picks a random one.
func _init(battle_rules: BattleRules = null, skill_catalog: SkillCatalog = null, seed_value: int = -1) -> void:
	rules = battle_rules if battle_rules != null else BattleRules.new()
	catalog = skill_catalog if skill_catalog != null else DatabaseSkillCatalog.new()
	battle_seed = seed_value if seed_value >= 0 else randi()


## An engine ready to start() for `params` (see the class notes), carrying the player's
## combat items.
func build(params: Dictionary) -> BattleEngine:
	var party: Array[Combatant] = []
	var formation: Array[Combatant] = []
	var waves: Array[Callable] = []
	if params.has("mission_id"):
		waves = mission_waves(str(params["mission_id"]))
		party = party_from_units(active_party_units())
		if not waves.is_empty():
			formation.assign(waves[0].call())
	elif params.has("battle_group"):
		party = party_from_units(active_party_units())
		formation = formation_for("", str(params["battle_group"]))
	else:
		party = party_from_units(test_party_units(), TEST_STATS)
		formation = formation_for("", TEST_BATTLE_GROUP)
	var engine: BattleEngine = assemble(party, formation)
	for i in range(1, waves.size()):
		engine.queue_wave(waves[i])
	engine.item_stock = combat_item_stock()
	return engine


## An engine holding `party` (by slot, null for an empty slot) and `formation`.
func assemble(party: Array[Combatant], formation: Array[Combatant]) -> BattleEngine:
	var engine := BattleEngine.new(catalog, rules, battle_seed)
	for slot in range(party.size()):
		if party[slot] != null:
			engine.add_party_member(party[slot], slot)
	for foe in formation:
		engine.add_enemy(foe)
	return engine


# === Items ===

## The items the party brings (BattleEngine.item_stock), from the player's combat item
## bar and inventory.
func combat_item_stock() -> Dictionary:
	return item_stock(CombatItemsService.combat_items, InventoryService.owned_items.get("stackables", {}))


## Item id -> count for the combat item bar `slots` (item ids, "" for an empty slot) and
## the `owned` quantities: each item that casts an ability in battle, as many as owned up
## to its carry limit (item.carryMaxNum: 10 Potions, 5 Phoenix Downs; a reading of the
## data). Items that cast nothing (a Tent, a material) are left out.
func item_stock(slots: Array, owned: Dictionary) -> Dictionary:
	var stock: Dictionary = {}
	for slot in slots:
		var item_id: String = str(slot)
		if item_id == "" or stock.has(item_id) or catalog.get_item(item_id) == null:
			continue
		var count: int = int(owned.get(item_id, 0))
		var carry_max: int = int(GameDatabase.get_item(int(item_id)).get("carryMaxNum", 0))
		if carry_max > 0:
			count = mini(count, carry_max)
		if count > 0:
			stock[item_id] = count
	return stock


# === Party ===

## The active party as owned-unit dicts by slot, {} for an empty slot. This is the one
## copy of the lookup the old BattleManager repeated in each init function.
func active_party_units() -> Array:
	var instance_ids: Array = []
	var active_party: Dictionary = PartyService.get_active_party()
	if not active_party.is_empty():
		instance_ids = active_party.get("units", [])
	elif not PartyService.parties.is_empty():
		var fallback: Variant = PartyService.parties[0]
		if fallback is Dictionary:
			instance_ids = (fallback as Dictionary).get("units", [])
		elif fallback is Array:
			instance_ids = fallback

	var owned: Dictionary = {}
	for unit in UnitService.owned_units_ids:
		if unit is Dictionary:
			owned[str(unit.get("instance_id", ""))] = unit
	var units: Array = []
	for instance_id in instance_ids:
		units.append(owned.get(str(instance_id), {}))
	return units


## Party members by slot from owned-unit dicts ({} = empty slot). `stat_override`
## replaces stats in each profile (the test battle's giant stats).
func party_from_units(units: Array, stat_override: Dictionary = {}) -> Array[Combatant]:
	var party: Array[Combatant] = []
	for unit in units:
		if unit is Dictionary and not (unit as Dictionary).is_empty():
			party.append(party_member(unit, stat_override))
		else:
			party.append(null)
	return party


func party_member(unit: Dictionary, stat_override: Dictionary = {}) -> Combatant:
	var battle_unit: Dictionary = unit.duplicate()
	var profile: Dictionary = StatCalculator.calculate_final_stats(battle_unit)
	if not stat_override.is_empty():
		var stats: Dictionary = (profile.get("stats", {}) as Dictionary).duplicate()
		stats.merge(stat_override, true)
		profile["stats"] = stats
	battle_unit["final_stats"] = profile
	var member: Combatant = CombatantFactory.party_member(battle_unit, profile)
	# "Change effect of normal attack" passives (op 100): the attack command runs that
	# ability instead, free like any attack, on the unit's own attack frames when the
	# ability has none. An id the catalog cannot build keeps the basic attack.
	if member.passives.attack_replace_id != "":
		var replacement: BattleSkill = catalog.get_attack_replacement(member.passives.attack_replace_id, member.attack_skill)
		if replacement != null:
			member.attack_skill = replacement
	var limit_burst: BattleSkill = null
	if member.limit_burst_id != "":
		limit_burst = catalog.get_limit_burst(member.limit_burst_id, member.limit_burst_level)
	member.max_lb = limit_burst.lb_cost if limit_burst != null else 0
	# The esper in the unit's slot of the active party, the same one its stats count.
	var esper: Dictionary = StatCalculator.resolve_party_esper(battle_unit)
	if not esper.is_empty():
		assign_esper(member, int(esper.get("summon_id", 0)), int(esper.get("rank", 1)))
	return member


## Gives `member` the esper `esper_id` (a beastId) at `rank` to evoke: the beast skill
## of that rank. Returns false, leaving the member without an esper, when the esper or
## the rank is unknown. Only evocation: the esper's stat bonus and board come from the
## active party through StatCalculator.
func assign_esper(member: Combatant, esper_id: int, rank: int) -> bool:
	member.esper_id = 0
	member.esper_skill_id = ""
	if esper_id <= 0:
		return false
	var row: Dictionary = GameDatabase.get_esper(esper_id, maxi(1, rank))
	var skill_id: String = str(row.get("beastSkillId", "")) if not row.is_empty() else ""
	if skill_id == "" or catalog.get_skill(BattleSkill.KIND_ESPER, skill_id) == null:
		return false
	member.esper_id = esper_id
	member.esper_skill_id = skill_id
	return true


## The starter units at level 1 with no equipment, built straight from the unit table.
## The old test battle created them with AccountService.start_new_local_game, which
## writes a save; this touches no save.
func test_party_units() -> Array:
	var units: Array = []
	for unit_id in TEST_PARTY_UNIT_IDS:
		units.append(unit_from_database(unit_id))
	return units


## An owned-unit dict (unit table row plus a fresh instance record) for `unit_id` at
## `level`, with no equipment. {} for an unknown id.
func unit_from_database(unit_id: String, level: int = 1) -> Dictionary:
	var template: Dictionary = GameDatabase.get_unit(int(unit_id))
	if template.is_empty():
		return {}
	var unit: Dictionary = template.duplicate()
	unit.merge({
		"instance_id": "battle_%s" % unit_id,
		"unit_id": unit_id,
		"level": level,
		"current_rarity": int(template.get("rare", 1)),
		"equipment": {},
		"awakened_abilities": [],
		"limitburst_level": 1,
	}, true)
	return unit


# === Enemies ===

## One formation source per wave of a mission's plan, Callable() -> Array[Combatant]
## (see BattleEngine.queue_wave). Each resolves its formation when called, so a
## lottery pick happens when its wave begins. Empty when the mission has no plan.
func mission_waves(mission_id: String) -> Array[Callable]:
	var waves: Array[Callable] = []
	# A local reference keeps this builder alive for as long as the lambdas are.
	var builder: BattleBuilder = self
	for entry in EncounterResolver.build_wave_plan(mission_id):
		var target_id: String = str(entry.get("target_id", ""))
		waves.append(func() -> Array[Combatant]: return builder.formation_for(mission_id, target_id))
	return waves


## The enemies of one wave. `target_id` is a wave-plan target: a battle lottery pool or
## a battle group id. Empty when it resolves to no formation.
func formation_for(mission_id: String, target_id: String) -> Array[Combatant]:
	var formation: Array[Combatant] = []
	for descriptor in EncounterResolver.resolve_formation(mission_id, target_id):
		formation.append(enemy_from_descriptor(descriptor))
	return formation


## One monster by its 9-digit id (the id the AI tables key on), outside any battle
## group: not a boss, no loot. null when the id has no monster parts row.
func enemy_by_id(instance_id: String) -> Combatant:
	var parts: Dictionary = GameDatabase.get_monster_parts(instance_id)
	if parts.is_empty():
		return null
	var dictionary_id: String = str(parts.get("dictionaryId", ""))
	var monster_name: String = GameDatabase.get_monster_name(dictionary_id)
	return enemy_from_descriptor({
		"instance_id": instance_id,
		"id": dictionary_id,
		"name": monster_name if monster_name != "" else str(parts.get("name", "Unknown Monster")),
		"is_boss": false,
		"loot": {},
	})


func enemy_from_descriptor(descriptor: Dictionary) -> Combatant:
	var instance_id: String = str(descriptor.get("instance_id", ""))
	var parts: Dictionary = GameDatabase.get_monster_parts(instance_id)
	var stat_input: Dictionary = CombatantFactory.monster_stat_input(parts)
	var profile: Dictionary = StatCalculator.calculate_final_stats(stat_input)
	var foe: Combatant = CombatantFactory.enemy(descriptor, parts, stat_input, profile)
	foe.brain = brain_for(instance_id)
	return foe


## The AI script for a 9-digit monster id, or a basic attacker for the 14153 monsters
## that have none. Keyed on the instance id, not the base monster id, so a boss does
## not get its trash-mob variant's behaviour.
func brain_for(instance_id: String) -> EnemyBrain:
	var compiled: MonsterAIScript = MonsterAIScript.compile(instance_id)
	if compiled.has_script():
		return ScriptedEnemyBrain.new(compiled, MonsterAIState.new(instance_id))
	return EnemyBrain.new()

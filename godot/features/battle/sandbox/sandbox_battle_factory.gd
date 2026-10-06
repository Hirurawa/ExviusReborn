class_name SandboxBattleFactory
extends RefCounted

## The battle sandbox's logic, kept out of its UI so tests can run it headless: setups
## (party slots, enemies), unit and monster search, building an engine from a setup,
## enemy behaviours and a party member's command menu. Session-layer code: it reads
## GameDatabase through BattleBuilder.
##
## A setup is a plain Dictionary, the same one the sandbox saves between runs:
##   party:        6 slots, each {} or { unit_id, level, lb_level, stats, esper,
##                 esper_rank, skills }, where unit_id is a unit row (the rarity is part
##                 of the id), stats an override string such as "ATK=1000 HP=50000",
##                 esper a beastId to evoke (0 or missing for none; evocation only, its
##                 stat bonus and board are not applied) and skills extra magic or
##                 ability ids the unit gets for this battle ("200150 20010": Dualcast
##                 and Fire), to try skills its kit does not have
##   enemy_mode:   "group" (battle_group), "monsters" (monsters) or "mission" (mission)
##   battle_group: a battle group id; "|" separates waves ("111050313 | 111050314")
##   monsters:     9-digit monster ids, "302001000, 302001000" or "302001000 x3"; "|"
##                 separates waves
##   mission:      a mission id: its real wave plan, a formation rolled per wave
##   seed:         the battle seed

const PARTY_SLOTS: int = 6
const MAX_ENEMIES: int = 10
const ENEMY_MODE_GROUP: String = "group"
const ENEMY_MODE_MONSTERS: String = "monsters"
const ENEMY_MODE_MISSION: String = "mission"
## Separates waves in the battle group and monster id fields.
const WAVE_SEPARATOR: String = "|"
const STAT_KEYS: PackedStringArray = ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]

## Enemy behaviours the sandbox can switch between.
const BEHAVIOUR_SCRIPTED: StringName = &"scripted"
const BEHAVIOUR_ATTACK: StringName = &"attack"
const BEHAVIOUR_PASS: StringName = &"pass"
## Combatant.meta key holding the brain the builder gave an enemy.
const META_BUILT_BRAIN: String = "sandbox_built_brain"

## What went wrong in the last build(): unknown ids, bad override keys, an empty side.
var problems: Array[String] = []

static var _units: Array = []
static var _units_by_id: Dictionary = {}


## The old test battle: Lasswell and Rain at rarity 2, level 1, with its giant stats,
## against battle group 111050313 (Zu).
static func test_setup() -> Dictionary:
	var stats: PackedStringArray = []
	for stat_name in STAT_KEYS:
		if BattleBuilder.TEST_STATS.has(stat_name):
			stats.append("%s=%d" % [stat_name, int(BattleBuilder.TEST_STATS[stat_name])])
	var party: Array = []
	for unit_id in BattleBuilder.TEST_PARTY_UNIT_IDS:
		party.append({"unit_id": unit_id, "level": 1, "lb_level": 1, "stats": " ".join(stats)})
	while party.size() < PARTY_SLOTS:
		party.append({})
	return {
		"party": party,
		"enemy_mode": ENEMY_MODE_GROUP,
		"battle_group": BattleBuilder.TEST_BATTLE_GROUP,
		"monsters": "",
		"mission": "",
		"seed": 42,
	}


# === Building ===

## An engine for `setup` with `seed_value`, not started, with every wave queued.
## Problems go to `problems`; a side left empty still builds (the engine ends such a
## battle at once).
func build(setup: Dictionary, seed_value: int, rules: BattleRules) -> BattleEngine:
	problems = []
	var builder := BattleBuilder.new(rules, null, seed_value)
	var party: Array[Combatant] = []
	var slots: Array = setup.get("party", [])
	for slot in range(mini(slots.size(), PARTY_SLOTS)):
		party.append(_party_member(builder, slots[slot], slot))
	var waves: Array[Callable] = _enemy_waves(builder, setup)
	var formation: Array[Combatant] = []
	if not waves.is_empty():
		formation.assign(waves[0].call())
	if party.all(func(member: Combatant) -> bool: return member == null):
		problems.append("the party is empty")
	var engine: BattleEngine = builder.assemble(party, formation)
	for i in range(1, waves.size()):
		engine.queue_wave(waves[i])
	return engine


## One formation source per wave (see BattleEngine.queue_wave). Battle groups and
## monster ids are built now, so their problems show at once; a mission's waves roll
## their formations when they begin.
func _enemy_waves(builder: BattleBuilder, setup: Dictionary) -> Array[Callable]:
	var waves: Array[Callable] = []
	match str(setup.get("enemy_mode", ENEMY_MODE_GROUP)):
		ENEMY_MODE_MISSION:
			var mission_id: String = str(setup.get("mission", "")).strip_edges()
			waves = builder.mission_waves(mission_id)
			if waves.is_empty():
				problems.append("mission \"%s\" has no wave plan" % mission_id)
		ENEMY_MODE_MONSTERS:
			var texts: PackedStringArray = split_waves(str(setup.get("monsters", "")))
			for i in range(texts.size()):
				var prefix: String = "wave %d: " % (i + 1) if texts.size() > 1 else ""
				var errors: Array[String] = []
				var foes: Array[Combatant] = []
				for instance_id in parse_monster_ids(texts[i], errors):
					var foe: Combatant = builder.enemy_by_id(instance_id)
					if foe == null:
						errors.append("unknown monster id %s" % instance_id)
					else:
						foes.append(foe)
				for error in errors:
					problems.append(prefix + error)
				waves.append(func() -> Array[Combatant]: return foes)
		_:
			var group_ids: PackedStringArray = split_waves(str(setup.get("battle_group", "")))
			if group_ids.is_empty():
				group_ids.append("")
			for i in range(group_ids.size()):
				var foes: Array[Combatant] = builder.formation_for("", group_ids[i])
				if foes.is_empty():
					var prefix: String = "wave %d: " % (i + 1) if group_ids.size() > 1 else ""
					problems.append("%sbattle group \"%s\" has no monsters" % [prefix, group_ids[i]])
				waves.append(func() -> Array[Combatant]: return foes)
	return waves


## The waves of a battle group or monster id field: the text between "|" separators,
## trimmed, empty ones left out.
static func split_waves(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for part in text.split(WAVE_SEPARATOR):
		if part.strip_edges() != "":
			out.append(part.strip_edges())
	return out


func _party_member(builder: BattleBuilder, slot: Variant, index: int) -> Combatant:
	if not slot is Dictionary or (slot as Dictionary).is_empty():
		return null
	var unit_id: String = str(slot.get("unit_id", "")).strip_edges()
	if unit_id == "":
		return null
	var unit: Dictionary = builder.unit_from_database(unit_id, maxi(1, int(slot.get("level", 1))))
	if unit.is_empty():
		problems.append("slot %d: unknown unit id %s" % [index + 1, unit_id])
		return null
	unit["limitburst_level"] = maxi(1, int(slot.get("lb_level", 1)))
	unit["extra_skills"] = _extra_skill_ids(str(slot.get("skills", "")), index)
	var overrides: Dictionary = parse_stat_overrides(str(slot.get("stats", "")), problems)
	var member: Combatant = builder.party_member(unit, overrides)
	var esper_id: int = int(slot.get("esper", 0))
	var esper_rank: int = maxi(1, int(slot.get("esper_rank", 1)))
	if esper_id > 0 and not builder.assign_esper(member, esper_id, esper_rank):
		problems.append("slot %d: esper %d has no rank %d" % [index + 1, esper_id, esper_rank])
	return member


## The slot's extra skill ids that name a spell, an ability or a passive. StatCalculator
## gives them to the unit for this battle (source "Extra"): actives join its skill list,
## passives count like its own (counters, casts, stats...). Unknown ids are reported.
func _extra_skill_ids(text: String, index: int) -> PackedStringArray:
	var errors: Array[String] = []
	var ids: PackedStringArray = parse_skill_ids(text, errors)
	for error in errors:
		problems.append("slot %d: %s" % [index + 1, error])
	var known := PackedStringArray()
	for id in ids:
		if GameDatabase.classify_skill_id(id) in ["magic", "ability", "passive"]:
			known.append(id)
		else:
			problems.append("slot %d: unknown skill id %s" % [index + 1, id])
	return known


## "200150, 20010 503330" -> ["200150", "20010", "503330"]. Anything that is not a whole
## number is reported to `errors` and skipped.
static func parse_skill_ids(text: String, errors: Array[String] = []) -> PackedStringArray:
	var out: PackedStringArray = []
	for token in text.replace(",", " ").replace(";", " ").split(" ", false):
		var id: String = token.strip_edges()
		if id.is_valid_int() and int(id) > 0:
			out.append(str(int(id)))
		elif id != "":
			errors.append("\"%s\" is not a skill id" % id)
	return out


## The espers a party slot can take: { id (beastId), name }, in the game's order.
static func esper_choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in GameDatabase.get_all_esper():
		out.append({"id": int(row.get("beastId", 0)), "name": str(row.get("esperName", ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


## "ATK=1000 hp:5000, MAG 300" -> { ATK: 1000, HP: 5000, MAG: 300 }. Keys other than
## HP, MP, ATK, DEF, MAG and SPR are reported to `errors` and skipped.
static func parse_stat_overrides(text: String, errors: Array[String] = []) -> Dictionary:
	var out: Dictionary = {}
	var pattern := RegEx.create_from_string("([A-Za-z]+)\\s*[=:]?\\s*(-?\\d+)")
	for found in pattern.search_all(text):
		var key: String = found.get_string(1).to_upper()
		if STAT_KEYS.has(key):
			out[key] = int(found.get_string(2))
		else:
			errors.append("unknown stat \"%s\"" % found.get_string(1))
	return out


## Monster ids from "302001000, 302001000" or "302001000 x3" (also *3), at most
## MAX_ENEMIES. Anything that is not a 9-digit id is reported to `errors`.
static func parse_monster_ids(text: String, errors: Array[String] = []) -> PackedStringArray:
	var out: PackedStringArray = []
	var pattern := RegEx.create_from_string("(\\S+?)(?:\\s*[xX*]\\s*(\\d+))?(?:[\\s,;]+|$)")
	for found in pattern.search_all(text.strip_edges()):
		var id: String = found.get_string(1)
		if id == "":
			continue
		if id.length() != 9 or not id.is_valid_int():
			errors.append("\"%s\" is not a 9-digit monster id" % id)
			continue
		var count: int = int(found.get_string(2)) if found.get_string(2) != "" else 1
		for _i in range(maxi(1, count)):
			if out.size() >= MAX_ENEMIES:
				errors.append("more than %d enemies; the rest are left out" % MAX_ENEMIES)
				return out
			out.append(id)
	return out


# === Enemy behaviour ===

## Switches `foe` between its built brain (its AI script, or the basic attacker when it
## has none), a basic attack every turn and passing. Takes effect from the enemy's next
## decision.
static func set_behaviour(foe: Combatant, behaviour: StringName) -> void:
	if not foe.meta.has(META_BUILT_BRAIN):
		foe.meta[META_BUILT_BRAIN] = foe.brain
	match behaviour:
		BEHAVIOUR_ATTACK:
			foe.brain = EnemyBrain.new()
		BEHAVIOUR_PASS:
			foe.brain = IdleEnemyBrain.new()
		_:
			foe.brain = foe.meta[META_BUILT_BRAIN]


static func behaviour_of(foe: Combatant) -> StringName:
	if foe.brain is IdleEnemyBrain:
		return BEHAVIOUR_PASS
	if foe.meta.has(META_BUILT_BRAIN) and foe.brain != foe.meta[META_BUILT_BRAIN]:
		return BEHAVIOUR_ATTACK
	return BEHAVIOUR_SCRIPTED


static func has_ai_script(foe: Combatant) -> bool:
	var built: Variant = foe.meta.get(META_BUILT_BRAIN, foe.brain)
	return built is ScriptedEnemyBrain


# === Command menu ===

## What a party member can be told to do: { label, command, tooltip, unsupported,
## multicast_count }. Attack, Defend, the limit burst, the esper, then magic and abilities
## from its profile (as the old battle UI's skill menu lists them), the multicast
## commands its passives give, and the skills it holds through grants (op 100, labelled
## with their turns and uses left), each once. `unsupported` counts effects the engine cannot
## run yet; `multicast_count` is how many skills a multicast command picks (0 otherwise;
## the unit card then shows a row per pick).
static func command_options(engine: BattleEngine, unit: Combatant) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	options.append(_option("Attack", BattleCommand.attack(), unit.attack_skill, engine))
	options.append({"label": "Defend", "command": BattleCommand.defend(), "tooltip": "Halves damage taken until the next turn", "unsupported": 0})
	if unit.limit_burst_id != "":
		var limit_burst: BattleSkill = engine.catalog.get_limit_burst(unit.limit_burst_id, unit.limit_burst_level)
		if limit_burst != null:
			var label: String = "LB: %s (%.1f crystals)" % [limit_burst.name, float(limit_burst.lb_cost) / 100.0]
			options.append(_option(label, BattleCommand.limit_burst(unit.limit_burst_id), limit_burst, engine))
	if unit.esper_skill_id != "":
		var esper: BattleSkill = engine.catalog.get_skill(BattleSkill.KIND_ESPER, unit.esper_skill_id)
		if esper != null:
			var label: String = "Evoke: %s (rank %d, %d orbs)" % [esper.name, int(esper.record.get("rank", 0)), engine.rules.esper_gauge_max]
			options.append(_option(label, BattleCommand.evoke(), esper, engine))
	var skills: Dictionary = unit.profile.get("skills", {})
	var seen: Dictionary = {}
	for kind in [BattleSkill.KIND_MAGIC, BattleSkill.KIND_ABILITY]:
		for entry in skills.get(str(kind), []):
			if not entry is Dictionary:
				continue
			var id: String = str(int(entry.get("id", 0)))
			var key: String = "%s:%s" % [kind, id]
			if seen.has(key):
				continue
			seen[key] = true
			var skill: BattleSkill = engine.catalog.get_skill(kind, id)
			if skill == null:
				options.append({"label": "(unknown %s %s)" % [kind, id], "command": BattleCommand.skill(kind, id), "tooltip": "", "unsupported": 0})
				continue
			options.append(_skill_option(kind, id, skill, engine, unit))
	for command_id in unit.passives.multicast_commands:
		var key: String = "%s:%s" % [BattleSkill.KIND_ABILITY, command_id]
		var command_skill: BattleSkill = engine.catalog.get_skill(BattleSkill.KIND_ABILITY, command_id)
		if seen.has(key) or command_skill == null:
			continue
		seen[key] = true
		options.append(_skill_option(BattleSkill.KIND_ABILITY, command_id, command_skill, engine, unit))
	for grant in engine.grants_of(unit.id):
		var granted_skill: BattleSkill = engine.catalog.get_skill(grant.skill_kind, grant.skill_id)
		if seen.has(grant.key()) or granted_skill == null:
			continue
		seen[grant.key()] = true
		var option: Dictionary = _skill_option(grant.skill_kind, grant.skill_id, granted_skill, engine, unit)
		option["label"] = "%s  [granted: %s]" % [option["label"], grant_text(grant)]
		options.append(option)
	return options


## How long a grant lasts, for labels: "1 turn, 1 use", "no time limit, unlimited uses".
static func grant_text(grant: SkillGrant) -> String:
	var turns: String = "no time limit" if grant.turns_left == SkillGrant.UNLIMITED else "%d turn%s" % [grant.turns_left, "" if grant.turns_left == 1 else "s"]
	var uses: String = "unlimited uses" if grant.uses_left == SkillGrant.UNLIMITED else "%d use%s" % [grant.uses_left, "" if grant.uses_left == 1 else "s"]
	return "%s, %s" % [turns, uses]


## A magic or ability option, its label carrying its costs and, for a multicast command,
## how many skills it picks for `unit`.
static func _skill_option(kind: StringName, id: String, skill: BattleSkill, engine: BattleEngine, unit: Combatant) -> Dictionary:
	var cost: String = "  MP %d" % skill.mp_cost if skill.mp_cost > 0 else ""
	if skill.lb_cost > 0:
		cost += "  LB %.1f" % (float(skill.lb_cost) / 100.0)
	if skill.orb_cost > 0:
		cost += "  orbs %d" % skill.orb_cost
	var command: BattleCommand = BattleCommand.skill(kind, id)
	var rule: Multicast.Rule = engine.multicast_rule(unit.id, command)
	if rule != null:
		cost += "  [multicast x%d]" % rule.count
	var option: Dictionary = _option("%s%s" % [skill.name, cost], command, skill, engine)
	option["multicast_count"] = rule.count if rule != null else 0
	return option


static func _option(label: String, command: BattleCommand, skill: BattleSkill, engine: BattleEngine) -> Dictionary:
	var unsupported: Array[SkillEffect] = engine.unsupported_effects(skill)
	var shown: String = label if unsupported.is_empty() else "%s  [%d unsupported]" % [label, unsupported.size()]
	return {"label": shown, "command": command, "tooltip": describe_skill(skill, unsupported), "unsupported": unsupported.size()}


## One line per effect: type, opcode, target, hits and the frame they land on.
static func describe_skill(skill: BattleSkill, unsupported: Array[SkillEffect] = []) -> String:
	if skill == null:
		return ""
	var lines: PackedStringArray = ["%s %s:%s" % [skill.name, skill.kind, skill.id]]
	for effect in skill.effects:
		var flag: String = "  (not run yet)" if unsupported.has(effect) else ""
		lines.append("  %s op %d, area %d target %d, %d hit(s) at %s%s" % [
			effect.type if effect.type != "" else "?", effect.opcode, effect.target_area, effect.target_type,
			effect.hit_frames.size(), Array(effect.hit_frames), flag,
		])
	return "\n".join(lines)


## Matches a command to an option: same kind and skill.
static func command_key(command: BattleCommand) -> String:
	if command == null:
		return command_key(BattleCommand.attack())
	return "%d:%s:%s" % [command.kind, command.skill_kind, command.skill_id]


# === Unit and monster search ===

## Units whose name contains `query` or whose unit or series id is `query`, one entry
## per series: { series, name, rows: [{ unit_id, rarity, max_lv, max_lb_lv }] }. Exact
## names first, then prefixes, then the rest.
static func search_units(query: String, limit: int = 40) -> Array[Dictionary]:
	_load_units()
	var needle: String = query.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	if needle == "":
		return out
	var direct: Dictionary = _units_by_id.get(needle, {})
	var by_series: Dictionary = {}
	var ranks: Dictionary = {}
	for row in _units:
		var series: String = str(row.get("unitSeries", ""))
		var unit_name: String = str(row.get("unitName", ""))
		var lower: String = unit_name.to_lower()
		var rank: int = -1
		if not direct.is_empty() and series == str(direct.get("unitSeries", "")):
			rank = 0
		elif lower == needle:
			rank = 1
		elif lower.begins_with(needle):
			rank = 2
		elif lower.contains(needle):
			rank = 3
		if rank < 0:
			continue
		if not by_series.has(series):
			by_series[series] = {"series": series, "name": unit_name, "rows": []}
			ranks[series] = rank
		(by_series[series]["rows"] as Array).append(_row_summary(row))
	var series_ids: Array = by_series.keys()
	series_ids.sort_custom(func(a: String, b: String) -> bool:
		return ranks[a] < ranks[b] or (ranks[a] == ranks[b] and a < b)
	)
	for series in series_ids.slice(0, limit):
		out.append(by_series[series])
	return out


## The rows of the series `unit_id` belongs to, lowest rarity first. [] for an unknown id.
static func series_rows(unit_id: String) -> Array[Dictionary]:
	_load_units()
	var out: Array[Dictionary] = []
	var unit: Dictionary = _units_by_id.get(unit_id.strip_edges(), {})
	if unit.is_empty():
		return out
	var series: String = str(unit.get("unitSeries", ""))
	for row in _units:
		if str(row.get("unitSeries", "")) == series:
			out.append(_row_summary(row))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["unit_id"]) < str(b["unit_id"]))
	return out


static func unit_name(unit_id: String) -> String:
	_load_units()
	return str((_units_by_id.get(unit_id.strip_edges(), {}) as Dictionary).get("unitName", ""))


## { monsterId, name, level, hp } rows whose name contains `query`.
static func search_monsters(query: String, limit: int = 50) -> Array:
	if query.strip_edges() == "":
		return []
	return GameDatabase.search_monsters(query.strip_edges(), limit)


## The setup form's preview of the enemies: per wave (headed "Wave n" when there is
## more than one), a line per monster, or per battle group slot, or a note for a
## lottery pool. `mode` is an ENEMY_MODE_* value and `value` the field's text.
static func describe_enemies(mode: String, value: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var waves: Array[PackedStringArray] = []
	if mode == ENEMY_MODE_MISSION:
		if value.strip_edges() == "":
			return lines
		var plan: Array = EncounterResolver.build_wave_plan(value.strip_edges())
		if plan.is_empty():
			lines.append("(no wave plan for this mission)")
			return lines
		for entry in plan:
			var target_id: String = str(entry.get("target_id", ""))
			var wave_lines: PackedStringArray = ["target %s" % target_id]
			wave_lines.append_array(describe_battle_group(target_id))
			waves.append(wave_lines)
	else:
		for text in split_waves(value):
			var wave_lines: PackedStringArray = []
			if mode == ENEMY_MODE_MONSTERS:
				var errors: Array[String] = []
				for instance_id in parse_monster_ids(text, errors):
					var described: String = describe_monster(instance_id)
					wave_lines.append("%s  %s" % [instance_id, described if described != "" else "(unknown id)"])
				wave_lines.append_array(PackedStringArray(errors))
			else:
				wave_lines.append_array(describe_battle_group(text))
			waves.append(wave_lines)
	for i in range(waves.size()):
		if waves.size() > 1:
			lines.append("Wave %d" % (i + 1))
		for line in waves[i]:
			lines.append(("  " if waves.size() > 1 else "") + line)
	return lines


## "Zu Lv 5, 3000 HP" for a monster id, or "" when unknown.
static func describe_monster(instance_id: String) -> String:
	var parts: Dictionary = GameDatabase.get_monster_parts(instance_id)
	if parts.is_empty():
		return ""
	var monster_name: String = GameDatabase.get_monster_name(str(parts.get("dictionaryId", "")))
	if monster_name == "":
		monster_name = str(parts.get("name", "?"))
	return "%s Lv %d, %d HP" % [monster_name, int(parts.get("level", 0)), int(parts.get("hp", 0))]


## One line per monster of a battle group, reinforcements marked (the battle starts
## with the initially shown ones only). A lottery pool id resolves to a random group
## when the battle is built, so it gets a note instead.
static func describe_battle_group(group_id: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	if not GameDatabase.has_battle_group(group_id):
		if GameDatabase.get_lottery_pool(group_id).is_empty():
			lines.append("(not a battle group)")
		else:
			lines.append("(a lottery pool: the battle picks one of its groups at random)")
		return lines
	var rows: Array = GameDatabase.get_battle_group(group_id)
	# EncounterResolver takes every slot when none is initially shown.
	var any_shown: bool = rows.any(func(row: Dictionary) -> bool: return str(row.get("initialDisp", "1")) != "0")
	for row in rows:
		var instance_id: String = str(row.get("monsterId", ""))
		var reinforcement: bool = any_shown and str(row.get("initialDisp", "1")) == "0"
		lines.append("%s  %s%s" % [instance_id, describe_monster(instance_id), "  (reinforcement, left out)" if reinforcement else ""])
	return lines


static func _row_summary(row: Dictionary) -> Dictionary:
	return {
		"unit_id": str(row.get("unitId", "")),
		"rarity": int(row.get("rare", 1)),
		"max_lv": maxi(1, int(row.get("maxLv", 1))),
		"max_lb_lv": maxi(1, int(row.get("maxLimitBurstLv", 1))),
	}


static func _load_units() -> void:
	if not _units.is_empty():
		return
	_units = GameDatabase.get_all_units()
	for row in _units:
		_units_by_id[str(row.get("unitId", ""))] = row

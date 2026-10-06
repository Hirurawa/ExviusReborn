extends VBoxContainer

## Shows one combatant in full (stats, resistances, statuses, skill limits, commands)
## and offers live edits of its pools, stats, element resistances and ailments. Edits go
## out as edit_requested; the sandbox applies them with BattleEngine.debug_edit.

signal edit_requested(target_id: int, field: StringName, value: int, key: String)

const LIMIT: int = 999999999
## [caption, field, key] per editable value.
const EDITS: Array = [
	["HP", &"hp", ""], ["Max HP", &"max_hp", ""], ["MP", &"mp", ""], ["Max MP", &"max_mp", ""],
	["LB (1/100 crystal)", &"lb", ""], ["Esper orbs (party)", &"orbs", ""],
	["ATK", &"stat", "ATK"], ["DEF", &"stat", "DEF"], ["MAG", &"stat", "MAG"], ["SPR", &"stat", "SPR"],
]
const HEADING_COLOR := Color(1.0, 0.85, 0.3)
## Turns an ailment toggled on here lasts if it is stop, charm or berserk (the others
## last as their rules say).
const AILMENT_TOGGLE_TURNS: int = 3

var _engine: BattleEngine = null
var _fighter_id: int = -1

var _title := Label.new()
var _info := Label.new()
var _details := Label.new()
var _edit_box := VBoxContainer.new()
## [field, key, current value Label, SpinBox] per edit row.
var _edit_rows: Array = []
## Ailment key -> its toggle Button.
var _ailment_toggles: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_title.add_theme_font_size_override("font_size", 16)
	add_child(_title)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 12)
	add_child(_info)

	add_child(_heading("Live edits"))
	add_child(_edit_box)
	var quick := HBoxContainer.new()
	_edit_box.add_child(quick)
	quick.add_child(_button("Full HP", func() -> void: _quick(&"hp", "", func(f: Combatant) -> int: return f.max_hp)))
	quick.add_child(_button("Full MP", func() -> void: _quick(&"mp", "", func(f: Combatant) -> int: return f.max_mp)))
	quick.add_child(_button("Full LB", func() -> void: _quick(&"lb", "", func(f: Combatant) -> int: return f.max_lb)))
	quick.add_child(_button("Full orbs", func() -> void: _quick(&"orbs", "", func(_f: Combatant) -> int: return _engine.rules.esper_gauge_max)))
	quick.add_child(_button("KO", func() -> void: _quick(&"hp", "", func(_f: Combatant) -> int: return 0)))

	var grid := GridContainer.new()
	grid.columns = 4
	_edit_box.add_child(grid)
	for header in ["", "now", "set to", ""]:
		var label := Label.new()
		label.text = header
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if header == "now" else HORIZONTAL_ALIGNMENT_LEFT
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		grid.add_child(label)
	var rows: Array = EDITS.duplicate()
	for element in DamageFormula.ELEMENT_NAMES:
		rows.append(["%s resist" % element.capitalize(), &"element_resist", element])
	for entry in rows:
		var caption := Label.new()
		caption.text = str(entry[0])
		grid.add_child(caption)
		var current := Label.new()
		current.custom_minimum_size.x = 80
		current.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		current.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		grid.add_child(current)
		var spin := SpinBox.new()
		spin.min_value = -LIMIT if entry[1] == &"element_resist" else 0
		spin.max_value = LIMIT
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(spin)
		var field: StringName = entry[1]
		var key: String = entry[2]
		grid.add_child(_button("Set", func() -> void: _emit_edit(field, key, int(spin.value))))
		_edit_rows.append([field, key, current, spin])

	var ailments := HFlowContainer.new()
	ailments.tooltip_text = "Inflict or cure without a roll. Stop, charm and berserk last %d turns." % AILMENT_TOGGLE_TURNS
	_edit_box.add_child(ailments)
	for ailment in StatusBehaviorRegistry.shared().ailment_keys():
		var toggle := Button.new()
		toggle.text = ailment.capitalize()
		toggle.toggle_mode = true
		toggle.add_theme_font_size_override("font_size", 12)
		var key: String = ailment
		toggle.toggled.connect(func(on: bool) -> void: _emit_edit(&"ailment", key, AILMENT_TOGGLE_TURNS if on else 0))
		ailments.add_child(toggle)
		_ailment_toggles[ailment] = toggle

	add_child(_heading("Details"))
	_details.add_theme_font_size_override("font_size", 12)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_details)
	show_combatant(null, -1)


## Shows `fighter_id` from `engine` (-1 for nobody) and loads its values into the edit
## fields.
func show_combatant(engine: BattleEngine, fighter_id: int) -> void:
	_engine = engine
	_fighter_id = fighter_id
	_load_edit_values()
	refresh()


func refresh() -> void:
	var fighter: Combatant = _engine.combatant(_fighter_id) if _engine != null else null
	_edit_box.visible = fighter != null
	if fighter == null:
		_title.text = "Nothing selected"
		_info.text = "Click a combatant's card to inspect it."
		_details.text = ""
		return
	_title.text = "%s#%d" % [fighter.name, fighter.id]
	_info.text = _info_text(fighter)
	for row in _edit_rows:
		(row[2] as Label).text = str(_value_of(fighter, row[0], row[1]))
	for ailment in _ailment_toggles:
		(_ailment_toggles[ailment] as Button).set_pressed_no_signal(fighter.has_ailment(ailment))
	_details.text = _details_text(_engine, fighter)


func _load_edit_values() -> void:
	var fighter: Combatant = _engine.combatant(_fighter_id) if _engine != null else null
	if fighter == null:
		return
	for row in _edit_rows:
		(row[3] as SpinBox).value = _value_of(fighter, row[0], row[1])


func _emit_edit(field: StringName, key: String, value: int) -> void:
	if _fighter_id < 0:
		return
	edit_requested.emit(_fighter_id, field, value, key)
	_load_edit_values()
	refresh()


func _quick(field: StringName, key: String, value_of: Callable) -> void:
	var fighter: Combatant = _engine.combatant(_fighter_id) if _engine != null else null
	if fighter != null:
		_emit_edit(field, key, int(value_of.call(fighter)))


func _value_of(fighter: Combatant, field: StringName, key: String) -> int:
	match field:
		&"orbs":
			return _engine.esper_orbs if _engine != null else 0
		&"hp":
			return fighter.hp
		&"max_hp":
			return fighter.max_hp
		&"mp":
			return fighter.mp
		&"max_mp":
			return fighter.max_mp
		&"lb":
			return fighter.lb
		&"stat":
			return int(fighter.base_stats.get(key, 0))
	return int(fighter.element_resist.get(key, 0))


static func _info_text(fighter: Combatant) -> String:
	var brain: String = ""
	if fighter.brain != null:
		brain = ", brain %s" % ("AI script" if fighter.brain is ScriptedEnemyBrain else fighter.brain.get_script().resource_path.get_file().get_basename())
	return "%s slot %d, Lv %d, source %s, template %s, races %s%s%s" % [
		"Party" if fighter.is_party() else "Enemy", fighter.slot + 1, fighter.level, fighter.source_id,
		fighter.template_id, Array(fighter.races), ", boss" if fighter.is_boss else "", brain,
	]


static func _details_text(engine: BattleEngine, fighter: Combatant) -> String:
	var lines: PackedStringArray = []
	lines.append("Stats (profile / raw base / now):")
	for stat_name in ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]:
		lines.append("  %s  %d / %d / %d" % [stat_name, int(fighter.base_stats.get(stat_name, 0)), int(fighter.raw_stats.get(stat_name, 0)), fighter.stat(stat_name)])
	var elements: PackedStringArray = []
	for element in DamageFormula.ELEMENT_NAMES:
		elements.append("%s %d" % [element.substr(0, 3), fighter.element_resistance(element)])
	lines.append("Elements (with statuses): " + "  ".join(elements))
	var ailments: PackedStringArray = []
	for ailment in Combatant.AILMENTS:
		ailments.append("%s %d" % [ailment.substr(0, 4), fighter.ailment_resistance(ailment)])
	lines.append("Ailments: " + "  ".join(ailments))
	var debuffs: PackedStringArray = []
	for debuff in Combatant.DEBUFF_KEYS:
		debuffs.append("%s %d" % [debuff, fighter.debuff_resistance(debuff)])
	lines.append("Debuff resist: " + "  ".join(debuffs))
	lines.append("Damage resist: physical %d  magic %d" % [fighter.physical_resist, fighter.magic_resist])
	if not fighter.weapon_inflicts.is_empty():
		var inflicts: PackedStringArray = []
		for ailment in Combatant.AILMENTS:
			if fighter.weapon_inflicts.has(ailment):
				inflicts.append("%s %d%%" % [ailment.substr(0, 4), int(fighter.weapon_inflicts[ailment])])
		lines.append("Weapon inflicts (physical hits): " + "  ".join(inflicts))
	if not fighter.weapon_elements.is_empty():
		var weapon_elements: PackedStringArray = []
		for element in fighter.weapon_elements:
			weapon_elements.append(DamageFormula.element_name(element))
		lines.append("Weapon elements (physical hits): " + ", ".join(weapon_elements))
	if fighter.weapon_variance_min != 100 or fighter.weapon_variance_max != 100:
		lines.append("Weapon variance (every formula hit): %d-%d%%" % [fighter.weapon_variance_min, fighter.weapon_variance_max])
	if fighter.is_dual_wielding():
		var total: int = fighter.stat("ATK")
		lines.append("Dual wield: right hand ATK %d, left hand ATK %d (weapons %d + %d)" % [
			total - fighter.hand_atk[DualWield.LEFT], total - fighter.hand_atk[DualWield.RIGHT],
			fighter.hand_atk[DualWield.RIGHT], fighter.hand_atk[DualWield.LEFT],
		])
	lines.append("Chain as target: %d, x%.2f, last hit f%d from #%d" % [
		fighter.chain_count, fighter.chain_percent / 100.0, fighter.chain_last_frame, fighter.chain_last_source,
	] if fighter.chain_count > 0 else "Chain as target: none")
	var passive_lines: PackedStringArray = fighter.passives.describe()
	lines.append("Passives:" if not passive_lines.is_empty() else "Passives: none")
	for line in passive_lines:
		lines.append("  " + line)
	lines.append("Statuses:" if not fighter.statuses.is_empty() else "Statuses: none")
	for status in fighter.statuses:
		lines.append("  %s, from #%d %s" % [status.describe(), status.source_id, status.skill_id])
	if not fighter.skill_state.is_empty():
		lines.append("Skill limits: %s" % fighter.skill_state)
	var grants: Array[SkillGrant] = engine.grants_of(fighter.id)
	lines.append("Grants:" if not grants.is_empty() else "Grants: none")
	for grant in grants:
		var skill: BattleSkill = engine.catalog.get_skill(grant.skill_kind, grant.skill_id)
		lines.append("  %s (%s:%s): %s, from #%d %s" % [
			skill.name if skill != null else "?", grant.skill_kind, grant.skill_id,
			SandboxBattleFactory.grant_text(grant), grant.granted_by, grant.source_skill_id,
		])
	lines.append("History: %s" % fighter.history.describe())
	if not fighter.counter_uses.is_empty():
		lines.append("Counters this turn: %s" % fighter.counter_uses)
	var queued: PackedStringArray = []
	for reaction in engine.queued_reactions():
		if reaction.actor_id == fighter.id:
			queued.append(reaction.describe())
	if not queued.is_empty():
		lines.append("Queued reactions: " + ", ".join(queued))
	var jump: Dictionary = engine.jump_of(fighter.id)
	if not jump.is_empty():
		var jump_skill: BattleSkill = engine.catalog.get_skill(StringName(jump["skill_kind"]), str(jump["skill_id"]))
		var when: String = "lands on turn %d" % int(jump["ready_turn"])
		if bool(jump["manual"]):
			when = "ready to land" if bool(jump["ready"]) else "can land from turn %d" % int(jump["ready_turn"])
		lines.append("In the air: %s, %s" % [jump_skill.name if jump_skill != null else str(jump["skill_id"]), when])
	var delayed: PackedStringArray = []
	for entry in engine.pending_delays():
		if entry.actor_id == fighter.id:
			delayed.append("%s (%s:%s), turn %d" % [entry.skill.name, entry.skill.kind, entry.skill.id, entry.due_turn])
	if not delayed.is_empty():
		lines.append("Delayed: " + ", ".join(delayed))
	if fighter.is_party():
		lines.append("Queued: %s" % (fighter.queued_command.describe() if fighter.queued_command != null else "(attack)"))
		lines.append("Last: %s" % (fighter.last_command.describe() if fighter.last_command != null else "-"))
		if fighter.limit_burst_id != "":
			lines.append("Limit burst %s at level %d" % [fighter.limit_burst_id, fighter.limit_burst_level])
		if fighter.esper_skill_id != "":
			var esper: BattleSkill = engine.catalog.get_skill(BattleSkill.KIND_ESPER, fighter.esper_skill_id)
			lines.append("Esper %d: %s" % [fighter.esper_id, SandboxBattleFactory.describe_skill(esper, engine.unsupported_effects(esper)).replace("\n", " |")])
		lines.append("Party esper gauge: %d / %d orbs" % [engine.esper_orbs, engine.rules.esper_gauge_max])
	lines.append("Basic attack: %s" % SandboxBattleFactory.describe_skill(fighter.attack_skill, engine.unsupported_effects(fighter.attack_skill)).replace("\n", " |"))
	return "\n".join(lines)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


static func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button

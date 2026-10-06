extends VBoxContainer

## The sandbox's setup form: six party slots (unit, rarity row, level, limit burst
## level, stat overrides, esper and its rank, extra skills), the enemies (battle groups or monster ids, "|" between
## waves, with a name search; or a mission's wave plan) and the seed. get_setup() and
## set_setup() use SandboxBattleFactory's setup dictionary; Start emits it.

signal start_requested(setup: Dictionary)

const MAX_SEED: int = 2147483647
## SandboxBattleFactory.ENEMY_MODE_* values in the order of the mode menu.
const ENEMY_MODES: PackedStringArray = [
	SandboxBattleFactory.ENEMY_MODE_GROUP, SandboxBattleFactory.ENEMY_MODE_MONSTERS, SandboxBattleFactory.ENEMY_MODE_MISSION,
]
## The setup key each mode's text goes to.
const ENEMY_KEYS: PackedStringArray = ["battle_group", "monsters", "mission"]
const MODE_MONSTERS: int = 1


## The widgets of one party slot and the unit rows of its series.
class Slot:
	extends RefCounted
	var name_edit := LineEdit.new()
	var rarity := OptionButton.new()
	var level := SpinBox.new()
	var lb_level := SpinBox.new()
	var stats := LineEdit.new()
	## Item ids are beastIds; 0 is "no esper".
	var esper := OptionButton.new()
	var esper_rank := SpinBox.new()
	## Extra magic, ability or passive ids for the battle (SandboxBattleFactory's `skills`).
	var skills := LineEdit.new()
	var rows: Array[Dictionary] = []


## The highest esper rank in the data; an esper without the chosen rank is reported when
## the battle is built.
const MAX_ESPER_RANK: int = 3

var _slots: Array[Slot] = []
var _espers: Array[Dictionary] = []
var _enemy_mode := OptionButton.new()
var _enemy_value := LineEdit.new()
var _monster_query := LineEdit.new()
var _enemy_preview := Label.new()
var _seed := SpinBox.new()
var _message := Label.new()
var _picker := PopupMenu.new()
## What the open picker offers: "unit" with a slot index, or "monster".
var _picker_kind: String = ""
var _picker_slot: int = -1
var _picker_results: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(_picker)
	_picker.id_pressed.connect(_on_picker_chosen)

	add_child(_heading("Party"))
	_espers = SandboxBattleFactory.esper_choices()
	for index in range(SandboxBattleFactory.PARTY_SLOTS):
		_slots.append(_build_slot(index))

	add_child(_heading("Enemies"))
	var enemy_row := HBoxContainer.new()
	add_child(enemy_row)
	_enemy_mode.add_item("Battle group")
	_enemy_mode.add_item("Monster ids")
	_enemy_mode.add_item("Mission")
	_enemy_mode.item_selected.connect(func(_index: int) -> void: _update_enemy_preview())
	enemy_row.add_child(_enemy_mode)
	_enemy_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_value.placeholder_text = "111050313, or 302001000 x2, 101001000, or a mission id"
	_enemy_value.tooltip_text = "Separate waves with | (battle groups and monster ids)"
	_enemy_value.text_changed.connect(func(_text: String) -> void: _update_enemy_preview())
	enemy_row.add_child(_enemy_value)

	var search_row := HBoxContainer.new()
	add_child(search_row)
	_monster_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_monster_query.placeholder_text = "find a monster by name"
	_monster_query.text_submitted.connect(func(_text: String) -> void: _find_monster())
	search_row.add_child(_monster_query)
	search_row.add_child(_button("Find", _find_monster))

	_enemy_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enemy_preview.add_theme_font_size_override("font_size", 12)
	_enemy_preview.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	add_child(_enemy_preview)

	add_child(_heading("Seed"))
	var seed_row := HBoxContainer.new()
	add_child(seed_row)
	_seed.max_value = MAX_SEED
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed)
	seed_row.add_child(_button("Random", func() -> void: set_seed(randi() % MAX_SEED)))

	var actions := HBoxContainer.new()
	add_child(actions)
	actions.add_child(_button("Test preset", func() -> void: set_setup(SandboxBattleFactory.test_setup())))
	var start := _button("Start battle", func() -> void: start_requested.emit(get_setup()))
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(start)

	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Color(1.0, 0.6, 0.35))
	add_child(_message)


func get_setup() -> Dictionary:
	var party: Array = []
	for slot in _slots:
		var row: Dictionary = _selected_row(slot)
		if row.is_empty():
			party.append({})
			continue
		party.append({
			"unit_id": str(row["unit_id"]),
			"level": int(slot.level.value),
			"lb_level": int(slot.lb_level.value),
			"stats": slot.stats.text.strip_edges(),
			"esper": maxi(0, slot.esper.get_selected_id()),
			"esper_rank": int(slot.esper_rank.value),
			"skills": slot.skills.text.strip_edges(),
		})
	var setup: Dictionary = {
		"party": party,
		"enemy_mode": ENEMY_MODES[_enemy_mode.selected],
		"seed": int(_seed.value),
	}
	for i in range(ENEMY_KEYS.size()):
		setup[ENEMY_KEYS[i]] = _enemy_value.text.strip_edges() if i == _enemy_mode.selected else ""
	return setup


func set_setup(setup: Dictionary) -> void:
	var party: Array = setup.get("party", [])
	for index in range(_slots.size()):
		var entry: Variant = party[index] if index < party.size() else {}
		var slot: Slot = _slots[index]
		if not entry is Dictionary or str((entry as Dictionary).get("unit_id", "")) == "":
			_clear_slot(slot)
			continue
		var unit_id: String = str(entry["unit_id"])
		var rows: Array[Dictionary] = SandboxBattleFactory.series_rows(unit_id)
		if rows.is_empty():
			_clear_slot(slot)
			continue
		_apply_series(slot, rows, unit_id)
		slot.level.value = int(entry.get("level", 1))
		slot.lb_level.value = int(entry.get("lb_level", 1))
		slot.stats.text = str(entry.get("stats", ""))
		slot.esper.select(maxi(0, slot.esper.get_item_index(int(entry.get("esper", 0)))))
		slot.esper_rank.value = int(entry.get("esper_rank", 1))
		slot.skills.text = str(entry.get("skills", ""))
	var mode: int = maxi(0, ENEMY_MODES.find(str(setup.get("enemy_mode", ""))))
	_enemy_mode.select(mode)
	_enemy_value.text = str(setup.get(ENEMY_KEYS[mode], ""))
	set_seed(int(setup.get("seed", 0)))
	_update_enemy_preview()


func set_seed(value: int) -> void:
	_seed.value = value


func show_message(text: String) -> void:
	_message.text = text


# === Party slots ===

func _build_slot(index: int) -> Slot:
	var slot := Slot.new()
	var panel := PanelContainer.new()
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	var number := Label.new()
	number.text = "%d" % (index + 1)
	number.custom_minimum_size.x = 14
	top.add_child(number)
	slot.name_edit.placeholder_text = "unit name or id"
	slot.name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.name_edit.text_submitted.connect(func(_text: String) -> void: _find_unit(index))
	top.add_child(slot.name_edit)
	top.add_child(_button("Find", func() -> void: _find_unit(index)))
	top.add_child(_button("X", func() -> void: _clear_slot(slot)))

	var middle := HBoxContainer.new()
	box.add_child(middle)
	slot.rarity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.rarity.fit_to_longest_item = false
	slot.rarity.item_selected.connect(func(_index: int) -> void: _on_rarity_changed(slot))
	middle.add_child(slot.rarity)
	middle.add_child(_caption("Lv"))
	slot.level.min_value = 1
	middle.add_child(slot.level)
	middle.add_child(_caption("LB"))
	slot.lb_level.min_value = 1
	middle.add_child(slot.lb_level)

	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	bottom.add_child(_caption("Stats"))
	slot.stats.placeholder_text = "overrides, e.g. ATK=1000 HP=50000"
	slot.stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(slot.stats)

	var esper_row := HBoxContainer.new()
	box.add_child(esper_row)
	esper_row.add_child(_caption("Esper"))
	slot.esper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.esper.fit_to_longest_item = false
	slot.esper.tooltip_text = "The esper this unit evokes (evocation only: its stat bonus and board are not applied)"
	slot.esper.add_item("(no esper)", 0)
	for esper in _espers:
		slot.esper.add_item(str(esper["name"]), int(esper["id"]))
	esper_row.add_child(slot.esper)
	esper_row.add_child(_caption("Rank"))
	slot.esper_rank.min_value = 1
	slot.esper_rank.max_value = MAX_ESPER_RANK
	esper_row.add_child(slot.esper_rank)

	var skills_row := HBoxContainer.new()
	box.add_child(skills_row)
	skills_row.add_child(_caption("Skills"))
	slot.skills.placeholder_text = "extra skill ids, e.g. 200150 20010 (Dualcast, Fire)"
	slot.skills.tooltip_text = "Magic, ability or passive ids this unit gets for the battle (passives count like its own: counters, battle-start casts...)"
	slot.skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_row.add_child(slot.skills)
	_clear_slot(slot)
	return slot


func _find_unit(index: int) -> void:
	var slot: Slot = _slots[index]
	var query: String = slot.name_edit.text.strip_edges()
	if query == "":
		return
	var direct: Array[Dictionary] = []
	if query.is_valid_int():
		direct = SandboxBattleFactory.series_rows(query)
	if not direct.is_empty():
		_apply_series(slot, direct, query)
		return
	var found: Array[Dictionary] = SandboxBattleFactory.search_units(query)
	if found.is_empty():
		show_message("No unit matches \"%s\"." % query)
	elif found.size() == 1:
		_apply_series(slot, _rows_of(found[0]), "")
	else:
		_picker.clear()
		for i in range(found.size()):
			var rows: Array = found[i]["rows"]
			var rarities: String = "R%d" % int(rows[0]["rarity"]) if rows.size() == 1 else "R%d-%d" % [int(rows[0]["rarity"]), int(rows[-1]["rarity"])]
			_picker.add_item("%s  (%s, %s)" % [found[i]["name"], found[i]["series"], rarities], i)
		_open_picker("unit", index, found, slot.name_edit)


func _apply_series(slot: Slot, rows: Array[Dictionary], unit_id: String) -> void:
	slot.rows = rows
	slot.rarity.clear()
	var chosen: int = rows.size() - 1
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		slot.rarity.add_item("R%d  %s  (max Lv %d)" % [int(row["rarity"]), row["unit_id"], int(row["max_lv"])], i)
		if str(row["unit_id"]) == unit_id:
			chosen = i
	slot.rarity.disabled = false
	slot.rarity.select(chosen)
	slot.name_edit.text = SandboxBattleFactory.unit_name(str(rows[chosen]["unit_id"]))
	_on_rarity_changed(slot)
	slot.level.value = slot.level.max_value
	slot.lb_level.value = slot.lb_level.max_value


func _on_rarity_changed(slot: Slot) -> void:
	var row: Dictionary = _selected_row(slot)
	if row.is_empty():
		return
	slot.level.max_value = int(row["max_lv"])
	slot.lb_level.max_value = int(row["max_lb_lv"])


func _clear_slot(slot: Slot) -> void:
	slot.rows = []
	slot.name_edit.text = ""
	slot.rarity.clear()
	slot.rarity.add_item("(empty)")
	slot.rarity.disabled = true
	slot.level.max_value = 1
	slot.level.value = 1
	slot.lb_level.max_value = 1
	slot.lb_level.value = 1
	slot.stats.text = ""
	slot.esper.select(0)
	slot.esper_rank.value = 1
	slot.skills.text = ""


static func _selected_row(slot: Slot) -> Dictionary:
	if slot.rows.is_empty() or slot.rarity.selected < 0 or slot.rarity.selected >= slot.rows.size():
		return {}
	return slot.rows[slot.rarity.selected]


static func _rows_of(entry: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in entry.get("rows", []):
		rows.append(row)
	return rows


# === Enemies ===

func _find_monster() -> void:
	var query: String = _monster_query.text.strip_edges()
	if query == "":
		return
	var found: Array = SandboxBattleFactory.search_monsters(query)
	if found.is_empty():
		show_message("No monster matches \"%s\"." % query)
		return
	_picker.clear()
	for i in range(found.size()):
		var row: Dictionary = found[i]
		_picker.add_item("%s  %s  (Lv %d, %d HP)" % [row.get("name", "?"), row.get("monsterId", ""), int(row.get("level", 0)), int(row.get("hp", 0))], i)
	_open_picker("monster", -1, found, _monster_query)


func _add_monster(instance_id: String) -> void:
	if _enemy_mode.selected != MODE_MONSTERS:
		_enemy_mode.select(MODE_MONSTERS)
		_enemy_value.text = ""
	var current: String = _enemy_value.text.strip_edges()
	_enemy_value.text = instance_id if current == "" else "%s, %s" % [current, instance_id]
	_update_enemy_preview()


func _update_enemy_preview() -> void:
	var lines: PackedStringArray = SandboxBattleFactory.describe_enemies(ENEMY_MODES[_enemy_mode.selected], _enemy_value.text)
	_enemy_preview.text = "\n".join(lines)


# === Picker ===

func _open_picker(kind: String, slot_index: int, results: Array, anchor: Control) -> void:
	_picker_kind = kind
	_picker_slot = slot_index
	_picker_results = results
	var rect: Rect2 = anchor.get_global_rect()
	_picker.max_size = Vector2i(maxi(int(rect.size.x), 360), 480)
	_picker.reset_size()
	_picker.position = Vector2i(rect.position + Vector2(0, rect.size.y))
	_picker.popup()


func _on_picker_chosen(id: int) -> void:
	if id < 0 or id >= _picker_results.size():
		return
	if _picker_kind == "unit" and _picker_slot >= 0:
		_apply_series(_slots[_picker_slot], _rows_of(_picker_results[id]), "")
	elif _picker_kind == "monster":
		_add_monster(str(_picker_results[id].get("monsterId", "")))


# === Widgets ===

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	return label


static func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


static func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button

extends Control

@onready var party_name_label: Label = $VBoxContainer/PartyHeaderHBox/PartyNameLabel
@onready var prev_party_btn: Button = $VBoxContainer/PartyHeaderHBox/PrevPartyButton
@onready var next_party_btn: Button = $VBoxContainer/PartyHeaderHBox/NextPartyButton
@onready var pagination_indicators: HBoxContainer = $VBoxContainer/PaginationHBox
@onready var slots_container: HBoxContainer = $VBoxContainer/PartySlotsHBox

@onready var view_units_btn: Button = $VBoxContainer/BottomButtonsGrid/ViewUnitsButton
@onready var awaken_abilities_btn: Button = $VBoxContainer/BottomButtonsGrid/AwakenAbilitiesButton
@onready var enhance_units_btn: Button = $VBoxContainer/BottomButtonsGrid/EnhanceUnitsButton
@onready var awaken_units_btn: Button = $VBoxContainer/BottomButtonsGrid/AwakenUnitsButton

var current_party_index: int = 0
var max_parties: int = 5

var _texture_cache: Dictionary = {}

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _ready() -> void:
	DataManager.parties_updated.connect(_on_parties_updated)
	DataManager.units_updated.connect(_on_units_updated)

	prev_party_btn.pressed.connect(_on_prev_party)
	next_party_btn.pressed.connect(_on_next_party)
	view_units_btn.pressed.connect(_on_view_units)

	_refresh_ui()

func _on_parties_updated(parties: Array) -> void:
	_refresh_ui()

func _on_units_updated(units: Array) -> void:
	_refresh_ui()

func _refresh_ui() -> void:
	var parties: Array = DataManager.parties
	if parties.is_empty():
		return

	if current_party_index >= parties.size():
		current_party_index = parties.size() - 1
	if current_party_index < 0:
		current_party_index = 0

	var party: Dictionary = parties[current_party_index]
	party_name_label.text = party.get("name", "Party")

	_update_pagination()
	_update_slots(party.get("units", []))

func _update_pagination() -> void:
	for i in range(pagination_indicators.get_child_count()):
		var indicator: Label = pagination_indicators.get_child(i) as Label
		if i == current_party_index:
			indicator.text = "●"
		else:
			indicator.text = "○"

func _update_slots(unit_uuids: Array) -> void:
	for i in range(5):
		var slot_btn: Button = slots_container.get_child(i) as Button
		var uuid: Variant = null
		if i < unit_uuids.size():
			uuid = unit_uuids[i]

		var slot_tex: Texture2D = null
		var unit_name: String = ""
		var unit_level: String = ""
		var unit_inst: Dictionary = {}

		if uuid != null and typeof(uuid) == TYPE_STRING and uuid != "":
			unit_inst = _find_unit_inst(uuid)
			if not unit_inst.is_empty():
				var unit_id: String = unit_inst.get("unit_id", "")
				var path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
				if ResourceLoader.exists(path):
					slot_tex = _get_dynamic_texture(path)

				var unit_data: Dictionary = DataManager.game_data_units.get(unit_id, {})
				unit_name = unit_data.get("name", "Unknown")
				unit_level = "Lvl %s" % str(int(unit_inst.get("level", 1)))

		# Update slot visuals
		var tex_rect: TextureRect = slot_btn.get_node("TextureRect") as TextureRect
		tex_rect.texture = slot_tex
		var lbl_name: Label = slot_btn.get_node("NameLabel") as Label
		lbl_name.text = unit_name
		var lbl_lvl: Label = slot_btn.get_node("LevelLabel") as Label
		lbl_lvl.text = unit_level

		# Disconnect old signals
		if slot_btn.pressed.is_connected(_on_slot_clicked):
			slot_btn.pressed.disconnect(_on_slot_clicked)

		slot_btn.pressed.connect(_on_slot_clicked.bind(i, unit_inst))

func _find_unit_inst(uuid: String) -> Dictionary:
	for u in DataManager.owned_units_ids:
		if u is Dictionary and u.get("instance_id") == uuid:
			return u
	return {}

func _on_prev_party() -> void:
	current_party_index -= 1
	if current_party_index < 0:
		current_party_index = max_parties - 1
	_refresh_ui()

func _on_next_party() -> void:
	current_party_index += 1
	if current_party_index >= max_parties:
		current_party_index = 0
	_refresh_ui()

func _on_slot_clicked(slot_index: int, unit_inst: Dictionary) -> void:
	if unit_inst.is_empty():
		UIManager.push("unit_selector_ui", {"mode": "select", "party_index": current_party_index, "slot_index": slot_index})
	else:
		UIManager.push("unit_stats_popup", {"unit_inst": unit_inst, "party_index": current_party_index, "slot_index": slot_index})

func _on_view_units() -> void:
	UIManager.push("unit_selector_ui", {"mode": "view"})

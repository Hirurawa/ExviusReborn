extends Control

const UNIT_SCENE: PackedScene = preload("res://features/shared/Unit.tscn")
const SUBMENU_POPUP: PackedScene = preload("res://features/outgame/units/components/UnitSubmenuPopup.tscn")

@onready var party_name_label: Label = $slot_label
@onready var prev_party_btn: TextureButton = $Pagination/ArrowLeft
@onready var next_party_btn: TextureButton = $Pagination/ArrowRight
@onready var pagination_indicators: HBoxContainer = $Pagination/Mark
@onready var slots_container: HBoxContainer = $HBoxContainer

@onready var view_units_btn: TextureButton = $BottomButtonsGrid/ViewUnitsButton
@onready var awaken_abilities_btn: TextureButton = $BottomButtonsGrid/AwakenAbilitiesButton
@onready var enhance_units_btn: TextureButton = $BottomButtonsGrid/EnhanceUnitsButton
@onready var awaken_units_btn: TextureButton = $BottomButtonsGrid/AwakenUnitsButton

var current_party_index: int = 0

func _ready() -> void:
	prev_party_btn.pressed.connect(_on_prev_party)
	next_party_btn.pressed.connect(_on_next_party)
	
	view_units_btn.pressed.connect(_on_view_units)
	enhance_units_btn.pressed.connect(_on_enhance_units)
	awaken_abilities_btn.pressed.connect(_on_awaken_ability)
	awaken_units_btn.pressed.connect(_on_awaken_units)
	
	PartyService.parties_updated.connect(func(): _refresh_ui())
	current_party_index = PartyService.get_selected_party_index()
	
	for i in range(5):
		var slot_btn = slots_container.get_child(i)
		if slot_btn == null:
			continue
		var pedestal_btn = slot_btn.get_node("unit_pedestal")
		pedestal_btn.pressed.connect(_on_slot_clicked.bind(i))
		var beast_btn = slot_btn.get_node("beast_frame")
		beast_btn.pressed.connect(_on_esper_slot_clicked.bind(i))
	
	_refresh_ui()


func _exit_tree() -> void:
	var changed: bool = PartyService.set_selected_party_index(current_party_index)
	if not changed:
		return

	PartyService.party_save_requested.emit(PartyService.parties.duplicate(true))


func _on_view_units():
	UIManager.push("unit_selector_ui", {"mode": ModeView.new()})


func _on_enhance_units() -> void:
	# Rule: Can only enhance units that aren't max level
	var filter = func(u): return u.get("useType") == 0#.level < u.max_level
	
	UIManager.push("unit_selector_ui", {
		"mode": ModeSelectBase.new("enhance_ui", filter)
	})


func _on_awaken_units() -> void:
	# Rule: Can only awaken units at max level that have a higher rarity available
	var filter = func(u): return u.get("useType") == 0#.level == u.maxLv and u.can_awaken
	
	UIManager.push("unit_selector_ui", {
		"mode": ModeSelectBase.new("awaken_ui", filter)
	})


func _on_awaken_ability() -> void:
	# Rule: Can only select units that actually possess awakenable abilities
	var filter = func(u): return u.get("useType") == 0
	
	UIManager.push("unit_selector_ui", {
		"mode": ModeSelectBase.new("awaken_ability_ui", filter)
	})


func _on_slot_clicked(slot_index: int) -> void:
	var instance_id = PartyService.parties[current_party_index].get("units")[slot_index]
	var unit_inst = UnitService.owned_units_ids.filter(func(x): return x.instance_id == instance_id)
	if unit_inst.is_empty():
		var filter = func(u): return u.get("useType") == 0 && u.get("joinParty") == 1 && not u.instance_id in PartyService.parties[current_party_index].get("units")
		UIManager.push("unit_selector_ui", {
			"mode": ModeSelectPartyMember.new({}, current_party_index, slot_index, filter)
		})
	else:
		var popup: Control = SUBMENU_POPUP.instantiate() as Control
		add_child(popup)
		popup.init_scene({"unit_inst": unit_inst[0], "party_index": current_party_index, "slot_index": slot_index})


func _on_esper_slot_clicked(slot_index: int) -> void:
	var current_summon_id = PartyService.parties[current_party_index].get("espers")[slot_index]
	UIManager.push("espers_ui", {
		"mode": "select",
		"party_index": current_party_index,
		"slot_index": slot_index,
		"current_summon_id": current_summon_id,
		"selection_callback": func(summon_id: String, _summon_name: String): PartyService.assign_esper_to_party(current_party_index, slot_index, summon_id)
	})


func _on_prev_party() -> void:
	if PartyService.parties.is_empty():
		return
	var party_count: int = PartyService.parties.size()
	current_party_index -= 1
	if current_party_index < 0:
		current_party_index = party_count - 1
	_refresh_ui()


func _on_next_party() -> void:
	if PartyService.parties.is_empty():
		return
	var party_count: int = PartyService.parties.size()
	current_party_index += 1
	if current_party_index >= party_count:
		current_party_index = 0
	_refresh_ui()


func _refresh_ui() -> void:
	var parties: Array = PartyService.parties
	var party: Dictionary = parties[current_party_index]
	party_name_label.text = party.get("name", "Party")

	for i in range(pagination_indicators.get_child_count()):
		var indicator: TextureRect = pagination_indicators.get_child(i) as TextureRect
		if i == current_party_index:
			indicator.texture = ResourceLoader.load("res://assets/ui/common/positionmark_on.tres")
		else:
			indicator.texture = ResourceLoader.load("res://assets/ui/common/positionmark_off.tres")
	
	_update_slots(party.get("units", []))
	_update_esper_icons(party.get("espers", []))


func _update_slots(unit_uuids: Array) -> void:
	for i in range(5):
		var slot_btn = slots_container.get_child(i)
		var uuid: Variant = null
		if i < unit_uuids.size():
			uuid = unit_uuids[i]

		var unit_inst: Dictionary = {}
		if uuid != "":
			unit_inst = UnitService.owned_units_ids.filter(func(x): return x.instance_id == uuid)[0]

		var pedestal_btn = slot_btn.get_node("unit_pedestal")
		for c in pedestal_btn.get_children():
			c.queue_free()
		if unit_inst != {}:
			var shared_visual: Control = UNIT_SCENE.instantiate() as Control
			shared_visual.mouse_filter = Control.MOUSE_FILTER_PASS
			pedestal_btn.add_child(shared_visual)
			pedestal_btn.icon = null
			shared_visual.setup(unit_inst)
		else:
			pedestal_btn.icon = ResourceLoader.load("res://assets/ui/unit/unit_charastand_small.tres")


func _update_esper_icons(esper_ids: Array) -> void:
	for i in range(5):
		var slot_btn = slots_container.get_child(i)
		var beast_icon = slot_btn.get_node("beast_icon")

		var summon_id: String = ""
		if i < esper_ids.size():
			summon_id = str(esper_ids[i])

		var icon_tex: Texture2D = null
		if summon_id != "":
			var summon_data: Dictionary = GameDatabase.get_esper(int(summon_id))
			var icon_filename: String = str(summon_data.get("thumImage"))
			var icon_path: String = "res://assets/esper/" + icon_filename
			if ResourceLoader.exists(icon_path):
				icon_tex = ResourceLoader.load(icon_path) as Texture2D
		
		beast_icon.texture = icon_tex

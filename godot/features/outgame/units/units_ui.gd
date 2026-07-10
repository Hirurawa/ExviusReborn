extends Control

const UNIT_SCENE: PackedScene = preload("res://features/shared/Unit.tscn")

const SLOT_FALLBACK_W: float = 128.0
const SLOT_FALLBACK_H: float = 168.0
const SLOT_SIDE_PADDING: float = 4.0
const SLOT_PEDESTAL_BOTTOM_MARGIN: float = 2.0

@onready var back_button: Button = $UnitNamebgChara/UnitMinibutton1

@onready var party_name_label: Label = $slot_label
@onready var prev_party_btn: Button = $PartyHeaderHBox/PrevPartyButton
@onready var next_party_btn: Button = $PartyHeaderHBox/NextPartyButton
@onready var pagination_indicators: HBoxContainer = $PartyHeaderHBox/PaginationHBox
@onready var slots_container: HBoxContainer = $HBoxContainer

@onready var view_units_btn: Button = $BottomButtonsGrid/ViewUnitsButton
@onready var awaken_abilities_btn: Button = $BottomButtonsGrid/AwakenAbilitiesButton
@onready var enhance_units_btn: Button = $BottomButtonsGrid/EnhanceUnitsButton
@onready var awaken_units_btn: Button = $BottomButtonsGrid/AwakenUnitsButton

var current_party_index: int = 0
var max_parties: int = 5

var _texture_cache: Dictionary = {}
var _slot_unit_instances: Array = []
var _slot_summon_ids: Array = []

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _get_pedestal_texture(rarity: int) -> Texture2D:
	var candidate_paths: Array[String] = [
		"res://assets/ui/unit/unit_charastand_rare%s_small.tres" % rarity,
		"res://assets/ui/unit/unit_charastand_small.tres",
	]

	for path in candidate_paths:
		if ResourceLoader.exists(path):
			return _get_dynamic_texture(path)

	return null

func _get_or_create_slot_visual(slot_btn: Button) -> Control:
	var visual_container: Control = slot_btn.get_node_or_null("SharedUnitVisual") as Control
	if visual_container == null:
		visual_container = Control.new()
		visual_container.name = "SharedUnitVisual"
		visual_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		visual_container.clip_contents = true
		visual_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_btn.add_child(visual_container)
		slot_btn.move_child(visual_container, 0)

		var unit_visual: Control = UNIT_SCENE.instantiate() as Control
		if unit_visual != null:
			unit_visual.name = "UnitVisual"
			unit_visual.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
			unit_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
			visual_container.add_child(unit_visual)

		# Hide only the legacy unit portrait layer; keep the legacy pedestal for empty slots.
		var legacy_unit_rect: TextureRect = slot_btn.get_node_or_null("TextureRect") as TextureRect
		if legacy_unit_rect != null:
			legacy_unit_rect.visible = false

	return visual_container

func _get_slot_display_rect(slot_btn: Button) -> Rect2:
	var legacy_pedestal: TextureRect = slot_btn.get_node_or_null("unit_pedestal") as TextureRect
	if legacy_pedestal != null:
		var left: float = legacy_pedestal.offset_left
		var top: float = legacy_pedestal.offset_top
		var width: float = legacy_pedestal.offset_right - legacy_pedestal.offset_left
		var height: float = legacy_pedestal.offset_bottom - legacy_pedestal.offset_top
		return Rect2(left, top, maxf(1.0, width), maxf(1.0, height))

	var fallback_w: float = slot_btn.size.x
	var fallback_h: float = slot_btn.size.y
	if fallback_w <= 0.0:
		fallback_w = SLOT_FALLBACK_W
	if fallback_h <= 0.0:
		fallback_h = SLOT_FALLBACK_H
	return Rect2(0.0, 0.0, fallback_w, fallback_h)

func _set_legacy_pedestal_visible(slot_btn: Button, visibility: bool) -> void:
	for child in slot_btn.get_children():
		if child is TextureRect and String(child.name).begins_with("unit_pedestal"):
			(child as TextureRect).visible = visibility
			return

func _ready() -> void:
	PartyService.parties_updated.connect(_on_parties_updated)
	UnitService.units_updated.connect(_on_units_updated)

	back_button.pressed.connect(_on_back_pressed)
	prev_party_btn.pressed.connect(_on_prev_party)
	next_party_btn.pressed.connect(_on_next_party)
	view_units_btn.pressed.connect(_on_view_units)
	enhance_units_btn.pressed.connect(_on_enhance_units)
	awaken_units_btn.pressed.connect(_on_awaken_units)
	current_party_index = PartyService.get_selected_party_index()
	_initialize_slot_click_data()
	_wire_slot_input_handlers()

	_refresh_ui()

func _initialize_slot_click_data() -> void:
	_slot_unit_instances.resize(5)
	_slot_summon_ids.resize(5)
	for i in range(5):
		_slot_unit_instances[i] = {}
		_slot_summon_ids[i] = ""

func _wire_slot_input_handlers() -> void:
	for i in range(5):
		var slot_btn: Button = slots_container.get_child(i) as Button
		if slot_btn == null:
			continue
		if slot_btn.pressed.is_connected(_on_slot_clicked):
			slot_btn.pressed.disconnect(_on_slot_clicked)
		if not slot_btn.gui_input.is_connected(_on_slot_gui_input):
			slot_btn.gui_input.connect(_on_slot_gui_input.bind(i))

func _exit_tree() -> void:
	_commit_selected_party_on_exit()

func _on_parties_updated() -> void:
	_refresh_ui()

func _on_units_updated(_units: Array) -> void:
	_refresh_ui()

func _on_back_pressed() -> void:
	UIManager.pop()

func _refresh_ui() -> void:
	var parties: Array = PartyService.parties
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
	_update_esper_icons(party.get("espers", []))

func _update_esper_icons(esper_ids: Array) -> void:
	for i in range(5):
		var slot_btn: Button = slots_container.get_child(i) as Button
		if slot_btn == null:
			continue

		var beast_icon: TextureRect = slot_btn.get_node_or_null("beast_icon") as TextureRect
		if beast_icon == null:
			continue

		var summon_id: String = ""
		if i < esper_ids.size():
			summon_id = str(esper_ids[i]).strip_edges()
		_slot_summon_ids[i] = summon_id

		var icon_tex: Texture2D = null
		if summon_id != "":
			icon_tex = _get_summon_icon_texture(summon_id)

		beast_icon.texture = icon_tex

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
		var pedestal_tex: Texture2D = null
		var unit_inst: Dictionary = {}

		if uuid != null and typeof(uuid) == TYPE_STRING and uuid != "":
			unit_inst = _find_unit_inst(uuid)
			if not unit_inst.is_empty():
				var entry_id: String = str(unit_inst.get("unitId"))
				var path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % entry_id
				if ResourceLoader.exists(path):
					slot_tex = _get_dynamic_texture(path)
				pedestal_tex = _get_pedestal_texture(int(unit_inst.get("current_rarity")))

		# Render slot with the shared unit visual so pedestal style matches rarity.
		var shared_visual: Control = _get_or_create_slot_visual(slot_btn)
		var unit_visual: Control = shared_visual.get_node_or_null("UnitVisual") as Control
		var can_render_shared: bool = unit_visual != null and slot_tex != null and pedestal_tex != null
		var display_rect: Rect2 = _get_slot_display_rect(slot_btn)
		shared_visual.position = display_rect.position
		shared_visual.size = display_rect.size
		if slot_btn.get_child(0) != shared_visual:
			slot_btn.move_child(shared_visual, 0)
		shared_visual.visible = can_render_shared
		_set_legacy_pedestal_visible(slot_btn, not can_render_shared)
		if unit_inst != {}:
			unit_visual.setup(unit_inst)
		
		_slot_unit_instances[i] = unit_inst

func _get_summon_display_name(summon_id: String) -> String:
	var summon_data: Dictionary = StaticData.game_data_summons.get(summon_id, {})
	if summon_data.is_empty():
		return "Summon %s" % summon_id

	var names_value: Variant = summon_data.get("names", [])
	if names_value is Array:
		var names_array: Array = names_value
		for name_variant in names_array:
			var candidate: String = str(name_variant).strip_edges()
			if candidate != "":
				return candidate

	return "Summon %s" % summon_id

func _get_summon_icon_texture(summon_id: String) -> Texture2D:
	if summon_id == "":
		return null

	var summon_data: Dictionary = StaticData.game_data_summons.get(summon_id, {})
	if summon_data.is_empty():
		return null

	var icon_filename: String = str(summon_data.get("icon", "")).strip_edges()
	if icon_filename == "":
		return null

	var icon_path: String = "res://assets/esper/" + icon_filename
	if not ResourceLoader.exists(icon_path):
		return null

	return _get_dynamic_texture(icon_path)

func _find_unit_inst(uuid: String) -> Dictionary:
	for u in UnitService.owned_units_ids:
		if u is Dictionary and u.get("instance_id") == uuid:
			return u
	return {}

func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if not (event is InputEventMouseButton):
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if slot_index < 0 or slot_index >= 5:
		return

	var slot_btn: Button = slots_container.get_child(slot_index) as Button
	if slot_btn == null:
		return

	var beast_frame: TextureRect = slot_btn.get_node_or_null("beast_frame") as TextureRect
	if beast_frame == null:
		return

	# Route clicks by vertical zone: top section for unit actions, beast frame section for esper actions.
	if mouse_event.position.y >= beast_frame.offset_top:
		var summon_id: String = str(_slot_summon_ids[slot_index]).strip_edges()
		_on_esper_slot_clicked(slot_index, summon_id)
	else:
		var unit_inst: Dictionary = _slot_unit_instances[slot_index] as Dictionary
		_on_slot_clicked(slot_index, unit_inst)

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

func _commit_selected_party_on_exit() -> void:
	if PartyService.parties.is_empty():
		return

	var changed: bool = PartyService.set_selected_party_index(current_party_index)
	if not changed:
		return

	# Persist only the selected party index at Units root exit.
	PartyService.party_save_requested.emit(PartyService.parties.duplicate(true))

func _on_slot_clicked(slot_index: int, unit_inst: Dictionary) -> void:
	if unit_inst.is_empty():
		var exclude_list: Array = PartyService.get_units_in_party_excluding_slot(current_party_index, slot_index)
		
		# Also exclude material units from party selection
		for unit in UnitService.owned_units_ids:
			if unit is Dictionary and UnitService.is_material_unit(unit):
				var material_instance_id: String = str(unit.get("instance_id", ""))
				if material_instance_id != "" and material_instance_id not in exclude_list:
					exclude_list.append(material_instance_id)
		
		UIManager.push("unit_selector_ui", {
			"mode": "select",
			"party_index": current_party_index,
			"slot_index": slot_index,
			"exclude_list": exclude_list
		})
	else:
		UIManager.push("unit_stats_popup", {"unit_inst": unit_inst, "party_index": current_party_index, "slot_index": slot_index})

func _on_esper_slot_clicked(slot_index: int, current_summon_id: String) -> void:
	UIManager.push("espers_ui", {
		"mode": "select",
		"party_index": current_party_index,
		"slot_index": slot_index,
		"current_summon_id": current_summon_id
	})

func _on_view_units() -> void:
	UIManager.push("unit_selector_ui", {"mode": "view"})

func _on_enhance_units() -> void:
	var exclude_list: Array = []
		
	# Exclude material units
	for unit in UnitService.owned_units_ids:
		if unit is Dictionary and UnitService.is_material_unit(unit):
			var material_instance_id: String = str(unit.get("instance_id", ""))
			if material_instance_id != "" and material_instance_id not in exclude_list:
				exclude_list.append(material_instance_id)
	
	UIManager.push("unit_selector_ui", {
		"mode": "enhance_base_selection",
		"selection_callback": Callable(self, "_on_enhance_base_selected"),
		"exclude_list": exclude_list
	})
	
func _on_awaken_units() -> void:
	var exclude_list: Array = []
		
	# Exclude material units
	for unit in UnitService.owned_units_ids:
		if unit is Dictionary and UnitService.is_material_unit(unit):
			var material_instance_id: String = str(unit.get("instance_id", ""))
			if material_instance_id != "" and material_instance_id not in exclude_list:
				exclude_list.append(material_instance_id)
	
	UIManager.push("unit_selector_ui", {
		"mode": "awaken_base_selection",
		"selection_callback": Callable(self, "_on_awaken_base_selected"),
		"exclude_list": exclude_list
	})

func _on_enhance_base_selected(unit_inst: Dictionary) -> void:
	if unit_inst.is_empty():
		return

	var base_instance_id: String = str(unit_inst.get("instance_id", ""))
	if base_instance_id == "":
		return

	call_deferred("_open_enhance_ui", base_instance_id, unit_inst)

func _on_awaken_base_selected(unit_inst: Dictionary) -> void:
	if unit_inst.is_empty():
		return

	var base_instance_id: String = str(unit_inst.get("instance_id", ""))
	if base_instance_id == "":
		return

	call_deferred("_open_awaken_ui", base_instance_id, unit_inst)

func _open_enhance_ui(base_instance_id: String, unit_inst: Dictionary) -> void:
	UIManager.push("enhance_ui", {
		"base_unit_instance_id": base_instance_id,
		"base_unit_inst": unit_inst
	})

func _open_awaken_ui(base_instance_id: String, unit_inst: Dictionary) -> void:
	UIManager.push("awaken_ui", {
		"base_unit_instance_id": base_instance_id,
		"base_unit_inst": unit_inst
	})

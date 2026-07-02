extends Control

@onready var back_button: Button = $UnitNamebgChara/UnitMinibutton1
@onready var before_stand: TextureRect = $Status/unit_classup_before_stand
@onready var before_unit: TextureRect = $Status/unit_classup_before_unit
@onready var after_stand: TextureRect = $Status/unit_classup_after_stand
@onready var after_unit: TextureRect = $Status/unit_classup_after_unit
@onready var gil_label: Label = $Button/unit_classup_need_money_number
@onready var awaken_button: TextureButton = $Button/unit_classup_button_evo
@onready var enhance_button: TextureButton = $Button/unit_classup_button_mix
@onready var result_text_label: Label = $Button/unit_classup_check_result_text
@onready var before_lv_label: Label = $Status/unit_classup_before_status_offset/before_lvl
@onready var before_hp_label: Label = $Status/unit_classup_before_status_offset/before_hp
@onready var before_mp_label: Label = $Status/unit_classup_before_status_offset/before_mp
@onready var before_atk_label: Label = $Status/unit_classup_before_status_offset/before_atk
@onready var before_def_label: Label = $Status/unit_classup_before_status_offset/before_def
@onready var before_mag_label: Label = $Status/unit_classup_before_status_offset/before_mag
@onready var before_spr_label: Label = $Status/unit_classup_before_status_offset/before_spr
@onready var after_status_offset: Control = $Status/unit_classup_after_status_offset
@onready var after_lv_label: Label = $Status/unit_classup_after_status_offset/after_lvl
@onready var after_hp_label: Label = $Status/unit_classup_after_status_offset/after_hp
@onready var after_mp_label: Label = $Status/unit_classup_after_status_offset/after_mp
@onready var after_atk_label: Label = $Status/unit_classup_after_status_offset/after_atk
@onready var after_def_label: Label = $Status/unit_classup_after_status_offset/after_def
@onready var after_mag_label: Label = $Status/unit_classup_after_status_offset/after_mag
@onready var after_spr_label: Label = $Status/unit_classup_after_status_offset/after_spr
@onready var material_nodes: Array[Control] = [
	$Material1,
	$Material2,
	$Material3,
	$Material4,
	$Material5,
]

var base_unit_instance_id: String = ""
var base_unit_inst: Dictionary = {}

var _texture_cache: Dictionary = {}

func init_scene(params: Dictionary) -> void:
	if params.has("base_unit_instance_id"):
		base_unit_instance_id = str(params.get("base_unit_instance_id", ""))
	if params.has("base_unit_inst") and params.get("base_unit_inst") is Dictionary:
		base_unit_inst = (params.get("base_unit_inst", {}) as Dictionary).duplicate(true)
	call_deferred("_refresh_before_visual")

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	if awaken_button != null:
		awaken_button.pressed.connect(_on_awaken_pressed)
	if enhance_button != null:
		enhance_button.pressed.connect(_on_enhance_pressed)

func _refresh_before_visual() -> void:
	var unit_tex: Texture2D = _get_unit_texture(base_unit_inst)
	var rarity: int = int(base_unit_inst.get("current_rarity", base_unit_inst.get("rarity", 1)))
	var next_rarity: int = min(rarity + 1, 7)
	var next_unit_tex: Texture2D = _get_unit_texture_for_rarity(base_unit_inst, next_rarity)
	if next_unit_tex == null:
		next_unit_tex = unit_tex

	if before_unit != null:
		before_unit.texture = unit_tex
	if before_stand != null:
		var ped: Texture2D = _get_pedestal_texture(rarity)
		if ped != null:
			before_stand.texture = ped

	if after_unit != null:
		after_unit.texture = next_unit_tex
	if after_stand != null:
		var next_ped: Texture2D = _get_pedestal_texture(next_rarity)
		if next_ped != null:
			after_stand.texture = next_ped

	_populate_awakening_requirements()
	_populate_before_stats()
	_populate_after_stats()
	_refresh_button_state()

func _populate_before_stats() -> void:
	if base_unit_inst.is_empty():
		return
	var level: int = int(base_unit_inst.get("level", 1))
	var rarity: int = int(base_unit_inst.get("current_rarity", base_unit_inst.get("rarity", 1)))
	var max_level: int = int(StatCalculator.RARITY_MAX_LEVELS.get(rarity, 15))

	var final_profile: Dictionary = StatCalculator.calculate_final_stats(base_unit_inst)
	var stats_var: Variant = final_profile.get("stats", {})
	var stats: Dictionary = stats_var as Dictionary if stats_var is Dictionary else {}

	if before_lv_label != null:
		before_lv_label.text = "%d/%d" % [level, max_level]
	if before_hp_label != null:
		before_hp_label.text = str(int(stats.get("HP", 0)))
	if before_mp_label != null:
		before_mp_label.text = str(int(stats.get("MP", 0)))
	if before_atk_label != null:
		before_atk_label.text = str(int(stats.get("ATK", 0)))
	if before_def_label != null:
		before_def_label.text = str(int(stats.get("DEF", 0)))
	if before_mag_label != null:
		before_mag_label.text = str(int(stats.get("MAG", 0)))
	if before_spr_label != null:
		before_spr_label.text = str(int(stats.get("SPR", 0)))

func _get_current_entry() -> Dictionary:
	var rarity: int = int(base_unit_inst.get("current_rarity", base_unit_inst.get("rarity", 1)))
	return _get_entry_for_rarity(rarity)

func _get_entry_for_rarity(rarity: int) -> Dictionary:
	if base_unit_inst.is_empty():
		return {}
	var unit_id: String = str(base_unit_inst.get("unit_id", ""))
	if unit_id == "":
		return {}
	var unit_data: Dictionary = StaticData.game_data_units.get(unit_id, {})
	var entries: Variant = unit_data.get("entries", {})
	if not (entries is Dictionary):
		return {}
	for key in (entries as Dictionary).keys():
		var entry: Variant = (entries as Dictionary)[key]
		if entry is Dictionary and int((entry as Dictionary).get("rarity", -1)) == rarity:
			return entry as Dictionary
	return {}

func _populate_after_stats() -> void:
	if base_unit_inst.is_empty():
		return
	var rarity: int = int(base_unit_inst.get("current_rarity", base_unit_inst.get("rarity", 1)))
	var next_rarity: int = rarity + 1
	if not StatCalculator.RARITY_MAX_LEVELS.has(next_rarity):
		if after_status_offset != null:
			after_status_offset.visible = false
		return
	if after_status_offset != null:
		after_status_offset.visible = true

	var next_entry: Dictionary = _get_entry_for_rarity(next_rarity)
	if next_entry.is_empty():
		if after_status_offset != null:
			after_status_offset.visible = false
		return

	var hypothetical: Dictionary = base_unit_inst.duplicate(true)
	hypothetical.merge(next_entry, true)
	hypothetical["current_rarity"] = next_rarity

	var level: int = int(base_unit_inst.get("level", 1))
	var max_level: int = int(StatCalculator.RARITY_MAX_LEVELS.get(next_rarity, 15))

	var final_profile: Dictionary = StatCalculator.calculate_final_stats(hypothetical)
	var stats_var: Variant = final_profile.get("stats", {})
	var stats: Dictionary = stats_var as Dictionary if stats_var is Dictionary else {}

	if after_lv_label != null:
		after_lv_label.text = "%d/%d" % [level, max_level]
	if after_hp_label != null:
		after_hp_label.text = str(int(stats.get("HP", 0)))
	if after_mp_label != null:
		after_mp_label.text = str(int(stats.get("MP", 0)))
	if after_atk_label != null:
		after_atk_label.text = str(int(stats.get("ATK", 0)))
	if after_def_label != null:
		after_def_label.text = str(int(stats.get("DEF", 0)))
	if after_mag_label != null:
		after_mag_label.text = str(int(stats.get("MAG", 0)))
	if after_spr_label != null:
		after_spr_label.text = str(int(stats.get("SPR", 0)))

func _populate_awakening_requirements() -> void:
	var entry: Dictionary = _get_current_entry()
	var awakening_data: Variant = entry.get("awakening", null)
	var awakening: Dictionary = awakening_data as Dictionary if awakening_data is Dictionary else {}

	if gil_label != null:
		gil_label.text = str(int(awakening.get("gil", 0)))

	var materials_var: Variant = awakening.get("materials", {})
	var materials: Dictionary = materials_var as Dictionary if materials_var is Dictionary else {}
	var material_ids: Array = materials.keys()

	var stackables_var: Variant = InventoryService.owned_items.get("stackables", {})
	var stackables: Dictionary = stackables_var as Dictionary if stackables_var is Dictionary else {}

	for i in range(material_nodes.size()):
		var slot: Control = material_nodes[i]
		if slot == null:
			continue
		if i >= material_ids.size():
			slot.visible = false
			continue
		var item_id: String = str(material_ids[i])
		var count: int = int(materials[material_ids[i]])
		var item_data: Dictionary = GameDatabase.get_item(item_id)

		var icon_node: TextureRect = slot.get_node_or_null("unit_classup_item_icon") as TextureRect
		if icon_node != null:
			var icon_name: String = str(item_data.get("icon", ""))
			var tex: Texture2D = null
			if icon_name != "":
				tex = _load_cached_texture("res://assets/items/" + icon_name)
			icon_node.texture = tex

		var num_node: Label = slot.get_node_or_null("unit_classup_item_num") as Label
		if num_node != null:
			num_node.text = "x " + str(count)

		var name_node: Label = slot.get_node_or_null("unit_classup_item_name") as Label
		if name_node != null:
			name_node.text = str(item_data.get("name", item_id))

		var have_node: Label = slot.get_node_or_null("unit_classup_item_have") as Label
		if have_node != null:
			var owned_count: int = int(stackables.get(item_id, 0))
			have_node.text = str(owned_count)
			if owned_count < count:
				have_node.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
			else:
				have_node.remove_theme_color_override("font_color")

		slot.visible = true

func _get_unit_texture(unit_inst: Dictionary) -> Texture2D:
	if unit_inst.is_empty():
		return null
	var entry_id: String = UnitService.get_entry_id(unit_inst)
	if entry_id == "":
		return null
	var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % entry_id
	return _load_cached_texture(img_path)

func _get_unit_texture_for_rarity(unit_inst: Dictionary, rarity: int) -> Texture2D:
	if unit_inst.is_empty():
		return null
	var unit_id: String = str(unit_inst.get("unit_id", ""))
	if unit_id == "":
		return null
	var unit_data: Dictionary = StaticData.game_data_units.get(unit_id, {})
	var entries: Variant = unit_data.get("entries", {})
	if entries is Dictionary:
		for key in (entries as Dictionary).keys():
			var entry: Variant = (entries as Dictionary)[key]
			if entry is Dictionary and int((entry as Dictionary).get("rarity", -1)) == rarity:
				var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % str(key)
				return _load_cached_texture(img_path)
	return null

func _get_pedestal_texture(rarity: int) -> Texture2D:
	var candidate_paths: Array[String] = [
		"res://assets/ui/unit/unit_charastand_rare%s_small.tres" % rarity,
		"res://assets/ui/unit/unit_charastand_small.tres",
	]
	for path in candidate_paths:
		var tex: Texture2D = _load_cached_texture(path)
		if tex != null:
			return tex
	return null

func _load_cached_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not ResourceLoader.exists(path):
		_texture_cache[path] = null
		return null
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _refresh_button_state() -> void:
	if base_unit_instance_id == "":
		return
	var status: Dictionary = UnitService.can_awaken_unit(base_unit_instance_id)
	var can_awaken: bool = bool(status.get("can_awaken", false))
	var reason: String = str(status.get("reason", ""))

	if awaken_button != null:
		awaken_button.visible = true
		awaken_button.disabled = not can_awaken
	if result_text_label != null:
		if can_awaken:
			result_text_label.visible = false
		else:
			result_text_label.text = reason
			result_text_label.visible = reason != ""

func _on_awaken_pressed() -> void:
	if base_unit_instance_id == "":
		return
	var response: Dictionary = UnitService.awaken_unit(base_unit_instance_id)
	if bool(response.get("success", false)):
		var new_rarity: int = int(base_unit_inst.get("current_rarity", base_unit_inst.get("rarity", 1))) + 1
		base_unit_inst["current_rarity"] = new_rarity
		_refresh_before_visual()
		_show_result_popup("Awakening successful!")
	else:
		_show_result_popup(str(response.get("error", "Awakening failed")))

func _on_enhance_pressed() -> void:
	if base_unit_instance_id == "":
		return
	UIManager.pop()
	UIManager.push("enhance_ui", {
		"base_unit_instance_id": base_unit_instance_id,
		"base_unit_inst": base_unit_inst,
	})

func _show_result_popup(message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Awakening Result"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)

func _on_back_pressed() -> void:
	UIManager.pop()
	var new_top: Node = UIManager.get_current_scene()
	if new_top and new_top.has_method("_on_awaken_units"):
		new_top.call_deferred("_on_awaken_units")
